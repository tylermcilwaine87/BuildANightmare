--[[
	PartDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/PartDefinitions

	Data-driven definitions for every Nightmare part. Adding a part = adding one entry.

	COORDINATES
	  * Creatures face -Z (Roblox LookVector). +Y is up. +X is the creature's right.
	  * Every part's Visual pieces are positioned relative to its JOINT (the socket it
	    plugs into). Cores define Sockets (joint positions for every other slot).
	  * Arm parts are authored as RIGHT arms. The LeftArm slot mirrors them.
	  * Groups are sub-joints (e.g. each leg, each wing) so they can animate separately.

	PLACEHOLDER ART
	  Visual = list of primitive pieces built at runtime. To replace a part with real art,
	  put a Model in ReplicatedStorage/Assets/PartModels named after the part's ModelAsset
	  value, with its pivot at the joint and facing -Z. The assembler uses it automatically.

	FIELDS (spec section 32)
	  Id, DisplayName, Rarity, Slot, Description, ModelAsset, AttachmentType, Movement
	  (legs only), Compat (allowed archetypes, nil = all), Stats, PowerCost, AbilityId
	  (nil until Phase 2/3), PlannedAbility (text shown in UI), Passive, Source,
	  Crafting (Phase 5), AnimationSet, SoundId, EffectId, Sockets (cores), Groups, Visual
]]

local PartDefinitions = {}
PartDefinitions.ById = {}

local V = Vector3.new
local RGB = Color3.fromRGB
local Mat = Enum.Material
local ZERO = Vector3.zero

------------------------------------------------------------------------------------------
-- Piece helpers
------------------------------------------------------------------------------------------
local function piece(shape, size, pos, color, material, extra)
	local p = {
		Shape = shape,
		Size = size,
		Pos = pos,
		Rot = ZERO, -- degrees, applied as CFrame.Angles(X, Y, Z)
		Color = color,
		Material = material or Mat.SmoothPlastic,
		Transparency = 0,
	}
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function block(size, pos, color, material, extra)
	return piece("Block", size, pos, color, material, extra)
end

local function ball(diameter, pos, color, material, extra)
	return piece("Ball", V(diameter, diameter, diameter), pos, color, material, extra)
end

-- Cylinders run along local X. Use Rot = V(0, 0, 90) for vertical, V(0, 90, 0) for depth.
local function cyl(length, diameter, pos, color, material, extra)
	return piece("Cylinder", V(length, diameter, diameter), pos, color, material, extra)
end

-- Wedge slope faces forward (-Z) and up.
local function wedge(size, pos, color, material, extra)
	return piece("Wedge", size, pos, color, material, extra)
end

local function mirrorPiece(p, group)
	local c = table.clone(p)
	c.Pos = V(-p.Pos.X, p.Pos.Y, p.Pos.Z)
	c.Rot = V(p.Rot.X, -p.Rot.Y, -p.Rot.Z)
	c.Group = group
	return c
end

-- Builds a left/right pair of sub-joints (legs, wings). rightPieces are authored for the
-- RIGHT side relative to the right pivot; the left side is mirrored automatically.
local function symmetric(pivot: Vector3, rot: Vector3, rightPieces, sharedPieces)
	local groups = {
		R = { Pivot = pivot, Rot = rot },
		L = { Pivot = V(-pivot.X, pivot.Y, pivot.Z), Rot = V(rot.X, -rot.Y, -rot.Z) },
	}
	local visual = {}
	for _, p in rightPieces do
		local c = table.clone(p)
		c.Group = "R"
		table.insert(visual, c)
	end
	for _, p in rightPieces do
		table.insert(visual, mirrorPiece(p, "L"))
	end
	for _, p in sharedPieces or {} do
		table.insert(visual, p)
	end
	return groups, visual
end

-- Four legs (Quadruped): authored as the FRONT-RIGHT leg relative to its hip pivot;
-- the same piece list is reused for back-right and mirrored for the left legs.
local function quad(front: Vector3, back: Vector3, rightPieces)
	local groups = {
		FR = { Pivot = front },
		FL = { Pivot = V(-front.X, front.Y, front.Z) },
		BR = { Pivot = back },
		BL = { Pivot = V(-back.X, back.Y, back.Z) },
	}
	local visual = {}
	for _, group in { "FR", "BR" } do
		for _, p in rightPieces do
			local c = table.clone(p)
			c.Group = group
			table.insert(visual, c)
		end
	end
	for _, group in { "FL", "BL" } do
		for _, p in rightPieces do
			table.insert(visual, mirrorPiece(p, group))
		end
	end
	return groups, visual
