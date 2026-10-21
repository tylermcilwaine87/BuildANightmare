--[[
	AbilityDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/AbilityDefinitions

	Data-driven Nightmare special abilities. Parts reference these via AbilityId.
	AbilityService executes them on the server; the client reads them for UI.

	Ability types (each handled by one executor in AbilityService):
	  Melee   box in front of the Nightmare            Range, Width, Damage
	  AoE     circle centred Offset studs ahead        Radius, Offset, Damage (telegraphed)
	  Dash    lunge forward, hits along the path        Distance, Width, Damage
	  Pull    yank one target in front of you           Range, Damage
	  Shield  temporary damage-absorbing barrier        Amount, Duration

	Which abilities a Nightmare gets (shown in the workshop):
	  Q (Ability 1) = the Head part's ability
	  E (Ability 2) = first ability found on: Core, Right Arm, Left Arm, Back, Tail
	Element is cosmetic until status effects arrive in Phase 3.
]]

local AbilityDefinitions = {}

AbilityDefinitions.ById = {
	-- (Lunge: studs the body closes in during the windup so the jaws reach them.
	--  Motion "Grip": the bite clamps and tears back, jerking the victim toward the biter;
	--  "Sweep": the blow carries the victim across the way the claw travels.
	--  Knockback overrides the Melee default of 15.)
	Bite = {
		DisplayName = "Bite",
		Type = "Melee",
		Description = "A quick, nasty chomp.",
		Damage = 22, Range = 5, Width = 5, Windup = 0.3, Recovery = 0.4, Cooldown = 6,
		Lunge = 3, Motion = "Grip", Knockback = 0,
		-- the jaws LOCK ON: the victim is held in the mouth and thrashed for Hold seconds
		-- (Share of the damage on the snap), then the head rips away: the rest of the damage
		-- and a hard throw to the side. Hold / Shake match the Ability_Bite animation's
		-- thrash and its "Rip" marker (NightmarePoses BITE).
		Clamp = { Hold = 1.45, Shake = 2.6, Share = 0.55, RipKnockback = 48 },
	},
	ChargedBite = {
		DisplayName = "Charged Bite",
		Type = "Melee",
		Element = "Electric",
		Description = "A crackling bite that hits hard.",
		Damage = 32, Range = 5, Width = 6, Windup = 0.45, Recovery = 0.45, Cooldown = 8,
		Lunge = 3.5, Motion = "Grip", Knockback = 0,
		-- the same clamp, its animation stretched 1.5x (so is the hold and the thrash)
		Clamp = { Hold = 1.45 * 1.5, Shake = 2.6 / 1.5, Share = 0.55, RipKnockback = 60 },
	},
	FrostRam = {
		DisplayName = "Frost Ram",
		Type = "Dash",
		Element = "Ice",
		Description = "Charge forward horns-first.",
		Damage = 24, Distance = 14, Width = 5, Windup = 0.35, Recovery = 0.5, Cooldown = 9, Stagger = 25,
	},
	ScrapVisorBeam = {
		DisplayName = "Visor Glare",
		Type = "Melee",
		Description = "A searing short-range glare.",
		Damage = 20, Range = 10, Width = 3, Windup = 0.4, Recovery = 0.4, Cooldown = 7,
	},
	RustySlash = {
		DisplayName = "Rusty Slash",
		Type = "Melee",
		Description = "A wide, squeaky sweep.",
		Damage = 18, Range = 6, Width = 9, Windup = 0.3, Recovery = 0.4, Cooldown = 5,
		Motion = "Sweep",
	},
	TentacleLash = {
		DisplayName = "Tentacle Lash",
		Type = "Melee",
		Element = "Shadow",
		Description = "A long, whipping strike.",
		Damage = 24, Range = 11, Width = 3, Windup = 0.4, Recovery = 0.45, Cooldown = 7,
	},
	DemonRend = {
		DisplayName = "Demon Rend",
		Type = "Melee",
		Description = "A brutal finisher.",
		Damage = 38, Range = 6, Width = 6, Windup = 0.5, Recovery = 0.6, Cooldown = 10, Stagger = 40, Element = "Fire",
	},
	MagnetPull = {
		DisplayName = "Magnet Pull",
		Type = "Pull",
		Element = "Mechanical",
		Description = "Yank an enemy right up to your claws.",
		Damage = 15, Range = 25, Windup = 0.4, Recovery = 0.5, Cooldown = 10,
	},
	HammerSlam = {
		DisplayName = "Hammer Slam",
		Type = "AoE",
		Description = "Bring the hammer down on everything ahead.",
		Damage = 45, Radius = 9, Offset = 7, Windup = 0.8, Recovery = 0.7, Cooldown = 12, Stagger = 50,
	},
	BatDive = {
		DisplayName = "Bat Dive",
		Type = "Dash",
		Description = "A short flapping dive.",
		Damage = 10, Distance = 10, Width = 4, Windup = 0.15, Recovery = 0.3, Cooldown = 6,
	},
	BlinkDash = {
		DisplayName = "Blink Dash",
		Type = "Dash",
		Element = "Void",
		Description = "Tear through space and through enemies.",
		Damage = 16, Distance = 20, Width = 5, Windup = 0.2, Recovery = 0.35, Cooldown = 8,
	},
	TailSweep = {
		DisplayName = "Tail Sweep",
		Type = "AoE",
		Description = "Spin and sweep everything nearby.",
		Damage = 14, Radius = 7, Offset = 0, Windup = 0.35, Recovery = 0.4, Cooldown = 7,
	},
	ReinforcedGuard = {
		DisplayName = "Reinforced Guard",
		Type = "Shield",
		Element = "Mechanical",
		Description = "Lock the plates: absorbs damage for a few seconds.",
		Amount = 60, Duration = 5, Windup = 0.2, Recovery = 0.2, Cooldown = 15,
	},
	CrystalBarrier = {
		DisplayName = "Crystal Barrier",
		Type = "Shield",
		Description = "A shimmering barrier that soaks a big hit.",
		Amount = 90, Duration = 5, Windup = 0.25, Recovery = 0.2, Cooldown = 18,
	},
	EnergyOverload = {
		DisplayName = "Energy Overload",
		Type = "AoE",
		Description = "The reactor vents in a devastating blast. Long cooldown.",
		Damage = 60, Radius = 12, Offset = 0, Windup = 1.0, Recovery = 0.8, Cooldown = 25, Stagger = 60, Element = "Fire",
	},
}

