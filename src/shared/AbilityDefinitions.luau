--[[
	AbilityDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/AbilityDefinitions

	Data-driven Nightmare special abilities. Parts reference these via AbilityId.
	AbilityService executes them on the server; the client reads them for UI.

	Ability types (each handled by one executor in AbilityService):
	  Melee   box in front of the Nightmare            Range, Width, Damage
	  AoE     circle centred Offset studs ahead        Radius, Offset, Damage (telegraphed)
	  Charge  the body is driven forward, hitting what it runs into   Distance, Width, Time
	  Pull    yank one target in front of you           Range, Damage
	  Glare   a beam from the head, several ticks       Range, Width, Ticks, Interval
	  Shield  temporary damage-absorbing barrier        Amount, Duration
	  Leap / Breath (see the shop exclusives below)

	Every ability plays its own keyframed animation (NightmarePoses "Ability_<Id>"): Windup
	is its Hit frame, Windup + Recovery its length (plus a hold's time where it has one).
	Its effects and sounds are cued by that animation's markers (AbilityEffects).

	Shapes a melee ability can take (the BITE is the model: it lands, holds, finishes):
	  Strikes  several blows in one move: { At = seconds, Share = of Damage, Motion, ... }
	  Clamp    the jaws lock on, hold and shake the victim, then rip / blast it away
	  Wrap     the limb coils round the victim at range, hoists it and slams it down
	  Pin      the point goes in and stays in: the victim is pinned while venom pumps

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
		Damage = 22, Range = 5, Width = 5, Windup = 0.3, Recovery = 0.55, Cooldown = 6,
		Lunge = 3, Motion = "Grip", Knockback = 0,
		-- the jaws LOCK ON: the victim is held in the mouth and thrashed for Hold seconds
		-- (Share of the damage on the snap), then the head rips away: the rest of the damage
		-- and a hard throw to the side. Hold / Shake match the Ability_Bite animation's
		-- thrash and its "Rip" marker (NightmarePoses BITE).
		Clamp = { Hold = 1.45, Shake = 2.6, Share = 0.55, RipKnockback = 48 },
	},
	-- CHARGED BITE: the same lock-on as the bite, but electric: the jaw crackles open, snaps
	-- shut, and the victim is held CONVULSING (Style "Convulse": fast small jolts instead of
	-- a thrash) while three shocks run through it (Ticks: seconds after the snap, a share of
	-- the damage each), then the jaws DISCHARGE and blast it straight away (Throw "Forward").
	ChargedBite = {
		DisplayName = "Charged Bite",
		Type = "Melee",
		Element = "Electric",
		Description = "Lock the jaws on and run the current through them, then blast them away.",
		Damage = 34, Range = 5, Width = 6, Windup = 0.45, Recovery = 0.6, Cooldown = 8,
		Lunge = 3.5, Motion = "Grip", Knockback = 0,
		Clamp = {
			Hold = 1.4, Shake = 9, Swing = 4, Lift = 0.08, Style = "Convulse", Share = 0.35,
			Ticks = { { 0.35, 0.1 }, { 0.7, 0.1 }, { 1.05, 0.1 } },
			Throw = "Forward", RipKnockback = 58,
		},
	},
	-- FROST RAM (Charge): paw the ground twice snorting frost, then CHARGE: the body is
	-- driven Distance studs over Time, laying ice behind it. The first body it runs into that
	-- can be carried is GORED (Gore.Share of the damage) and carried on the horns to the end
	-- of the run, then TOSSED up and over (the rest, a launch); anything else it ploughs
	-- through is knocked aside. A boss stops it dead (the full hit lands there).
	FrostRam = {
		DisplayName = "Frost Ram",
		Type = "Charge",
		Element = "Ice",
		Description = "Paw the ice, charge horns-first, gore whatever's in the way and toss it.",
		Damage = 30, Distance = 14, Width = 5, Time = 0.45, Windup = 0.55, Recovery = 1.05, Cooldown = 9, Stagger = 30,
		Gore = { Share = 0.4, Lift = 1.4, Toss = { Lift = 52, Push = 20, Spin = 9 } },
		Trail = "Ice",
	},
	-- VISOR GLARE (Glare): the visor charges white-hot, then a searing beam pours out of it
	-- for Ticks x Interval, sweeping a little side to side; Damage per tick, the last one
	-- staggers. The welder vents its canister after.
	ScrapVisorBeam = {
		DisplayName = "Visor Glare",
		Type = "Glare",
		Element = "Fire",
		Description = "Charge the visor white-hot and pour a searing beam over them.",
		Damage = 6, Ticks = 4, Interval = 0.2, Range = 12, Width = 3.5, Windup = 0.55, Recovery = 0.45, Cooldown = 7, Stagger = 8,
	},
	-- RUSTY SLASH: a rake across, the claw carried round, and a backhand rake back the other
	-- way that sends them off (Strikes; "Sweep" carries the victim across the way the claw
	-- goes, "SweepBack" the other way).
	RustySlash = {
		DisplayName = "Rusty Slash",
		Type = "Melee",
		Description = "Rake across, then backhand them away the other way.",
		Damage = 20, Range = 6, Width = 9, Windup = 0.3, Recovery = 0.6, Cooldown = 5,
		Motion = "Sweep",
		Strikes = {
			{ At = 0.3, Share = 0.4, Motion = "Sweep", Knockback = 6, NoKnockdown = true },
			{ At = 0.62, Share = 0.6, Motion = "SweepBack", Knockback = 24 },
		},
	},
	-- TENTACLE LASH: the whip cracks out at full length (Range); a body it catches that can be
	-- carried is WRAPPED (Wrap.Share): reeled in to Wrap.Reach in front, hoisted Wrap.Lift
	-- studs, and SLAMMED into the floor Wrap.SlamAt seconds after the catch (the rest,
	-- crumpling them). Anything else just takes the lash.
	TentacleLash = {
		DisplayName = "Tentacle Lash",
		Type = "Melee",
		Element = "Shadow",
		Description = "Whip it out, wrap them up, hoist them high and smash them down.",
		Damage = 28, Range = 11, Width = 3.5, Windup = 0.45, Recovery = 0.5, Cooldown = 7,
		Wrap = { Share = 0.35, Reach = 4.5, Lift = 4, ReelTime = 0.25, LiftAt = 0.55, SlamAt = 0.75 },
	},
	-- DEMON REND: three rends with the burning claws: down across, back across (an X), then
	-- a rising gut-rip that throws them up in a burst of fire.
	DemonRend = {
		DisplayName = "Demon Rend",
		Type = "Melee",
		Element = "Fire",
		Description = "Rend them in an X, then rip upward and throw them in a burst of fire.",
		Damage = 42, Range = 6, Width = 6, Windup = 0.5, Recovery = 1.0, Cooldown = 10, Stagger = 40,
		Lunge = 2, Reach = 3,
		Strikes = {
			{ At = 0.5, Share = 0.22, Motion = "Sweep", Knockback = 4, NoKnockdown = true, NoStatus = true },
			{ At = 0.72, Share = 0.22, Motion = "SweepBack", Knockback = 4, NoKnockdown = true, NoStatus = true },
			{ At = 1.02, Share = 0.56, Motion = "Up", Heavy = true, Launch = { Lift = 30, Push = 14, Spin = 6 } },
		},
	},
	-- MAGNET PULL: the magnet locks on (Damage x Reel.Share), the victim is DRAGGED along the
	-- floor into the claw over Reel.Time, swung up over the head and SLAMMED down in front
	-- Reel.SlamAt seconds after the lock (the rest). A player is yanked in instead and takes
	-- the slam if they're still in reach.
	MagnetPull = {
		DisplayName = "Magnet Pull",
		Type = "Pull",
		Element = "Mechanical",
		Description = "Lock the magnet on, drag them in, swing them overhead and slam them down.",
		Damage = 22, Range = 25, Windup = 0.4, Recovery = 0.45, Cooldown = 10,
		Reel = { Share = 0.3, Time = 0.45, Lift = 4.5, SlamAt = 0.75, Reach = 3 },
	},
	-- HAMMER SLAM: hop and heave the hammer over, slam it down (the hit), and wrench it out
	-- of the floor in an AFTERSHOCK (Aftershock.At seconds after: a smaller ring).
	HammerSlam = {
		DisplayName = "Hammer Slam",
		Type = "AoE",
		Description = "Bring the hammer down on everything ahead, then wrench it free in an aftershock.",
		Damage = 45, Radius = 9, Offset = 7, Windup = 0.8, Recovery = 0.9, Cooldown = 12, Stagger = 50, Heavy = true,
		Slam = true,
		Aftershock = { At = 0.45, Radius = 6, Share = 0.2 },
	},
	-- BAT DIVE (Charge, Arc): two hard flaps up, then dive onto them in an arc (Time) and
	-- rake them (StopOnHit: the dive ends on the first body), then kick off them backwards
	-- (Bounce studs).
	BatDive = {
		DisplayName = "Bat Dive",
		Type = "Charge",
		Description = "Flap up, dive onto them claws-first and kick off.",
		Damage = 12, Distance = 10, Width = 4, Time = 0.25, Windup = 0.45, Recovery = 0.4, Cooldown = 6,
		Arc = 3.5, Early = true, StopOnHit = true, Bounce = 3,
	},
	-- BLINK DASH (Charge, Blink): wrap in the wings, vanish, and come out Distance studs on;
	-- the tear left in the air along the way splits open RiftDelay seconds later and cuts
	-- everything it passes through.
	BlinkDash = {
		DisplayName = "Blink Dash",
		Type = "Charge",
		Element = "Void",
		Description = "Vanish through a tear in space; a moment later the tear cuts everything on the line.",
		Damage = 18, Distance = 20, Width = 5, Time = 0, Windup = 0.35, Recovery = 0.45, Cooldown = 8,
		Blink = { RiftDelay = 0.25 },
		Trail = "Void",
	},
	-- TAIL SWEEP: crouch, coil, and spin round one and a half times with the tail out flat
	-- along the floor, sweeping the legs out from under everything around (Launch: a trip).
	TailSweep = {
		DisplayName = "Tail Sweep",
		Type = "AoE",
		Description = "Spin low and sweep the legs out from under everything around.",
		Damage = 16, Radius = 7, Offset = 0, Windup = 0.35, Recovery = 0.55, Cooldown = 7,
		Launch = { Lift = 22, Push = 6, Spin = 10 },
	},
	ReinforcedGuard = {
		DisplayName = "Reinforced Guard",
		Type = "Shield",
		Element = "Mechanical",
		Description = "Bang the fists together and stomp: the plates lock and absorb damage.",
		Amount = 60, Duration = 5, Windup = 0.35, Recovery = 0.4, Cooldown = 15,
	},
	CrystalBarrier = {
		DisplayName = "Crystal Barrier",
		Type = "Shield",
		Description = "Slam the ground: crystals erupt in a ring and soak a big hit.",
		Amount = 90, Duration = 5, Windup = 0.45, Recovery = 0.45, Cooldown = 18,
	},
	-- ENERGY OVERLOAD: the reactor builds, shaking harder and harder, then VENTS: everything
	-- around is blown outward (Radial launch).
	EnergyOverload = {
		DisplayName = "Energy Overload",
		Type = "AoE",
		Description = "The reactor builds to breaking point and vents in a devastating blast. Long cooldown.",
		Damage = 60, Radius = 12, Offset = 0, Windup = 1.0, Recovery = 0.9, Cooldown = 25, Stagger = 60, Element = "Fire", Heavy = true,
		Radial = true, Launch = { Lift = 26, Push = 38, Spin = 5 },
	},

	-- SHOP exclusives (PartDefinitions "Exclusive"): tuned like the free abilities of the
	-- same rarity (Meteor Fist ~ Hammer Slam, Dragon Breath ~ Demon Rend over time).
	-- Leap: the body jumps (an arc, Height high) to the target, at most Leap studs, and
	-- lands on the Hit frame (Windup): Damage in Radius around the landing, knockdown.
	-- FistAhead: where the fist comes down, ahead of the body (measured on the Hit frame).
	MeteorFist = {
		DisplayName = "Meteor Fist",
		Type = "Leap",
		Element = "Fire",
		Description = "Leap high and smash down fist-first: a burning crater.",
		Damage = 40, Radius = 8, Leap = 16, Height = 8, FistAhead = 2.0, Windup = 0.85, Recovery = 0.7, Cooldown = 12, Stagger = 50, Heavy = true,
	},
	-- Breath: a cone (Cone degrees wide, Range studs) in front of the head, Ticks hits
	-- Interval apart from the Hit frame on; Damage is per tick.
	DragonBreath = {
		DisplayName = "Dragon Breath",
		Type = "Breath",
		Element = "Fire",
		Description = "Rear back and pour a cone of fire over everything ahead.",
		Damage = 9, Ticks = 5, Interval = 0.2, Range = 14, Cone = 50, Windup = 0.5, Recovery = 0.4, Cooldown = 11, Stagger = 6,
	},
	-- PHOENIX DIVE (Charge, PassThrough): the wings flare into flame, fold, and the body
	-- streaks Distance studs through everything in the way, a trail of fire behind it, then
	-- flares open in a burst of fire where it pulls up (EndBurst).
	PhoenixDive = {
		DisplayName = "Phoenix Dive",
		Type = "Charge",
		Element = "Fire",
		Description = "Burst into flame and streak through them, then flare open in a blast of fire.",
		Damage = 22, Distance = 16, Width = 5, Time = 0.3, Windup = 0.35, Recovery = 0.5, Cooldown = 9,
		PassThrough = 0.6, EndBurst = { Radius = 5.5, Share = 0.4 },
		Trail = "Fire",
	},
	-- Retaliate: while the shield is up, anything that hits it from within Range gets the
	-- Status (PassiveService).
	MagmaShell = {
		DisplayName = "Magma Shell",
		Type = "Shield",
		Element = "Fire",
		Description = "A crust of cooling lava: absorbs damage and burns whatever hits it.",
		Amount = 70, Duration = 5, Windup = 0.35, Recovery = 0.35, Cooldown = 16,
		Retaliate = { Status = "Burn", Range = 10 },
	},
	-- VENOM STING: lunge in, the tail arcs over the head and STABS down. A body that can be
	-- held is PINNED on the stinger (Pin.Share): the tail pumps venom into it three times
	-- (Pin.Pumps: seconds after the stab, a share of the damage and a poison stack each),
	-- then yanks out in a spray and kicks it away. Anything else just takes the sting.
	VenomSting = {
		DisplayName = "Venom Sting",
		Type = "Melee",
		Element = "Poison",
		Description = "Stab down over the head, pin them on the stinger and pump the venom in.",
		-- Reach: the stinger is 3.05 studs ahead of the body on the Hit frame (measured,
		-- NightmarePoses VENOM STING), so the lunge stops there and the hit lands on the point
		Damage = 30, Range = 4, Width = 3, Lunge = 4, Reach = 3.05, Windup = 0.45, Recovery = 0.45, Cooldown = 8, Knockback = 8,
		Pin = { Share = 0.35, Hold = 0.9, Pumps = { { 0.22, 0.1 }, { 0.46, 0.1 }, { 0.7, 0.1 } }, YankKnockback = 26 },
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
	  Beam      long line in front, several ticks     Reach, Width, Ticks, Interval
	  Collapse  pull enemies to a point, then burst   PullRadius, Radius, Offset, OpenAt
	Startup is the first moment it deals damage; Length is the whole move (its clip's Duration).
]]
AbilityDefinitions.Ultimates = {
	SplinterStorm = {
		DisplayName = "SPLINTER STORM",
		Type = "Nova",
		Description = "The crate bursts apart and reassembles, three times.",
		Startup = 1.0, Length = 2.9, Damage = 22, Radius = 12, Pulses = 3, Interval = 0.6, Stagger = 30,
	},
	ThousandEyeGlare = {
		DisplayName = "THOUSAND-EYE GLARE",
		Type = "Beam",
		Element = "Shadow",
		Description = "An unblinking beam of pure dread.",
		Startup = 1.2, Length = 2.8, Damage = 24, Reach = 40, Width = 6, Ticks = 3, Interval = 0.4, Stagger = 20,
	},
	BastionQuake = {
		DisplayName = "BASTION QUAKE",
		Type = "Nova",
		Description = "Armour plates slam the ground in two massive shockwaves.",
		Startup = 1.1, Length = 2.7, Damage = 34, Radius = 14, Pulses = 2, Interval = 0.8, Stagger = 60,
	},
	CrystalCataclysm = {
		DisplayName = "CRYSTAL CATACLYSM",
		Type = "Barrage",
		Element = "Ice",
		Description = "Crystals erupt beneath every nearby enemy.",
		Startup = 1.2, Length = 3.0, Damage = 30, Count = 6, Interval = 0.12, ShatterAt = 2.4, Radius = 6, Area = 30, Stagger = 25,
	},
	ScrapApocalypse = {
		DisplayName = "SCRAP APOCALYPSE",
		Type = "Barrage",
		Element = "Fire",
		Description = "The reactor hurls a storm of burning scrap across the battlefield.",
		Startup = 1.4, Length = 3.5, Damage = 34, Count = 10, Interval = 0.35, Flight = 0.45, Radius = 6, Area = 35, Stagger = 30,
	},
	VoidCollapse = {
		DisplayName = "VOID COLLAPSE",
		Type = "Collapse",
		Element = "Shadow",
		Description = "A gravity well drags enemies together, then detonates.",
		Startup = 1.7, Length = 2.7, Damage = 70, OpenAt = 0.3, PullRadius = 22, Radius = 10, Offset = 8, Stagger = 70,
	},
	-- SHOP exclusives
	Supernova = {
		DisplayName = "SUPERNOVA",
		Type = "Nova",
		Element = "Fire",
		Description = "The phoenix flares three times, each wave of fire wider than the last.",
		Startup = 1.2, Length = 3.3, Damage = 24, Radius = 13, Pulses = 3, Interval = 0.6, Rise = 6, Stagger = 35,
	},
	Eruption = {
		DisplayName = "ERUPTION",
		Type = "Barrage",
		Element = "Fire",
		Description = "The heart splits open and lava rains down across the battlefield.",
		Startup = 1.3, Length = 3.4, Damage = 32, Count = 8, Interval = 0.14, Flight = 0.7, Radius = 6, Area = 32, Stagger = 30,
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
for id, def in AbilityDefinitions.Ultimates do
	def.Id = id
end

function AbilityDefinitions.Get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return AbilityDefinitions.ById[id]
end

-- How long an ability's action lasts, start to finish (its animation's length), and how
-- long it's committed (nothing cuts it before then): the windup, then any hold / pour
-- (a clamp, a wrap's slam, a pin, a reel, a beam or a breath), then the Recovery.
function AbilityDefinitions.Length(def): (number, number)
	local held = (def.Clamp and def.Clamp.Hold) or (def.Wrap and def.Wrap.SlamAt) or (def.Pin and def.Pin.Hold)
		or (def.Reel and def.Reel.SlamAt) or ((def.Type == "Glare" or def.Type == "Breath") and def.Ticks * def.Interval) or 0
	local committed = def.Windup + held
	return committed + def.Recovery, committed
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