end
------------------------------------------------------------------------------------------
-- define()
------------------------------------------------------------------------------------------
local REQUIRED = { "Id", "DisplayName", "Rarity", "Slot", "PowerCost", "Visual" }

local function define(def)
	for _, key in REQUIRED do
		assert(def[key] ~= nil, ("Part definition missing %s (%s)"):format(key, tostring(def.Id)))
	end
	assert(PartDefinitions.ById[def.Id] == nil, "Duplicate part id " .. def.Id)
	if def.Slot == "Core" then
		assert(def.Sockets, "Core parts need Sockets: " .. def.Id)
	end
	if def.Slot == "Legs" then
		assert(def.Movement, "Legs parts need a Movement archetype: " .. def.Id)
	end

	def.Description = def.Description or ""
	def.AttachmentType = def.AttachmentType or "Socket"
	def.ModelAsset = def.ModelAsset or def.Id -- optional art override (see header)
	def.Stats = def.Stats or {}
	def.AbilityId = def.AbilityId -- nil in Phase 1: abilities arrive in Phase 2/3
	def.PlannedAbility = def.PlannedAbility or "None"
	def.Passive = def.Passive
	def.Source = def.Source or "Starter"
	def.Crafting = def.Crafting -- recipes live in Shared/CraftingDefinitions
	def.AnimationSet = def.AnimationSet or "Default"
	def.SoundId = def.SoundId or "" -- PLACEHOLDER: add rbxassetid:// when audio exists
	def.EffectId = def.EffectId or ""
	def.Equippable = def.Equippable ~= false

	PartDefinitions.ById[def.Id] = def
end

------------------------------------------------------------------------------------------
-- CORES
------------------------------------------------------------------------------------------
define({
	Id = "WoodenBody",
	DisplayName = "Wooden Body",
	Rarity = "Uncommon",
	Slot = "Core",
	Description = "A splintery crate that somehow has a heartbeat. Cheap, sturdy, and slightly haunted.",
	Stats = { MaxHealth = 40, Defence = 6 },
	PowerCost = 10,
	PlannedAbility = "Low-cost defence",
	UltimateId = "SplinterStorm",
	Sockets = {
		Head = V(0, 1.5, 0),
		RightArm = V(1.55, 0.8, 0),
		LeftArm = V(-1.55, 0.8, 0),
		Legs = V(0, -1.5, 0),
		Back = V(0, 0.5, 1.0),
		Tail = V(0, -1.0, 1.0),
	},
	Visual = {
		block(V(3, 3, 2), V(0, 0, 0), RGB(124, 92, 60), Mat.WoodPlanks),
		block(V(3.2, 0.4, 2.2), V(0, 1.2, 0), RGB(90, 64, 42), Mat.Wood),
		block(V(3.2, 0.4, 2.2), V(0, -1.2, 0), RGB(90, 64, 42), Mat.Wood),
		ball(0.5, V(0.6, 0.3, -1.0), RGB(60, 42, 28), Mat.Wood),
		block(V(0.12, 1.4, 0.1), V(-0.7, -0.1, -1.02), RGB(40, 28, 20), Mat.Wood, { Rot = V(0, 0, 20) }),
	},
})

define({
	Id = "PeeperOrb",
	DisplayName = "Peeper Orb",
	Rarity = "Uncommon",
	Slot = "Core",
	Description = "One enormous, unblinking eye. It has never lost a staring contest.",
	Stats = { MaxHealth = -20, AttackSpeed = 8, MoveSpeed = 1 },
	PowerCost = 7,
	PlannedAbility = "Glare (brief slow)",
	UltimateId = "ThousandEyeGlare",
	Sockets = {
		Head = V(0, 1.55, 0),
		RightArm = V(1.55, 0, 0),
		LeftArm = V(-1.55, 0, 0),
		Legs = V(0, -1.6, 0),
		Back = V(0, 0.4, 1.4),
		Tail = V(0, -0.6, 1.4),
	},
	Visual = {
		ball(3.2, V(0, 0, 0), RGB(240, 236, 228)),
		ball(1.7, V(0, 0.05, -0.85), RGB(60, 130, 220)),
		ball(0.9, V(0, 0.05, -1.35), RGB(15, 15, 20), Mat.SmoothPlastic),
		ball(0.3, V(0.2, 0.3, -1.72), RGB(255, 255, 255), Mat.Neon),
		block(V(0.08, 1.2, 0.08), V(1.05, 0.6, -0.95), RGB(200, 40, 50), Mat.SmoothPlastic, { Rot = V(0, 0, 40) }),
		block(V(0.08, 1.0, 0.08), V(-1.1, -0.5, -0.9), RGB(200, 40, 50), Mat.SmoothPlastic, { Rot = V(0, 0, -50) }),
	},
})

