--[[
	WorldDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/WorldDefinitions

	The world map, shared by the server (builds it) and the client (lighting, sky,
	ambience and reveal moments per region).

	Layout (top-down, north = -Z):

	                      STORM BEAST
	               Storm Cliffs → Tempest Summit
	                           |
	  SCRAP TITAN ——— THE NIGHTMARE FORGE (hub) ——— MIRROR WARDEN
	  Rusted Expanse → Foundry                 Shattered Reach → Hall of Reflections
	                           |
	                      ABYSSAL MAW
	              Drowned Descent → Maw Cathedral

	Each boss arena's FIRST slot is built in the world at the end of its route
	(Regions[x].Arena). Extra slots (several groups fighting the same boss at once) are
	identical copies far away (Config.Bosses.ArenaOrigin), so nobody ever waits.
]]

local RGB = Color3.fromRGB
local V3 = Vector3.new

local World = {}

World.HubCenter = V3(0, 1, 0)
World.HubRadius = 175
World.HubSpawn = V3(0, 4, 52)
-- How much the Forge's neon is toned down (0 = full glow, 1 = black). Applies to every
-- neon part and light in the hub, and the boss monuments.
World.HubNeonDim = 0.45
World.HubLightScale = 0.6

-- Distance from an arena's centre to the plaza outside its gate (where routes end).
World.GateDistance = 104

local function arena(center: Vector3, entranceDirection: Vector3): CFrame
	return CFrame.lookAt(center, center + entranceDirection)
end

-- Lighting presets the client blends between. ClockTime is applied instantly.
World.Regions = {
	Hub = {
		Name = "THE NIGHTMARE FORGE",
		Subtitle = "Where every Nightmare is born",
		Color = RGB(190, 140, 255),
		Ambience = "HubAmbience",
		Lighting = {
			ClockTime = 18.2,
			Brightness = 2.6,
			Ambient = RGB(96, 82, 128),
			OutdoorAmbient = RGB(128, 112, 165),
			Atmosphere = { Density = 0.32, Offset = 0.12, Color = RGB(150, 120, 190), Decay = RGB(70, 46, 110), Glare = 0.2, Haze = 1.6 },
			Grading = { Brightness = 0, Contrast = 0.1, Saturation = 0.05, TintColor = RGB(250, 240, 255) },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.6 },
			Clouds = { Cover = 0.55, Density = 0.35, Color = RGB(150, 120, 190) },
			Sky = { SunSize = 14, MoonSize = 11, Stars = 3000 },
		},
	},
	Scrap = {
		BossId = "ScrapTitan",
		Name = "THE RUSTED EXPANSE",
		Subtitle = "Kingdom of the Scrap Titan",
		ArenaName = "THE TITAN'S FOUNDRY",
		Color = RGB(255, 130, 40),
		Direction = V3(-1, 0, 0),
		Arena = arena(V3(-700, 1, 40), V3(1, 0, 0)),
		Ambience = "ScrapAmbience",
		Lighting = {
			ClockTime = 17.7,
			Brightness = 2,
			Ambient = RGB(78, 56, 40),
			OutdoorAmbient = RGB(120, 84, 60),
			Atmosphere = { Density = 0.42, Offset = 0.15, Color = RGB(206, 140, 96), Decay = RGB(120, 70, 46), Glare = 0.6, Haze = 2.4 },
			Grading = { Brightness = 0, Contrast = 0.16, Saturation = -0.12, TintColor = RGB(255, 228, 200) },
			Bloom = { Intensity = 0.6, Size = 26, Threshold = 1.5 },
			Clouds = { Cover = 0.7, Density = 0.55, Color = RGB(150, 100, 80) },
			Sky = { SunSize = 34, MoonSize = 11, Stars = 0 },
		},
	},
	Mirror = {
		BossId = "MirrorWarden",
		Name = "THE SHATTERED REACH",
		Subtitle = "Realm of the Mirror Warden",
		ArenaName = "THE HALL OF REFLECTIONS",
		Color = RGB(200, 170, 255),
		Direction = V3(1, 0, 0),
		Arena = arena(V3(700, 1, -40), V3(-1, 0, 0)),
		Ambience = "MirrorAmbience",
		Lighting = {
			ClockTime = 0.2,
			Brightness = 1.2,
			Ambient = RGB(110, 104, 140),
			OutdoorAmbient = RGB(150, 146, 190),
			Atmosphere = { Density = 0.36, Offset = 0.3, Color = RGB(214, 210, 240), Decay = RGB(150, 130, 210), Glare = 0, Haze = 2 },
			Grading = { Brightness = 0, Contrast = 0.08, Saturation = -0.25, TintColor = RGB(236, 236, 255) },
			Bloom = { Intensity = 0.4, Size = 24, Threshold = 2 },
			Clouds = { Cover = 0.35, Density = 0.2, Color = RGB(220, 216, 255) },
			Sky = { SunSize = 14, MoonSize = 42, Stars = 5000 },
		},
	},
	Storm = {
		BossId = "StormBeast",
		Name = "THE STORM CLIFFS",
		Subtitle = "Hunting ground of the Storm Beast",
		ArenaName = "THE TEMPEST SUMMIT",
		Color = RGB(110, 200, 255),
		Direction = V3(0, 0, -1),
		Arena = arena(V3(40, 121, -700), V3(0, 0, 1)),
		Ambience = "StormAmbience",
		Lighting = {
			ClockTime = 14,
			Brightness = 2.4,
			Ambient = RGB(90, 100, 124),
			OutdoorAmbient = RGB(120, 132, 160),
			Atmosphere = { Density = 0.36, Offset = 0.05, Color = RGB(136, 150, 176), Decay = RGB(70, 82, 110), Glare = 0, Haze = 2 },
			Grading = { Brightness = 0.02, Contrast = 0.2, Saturation = -0.25, TintColor = RGB(225, 236, 255) },
			Bloom = { Intensity = 0.7, Size = 26, Threshold = 1.4 },
			Clouds = { Cover = 0.85, Density = 0.65, Color = RGB(80, 88, 110) },
			Sky = { SunSize = 10, MoonSize = 11, Stars = 0 },
			Lightning = true,
		},
	},
	Abyss = {
		BossId = "AbyssalMaw",
		Name = "THE DROWNED DESCENT",
		Subtitle = "Lair of the Abyssal Maw",
		ArenaName = "THE MAW CATHEDRAL",
		Color = RGB(70, 230, 180),
		Direction = V3(0, 0, 1),
		Arena = arena(V3(-40, -99, 700), V3(0, 0, -1)),
		Ambience = "AbyssAmbience",
		Lighting = {
			ClockTime = 1,
			Brightness = 1,
			Ambient = RGB(56, 100, 104),
			OutdoorAmbient = RGB(58, 110, 114),
			Atmosphere = { Density = 0.46, Offset = 0, Color = RGB(40, 104, 110), Decay = RGB(12, 40, 50), Glare = 0, Haze = 2.4 },
			Grading = { Brightness = 0, Contrast = 0.14, Saturation = 0.05, TintColor = RGB(196, 240, 236) },
			Bloom = { Intensity = 0.9, Size = 30, Threshold = 1.1 },
			Clouds = { Cover = 0, Density = 0, Color = RGB(20, 40, 46) },
			Sky = { SunSize = 10, MoonSize = 8, Stars = 0 },
		},
	},
}