--[[
	ULTIMATES (G). Chosen by the build's SIGNATURE part: a Back part with an UltimateId
	(e.g. Void Wings) overrides the Core's ultimate. Every ultimate:
	  * needs a full Ultimate Energy bar (earned in combat), never spammable
	  * has a visible, telegraphed Startup so opponents can react
	  * respects damage caps (Config.Ultimate.PvPDamageCapFraction in PvP)
	Types:
	  Nova      pulses around the Nightmare           Radius, Pulses, Interval
	  Barrage   impacts around enemies in an area     Count, Radius, Area
	  Beam      long line in front, several ticks     Length, Width, Ticks, Interval
	  Collapse  pull enemies to a point, then burst   PullRadius, Radius, Offset
]]
AbilityDefinitions.Ultimates = {
	SplinterStorm = {
		DisplayName = "SPLINTER STORM",
		Type = "Nova",
		Description = "The crate bursts apart and reassembles, three times.",
		Startup = 1.0, Damage = 22, Radius = 12, Pulses = 3, Interval = 0.6, Stagger = 30,
	},
	ThousandEyeGlare = {
		DisplayName = "THOUSAND-EYE GLARE",
		Type = "Beam",
		Element = "Shadow",
		Description = "An unblinking beam of pure dread.",
		Startup = 1.2, Damage = 24, Length = 40, Width = 6, Ticks = 3, Interval = 0.35, Stagger = 20,
	},
	BastionQuake = {
		DisplayName = "BASTION QUAKE",
		Type = "Nova",
		Description = "Armour plates slam the ground in two massive shockwaves.",
		Startup = 1.1, Damage = 34, Radius = 14, Pulses = 2, Interval = 0.8, Stagger = 60,
	},
	CrystalCataclysm = {
		DisplayName = "CRYSTAL CATACLYSM",
		Type = "Barrage",
		Element = "Ice",
		Description = "Crystals erupt beneath every nearby enemy.",
		Startup = 1.2, Damage = 30, Count = 6, Radius = 6, Area = 30, Stagger = 25,
	},
	ScrapApocalypse = {
		DisplayName = "SCRAP APOCALYPSE",
		Type = "Barrage",
		Element = "Fire",
		Description = "The reactor hurls a storm of burning scrap across the battlefield.",
		Startup = 1.4, Damage = 34, Count = 10, Radius = 6, Area = 35, Stagger = 30,
	},
	VoidCollapse = {
		DisplayName = "VOID COLLAPSE",
		Type = "Collapse",
		Element = "Shadow",
		Description = "A gravity well drags enemies together, then detonates.",
		Startup = 1.2, Damage = 70, PullRadius = 22, Radius = 10, Offset = 8, Stagger = 70,
	},
}

function AbilityDefinitions.GetUltimate(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return AbilityDefinitions.Ultimates[id]
end

-- Signature part (Back) overrides the Core.
function AbilityDefinitions.UltimateForBuild(build, PartDefinitions): string?
	local parts = (build and build.Parts) or {}
	local back = PartDefinitions.Get(parts.Back)
	if back and back.UltimateId and AbilityDefinitions.Ultimates[back.UltimateId] then
		return back.UltimateId
	end
	local core = PartDefinitions.Get(parts.Core)
	if core and core.UltimateId and AbilityDefinitions.Ultimates[core.UltimateId] then
		return core.UltimateId
	end
	return nil
end

-- Order E (Ability 2) is taken from.
AbilityDefinitions.SecondarySlotOrder = { "Core", "RightArm", "LeftArm", "Back", "Tail" }

for id, def in AbilityDefinitions.ById do
	def.Id = id
end

function AbilityDefinitions.Get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return AbilityDefinitions.ById[id]
end

-- Returns { [1] = abilityId?, [2] = abilityId? } for a build.
-- PartDefinitions is passed in to avoid a circular require.
function AbilityDefinitions.ForBuild(build, PartDefinitions)
	local result = {}
	local parts = (build and build.Parts) or {}
	local head = PartDefinitions.Get(parts.Head)
	if head and head.AbilityId and AbilityDefinitions.ById[head.AbilityId] then
		result[1] = head.AbilityId
	end
	for _, slot in AbilityDefinitions.SecondarySlotOrder do
		local def = PartDefinitions.Get(parts[slot])
		if def and def.AbilityId and AbilityDefinitions.ById[def.AbilityId] and def.AbilityId ~= result[1] then
			result[2] = def.AbilityId
			break
		end
	end
	return result
end

return AbilityDefinitions
