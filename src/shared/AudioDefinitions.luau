--[[
	AudioDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/AudioDefinitions

	EVERY SOUND AND MUSIC TRACK IN THE GAME (Phase 7). This is the only file you edit to
	add audio: paste an asset id into Id, e.g. Id = "rbxassetid://1234567890".
	Empty ids are simply skipped (no errors), so you can fill them in one at a time.

	WHERE TO GET SOUNDS: Studio → Toolbox → Creator Store → Audio. Sounds uploaded by
	Roblox are free to use in any game. Right-click a sound → "Copy Asset ID".
	Since 2022 most audio uploaded by OTHER people is private and won't play in your game,
	so prefer Roblox's own uploads (or upload your own).

	Fields:
	  Id       "rbxassetid://..." ("" = silent)
	  Volume   0..1 before the player's volume setting (Settings: SfxVolume / MusicVolume)
	  Pitch    { min, max } random pitch per play, so repeated hits don't sound robotic
	  Spatial  true = plays in the world at the event's position (fades with distance)
	  Cooldown seconds before this sound can play again (stops spam from many hits)
	Music tracks loop and cross-fade when the situation changes (AudioController).
]]

local AudioDefinitions = {}

AudioDefinitions.Sounds = {
	-- Combat
	Hit = { Id = "", Volume = 0.5, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.06 },
	HeavyHit = { Id = "", Volume = 0.7, Pitch = { 0.85, 1 }, Spatial = true, Cooldown = 0.1 },
	-- Handler strikes: a whoosh as the punch is thrown, a meaty impact when it lands (a
	-- landed heavy strike, e.g. the Overhand, plays PunchHeavy INSTEAD of Hit / HeavyHit)
	PunchWhoosh = { Id = "", Volume = 0.45, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.05 },
	PunchHeavy = { Id = "", Volume = 0.85, Pitch = { 0.9, 1.0 }, Spatial = true, Cooldown = 0.08 },
	-- animation markers: a foot planting hard into a strike / dodge, landing from the air
	Footstep = { Id = "", Volume = 0.35, Pitch = { 0.9, 1.15 }, Spatial = true, Cooldown = 0.05 },
	Land = { Id = "", Volume = 0.6, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.1 },
	-- Nightmare abilities that connect: the jaws snapping shut (animation marker), the bite
	-- landing (wet crunch), a claw ripping through (slash), a claw striking armour (clang)
	BiteSnap = { Id = "", Volume = 0.7, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.1 },
	BiteImpact = { Id = "", Volume = 0.8, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.1 },
	-- the clamp: teeth grinding in while it thrashes them, then the wet tear of the rip
	BiteGrind = { Id = "", Volume = 0.55, Pitch = { 0.85, 1.05 }, Spatial = true, Cooldown = 0.15 },
	BiteRip = { Id = "", Volume = 0.9, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.2 },
	ClawSlash = { Id = "", Volume = 0.7, Pitch = { 0.95, 1.1 }, Spatial = true, Cooldown = 0.08 },
	MetalSpark = { Id = "", Volume = 0.75, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.08 },
	-- a boss's full-weight slam / landing: deep ground boom + rubble
	BossSlam = { Id = "", Volume = 1, Pitch = { 0.9, 1.0 }, Spatial = true, Cooldown = 0.2 },
	Block = { Id = "", Volume = 0.6, Pitch = { 0.95, 1.05 }, Spatial = true, Cooldown = 0.1 },
	GuardBreak = { Id = "", Volume = 0.8, Spatial = true },
	Stagger = { Id = "", Volume = 0.8, Spatial = true },
	Defeated = { Id = "", Volume = 0.8, Spatial = true },
	Shock = { Id = "", Volume = 0.5, Pitch = { 0.95, 1.1 }, Spatial = true, Cooldown = 0.1 },
	Shield = { Id = "", Volume = 0.6, Spatial = true },
	Warning = { Id = "", Volume = 0.35, Pitch = { 0.95, 1.05 }, Cooldown = 0.25 }, -- red telegraphs appearing
	Slam = { Id = "", Volume = 0.8, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.08 }, -- boss / AoE impacts
	Projectile = { Id = "", Volume = 0.4, Pitch = { 0.9, 1.15 }, Spatial = true, Cooldown = 0.05 },
	Ultimate = { Id = "", Volume = 0.9 },
	Possess = { Id = "", Volume = 0.7 },

	-- Bosses
	BossIntro = { Id = "", Volume = 0.9 },
	BossPhase = { Id = "", Volume = 0.9 }, -- OVERDRIVE / THE MIRROR CRACKS
	Victory = { Id = "", Volume = 0.9 },
	Defeat = { Id = "", Volume = 0.8 },

	-- Rewards & progress
	RevealUncommon = { Id = "", Volume = 0.6 },
	RevealRare = { Id = "", Volume = 0.7 },
	RevealEpic = { Id = "", Volume = 0.8 },
	RevealLegendary = { Id = "", Volume = 1 },
	LevelUp = { Id = "", Volume = 0.8 },
	ChallengeComplete = { Id = "", Volume = 0.7 },
	Craft = { Id = "", Volume = 0.7 },

	-- PvP
	DuelBell = { Id = "", Volume = 0.8 }, -- round start / "FIGHT!"

	-- The Nightmare Gym
	GymDoor = { Id = "", Volume = 0.8 }, -- the heavy freight-lift doors grinding open / shut
	BagHit = { Id = "", Volume = 0.55, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.05 }, -- leather thump
	BagHeavy = { Id = "", Volume = 0.8, Pitch = { 0.85, 1 }, Spatial = true, Cooldown = 0.08 }, -- deep heavy-bag boom
	ChainRattle = { Id = "", Volume = 0.45, Pitch = { 0.9, 1.15 }, Spatial = true, Cooldown = 0.25 }, -- the bag's chain jangling
	GymReward = { Id = "", Volume = 0.6 }, -- a common / uncommon reward ticking in
	GymRevealRare = { Id = "", Volume = 0.9 }, -- the crate glowing open for Rare and better
	GymRevealMythic = { Id = "", Volume = 1 }, -- Mythic / Secret: the big one

	-- UI
	Click = { Id = "", Volume = 0.35, Cooldown = 0.04 },
	Toast = { Id = "", Volume = 0.3, Cooldown = 0.3 },
}

