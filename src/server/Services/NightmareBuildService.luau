--[[
	NightmareBuildService  (ModuleScript)
	Location: ServerScriptService/Server/Services/NightmareBuildService

	Handles the BuildRequest RemoteFunction. The workshop UI edits a local DRAFT; only
	"SaveBuild" changes real data, and only after the server:
	  1. sanitises the untrusted table (types, unknown ids, NaN, clamps adjustments)
	  2. validates game rules with the AUTHORITATIVE inventory and power budget
	  3. filters the name through TextService (Roblox requirement for user text)

	Actions (all return { Ok = bool, Error = string?, Warning = string?, State = snapshot? }):
	  "GetState"
	  "SaveBuild", slotIndex, draftBuild
	  "SetActive", slotIndex
]]

local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local BuildValidator = require(Shared:WaitForChild("BuildValidator"))
local LevelUnlocks = require(Shared:WaitForChild("LevelUnlocks"))
local SettingsDefinitions = require(Shared:WaitForChild("SettingsDefinitions"))
local Util = require(Shared:WaitForChild("Util"))

local NightmareBuildService = {}

-- (profile.Builds holds SlotCount builds, or MaxSlotCount with the +3 Build Slots pass)
local function isValidSlotIndex(index, profile): boolean
	return type(index) == "number" and index % 1 == 0 and index >= 1 and index <= #profile.Builds
end

function NightmareBuildService:Init(services)
	self.Services = services
	self.UIState = Net.Get("UIStateUpdate")
end

function NightmareBuildService:Start()
	Net.Get("BuildRequest").OnServerInvoke = function(player, action, ...)
		if not self.Services.AntiExploitService:Allow(player, "BuildRequest") then
			return { Ok = false, Error = "Slow down a little!" }
		end
		local profile = self.Services.PlayerDataService:WaitFor(player, 10)
		if not profile then
			return { Ok = false, Error = "Your profile is still loading." }
		end

		-- Settings can be changed any time (even mid-duel).
		if action == "SetSetting" then
			local key, value = ...
			local clean = SettingsDefinitions.Sanitize(key, value)
			if clean == nil then
				return { Ok = false, Error = "Invalid setting." }
			end
			profile.Settings[key] = clean
			return { Ok = true, State = self.Services.PlayerDataService:Snapshot(player) }
		end
		if action ~= "GetState" and self.Services.DuelService:IsInMatch(player) then
			return { Ok = false, Error = "You can't change builds mid-duel. Pick one during PREP." }
		end
		if action == "GetState" then
			return { Ok = true, State = self.Services.PlayerDataService:Snapshot(player) }
		elseif action == "SaveBuild" then
			return self:SaveBuild(player, ...)
		elseif action == "SetActive" then
			return self:SetActive(player, ...)
		end
		return { Ok = false, Error = "Unknown request." }
	end
end

function NightmareBuildService:PushState(player: Player)
	local snapshot = self.Services.PlayerDataService:Snapshot(player)
	if snapshot then
		self.UIState:FireClient(player, "Profile", snapshot)
	end
end

-- Returns the filtered name (or the fallback) and an optional warning.
function NightmareBuildService:FilterName(player: Player, requested: string, fallback: string): (string, string?)
	if requested == "" then
		return fallback, nil
	end
	if requested == fallback then
		return fallback, nil -- already filtered when it was first saved
	end
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(requested, player.UserId)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if not ok or type(result) ~= "string" or result == "" then
		return fallback, "Name could not be checked right now, so it was not changed."
	end
	return Util.TruncateUtf8(result, Config.Builds.MaxNameLength), nil
end

function NightmareBuildService:SaveBuild(player: Player, slotIndex, draft)
	local profile = self.Services.PlayerDataService:Get(player)
	if not isValidSlotIndex(slotIndex, profile) then
		return { Ok = false, Error = "Invalid build slot." }
	end

	local build, sanitizeError = BuildValidator.Sanitize(draft)
	if not build then
		return { Ok = false, Error = sanitizeError }
	end

	local valid, validationError = BuildValidator.Validate(build, profile.Inventory, LevelUnlocks.PvEBudget(profile.Level), profile.Mutations)
	if not valid then
		return { Ok = false, Error = validationError }
	end

	local previousName = profile.Builds[slotIndex].Name
	local name, warning = self:FilterName(player, build.Name, previousName)
	build.Name = name

	profile.Builds[slotIndex] = build
	if profile.ActiveBuild == slotIndex then
		self.Services.NightmareSpawnService:Refresh(player)
	end
	self.Services.TutorialService:Notify(player, "BuildSaved", { Slot = slotIndex, Build = build })

	return { Ok = true, Warning = warning, State = self.Services.PlayerDataService:Snapshot(player) }
end

function NightmareBuildService:SetActive(player: Player, slotIndex)
	local profile = self.Services.PlayerDataService:Get(player)
	if not isValidSlotIndex(slotIndex, profile) then
		return { Ok = false, Error = "Invalid build slot." }
	end

	-- Re-validate: the saved build must still be legal (e.g. after a balance patch).
	local valid, validationError = BuildValidator.Validate(profile.Builds[slotIndex], profile.Inventory, LevelUnlocks.PvEBudget(profile.Level), profile.Mutations)
	if not valid then
		return { Ok = false, Error = validationError }
	end

	profile.ActiveBuild = slotIndex
	self.Services.NightmareSpawnService:Refresh(player)
	return { Ok = true, State = self.Services.PlayerDataService:Snapshot(player) }
end

return NightmareBuildService