define({
	Id = "ReinforcedCore",
	DisplayName = "Reinforced Core",
	Rarity = "Rare",
	Slot = "Core",
	Description = "Riveted plating salvaged from the Rusted Expanse. Built to take a beating.",
	Stats = { MaxHealth = 90, Defence = 14, MoveSpeed = -1, StaggerResist = 20 },
	PowerCost = 22,
	AbilityId = "ReinforcedGuard",
	UltimateId = "BastionQuake",
	Source = "The Scrap Titan",
	Sockets = {
		Head = V(0, 1.6, 0),
		RightArm = V(1.75, 0.9, 0),
		LeftArm = V(-1.75, 0.9, 0),
		Legs = V(0, -1.6, 0),
		Back = V(0, 0.6, 1.2),
		Tail = V(0, -1.1, 1.2),
	},
	Visual = {
		block(V(3.4, 3.2, 2.4), V(0, 0, 0), RGB(99, 102, 110), Mat.DiamondPlate),
		block(V(3.6, 0.6, 2.6), V(0, 1.0, 0), RGB(70, 72, 80), Mat.Metal),
		block(V(2, 0.3, 0.1), V(0, 0.2, -1.25), RGB(80, 220, 255), Mat.Neon),
		ball(0.35, V(1.4, -1.2, -1.2), RGB(150, 150, 160), Mat.Metal),
		ball(0.35, V(-1.4, -1.2, -1.2), RGB(150, 150, 160), Mat.Metal),
		ball(0.35, V(1.4, 0.55, -1.2), RGB(150, 150, 160), Mat.Metal),
		ball(0.35, V(-1.4, 0.55, -1.2), RGB(150, 150, 160), Mat.Metal),
	},
})

define({
	Id = "ReactorHeart",
	DisplayName = "Reactor Heart",
	Rarity = "Legendary",
	Slot = "Core",
	Description = "The still-burning heart of the Scrap Titan. It hums. It is warm. It should not be touched.",
	Stats = { MaxHealth = 110, AttackPower = 15, Defence = 8 },
	PowerCost = 38,
	AbilityId = "EnergyOverload",
	UltimateId = "ScrapApocalypse",
	Source = "The Scrap Titan / The Mirror Warden",
	Sockets = {
		Head = V(0, 1.75, 0),
		RightArm = V(1.8, 0.5, 0),
		LeftArm = V(-1.8, 0.5, 0),
		Legs = V(0, -1.7, 0),
		Back = V(0, 0.6, 1.6),
		Tail = V(0, -1.0, 1.6),
	},
	Visual = {
		ball(3.4, V(0, 0, 0), RGB(45, 45, 55), Mat.Metal),
		ball(2.2, V(0, 0, -0.75), RGB(255, 170, 40), Mat.Neon),
		cyl(0.3, 4.3, V(0, 0, 0), RGB(255, 200, 70), Mat.Metal, { Rot = V(0, 0, 90) }),
		block(V(0.6, 1, 0.6), V(1.2, 1.3, 0), RGB(70, 70, 80), Mat.Metal),
		block(V(0.6, 1, 0.6), V(-1.2, 1.3, 0), RGB(70, 70, 80), Mat.Metal),
		ball(0.4, V(1.2, 1.9, 0), RGB(255, 170, 40), Mat.Neon),
		ball(0.4, V(-1.2, 1.9, 0), RGB(255, 170, 40), Mat.Neon),
	},
})

------------------------------------------------------------------------------------------
-- HEADS (joint at the neck, head extends upward)
------------------------------------------------------------------------------------------
define({
	Id = "CrackedSkull",
	DisplayName = "Cracked Skull",
	Rarity = "Uncommon",
	Slot = "Head",
	Description = "Seen better centuries. Still bites.",
	Stats = { MaxHealth = 10, AttackPower = 3 },
	PowerCost = 5,
	AbilityId = "Bite",
	Visual = {
		ball(2.2, V(0, 1.2, 0), RGB(230, 225, 205)),
		block(V(1.6, 0.6, 1.4), V(0, 0.35, -0.25), RGB(215, 208, 185)),
		ball(0.55, V(0.45, 1.35, -0.85), RGB(20, 18, 22)),
		ball(0.55, V(-0.45, 1.35, -0.85), RGB(20, 18, 22)),
		block(V(0.1, 0.8, 0.1), V(0.3, 1.85, -0.85), RGB(70, 60, 50), Mat.SmoothPlastic, { Rot = V(0, 0, 25) }),
	},
})

