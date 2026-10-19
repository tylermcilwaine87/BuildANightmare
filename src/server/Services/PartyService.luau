--[[
	PartyService  (ModuleScript)
	Location: ServerScriptService/Server/Services/PartyService

	PARTIES (Phase 6): up to Config.Party.MaxSize players who fight bosses together.
	Parties live in memory only (they end when the server does).

	  Invite   -> pop-up for the target (expires after InviteTimeout) -> Accept / Decline
	             Accepting creates the party (inviter = leader) if there isn't one yet,
	             and leaves any party the target was already in.
	  Leave    -> if the leader leaves, the next member becomes leader; a party of one
	             is disbanded
	  Kick     -> leader only
	  Leaving the game = Leave.

	Co-op boss fights: BossService asks :GetParty(player). Only the leader can start a
	fight; every available member is brought in.

	Remote PartyRequest (RemoteFunction): "Invite", userId | "Respond", inviteId, accept |
	  "Leave" | "Kick", userId
	Remote PartyEvent (server -> client): "Incoming" | "State" | "Result"
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local PartyService = {}
local PARTY = Config.Party

local playerParty: { [Player]: any } = {}
local invites = {} -- [inviteId] = { From, To, Expires }
local lastInvite: { [Player]: number } = {}

function PartyService:Init(services)
	self.Services = services
	self.PartyEvent = Net.Get("PartyEvent")
end

-- The player's party ({ Leader, Members }) or nil.
function PartyService:GetParty(player: Player)
	return playerParty[player]
end

function PartyService:IsLeader(player: Player): boolean
	local party = playerParty[player]
	return party ~= nil and party.Leader == player
end

-- Sends every member (and anyone just removed) the current party.
function PartyService:Broadcast(party, removed: Player?)
	local members = {}
	for _, member in party.Members do
		table.insert(members, { UserId = member.UserId, Name = member.DisplayName })
	end
	local state = { LeaderUserId = party.Leader and party.Leader.UserId or 0, Members = members, MaxSize = PARTY.MaxSize }
	for _, member in party.Members do
		if member.Parent then
			self.PartyEvent:FireClient(member, "State", state)
		end
	end
	if removed and removed.Parent then
		self.PartyEvent:FireClient(removed, "State", { Members = {}, MaxSize = PARTY.MaxSize })
	end
end

local function notify(self, player: Player, text: string)
	if player.Parent then
		self.PartyEvent:FireClient(player, "Result", { Text = text })
	end
end

function PartyService:Remove(player: Player, reason: string?)
	local party = playerParty[player]
	if not party then
		return
	end
	playerParty[player] = nil
	local index = table.find(party.Members, player)
	if index then
		table.remove(party.Members, index)
	end
	if #party.Members <= 1 then
		-- Disband: the last member is on their own again.
		for _, member in party.Members do
			playerParty[member] = nil
			notify(self, member, "Your party was disbanded.")
			self.PartyEvent:FireClient(member, "State", { Members = {}, MaxSize = PARTY.MaxSize })
		end
		party.Members = {}
		if player.Parent then
			self.PartyEvent:FireClient(player, "State", { Members = {}, MaxSize = PARTY.MaxSize })
		end
		return
	end
	if party.Leader == player then
		party.Leader = party.Members[1]
		notify(self, party.Leader, "You're the party leader now.")
	end
	for _, member in party.Members do
		notify(self, member, ("%s %s the party."):format(player.DisplayName, reason or "left"))
	end
	self:Broadcast(party, player)
end

function PartyService:Invite(from: Player, userId)
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not target or target == from then
		return { Ok = false, Error = "That player isn't here." }
	end
	if os.clock() - (lastInvite[from] or 0) < PARTY.InviteCooldown then
		return { Ok = false, Error = "Wait a moment before inviting again." }
	end
	local party = playerParty[from]
	if party and party.Leader ~= from then
		return { Ok = false, Error = "Only the party leader can invite." }
	end
	if party and #party.Members >= PARTY.MaxSize then
		return { Ok = false, Error = ("Your party is full (%d players)."):format(PARTY.MaxSize) }
	end
	if party and playerParty[target] == party then
		return { Ok = false, Error = target.DisplayName .. " is already in your party." }
	end
	lastInvite[from] = os.clock()
	for id, invite in invites do -- one open invite per pair
		if invite.From == from and invite.To == target then
			invites[id] = nil
		end
	end
	local id = HttpService:GenerateGUID(false)
	invites[id] = { From = from, To = target, Expires = os.clock() + PARTY.InviteTimeout }
	self.PartyEvent:FireClient(target, "Incoming", { InviteId = id, FromName = from.DisplayName, Timeout = PARTY.InviteTimeout })
	task.delay(PARTY.InviteTimeout, function()
		if invites[id] then
			invites[id] = nil
			notify(self, from, target.DisplayName .. " didn't answer your party invite.")
		end
	end)
	return { Ok = true }
end

function PartyService:Respond(player: Player, inviteId, accept)
	local invite = type(inviteId) == "string" and invites[inviteId]
	if not invite or invite.To ~= player then
		return { Ok = false, Error = "That invite has expired." }
	end
	invites[inviteId] = nil
	local from = invite.From
	if not accept then
		notify(self, from, player.DisplayName .. " declined your party invite.")
		return { Ok = true }
	end
	if not from.Parent then
		return { Ok = false, Error = "They left." }
	end
	if self.Services.BossService:GetEncounter(player) or self.Services.BossService:GetEncounter(from) then
		return { Ok = false, Error = "Can't join a party during a boss fight." }
	end

	local party = playerParty[from]
	if party and party.Leader ~= from then
		return { Ok = false, Error = from.DisplayName .. " is no longer the party leader." }
	end
	if party and #party.Members >= PARTY.MaxSize then
		return { Ok = false, Error = "That party is full." }
	end
	if playerParty[player] then
		self:Remove(player) -- leave your old party first
	end
	if not party then
		party = { Id = HttpService:GenerateGUID(false), Leader = from, Members = { from } }
		playerParty[from] = party
	end
	table.insert(party.Members, player)
	playerParty[player] = party
	for _, member in party.Members do
		if member ~= player then
			notify(self, member, player.DisplayName .. " joined the party!")
		end
	end
	self:Broadcast(party)
	return { Ok = true }
end

function PartyService:Kick(leader: Player, userId)
	local party = playerParty[leader]
	local target = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	if not party or party.Leader ~= leader then
		return { Ok = false, Error = "Only the party leader can kick." }
	end
	if not target or target == leader or playerParty[target] ~= party then
		return { Ok = false, Error = "They're not in your party." }
	end
	if self.Services.BossService:GetEncounter(leader) then
		return { Ok = false, Error = "Can't kick during a boss fight." }
	end
	notify(self, target, "You were removed from the party.")
	self:Remove(target, "was removed from")
	return { Ok = true }
end

function PartyService:Start()
	Net.Get("PartyRequest").OnServerInvoke = function(player, action, arg, arg2)
		if not self.Services.AntiExploitService:Allow(player, "PartyRequest") then
			return { Ok = false, Error = "Slow down a little!" }
		end
		if action == "Invite" then
			return self:Invite(player, arg)
		elseif action == "Respond" then
			return self:Respond(player, arg, arg2 == true)
		elseif action == "Leave" then
			if not playerParty[player] then
				return { Ok = false, Error = "You're not in a party." }
			end
			self:Remove(player)
			return { Ok = true }
		elseif action == "Kick" then
			return self:Kick(player, arg)
		end
		return { Ok = false, Error = "Unknown request." }
	end

	Players.PlayerRemoving:Connect(function(player)
		self:Remove(player)
		lastInvite[player] = nil
		for id, invite in invites do
			if invite.From == player or invite.To == player then
				invites[id] = nil
			end
		end
	end)
end

return PartyService
