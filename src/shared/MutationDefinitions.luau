--[[
	MutationDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/MutationDefinitions

	MUTATIONS (Phase 5): a boss-dropped part can roll a mutation, a variant of the
	same part with a bonus and a new look. Mutations are SIDEGRADES: every one adds
	Power Cost, so PvP's 100 budget stays fair.

	Data:
	  profile.Mutations    = { [partId] = { [mutationId] = count } }  (mutated copies;
	                         they are ALSO counted in profile.Inventory[partId])
	  profile.MutationBook = { [mutationId] = { Found = n, Parts = { [partId] = true } } }
	  build.Mutations      = { [slot] = mutationId }  (nil/absent = plain part)

	Fields: DisplayName, Color, Weight (roll weight), Description, Stats (added to the
	part's), PowerCost (added), OnHit (status passive, like parts), Visual = { Tint,
	TintAlpha, Material, Transparency, Scale, Sparkle }.
]]

local MutationDefinitions = {}

local RGB = Color3.fromRGB
local Mat = Enum.Material

MutationDefinitions.ById = {
	Venomous = {
		DisplayName = "Venomous",
		Color = RGB(120, 220, 70),
		Weight = 12,
		Description = "Dripping with venom: hits may POISON.",
		Stats = { AttackPower = 2 },
		PowerCost = 2,
		OnHit = { Status = "Poison", Chance = 0.35 },
		Visual = { Tint = RGB(110, 210, 60), TintAlpha = 0.5 },
	},
	Infernal = {
		DisplayName = "Infernal",
		Color = RGB(255, 130, 40),
		Weight = 12,
		Description = "Smouldering from within: hits may BURN.",
		Stats = { AttackPower = 2 },
		PowerCost = 2,
		OnHit = { Status = "Burn", Chance = 0.3 },
		Visual = { Tint = RGB(255, 110, 30), TintAlpha = 0.5 },
	},
	Frozen = {
		DisplayName = "Frozen",
		Color = RGB(130, 220, 255),
		Weight = 12,
		Description = "Rimed with frost: hits may CHILL.",
		Stats = { Defence = 2 },
		PowerCost = 2,
		OnHit = { Status = "Chill", Chance = 0.3 },
		Visual = { Tint = RGB(170, 230, 255), TintAlpha = 0.55, Material = Mat.Ice },
	},
	Charged = {
		DisplayName = "Charged",
		Color = RGB(255, 235, 80),
		Weight = 12,
		Description = "Crackling with static: hits may SHOCK a second enemy.",
		Stats = { AttackSpeed = 3 },
		PowerCost = 2,
		OnHit = { Status = "Shock", Chance = 0.25 },
		Visual = { Tint = RGB(255, 230, 70), TintAlpha = 0.45 },
	},
	Cursed = {
		DisplayName = "Cursed",
		Color = RGB(170, 100, 255),
		Weight = 12,
		Description = "Whispering shadows: hits may WEAKEN the target.",
		Stats = { MaxHealth = 10 },
		PowerCost = 2,
		OnHit = { Status = "Weaken", Chance = 0.3 },
		Visual = { Tint = RGB(120, 60, 200), TintAlpha = 0.55 },
	},
	Glass = {
		DisplayName = "Glass",
		Color = RGB(200, 235, 255),
		Weight = 10,
		Description = "Brittle but razor-sharp: much more attack, less health.",
		Stats = { AttackPower = 12, MaxHealth = -40 },
		PowerCost = 1,
		Visual = { Tint = RGB(210, 240, 255), TintAlpha = 0.6, Material = Mat.Glass, Transparency = 0.35 },
	},
	Ironclad = {
		DisplayName = "Ironclad",
		Color = RGB(160, 165, 180),
		Weight = 10,
		Description = "Bolted-on plating: more defence, a little slower.",
		Stats = { Defence = 6, MoveSpeed = -1 },
		PowerCost = 2,
		Visual = { Tint = RGB(110, 115, 130), TintAlpha = 0.55, Material = Mat.DiamondPlate },
	},
	Swift = {
		DisplayName = "Swift",
		Color = RGB(90, 230, 210),
		Weight = 10,
		Description = "Light and twitchy: faster movement and attacks.",
		Stats = { MoveSpeed = 2, AttackSpeed = 8 },
		PowerCost = 2,
		Visual = { Tint = RGB(80, 220, 200), TintAlpha = 0.45 },
	},
	Colossal = {
		DisplayName = "Colossal",
		Color = RGB(230, 150, 90),
		Weight = 8,
		Description = "Grown oversized: more health and stagger resist, slower attacks.",
		Stats = { MaxHealth = 45, StaggerResist = 10, AttackSpeed = -5 },
		PowerCost = 3,
		Visual = { Tint = RGB(200, 120, 70), TintAlpha = 0.3, Scale = 1.15 },
	},
	Prismatic = {
		DisplayName = "Prismatic",
		Color = RGB(255, 140, 230),
		Weight = 2, -- very rare
		Description = "Shimmers with every colour at once: a little of everything.",
		Stats = { MaxHealth = 15, AttackPower = 5, Defence = 2, MoveSpeed = 1, AttackSpeed = 4 },
		PowerCost = 4,
		Visual = { Tint = RGB(255, 170, 240), TintAlpha = 0.35, Material = Mat.ForceField },
	},
}

-- Book / display order.
MutationDefinitions.Order = { "Venomous", "Infernal", "Frozen", "Charged", "Cursed", "Glass", "Ironclad", "Swift", "Colossal", "Prismatic" }

function MutationDefinitions.Get(id)
	return type(id) == "string" and MutationDefinitions.ById[id] or nil
end

-- Weighted random mutation id. `random` is a Random object.
function MutationDefinitions.Roll(random: Random): string
	local total = 0
	for _, id in MutationDefinitions.Order do
		total += MutationDefinitions.ById[id].Weight
	end
	local roll = random:NextNumber(0, total)
	for _, id in MutationDefinitions.Order do
		roll -= MutationDefinitions.ById[id].Weight
		if roll <= 0 then
			return id
		end
	end
	return MutationDefinitions.Order[1]
end

-- "Venomous Rusty Claw"
function MutationDefinitions.FullName(partName: string, mutationId: string?): string
	local mutation = MutationDefinitions.Get(mutationId)
	return mutation and (mutation.DisplayName .. " " .. partName) or partName
end

-- How many mutated copies of a part a profile owns (all mutations together).
function MutationDefinitions.MutatedCount(profile, partId: string): number
	local byMutation = profile.Mutations and profile.Mutations[partId]
	local total = 0
	for _, count in byMutation or {} do
		total += count
	end
	return total
end

-- The mutation equipped in a build slot (nil = plain).
function MutationDefinitions.ForSlot(build, slot: string): string?
	local mutations = build and build.Mutations
	local id = mutations and mutations[slot]
	return MutationDefinitions.Get(id) and id or nil
end

return MutationDefinitions
