--[[
	Config  (ModuleScript)
	Location: ReplicatedStorage/Shared/Config

	Central balancing & tuning. EVERY gameplay number lives here so nobody has to hunt
	through service code to rebalance. It is shared so the client can DISPLAY the same
	numbers the server ENFORCES. The server never trusts numbers sent back by a client.
]]

local Config = {}

Config.Version = "0.12.0 (the SHOP)"

Config.Dev = {
	-- DEV ONLY: in Studio, every player gets 2 of every part so the whole builder can be
	-- tested. Ignored on live servers (the server checks RunService:IsStudio()).
	-- Turn OFF to test the real progression (starter parts + boss drops).
	GrantAllPartsInStudio = false,
	-- DEV ONLY: in Studio, test players (Player1, Player2...) skip the tutorial so they can
	-- summon and duel straight away. Ignored on live servers. Turn OFF to test the tutorial.
	SkipTutorialInStudio = true,
	-- DEV ONLY: in Studio, Hard and Nightmare difficulty (and bosses that need another boss
	-- beaten first, like the Mirror Warden) are unlocked. Turn OFF to test the unlock flow.
	UnlockAllDifficultiesInStudio = true,
	-- DEV ONLY: in Studio, crafting at the Forge costs nothing (no level, Essence, coins
	-- or ingredient parts). Turn OFF to test the real crafting costs.
	FreeCraftingInStudio = true,
	-- DEV ONLY: in Studio, boss drops mutate this often (nil = use the real chances in
	-- Config.Mutations). Makes the Mutation Book easy to test.
	StudioMutationChance = 0.5,
	-- DEV ONLY: in Studio, the Forge's waystones to every boss gate work without a win
	-- (normally you must beat that boss once). Ignored on live servers.
	UnlockWaystonesInStudio = true,
	-- Studio only: every fighting move and weapon unlocked (to try them without levelling)
	UnlockAllMovesInStudio = true,
	-- DEV ONLY: in Studio, act as a player from a country where Roblox restricts paid
	-- random items, so the SHOP hides its luck items (PolicyService). Ignored live.
	ShopRestrictedInStudio = false,
	-- DEV ONLY: in Studio, print every hit of every Nightmare string / combo as the server
	-- resolves it (time into the move, target distance, who it hit). For measuring.
	LogNightmareCombos = true,
	-- In Studio, a move whose AnimationDefinitions slot has no uploaded Id but has an
	-- editable KeyframeSequence in Shared/Animations (e.g. Overhand.rbxm) plays THAT through
	-- the Animator (registered locally, nothing published). Live servers need the published
	-- Id; until then they use the move's code pose (same keyframes).
	PreviewKeyframesInStudio = true,
	-- Draws a translucent red box/sphere for every server-side hit query.
	DebugHitboxes = false,
	-- Draws each computed AI path as glowing dots (green = path found, red = no path).
	DebugNavigation = false,
}

------------------------------------------------------------------------------------------
-- Saving (DataStore)
------------------------------------------------------------------------------------------
Config.Data = {
	StoreName = "BuildANightmare_Profiles_v1",
	-- Studio playtests (with API access on) save to separate stores, so free crafting,
	-- the boosted Studio mutation chance etc. never leak into anyone's live save or the
	-- live leaderboards. Set to "" only if you deliberately want Studio to touch live data.
	StudioStoreSuffix = "_Studio",
	KeyPrefix = "Player_",
	AutosaveInterval = 120, -- seconds
	SessionLockTimeout = 600, -- a lock older than this is considered abandoned (crashed server)
	LoadRetries = 6, -- attempts while another server still holds the lock
	LoadRetryDelay = 5,
	WriteRetries = 4, -- exponential backoff 1s, 2s, 4s ...
}

------------------------------------------------------------------------------------------
-- Builds
------------------------------------------------------------------------------------------
Config.Builds = {
	SlotCount = 3, -- three saved Nightmares per player (e.g. Tank / Assassin / Abomination)
	MaxSlotCount = 6, -- with the SHOP's +3 Build Slots pass (profile.Builds grows to this)
	MaxNameLength = 20,
	ScaleMin = 0.8,
	ScaleMax = 1.25,
	ScaleStep = 0.05,
	RotateLimit = 20, -- degrees, applies to both yaw and pitch
	RotateStep = 5,
	PvEPowerBudget = 100, -- level 1 budget; rises with level (Shared/LevelUnlocks: 110 at 10, 120 at 20)
	PvPPowerBudget = 100, -- Phase 4: standard/ranked PvP is always normalised to 100
	MaxLegendaryParts = 1, -- one signature Legendary per Nightmare
}

-- Starter parts every new player receives (counts matter: two arms need two claws).
Config.StarterInventory = {
	WoodenBody = 1,
	PeeperOrb = 1,
	CrackedSkull = 1,
	RustyClaw = 2,
	JellyLegs = 1,
	DriftingWisp = 1,
	TinyBatWings = 1,
	BentMetalTail = 1,
	MangyHoundLegs = 1,
}

