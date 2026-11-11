--[[
	DuelService  (ModuleScript)
	Location: ServerScriptService/Server/Services/DuelService

	THE NIGHTMARE COLOSSEUM: optional 1v1 Nightmare Duels (Best of 1 or Best of 3).
	PvP is never required; players can turn duel requests off entirely.

	FLOW
	  Challenge  -> request popup for the target (expires in 20s) -> Accept / Decline
	  Match      -> private arena slot, both Handlers + Nightmares teleported in
	  Each round:
	    PREP (12s)       pick any saved build that is PvP-legal (Power <= 100, 1 Legendary)
	    COUNTDOWN (3s)   everyone frozen at balanced spawns; HP, stamina, cooldowns,
	                     possession & ultimate meters all reset (fresh Nightmare)
	    LIVE (3:00)      a round is LOST when:
	                       * your NIGHTMARE is defeated, or
	                       * your HANDLER is knocked out a 2nd time (the 1st KO gives a
	                         short protected respawn; your Nightmare keeps fighting)
	    SUDDEN DEATH     30s, the safe zone shrinks; outside it you take damage. If still
	                     unresolved: higher remaining health wins (Nightmare HP 70%,
	                     Handler HP 30%, -30% per Handler KO). Hiding never wins.
	  Match end  -> results + rewards (Arena Tokens, XP, coins) EXACTLY ONCE, saved,
	               everyone returned to the Forge with their normal active Nightmare.
	  Leaving / disconnecting = forfeit.

	NIGHTMARE UNDERGROUND (StartMatch opts.Mode = "Underground", UndergroundService): the same
	match flow with its own ring, timings (Config.Underground) and rules: the Handlers watch
	from their corner booths, each player drives their Nightmare for the whole round, only
	the Nightmares can hurt each other, a round ends on a KNOCKOUT or a points DECISION at the
	bell (no sudden death), and the result goes on the profile's Underground record.

	PVP RULES live in CombatService (opponent check, Nightmare->Handler x0.45 damage,
	Ultimate cap 45% of max HP per cast) and here (Handler KOs never actually kill).
	Remote DuelRequest (RemoteFunction): "Challenge", userId, bestOf | "Respond", id, bool |
	  "SetAllow", bool | "SelectBuild", index | "Forfeit"
	Remote DuelEvent (server -> client): "Incoming" | "RequestResult" | "State" | "Banner" | "MatchEnd" | "Queue"
	RANKED (Phase 6): DuelRequest "QueueRanked" / "LeaveQueue" -> RankedService, which pairs
	players and calls StartMatch(a, b, 3, { Ranked = true }); EndMatch asks RankedService
	to apply the rating change once.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local BuildValidator = require(Shared:WaitForChild("BuildValidator"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local RankDefinitions = require(Shared:WaitForChild("RankDefinitions"))

local DuelService = {}

local PVP = Config.PvP
local requests = {} -- [id] = { Id, From, To, BestOf, Expires }
local lastChallenge: { [Player]: number } = {}
local matches = {} -- [id] = match
local playerMatch: { [Player]: any } = {}
local arenas = {} -- [slot] = arena
local slotInUse = {}
local rewardLog: { [Player]: { number } } = {}

------------------------------------------------------------------------------------------
-- Arena (placeholder geometry, built once per slot)
------------------------------------------------------------------------------------------
local function buildArena(slot: number)
	local center = PVP.ArenaOrigin + Vector3.new((slot - 1) * PVP.ArenaSpacing, 0, 0)
	local root = Workspace:FindFirstChild("DuelArenas")
	if not root then
		root = Instance.new("Folder")
		root.Name = "DuelArenas"
		root.Parent = Workspace
	end
	local folder = Instance.new("Folder")
	folder.Name = "Colosseum" .. slot
	folder.Parent = root

	local function part(name, size, cframe, color, material, shape)
		local p = Instance.new("Part")
		p.Name = name
		if shape then
			p.Shape = shape
		end
		p.Size = size
		p.CFrame = cframe
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end

	local radius = PVP.ArenaRadius
	local groundY = center.Y + 0.5
	part("Floor", Vector3.new(1, radius * 2 + 8, radius * 2 + 8), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(45, 38, 55), Enum.Material.Slate, Enum.PartType.Cylinder)
	part("Ring", Vector3.new(0.2, 24, 24), CFrame.new(center.X, groundY + 0.05, center.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 90, 255), Enum.Material.Neon, Enum.PartType.Cylinder).CanCollide = false

	-- Wall ring
	local segments = 28
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local position = center + Vector3.new(math.cos(angle) * (radius + 2), 6, math.sin(angle) * (radius + 2))
		local wall = part("Wall", Vector3.new(2, 12, (2 * math.pi * (radius + 2)) / segments + 0.5), CFrame.lookAt(position, Vector3.new(center.X, position.Y, center.Z)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(70, 55, 85), Enum.Material.Brick)
		wall.CFrame = CFrame.new(position) * CFrame.Angles(0, -angle, 0)
	end

	-- Cover pillars (symmetric so neither side has an advantage)
	for _, offset in { Vector3.new(14, 0, 8), Vector3.new(-14, 0, 8), Vector3.new(14, 0, -8), Vector3.new(-14, 0, -8) } do
		part("Pillar", Vector3.new(4, 10, 4), CFrame.new(center + offset + Vector3.new(0, 5.5, 0)), Color3.fromRGB(90, 80, 105), Enum.Material.Marble)
	end

	local spawnA = CFrame.lookAt(Vector3.new(center.X, groundY + 3, center.Z + 32), Vector3.new(center.X, groundY + 3, center.Z))
	local spawnB = CFrame.lookAt(Vector3.new(center.X, groundY + 3, center.Z - 32), Vector3.new(center.X, groundY + 3, center.Z))
	part("PadA", Vector3.new(0.3, 8, 8), CFrame.new(spawnA.Position.X, groundY + 0.1, spawnA.Position.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 140, 255), Enum.Material.Neon, Enum.PartType.Cylinder).CanCollide = false
	part("PadB", Vector3.new(0.3, 8, 8), CFrame.new(spawnB.Position.X, groundY + 0.1, spawnB.Position.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 80, 80), Enum.Material.Neon, Enum.PartType.Cylinder).CanCollide = false

	local light = Instance.new("PointLight")
	light.Range = 60
	light.Brightness = 1.5
	light.Color = Color3.fromRGB(200, 170, 255)
	light.Parent = part("Light", Vector3.new(2, 2, 2), CFrame.new(center + Vector3.new(0, 30, 0)), Color3.fromRGB(200, 170, 255), Enum.Material.Neon, Enum.PartType.Ball)

	return { Folder = folder, Center = Vector3.new(center.X, groundY, center.Z), Spawns = { spawnA, spawnB } }
end

local function reserveArena()
	for slot = 1, PVP.MaxArenas do
		if not slotInUse[slot] then
			slotInUse[slot] = true
			arenas[slot] = arenas[slot] or buildArena(slot)
			return slot, arenas[slot]
		end
	end
	return nil
end

------------------------------------------------------------------------------------------
-- Queries used by other services
------------------------------------------------------------------------------------------
local LIVE_STATES = { Live = true, SuddenDeath = true }
local FROZEN_STATES = { Prep = true, Countdown = true, RoundOver = true, Ended = true }

function DuelService:GetMatch(player: Player?)
	return player and playerMatch[player] or nil
end

function DuelService:IsInMatch(player: Player?): boolean
	return player ~= nil and playerMatch[player] ~= nil
end

-- Frozen between rounds, and for the rest of a round once you're OUT (team duels).
function DuelService:IsFrozen(player: Player?): boolean
	local match = player and playerMatch[player]
	return match ~= nil and (FROZEN_STATES[match.State] == true or match.Out[player] == true)
end

-- Enemies in the same live round, on different sides, neither of them out.
function DuelService:AreOpponents(a: Player?, b: Player?): boolean
	if not a or not b or a == b then
		return false
	end
	local match = playerMatch[a]
	return match ~= nil
		and match == playerMatch[b]
		and LIVE_STATES[match.State] == true
		and match.Side[a] ~= match.Side[b]
		and not match.Out[a]
		and not match.Out[b]
end

-- The first player on the other team (1v1: THE opponent).
function DuelService:GetOpponent(player: Player): Player?
	local match = playerMatch[player]
	if not match then
		return nil
	end
	local enemies = match.Teams[3 - match.Side[player]]
	return enemies and enemies[1]
end

-- Every enemy Handler + Nightmare that can be fought right now (Underground: the Nightmare).
function DuelService:GetOpponentModels(player: Player): { Model }
	local list = {}
	local match = playerMatch[player]
	if not match then
		return list
	end
	for _, enemy in match.Teams[3 - match.Side[player]] do
		if self:AreOpponents(player, enemy) then
			if enemy.Character and match.Mode ~= "Underground" then
				table.insert(list, enemy.Character)
			end
			local nightmare = self.Services.NightmareSpawnService:GetNightmare(enemy)
			if nightmare then
				table.insert(list, nightmare)
			end
		end
	end
	return list
end

function DuelService:IsOpponentModel(player: Player, model: Model): boolean
	local owner = self.Services.CombatService:GetOwnerPlayer(model)
	return owner ~= nil and self:AreOpponents(player, owner)
end

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local function legalBuilds(self, player: Player): { number }
	local profile = self.Services.PlayerDataService:Get(player)
	local list = {}
	if not profile then
		return list
	end
	for index, build in profile.Builds do
		if BuildValidator.Validate(build, profile.Inventory, Config.Builds.PvPPowerBudget, profile.Mutations) then
			table.insert(list, index)
		end
	end
	return list
end

local function buildSummaries(self, player: Player)
	local profile = self.Services.PlayerDataService:Get(player)
	local list = {}
	for index, build in profile.Builds do
		local ok, err = BuildValidator.Validate(build, profile.Inventory, Config.Builds.PvPPowerBudget, profile.Mutations)
		local stats, archetype = StatCalculator.Compute(build)
		table.insert(list, { Index = index, Name = build.Name, Power = stats.PowerCost, Archetype = archetype, Legal = ok == true, Reason = err })
	end
	return list
end

local function isBusy(self, player: Player): (boolean, string?)
	if playerMatch[player] then
		return true, "already in a duel"
	end
	if self.Services.BossService:GetEncounter(player) then
		return true, "in a boss fight"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return true, "not ready"
	end
	return false, nil
end

-- Public versions for RankedService.
function DuelService:IsBusy(player: Player): (boolean, string?)
	return isBusy(self, player)
end

function DuelService:HasLegalBuild(player: Player): boolean
	return #legalBuilds(self, player) > 0
end

local function setDuelAttributes(self, match, player: Player, enabled: boolean)
	local side = match.Side[player]
	local out = enabled and match.Out[player] == true or nil -- out for this round (team duels)
	local function mark(model: Model?)
		if model then
			model:SetAttribute("DuelId", enabled and match.Id or nil)
			model:SetAttribute("DuelSide", enabled and side or nil)
			model:SetAttribute("DuelOut", out)
		end
	end
	mark(player.Character)
	mark(self.Services.NightmareSpawnService:GetNightmare(player))
end

function DuelService:Broadcast(match, kind: string, data)
	for _, player in match.Players do
		if player.Parent then
			self.DuelEvent:FireClient(player, kind, data)
		end
	end
end

-- Full state snapshot for the match HUD (sent on every change).
-- { { Name, Out, KOs } } for one side (team duel scoreboard).
local function roster(match, side: number)
	local list = {}
	for _, member in match.Teams[side] do
		table.insert(list, { Name = member.DisplayName, Out = match.Out[member] == true, KOs = match.KOs[member] or 0 })
	end
	return list
end

function DuelService:SendState(match)
	for _, player in match.Players do
		if player.Parent then
			local side = match.Side[player]
			local other = 3 - side
			local opponent = match.Teams[other][1]
			self.DuelEvent:FireClient(player, "State", {
				MatchId = match.Id,
				Mode = match.Mode,
				MyName = player.DisplayName,
				State = match.State,
				Round = match.Round,
				BestOf = match.BestOf,
				MyScore = match.Score[side],
				OpponentScore = match.Score[other],
				MyKOs = match.KOs[player],
				OpponentKOs = match.KOs[opponent],
				OpponentName = match.TeamNames[other],
				OpponentUserId = opponent.UserId,
				TeamSize = match.TeamSize,
				Allies = roster(match, side),
				Enemies = roster(match, other),
				AmOut = match.Out[player] == true,
				Ranked = match.Ranked,
				PhaseEndsAt = match.PhaseEndsAt, -- Workspace:GetServerTimeNow() based
				ZoneCenter = match.Arena.Center,
				ZoneStartRadius = PVP.SuddenDeathStartRadius,
				ZoneEndRadius = PVP.SuddenDeathEndRadius,
				SuddenDeathStart = match.SuddenDeathStart,
				SuddenDeathEnd = match.SuddenDeathEnd,
				Builds = match.State == "Prep" and buildSummaries(self, player) or nil,
				Choice = match.BuildChoice[player],
			})
		end
	end
end

local function serverNow()
	return Workspace:GetServerTimeNow()
end

------------------------------------------------------------------------------------------
-- Requests
------------------------------------------------------------------------------------------
-- Checks both parties for a team duel. Returns myParty, theirParty or nil, error.
function DuelService:CheckTeams(from: Player, target: Player)
	local partyService = self.Services.PartyService
	local myParty = partyService:GetParty(from)
	if not myParty or myParty.Leader ~= from then
		return nil, nil, "Only a party leader can start a team duel (form a party with L)."
	end
	local size = #myParty.Members
	if size < PVP.MinTeamSize or size > PVP.MaxTeamSize then
		return nil, nil, ("Team duels need a party of %d to %d players."):format(PVP.MinTeamSize, PVP.MaxTeamSize)
	end
	local theirParty = partyService:GetParty(target)
	if not theirParty or theirParty == myParty or theirParty.Leader ~= target then
		return nil, nil, target.DisplayName .. " isn't leading another party."
	end
	if #theirParty.Members ~= size then
		return nil, nil, ("Both parties need %d players (theirs has %d)."):format(size, #theirParty.Members)
	end
	for _, member in table.move(theirParty.Members, 1, #theirParty.Members, #myParty.Members + 1, table.clone(myParty.Members)) do
		local busy, why = isBusy(self, member)
		if busy then
			return nil, nil, member.DisplayName .. " is " .. why .. "."
		end
		if #legalBuilds(self, member) == 0 then
			return nil, nil, member.DisplayName .. " has no PvP-legal Nightmare."
		end
	end
	return myParty, theirParty, nil
end

-- team = true: party vs party (2v2 / 3v3), always Best of PVP.TeamBestOf.
function DuelService:Challenge(from: Player, targetUserId, bestOf, team)
	if team == true then
		bestOf = PVP.TeamBestOf
	end
	if type(targetUserId) ~= "number" or not table.find(PVP.BestOfOptions, bestOf) then
		return { Ok = false, Error = "Invalid challenge." }
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == from then
		return { Ok = false, Error = "That player isn't here." }
	end
	if team == true then
		if os.clock() - (lastChallenge[from] or 0) < PVP.RequestCooldown then
			return { Ok = false, Error = "Wait a moment before challenging again." }
		end
		local targetProfile = self.Services.PlayerDataService:Get(target)
		if not targetProfile or (targetProfile.Settings and targetProfile.Settings.AllowDuels == false) then
			return { Ok = false, Error = target.DisplayName .. " isn't accepting duel requests." }
		end
		local myParty, _, err = self:CheckTeams(from, target)
		if not myParty then
			return { Ok = false, Error = err }
		end
		lastChallenge[from] = os.clock()
		local id = HttpService:GenerateGUID(false)
		requests[id] = { Id = id, From = from, To = target, BestOf = bestOf, Team = true, Expires = os.clock() + PVP.RequestTimeout }
		self.DuelEvent:FireClient(target, "Incoming", { RequestId = id, FromName = from.DisplayName, FromUserId = from.UserId, BestOf = bestOf, TeamSize = #myParty.Members, Timeout = PVP.RequestTimeout })
		task.delay(PVP.RequestTimeout, function()
			if requests[id] then
				requests[id] = nil
				if from.Parent then
					self.DuelEvent:FireClient(from, "RequestResult", { Text = target.DisplayName .. " didn't respond." })
				end
			end
		end)
		return { Ok = true }
	end
	if os.clock() - (lastChallenge[from] or 0) < PVP.RequestCooldown then
		return { Ok = false, Error = "Wait a moment before challenging again." }
	end
	local busy, why = isBusy(self, from)
	if busy then
		return { Ok = false, Error = "You're " .. why .. "." }
	end
	busy, why = isBusy(self, target)
	if busy then
		return { Ok = false, Error = target.DisplayName .. " is " .. why .. "." }
	end
	local targetProfile = self.Services.PlayerDataService:Get(target)
	if not targetProfile or (targetProfile.Settings and targetProfile.Settings.AllowDuels == false) then
		return { Ok = false, Error = target.DisplayName .. " isn't accepting duel requests." }
	end
	if #legalBuilds(self, from) == 0 then
		return { Ok = false, Error = "None of your saved builds fit the PvP Power budget (100)." }
	end
	if #legalBuilds(self, target) == 0 then
		return { Ok = false, Error = target.DisplayName .. " has no PvP-legal Nightmare yet." }
	end

	lastChallenge[from] = os.clock()
	-- One pending request per pair.
	for id, request in requests do
		if request.From == from and request.To == target then
			requests[id] = nil
		end
	end
	local id = HttpService:GenerateGUID(false)
	requests[id] = { Id = id, From = from, To = target, BestOf = bestOf, Expires = os.clock() + PVP.RequestTimeout }
	self.DuelEvent:FireClient(target, "Incoming", { RequestId = id, FromName = from.DisplayName, FromUserId = from.UserId, BestOf = bestOf, Timeout = PVP.RequestTimeout })
	task.delay(PVP.RequestTimeout, function()
		if requests[id] then
			requests[id] = nil
			if from.Parent then
				self.DuelEvent:FireClient(from, "RequestResult", { Text = target.DisplayName .. " didn't respond." })
			end
		end
	end)
	return { Ok = true }
end

function DuelService:Respond(player: Player, requestId, accept)
	local request = type(requestId) == "string" and requests[requestId]
	if not request or request.To ~= player then
		return { Ok = false, Error = "That request has expired." }
	end
	requests[requestId] = nil
	local from = request.From
	if not accept then
		if from.Parent then
			self.DuelEvent:FireClient(from, "RequestResult", { Text = player.DisplayName .. " declined your duel." })
		end
		return { Ok = true }
	end
	if not from.Parent then
		return { Ok = false, Error = "They left." }
	end
	if request.Team then
		-- Re-check: parties can change while the request is open.
		local theirParty, myParty, err = self:CheckTeams(from, player)
		if not theirParty then
			return { Ok = false, Error = err }
		end
		return self:StartMatch(table.clone(theirParty.Members), table.clone(myParty.Members), request.BestOf)
	end
	for _, p in { from, player } do
		local busy, why = isBusy(self, p)
		if busy then
			return { Ok = false, Error = p.DisplayName .. " is " .. why .. "." }
		end
		if #legalBuilds(self, p) == 0 then
			return { Ok = false, Error = p.DisplayName .. " has no build within the PvP Power budget (100)." }
		end
	end
	return self:StartMatch(from, player, request.BestOf)
end

------------------------------------------------------------------------------------------
-- Match lifecycle
------------------------------------------------------------------------------------------
-- a / b: a Player (1v1) or a list of Players (a team: 2v2 / 3v3).
-- opts.Ranked = true: a ranked match (RankedService queue); ratings change at the end.
-- opts.Mode = "Underground": NIGHTMARE UNDERGROUND (UndergroundService): 1v1, each player IS
-- their Nightmare, in an Underground ring.
function DuelService:StartMatch(a, b, bestOf: number, opts)
	local mode = opts and opts.Mode or nil
	local slot, arena
	if mode == "Underground" then
		slot, arena = self.Services.UndergroundService:ReserveArena()
	else
		slot, arena = reserveArena()
	end
	if not slot then
		return { Ok = false, Error = mode == "Underground" and "Every Underground ring is taken. Try again soon." or "All Colosseum arenas are busy. Try again soon." }
	end
	local teams = { typeof(a) == "Instance" and { a } or a, typeof(b) == "Instance" and { b } or b }
	local function teamName(team)
		return #team == 1 and team[1].DisplayName or ("Team " .. team[1].DisplayName)
	end
	local ranked = opts and opts.Ranked == true
	local match = {
		Id = HttpService:GenerateGUID(false),
		Mode = mode,
		Ranked = ranked,
		BestOf = bestOf,
		Teams = teams,
		TeamSize = #teams[1],
		TeamNames = { teamName(teams[1]), teamName(teams[2]) },
		Players = {},
		Side = {},
		Score = { [1] = 0, [2] = 0 }, -- by side
		KOs = {}, -- by player
		Out = {}, -- [player] = true: out for the rest of this round
		Left = {}, -- [player] = true: left the game mid-match (team duels play on)
		BuildChoice = {},
		Round = 0,
		State = "Prep",
		Slot = slot,
		Arena = arena,
		StartTime = os.clock(),
		Token = 0,
		Rewarded = false,
		Connections = {},
	}
	for side, team in teams do
		for _, player in team do
			table.insert(match.Players, player)
			match.Side[player] = side
			match.KOs[player] = 0
		end
	end
	matches[match.Id] = match
	for _, player in match.Players do
		playerMatch[player] = match
		local profile = self.Services.PlayerDataService:Get(player)
		local legal = legalBuilds(self, player)
		match.BuildChoice[player] = table.find(legal, profile.ActiveBuild) and profile.ActiveBuild or legal[1]
		self.Services.PossessionService:End(player, "Duel")
		-- Anyone still searching for a ranked match stops (they're in a duel now).
		self.Services.RankedService:Leave(player, nil)
		self.Services.UndergroundService:Leave(player, nil)
	end
	if mode == "Underground" then
		self:Broadcast(match, "Banner", { Title = "NIGHTMARE UNDERGROUND", Subtitle = ("%s  vs  %s  ·  Best of %d  ·  You ARE your Nightmare"):format(match.TeamNames[1], match.TeamNames[2], bestOf) })
	elseif ranked then
		local function label(player: Player)
			local record = RankDefinitions.Record(self.Services.PlayerDataService:Get(player))
			return ("%s (%s %d)"):format(player.DisplayName, RankDefinitions.TierFor(record.Rating).DisplayName, record.Rating)
		end
		self:Broadcast(match, "Banner", { Title = "RANKED DUEL", Subtitle = ("%s  vs  %s  ·  Best of %d"):format(label(teams[1][1]), label(teams[2][1]), bestOf) })
	elseif match.TeamSize > 1 then
		self:Broadcast(match, "Banner", { Title = ("%dv%d TEAM DUEL"):format(match.TeamSize, match.TeamSize), Subtitle = ("%s  vs  %s  ·  Best of %d"):format(match.TeamNames[1], match.TeamNames[2], bestOf) })
	else
		self:Broadcast(match, "Banner", { Title = "NIGHTMARE DUEL", Subtitle = ("%s  vs  %s  ·  Best of %d"):format(match.TeamNames[1], match.TeamNames[2], bestOf) })
	end
	self:BeginPrep(match)
	return { Ok = true }
end

-- Your team's pad; teammates stand side by side on it.
function DuelService:SpawnFor(match, player: Player): CFrame
	local side = match.Side[player]
	local team = match.Teams[side]
	local index = table.find(team, player) or 1
	return match.Arena.Spawns[side] * CFrame.new((index - (#team + 1) / 2) * PVP.TeamSpawnSpacing, 0, 0)
end

function DuelService:PlacePlayer(match, player: Player)
	if match.Mode == "Underground" then
		self.Services.UndergroundService:Place(match, player) -- (Handler to its booth, Nightmare to its corner)
		return
	end
	local spawnCF = self:SpawnFor(match, player)
	local character = player.Character
	if character and character.Parent then
		character:PivotTo(spawnCF)
	end
	self.Services.NightmareSpawnService:TeleportNightmare(player, spawnCF * CFrame.new(5, 0, 3))
end

function DuelService:ResetPlayer(match, player: Player)
	if match.Left[player] or not player.Parent then
		return -- left the game mid-match (team duels play on without them)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		humanoid.Health = humanoid.MaxHealth
	end
	self.Services.HandlerService:ResetForDuel(player)
	self.Services.PossessionService:ResetForDuel(player)
	-- A fresh Nightmare = full HP, cooldowns, stagger and ultimate reset.
	self.Services.NightmareSpawnService:ForceSpawn(player, match.BuildChoice[player])
	self:PlacePlayer(match, player)
	setDuelAttributes(self, match, player, true)
	if match.Mode == "Underground" then
		self.Services.UndergroundService:PrepareFighter(match, player)
	end
end

-- The timings for this match's mode (Underground has its own).
local function timing(match, key: string): number
	return match.Mode == "Underground" and Config.Underground[key] or PVP[key]
end

function DuelService:BeginPrep(match)
	match.Token += 1
	match.State = "Prep"
	local prepTime = timing(match, "PrepTime")
	match.PhaseEndsAt = serverNow() + prepTime
	match.SuddenDeathStart, match.SuddenDeathEnd = nil, nil
	for _, player in match.Players do
		self:ResetPlayer(match, player)
	end
	self:SendState(match)
	local token = match.Token
	task.delay(prepTime, function()
		if match.Token == token and match.State == "Prep" then
			self:BeginCountdown(match)
		end
	end)
end

function DuelService:SelectBuild(player: Player, index)
	local match = playerMatch[player]
	if not match or match.State ~= "Prep" then
		return { Ok = false, Error = "You can only switch builds during preparation." }
	end
	if not table.find(legalBuilds(self, player), index) then
		return { Ok = false, Error = "That build isn't PvP-legal." }
	end
	match.BuildChoice[player] = index
	self.Services.NightmareSpawnService:ForceSpawn(player, index)
	self:PlacePlayer(match, player)
	setDuelAttributes(self, match, player, true)
	if match.Mode == "Underground" then
		self.Services.UndergroundService:PrepareFighter(match, player)
	end
	self:SendState(match)
	return { Ok = true }
end

function DuelService:BeginCountdown(match)
	match.Token += 1
	match.Round += 1
	match.State = "Countdown"
	-- Fresh round: everyone back in (except players who left the game).
	match.Out = {}
	for _, player in match.Players do
		match.KOs[player] = 0
		if match.Left[player] then
			match.Out[player] = true
		end
	end
	for _, player in match.Players do
		self:ResetPlayer(match, player)
	end
	local underground = match.Mode == "Underground"
	if underground then
		-- in control of your Nightmare, frozen in your corner until FIGHT
		self.Services.UndergroundService:BeginCountdown(match)
		self:Broadcast(match, "Banner", { Title = ("ROUND %d"):format(match.Round), Subtitle = ("%s  vs  %s"):format(match.TeamNames[1], match.TeamNames[2]) })
	end
	local countdown = timing(match, "CountdownTime")
	match.PhaseEndsAt = serverNow() + countdown
	self:SendState(match)
	local token = match.Token
	task.delay(countdown, function()
		if match.Token == token and match.State == "Countdown" then
			match.State = "Live"
			match.RoundStart = os.clock()
			match.PhaseEndsAt = serverNow() + timing(match, "RoundTime")
			if underground then
				self.Services.UndergroundService:BeginLive(match)
			end
			self:SendState(match)
			self:Broadcast(match, "Banner", { Title = underground and "FIGHT!" or ("ROUND %d"):format(match.Round), Subtitle = underground and "" or "FIGHT!" })
		end
	end)
end

function DuelService:StartSuddenDeath(match)
	match.State = "SuddenDeath"
	match.SuddenDeathStart = serverNow()
	match.SuddenDeathEnd = serverNow() + PVP.SuddenDeathTime
	match.PhaseEndsAt = match.SuddenDeathEnd
	self:SendState(match)
	self:Broadcast(match, "Banner", { Title = "SUDDEN DEATH", Subtitle = "Stay inside the shrinking circle!" })
end

local function zoneRadius(match): number
	local t = math.clamp((serverNow() - match.SuddenDeathStart) / PVP.SuddenDeathTime, 0, 1)
	return PVP.SuddenDeathStartRadius + (PVP.SuddenDeathEndRadius - PVP.SuddenDeathStartRadius) * t
end

-- Health-based score used when time runs out: the average over a side (out = 0).
function DuelService:HealthScore(match, side: number): number
	local total = 0
	for _, player in match.Teams[side] do
		if not match.Out[player] then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local handlerPct = humanoid and humanoid.Health / humanoid.MaxHealth or 0
			local nightmare = self.Services.NightmareSpawnService:GetNightmare(player)
			local nmHumanoid = nightmare and nightmare:FindFirstChildOfClass("Humanoid")
			local nightmarePct = nmHumanoid and nmHumanoid.Health / nmHumanoid.MaxHealth or 0
			total += nightmarePct * 0.7 + handlerPct * 0.3 - match.KOs[player] * 0.3
		end
	end
	return total / #match.Teams[side]
end

-- winnerSide: 1 / 2, or nil for a drawn round.
function DuelService:EndRound(match, winnerSide: number?, reason: string)
	if not LIVE_STATES[match.State] then
		return
	end
	match.Token += 1
	match.State = "RoundOver"
	if winnerSide then
		match.Score[winnerSide] += 1
	end
	local underground = match.Mode == "Underground"
	if not underground then
		for _, player in match.Players do
			self.Services.PossessionService:End(player, "RoundOver")
		end
	end
	local teamMatch = match.TeamSize > 1
	local reasonText = ({
		NightmareDefeated = teamMatch and "Every enemy is out!" or "Nightmare defeated!",
		HandlerKO = teamMatch and "Every enemy is out!" or "Handler knocked out twice!",
		Left = "The other side left.",
		Time = "Time! Decided by remaining health.",
		Forfeit = "Opponent forfeited.",
	})[reason] or reason
	if underground then
		-- the bell: nobody moves, the call, the judge's card, the knockout camera, back to the
		-- corners (UndergroundService)
		self.Services.UndergroundService:EndRound(match, winnerSide, reason)
	else
		self:Broadcast(match, "Banner", { Title = winnerSide and (string.upper(match.TeamNames[winnerSide]) .. " WINS THE ROUND") or "ROUND DRAWN", Subtitle = reasonText })
	end
	self:SendState(match)

	local needed = math.ceil(match.BestOf / 2)
	local token = match.Token
	task.delay(timing(match, "BetweenRoundsTime"), function()
		if match.Token ~= token or match.State ~= "RoundOver" then
			return
		end
		if underground then
			-- (its own rule: at most BestOf rounds, then rounds won, then the scorecards)
			local over, side, why = self.Services.UndergroundService:Verdict(match)
			if over then
				self:EndMatch(match, side, why)
			else
				self:BeginPrep(match)
			end
			return
		end
		for side = 1, 2 do
			if match.Score[side] >= needed then
				self:EndMatch(match, side, "Score")
				return
			end
		end
		if match.Round >= PVP.MaxRoundsBeforeDraw then
			self:EndMatch(match, nil, "Draw")
			return
		end
		self:BeginPrep(match)
	end)
end

-- winnerSide: 1 / 2, or nil for a draw.
function DuelService:EndMatch(match, winnerSide: number?, reason: string)
	if match.State == "Ended" then
		return
	end
	match.Token += 1
	match.State = "Ended"
	local duration = os.clock() - match.StartTime

	-- Rewards: exactly once, never for instant forfeits, capped per hour.
	if not match.Rewarded then
		match.Rewarded = true
		-- Ranked (always 1v1): ratings change once per match, forfeits/leaves included.
		local ratingChanges = match.Ranked and self.Services.RankedService:ApplyResult(match, winnerSide and match.Teams[winnerSide][1] or nil) or {}
		for _, player in match.Players do
			if player.Parent then
				local side = match.Side[player]
				local result = (winnerSide == nil) and "Draw" or (winnerSide == side and "Win" or "Loss")
				local profile = self.Services.PlayerDataService:Get(player)
				local summary = nil
				local log = rewardLog[player] or {}
				local now = os.clock()
				for i = #log, 1, -1 do
					if now - log[i] > 3600 then
						table.remove(log, i)
					end
				end
				rewardLog[player] = log
				local eligible = duration >= PVP.MinMatchSecondsForRewards and #log < PVP.MaxRewardedMatchesPerHour
				if profile then
					local key = result == "Win" and "Wins" or (result == "Loss" and "Losses" or "Draws")
					-- (NIGHTMARE UNDERGROUND keeps its own fight record)
					local record = match.Mode == "Underground" and profile.Underground or profile.PvP
					record[key] = (record[key] or 0) + 1
					if eligible then
						table.insert(log, now)
						summary = self.Services.ProgressionService:Award(player, PVP.Rewards[result])
						self.Services.GameAnalyticsService:Rewards(player, PVP.Rewards[result], "Duel")
					end
					self.Services.PlayerDataService:SaveNow(player)
					self.Services.NightmareBuildService:PushState(player)
				end
				self.DuelEvent:FireClient(player, "MatchEnd", {
					Result = result,
					Reason = reason,
					MyScore = match.Score[side],
					OpponentScore = match.Score[3 - side],
					OpponentName = match.TeamNames[3 - side],
					Rewards = summary,
					RewardNote = (not eligible) and (duration < PVP.MinMatchSecondsForRewards and "Match too short for rewards." or "Hourly reward limit reached.") or nil,
					Ranked = ratingChanges[player], -- { Old, New, Delta } for ranked matches
					ReturnIn = timing(match, "ResultsTime"),
					-- (NIGHTMARE UNDERGROUND: how it ended, the round cards, both fighters' numbers)
					Underground = match.Mode == "Underground" and self.Services.UndergroundService:Results(match, player, winnerSide, reason) or nil,
				})
				local kind = match.Mode == "Underground" and "Underground" or match.Ranked and "Ranked" or (match.TeamSize > 1 and ("Team%dv%d"):format(match.TeamSize, match.TeamSize) or "Casual")
				self.Services.GameAnalyticsService:Event(player, "DuelEnd", math.floor(duration), { kind, result, reason })
			end
		end
	end

	task.delay(timing(match, "ResultsTime"), function()
		self:Cleanup(match)
	end)
end

function DuelService:Cleanup(match)
	if match.Closed then
		return
	end
	match.Closed = true
	for _, player in match.Players do
		if playerMatch[player] == match then
			playerMatch[player] = nil
			setDuelAttributes(self, match, player, false)
			if match.Mode == "Underground" then
				self.Services.PossessionService:End(player, "MatchOver")
				self.Services.UndergroundService:Unpark(player)
			end
			if player.Parent then
				local character = player.Character
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					humanoid.Health = humanoid.MaxHealth
					character:PivotTo(CFrame.new(Config.World.HubSpawn))
				end
				self.Services.HandlerService:ResetForDuel(player)
				self.Services.NightmareSpawnService:ClearOverride(player)
				self.Services.NightmareSpawnService:ForceSpawn(player, nil)
				self.DuelEvent:FireClient(player, "State", { State = "None" })
			end
		end
	end
	matches[match.Id] = nil
	if match.Mode == "Underground" then
		self.Services.UndergroundService:ReleaseArena(match.Slot)
		self.Services.UndergroundService:AfterCleanup(match) -- (a rematch, or back in the queue)
	else
		slotInUse[match.Slot] = nil
	end
end

-- FORFEIT forfeits for your whole side (team duels included).
function DuelService:Forfeit(player: Player)
	local match = playerMatch[player]
	if not match or match.State == "Ended" then
		return
	end
	local winnerSide = 3 - match.Side[player]
	if LIVE_STATES[match.State] then
		match.State = "Live" -- let EndRound run
		match.Token += 1
	end
	local who = match.TeamSize > 1 and (player.DisplayName .. "'S TEAM") or player.DisplayName
	self:Broadcast(match, "Banner", { Title = string.upper(who) .. " FORFEITS", Subtitle = "" })
	match.Score[winnerSide] = math.max(match.Score[winnerSide], math.ceil(match.BestOf / 2))
	self:EndMatch(match, winnerSide, "Forfeit")
end

-- A player who leaves the game. 1v1 (or their whole team gone): forfeit. Otherwise
-- they're out for good and their team plays on.
function DuelService:OnPlayerLeft(player: Player)
	local match = playerMatch[player]
	if not match or match.State == "Ended" then
		return
	end
	match.Left[player] = true
	local side = match.Side[player]
	for _, teammate in match.Teams[side] do
		if not match.Left[teammate] then
			if LIVE_STATES[match.State] then
				self:Eliminate(match, player, "Left")
			else
				match.Out[player] = true -- between rounds: just out (next rounds keep them out too)
				self:SendState(match)
			end
			return
		end
	end
	self:Forfeit(player)
end

-- Out for the rest of the round: frozen, untouchable, Nightmare stops. When a whole
-- side is out, the other side wins the round. (1v1: being out = losing the round.)
function DuelService:Eliminate(match, player: Player, reason: string)
	if not LIVE_STATES[match.State] or match.Out[player] then
		return
	end
	match.Out[player] = true
	local side = match.Side[player]
	for _, teammate in match.Teams[side] do
		if not match.Out[teammate] then
			-- Teammates still fighting: park this player on their pad, out of the way.
			if player.Parent then
				self:PlacePlayer(match, player)
				setDuelAttributes(self, match, player, true)
				self.Services.PossessionService:End(player, "Out")
			end
			local why = ({ NightmareDefeated = "Nightmare defeated", HandlerKO = "Handler knocked out twice", Left = "left the game" })[reason] or reason
			self:Broadcast(match, "Banner", { Title = string.upper(player.DisplayName) .. " IS OUT", Subtitle = why })
			self:SendState(match)
			return
		end
	end
	self:EndRound(match, 3 - side, reason)
end

------------------------------------------------------------------------------------------
-- Knockouts (called by CombatService / NightmareSpawnService)
------------------------------------------------------------------------------------------
function DuelService:OnHandlerKO(player: Player)
	local match = playerMatch[player]
	if not match or not LIVE_STATES[match.State] or match.Mode == "Underground" then
		return -- (Underground: the Handler isn't in the fight)
	end
	local character = player.Character
	if match.Out[player] or (character and character:FindFirstChildOfClass("ForceField")) then
		return -- already out, or in a protected respawn
	end
	match.KOs[player] += 1
	if match.KOs[player] >= PVP.HandlerKOsToLose then
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.Health = humanoid.MaxHealth -- (team duels: they wait on their pad)
		end
		self:Eliminate(match, player, "HandlerKO")
		return
	end
	-- 1st knockout: short protected respawn at your spawn; your Nightmare fights on.
	self:Broadcast(match, "Banner", { Title = player.DisplayName .. "'s HANDLER IS DOWN", Subtitle = ("Knockout %d / %d"):format(match.KOs[player], PVP.HandlerKOsToLose) })
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
		local shield = Instance.new("ForceField")
		shield.Parent = character
		task.delay(PVP.KOProtectTime, function()
			shield:Destroy()
		end)
		character:PivotTo(self:SpawnFor(match, player))
	end
	self:SendState(match)
end

function DuelService:OnNightmareDefeated(player: Player)
	local match = playerMatch[player]
	if match and LIVE_STATES[match.State] then
		self:Eliminate(match, player, "NightmareDefeated")
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function DuelService:Init(services)
	self.Services = services
	self.DuelEvent = Net.Get("DuelEvent")
end

function DuelService:Start()
	Net.Get("DuelRequest").OnServerInvoke = function(player, action, a1, a2)
		if not self.Services.AntiExploitService:Allow(player, "DuelRequest") then
			return { Ok = false, Error = "Slow down a little!" }
		end
		local profile = self.Services.PlayerDataService:Get(player)
		if not profile then
			return { Ok = false, Error = "Your profile is still loading." }
		end
		if action == "Challenge" then
			return self:Challenge(player, a1, a2, false)
		elseif action == "ChallengeTeam" then
			return self:Challenge(player, a1, nil, true)
		elseif action == "Respond" then
			return self:Respond(player, a1, a2 == true)
		elseif action == "SetAllow" then
			profile.Settings.AllowDuels = a1 == true
			self.Services.NightmareBuildService:PushState(player)
			return { Ok = true }
		elseif action == "SelectBuild" then
			return self:SelectBuild(player, a1)
		elseif action == "Forfeit" then
			self:Forfeit(player)
			return { Ok = true }
		elseif action == "QueueRanked" then
			return self.Services.RankedService:Join(player)
		elseif action == "UGAfter" then
			return self.Services.UndergroundService:After(player, a1) -- (REMATCH / QUEUE AGAIN)
		elseif action == "LeaveQueue" then
			self.Services.RankedService:Leave(player, "You stopped searching.")
			return { Ok = true }
		end
		return { Ok = false, Error = "Unknown request." }
	end

	-- A Handler that actually dies mid-match (reset, falling) counts as a knockout and
	-- is brought back to the arena when it respawns.
	local function hookCharacter(player: Player, character: Model)
		local match = playerMatch[player]
		if match and match.State ~= "Ended" then
			task.defer(function()
				self:PlacePlayer(match, player)
				setDuelAttributes(self, match, player, true)
			end)
		end
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid then
			humanoid.Died:Connect(function()
				self:OnHandlerKO(player)
			end)
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			hookCharacter(player, character)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		for id, request in requests do
			if request.From == player or request.To == player then
				requests[id] = nil
			end
		end
		self:OnPlayerLeft(player) -- 1v1: forfeit; team duels: out, team plays on
		rewardLog[player] = nil
		lastChallenge[player] = nil
	end)

	-- 4 Hz: round timer, sudden death zone damage.
	local accumulated, damageClock = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		damageClock += dt
		if accumulated < 0.25 then
			return
		end
		accumulated = 0
		local applyZoneDamage = damageClock >= 1
		if applyZoneDamage then
			damageClock = 0
		end
		for _, match in matches do
			if match.State == "Live" and serverNow() >= match.PhaseEndsAt and match.Mode == "Underground" then
				-- the bell: a decision on points (UndergroundService:Decide)
				self:EndRound(match, self.Services.UndergroundService:Decide(match), "Decision")
			elseif match.State == "Live" and serverNow() >= match.PhaseEndsAt then
				self:StartSuddenDeath(match)
			elseif match.State == "SuddenDeath" then
				if serverNow() >= match.SuddenDeathEnd then
					local scoreA, scoreB = self:HealthScore(match, 1), self:HealthScore(match, 2)
					local winnerSide = (math.abs(scoreA - scoreB) < 0.01) and nil or (scoreA > scoreB and 1 or 2)
					self:EndRound(match, winnerSide, "Time")
				elseif applyZoneDamage then
					local radius = zoneRadius(match)
					local center = match.Arena.Center
					for _, player in match.Players do
						if match.Out[player] then
							continue -- out players wait on their pad; the zone doesn't hurt them
						end
						local victims = { { player.Character, PVP.SuddenDeathDamage.Handler }, { self.Services.NightmareSpawnService:GetNightmare(player), PVP.SuddenDeathDamage.Nightmare } }
						for _, entry in victims do
							local model, amount = entry[1], entry[2]
							local root = model and model:FindFirstChild("HumanoidRootPart")
							if root and Util.FlatDistance(root.Position, center) > radius then
								self.Services.CombatService:ApplyDamage({
									Attacker = nil,
									Target = model,
									BaseDamage = amount,
									AllowSourceless = true,
									IgnoreDefence = true,
									Unblockable = true,
									NoStatus = true,
									Source = "SuddenDeath",
								})
							end
						end
					end
				end
			end
		end
	end)
end

return DuelService
