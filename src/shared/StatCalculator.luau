--[[
	StatCalculator  (ModuleScript)
	Location: ReplicatedStorage/Shared/StatCalculator

	Pure function: build data -> final stats. The SERVER uses it authoritatively when
	spawning a Nightmare; the CLIENT uses the same code to preview stats in the workshop.

	  MaxHealth   = archetype base + sum(part bonuses), clamped
	  AttackPower = archetype base + sum(part bonuses), clamped   (100 = x1.0 damage)
	  Reach       = archetype base + the single best arm Reach bonus (not summed)
	  PowerCost   = sum(part costs)
	A mutated part (build.Mutations[slot]) adds its mutation's Stats and PowerCost.
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local SlotDefinitions = require(Shared.SlotDefinitions)
local PartDefinitions = require(Shared.PartDefinitions)
local ArchetypeDefinitions = require(Shared.ArchetypeDefinitions)
local MutationDefinitions = require(Shared.MutationDefinitions)

local StatCalculator = {}

-- Rows shown in the workshop stat panel, in order.
StatCalculator.DisplayOrder = {
	{ Key = "MaxHealth", Label = "Max Health" },
	{ Key = "AttackPower", Label = "Attack Power" },
	{ Key = "Defence", Label = "Defence" },
	{ Key = "MoveSpeed", Label = "Move Speed" },
	{ Key = "AttackSpeed", Label = "Attack Speed" },
	{ Key = "Reach", Label = "Reach" },
	{ Key = "StaggerPower", Label = "Stagger Power" },
	{ Key = "StaggerResist", Label = "Stagger Resist" },
}

function StatCalculator.GetArchetype(build): string
	local parts = build and build.Parts
	local legs = parts and PartDefinitions.Get(parts.Legs)
	local archetype = legs and legs.Movement
	if archetype and ArchetypeDefinitions[archetype] then
		return archetype
	end
	return "Biped"
end

function StatCalculator.Compute(build)
	local archetypeName = StatCalculator.GetArchetype(build)
	local base = ArchetypeDefinitions[archetypeName]

	local stats = {
		MaxHealth = base.MaxHealth,
		AttackPower = base.AttackPower,
		Defence = base.Defence,
		MoveSpeed = base.MoveSpeed,
		AttackSpeed = base.AttackSpeed,
		Reach = base.Reach,
		StaggerPower = 100,
		StaggerResist = 0,
		PowerCost = 0,
	}

	local reachBonus = 0
	local parts = (build and build.Parts) or {}
	for _, slot in SlotDefinitions.Order do
		local def = PartDefinitions.Get(parts[slot])
		if def then
			stats.PowerCost += def.PowerCost
			for key, value in def.Stats do
				if key == "Reach" then
					reachBonus = math.max(reachBonus, value)
				elseif stats[key] ~= nil then
					stats[key] += value
				end
			end
			local mutation = MutationDefinitions.Get(MutationDefinitions.ForSlot(build, slot))
			if mutation then
				stats.PowerCost += mutation.PowerCost
				for key, value in mutation.Stats do
					if stats[key] ~= nil then
						stats[key] += value
					end
				end
			end
		end
	end
	stats.Reach += reachBonus

	for key, range in Config.StatCaps do
		if stats[key] ~= nil then
			stats[key] = math.clamp(stats[key], range[1], range[2])
		end
	end

	return stats, archetypeName
end

-- Damage multiplier from a target's Defence stat (never reaches zero).
function StatCalculator.DefenceMultiplier(defence: number): number
	local k = Config.Combat.DefenceConstant
	return k / (k + math.max(0, defence))
end

return StatCalculator