-- The three default saved builds. Players rename/rebuild them freely.
Config.StarterBuilds = {
	{
		Name = "The Tank",
		Parts = { Core = "WoodenBody", Head = "CrackedSkull", LeftArm = "RustyClaw", RightArm = "RustyClaw", Legs = "JellyLegs", Tail = "BentMetalTail" },
	},
	{
		Name = "The Assassin",
		Parts = { Core = "WoodenBody", Head = "CrackedSkull", RightArm = "RustyClaw", Legs = "JellyLegs", Back = "TinyBatWings" },
	},
	{
		Name = "The Abomination",
		Parts = { Core = "PeeperOrb", Head = "CrackedSkull", RightArm = "RustyClaw", Legs = "DriftingWisp", Back = "TinyBatWings" },
	},
}

------------------------------------------------------------------------------------------
-- Stat caps (hard limits applied after all part bonuses)
------------------------------------------------------------------------------------------
Config.StatCaps = {
	MaxHealth = { 150, 700 },
	AttackPower = { 50, 175 },
	Defence = { 0, 60 }, -- 60 defence = 37.5% damage reduction; 100% is impossible
	MoveSpeed = { 10, 26 },
	AttackSpeed = { 70, 140 }, -- percent; 140 = attacks take 71% of base time
	Reach = { 3, 9 },
	StaggerPower = { 50, 200 }, -- percent
	StaggerResist = { 0, 50 }, -- percent of incoming stagger ignored
}

------------------------------------------------------------------------------------------
-- Combat
------------------------------------------------------------------------------------------
Config.Combat = {
	-- Damage multiplier = DefenceConstant / (DefenceConstant + Defence)
	DefenceConstant = 100,
	DamageNumberMaxDistance = 140,
}