define({
	Id = "ElectricJaw",
	DisplayName = "Electric Jaw",
	Rarity = "Rare",
	Slot = "Head",
	Description = "A clattering metal jaw that crackles every time it closes.",
	Stats = { AttackPower = 10, AttackSpeed = 5 },
	PowerCost = 14,
	AbilityId = "ChargedBite",
	OnHit = { Status = "Shock", Chance = 1, ComboHit = 3 }, -- combo finisher shocks
	Source = "The Storm Beast",
	Visual = {
		block(V(2, 1.4, 1.9), V(0, 1.15, 0), RGB(80, 90, 110), Mat.Metal),
		block(V(1.8, 0.5, 1.7), V(0, 0.25, -0.15), RGB(65, 72, 90), Mat.Metal, { Rot = V(-12, 0, 0) }),
		block(V(1.6, 0.2, 0.2), V(0, 0.62, -0.95), RGB(255, 240, 90), Mat.Neon),
		block(V(0.5, 0.2, 0.1), V(0.5, 1.4, -0.96), RGB(90, 230, 255), Mat.Neon),
		block(V(0.5, 0.2, 0.1), V(-0.5, 1.4, -0.96), RGB(90, 230, 255), Mat.Neon),
		cyl(1, 0.15, V(0, 2.35, 0), RGB(60, 60, 70), Mat.Metal, { Rot = V(0, 0, 90) }),
		ball(0.45, V(0, 2.9, 0), RGB(255, 240, 90), Mat.Neon),
	},
})

define({
	Id = "FrostHorns",
	DisplayName = "Frost Horns",
	Rarity = "Rare",
	Slot = "Head",
	Description = "A frozen head crowned with horns that never melt.",
	Stats = { MaxHealth = 20, Defence = 4, AttackPower = 4 },
	PowerCost = 12,
	AbilityId = "FrostRam",
	OnHit = { Status = "Chill", Chance = 0.5, ComboHit = 3 },
	Source = "Crafting Forge / The Mirror Warden",
	Visual = {
		ball(2, V(0, 1.1, 0), RGB(175, 215, 240), Mat.Ice),
		block(V(0.35, 1.6, 0.35), V(0.75, 2.25, 0), RGB(210, 240, 255), Mat.Ice, { Rot = V(0, 0, -25) }),
		block(V(0.35, 1.6, 0.35), V(-0.75, 2.25, 0), RGB(210, 240, 255), Mat.Ice, { Rot = V(0, 0, 25) }),
		ball(0.4, V(0.4, 1.2, -0.85), RGB(120, 240, 255), Mat.Neon),
		ball(0.4, V(-0.4, 1.2, -0.85), RGB(120, 240, 255), Mat.Neon),
	},
})

------------------------------------------------------------------------------------------
-- ARMS (authored as RIGHT arms: joint at the shoulder, arm hangs down / outward)
------------------------------------------------------------------------------------------
define({
	Id = "RustyClaw",
	DisplayName = "Rusty Claw",
	Rarity = "Uncommon",
	Slot = "Arm",
	Description = "Squeaks on every swing. Tetanus not included.",
	Stats = { AttackPower = 6 },
	PowerCost = 6,
	AbilityId = "RustySlash",
	Source = "Starter / The Scrap Titan",
	AnimationSet = "Claw",
	Visual = {
		ball(0.9, V(0.2, 0, 0), RGB(150, 85, 50), Mat.CorrodedMetal),
		block(V(0.6, 2.0, 0.6), V(0.45, -1.0, 0), RGB(150, 85, 50), Mat.CorrodedMetal, { Rot = V(0, 0, 10) }),
		block(V(0.8, 0.6, 0.9), V(0.6, -2.1, 0), RGB(120, 70, 40), Mat.CorrodedMetal),
		block(V(0.18, 0.8, 0.18), V(0.6, -2.75, -0.3), RGB(190, 180, 170), Mat.Metal),
		block(V(0.18, 0.8, 0.18), V(0.6, -2.75, 0), RGB(190, 180, 170), Mat.Metal),
		block(V(0.18, 0.8, 0.18), V(0.6, -2.75, 0.3), RGB(190, 180, 170), Mat.Metal),
	},
})

