--[[
	Config  (ModuleScript)
	Location: ReplicatedStorage/Shared/Config

	Central balancing & tuning. EVERY gameplay number lives here so nobody has to hunt
	through service code to rebalance. It is shared so the client can DISPLAY the same
	numbers the server ENFORCES. The server never trusts numbers sent back by a client.
]]

local Config = {}

Config.Version = "0.13.0 (the FIGHT)"

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
	PreviewKeyframesInStudio = false,
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
	Guard = { -- (what it stops and how long it holds: Config.Block)
		WalkSpeed = 8,
		BreakWalkSpeed = 5, -- guard broken: slowed
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

-- BLOCKING (BlockService): the guard meter, for Handlers and Nightmares alike. A held guard with
-- nothing hitting it lasts Max / HoldDrain seconds; it starts failing below CrackAt.
Config.Block = {
	Max = 100,
	Startup = 0.15, -- a press isn't protecting you yet (a parry window covers it)
	Reduction = 0.88, -- of a normal blow, while the stance holds
	HeavyReduction = 0.6, -- of a Heavy
	BossReduction = 0.65, -- (boss fights stay as hard as they were tuned)
	BossHeavyReduction = 0.3,
	CrackAt = 40, -- below this the stance fails: Reduction slides down to LeakReduction at 0
	LeakReduction = 0.25,
	HoldDrain = 8.5, -- per second, just holding it up (about 12 s to break untouched)
	HitCost = 2, -- each blow stopped (about 5 s to break under a steady stream of punches)...
	CostPerPercent = 0.4, -- ...plus this per 1% of max health the blow would have done
	HeavyCost = 2, -- x for a Heavy
	GuardBreakCost = 2.2, -- x for a guard-breaking move (GuardBreak strings, some kicks)
	RepressCost = 6, -- pressing again within RegenDelay of letting go
	RegenDelay = 1.3, -- seconds with the guard down before it refills
	RegenPerSecond = 26,
	BrokenTime = 1.3, -- seconds with no guard and no dodge
	AfterBreak = 25, -- what it comes back with, so it isn't instantly broken again
	ArcDot = -0.15, -- hits from outside this of the way it faces (about 100 degrees either side) go through
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
		{ Action = "Combo_SavageExecution", Duration = 2.2, Weight = 2, Tags = { "Grab", "GuardBreak", "Finisher" }, Cost = 28, Arms = true, BothArms = true, Head = true, Legs = true, Clinch = true, Grab = true, Hold = { Reach = 3.5, Height = 1.7, Lift = 3.5, Throw = Vector3.new(3.0, 0, -2.2) }, Throw = "Right", Hits = { { 0.3, 0.3 }, { 0.62, 0.9 }, { 0.94, 1.0 }, { 1.38, 1.8, 30, true, { Lift = 40, Push = 30, Spin = 7 } } } },
		-- CYCLONE DESTROYER (a SIGNATURE: rare; unlocked by beating the Storm Beast): jab,
		-- spinning backfist, leaping double hammerfist
		{ Action = "Combo_CycloneDestroyer", Duration = 2.3, Weight = 3, Tags = { "Signature", "Finisher", "Long" }, Cost = 40, Arms = true, BothArms = true, Legs = true, Unlock = { Boss = "StormBeast" }, Leap = { At = 1.2, Time = 0.3, Max = 5 }, Hits = { { 0.3, 0.5 }, { 0.72, 1.2, 14 }, { 1.58, 2.4, 0, true, { Lift = 50, Push = 18, Spin = 6 } } } },
		-- PREDATOR RUSH (four legs and a head): spring in raking with a forepaw, bite, bite and
		-- wrench, rear up and slam both forepaws down
		{ Action = "Combo_PredatorRush", Duration = 1.9, Weight = 3, Tags = { "Beast", "Rush", "Long", "Finisher" }, Cost = 30, Quad = true, Head = true, Leap = { At = 0.2, Time = 0.22, Max = 8 }, Hits = { { 0.42, 0.7, 4 }, { 0.7, 0.9 }, { 1.0, 1.0, 6 }, { 1.45, 1.6, 30, true } } },
		-- hit[6] options: Radius = a shockwave round the impact (everything inside, the slam
		-- effect), Up = the hit reaches that much higher (blows in the air), Force = always
		-- knocks down. Unlock: Boss / Mutation / Mastery (NightmareAIService:Unlocked).
		-- GROUND BREAKER (unlocked by the Abyssal Maw): low kick, rising knee, leaping
		-- two-fist ground pound with a shockwave
		{ Action = "Combo_GroundBreaker", Duration = 2.3, Weight = 2, Tags = { "Heavy", "Finisher", "GuardBreak" }, Cost = 32, Arms = true, BothArms = true, Legs = true, Unlock = { Boss = "AbyssalMaw" }, Leap = { At = 0.95, Time = 0.37, Max = 5 }, Hits = { { 0.3, 0.5, 4 }, { 0.7, 0.8, 10 }, { 1.32, 1.8, 0, true, { Lift = 36, Push = 10, Spin = 4 }, { Radius = 10, Force = true } } } },
		-- AERIAL CRUSHER (a SIGNATURE, unlocked by the Mirror Warden): launcher uppercut,
		-- flying knee, spike back down
		{ Action = "Combo_AerialCrusher", Duration = 2.0, Weight = 3, Tags = { "Signature", "Finisher" }, Cost = 40, Arms = true, BothArms = true, Legs = true, Unlock = { Boss = "MirrorWarden" }, Leap = { At = 0.45, Time = 0.4, Max = 4 }, Hits = { { 0.36, 0.9, 0, false, { Lift = 40, Push = 6, Spin = 3 }, { Force = true } }, { 0.72, 0.8, 0, false, { Lift = 12, Push = 4, Spin = 2 }, { Up = 7 } }, { 1.08, 1.8, 0, true, { Lift = -45, Push = 8, Spin = 4 }, { Up = 7, Force = true } } } },
		-- TITAN COMBINATION (unlocked by the Scrap Titan): haymaker, body uppercut,
		-- axe-handle smash that cracks the floor
		{ Action = "Combo_TitanCombination", Duration = 2.6, Weight = 2, Tags = { "Heavy", "Long", "Finisher", "GuardBreak" }, Cost = 34, Arms = true, BothArms = true, Legs = true, Unlock = { Boss = "ScrapTitan" }, Hits = { { 0.72, 1.3, 6 }, { 1.1, 1.0, 10 }, { 1.7, 2.2, 30, true, nil, { Radius = 7 } } } },
		-- NIGHTMARE FRENZY (any two arms, legs or not; unlocked by a MUTATED part): six wild
		-- rakes, a roar, a two-handed shove
		{ Action = "Combo_NightmareFrenzy", Duration = 2.3, Weight = 3, Tags = { "Long", "Rush", "Finisher" }, Cost = 34, Arms = true, BothArms = true, Unlock = { Mutation = true }, Hits = { { 0.3, 0.35, 2 }, { 0.48, 0.35, 2 }, { 0.66, 0.35, 2 }, { 0.84, 0.35, 2 }, { 1.02, 0.4, 2 }, { 1.2, 0.45, 4 }, { 1.72, 1.5, 40, true } } },
		-- TENTACLE SLAM (a Shadow Tentacle right arm): wrap them at range, haul in, hoist
		-- high, smash down (Hold.Path: where the tentacle carries them, per beat)
		{ Action = "Combo_TentacleSlam", Duration = 2.2, Weight = 3, Tags = { "Grab", "Finisher" }, Cost = 28, Tentacle = true, Clinch = true, Grab = true, ExtraReach = 1.5, Hold = { Path = { Vector3.new(2.0, 0, -4.6), Vector3.new(0.8, 3.0, -3.6), Vector3.new(1.0, 7.0, -3.0), Vector3.new(1.0, 0, -3.8) } }, Hits = { { 0.32, 0.5 }, { 0.6, 0.4 }, { 0.95, 0.3 }, { 1.25, 2.0, 0, true, { Lift = -40, Push = 6, Spin = 3 }, { Force = true } } } },
		-- BEASTLY ASSAULT (four legs): ram, left rake, right rake, spin and buck
		{ Action = "Combo_BeastlyAssault", Duration = 2.3, Weight = 3, Tags = { "Beast", "Rush", "Long", "Finisher" }, Cost = 30, Quad = true, Leap = { At = 0.15, Time = 0.2, Max = 6 }, Hits = { { 0.35, 0.9, 8 }, { 0.6, 0.6 }, { 0.85, 0.7, 6 }, { 1.45, 1.7, 42, true } } },
		-- PREDATOR COUNTER (React; four legs and a head): hop out, pounce bite, shake, fling
		{ Action = "Combo_PredatorCounter", Duration = 1.7, Weight = 3, Tags = { "Counter", "Beast" }, Cost = 24, Quad = true, Head = true, Evade = { Time = 0.22, Distance = 2.2 }, Hits = { { 0.55, 0.9 }, { 0.8, 0.6 }, { 1.05, 1.2, 30, true } } },
		-- MASTERED versions (Combo Mastery: 15 finished fights with the base combo; then they
		-- take its place)
		{ Action = "Combo_BrutalBoxerII", Duration = 2.6, Weight = 3, Tags = { "Long", "Finisher" }, Cost = 32, Arms = true, BothArms = true, Legs = true, Unlock = { Mastery = { Action = "Combo_BrutalBoxer", Count = 15 } }, Replaces = "Combo_BrutalBoxer", Hits = { { 0.3, 0.5 }, { 0.55, 0.7, 4 }, { 0.82, 0.8, 8 }, { 1.1, 0.9, 6 }, { 1.32, 0.9, 6 }, { 1.84, 2.0, 36, true } } },
		{ Action = "Combo_PredatorRushII", Duration = 2.6, Weight = 3, Tags = { "Beast", "Rush", "Long", "Finisher" }, Cost = 32, Quad = true, Head = true, Leap = { At = 0.2, Time = 0.22, Max = 8 }, Unlock = { Mastery = { Action = "Combo_PredatorRush", Count = 15 } }, Replaces = "Combo_PredatorRush", Hits = { { 0.42, 0.7, 4 }, { 0.7, 0.9 }, { 1.0, 1.0, 6 }, { 1.45, 1.6, 0, true, nil, { Crumple = true, Force = true } }, { 1.82, 0.9, 0, false, nil, { Chase = 9 } }, { 2.05, 1.1, 25 } } },
		{ Action = "Gym_ComboA", Duration = 1.6, Weight = 3, Tags = { "Light" }, Arms = true, Hits = { { 0.3, 0.55 }, { 0.54, 0.55 }, { 0.8, 0.95, 10 } } }, -- jab, jab, cross
		{ Action = "Gym_ComboB", Duration = 1.8, Weight = 3, Tags = { "Light" }, Arms = true, Hits = { { 0.3, 0.55 }, { 0.56, 0.8, 6 }, { 0.86, 1.05, 16 } } }, -- jab, cross, hook
		{ Action = "Gym_ComboC", Duration = 2.1, Weight = 2, Tags = { "Heavy", "Finisher" }, Arms = true, Hits = { { 0.3, 0.55 }, { 0.58, 0.85, 8 }, { 1.04, 1.6, 32, true } } }, -- jab, hook, OVERHAND
		{ Action = "Gym_BodyRip", Duration = 1.5, Weight = 2, Tags = { "Light", "GuardBreak" }, Arms = true, Hits = { { 0.46, 0.9, 6 }, { 0.74, 1.25, 20 } } }, -- body hook, uppercut
		{ Action = "Gym_OneTwoLow", Duration = 1.7, Weight = 3, Tags = { "Light", "Kick" }, Arms = true, BothArms = true, Legs = true, Hits = { { 0.26, 0.55 }, { 0.5, 0.8, 6 }, { 0.88, 1.15, 10 } } }, -- jab, cross, low kick
		{ Action = "Gym_LiverHead", Duration = 1.6, Weight = 2, Tags = { "Light", "GuardBreak" }, Arms = true, Hits = { { 0.4, 1.0, 4 }, { 0.72, 1.2, 16 } } }, -- left to the liver, left to the jaw
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
	StanceRange = 24, -- studs from its target: hands up, in its fighting stance
	-- WHERE each blow of a string lands, in order (NightmarePoses "Reactions": how the body it
	-- hits takes it). Anything not listed rocks them along the blow's force instead.
	Reactions = {
		Combo1 = { "Jab" },
		Combo2 = { "Cross" },
		Rage_Haymaker = { "HookR" },
		Rage_Elbow = { "Cross" },
		Rage_Uppercut = { "Upper" },
		Rage_Smash = { "Heavy" },
		Rage_GrabSlam = { "Body", "Body", "Heavy" },
		Rage_Leap = { "Heavy" },
		Combo3 = { "HookL" },
		Gym_ComboA = { "Jab", "Jab", "Cross" },
		Gym_ComboB = { "Jab", "Cross", "HookL" },
		Gym_ComboC = { "Jab", "HookL", "Heavy" },
		Gym_OneTwoLow = { "Jab", "Cross", "Leg" },
		Gym_LiverHead = { "Body", "HookL" },
		Gym_BodyRip = { "Body", "Upper" },
		Gym_Power = { "Heavy" },
		Gym_Teep = { "Body" },
		Gym_Roundhouse = { "HookR" },
		Gym_KneeClinch = { "Body", "Body", "Upper" },
		Gym_SpinBackKick = { "Heavy" },
		Beast_Headbutt = { "Cross" },
		Beast_TailWhip = { "HookR" },
		Combo_BrutalBoxer = { "Jab", "Cross", "HookL", "Upper", "Heavy" },
		Combo_BrutalBoxerII = { "Jab", "Cross", "HookL", "Upper", "Body", "Heavy" },
		Combo_PerfectCounter = { "HookL", "Upper", "Body" },
		Combo_SavageExecution = { "Cross", "Cross", "Cross" },
		Combo_CycloneDestroyer = { "Jab", "HookR" },
		Combo_GroundBreaker = { "Leg", "Upper" },
		Combo_TitanCombination = { "HookL", "Body" },
		Combo_NightmareFrenzy = { "HookR", "HookL", "HookR", "HookL", "HookR", "HookL", "Heavy" },
		Combo_PredatorRush = { "HookL", "Cross", "Cross" },
		Combo_PredatorRushII = { "HookL", "Cross", "Cross" },
		Combo_BeastlyAssault = { "Body", "HookL", "HookR" },
		Combo_PredatorCounter = { "Cross", "Cross" },
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
	-- THE GUARD DUMMY (Training Arena): a dummy with its padded arms up that never drops its
	-- guard by itself (BlockService GuardSteady). Blows from the front are blocked like anyone's
	-- guard; break it (heavies, grabs, guard breakers) or go round it (the guard only covers the
	-- front). Broken, the pads fall for Config.Block.BrokenTime and come back up.
	GuardDummy = {
		DisplayName = "Guard Dummy",
		MaxHealth = 600,
		Defence = 0,
		RespawnDelay = 3,
		RegenDelay = 5,
	},
	-- SCRAP BRUTE (the Pit): a big, slow, armoured Scrapling. It winds up an overhead
	-- two-fist SLAM (a long, wide telegraph: dodge, step back or block it) that hits hard and
	-- knocks you flying. A Scrapling's rules (AggroRadius, LeashRadius, StepIn...) otherwise.
	ScrapBrute = {
		DisplayName = "Scrap Brute",
		MaxHealth = 650,
		Defence = 12,
		WalkSpeed = 8,
		AggroRadius = 26,
		LeashRadius = 30,
		AttackRange = 8,
		AttackWidth = 7,
		AttackDamage = 20,
		AttackKnockback = 45,
		AttackWindup = 1.1,
		AttackCooldown = 2.6,
		TrackTurnRate = 110,
		TrackCommit = 0.25,
		StepIn = 2,
		RespawnDelay = 12,
		Scale = 1.7, -- x a Scrapling's build
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
	ArenaCenter = Vector3.new(82, 1, -82), -- Training Arena, NE quarter (World/Hub buildTraining)
	ArenaRadius = 50, -- a round arena, 100 studs across (the old square one was 70)
	ColosseumCenter = Vector3.new(92, 1, 92), -- SE quarter
	-- What's in the arena, in ITS frame: x to the right and z toward the back wall, standing at
	-- the entrance (which faces the hub). TrainingService spawns these; Hub builds round them.
	Arena = {
		-- THE STRIKING RANGE (left): dummies to work combos on, facing the centre aisle
		Dummies = { Vector3.new(-35, 0, -18), Vector3.new(-38, 0, -5), Vector3.new(-38, 0, 8), Vector3.new(-35, 0, 21) },
		RangeFacing = Vector3.new(-12, 0, 2),
		-- the GUARD DUMMY: holds its guard up for good (Config.Block); break it or go round it
		GuardDummy = Vector3.new(-22, 0, 32),
		GuardFacing = Vector3.new(-8, 0, 14),
		-- THE PIT (right): a caged octagon. What's inside only fights what's inside.
		Pit = { Center = Vector3.new(20, 0, 4), Radius = 15 },
		Scraplings = { Vector3.new(-6, 0, -6), Vector3.new(6, 0, -6), Vector3.new(0, 0, 8) }, -- (from the pit's centre)
		Brute = Vector3.new(0, 0, 0),
	},
	ApplyLighting = true,
}

-- The Training Arena's own frame: standing in its entrance looking in (away from the hub),
-- -Z is toward the back wall and +X to the right. Config.World.Arena positions are given
-- with z toward the back wall; ArenaPoint turns one into a world position (on the ground).
function Config.ArenaFrame(): CFrame
	local world = Config.World
	local center = world.ArenaCenter
	local back = Vector3.new(center.X - world.HubCenter.X, 0, center.Z - world.HubCenter.Z).Unit
	return CFrame.lookAt(center, center + back)
end
function Config.ArenaPoint(offset: Vector3): Vector3
	return Config.ArenaFrame() * Vector3.new(offset.X, offset.Y, -offset.Z)
end

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
	-- UNLEASHED: while you drive it, your Nightmare fights with its own heavy-hitting moveset
	-- (NightmareAIService:StartRage), not the companion's. The same keyframed strings as the
	-- wild moveset (Hits = { time, damage x Nightmare.StringDamage, knockback, heavy, launch,
	-- options }), each clip in NightmarePoses ("Rage_*", a four-legged body has its own).
	Rampage = {
		-- ATTACK: each press throws the next blow; pressed again within ResetTime of a blow's
		-- recovery it carries on, else it starts over. A press during a blow is held for the
		-- next one if it comes in the last BufferTime seconds.
		ResetTime = 0.9,
		BufferTime = 0.35,
		Beats = {
			-- a wild right HAYMAKER, the whole body thrown round behind it
			{ Action = "Rage_Haymaker", Duration = 1.0, Recovery = 0.18, Hits = { { 0.36, 1.5, 14 } } },
			-- a lead ELBOW smashed across, stepping in
			{ Action = "Rage_Elbow", Duration = 0.95, Recovery = 0.16, Hits = { { 0.3, 1.4, 8 } } },
			-- a launching UPPERCUT from a deep dip: up off their feet
			{ Action = "Rage_Uppercut", Duration = 1.1, Recovery = 0.22, Hits = { { 0.34, 1.6, 0, false, { Lift = 40, Push = 8, Spin = 3 }, { Force = true, Up = 4 } } } },
			-- both fists overhead and DOWN into the floor: a shockwave
			{ Action = "Rage_Smash", Duration = 1.4, Recovery = 0.4, Display = "Combo_Rampage", Tags = { "Finisher", "GuardBreak" }, Hits = { { 0.52, 2.4, 30, true, { Lift = 30, Push = 14, Spin = 4 }, { Radius = 9, Force = true } } } },
		},
		-- HEAVY: within reach of something it can lift (Grab: an ordinary enemy; two arms, or
		-- four legs and a head): grab it, hoist it overhead and SLAM it into the floor. Anything
		-- else (out of reach, a boss, a player): a CRUSHING LEAP onto them (or straight ahead)
		-- that lands in a shockwave.
		HeavyCooldown = 2.2,
		Grab = {
			Action = "Rage_GrabSlam", Duration = 1.9, Recovery = 0.4, Display = "Combo_NightmareSlam", Tags = { "Grab", "Finisher", "GuardBreak" },
			Clinch = true, Grab = true, ExtraReach = 1.5, GrabReach = 2.5,
			Hold = { Path = { Vector3.new(0, 0, -3.6), Vector3.new(0, 7.5, -0.8), Vector3.new(0, 0, -4.2) } },
			-- (beat 2 is the top of the lift, arms locked out overhead: the body is carried up
			-- 0.3 -> 0.96 s with the squat and hoist, then driven down in 0.16 s with the slam)
			Hits = { { 0.3, 0.3 }, { 0.96, 0.2 }, { 1.12, 2.8, 0, true, { Lift = -35, Push = 6, Spin = 3 }, { Radius = 10, Force = true } } },
		},
		Leap = {
			Action = "Rage_Leap", Duration = 1.5, Recovery = 0.35, Display = "Combo_CrushingLeap", Tags = { "Rush", "Finisher", "GuardBreak" },
			Leap = { At = 0.2, Time = 0.38, Max = 16, Ahead = 9 },
			Hits = { { 0.6, 2.2, 0, true, { Lift = 42, Push = 16, Spin = 5 }, { Radius = 12, Force = true } } },
		},
		AimRange = 22, -- studs: the enemy in front it goes for (else it strikes the air ahead)
	},
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
-- NIGHTMARE UNDERGROUND (UndergroundService): 1v1 where each player IS their Nightmare.
-- The Handlers watch from their corners; DuelService runs the match (Mode "Underground").
------------------------------------------------------------------------------------------
Config.Underground = {
	BestOf = 3,
	PrepTime = 10, -- pick the Nightmare you'll fight as (PvP-legal builds)
	CountdownTime = 4, -- in your corner, in control, frozen until FIGHT
	RoundTime = 90, -- then a decision
	BetweenRoundsTime = 7, -- the scorecard is up, the knocked-out body stays down this long
	KOCamTime = 2.6, -- after a knockout: the fight camera stays on the body going down
	ResultsTime = 14, -- the results screen, before both players go back to the Forge
	-- every fighter has the same health (and starts every round fresh): a build changes HOW
	-- it fights, not how long it lasts
	FighterHealth = 600,

	-- THE RULES (shown to players: UndergroundController's rules line)
	--   A match is at most BestOf rounds; the first to win 2 wins. A drawn round still counts.
	--   If nobody has 2 after the last round: more rounds won wins; level on rounds, the judge's
	--   points over the whole match decide; within DrawMargin of each other, the match is a DRAW.

	-- KNOCKDOWNS are earned, never random (UndergroundFightService:KnockdownRule). A CLEAN power
	-- shot (not blocked) floors a fighter when it's a COUNTER, when they're GASSED, when they're
	-- HURT (health under HurtHealth), or when it's the LAUNCHER. They're down for the count
	-- (DownTime, + DownTimeStep for each earlier knockdown that round) and can't be hit while
	-- down or for GraceAfter once they're up.
	Knockdown = { HurtHealth = 0.35, DownTime = 2.4, DownTimeStep = 0.6, GraceAfter = 1.0, GetUpTime = 0.9, CountInterval = 0.6 },
	-- TKO: the fight is stopped on a fighter's 3rd knockdown in a round, or on any knockdown
	-- that leaves it under StopHealth of its health (it can't beat the count).
	TKO = { Knockdowns = 3, StopHealth = 0.08 },
	-- THE SCORECARD (UndergroundService:Decide): what a round is judged on. Clean damage is
	-- worth its own number; nothing is scored for swinging at air or for blows that were blocked.
	-- A round within DrawMargin points is drawn (10 — 10).
	Score = { Landed = 1, Counter = 8, Parry = 5, Slip = 3, Combo = 4, Knockdown = 40 },
	KnockdownPoints = 40,
	DrawMargin = 5,
	-- the arenas: closed halls high above the map, out of sight of the hub
	ArenaOrigin = Vector3.new(0, 400, -2400),
	ArenaSpacing = 260,
	MaxArenas = 6,
	RingHalf = 24, -- the fighting area inside the ropes: 48 x 48 studs
	CornerInset = 15, -- where each fighter starts, from the centre along the diagonal
	Rewards = Config.PvP.Rewards,

	-- THE FIGHT (UndergroundFightService): how a fighter you're driving fights. Its own moveset,
	-- not the possession RAMPAGE: single strikes you chain yourself, by input.
	Fight = {
		-- STAMINA (attribute UGStamina on the body): every strike costs it, body shots taken
		-- drain it. It comes back after RegenDelay without throwing (slower behind a guard). At 0
		-- the fighter is GASSED: strikes land for GassedDamage, no power shots until it's back
		-- over Recovered.
		Stamina = { Max = 100, RegenDelay = 0.7, Regen = 18, GuardRegen = 7, GassedDamage = 0.6, Recovered = 30, BlockedCost = 3 },
		-- a string carries on if the next press comes within ResetTime of the last blow's
		-- recovery; a press in the last BufferTime of a blow is held for it
		ResetTime = 0.6,
		BufferTime = 0.3,
		-- PARRY: a guard raised within Window before a blow lands knocks it away: no damage,
		-- the attacker is stunned AttackerStun (no guard, no strike), and the parrier's next
		-- strike within CounterWindow is a COUNTER. Re-raising within Lockout doesn't parry
		-- (no mashing the guard).
		Parry = { Window = 0.2, Lockout = 0.5, AttackerStun = 0.75, StaminaGain = 10 },
		-- SLIP (dodge + a direction): head off the line, i-frames for Invulnerable. A blow that
		-- whiffs through a slip gives a COUNTER window. Speed / Time: the body's burst.
		Slip = {
			Cooldown = 0.75, Invulnerable = 0.28, Cost = 8,
			Side = { Speed = 32, Time = 0.16, Action = "UG_Slip" }, -- left / right
			Back = { Speed = 40, Time = 0.18, Action = "PullBack" }, -- pull straight back
			In = { Speed = 30, Time = 0.16, Action = "RollUnder" }, -- duck under, stepping in
		},
		CounterWindow = 0.8,
		CounterDamage = 1.35, -- x, for a strike thrown in a counter window
		-- FEINT: raise the guard during a power shot's wind-up (up to FeintBefore s before it
		-- lands) to pull it: costs Cost stamina, back in your stance in Recover.
		Feint = { Cost = 10, FeintBefore = 0.1, Recover = 0.18, Action = "UG_Feint" },
		-- GUARD HEIGHT: the guard covers the head; guard while pulling BACK on the stick to
		-- drop it to the body. A blow at the other height goes round it.
		-- STRIKES: StartString defs (Hits = { time, damage x Nightmare.StringDamage, knockback,
		-- heavy, launch, options }) plus Cost (stamina), Height ("Head" / "Body"), Drain (body
		-- shots: stamina taken off them), Power (a power shot: can be feinted, needs stamina).
		Moves = {
			Biped = {
				UG_Jab = { Action = "UG_Jab", Duration = 0.62, Recovery = 0.1, Display = "JAB", Cost = 5, Height = "Head", Hits = { { 0.2, 0.7, 4 } } },
				UG_Cross = { Action = "UG_Cross", Duration = 0.72, Recovery = 0.14, Display = "CROSS", Cost = 8, Height = "Head", Hits = { { 0.26, 1.0, 8 } } },
				UG_HookL = { Action = "UG_HookL", Duration = 0.8, Recovery = 0.16, Display = "LEAD HOOK", Cost = 10, Height = "Head", Hits = { { 0.3, 1.2, 10 } } },
				UG_Uppercut = { Action = "UG_Uppercut", Duration = 0.85, Recovery = 0.2, Display = "UPPERCUT", Cost = 11, Height = "Head", Hits = { { 0.32, 1.3, 6, false, nil, { Up = 2 } } } },
				UG_LiverHook = { Action = "UG_LiverHook", Duration = 0.85, Recovery = 0.18, Display = "LIVER SHOT", Cost = 11, Height = "Body", Drain = 16, Hits = { { 0.32, 1.1, 6 } } },
				UG_Overhand = { Action = "UG_Overhand", Duration = 1.15, Recovery = 0.32, Display = "OVERHAND", Cost = 18, Height = "Head", Power = true, Tags = { "GuardBreak" }, Hits = { { 0.5, 2.0, 22, true } } },
				UG_Launcher = { Action = "UG_Launcher", Duration = 1.1, Recovery = 0.36, Display = "LAUNCHER", Cost = 20, Height = "Head", Power = true, Tags = { "Finisher" }, Hits = { { 0.44, 2.2, 0, true, { Lift = 34, Push = 8, Spin = 3 }, { Force = true, Up = 3 } } } },
				UG_BodyBlast = { Action = "UG_BodyBlast", Duration = 1.05, Recovery = 0.3, Display = "BODY BLAST", Cost = 16, Height = "Body", Drain = 24, Power = true, Tags = { "GuardBreak" }, Hits = { { 0.42, 1.7, 16, true } } },
			},
			-- four legs: rakes, a headbutt, a rear-up and a crashing smash (the same buttons)
			Quadruped = {
				UG_Jab = { Action = "Rage_Haymaker", Duration = 1.0, Recovery = 0.12, Display = "RAKE", Cost = 7, Height = "Head", Hits = { { 0.36, 0.9, 6 } } },
				UG_Cross = { Action = "Rage_Elbow", Duration = 0.95, Recovery = 0.12, Display = "CROSS RAKE", Cost = 9, Height = "Head", Hits = { { 0.3, 1.05, 8 } } },
				UG_HookL = { Action = "Beast_Headbutt", Duration = 1.0, Recovery = 0.16, Display = "HEADBUTT", Cost = 11, Height = "Head", Hits = { { 0.4, 1.25, 12 } } },
				UG_Uppercut = { Action = "Rage_Uppercut", Duration = 1.1, Recovery = 0.2, Display = "REAR UP", Cost = 12, Height = "Head", Hits = { { 0.34, 1.3, 0, false, { Lift = 28, Push = 6, Spin = 2 }, { Up = 4 } } } },
				UG_LiverHook = { Action = "Beast_Headbutt", Duration = 1.0, Recovery = 0.16, Display = "GUT RAM", Cost = 11, Height = "Body", Drain = 16, Hits = { { 0.4, 1.1, 10 } } },
				UG_Overhand = { Action = "Rage_Smash", Duration = 1.4, Recovery = 0.3, Display = "CRASH DOWN", Cost = 18, Height = "Head", Power = true, Tags = { "GuardBreak" }, Hits = { { 0.52, 2.0, 22, true } } },
				UG_Launcher = { Action = "Rage_Uppercut", Duration = 1.1, Recovery = 0.3, Display = "LAUNCHER", Cost = 20, Height = "Head", Power = true, Tags = { "Finisher" }, Hits = { { 0.34, 2.2, 0, true, { Lift = 34, Push = 8, Spin = 3 }, { Force = true, Up = 4 } } } },
				UG_BodyBlast = { Action = "Beast_TailWhip", Duration = 1.2, Recovery = 0.3, Display = "TAIL WHIP", Cost = 16, Height = "Body", Drain = 24, Power = true, Tags = { "GuardBreak" }, Hits = { { 0.52, 1.7, 16, true } } },
			},
		},
		-- INPUT STRINGS: L = attack (click / R2 / ATTACK), H = power (right-click / X / KICK).
		-- Each press extends the string you're in; anything not listed starts over from it.
		Strings = {
			L = "UG_Jab", LL = "UG_Cross", LLL = "UG_HookL", LLLL = "UG_Uppercut",
			H = "UG_Overhand", LH = "UG_LiverHook", LHL = "UG_HookL", LLH = "UG_Overhand", LLLH = "UG_Launcher", LHH = "UG_BodyBlast",
		},
		-- what the string reads as when it lands (combo callouts)
		Names = {
			LL = "ONE-TWO", LLL = "ONE-TWO-THREE", LLLL = "FOUR-PIECE", LH = "JAB TO THE BODY", LHL = "BODY-HEAD",
			LLH = "ONE-TWO-OVERHAND", LLLH = "THREE AND THE LAUNCHER", LHH = "DIG TO THE BODY",
		},
		Ends = { LLLL = true, LLLH = true, LHL = true, LLH = true, LHH = true, H = true },
		PowerCooldown = 0.9, -- after a power shot, before the next one
	},
}

-- how each Underground strike lands on the body it hits (NightmarePoses Reactions)
do
	local reactions = Config.Nightmare.Reactions
	for action, react in { UG_Jab = "Jab", UG_Cross = "Cross", UG_HookL = "HookL", UG_Uppercut = "Upper", UG_LiverHook = "Body", UG_Overhand = "Heavy", UG_Launcher = "Upper", UG_BodyBlast = "Body" } do
		reactions[action] = reactions[action] or { react }
	end
end

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