Config.Handler = {
	MaxHealth = 100,
	-- (punches, kicks, combos and weapons: Shared/MeleeDefinitions)
	Stamina = {
		Max = 100,
		RegenPerSecond = 22,
		RegenDelay = 0.8, -- seconds after spending stamina before it refills
	},
	-- The STEP BACK (X, or Shift while moving backwards): a quick hop straight back, still
	-- facing the fight, with a sliver of invulnerability. Punch or kick within
	-- CounterWindow afterwards and you dash back in with a COUNTER punch / kick
	-- (MeleeDefinitions CounterPunch / CounterKick) that hits harder and knocks back.
	StepBack = {
		StaminaCost = 14,
		Cooldown = 0.55,
		Distance = 7,
		Duration = 0.2,
		InvulnerableTime = 0.2,
		CounterWindow = 0.7, -- seconds after the step back to start a counter
		CounterDistance = 16, -- max studs the counter flies back in (always enough to reach)
		CounterDuration = 0.18, -- seconds the dash-in lasts (the hit lands at the end)
	},
	-- The DIVE (Shift): a leap in the direction you're moving (forward if standing still),
	-- with invulnerability while airborne. Dives through stomps, slams and projectiles.
	Dodge = {
		StaminaCost = 28,
		Cooldown = 1.1,
		InvulnerableTime = 0.45, -- i-frames cover the airborne part of the dive
		Speed = 46, -- studs/sec along the ground (client applies it; movement is client-owned)
		Hop = 32, -- upward launch speed: a low, fast leap (about a third of a second in the air)
		Duration = 0.42, -- how long the dive carries you
		RollSpeed = 22, -- then you roll forward along the floor...
		RollDuration = 0.4, -- ...for this long, and come up on your feet
		-- Facing an opponent (locked on, or one right in front of you), left / right dodges
		-- are a SIDE DIVE instead: low and sideways, a shoulder roll, circling AROUND them
		-- and still facing them (about 9 studs of arc: at close range that's ~75 degrees round
		-- to their flank, still in reach). Same stamina, cooldown and i-frames.
		Side = {
			Speed = 22,
			Hop = 12,
			Duration = 0.3,
			RollSpeed = 10,
			RollDuration = 0.27,
		},
	},
	Guard = {
		Startup = 0.15, -- guard isn't active instantly
		DamageReduction = 0.65, -- blockable damage
		HeavyDamageReduction = 0.3, -- "heavy" boss attacks are only partly blocked
		StaminaPerDamage = 1.0, -- stamina drained per point of damage absorbed
		WalkSpeed = 8,
		BreakStunTime = 1.2, -- guard break: can't guard, slowed
		BreakWalkSpeed = 5,
	},
	-- The PARRY: guard pressed within Window seconds before a blockable hit lands. No
	-- damage, and the attacker is knocked off line: Stagger x its stagger bar (BossStagger
	-- for bosses, which are also left EXPOSED), another player can't guard or dive for
	-- AttackerStun. Pressing guard again within Lockout of the last press opens no window
	-- (mashing guard doesn't parry everything).
	Parry = {
		Window = 0.25,
		Lockout = 0.6,
		Stagger = 0.6,
		BossStagger = 0.2,
		AttackerStun = 0.6,
	},
}

-- Ragdoll knockdowns: Handlers, Nightmares and normal enemies get knocked off their feet
-- (real physics) for Duration seconds by any of:
--   * a SPECIAL move: a Nightmare ability or Ultimate, a heavy attack, a boss slam
--   * a hit with at least MinKnockback
--   * a BIG hit: one hit taking DamageFraction of max health, or BurstFraction taken
--     within about BurstWindow seconds (a combo that really hurts)
-- Bosses never ragdoll. Each body can only be knocked down once per Cooldown (no juggling).
Config.Ragdoll = {
	MinKnockback = 40,
	DamageFraction = 0.18,
	BurstFraction = 0.35,
	BurstWindow = 3,
	MinThrow = 32, -- weak-knockback hits still throw the body at least this hard
	Duration = 1.3,
	Cooldown = 5,
	Launch = 0.9, -- how far the hit throws the body (x the hit's knockback)
	-- A LEG SWEEP (MeleeDefinitions Sweep) flips the body instead: popped up off its feet
	-- (Lift, studs/s), a little away (Push) and rotated heels over head (Spin, rad/s) to land
	-- on its back. (x the size factor: a small body flies higher)
	Sweep = { Lift = 44, Push = 6, Spin = 11 },

	-- SIZE: every body has a size = the cube root of its hitbox volume (a Handler counts
	-- as 3 x 5.2 x 2: about 3.2; a Scrapling 2.8, a Biped Nightmare 3.9, bosses 9-13).
	-- Hitting something SMALLER than you does more damage and throws it further; hitting
	-- something bigger does less and barely moves it. (ratio = your size / theirs)
	HandlerBody = Vector3.new(3, 5.2, 2),
	SizeDamage = { Exponent = 0.4, Min = 0.8, Max = 1.4 }, -- damage x ratio^Exponent (not vs bosses: their health is tuned)
	SizeThrow = { Exponent = 0.8, Min = 0.45, Max = 1.6 }, -- knockback / launch x ratio^Exponent (capped: dramatic, not absurd)
	SizeChance = { Exponent = 0.5, Min = 0.6, Max = 1.5 }, -- knockdown chance x ratio^Exponent

	-- RESISTANCE: the chance a knockdown-worthy hit actually knocks the target down is
	-- (1 - resist) x the size factor (x1.25 for a hit taking >= DamageFraction of its health).
	Resist = {
		Enemy = 0, -- Scraplings and other normal enemies: down every time
		Handler = 0.15,
		-- another player's Nightmare: armour (its Defence stat, 0-60) and StaggerResist make
		-- it much harder to drop than a Scrapling, but a good shot still can
		Nightmare = 0.3,
		NightmarePerDefence = 0.0075, -- 60 Defence: +0.45
		NightmarePerStaggerResist = 0.004, -- 50 StaggerResist: +0.2
		NightmareMax = 0.85,
	},
	-- BOSSES: only a SIGNATURE strike (a heavy move, an ability or an Ultimate) can floor
	-- one, and only the odd time; then it's down for a moment and can't be dropped again for
	-- a while. (Size makes no difference here: it's already priced in.)
	Boss = {
		Chance = 0.12,
		Cooldown = 25,
		Duration = 1.8,
		ThrowScale = 0.25, -- a huge body barely leaves the floor: it topples
		SpinScale = 0.4, -- ...and slowly
	},
}

-- Lock-on camera (Z / gamepad Select / LOCK button on phones).
Config.LockOn = {
	Range = 140, -- studs: how far away you can lock on
	BreakRange = 200, -- the lock drops if the target gets this far away
	Distance = 16, -- camera distance behind you while locked
	Height = 6,
	LockInTime = 0.6, -- seconds for the camera to glide onto the target
	ReleaseTime = 0.45, -- seconds to glide back to the normal camera after unlocking
	-- Close in (a duel) and the camera moves in over your shoulder, so your own body never
	-- hides the enemy in front of you. Blends in from DuelFrom studs, full at DuelAt.
	-- (Tuned in Studio: any less to the side and your body covers them.) It sits over your
	-- right shoulder unless your Nightmare is standing on that side, then the left.
	DuelFrom = 15,
	DuelAt = 8,
	DuelDistance = 8,
	DuelHeight = 6,
	DuelSide = 7,
}

Config.Nightmare = {
	AIUpdateRate = 10, -- brain ticks per second (all Nightmares share one loop)
	-- If a Nightmare is being hit but hasn't landed a hit on its own target for this long
	-- (e.g. it can't reach it), it turns on whatever is hitting it.
	SwitchTargetAfter = 2.5,
	FollowOffset = Vector3.new(5, 0, 4), -- right & behind the Handler
	FollowStopDistance = 3,
	CatchUpDistance = 18, -- beyond this the Nightmare runs faster to catch up
	CatchUpSpeedMultiplier = 1.4,
	TeleportDistance = 90, -- left far behind -> blink back to the Handler
	AggroRadius = 45, -- auto-defend: enemies this close to the HANDLER get engaged
	BossAggroRadius = 90, -- bosses are big: engage them from further away
	LeashRadius = 70, -- targets further than this from the Handler are dropped
	BossLeashRadius = 110,
	RetreatDuration = 5, -- seconds a Retreat order lasts before reverting to Follow
	RespawnDelay = 8, -- seconds after defeat before the Nightmare reforms
	OutOfCombatRegenDelay = 5,
	OutOfCombatRegenPerSecond = 0.06, -- fraction of MaxHealth per second
	ComboResetTime = 1.2, -- seconds after a swing before the combo restarts at hit 1
	IdleActionInterval = { 7, 14 }, -- seconds between personality idle actions
	-- Companion dodging of telegraphed attacks: deliberately imperfect.
	HazardDodgeChance = 0.7,
	HazardReactionTime = { 0.25, 0.5 },
	AbilityQueueTimeout = 3, -- an ability ordered out of range waits this long to get in range
	-- Fighting style: footwork instead of standing still and trading hits.
	Fight = {
		DashTime = 0.18, -- seconds a quick step lasts
		DashCooldown = 1.3, -- between any two quick steps
		StepBackDistance = 6, -- short hop back, just out of the attacker's reach
		SidestepDistance = 5,
		LungeDistance = 10, -- gap closer: dash in from up to this far outside reach
		LungeChance = 0.55,
		ReactChance = 0.5, -- target starts an attack close by: chance to step away
		ReactDelay = { 0.08, 0.22 }, -- reaction time (seconds), so it's not perfect
		SidestepShare = 0.35, -- of reactions, how many are sidesteps instead of hops back
		CounterChance = 0.7, -- after stepping out of an attack: dash straight back in and hit
		CounterDelay = 0.12,
		AfterFinisherStepChance = 0.45, -- after a combo finisher / heavy: hop out
		CircleChance = 0.6, -- after a full combo: circle the target for a moment
		CircleTime = { 0.5, 1.2 },
		CircleSpeed = 0.75, -- x MoveSpeed while circling
	},
	-- THE WILD MOVESET (NightmareAIService.StartString): real fighting strings, the same
	-- keyframed animations the Nightmare Gym trains on the bag (NightmarePoses.Common
	-- "Gym_*"), picked at random (by Weight, never the same twice in a row). Arms = needs an
	-- arm, Legs = needs two legs (Biped). Hits = { time (s), damage x StringDamage,
	-- knockback, heavy (knockdown), launch }. Times are the animation's contact frames (the
	-- markers measured on the gym bag), scaled by AttackSpeed. Clinch = grabs and holds the
	-- target for the knees. ExtraReach = a kick reaches further than a fist.
	StringDamage = 13,
	Moveset = {
		-- (Duration = the animation's length, GymDefinitions.Routines: the client plays it at
		-- the speed the server's timing implies)
		-- BRUTAL BOXER (NightmarePoses Biped Combo_BrutalBoxer, also a real KeyframeSequence in
		-- Shared/Animations): jab, cross, lead hook, uppercut, OVERHAND (knockdown), each hit on
		-- the clip's measured contact frame. Needs both arms and two legs (BothArms + Legs).
		{ Action = "Combo_BrutalBoxer", Duration = 2.4, Weight = 3, Tags = { "Long", "Finisher" }, Cost = 30, Arms = true, BothArms = true, Legs = true, Hits = { { 0.3, 0.5 }, { 0.55, 0.7, 4 }, { 0.82, 0.8, 8 }, { 1.1, 0.9, 6 }, { 1.62, 1.9, 34, true } } },
		-- PERFECT COUNTER (React only: Counter): the slip IS the evasion (Evade: the server slides
		-- the body Distance to the side over Time, untouchable), then hook, uppercut, push kick.
		{ Action = "Combo_PerfectCounter", Duration = 1.9, Weight = 3, Tags = { "Counter", "Kick", "Space" }, Cost = 24, Arms = true, BothArms = true, Legs = true, Evade = { Time = 0.26, Distance = 2.4 }, Hits = { { 0.46, 0.8, 4 }, { 0.7, 1.0, 8 }, { 1.0, 1.3, 30, true } } },
		-- SAVAGE EXECUTION (a grab: Hold keeps them in front of the chest): collar grab, two
		-- headbutts, hip toss (Throw: they fly off to its right, flipping)
		{ Action = "Combo_SavageExecution", Duration = 2.2, Weight = 2, Tags = { "Grab", "GuardBreak", "Finisher" }, Cost = 28, Arms = true, BothArms = true, Head = true, Clinch = true, Grab = true, Hold = { Reach = 3.5, Height = 1.7, Lift = 3.5, Throw = Vector3.new(3.0, 0, -2.2) }, Throw = "Right", Hits = { { 0.3, 0.3 }, { 0.62, 0.9 }, { 0.94, 1.0 }, { 1.38, 1.8, 30, true, { Lift = 40, Push = 30, Spin = 7 } } } },
		-- CYCLONE DESTROYER (a SIGNATURE: rare; unlocked by beating the Storm Beast): jab,
		-- spinning backfist, leaping double hammerfist
		{ Action = "Combo_CycloneDestroyer", Duration = 2.3, Weight = 3, Tags = { "Signature", "Finisher", "Long" }, Cost = 40, Arms = true, BothArms = true, Legs = true, Unlock = { Boss = "StormBeast" }, Leap = { At = 1.2, Time = 0.3, Max = 5 }, Hits = { { 0.3, 0.5 }, { 0.72, 1.2, 14 }, { 1.58, 2.4, 0, true, { Lift = 50, Push = 18, Spin = 6 } } } },
		-- PREDATOR RUSH (four legs and a head): spring in raking with a forepaw, bite, bite and
		-- wrench, rear up and slam both forepaws down
		{ Action = "Combo_PredatorRush", Duration = 1.9, Weight = 3, Tags = { "Beast", "Rush", "Long", "Finisher" }, Cost = 30, Quad = true, Head = true, Leap = { At = 0.2, Time = 0.22, Max = 8 }, Hits = { { 0.42, 0.7, 4 }, { 0.7, 0.9 }, { 1.0, 1.0, 6 }, { 1.45, 1.6, 30, true } } },
		{ Action = "Gym_ComboA", Duration = 1.6, Weight = 3, Tags = { "Light" }, Arms = true, Hits = { { 0.3, 0.55 }, { 0.54, 0.55 }, { 0.8, 0.95, 10 } } }, -- jab, jab, cross
		{ Action = "Gym_ComboB", Duration = 1.8, Weight = 3, Tags = { "Light" }, Arms = true, Hits = { { 0.3, 0.55 }, { 0.56, 0.8, 6 }, { 0.86, 1.05, 16 } } }, -- jab, cross, hook
		{ Action = "Gym_ComboC", Duration = 2.1, Weight = 2, Tags = { "Heavy", "Finisher" }, Arms = true, Hits = { { 0.3, 0.55 }, { 0.58, 0.85, 8 }, { 1.04, 1.6, 32, true } } }, -- jab, hook, OVERHAND
		{ Action = "Gym_BodyRip", Duration = 1.5, Weight = 2, Tags = { "Light", "GuardBreak" }, Arms = true, Hits = { { 0.46, 0.9, 6 }, { 0.74, 1.25, 20 } } }, -- body hook, uppercut
		{ Action = "Gym_Power", Duration = 1.4, Weight = 1, Tags = { "Heavy", "GuardBreak" }, Arms = true, Hits = { { 0.5, 1.9, 34, true } } }, -- one huge overhand
		{ Action = "Gym_Teep", Duration = 1.3, Weight = 2, Tags = { "Kick", "Space" }, Legs = true, ExtraReach = 1.5, Hits = { { 0.42, 1.0, 38 } } }, -- push kick: shoved away
		{ Action = "Gym_Roundhouse", Duration = 1.5, Weight = 2, Tags = { "Kick", "Heavy" }, Legs = true, ExtraReach = 1.5, Hits = { { 0.5, 1.5, 24, true } } },
		{ Action = "Gym_KneeClinch", Duration = 1.8, Weight = 1, Tags = { "Grab", "GuardBreak" }, Legs = true, Clinch = true, Hits = { { 0.5, 0.7 }, { 0.95, 0.7 }, { 1.35, 1.1, 18 } } },
		{ Action = "Gym_SpinBackKick", Duration = 1.6, Weight = 1, Tags = { "Kick", "Heavy", "Finisher" }, Legs = true, ExtraReach = 2, Hits = { { 0.56, 2.0, 0, true, { Lift = 34, Push = 22, Spin = 7 } } } },
		-- BEAST MOVES (NightmarePoses Common): for bodies that can't box. Quad = four legs,
		-- Head / Tail = needs one. Leap = { At, Time, Max }: the body travels onto them.
		-- POUNCE: crouch, spring, land on them, maul and tear loose
		{ Action = "Beast_Pounce", Duration = 1.5, Weight = 3, Tags = { "Beast", "Rush", "Grab" }, Quad = true, Leap = { At = 0.3, Time = 0.28, Max = 12 }, Hits = { { 0.58, 1.3, 0, true }, { 0.82, 0.5 }, { 1.02, 0.7, 18 } } },
		-- ROLLING CHARGE: curl up into a ball and roll right into them
		{ Action = "Beast_Roll", Duration = 1.4, Weight = 2, Tags = { "Beast", "Rush" }, Quad = true, Leap = { At = 0.3, Time = 0.4, Max = 14 }, Hits = { { 0.5, 0.8 }, { 0.68, 1.0, 26 } } },
		-- TAIL WHIP: spin the whole body round so the tail scythes through them
		{ Action = "Beast_TailWhip", Duration = 1.2, Weight = 2, Tags = { "Beast", "Heavy" }, Tail = true, ExtraReach = 1.5, Hits = { { 0.52, 1.4, 30, true } } },
		-- HEADBUTT: rear back and slam the skull in
		{ Action = "Beast_Headbutt", Duration = 1.0, Weight = 2, Tags = { "Beast", "Light", "GuardBreak" }, Head = true, Leap = { At = 0.22, Time = 0.16, Max = 3 }, Hits = { { 0.4, 1.2, 14 } } },
	},
	Feint = { Action = "Gym_Bounce", Duration = 1.6, Cut = 1.0 }, -- footwork + slips; cut short
	Wild = {
		StringChance = 0.85, -- of attacks: a real string (else the classic 3-hit combo)
		ChainChance = 0.35, -- straight into another string, no breather (x the Nightmare's flair)
		FlankChance = 0.18, -- per decision: sprint round to their side / back first (x flair)
		BossFlankChance = 0.35, -- ...against a boss, more often
		FlankAngle = { 100, 160 }, -- degrees round the target
		FlankSpeed = 1.55, -- x MoveSpeed
		FlankTime = 1.4, -- gives up after this long
		FeintChance = 0.08, -- a bounce of footwork and slips (feints) before going in
		LeapFromRangeChance = 0.5, -- per approach: a pounce / rolling charge from out of reach
		HitAndRunHealth = 0.35, -- below this fraction of health it starts hitting and running
		HitAndRunChance = 0.5, -- after a string, when hurt: sprint off, then dive back in
		HitAndRunTime = { 0.8, 1.3 },
		AfterStringRest = 0.3, -- seconds after a string's last hit before it can act again
	},
	-- The three-hit basic combo. Durations are scaled by the AttackSpeed stat.
	Combo = {
		{ Name = "Combo1", Damage = 12, Windup = 0.22, Recovery = 0.33, Knockback = 0 },
		{ Name = "Combo2", Damage = 14, Windup = 0.25, Recovery = 0.38, Knockback = 10 },
		{ Name = "Combo3", Damage = 20, Windup = 0.35, Recovery = 0.65, Knockback = 25 },
	},
}

------------------------------------------------------------------------------------------
-- Training enemies
------------------------------------------------------------------------------------------
Config.Enemies = {
	TrainingDummy = {
		DisplayName = "Training Dummy",
		MaxHealth = 400,
		Defence = 0,
		RespawnDelay = 3,
		RegenDelay = 5, -- fully heals after this long without being hit
	},
	Scrapling = {
		DisplayName = "Scrapling",
		MaxHealth = 180,
		Defence = 5,
		WalkSpeed = 11,
		AggroRadius = 30,
		LeashRadius = 40, -- from its home position
		AttackRange = 5,
		AttackWidth = 4,
		AttackDamage = 8,
		AttackWindup = 0.7, -- telegraph time: players can see it coming and step out
		AttackCooldown = 1.8,
		-- Tracking: during the windup it keeps turning toward its target (capped turn speed,
		-- so circling it still pays off if you're quick), then COMMITS for the last
		-- TrackCommit seconds and lunges up to StepIn studs into the swing. Dodge, step
		-- back or get out sideways late: you can't just jog around it anymore.
		TrackTurnRate = 170, -- degrees per second
		TrackCommit = 0.18,
		StepIn = 3,
		RespawnDelay = 6,
		AIUpdateRate = 5,
	},
}

------------------------------------------------------------------------------------------
-- Bosses (per-boss data lives in BossDefinitions)
------------------------------------------------------------------------------------------
Config.Bosses = {
	AIUpdateRate = 10,
	-- Slot 1 of each boss arena stands at the end of its route (WorldDefinitions). Extra
	-- slots (several groups fighting the same boss at once) are copies built out here.
	ArenaOrigin = Vector3.new(0, 1, 6000),
	ArenaSpacing = 600,
	MaxArenas = 12,
	IntroDelay = 3, -- seconds between arriving and the boss waking
	VictoryReturnTimeout = 60, -- auto-return to hub if the player doesn't choose
	-- Multiplayer health scaling by participant count (parties arrive in Phase 6).
	HealthScaling = { 1.0, 1.65, 2.3, 2.95 },
	ThreatNightmareBias = 1.2, -- bosses slightly prefer hitting Nightmares over Handlers
	TargetSwitchInterval = { 8, 12 },
	-- Pause between boss attacks (seconds), before the mode's AttackDelayMultiplier.
	AttackDelay = 1.1,
	OverdriveAttackDelay = 0.6,
	MinWindup = 0.5, -- telegraphs never get shorter than this, whatever the difficulty
	-- THE FIGHT'S RHYTHM (every boss):
	-- EXPOSED: after an attack (or a chain of them) the boss is open for a moment: it
	-- glows, and hits land harder and stagger far more. Dodge it, then punish.
	Exposed = { Time = 1.3, OverdriveTime = 0.85, DamageMultiplier = 1.35, StaggerMultiplier = 2 },
	-- CHAINS: sometimes it goes straight from one attack into the next, no breather (more
	-- often in its later phases); the exposed window comes at the end of the chain.
	Chain = { Chance = 0.18, OverdriveChance = 0.45, Max = 2, Delay = 0.3 },
	-- BROKEN: a full stagger bar drops it to its knees and it takes extra damage while down.
	BrokenDamageMultiplier = 1.5,
}

-- Selectable boss difficulties (Phase 5). Per-boss numbers (health, damage, windups)
-- live in BossDefinitions[boss].Modes; these are the shared rules for every boss.
Config.Difficulties = {
	Order = { "Normal", "Hard", "Nightmare" },
	Normal = { DisplayName = "NORMAL", Color = Color3.fromRGB(220, 90, 40), ExtraSkulls = 0, RewardMultiplier = 1 },
	Hard = { DisplayName = "HARD", Color = Color3.fromRGB(230, 50, 60), ExtraSkulls = 1, RewardMultiplier = 1.5, Requires = "Normal" },
	Nightmare = { DisplayName = "NIGHTMARE", Color = Color3.fromRGB(170, 60, 255), ExtraSkulls = 2, RewardMultiplier = 2.25, Requires = "Hard" },
}

-- Parties (Phase 6): co-op boss fights. Boss health scales with Config.Bosses.HealthScaling.
Config.Party = {
	MaxSize = 4,
	InviteTimeout = 20, -- seconds an invite stays open
	InviteCooldown = 3, -- seconds between invites from the same player
	-- Comebacks per boss fight, shared by the whole party. "PartySize" = one per member.
	-- A comeback only happens while someone is still standing in the arena; solo
	-- players therefore never get one.
	Revives = { Tutorial = "PartySize", Normal = "PartySize", Hard = 1, Nightmare = 0 },
	-- Extra seconds on top of Roblox's 5 s respawn, for the 1st / 2nd / 3rd+ comeback
	-- (so about 8 s, 12 s, 16 s in total).
	RejoinDelays = { 3, 7, 11 },
}

-- Leaderboards (Phase 6): global OrderedDataStores, shown on the HALL OF NIGHTMARES board.
Config.Leaderboards = {
	StorePrefix = "BuildANightmare_LB_v1_", -- bump the version to start fresh boards
	Size = 10, -- rows per board
	WriteInterval = 30, -- seconds between writes of changed values (per player, only if changed)
	ReadInterval = 60, -- seconds between refreshing the top lists
	CycleSeconds = 8, -- the board in the Forge shows each leaderboard this long
	BoardPosition = Vector3.new(-70, 1, 132), -- Hall of Nightmares (SW quarter), behind the showcase
}

-- Performance (Phase 7)
Config.Performance = {
	-- Visual effects (damage numbers, telegraphs, impacts, statuses...) are only sent to
	-- players within this many studs. Far-away boss fights cost your client nothing.
	EffectRadius = 250,
	-- Cached raycast filters (creatures / characters) are rebuilt at most this often.
	FilterRefresh = 1,
}

-- The Nightmare Showcase (Phase 6): one pedestal per player next to the Workshop.
Config.Showcase = {
	Slots = 8, -- pedestals (one per player in the server)
	FirstPedestal = Vector3.new(-122, 1, 96), -- Hall of Nightmares (SW quarter), a row along +X
	Spacing = 9,
	RefreshInterval = 4, -- seconds between checks for changed builds
}

-- Chance a boss-dropped part is MUTATED, per difficulty (Tutorial drops never mutate).
-- Which mutation: weights in Shared/MutationDefinitions.
Config.Mutations = {
	Chance = { Normal = 0.08, Hard = 0.14, Nightmare = 0.22 },
}

-- Rarity odds per boss mode. Hard sits between Normal and Nightmare.
Config.Loot = {
	Odds = {
		Normal = { Uncommon = 55, Rare = 30, Epic = 12, Legendary = 3 },
		Hard = { Uncommon = 45, Rare = 34, Epic = 17, Legendary = 4 },
		Nightmare = { Uncommon = 35, Rare = 37, Epic = 23, Legendary = 5 },
	},
	LegendaryPity = 25, -- the 25th eligible victory without a Legendary guarantees one
	TutorialGuaranteedRarity = "Rare",
}

------------------------------------------------------------------------------------------
-- Progression (levels unlock content in Phase 5; XP/coins are earned from Phase 2)
------------------------------------------------------------------------------------------
Config.Progression = {
	MaxLevel = 50,
	XPForLevel = function(level: number): number
		return 100 + 60 * (level - 1)
	end,
	Rewards = {
		BossVictory = { XP = 120, Coins = 60, Essence = 10 },
		TutorialBossVictory = { XP = 100, Coins = 40, Essence = 5 },
		TutorialComplete = { XP = 50, Coins = 100, Essence = 0 },
	},
}

------------------------------------------------------------------------------------------
-- World layout (generated by WorldBuilder when no hand-built map exists)
------------------------------------------------------------------------------------------
-- Hub facilities (the map layout itself lives in Shared/WorldDefinitions).
Config.World = {
	GroundY = 1,
	HubCenter = Vector3.new(0, 1, 0),
	HubSpawn = Vector3.new(0, 4, 52), -- = WorldDefinitions.HubSpawn
	WorkshopCenter = Vector3.new(-88, 1, -88), -- NW quarter
	ArenaCenter = Vector3.new(88, 1, -88), -- Training Arena, NE quarter
	ArenaSize = 70,
	ColosseumCenter = Vector3.new(92, 1, 92), -- SE quarter
	DummyOffsets = { Vector3.new(-15, 0, -25), Vector3.new(0, 0, -25), Vector3.new(15, 0, -25) },
	ScraplingOffsets = { Vector3.new(-14, 0, 18), Vector3.new(14, 0, 18) },
	ApplyLighting = true,
}

------------------------------------------------------------------------------------------
-- PHASE 3: advanced combat
------------------------------------------------------------------------------------------
-- Nightmare heavy attack: slow, hits hard, builds stagger, breaks guards.
Config.HeavyAttack = {
	Name = "Heavy",
	Damage = 28,
	Windup = 0.45,
	Active = 0.15,
	Recovery = 0.4,
	Knockback = 35,
	Stagger = 35,
	Cooldown = 4, -- companion AI only; possessed Nightmares are limited by timing
	ExtraReach = 1,
}

-- Stagger: meters fill from heavy hits & abilities; full = brief stun + follow-up window.
Config.Stagger = {
	ComboStagger = { 4, 5, 12 }, -- per basic-combo hit
	Max = { Nightmare = 100, Enemy = 80 }, -- bosses: BossDefinitions.StaggerMax
	Duration = { Nightmare = 1.2, Enemy = 1.5, Boss = 2.5 },
	DecayDelay = 2, -- seconds without stagger before the meter drains
	DecayPerSecond = 20,
	ResistanceTime = 5, -- after a stagger, stagger builds slowly for a while...
	ResistanceMultiplier = 0.25, -- ...at 25% rate: no stun-lock loops
}

Config.Status = {
	TickRate = 4, -- status ticks per second (definitions in StatusDefinitions)
}

-- SYNC (SyncService): you and your Nightmare landing hits on the SAME enemy within `Window`
-- seconds of each other fills the meter (`Gain` per hit); it drains after `DecayDelay`
-- without one. Full: SYNCED for `Duration` - both of you hit harder and stagger more.
Config.Sync = {
	Max = 100,
	Window = 1.5,
	Gain = 5,
	DecayDelay = 3,
	DecayPerSecond = 12,
	Duration = 8,
	DamageMultiplier = 1.25,
	StaggerMultiplier = 1.5,
}

-- NIGHTMARE POSSESSION
Config.Possession = {
	MeterMax = 100,
	Duration = 10,
	Cooldown = 45, -- minimum time between activations
	HandlerDamageReduction = 0.5, -- channelling Handler takes half damage (not immune)
	InterruptKnockback = 30, -- hits this strong (or Heavy) on the Handler break possession
	Gains = { HandlerHit = 5, NightmareHit = 2, CommandedHit = 3, AbilityHit = 4, PerfectDodge = 15 },
	MaxDistanceFromHandler = 90,
	SpeedTolerance = 1.8, -- anti-teleport: max allowed speed = MoveSpeed x this (+ dodge)
	DodgeCooldown = 1.0,
	DodgeInvulnerable = 0.3,
	DodgeSpeed = 55,
	DodgeDuration = 0.2,
}

-- ULTIMATES
Config.Ultimate = {
	EnergyMax = 100,
	PerDamageDealt = 1 / 5, -- energy per point of damage the Nightmare deals
	PerDamageTaken = 1 / 8,
	PerAbilityUse = 6,
	PvPDamageCapFraction = 0.45, -- Phase 4: an ultimate can never take >45% of a full-HP target
}

-- Companion pathfinding
Config.Navigation = {
	RepathInterval = 1.0, -- never recompute a path more often than this
	RepathDistance = 6, -- ...unless the goal moved this far
	WaypointReach = 4,
	-- Stuck detection: if a creature moves less than StuckMinProgress studs in
	-- StuckCheckInterval seconds while far from its goal, it stops trusting the straight
	-- line and pathfinds (or sidesteps if no path exists) for DetourDuration seconds.
	StuckCheckInterval = 0.75,
	StuckMinProgress = 1,
	DetourDuration = 2.5,
}

-- Command modes
Config.Commands = {
	Defend = { AggroRadius = 25, HeavyCooldownMultiplier = 1.2 },
	Aggressive = { AggroRadius = 70, LeashBonus = 25, HeavyCooldownMultiplier = 0.6 },
}

------------------------------------------------------------------------------------------
-- PHASE 4: PvP — THE NIGHTMARE COLOSSEUM
------------------------------------------------------------------------------------------
Config.PvP = {
	-- Fairness (spec section 13): every build must fit Config.Builds.PvPPowerBudget (100),
	-- max 1 Legendary, and stats never depend on player level.
	NightmareToHandlerMultiplier = 0.45, -- Nightmares hit Handlers for less, so duels stay about the monsters
	HandlerKOsToLose = 2, -- 2nd Handler knockout loses the round
	KOProtectTime = 2.5, -- protected respawn after the 1st knockout
	RoundTime = 180, -- 3 minutes
	SuddenDeathTime = 30, -- then the safe zone shrinks
	SuddenDeathStartRadius = 44,
	SuddenDeathEndRadius = 8,
	SuddenDeathDamage = { Handler = 5, Nightmare = 12 }, -- per second outside the zone
	PrepTime = 12, -- choose a saved build between rounds
	CountdownTime = 3,
	BetweenRoundsTime = 4,
	ResultsTime = 8, -- results screen before returning to the Forge
	RequestTimeout = 20,
	RequestCooldown = 4, -- seconds between challenges from the same player
	BestOfOptions = { 1, 3 },
	-- Team duels (Phase 6): party leader vs party leader, both parties the same size.
	MinTeamSize = 2,
	MaxTeamSize = 3, -- 2v2 and 3v3
	TeamBestOf = 3,
	TeamSpawnSpacing = 7, -- studs between teammates on a pad
	MaxRoundsBeforeDraw = 5, -- safety valve for drawn rounds
	ArenaOrigin = Vector3.new(0, 1, -1800),
	ArenaSpacing = 300,
	ArenaRadius = 48,
	MaxArenas = 10,
	-- Rewards (Friendly duels never change ranked rating — ranked arrives in Phase 6)
	Rewards = {
		Win = { ArenaTokens = 30, XP = 80, Coins = 20 },
		Loss = { ArenaTokens = 10, XP = 40, Coins = 5 },
		Draw = { ArenaTokens = 15, XP = 50, Coins = 10 },
	},
	MinMatchSecondsForRewards = 30, -- instant forfeits pay nothing (anti-farming)
	MaxRewardedMatchesPerHour = 12,
}

------------------------------------------------------------------------------------------
-- Remote rate limits (token buckets, per player)
------------------------------------------------------------------------------------------
Config.RateLimits = {
	CombatAction = { Capacity = 12, RefillPerSecond = 8 },
	NightmareCommand = { Capacity = 8, RefillPerSecond = 4 },
	BuildRequest = { Capacity = 6, RefillPerSecond = 2 },
	BossRequest = { Capacity = 4, RefillPerSecond = 1 },
	TutorialAction = { Capacity = 3, RefillPerSecond = 1 },
	DuelRequest = { Capacity = 6, RefillPerSecond = 1.5 },
	CraftRequest = { Capacity = 5, RefillPerSecond = 2 },
	PartyRequest = { Capacity = 6, RefillPerSecond = 1.5 },
	ShowcaseRequest = { Capacity = 6, RefillPerSecond = 2 },
	GymRequest = { Capacity = 6, RefillPerSecond = 1.5 },
	ShopRequest = { Capacity = 6, RefillPerSecond = 1.5 },
}

return Config
