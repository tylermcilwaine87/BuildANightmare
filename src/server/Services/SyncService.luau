--[[
	SyncService  (ModuleScript)
	Location: ServerScriptService/Server/Services/SyncService

	The SYNC meter (Config.Sync): fighting WITH your Nightmare. Every hit you or your
	Nightmare land on an enemy the other one hit within the last `Window` seconds fills it;
	it drains when you stop. Full: SYNCED - for `Duration` seconds your hits and its hits
	deal more damage and stagger (CombatService asks :DamageMultiplier / :StaggerMultiplier).

	Attributes on the player's character (HUD): Sync (0..Max), SyncedUntil (server time).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local SyncService = {}

local CFG = Config.Sync
local states: { [Player]: any } = {}

local function stateOf(player: Player)
	local state = states[player]
	if not state then
		state = { Meter = 0, LastGain = 0, SyncedUntil = 0, Hits = {} }
		states[player] = state
	end
	return state
end

local function publish(player: Player, state)
	local character = player.Character
	if character then
		character:SetAttribute("Sync", math.floor(state.Meter + 0.5))
		character:SetAttribute("SyncedUntil", state.SyncedUntil)
	end
end

-- "Handler" / "Nightmare" for a model a player fights with, plus that player.
function SyncService:SideOf(model: Model?): (Player?, string?)
	local player = model and self.Services.CombatService:GetOwnerPlayer(model)
	if not player then
		return nil, nil
	end
	if model == player.Character then
		return player, "Handler"
	elseif CollectionService:HasTag(model, "Nightmare") then
		return player, "Nightmare"
	end
	return nil, nil
end

function SyncService:IsSynced(player: Player): boolean
	local state = states[player]
	return state ~= nil and Workspace:GetServerTimeNow() < state.SyncedUntil
end

-- Outgoing multipliers for a hit by `attacker` (1 unless its owner is synced).
function SyncService:DamageMultiplier(attacker: Model?): number
	local player = self:SideOf(attacker)
	return player and self:IsSynced(player) and CFG.DamageMultiplier or 1
end

function SyncService:StaggerMultiplier(attacker: Model?): number
	local player = self:SideOf(attacker)
	return player and self:IsSynced(player) and CFG.StaggerMultiplier or 1
end

function SyncService:OnHit(target: Model, attacker: Model?, params)
	if not attacker or (params.Source or ""):sub(1, 7) == "Status:" then
		return
	end
	local player, side = self:SideOf(attacker)
	if not player then
		return
	end
	local state = stateOf(player)
	local now = Workspace:GetServerTimeNow()
	state.Hits[side] = { Target = target, At = now }
	if now < state.SyncedUntil then
		return
	end
	local partner = state.Hits[side == "Handler" and "Nightmare" or "Handler"]
	if not partner or partner.Target ~= target or now - partner.At > CFG.Window then
		return
	end
	state.Meter = math.min(CFG.Max, state.Meter + CFG.Gain)
	state.LastGain = now
	if state.Meter >= CFG.Max then
		state.Meter = 0
		state.SyncedUntil = now + CFG.Duration
	end
	publish(player, state)
end

function SyncService:Init(services)
	self.Services = services
end

function SyncService:Start()
	self.Services.CombatService:OnDamaged(function(target, attacker, _, params)
		self:OnHit(target, attacker, params or {})
	end)
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)

	-- 4 Hz: the meter drains when you stop fighting together
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.25 then
			return
		end
		local step = accumulated
		accumulated = 0
		local now = Workspace:GetServerTimeNow()
		for player, state in states do
			if state.Meter > 0 and now - state.LastGain > CFG.DecayDelay then
				state.Meter = math.max(0, state.Meter - CFG.DecayPerSecond * step)
				publish(player, state)
			end
		end
	end)
end

return SyncService
