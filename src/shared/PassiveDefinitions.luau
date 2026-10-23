--[[
	PassiveDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/PassiveDefinitions

	Part PASSIVES: always-on effects a part gives its Nightmare (PartDefinitions `Passive`).
	The spawned Nightmare carries them in its "Passives" attribute ("Splinters,Sprint"), so
	server and client can both check them with PassiveDefinitions.Has(model, id).

	Where each one works:
	  Splinters   PassiveService (damage back to whoever hits it up close)
	  Glare       PassiveService (its hits CHILL, on a cooldown)
	  Bouncy      RagdollService (shorter knockdowns)
	  Hover       RagdollService (no knockdowns) + CombatService (floor hazards miss it)
	  Afterimage  NightmareAIService:QuickStep (untouchable mid-step) + EffectsController
	  Sturdy      CombatService (fewer knockdowns, less knockback)
	  Sprint      NightmareAIService (faster chasing far targets)
]]

local PassiveDefinitions = {}

PassiveDefinitions.ById = {
	Splinters = {
		DisplayName = "Splinters",
		Text = "anything that hits it up close takes 3 damage back",
		Damage = 3,
		Range = 10, -- studs between them (melee, not ranged hits)
		Cooldown = 1, -- per attacker
	},
	Glare = {
		DisplayName = "Glare",
		Text = "its first hit every 6 s CHILLS the target (35% slower)",
		Status = "Chill",
		Cooldown = 6,
	},
	Bouncy = {
		DisplayName = "Bouncy",
		Text = "bounces back up from knockdowns 40% faster",
		DurationMultiplier = 0.6,
	},
	Hover = {
		DisplayName = "Hover",
		Text = "can't be knocked down, and floats over floor hazards (steam vents, abyss pools)",
	},
	Afterimage = {
		DisplayName = "Afterimage",
		Text = "its sidesteps and dashes leave an afterimage, and nothing can hit it mid-step",
	},
	Sturdy = {
		DisplayName = "Sturdy",
		Text = "knockdowns are 75% less likely and knockback is halved",
		KnockdownMultiplier = 0.25,
		KnockbackMultiplier = 0.5,
	},
	Sprint = {
		DisplayName = "Sprint",
		Text = "chasing something more than 15 studs away, it breaks into a four-legged sprint (+40% speed)",
		Distance = 15,
		SpeedMultiplier = 1.4,
	},
}

for id, def in PassiveDefinitions.ById do
	def.Id = id
end

function PassiveDefinitions.Get(id: string?)
	return id and PassiveDefinitions.ById[id] or nil
end

-- "Splinters: anything that hits it up close takes 3 damage back" (UI line)
function PassiveDefinitions.Describe(id: string?): string?
	local def = PassiveDefinitions.Get(id)
	return def and (def.DisplayName .. ": " .. def.Text) or nil
end

-- Does this model (a spawned Nightmare) have passive `id`?
function PassiveDefinitions.Has(model: Instance?, id: string): boolean
	local list = model and model:GetAttribute("Passives")
	return type(list) == "string" and string.find("," .. list .. ",", "," .. id .. ",", 1, true) ~= nil
end

-- The passive ids a build's parts give. PartDefinitions is passed in (no circular require).
function PassiveDefinitions.ForBuild(build, PartDefinitions): { string }
	local ids = {}
	for _, partId in (build and build.Parts) or {} do
		local def = PartDefinitions.Get(partId)
		if def and def.Passive and PassiveDefinitions.ById[def.Passive] and not table.find(ids, def.Passive) then
			table.insert(ids, def.Passive)
		end
	end
	table.sort(ids)
	return ids
end

return PassiveDefinitions