World.RouteOrder = { "Scrap", "Mirror", "Storm", "Abyss" }

World.BossRegion = {
	ScrapTitan = "Scrap",
	MirrorWarden = "Mirror",
	StormBeast = "Storm",
	AbyssalMaw = "Abyss",
}

-- Where the route meets the arena gate (outside the barrier), facing the gate.
function World.GatePlaza(regionId: string): CFrame
	local origin = World.Regions[regionId].Arena
	local plaza = origin * CFrame.new(0, 0, -World.GateDistance)
	return CFrame.lookAt(plaza.Position, origin.Position)
end

-- Which region a world position is in (hub disc first, then the four quarters).
function World.RegionAt(position: Vector3): string
	local flat = V3(position.X, 0, position.Z)
	if flat.Magnitude <= World.HubRadius + 25 then
		return "Hub"
	end
	if math.abs(flat.X) >= math.abs(flat.Z) then
		return flat.X < 0 and "Scrap" or "Mirror"
	end
	return flat.Z < 0 and "Storm" or "Abyss"
end

-- Hidden relics along the routes: walking off the main path pays off. Each can be found
-- once per player (profile.Relics) and gives Reward.
World.RelicReward = { Coins = 60, Essence = 15, XP = 90 }
World.Relics = {
	-- Hub
	{ Id = "ForgeEmber", Region = "Hub", Name = "First Ember", Lore = "The Forge's first spark. Every Nightmare ever built carries a little of it." },
	-- Scrap
	{ Id = "ForemanBadge", Region = "Scrap", Name = "Foreman's Badge", Lore = "'SHIFT 9 - DO NOT WAKE THE FURNACE.' Nobody remembers who wrote it." },
	{ Id = "TitanBolt", Region = "Scrap", Name = "Titan's Bolt", Lore = "A bolt the size of a man, sheared clean off. Something tore itself free here." },
	{ Id = "CrusherLog", Region = "Scrap", Name = "Crusher Log", Lore = "Crusher 4: 12,000 machines fed in. Crusher 4 was fed in last." },
	-- Mirror
	{ Id = "CrackedLocket", Region = "Mirror", Name = "Cracked Locket", Lore = "The portrait inside shows whoever holds it. It never smiles back." },
	{ Id = "WardenSigil", Region = "Mirror", Name = "Warden's Sigil", Lore = "Pressed into the glass: 'Every visitor stays. Only their reflection leaves.'" },
	{ Id = "SilverQuill", Region = "Mirror", Name = "Silver Quill", Lore = "It writes backwards, and only the truth. The pages around it are blank." },
	-- Storm
	{ Id = "ScorchedHelm", Region = "Storm", Name = "Scorched Helm", Lore = "Melted through the crown. The climber kept going for another mile." },
	{ Id = "StormCore", Region = "Storm", Name = "Captured Storm Core", Lore = "A lightning bolt, caught in a bottle. It still remembers the sky." },
	{ Id = "TornBanner", Region = "Storm", Name = "Last Banner", Lore = "The cliff fort's last banner. The Beast left the pole and took the fort." },
	-- Abyss
	{ Id = "DiversLamp", Region = "Abyss", Name = "Diver's Lamp", Lore = "Still warm. The diver's rope went down and never came back up." },
	{ Id = "AbyssPearl", Region = "Abyss", Name = "Black Pearl", Lore = "It beats like a heart. The Maw grows them, and it wants them back." },
	{ Id = "DrownedHymn", Region = "Abyss", Name = "Drowned Hymn", Lore = "A prayer carved into bone: 'Feed it the bells and it sleeps a little longer.'" },
}

World.RelicById = {}
for _, relic in World.Relics do
	World.RelicById[relic.Id] = relic
end

return World
