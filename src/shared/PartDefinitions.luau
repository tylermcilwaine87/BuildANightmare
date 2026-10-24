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

local Passives = require(script.Parent:WaitForChild("PassiveDefinitions"))

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
	-- Passive: an always-on effect (PassiveDefinitions id); the UI line describes it
	def.Passive = def.Passive
	def.PlannedAbility = (def.Passive and Passives.Describe(def.Passive)) or def.PlannedAbility or "None"
	def.Source = def.Source or "Starter"
	def.Crafting = def.Crafting -- recipes live in Shared/CraftingDefinitions
	def.AnimationSet = def.AnimationSet or "Default"
	def.SoundId = def.SoundId or "" -- PLACEHOLDER: add rbxassetid:// when audio exists
	def.EffectId = def.EffectId or ""
	def.Equippable = def.Equippable ~= false
	-- Exclusive = true: a SHOP part (MonetizationDefinitions). Never drops, never
	-- dismantled; owning its pass tops it back up. Same PowerCost rules as everything else.
	def.Exclusive = def.Exclusive == true

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
	Passive = "Splinters",
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
	Passive = "Glare",
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
	-- A real hinged JAW (sub-joint "Sub_Head_Jaw", hinge at the back of the jaw): the bite
	-- animation drops it open, snaps it shut on contact. -X on the joint opens it.
	Groups = { Jaw = { Pivot = V(0, 0.6, 0.3) } },
	Visual = {
		ball(2.2, V(0, 1.2, 0), RGB(230, 225, 205)),
		ball(0.55, V(0.45, 1.35, -0.85), RGB(20, 18, 22)),
		ball(0.55, V(-0.45, 1.35, -0.85), RGB(20, 18, 22)),
		block(V(0.1, 0.8, 0.1), V(0.3, 1.85, -0.85), RGB(70, 60, 50), Mat.SmoothPlastic, { Rot = V(0, 0, 25) }),
		-- inside of the mouth (only shows when the jaw drops) and the upper teeth
		block(V(1.25, 0.32, 0.95), V(0, 0.52, -0.38), RGB(80, 22, 28)),
		block(V(0.17, 0.24, 0.14), V(-0.42, 0.5, -0.86), RGB(245, 240, 225)),
		block(V(0.17, 0.26, 0.14), V(-0.14, 0.49, -0.9), RGB(245, 240, 225)),
		block(V(0.17, 0.26, 0.14), V(0.14, 0.49, -0.9), RGB(245, 240, 225)),
		block(V(0.17, 0.24, 0.14), V(0.42, 0.5, -0.86), RGB(245, 240, 225)),
		-- the jaw itself and its lower teeth
		block(V(1.6, 0.6, 1.4), V(0, -0.25, -0.55), RGB(215, 208, 185), Mat.SmoothPlastic, { Group = "Jaw" }),
		block(V(0.16, 0.22, 0.13), V(-0.3, 0.15, -1.15), RGB(245, 240, 225), Mat.SmoothPlastic, { Group = "Jaw" }),
		block(V(0.16, 0.22, 0.13), V(0, 0.15, -1.18), RGB(245, 240, 225), Mat.SmoothPlastic, { Group = "Jaw" }),
		block(V(0.16, 0.22, 0.13), V(0.3, 0.15, -1.15), RGB(245, 240, 225), Mat.SmoothPlastic, { Group = "Jaw" }),
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
	-- hinged metal jaw (Sub_Head_Jaw): it drops open crackling and slams shut on the bite
	Groups = { Jaw = { Pivot = V(0, 0.5, 0.55) } },
	Visual = {
		block(V(2, 1.4, 1.9), V(0, 1.15, 0), RGB(80, 90, 110), Mat.Metal),
		-- the jaw (and its steel fangs)
		block(V(1.8, 0.5, 1.7), V(0, -0.25, -0.7), RGB(65, 72, 90), Mat.Metal, { Rot = V(-12, 0, 0), Group = "Jaw" }),
		wedge(V(0.22, 0.3, 0.22), V(-0.45, 0.1, -1.4), RGB(200, 205, 215), Mat.Metal, { Rot = V(0, 180, 0), Group = "Jaw" }),
		wedge(V(0.22, 0.3, 0.22), V(0.45, 0.1, -1.4), RGB(200, 205, 215), Mat.Metal, { Rot = V(0, 180, 0), Group = "Jaw" }),
		-- inside the mouth: a charged glow you only see when it opens
		block(V(1.5, 0.3, 1.2), V(0, 0.45, -0.3), RGB(60, 150, 255), Mat.Neon, { Transparency = 0.25 }),
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
	-- an ELBOW (Sub_<Slot>_Fore): the forearm and claw bend on it (pieces relative to it)
	Groups = { Fore = { Pivot = V(0.5, -1.0, 0) } },
	AnimationSet = "Claw",
	Visual = {
		ball(0.9, V(0.2, 0, 0), RGB(150, 85, 50), Mat.CorrodedMetal),
		block(V(0.6, 1.05, 0.6), V(0.38, -0.5, 0), RGB(150, 85, 50), Mat.CorrodedMetal, { Rot = V(0, 0, 10) }),
		ball(0.62, V(0.5, -1.0, 0), RGB(120, 70, 40), Mat.CorrodedMetal),
		block(V(0.55, 1.05, 0.55), V(0.05, -0.5, 0), RGB(150, 85, 50), Mat.CorrodedMetal, { Rot = V(0, 0, 10), Group = "Fore" }),
		block(V(0.8, 0.6, 0.9), V(0.1, -1.1, 0), RGB(120, 70, 40), Mat.CorrodedMetal, { Group = "Fore" }),
		block(V(0.18, 0.8, 0.18), V(0.1, -1.75, -0.3), RGB(190, 180, 170), Mat.Metal, { Group = "Fore" }),
		block(V(0.18, 0.8, 0.18), V(0.1, -1.75, 0), RGB(190, 180, 170), Mat.Metal, { Group = "Fore" }),
		block(V(0.18, 0.8, 0.18), V(0.1, -1.75, 0.3), RGB(190, 180, 170), Mat.Metal, { Group = "Fore" }),
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
	-- a second bend halfway down (Sub_<Slot>_Fore): the tentacle can curl, wrap and whip
	Groups = { Fore = { Pivot = V(0.8, -1.55, -0.2) } },
	Visual = {
		ball(0.9, V(0.4, -0.5, 0), RGB(45, 25, 70)),
		ball(0.8, V(0.7, -1.2, -0.1), RGB(50, 28, 78)),
		ball(0.7, V(0.1, -0.35, -0.1), RGB(55, 30, 86), Mat.SmoothPlastic, { Group = "Fore" }),
		ball(0.6, V(0.2, -1.05, -0.3), RGB(60, 33, 94), Mat.SmoothPlastic, { Group = "Fore" }),
		ball(0.5, V(0.2, -1.65, -0.6), RGB(65, 36, 102), Mat.SmoothPlastic, { Group = "Fore" }),
		ball(0.35, V(0.2, -2.05, -0.8), RGB(180, 90, 255), Mat.Neon, { Group = "Fore" }),
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
	Groups = { Fore = { Pivot = V(0.58, -1.1, 0) } }, -- elbow
	Visual = {
		block(V(0.3, 1.1, 0.3), V(0.3, 0.7, 0), RGB(25, 20, 25), Mat.Slate, { Rot = V(0, 0, -20) }),
		block(V(0.9, 1.25, 0.9), V(0.5, -0.5, 0), RGB(130, 25, 35), Mat.Slate, { Rot = V(0, 0, 8) }),
		ball(0.85, V(0.58, -1.1, 0), RGB(90, 15, 25), Mat.Slate),
		block(V(0.85, 1.25, 0.85), V(0.04, -0.6, 0), RGB(130, 25, 35), Mat.Slate, { Rot = V(0, 0, 8), Group = "Fore" }),
		block(V(1.1, 0.7, 1.1), V(0.12, -1.4, 0), RGB(90, 15, 25), Mat.Slate, { Group = "Fore" }),
		block(V(0.15, 1.6, 0.25), V(0.12, -2.5, -0.4), RGB(255, 60, 40), Mat.Neon, { Group = "Fore" }),
		block(V(0.15, 1.6, 0.25), V(0.12, -2.5, 0), RGB(255, 60, 40), Mat.Neon, { Group = "Fore" }),
		block(V(0.15, 1.6, 0.25), V(0.12, -2.5, 0.4), RGB(255, 60, 40), Mat.Neon, { Group = "Fore" }),
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
		Passive = "Bouncy",
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
	Passive = "Hover",
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
		Passive = "Afterimage",
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
	Groups = { Fore = { Pivot = V(0.5, -1.0, 0) } }, -- elbow
	Visual = {
		ball(0.9, V(0.2, 0, 0), RGB(90, 95, 105), Mat.Metal),
		block(V(0.6, 1.05, 0.6), V(0.38, -0.5, 0), RGB(200, 160, 40), Mat.Metal, { Rot = V(0, 0, 10) }),
		ball(0.62, V(0.5, -1.0, 0), RGB(90, 95, 105), Mat.Metal),
		block(V(0.55, 1.05, 0.55), V(0.05, -0.5, 0), RGB(200, 160, 40), Mat.Metal, { Rot = V(0, 0, 10), Group = "Fore" }),
		block(V(1.4, 0.4, 0.5), V(0.1, -1.15, 0), RGB(200, 40, 40), Mat.SmoothPlastic, { Group = "Fore" }),
		block(V(0.4, 0.9, 0.5), V(-0.45, -1.75, 0), RGB(200, 40, 40), Mat.SmoothPlastic, { Group = "Fore" }),
		block(V(0.4, 0.9, 0.5), V(0.65, -1.75, 0), RGB(200, 40, 40), Mat.SmoothPlastic, { Group = "Fore" }),
		block(V(0.42, 0.25, 0.52), V(-0.45, -2.2, 0), RGB(220, 220, 230), Mat.Metal, { Group = "Fore" }),
		block(V(0.42, 0.25, 0.52), V(0.65, -2.2, 0), RGB(220, 220, 230), Mat.Metal, { Group = "Fore" }),
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
	Groups = { Fore = { Pivot = V(0.6, -1.1, 0) } }, -- elbow
	Visual = {
		ball(1.1, V(0.3, 0, 0), RGB(70, 70, 80), Mat.Metal),
		block(V(0.9, 1.15, 0.9), V(0.52, -0.55, 0), RGB(110, 80, 60), Mat.CorrodedMetal, { Rot = V(0, 0, 8) }),
		ball(0.9, V(0.6, -1.1, 0), RGB(70, 70, 80), Mat.Metal),
		block(V(0.85, 1.15, 0.85), V(0.08, -0.55, 0), RGB(110, 80, 60), Mat.CorrodedMetal, { Rot = V(0, 0, 8), Group = "Fore" }),
		cyl(0.8, 0.5, V(0.15, -1.4, 0), RGB(60, 60, 70), Mat.Metal, { Rot = V(0, 0, 90), Group = "Fore" }),
		block(V(2.4, 1.3, 1.4), V(0.15, -2.2, 0), RGB(80, 82, 92), Mat.DiamondPlate, { Group = "Fore" }),
		block(V(0.2, 1.0, 1.0), V(1.37, -2.2, 0), RGB(255, 140, 40), Mat.Neon, { Group = "Fore" }),
		block(V(0.2, 1.0, 1.0), V(-1.07, -2.2, 0), RGB(255, 140, 40), Mat.Neon, { Group = "Fore" }),
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
		Passive = "Sturdy",
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
		Passive = "Sprint",
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
-- SHOP EXCLUSIVES (MonetizationDefinitions). Priced in PowerCost like any part of their
-- rarity and power, so they fit the same budget: different, not stronger. Each has its
-- own special attack (AbilityDefinitions) and animation (NightmarePoses).
------------------------------------------------------------------------------------------
do
	local basalt, iron, lava = RGB(92, 70, 64), RGB(130, 100, 84), RGB(255, 110, 30)
	define({
		Id = "InfernoGauntlet",
		DisplayName = "Inferno Gauntlet",
		Rarity = "Epic",
		Slot = "Arm",
		Exclusive = true,
		Description = "A molten-iron arm ending in a fist the size of an anvil. The cracks glow hotter the harder it hits.",
		Stats = { AttackPower = 15, MaxHealth = 10, AttackSpeed = -6 },
		PowerCost = 21,
		AbilityId = "MeteorFist",
		OnHit = { Status = "Burn", Chance = 0.5, ComboHit = 3 },
		Source = "SHOP exclusive (Inferno Gauntlets)",
		AnimationSet = "Hammer",
		Groups = { Fore = { Pivot = V(0.6, -1.55, 0) } }, -- elbow: the forearm and fist bend on it
		Visual = {
			-- shoulder pauldron with a lava seam
			ball(1.2, V(0.3, 0.05, 0), basalt, Mat.Basalt),
			block(V(1.3, 0.25, 1.3), V(0.45, 0.45, 0), iron, Mat.Metal, { Rot = V(0, 0, -18) }),
			block(V(1.0, 0.08, 0.08), V(0.45, 0.2, -0.62), lava, Mat.Neon, { Rot = V(0, 0, -18) }),
			-- upper arm, the elbow, and the forearm cracked with glowing seams
			block(V(0.75, 1.5, 0.75), V(0.5, -0.85, 0), basalt, Mat.Basalt, { Rot = V(0, 0, 6) }),
			block(V(0.08, 1.2, 0.08), V(0.52, -0.85, -0.39), lava, Mat.Neon, { Rot = V(0, 0, 14) }),
			ball(0.9, V(0.6, -1.55, 0), basalt, Mat.Basalt),
			block(V(0.95, 1.2, 0.95), V(0.02, -0.45, 0), iron, Mat.Metal, { Group = "Fore" }),
			block(V(0.08, 0.9, 0.08), V(0.02, -0.45, -0.49), lava, Mat.Neon, { Rot = V(0, 0, -16), Group = "Fore" }),
			block(V(1.05, 0.18, 1.05), V(0.02, -1.0, 0), lava, Mat.Neon, { Group = "Fore" }),
			-- the fist: a heavy block with knuckle spikes and a molten core showing through
			block(V(1.45, 1.25, 1.45), V(0.02, -1.7, 0), basalt, Mat.Basalt, { Group = "Fore" }),
			block(V(1.1, 0.12, 1.5), V(0.02, -1.45, 0), lava, Mat.Neon, { Transparency = 0.1, Group = "Fore" }),
			wedge(V(0.28, 0.4, 0.3), V(-0.38, -2.1, -0.78), iron, Mat.Metal, { Rot = V(-90, 0, 0), Group = "Fore" }),
			wedge(V(0.28, 0.4, 0.3), V(0.02, -2.1, -0.78), iron, Mat.Metal, { Rot = V(-90, 0, 0), Group = "Fore" }),
			wedge(V(0.28, 0.4, 0.3), V(0.42, -2.1, -0.78), iron, Mat.Metal, { Rot = V(-90, 0, 0), Group = "Fore" }),
		},
	})
end

define({
	Id = "DragonSkull",
	DisplayName = "Dragon Skull",
	Rarity = "Epic",
	Slot = "Head",
	Exclusive = true,
	Description = "The horned skull of something that ruled the sky. There is still fire in its throat.",
	Stats = { AttackPower = 9, MaxHealth = 15, Defence = 2 },
	PowerCost = 15,
	AbilityId = "DragonBreath",
	OnHit = { Status = "Burn", Chance = 0.35, ComboHit = 3 },
	Source = "SHOP exclusive",
	-- hinged jaw (Sub_Head_Jaw) like the other skulls: it drops open for the breath
	Groups = { Jaw = { Pivot = V(0, 0.55, 0.45) } },
	Visual = {
		-- cranium and long snout
		block(V(1.9, 1.3, 1.8), V(0, 1.25, 0.1), RGB(205, 190, 165), Mat.SmoothPlastic),
		block(V(1.3, 0.7, 1.6), V(0, 1.05, -1.4), RGB(215, 200, 175), Mat.SmoothPlastic),
		wedge(V(1.3, 0.45, 0.8), V(0, 1.6, -0.95), RGB(195, 180, 155), Mat.SmoothPlastic),
		-- ember eyes and nostrils
		ball(0.42, V(0.62, 1.45, -0.62), RGB(255, 140, 30), Mat.Neon),
		ball(0.42, V(-0.62, 1.45, -0.62), RGB(255, 140, 30), Mat.Neon),
		ball(0.2, V(0.3, 1.3, -2.2), RGB(255, 90, 20), Mat.Neon),
		ball(0.2, V(-0.3, 1.3, -2.2), RGB(255, 90, 20), Mat.Neon),
		-- horns swept back, and a ridge of spines
		block(V(0.3, 0.3, 2.0), V(0.75, 1.95, 1.0), RGB(60, 45, 40), Mat.Slate, { Rot = V(25, -12, 0) }),
		block(V(0.3, 0.3, 2.0), V(-0.75, 1.95, 1.0), RGB(60, 45, 40), Mat.Slate, { Rot = V(25, 12, 0) }),
		wedge(V(0.15, 0.5, 0.5), V(0, 2.05, 0.2), RGB(60, 45, 40), Mat.Slate),
		wedge(V(0.15, 0.45, 0.45), V(0, 1.95, 0.75), RGB(60, 45, 40), Mat.Slate),
		-- the throat glow (seen when the jaw drops) and upper fangs
		block(V(1.0, 0.25, 1.6), V(0, 0.62, -0.9), RGB(255, 120, 30), Mat.Neon, { Transparency = 0.15 }),
		wedge(V(0.15, 0.3, 0.15), V(0.42, 0.55, -2.05), RGB(245, 240, 225), Mat.SmoothPlastic, { Rot = V(180, 0, 0) }),
		wedge(V(0.15, 0.3, 0.15), V(-0.42, 0.55, -2.05), RGB(245, 240, 225), Mat.SmoothPlastic, { Rot = V(180, 0, 0) }),
		-- the jaw and its fangs
		block(V(1.25, 0.45, 2.1), V(0, 0.25, -1.15), RGB(190, 175, 150), Mat.SmoothPlastic, { Group = "Jaw" }),
		wedge(V(0.15, 0.3, 0.15), V(0.4, 0.6, -2.0), RGB(245, 240, 225), Mat.SmoothPlastic, { Group = "Jaw" }),
		wedge(V(0.15, 0.3, 0.15), V(-0.4, 0.6, -2.0), RGB(245, 240, 225), Mat.SmoothPlastic, { Group = "Jaw" }),
	},
})

do
	-- feathers fanning out from each wing's root: deep red at the root to gold at the tips
	-- (solid feathers; only a thin strip along each tip glows, so they read as feathers
	-- rather than one blob of light at night)
	local function feather(length, z, angle, color)
		return block(V(length, 0.5, 0.1), V(length / 2 + 0.3, 0, z), color, Mat.SmoothPlastic, { Rot = V(0, 0, angle) })
	end
	local function tip(length, z, angle)
		local a = math.rad(angle)
		local along = V(math.cos(a), math.sin(a), 0)
		return block(V(length * 0.35, 0.12, 0.12), V(0.3, 0, z) + along * length * 0.82 + V(-math.sin(a), math.cos(a), 0) * 0.22, RGB(255, 220, 90), Mat.Neon, { Rot = V(0, 0, angle) })
	end
	local groups, visual = symmetric(V(0.4, 0.3, 0.2), V(0, -22, 16), {
		block(V(2.6, 0.5, 0.25), V(1.4, 0.35, 0), RGB(150, 30, 20), Mat.SmoothPlastic),
		feather(3.6, 0, 18, RGB(255, 190, 50)),
		feather(3.4, 0.02, 4, RGB(250, 150, 40)),
		feather(3.1, 0.04, -10, RGB(240, 115, 30)),
		feather(2.7, 0.06, -24, RGB(225, 80, 25)),
		feather(2.2, 0.08, -38, RGB(200, 50, 20)),
		tip(3.6, -0.02, 18),
		tip(3.4, 0, 4),
		tip(3.1, 0.02, -10),
	}, {
		ball(0.9, V(0, 0.2, 0.15), RGB(170, 40, 20), Mat.SmoothPlastic),
	})
	define({
		Id = "PhoenixWings",
		DisplayName = "Phoenix Wings",
		Rarity = "Epic",
		Slot = "Back",
		Exclusive = true,
		Description = "Wings of living flame. Every time they fold, they flare back brighter.",
		Stats = { MoveSpeed = 2, AttackPower = 5, MaxHealth = 10 },
		PowerCost = 17,
		AbilityId = "PhoenixDive",
		UltimateId = "Supernova", -- signature: overrides the Core's ultimate
		Source = "SHOP exclusive",
		Groups = groups,
		Visual = visual,
	})
end

define({
	Id = "ObsidianHeart",
	DisplayName = "Obsidian Heart",
	Rarity = "Epic",
	Slot = "Core",
	Exclusive = true,
	Description = "Volcanic glass around a heart of magma. It cracks when struck, and what leaks out burns.",
	Stats = { MaxHealth = 80, Defence = 10, AttackPower = 4 },
	PowerCost = 22,
	AbilityId = "MagmaShell",
	UltimateId = "Eruption",
	Source = "SHOP exclusive",
	Sockets = {
		Head = V(0, 1.65, 0),
		RightArm = V(1.75, 0.8, 0),
		LeftArm = V(-1.75, 0.8, 0),
		Legs = V(0, -1.6, 0),
		Back = V(0, 0.6, 1.25),
		Tail = V(0, -1.05, 1.25),
	},
	Visual = {
		ball(3.3, V(0, 0, 0), RGB(62, 48, 70), Mat.Glass),
		ball(1.7, V(0, 0, -0.55), RGB(255, 90, 20), Mat.Neon),
		-- faceted shards of obsidian standing out of the shell
		block(V(0.9, 1.7, 0.9), V(0.95, 0.75, -0.6), RGB(78, 62, 92), Mat.Glass, { Rot = V(-20, 0, -25) }),
		block(V(0.8, 1.5, 0.8), V(-1.0, 0.6, -0.55), RGB(78, 62, 92), Mat.Glass, { Rot = V(-18, 0, 28) }),
		block(V(1.0, 1.4, 1.0), V(0, 1.25, 0.6), RGB(72, 56, 84), Mat.Glass, { Rot = V(25, 0, 0) }),
		-- lava veins
		block(V(2.6, 0.1, 0.1), V(0, -0.6, -1.45), RGB(255, 120, 30), Mat.Neon, { Rot = V(0, 0, 12) }),
		block(V(0.1, 2.2, 0.1), V(0.7, 0.1, -1.4), RGB(255, 120, 30), Mat.Neon, { Rot = V(0, 0, -10) }),
		block(V(0.1, 1.6, 0.1), V(-0.8, -0.2, -1.35), RGB(255, 120, 30), Mat.Neon, { Rot = V(0, 0, 15) }),
	},
})

define({
	Id = "ScorpionTail",
	DisplayName = "Scorpion Tail",
	Rarity = "Rare",
	Slot = "Tail",
	Exclusive = true,
	Description = "Seven armoured segments curling up over its back, and one very bad idea at the end.",
	Stats = { AttackPower = 6, AttackSpeed = 4, Defence = 2 },
	PowerCost = 12,
	AbilityId = "VenomSting",
	OnHit = { Status = "Poison", Chance = 0.4, ComboHit = 3 },
	Source = "SHOP exclusive",
	Visual = {
		-- back, then curling up and forward over the body
		ball(0.85, V(0, -0.1, 0.55), RGB(70, 50, 30), Mat.Slate),
		ball(0.8, V(0, 0.25, 1.3), RGB(80, 58, 34), Mat.Slate),
		ball(0.75, V(0, 0.95, 1.9), RGB(90, 64, 38), Mat.Slate),
		ball(0.7, V(0, 1.8, 2.15), RGB(100, 72, 42), Mat.Slate),
		ball(0.65, V(0, 2.65, 2.0), RGB(110, 80, 46), Mat.Slate),
		ball(0.6, V(0, 3.35, 1.5), RGB(120, 88, 50), Mat.Slate),
		ball(0.55, V(0, 3.75, 0.85), RGB(130, 96, 54), Mat.Slate),
		-- the venom sac and the stinger, pointing forward and down
		ball(0.6, V(0, 3.85, 0.25), RGB(120, 220, 70), Mat.Neon),
		wedge(V(0.22, 0.75, 0.3), V(0, 3.6, -0.3), RGB(30, 30, 30), Mat.Slate, { Rot = V(-140, 0, 0) }),
	},
})

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
