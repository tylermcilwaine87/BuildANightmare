--[[
	LevelUnlocks  (ModuleScript)
	Location: ReplicatedStorage/Shared/LevelUnlocks

	What each player LEVEL unlocks (Phase 5). Shared so the server enforces and the
	client shows the same thing (GOALS screen, level-up message).

	  PvE Power budget  100 -> 110 at level 10 -> 120 at level 20 (bigger PvE builds).
	                    PvP is ALWAYS 100 (Config.Builds.PvPPowerBudget), so duels stay fair.
	  Crafting          recipe levels from CraftingDefinitions (Rares at 3, Epics at 5)
	  Fighting          moves + weapons from MeleeDefinitions (Overhand 2, Pipe 3, Spin Kick 4...)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local CraftingDefinitions = require(Shared:WaitForChild("CraftingDefinitions"))
local MeleeDefinitions = require(Shared:WaitForChild("MeleeDefinitions"))

local LevelUnlocks = {}

-- { Level, Budget } in ascending level order.
LevelUnlocks.PvEBudgets = {
	{ Level = 1, Budget = Config.Builds.PvEPowerBudget }, -- 100
	{ Level = 10, Budget = 110 },
	{ Level = 20, Budget = 120 },
}

function LevelUnlocks.PvEBudget(level: number?): number
	local budget = Config.Builds.PvEPowerBudget
	for _, step in LevelUnlocks.PvEBudgets do
		if (level or 1) >= step.Level then
			budget = step.Budget
		end
	end
	return budget
end

-- Every unlock with a level above 1, sorted: { { Level, Text } }.
function LevelUnlocks.List(): { { Level: number, Text: string } }
	local list = {}
	for _, step in LevelUnlocks.PvEBudgets do
		if step.Level > 1 then
			table.insert(list, { Level = step.Level, Text = ("PvE Power budget %d (PvP stays %d)"):format(step.Budget, Config.Builds.PvPPowerBudget) })
		end
	end
	for _, partId in CraftingDefinitions.Order do
		local recipe = CraftingDefinitions.Get(partId)
		local def = PartDefinitions.Get(partId)
		if recipe and def and recipe.Level > 1 then
			table.insert(list, { Level = recipe.Level, Text = ("Craft %s at the Forge"):format(def.DisplayName) })
		end
	end
	-- fighting moves (Overhand, Spin Kick, Drop Kick) and weapons (MeleeDefinitions)
	for _, unlock in MeleeDefinitions.Unlocks() do
		table.insert(list, unlock)
	end
	table.sort(list, function(a, b)
		if a.Level ~= b.Level then
			return a.Level < b.Level
		end
		return a.Text < b.Text
	end)
	return list
end

-- Unlocks reached at exactly this level (for the level-up message).
function LevelUnlocks.At(level: number): { string }
	local texts = {}
	for _, unlock in LevelUnlocks.List() do
		if unlock.Level == level then
			table.insert(texts, unlock.Text)
		end
	end
	return texts
end

return LevelUnlocks
