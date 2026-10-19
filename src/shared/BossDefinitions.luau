--[[
	BossDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/BossDefinitions

	Display + balance data for every boss. The SERVER rolls loot from LootPool using
	Config.Loot odds; the client only displays this. Adding a boss = one entry here plus
	a behaviour module in ServerScriptService/Server/Services/Bosses/<Id>.

	Modes:
	  Tutorial   forgiving, shortened, guaranteed Rare, not pity-eligible
	  Normal     standard
	  Hard       unlocked by beating Normal: tougher, better odds, x1.5 rewards
	  Nightmare  unlocked by beating Hard: much tougher, a twist, best odds, x2.25 rewards
	Mode fields: HealthMultiplier, DamageMultiplier, WindupMultiplier (floored by
	Config.Bosses.MinWindup), AttackDelayMultiplier, Overdrive, PhaseThresholds (overrides
	the boss's), ExtraSlams / BarrageBonus (boss-specific twists).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BossDefinitions = {}

BossDefinitions.ById = {
	ScrapTitan = {
		Id = "ScrapTitan",
		DisplayName = "THE SCRAP TITAN",
		Title = "Lord of the Rusted Expanse",
		Area = "The Titan's Foundry",
		Difficulty = 1, -- skulls, 1..5
		RecommendedPower = 50,
		Codex = "A giant built from discarded machines, car parts and chains. When its reactor overheats it enters OVERDRIVE.",
		Tips = {
			"Red circles show where it will slam. Step out, then punish the long recovery.",
			"Blue ring = MAGNET PULL. Dodge out or guard before the sweep.",
			"Below 50% health it enters OVERDRIVE: faster attacks and double slams.",
			"Heavy hits fill its STAGGER bar. When it's full, the Titan is stunned. Go all in!",
		},
		MaxHealth = 4500,
		Defence = 10,
		StaggerMax = 300, -- heavy hits & abilities can stagger it: free punish window
		WalkSpeed = 9,
		HitboxSize = Vector3.new(9, 13, 7),
		PhaseThresholds = { 0.5 }, -- Overdrive at 50%
		Modes = {
			Tutorial = { HealthMultiplier = 0.3, DamageMultiplier = 0.55, WindupMultiplier = 1.3, AttackDelayMultiplier = 1.2, Overdrive = false },
			Normal = { HealthMultiplier = 1.0, DamageMultiplier = 1.0, WindupMultiplier = 1.0, AttackDelayMultiplier = 1.0, Overdrive = true },
			Hard = { HealthMultiplier = 1.6, DamageMultiplier = 1.3, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.85, Overdrive = true },
			-- Twist: double slams from the start (triple in Overdrive), bigger barrages,
			-- Overdrive at 60%.
			Nightmare = { HealthMultiplier = 2.4, DamageMultiplier = 1.6, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.7, Overdrive = true, PhaseThresholds = { 0.6 }, ExtraSlams = 1, BarrageBonus = 3 },
		},
		ModeTips = {
			Hard = "HARD: more health, harder hits, faster attacks.",
			Nightmare = "NIGHTMARE: it slams twice from the start, fires bigger barrages and overheats at 60% health.",
		},
		Arena = "Junkyard",
		LootPool = {
			Uncommon = { "RustyClaw", "ScrapLegs", "ScrapVisor" },
			Rare = { "ReinforcedCore", "MagneticClaw", "VenomousSpiderLegs" },
			Epic = { "TitanHammerArm" },
			Legendary = { "ReactorHeart" },
		},
	},

	MirrorWarden = {
		Id = "MirrorWarden",
		DisplayName = "THE MIRROR WARDEN",
		Title = "Keeper of the Hall of Reflections",
		Area = "The Hall of Reflections",
		Difficulty = 2,
		RecommendedPower = 70,
		Codex = "A crystal knight with a mirror for a face, sworn to guard the Hall of Reflections. Every blow it strikes echoes across the hall.",
		Tips = {
			"Mirror Combo: three red boxes in front of it, one after another. Step to the side, then punish.",
			"Reflected Slam hits where you stand AND at the mirror-image spot across the hall. Check both red circles.",
			"Shatter Nova blasts everything close to it. Back off when the ring appears.",
			"At 50% the mirror CRACKS: 4-way slams, more shards, and a crossing Prism Beam.",
		},
		ModeTips = {
			Hard = "HARD: more health, harder hits, faster attacks.",
			Nightmare = "NIGHTMARE: 4-way reflected slams from the start, more shards, and it cracks at 60% health.",
		},
		-- Unlocked by beating the Scrap Titan on Normal or harder (see IsBossUnlocked).
		RequiresBoss = "ScrapTitan",
		Arena = "MirrorHall",
		MaxHealth = 5200,
		Defence = 12,
		StaggerMax = 340,
		WalkSpeed = 10,
		HitboxSize = Vector3.new(9, 13, 7),
		PhaseThresholds = { 0.5 }, -- "THE MIRROR CRACKS" at 50%
		Modes = {
			Normal = { HealthMultiplier = 1.0, DamageMultiplier = 1.0, WindupMultiplier = 1.0, AttackDelayMultiplier = 1.0, Overdrive = true },
			Hard = { HealthMultiplier = 1.6, DamageMultiplier = 1.3, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.85, Overdrive = true },
			Nightmare = { HealthMultiplier = 2.4, DamageMultiplier = 1.6, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.7, Overdrive = true, PhaseThresholds = { 0.6 }, ExtraReflections = true, BarrageBonus = 3 },
		},
		LootPool = {
			Uncommon = { "PeeperOrb", "DriftingWisp", "JellyLegs" },
			Rare = { "FrostHorns", "CrystalShell" },
			Epic = { "PhantomLegs" },
			Legendary = { "ReactorHeart" },
		},
	},
}

BossDefinitions.ById.StormBeast = {
	Id = "StormBeast",
	DisplayName = "THE STORM BEAST",
	Title = "Tyrant of the Storm Cliffs",
	Area = "The Tempest Summit",
	Difficulty = 3,
	RecommendedPower = 80,
	Codex = "A beast of living lightning that hunts the Storm Cliffs from the Tempest Summit. It never stands still: it pounces, and wherever it lands, the storm follows.",
	Tips = {
		"Thunder Pounce: a red circle appears under you, then it LANDS there. Move out, then punish it.",
		"Chain Lightning jumps between players and SHOCKS them. Spread out so it can't chain.",
		"Thunderstorm: bolts strike all over the plateau. Watch the small circles and keep moving.",
		"At 50% it's SUPERCHARGED: double pounces and a Static Nova blast around itself.",
	},
	ModeTips = {
		Hard = "HARD: more health, harder hits, faster attacks.",
		Nightmare = "NIGHTMARE: it pounces twice from the start, the storm is bigger, and it supercharges at 60%.",
	},
	RequiresBoss = "MirrorWarden",
	Arena = "ThunderPlateau",
	MaxHealth = 6000,
	Defence = 12,
	StaggerMax = 380,
	WalkSpeed = 15, -- fast hunter
	HitboxSize = Vector3.new(10, 9, 14),
	PhaseThresholds = { 0.5 }, -- "SUPERCHARGED!"
	Modes = {
		Normal = { HealthMultiplier = 1.0, DamageMultiplier = 1.0, WindupMultiplier = 1.0, AttackDelayMultiplier = 1.0, Overdrive = true },
		Hard = { HealthMultiplier = 1.6, DamageMultiplier = 1.3, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.85, Overdrive = true },
		Nightmare = { HealthMultiplier = 2.4, DamageMultiplier = 1.6, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.7, Overdrive = true, PhaseThresholds = { 0.6 }, ExtraPounces = 1, BarrageBonus = 4 },
	},
	LootPool = {
		Uncommon = { "BentMetalTail", "TinyBatWings", "DriftingWisp" },
		Rare = { "ElectricJaw", "VenomousSpiderLegs" },
		Epic = { "DemonicClaws" },
		Legendary = { "ReactorHeart" },
	},
}

BossDefinitions.ById.AbyssalMaw = {
	Id = "AbyssalMaw",
	DisplayName = "THE ABYSSAL MAW",
	Title = "The Hunger Beneath",
	Area = "The Maw Cathedral",
	Difficulty = 4,
	RecommendedPower = 90,
	Codex = "Something enormous lives beneath the Maw Cathedral: all teeth and tentacles. It hunts from below, and it is always hungry.",
	Tips = {
		"Burrow & Erupt: it sinks out of sight, then bursts up under someone. Move off the red circle!",
		"Tentacle Slam: long red lines lash toward players. Step sideways, not backwards.",
		"Abyssal Inhale: the blue ring pulls everyone in, then it bites. Dodge or guard before the bite.",
		"Ink Spit WEAKENS you (less damage) for a few seconds. At 50% THE ABYSS OPENS: dark pools keep hurting anyone inside.",
	},
	ModeTips = {
		Hard = "HARD: more health, harder hits, faster attacks.",
		Nightmare = "NIGHTMARE: more ink, bigger abyss pools, and the abyss opens at 60%.",
	},
	RequiresBoss = "StormBeast",
	Arena = "SunkenAbyss",
	MaxHealth = 7000,
	Defence = 16,
	StaggerMax = 420,
	WalkSpeed = 7, -- slow above ground; it travels by burrowing
	HitboxSize = Vector3.new(12, 16, 12),
	PhaseThresholds = { 0.5 }, -- "THE ABYSS OPENS!"
	Modes = {
		Normal = { HealthMultiplier = 1.0, DamageMultiplier = 1.0, WindupMultiplier = 1.0, AttackDelayMultiplier = 1.0, Overdrive = true },
		Hard = { HealthMultiplier = 1.6, DamageMultiplier = 1.3, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.85, Overdrive = true },
		Nightmare = { HealthMultiplier = 2.4, DamageMultiplier = 1.6, WindupMultiplier = 0.9, AttackDelayMultiplier = 0.7, Overdrive = true, PhaseThresholds = { 0.6 }, BarrageBonus = 3, BigPools = true },
	},
	LootPool = {
		Uncommon = { "JellyLegs", "PeeperOrb", "ScrapVisor" },
		Rare = { "ShadowTentacle", "FrostHorns" },
		Epic = { "PhantomLegs", "VoidWings" },
		Legendary = { "ReactorHeart" },
	},
}

-- Display order in the Boss Portal Hall.
BossDefinitions.Order = { "ScrapTitan", "MirrorWarden", "StormBeast", "AbyssalMaw" }

function BossDefinitions.Get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return BossDefinitions.ById[id]
end

-- Wins/best time for one difficulty, from a profile's Bosses[bossId] record.
function BossDefinitions.ModeRecord(record, mode: string)
	local modes = type(record) == "table" and record.Modes
	local entry = type(modes) == "table" and modes[mode]
	return type(entry) == "table" and entry or { Wins = 0 }
end

-- Total wins on Normal or harder (tutorial wins don't count).
function BossDefinitions.RealWins(record): number
	local total = 0
	for _, mode in Config.Difficulties.Order do
		total += BossDefinitions.ModeRecord(record, mode).Wins or 0
	end
	return total
end

-- Can this boss be fought at all? (e.g. the Mirror Warden needs a Scrap Titan win.)
function BossDefinitions.IsBossUnlocked(bossRecords, bossId: string): (boolean, string?)
	local boss = BossDefinitions.Get(bossId)
	if not boss then
		return false, "Unknown boss."
	end
	if not boss.RequiresBoss then
		return true, nil
	end
	if Config.Dev.UnlockAllDifficultiesInStudio and RunService:IsStudio() then
		return true, nil
	end
	local record = type(bossRecords) == "table" and bossRecords[boss.RequiresBoss]
	if BossDefinitions.RealWins(record) > 0 then
		return true, nil
	end
	local required = BossDefinitions.Get(boss.RequiresBoss)
	return false, ("Defeat %s (Normal or harder) to unlock."):format(required and required.DisplayName or boss.RequiresBoss)
end

-- Shared by the server (enforces) and the portal (displays). `bossRecords` is the
-- profile's Bosses table. Returns ok, reason.
function BossDefinitions.IsModeUnlocked(bossRecords, bossId: string, mode: string): (boolean, string?)
	local boss = BossDefinitions.Get(bossId)
	local difficulty = Config.Difficulties[mode]
	if not boss or not difficulty or not boss.Modes[mode] then
		return false, "That difficulty doesn't exist."
	end
	local required = difficulty.Requires
	if not required then
		return true, nil
	end
	if Config.Dev.UnlockAllDifficultiesInStudio and RunService:IsStudio() then
		return true, nil
	end
	local record = type(bossRecords) == "table" and bossRecords[bossId]
	if (BossDefinitions.ModeRecord(record, required).Wins or 0) > 0 then
		return true, nil
	end
	return false, ("Beat %s on %s to unlock."):format(boss.DisplayName, Config.Difficulties[required].DisplayName)
end

return BossDefinitions
