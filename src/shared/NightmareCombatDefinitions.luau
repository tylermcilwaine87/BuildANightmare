--[[
	NightmareCombatDefinitions  (ModuleScript, data only)
	Location: ReplicatedStorage/Shared/NightmareCombatDefinitions

	THE COMBAT BRAIN's rules (NightmareAIService "CombatBrain"). Every time an equipped
	Nightmare is in range and ready to fight, it scores what it COULD do (every string in
	Config.Nightmare.Moveset its body can throw, plus footwork: circling, a feint, a flank,
	its heavy, a guard) by the situation, its PERSONALITY and its owner's MODE, and picks
	one at random IN PROPORTION to those scores: varied, but believable (a staggered target
	draws finishers, a guarding one draws grabs and guard breaks, an exhausted Nightmare
	backs off). Nothing here is a damage number.

	Move TAGS (on each Moveset entry):
	  Light      quick, safe strikes            Heavy      big committed hits
	  Long       4+ hit combinations            Finisher   ends in a knockdown-class hit
	  Grab       takes hold of them             GuardBreak cracks a guard
	  Rush       closes the distance itself     Counter    starts by evading (React only)
	  Kick / Beast / Space (pushes them away) / Signature (rare, cinematic)
]]

local Combat = {}

-- STAMINA: every string costs some (Moveset Cost, else by tag); it refills while the
-- Nightmare isn't attacking. Below Low it starts backing off and guarding instead.
Combat.Stamina = {
	Max = 100,
	Regen = 22, -- per second, once it hasn't spent any for RegenDelay
	RegenDelay = 0.6,
	Low = 25,
	CostByTag = { Light = 12, Heavy = 22, Long = 30, Grab = 26, Rush = 18, Signature = 40 },
	DefaultCost = 16,
	StepCost = 10, -- a sidestep / step back
}

-- PERSONALITIES: how a Nightmare likes to fight. "Auto" picks one from its body (Auto
-- below). Tags: x weight for moves carrying the tag. Footwork: x weight for those
-- options. Dodge: x the chance it evades an incoming attack. Counter: x the chance it
-- turns an evade into a counter combination. Abort: chance it gives up a combination
-- whose first hit missed (instead of swinging on at air). Pause: x the breather after a
-- string.
Combat.Personalities = {
	Berserker = {
		Name = "Berserker", Blurb = "Relentless: heavy combos, risky lunges, devastating finishers.",
		Tags = { Heavy = 1.6, Long = 1.5, Rush = 1.5, Finisher = 1.4, Light = 0.8, Space = 0.4, Counter = 0.6 },
		Footwork = { Circle = 0.4, Feint = 0.5, Flank = 0.8, Guard = 0.3 },
		Dodge = 0.6, Counter = 0.6, Abort = 0.3, Pause = 0.6,
	},
	Technical = {
		Name = "Technical", Blurb = "Timed counters, evasions, precise combinations and feints.",
		Tags = { Light = 1.4, Counter = 2.2, Long = 1.2, Heavy = 0.8, Space = 1.4, Kick = 1.2 },
		Footwork = { Circle = 1.3, Feint = 2.0, Flank = 1.0, Guard = 1.0 },
		Dodge = 1.4, Counter = 1.8, Abort = 0.85, Pause = 1.0,
	},
	Bruiser = {
		Name = "Bruiser", Blurb = "Heavyweight strikes, grabs, guard breaks and knockdowns.",
		Tags = { Heavy = 1.7, Grab = 1.8, GuardBreak = 1.8, Finisher = 1.3, Light = 0.7 },
		Footwork = { Circle = 0.6, Feint = 0.4, Flank = 0.6, Guard = 1.2 },
		Dodge = 0.7, Counter = 0.8, Abort = 0.5, Pause = 1.1,
	},
	Predator = {
		Name = "Predator", Blurb = "Circles, attacks from angles, lunges, claws and bites.",
		Tags = { Beast = 1.8, Rush = 1.6, Grab = 1.4, Light = 1.0, Heavy = 1.0 },
		Footwork = { Circle = 1.8, Feint = 0.8, Flank = 2.2, Guard = 0.4 },
		Dodge = 1.1, Counter = 1.0, Abort = 0.6, Pause = 0.9,
	},
	Defender = {
		Name = "Defender", Blurb = "Guards its owner: blocks, counters, interrupts the dangerous.",
		Tags = { Counter = 1.8, Space = 1.6, Light = 1.2, Heavy = 0.8, Rush = 0.6 },
		Footwork = { Circle = 1.0, Feint = 0.6, Flank = 0.4, Guard = 2.0 },
		Dodge = 1.3, Counter = 1.6, Abort = 0.7, Pause = 1.2,
	},
}
Combat.PersonalityOrder = { "Auto", "Berserker", "Technical", "Bruiser", "Predator", "Defender" }

