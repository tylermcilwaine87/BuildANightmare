--[[
	CraftingDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/CraftingDefinitions

	The Crafting Forge (Phase 5). Shared so the client DISPLAYS exactly the rules the
	server ENFORCES (CraftingService).

	  Recipes      partId -> { Level, Essence, Coins, Ingredients = { [partId] = count } }
	  DismantleValue  Essence gained per dismantled copy, by rarity
	  SpareCount   how many PLAIN copies of a part may be used up (crafting ingredient
	               or dismantle): never your last copy, never copies a saved build
	               needs, never mutated copies
	  CanCraft     ok, reason for one recipe against a profile snapshot

	Economy (Normal boss win = 10 Essence, 60 coins + a part): a Rare costs about 3-4
	wins, an Epic about 7-8 (fewer on Hard / Nightmare, or by dismantling duplicates).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local SlotDefinitions = require(Shared:WaitForChild("SlotDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))

local CraftingDefinitions = {}

CraftingDefinitions.Recipes = {
	FrostHorns = { Level = 3, Essence = 60, Coins = 150, Ingredients = { CrackedSkull = 1 } },
	CrystalShell = { Level = 3, Essence = 80, Coins = 200, Ingredients = { WoodenBody = 1, ScrapVisor = 1 } },
	DemonicClaws = { Level = 5, Essence = 150, Coins = 400, Ingredients = { RustyClaw = 2, MagneticClaw = 1 } },
	VoidWings = { Level = 5, Essence = 180, Coins = 500, Ingredients = { TinyBatWings = 1, ReinforcedCore = 1 } },
}

-- Display order in the Forge.
CraftingDefinitions.Order = { "FrostHorns", "CrystalShell", "DemonicClaws", "VoidWings" }

CraftingDefinitions.DismantleValue = {
	Uncommon = 5,
	Rare = 15,
	Epic = 40,
	Legendary = 100,
}

function CraftingDefinitions.Get(partId)
	return type(partId) == "string" and CraftingDefinitions.Recipes[partId] or nil
end

-- True when Studio testing makes crafting free (no level, Essence, coin or part cost).
function CraftingDefinitions.IsFree(): boolean
	return Config.Dev.FreeCraftingInStudio == true and RunService:IsStudio()
end

-- PLAIN copies of `partId` you could give up. Never takes your last copy, never breaks a
-- saved build, and never touches MUTATED copies (those are kept safe).
function CraftingDefinitions.SpareCount(profile, partId: string): number
	local owned = profile.Inventory[partId] or 0
	local plainOwned = owned - MutationDefinitions.MutatedCount(profile, partId)
	local needed, plainNeeded = 1, 0
	for _, build in profile.Builds do
		local used, usedPlain = 0, 0
		for _, slot in SlotDefinitions.Order do
			if build.Parts and build.Parts[slot] == partId then
				used += 1
				if not MutationDefinitions.ForSlot(build, slot) then
					usedPlain += 1
				end
			end
		end
		needed = math.max(needed, used)
		plainNeeded = math.max(plainNeeded, usedPlain)
	end
	return math.max(0, math.min(owned - needed, plainOwned - plainNeeded))
end

-- ok, reason (reason is player-facing).
function CraftingDefinitions.CanCraft(profile, partId: string): (boolean, string?)
	local recipe = CraftingDefinitions.Get(partId)
	if not recipe or not PartDefinitions.Get(partId) then
		return false, "That part can't be crafted."
	end
	if CraftingDefinitions.IsFree() then
		return true, nil
	end
	if (profile.Level or 1) < recipe.Level then
		return false, ("Reach level %d to craft this."):format(recipe.Level)
	end
	if (profile.Essence or 0) < recipe.Essence then
		return false, ("Not enough Essence (%d / %d)."):format(profile.Essence or 0, recipe.Essence)
	end
	if (profile.Coins or 0) < recipe.Coins then
		return false, ("Not enough coins (%d / %d)."):format(profile.Coins or 0, recipe.Coins)
	end
	for ingredient, count in recipe.Ingredients do
		if CraftingDefinitions.SpareCount(profile, ingredient) < count then
			local def = PartDefinitions.Get(ingredient)
			local name = def and def.DisplayName or ingredient
			if (profile.Inventory[ingredient] or 0) == 0 then
				return false, ("You need %d× %s."):format(count, name)
			end
			return false, ("You need %d spare %s (your last copy and copies used in saved builds are kept)."):format(count, name)
		end
	end
	return true, nil
end

return CraftingDefinitions