-- Rock / metal from Roblox's licensed library (APMOfficial, DistrokidOfficial), so they
-- play in any game. Other picks from the same search: "Fight through Adversity"
-- rbxassetid://9038254260 (rock), "Cinematic Metal Action Theme for Gaming"
-- rbxassetid://120519322089791 (metal).
AudioDefinitions.Music = {
	Hub = { Id = "rbxassetid://139483185512152", Volume = 0.4 }, -- the Forge, Workshop, Training Arena ("Crunch Time", blues-rock groove)
	Boss = { Id = "rbxassetid://78744747224727", Volume = 0.6 }, -- "Boss Fight!" (metal)
	BossOverdrive = { Id = "rbxassetid://1842652230", Volume = 0.65 }, -- after a boss's phase change (falls back to Boss) ("Toxic", heavy metal)
	Duel = { Id = "rbxassetid://1837301451", Volume = 0.55 }, -- "Epic Battle Simulator" (rock)
}

AudioDefinitions.MusicFadeTime = 1.5 -- seconds to cross-fade between tracks

-- Looping background sound per region (wind, machinery, dripping...), cross-faded by
-- WorldController as you walk between regions. Plays in the SFX volume group.
AudioDefinitions.Ambience = {
	HubAmbience = { Id = "", Volume = 0.35 }, -- the Forge: low hum, crackling braziers
	ScrapAmbience = { Id = "", Volume = 0.4 }, -- machinery, clanking chains, distant hammering
	MirrorAmbience = { Id = "", Volume = 0.35 }, -- glassy chimes, eerie choir
	StormAmbience = { Id = "", Volume = 0.45 }, -- howling wind, rain, thunder
	AbyssAmbience = { Id = "", Volume = 0.4 }, -- dripping water, deep groans
	GymAmbience = { Id = "", Volume = 0.4 }, -- ventilation hum, clanking weights, distant grunts
}

return AudioDefinitions
