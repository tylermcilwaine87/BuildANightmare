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
	Every id below is from Roblox's licensed libraries: sound effects from ProSoundEffects
	(Pro Sound Effects), music from APMOfficial / DistrokidOfficial. The comment on each
	line is the track's name in the Creator Store, so a slot is easy to find and swap.

	Fields:
	  Id       "rbxassetid://..." ("" = silent)
	  Volume   0..1 before the player's volume setting (Settings: SfxVolume / MusicVolume)
	  Pitch    { min, max } random pitch per play, so repeated hits don't sound robotic
	  Spatial  true = plays in the world at the event's position (fades with distance)
	  Cooldown seconds before this sound can play again (stops spam from many hits)
	  MaxLength seconds, then a quick fade out (for long library takes used as one-shots)
	Music tracks loop and cross-fade when the situation changes (AudioController).
]]

local AudioDefinitions = {}

AudioDefinitions.Sounds = {
	-- Combat
	Hit = { Id = "rbxassetid://9113575294", Volume = 0.5, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.06 }, -- "Boxing Hits 1"
	HeavyHit = { Id = "rbxassetid://9117971636", Volume = 0.7, Pitch = { 0.85, 1 }, Spatial = true, Cooldown = 0.1 }, -- "Punch Some Crack And Thud 2"
	-- Handler strikes: a whoosh as the punch is thrown, a meaty impact when it lands (a
	-- landed heavy strike, e.g. the Overhand, plays PunchHeavy INSTEAD of Hit / HeavyHit)
	PunchWhoosh = { Id = "rbxassetid://9120728815", Volume = 0.45, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.05 }, -- "Whoosh Heavy Punches 1"
	PunchHeavy = { Id = "rbxassetid://9117969687", Volume = 0.85, Pitch = { 0.9, 1.0 }, Spatial = true, Cooldown = 0.08 }, -- "Punch Kit Beefy Hit 2"
	-- animation markers: a foot planting hard into a strike / dodge, landing from the air
	Footstep = { Id = "rbxassetid://9114523345", Volume = 0.35, Pitch = { 0.9, 1.15 }, Spatial = true, Cooldown = 0.05 }, -- "Foot Stomp 3"
	Land = { Id = "rbxassetid://9113480915", Volume = 0.6, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.1 }, -- "Body Fall Thud 2"
	-- Nightmare abilities that connect: the jaws snapping shut (animation marker), the bite
	-- landing (wet crunch), a claw ripping through (slash), a claw striking armour (clang)
	BiteSnap = { Id = "rbxassetid://9119055432", Volume = 0.7, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.1 }, -- "Shark Bite Smaller Teeth Snaps 6"
	BiteImpact = { Id = "rbxassetid://9125466463", Volume = 0.8, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.1 }, -- "Creature Bite Pterodactyl Crunch"
	-- the clamp: teeth grinding in while it thrashes them, then the wet tear of the rip
	BiteGrind = { Id = "rbxassetid://9113540587", Volume = 0.55, Pitch = { 0.85, 1.05 }, Spatial = true, Cooldown = 0.15 }, -- "Bone Cracks 2"
	BiteRip = { Id = "rbxassetid://9114487557", Volume = 0.9, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.2, MaxLength = 1.4 }, -- "Flesh Tear 2"
	ClawSlash = { Id = "rbxassetid://9119749044", Volume = 0.7, Pitch = { 0.95, 1.1 }, Spatial = true, Cooldown = 0.08 }, -- "Sword Swish 201"
	MetalSpark = { Id = "rbxassetid://9119072660", Volume = 0.75, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.08 }, -- "Shield Clang As Hit Metal Sword Hubcap 1"
	-- a boss's full-weight slam / landing: deep ground boom + rubble
	BossSlam = { Id = "rbxassetid://9125404320", Volume = 1, Pitch = { 0.9, 1.0 }, Spatial = true, Cooldown = 0.2 }, -- "Boom Impact Deep Distant Thumping Hits"
	Block = { Id = "rbxassetid://9113520892", Volume = 0.6, Pitch = { 0.95, 1.05 }, Spatial = true, Cooldown = 0.1 }, -- "Body Hit With Rubber Glove 6"
	GuardBreak = { Id = "rbxassetid://9114590297", Volume = 0.8, Spatial = true }, -- "Glass Break 1"
	Stagger = { Id = "rbxassetid://9113516204", Volume = 0.8, Spatial = true }, -- "Body Hit Some Narrow End Hits 14"
	Defeated = { Id = "rbxassetid://9113470178", Volume = 0.8, Spatial = true }, -- "Body Fall Heavy 3"
	Shock = { Id = "rbxassetid://9114277757", Volume = 0.5, Pitch = { 0.95, 1.1 }, Spatial = true, Cooldown = 0.1 }, -- "Electric Zaps 12"
	Shield = { Id = "rbxassetid://9116393976", Volume = 0.6, Spatial = true }, -- "Magic Glow Short Pulsing Bursts 9"
	Warning = { Id = "rbxassetid://9125648149", Volume = 0.35, Pitch = { 0.95, 1.05 }, Cooldown = 0.25 }, -- red telegraphs appearing ("Magic Zoom Up Sharp Tubular Whoosh")
	Slam = { Id = "rbxassetid://9125869797", Volume = 0.8, Pitch = { 0.9, 1.05 }, Spatial = true, Cooldown = 0.08 }, -- boss / AoE impacts ("Rock Drops Smashes Impacts Hits")
	Projectile = { Id = "rbxassetid://9114446852", Volume = 0.4, Pitch = { 0.9, 1.15 }, Spatial = true, Cooldown = 0.05 }, -- "Fire Whoosh 15"
	Ultimate = { Id = "rbxassetid://9125544480", Volume = 0.9, MaxLength = 3.5 }, -- "Energy Blast Big Deep Horn Swell"
	Possess = { Id = "rbxassetid://9116421550", Volume = 0.7 }, -- "Magic Transformation 6"

	-- Bosses
	BossIntro = { Id = "rbxassetid://9113987603", Volume = 0.9 }, -- "Creature Vocal Giant Crab Monster Roars 1"
	BossPhase = { Id = "rbxassetid://9113980319", Volume = 0.9 }, -- OVERDRIVE / THE MIRROR CRACKS ("Creature Mix Giant Crab Monster Roar Growl 1")
	Victory = { Id = "rbxassetid://9120974911", Volume = 0.9 }, -- "Wrestling Crowd 1"
	Defeat = { Id = "rbxassetid://9114352428", Volume = 0.8, MaxLength = 4 }, -- "Evil Church Bell Twisted Bent 1"

	-- Rewards & progress
	RevealUncommon = { Id = "rbxassetid://9116394545", Volume = 0.6 }, -- "Magic Glows Soft Clusters Of Chiming Hits 1"
	RevealRare = { Id = "rbxassetid://9116395089", Volume = 0.7 }, -- "Magic Glows Soft Clusters Of Chiming Hits 4"
	RevealEpic = { Id = "rbxassetid://9125641284", Volume = 0.8 }, -- "Magic Synth Stinger Glassine Multi Tone"
	RevealLegendary = { Id = "rbxassetid://9126102254", Volume = 1 }, -- "Time Warp Big Explosion Blast Boom Tonal"
	LevelUp = { Id = "rbxassetid://9116422213", Volume = 0.8 }, -- "Magic Transformation 17"
	ChallengeComplete = { Id = "rbxassetid://9126073001", Volume = 0.7 }, -- "Synth Sparkle Tone High Pitch Bell Tone"
	Craft = { Id = "rbxassetid://9113447467", Volume = 0.7 }, -- "Blacksmith Anvil Hammer Hits 16"

	-- PvP
	DuelBell = { Id = "rbxassetid://9114630316", Volume = 0.8 }, -- round start / "FIGHT!" ("Gong Hit Resonant Trail 1")

	-- The Nightmare Gym
	GymDoor = { Id = "rbxassetid://9119207765", Volume = 0.8 }, -- the heavy freight-lift doors grinding open / shut ("Sliding Metal Door 1")
	BagHit = { Id = "rbxassetid://9117969420", Volume = 0.55, Pitch = { 0.9, 1.1 }, Spatial = true, Cooldown = 0.05 }, -- leather thump ("Punching Bag Hits 22")
	BagHeavy = { Id = "rbxassetid://9113572282", Volume = 0.8, Pitch = { 0.85, 1 }, Spatial = true, Cooldown = 0.08 }, -- deep heavy-bag boom ("Boxing Hits 10")
	ChainRattle = { Id = "rbxassetid://9113763590", Volume = 0.45, Pitch = { 0.9, 1.15 }, Spatial = true, Cooldown = 0.25 }, -- the bag's chain jangling ("Chain Rattle Glassy Metal Rattle 3")
	GymReward = { Id = "rbxassetid://9113849492", Volume = 0.6 }, -- a common / uncommon reward ticking in ("Coins Or Keys Jingle 6")
	GymRevealRare = { Id = "rbxassetid://9125635426", Volume = 0.9 }, -- the crate glowing open for Rare and better ("Magical Exit Sparkling Pass Bys Clinking")
	GymRevealMythic = { Id = "rbxassetid://9116420454", Volume = 1 }, -- Mythic / Secret: the big one ("Magic Tone Tonal Shimmer Shaking Rattle 3")

	-- UI
	Click = { Id = "rbxassetid://9119717523", Volume = 0.35, Cooldown = 0.04 }, -- "Switch Click On Or Off Toggle Button 2"
	Toast = { Id = "rbxassetid://9126073318", Volume = 0.3, Cooldown = 0.3 }, -- "Synth Sparkle Tone High Pitch Bell Tone 2"
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
	HubAmbience = { Id = "rbxassetid://9112780193", Volume = 0.35 }, -- the Forge: low hum, crackling braziers ("Fireplace Constant Burning Flame 1")
	ScrapAmbience = { Id = "rbxassetid://9112796831", Volume = 0.4 }, -- machinery, clanking chains, distant hammering ("Industrial Ambience 2")
	MirrorAmbience = { Id = "rbxassetid://9125718987", Volume = 0.35 }, -- glassy chimes, eerie choir ("Ominous Crystal Presence Ringing Tones")
	StormAmbience = { Id = "rbxassetid://9120020768", Volume = 0.45 }, -- howling wind, rain, thunder ("Thunder Light Rain 2")
	AbyssAmbience = { Id = "rbxassetid://9113731969", Volume = 0.4 }, -- dripping water, deep groans ("Cave Presence Constant Eerie Musical Hum")
	GymAmbience = { Id = "rbxassetid://9125446564", Volume = 0.4 }, -- ventilation hum, clanking weights, distant grunts ("Command Room Tone Deep Air Conditioning")
}

return AudioDefinitions