define({
	Id = "ShadowTentacle",
	DisplayName = "Shadow Tentacle",
	Rarity = "Rare",
	Slot = "Arm",
	Description = "A coil of living darkness. Reaches further than you expect.",
	Stats = { AttackPower = 7, AttackSpeed = -5, Reach = 2 },
	PowerCost = 13,
	AbilityId = "TentacleLash",
	OnHit = { Status = "Weaken", Chance = 0.3, ComboHit = 3 },
	Source = "The Abyssal Maw",
	AnimationSet = "Tentacle",
	Visual = {
		ball(0.9, V(0.4, -0.5, 0), RGB(45, 25, 70)),
		ball(0.8, V(0.7, -1.2, -0.1), RGB(50, 28, 78)),
		ball(0.7, V(0.9, -1.9, -0.3), RGB(55, 30, 86)),
		ball(0.6, V(1.0, -2.6, -0.5), RGB(60, 33, 94)),
		ball(0.5, V(1.0, -3.2, -0.8), RGB(65, 36, 102)),
		ball(0.35, V(1.0, -3.6, -1.0), RGB(180, 90, 255), Mat.Neon),
	},
})

define({
	Id = "DemonicClaws",
	DisplayName = "Demonic Claws",
	Rarity = "Epic",
	Slot = "Arm",
	Description = "Blades that glow brighter the angrier their owner gets.",
	Stats = { AttackPower = 16, MaxHealth = -10, AttackSpeed = -5, Reach = 1 },
	PowerCost = 21,
	AbilityId = "DemonRend",
	OnHit = { Status = "Burn", Chance = 1, ComboHit = 3 },
	Source = "Crafting Forge / The Storm Beast",
	AnimationSet = "Claw",
	Visual = {
		block(V(0.3, 1.1, 0.3), V(0.3, 0.7, 0), RGB(25, 20, 25), Mat.Slate, { Rot = V(0, 0, -20) }),
		block(V(0.9, 2.4, 0.9), V(0.55, -1.1, 0), RGB(130, 25, 35), Mat.Slate, { Rot = V(0, 0, 8) }),
		block(V(1.1, 0.7, 1.1), V(0.7, -2.5, 0), RGB(90, 15, 25), Mat.Slate),
		block(V(0.15, 1.6, 0.25), V(0.7, -3.6, -0.4), RGB(255, 60, 40), Mat.Neon),
		block(V(0.15, 1.6, 0.25), V(0.7, -3.6, 0), RGB(255, 60, 40), Mat.Neon),
		block(V(0.15, 1.6, 0.25), V(0.7, -3.6, 0.4), RGB(255, 60, 40), Mat.Neon),
	},
})

------------------------------------------------------------------------------------------
-- LEGS (joint at the hips; decides the movement archetype)
------------------------------------------------------------------------------------------
do
	local jelly = RGB(110, 225, 140)
	local groups, visual = symmetric(V(0.8, 0, 0), ZERO, {
		ball(1.1, V(0, -0.45, 0), jelly, Mat.SmoothPlastic, { Transparency = 0.1 }),
		block(V(0.85, 2.0, 0.85), V(0, -1.5, 0), jelly, Mat.SmoothPlastic, { Transparency = 0.1 }),
		block(V(1.1, 0.5, 1.4), V(0, -2.65, -0.2), RGB(80, 190, 110)),
	})
	define({
		Id = "JellyLegs",
		DisplayName = "Jelly Legs",
		Rarity = "Uncommon",
		Slot = "Legs",
		Movement = "Biped",
		Description = "Wobbly, bouncy, and surprisingly reliable.",
		Stats = { MoveSpeed = 1, MaxHealth = 10 },
		PowerCost = 6,
		PlannedAbility = "Bouncy movement",
		Groups = groups,
		Visual = visual,
	})
end

define({
	Id = "DriftingWisp",
	DisplayName = "Drifting Wisp",
	Rarity = "Uncommon",
	Slot = "Legs",
	Movement = "Floating",
	Description = "Who needs legs? A trail of ghost-light keeps this Nightmare aloft.",
	Stats = { MoveSpeed = 1, MaxHealth = -10 },
	PowerCost = 6,
	PlannedAbility = "Hover (floating archetype)",
	Visual = {
		ball(1.2, V(0, -0.7, 0), RGB(150, 220, 255), Mat.Neon, { Transparency = 0.25 }),
		ball(0.7, V(0, -1.5, 0), RGB(150, 220, 255), Mat.Neon, { Transparency = 0.45 }),
		ball(0.35, V(0, -2.1, 0), RGB(150, 220, 255), Mat.Neon, { Transparency = 0.6 }),
	},
})