-- MODES (the owner's choice): how much risk it takes.
--   Assist: prefers moves that follow up YOUR strikes on the same target (it watches
--   for your hits and jumps in right after).
Combat.Modes = {
	Aggressive = { Name = "Aggressive", Blurb = "Takes every opening, longer combinations.", Tags = { Long = 1.5, Heavy = 1.2, Rush = 1.3, Space = 0.6 }, Footwork = { Guard = 0.4, Circle = 0.6 }, Pause = 0.6, StaminaFloor = 0 },
	Balanced = { Name = "Balanced", Blurb = "Mixes attack, defence, footwork and specials.", Tags = {}, Footwork = {}, Pause = 1, StaminaFloor = 10 },
	Defensive = { Name = "Defensive", Blurb = "Protects itself and you, counters, safer combos.", Tags = { Counter = 1.8, Space = 1.5, Long = 0.6, Rush = 0.6, Heavy = 0.8 }, Footwork = { Guard = 2.0, Circle = 1.3 }, Pause = 1.4, StaminaFloor = 35 },
	Assist = { Name = "Assist", Blurb = "Follows up YOUR combos on the same enemy.", Tags = { Light = 1.4, Long = 0.8 }, Footwork = { Flank = 1.3 }, Pause = 0.9, StaminaFloor = 15, FollowUp = 2.2 },
}
Combat.ModeOrder = { "Balanced", "Aggressive", "Defensive", "Assist" }

-- The SITUATION: x weight for moves with these tags when...
Combat.Situation = {
	Staggered = { Heavy = 2.0, Long = 1.5, Finisher = 2.2, Grab = 1.6 }, -- the target is staggered
	Guarding = { Grab = 2.6, GuardBreak = 2.6, Light = 0.4, Long = 0.5 }, -- it's holding a guard
	LowHealth = { Finisher = 2.2, Signature = 2.0, Long = 1.3 }, -- under 30% health
	Armoured = { Heavy = 1.4, GuardBreak = 1.4, Light = 0.8 }, -- real Defence, or a boss
	Fast = { Light = 1.4, Heavy = 0.6, Rush = 0.7 }, -- it moves quickly
	Pressured = { Counter = 1.6, Space = 1.6, Light = 1.2, Long = 0.7 }, -- it keeps attacking us
}
Combat.LowHealth = 0.3
Combat.FastSpeed = 19 -- WalkSpeed above this counts as fast
Combat.ArmouredDefence = 10
Combat.PressureWindow = 6 -- seconds: attacks it threw at us in this long count as pressure
Combat.PressureAttacks = 3

-- Footwork options' base weights (vs a string's own Weight).
Combat.Footwork = { Circle = 1.2, Feint = 0.6, Flank = 0.9, Guard = 0.8, Heavy = 1.0 }

-- Variety: x weight for a string thrown 1 / 2 / 3 picks ago; a string whose first hit
-- missed recently is less attractive for a while.
Combat.Repeat = { 0.1, 0.35, 0.6 }
Combat.WhiffPenalty = 0.45
Combat.WhiffMemory = 6

-- GUARD (footwork option): the Nightmare covers up for a moment. Light hits do Absorb of
-- their damage less; a Heavy hit breaks it (staggered, as a guard break).
Combat.Guard = { Time = { 0.7, 1.3 }, Absorb = 0.65, Action = "Guard_Hold", StaminaDrain = 8 }

-- SIGNATURE moments: rare; at most one per Cooldown seconds per Nightmare, and only when
-- the situation calls for one (a finisher on a staggered or nearly beaten target).
Combat.SignatureCooldown = 18

-- COUNTERS (React): at most one counter combination per this many seconds.
Combat.CounterCooldown = 5

-- "Auto" personality from the body: the build's parts suggest how it fights.
function Combat.AutoPersonality(model: Model): string
	local archetype = model:GetAttribute("Archetype")
	if archetype == "Quadruped" then
		return "Predator"
	end
	local heavy = false
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and (d.Name:sub(1, 9) == "RightArm_" or d.Name:sub(1, 8) == "LeftArm_") and d.Size.Magnitude > 3 then
			heavy = true
			break
		end
	end
	if heavy then
		return "Bruiser"
	end
	if archetype == "Floating" then
		return "Technical"
	end
	return "Technical"
end

-- The tags a Moveset entry carries (its own Tags, never nil).
function Combat.TagsOf(def)
	return def.Tags or {}
end

function Combat.CostOf(def): number
	if def.Cost then
		return def.Cost
	end
	local cost = 0
	for _, tag in Combat.TagsOf(def) do
		cost = math.max(cost, Combat.Stamina.CostByTag[tag] or 0)
	end
	return cost > 0 and cost or Combat.Stamina.DefaultCost
end

return Combat