do
	local phantom = RGB(150, 120, 230)
	local groups, visual = symmetric(V(0.85, 0, 0), ZERO, {
		block(V(0.7, 1.5, 0.7), V(0, -0.8, 0), phantom, Mat.SmoothPlastic, { Transparency = 0.3 }),
		block(V(0.55, 1.6, 0.55), V(0, -2.3, 0.1), phantom, Mat.SmoothPlastic, { Transparency = 0.3 }),
		ball(0.4, V(0, -3.0, 0.1), RGB(200, 160, 255), Mat.Neon),
		wedge(V(0.7, 0.5, 1.1), V(0, -3.3, -0.25), phantom, Mat.SmoothPlastic, { Transparency = 0.3 }),
	})
	define({
		Id = "PhantomLegs",
		DisplayName = "Phantom Legs",
		Rarity = "Epic",
		Slot = "Legs",
		Movement = "Biped",
		Description = "Half here, half somewhere else. Very hard to pin down.",
		Stats = { MoveSpeed = 4, AttackSpeed = 6, MaxHealth = -15 },
		PowerCost = 19,
		PlannedAbility = "Afterimage dash",
		Source = "The Mirror Warden / The Abyssal Maw",
		Groups = groups,
		Visual = visual,
	})
end

------------------------------------------------------------------------------------------
-- BACK (joint on the core's back)
------------------------------------------------------------------------------------------
do
	local groups, visual = symmetric(V(0.3, 0.2, 0.1), V(0, -20, 15), {
		block(V(1.6, 1.1, 0.1), V(0.85, 0, 0), RGB(60, 40, 75)),
		block(V(1.8, 0.15, 0.18), V(0.9, 0.55, 0), RGB(35, 25, 40)),
	})
	define({
		Id = "TinyBatWings",
		DisplayName = "Tiny Bat Wings",
		Rarity = "Uncommon",
		Slot = "Back",
		Description = "Far too small to fly with. They flap anyway.",
		Stats = { MoveSpeed = 1 },
		PowerCost = 4,
		AbilityId = "BatDive",
		Groups = groups,
		Visual = visual,
	})
end

do
	local groups, visual = symmetric(V(0.4, 0.3, 0.2), V(0, -25, 18), {
		block(V(3.2, 2.2, 0.12), V(1.7, 0, 0), RGB(25, 12, 45)),
		block(V(3.4, 0.15, 0.15), V(1.75, 1.1, 0), RGB(170, 90, 255), Mat.Neon),
		wedge(V(0.15, 0.8, 0.5), V(3.3, -0.9, 0), RGB(170, 90, 255), Mat.Neon),
	}, {
		block(V(0.8, 0.8, 0.4), V(0, 0.2, 0.1), RGB(30, 20, 45), Mat.Slate),
	})
	define({
		Id = "VoidWings",
		DisplayName = "Void Wings",
		Rarity = "Epic",
		Slot = "Back",
		Description = "Wings cut from the space between stars.",
		Stats = { MoveSpeed = 2, AttackSpeed = 6, Defence = 3 },
		PowerCost = 17,
		AbilityId = "BlinkDash",
		UltimateId = "VoidCollapse", -- signature: overrides the Core's ultimate
		Source = "Crafting Forge / The Abyssal Maw",
		Groups = groups,
		Visual = visual,
	})
end

------------------------------------------------------------------------------------------
-- TAIL (joint at the core's lower back, extends backward / +Z)
------------------------------------------------------------------------------------------
define({
	Id = "BentMetalTail",
	DisplayName = "Bent Metal Tail",
	Rarity = "Uncommon",
	Slot = "Tail",
	Description = "A length of exhaust pipe with opinions.",
	Stats = { Defence = 2, AttackPower = 2 },
	PowerCost = 5,
	AbilityId = "TailSweep",
	Visual = {
		block(V(0.6, 0.6, 1.4), V(0, -0.1, 0.7), RGB(110, 115, 125), Mat.Metal),
		block(V(0.5, 0.5, 1.4), V(0.25, -0.35, 1.95), RGB(100, 104, 112), Mat.Metal, { Rot = V(10, 25, 0) }),
		wedge(V(0.4, 0.5, 0.8), V(0.6, -0.5, 2.9), RGB(170, 175, 185), Mat.Metal, { Rot = V(0, 205, 0) }),
	},
})

------------------------------------------------------------------------------------------
-- PHASE 2 ADDITIONS: Scrap Titan loot pool + extras
------------------------------------------------------------------------------------------
define({
	Id = "CrystalShell",
	DisplayName = "Crystal Shell",
	Rarity = "Rare",
	Slot = "Core",
	Description = "A geode that grew a heartbeat. Glitters menacingly.",
	Stats = { MaxHealth = 60, Defence = 10 },
	PowerCost = 18,
	AbilityId = "CrystalBarrier",
	UltimateId = "CrystalCataclysm",
	Source = "Crafting Forge / The Mirror Warden",
	Sockets = {
		Head = V(0, 1.6, 0),
		RightArm = V(1.6, 0.6, 0),
		LeftArm = V(-1.6, 0.6, 0),
		Legs = V(0, -1.6, 0),
		Back = V(0, 0.5, 1.2),
		Tail = V(0, -1.0, 1.2),
	},
	Visual = {
		ball(3.2, V(0, 0, 0), RGB(90, 70, 130), Mat.Slate),
		block(V(0.9, 1.8, 0.9), V(0.6, 0.6, -1.1), RGB(170, 120, 255), Mat.Glass, { Rot = V(-20, 0, -15), Transparency = 0.2 }),
		block(V(0.7, 1.4, 0.7), V(-0.7, 0.3, -1.1), RGB(120, 200, 255), Mat.Glass, { Rot = V(-25, 0, 20), Transparency = 0.2 }),
		block(V(0.8, 1.6, 0.8), V(0, 1.2, 0.6), RGB(170, 120, 255), Mat.Glass, { Rot = V(25, 0, 10), Transparency = 0.2 }),
		ball(0.8, V(0, -0.2, -1.35), RGB(200, 160, 255), Mat.Neon),
	},
})

define({
	Id = "ScrapVisor",
	DisplayName = "Scrap Visor",
	Rarity = "Uncommon",
	Slot = "Head",
	Description = "A welding mask with a single, very bright eye.",
	Stats = { Defence = 4, AttackPower = 2 },
	PowerCost = 6,
	AbilityId = "ScrapVisorBeam",
	Source = "The Scrap Titan",
	Visual = {
		block(V(2, 1.6, 1.8), V(0, 1.0, 0), RGB(85, 85, 95), Mat.DiamondPlate),
		block(V(1.6, 0.35, 0.15), V(0, 1.15, -0.95), RGB(255, 120, 40), Mat.Neon),
		block(V(2.2, 0.2, 2.0), V(0, 1.85, 0), RGB(120, 70, 40), Mat.CorrodedMetal),
		cyl(0.6, 0.3, V(0.9, 0.5, 0), RGB(60, 60, 68), Mat.Metal),
	},
})

define({
	Id = "MagneticClaw",
	DisplayName = "Magnetic Claw",
	Rarity = "Rare",
	Slot = "Arm",
	Description = "A crane grabber with a horseshoe magnet bolted on. Things stick to it. Enemies especially.",
	Stats = { AttackPower = 8, Defence = 3 },
	PowerCost = 13,
	AbilityId = "MagnetPull",
	Source = "The Scrap Titan",
	AnimationSet = "Claw",
	Visual = {
		ball(0.9, V(0.2, 0, 0), RGB(90, 95, 105), Mat.Metal),
		block(V(0.6, 2.0, 0.6), V(0.45, -1.0, 0), RGB(200, 160, 40), Mat.Metal, { Rot = V(0, 0, 10) }),
		block(V(1.4, 0.4, 0.5), V(0.6, -2.15, 0), RGB(200, 40, 40), Mat.SmoothPlastic),
		block(V(0.4, 0.9, 0.5), V(0.05, -2.75, 0), RGB(200, 40, 40), Mat.SmoothPlastic),
		block(V(0.4, 0.9, 0.5), V(1.15, -2.75, 0), RGB(200, 40, 40), Mat.SmoothPlastic),
		block(V(0.42, 0.25, 0.52), V(0.05, -3.2, 0), RGB(220, 220, 230), Mat.Metal),
		block(V(0.42, 0.25, 0.52), V(1.15, -3.2, 0), RGB(220, 220, 230), Mat.Metal),
	},
})

define({
	Id = "TitanHammerArm",
	DisplayName = "Titan Hammer Arm",
	Rarity = "Epic",
	Slot = "Arm",
	Description = "Torn straight off the Scrap Titan. Heavy enough to make the floor nervous.",
	Stats = { AttackPower = 14, MaxHealth = 20, AttackSpeed = -10, MoveSpeed = -1, StaggerPower = 25 },
	PowerCost = 22,
	AbilityId = "HammerSlam",
	Source = "The Scrap Titan",
	AnimationSet = "Hammer",
	Visual = {
		ball(1.1, V(0.3, 0, 0), RGB(70, 70, 80), Mat.Metal),
		block(V(0.9, 2.2, 0.9), V(0.6, -1.1, 0), RGB(110, 80, 60), Mat.CorrodedMetal, { Rot = V(0, 0, 8) }),
		cyl(0.8, 0.5, V(0.75, -2.5, 0), RGB(60, 60, 70), Mat.Metal, { Rot = V(0, 0, 90) }),
		block(V(2.4, 1.3, 1.4), V(0.75, -3.3, 0), RGB(80, 82, 92), Mat.DiamondPlate),
		block(V(0.2, 1.0, 1.0), V(1.97, -3.3, 0), RGB(255, 140, 40), Mat.Neon),
		block(V(0.2, 1.0, 1.0), V(-0.47, -3.3, 0), RGB(255, 140, 40), Mat.Neon),
	},
})

do
	local scrap, bolt = RGB(105, 90, 75), RGB(150, 150, 160)
	local groups, visual = symmetric(V(0.85, 0, 0), ZERO, {
		cyl(1.6, 0.7, V(0, -0.8, 0), scrap, Mat.CorrodedMetal, { Rot = V(0, 0, 90) }),
		ball(0.7, V(0, -1.65, 0), bolt, Mat.Metal),
		cyl(1.3, 0.55, V(0, -2.35, 0), scrap, Mat.CorrodedMetal, { Rot = V(0, 0, 90) }),
		block(V(1.0, 0.45, 1.5), V(0, -3.1, -0.25), RGB(60, 60, 66), Mat.Metal),
	})
	define({
		Id = "ScrapLegs",
		DisplayName = "Scrap Legs",
		Rarity = "Uncommon",
		Slot = "Legs",
		Movement = "Biped",
		Description = "Two exhaust pipes and a lot of optimism.",
		Stats = { MaxHealth = 25, Defence = 3, StaggerResist = 10 },
		PowerCost = 7,
		PlannedAbility = "Sturdy stance (passive)",
		Source = "The Scrap Titan",
		Groups = groups,
		Visual = visual,
	})
end

------------------------------------------------------------------------------------------
-- PHASE 3: Quadruped legs
------------------------------------------------------------------------------------------
do
	local fur, paw = RGB(120, 90, 60), RGB(70, 50, 35)
	local groups, visual = quad(V(1.1, 0, -1.0), V(1.1, 0, 1.0), {
		block(V(0.65, 1.4, 0.65), V(0, -0.7, 0), fur, Mat.Fabric),
		block(V(0.8, 0.4, 1.0), V(0, -1.55, -0.15), paw, Mat.Fabric),
	})
	define({
		Id = "MangyHoundLegs",
		DisplayName = "Mangy Hound Legs",
		Rarity = "Uncommon",
		Slot = "Legs",
		Movement = "Quadruped",
		Description = "Four scruffy legs that never stop running. Smells faintly of wet dog.",
		Stats = { MoveSpeed = 2, MaxHealth = 15 },
		PowerCost = 7,
		PlannedAbility = "Four-legged sprint (Quadruped)",
		Source = "Starter",
		Groups = groups,
		Visual = visual,
	})
end

do
	local shell, glow = RGB(40, 25, 50), RGB(120, 255, 90)
	local groups, visual = quad(V(1.0, 0.2, -0.8), V(1.0, 0.2, 0.8), {
		block(V(0.3, 1.7, 0.3), V(0.55, 0.35, 0), shell, Mat.Slate, { Rot = V(0, 0, -55) }),
		block(V(0.25, 2.5, 0.25), V(1.35, -0.95, 0), shell, Mat.Slate, { Rot = V(0, 0, 12) }),
		ball(0.35, V(1.6, -2.15, 0), glow, Mat.Neon),
	})
	define({
		Id = "VenomousSpiderLegs",
		DisplayName = "Venomous Spider Legs",
		Rarity = "Rare",
		Slot = "Legs",
		Movement = "Quadruped",
		Description = "Long, twitchy legs dripping with something green. Every hit leaves venom behind.",
		Stats = { MoveSpeed = 3, AttackSpeed = 5, MaxHealth = -10 },
		PowerCost = 15,
		PlannedAbility = "Venom: every basic hit poisons (stacks to 5)",
		OnHit = { Status = "Poison", Chance = 1 },
		Source = "The Scrap Titan / The Storm Beast",
		Groups = groups,
		Visual = visual,
	})
end
------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------
function PartDefinitions.Get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return PartDefinitions.ById[id]
end

-- All equippable parts for a PartSlot ("Core", "Head", "Arm", "Legs", "Back", "Tail").
function PartDefinitions.ForPartSlot(partSlot: string)
	local list = {}
	for _, def in PartDefinitions.ById do
		if def.Slot == partSlot and def.Equippable then
			table.insert(list, def)
		end
	end
	return list
end

return PartDefinitions
