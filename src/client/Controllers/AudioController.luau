--[[
	AudioController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/AudioController

	SOUND + MUSIC (Phase 7). All ids live in Shared/AudioDefinitions; empty ids are
	skipped, so the game is silent until you fill them in, and never errors.

	  SFX    reacts to events the game already sends (combat feedback, telegraphs,
	         impacts, boss events, rewards, level ups, challenges, duel rounds) plus
	         direct :Play(key) calls (UI clicks, crafting, possession, reward reveals).
	         Spatial sounds play at the event's position and fade with distance.
	  Music  Hub / Boss / BossOverdrive / Duel, chosen by what you're doing, looped and
	         cross-faded.
	  Volume two SoundGroups (Music, SFX) driven by Settings: MusicVolume / SfxVolume.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AudioDefinitions = require(Shared:WaitForChild("AudioDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local AudioController = {}

local controllers
local groups = {} -- Music / SFX SoundGroups
local lastPlayed = {} -- [key] = os.clock() (per-sound cooldowns)
local random = Random.new()
local tracks = {} -- [name] = Sound (music, created on first use)
local currentTrack: string? = nil
local bossPhase = 1

function AudioController:Init(registry)
	controllers = registry
end

local function group(name: string): SoundGroup
	if not groups[name] then
		local g = Instance.new("SoundGroup")
		g.Name = "BAN_" .. name
		g.Parent = SoundService
		groups[name] = g
	end
	return groups[name]
end

function AudioController:ApplyVolumes()
	group("Music").Volume = (controllers.SettingsController:Get("MusicVolume") or 60) / 100
	group("SFX").Volume = (controllers.SettingsController:Get("SfxVolume") or 80) / 100
end

------------------------------------------------------------------------------------------
-- Sound effects
------------------------------------------------------------------------------------------
-- Plays a sound by key. position (optional) = play it in the world there (if Spatial).
function AudioController:Play(key: string, position: Vector3?)
	local def = AudioDefinitions.Sounds[key]
	if not def or def.Id == "" then
		return
	end
	local now = os.clock()
	if def.Cooldown and now - (lastPlayed[key] or 0) < def.Cooldown then
		return
	end
	lastPlayed[key] = now

	local sound = Instance.new("Sound")
	sound.SoundId = def.Id
	sound.Volume = def.Volume or 0.5
	sound.SoundGroup = group("SFX")
	if def.Pitch then
		sound.PlaybackSpeed = random:NextNumber(def.Pitch[1], def.Pitch[2])
	end
	local holder
	if def.Spatial and position then
		holder = Instance.new("Part")
		holder.Anchored = true
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder.Transparency = 1
		holder.Size = Vector3.one * 0.2
		holder.Position = position
		holder.Parent = Workspace:FindFirstChild("ClientEffects") or Workspace
		sound.RollOffMaxDistance = 150
		sound.Parent = holder
	else
		sound.Parent = SoundService
	end
	sound:Play()
	local function cleanup()
		if holder then
			holder:Destroy()
		else
			sound:Destroy()
		end
	end
	sound.Ended:Connect(cleanup)
	if def.MaxLength then
		-- a long library take used as a one-shot: fade it out quickly at MaxLength
		task.delay(def.MaxLength, function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(0.25), { Volume = 0 }):Play()
				task.delay(0.25, function()
					if sound.Parent then
						cleanup()
					end
				end)
			end
		end)
	end
	task.delay(15, function() -- safety net (e.g. a sound that never loads)
		if sound.Parent then
			cleanup()
		end
	end)
end

------------------------------------------------------------------------------------------
-- Music
------------------------------------------------------------------------------------------
local function trackFor(name: string): Sound?
	local def = AudioDefinitions.Music[name]
	if not def or def.Id == "" then
		return nil
	end
	if not tracks[name] then
		local sound = Instance.new("Sound")
		sound.Name = "Music_" .. name
		sound.SoundId = def.Id
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = group("Music")
		sound.Parent = SoundService
		tracks[name] = sound
	end
	return tracks[name]
end

function AudioController:SetTrack(name: string?)
	if name == currentTrack then
		return
	end
	local fade = TweenInfo.new(AudioDefinitions.MusicFadeTime)
	local old = currentTrack and tracks[currentTrack]
	if old then
		local tween = TweenService:Create(old, fade, { Volume = 0 })
		tween:Play()
		tween.Completed:Connect(function()
			if currentTrack ~= old.Name:sub(7) then
				old:Pause()
			end
		end)
	end
	currentTrack = name
	local new = name and trackFor(name)
	if new then
		if not new.IsPlaying then
			new:Play()
		end
		TweenService:Create(new, fade, { Volume = AudioDefinitions.Music[name].Volume or 0.5 }):Play()
	end
end

-- Region ambience (WorldController): one looped sound, cross-faded on change.
local ambienceSounds = {}
local currentAmbience = nil
function AudioController:SetAmbience(key: string?)
	if key == currentAmbience then
		return
	end
	local fade = TweenInfo.new(2)
	local old = currentAmbience and ambienceSounds[currentAmbience]
	if old then
		TweenService:Create(old, fade, { Volume = 0 }):Play()
	end
	currentAmbience = key
	local def = key and AudioDefinitions.Ambience and AudioDefinitions.Ambience[key]
	if not def or def.Id == "" then
		return
	end
	local sound = ambienceSounds[key]
	if not sound then
		sound = Instance.new("Sound")
		sound.Name = "Ambience_" .. key
		sound.SoundId = def.Id
		sound.Looped = true
		sound.Volume = 0
		sound.SoundGroup = group("SFX")
		sound.Parent = SoundService
		ambienceSounds[key] = sound
	end
	if not sound.IsPlaying then
		sound:Play()
	end
	TweenService:Create(sound, fade, { Volume = def.Volume or 0.4 }):Play()
end

-- What should be playing right now?
function AudioController:WantedTrack(): string?
	local function available(name)
		return AudioDefinitions.Music[name] and AudioDefinitions.Music[name].Id ~= "" and name or nil
	end
	if controllers.PvPController:IsInMatch() then
		return available("Duel") or available("Hub")
	end
	if controllers.BossController:IsInFight() then
		if bossPhase > 1 then
			return available("BossOverdrive") or available("Boss")
		end
		return available("Boss")
	end
	return available("Hub")
end

------------------------------------------------------------------------------------------
-- Event hooks
------------------------------------------------------------------------------------------
local function positionOf(model)
	local root = typeof(model) == "Instance" and model:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

function AudioController:Start()
	self:ApplyVolumes()
	controllers.SettingsController.Changed:Connect(function()
		self:ApplyVolumes()
	end)
	controllers.ClientState.Changed:Connect(function()
		self:ApplyVolumes()
	end)

	-- UI clicks for every UIKit button in the game.
	UIKit.OnClick = function()
		self:Play("Click")
	end

	Net.Get("CombatFeedback").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		local position = data.Position
		if kind == "Damage" then
			local strike = type(data.Source) == "string" and data.Source:sub(1, 8) == "Handler:"
			self:Play((strike and data.Heavy) and "PunchHeavy" or (data.Amount or 0) >= 25 and "HeavyHit" or "Hit", position)
		elseif kind == "Defeated" then
			self:Play("Defeated", position)
		elseif kind == "Blocked" then
			self:Play("Block", position)
		elseif kind == "GuardBreak" then
			self:Play("GuardBreak", position)
		elseif kind == "Staggered" or kind == "KnockedDown" then
			self:Play("Stagger", position)
		elseif kind == "Chain" then
			self:Play("Shock", data.To)
		end
	end)

	Net.Get("WorldFX").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "Telegraph" and data.Style ~= "Friendly" then
			self:Play("Warning")
		elseif kind == "Impact" then
			self:Play("Slam", data.Position)
		elseif kind == "Projectile" then
			self:Play("Projectile", data.From)
		elseif kind == "Shield" then
			self:Play("Shield", positionOf(data.Target))
		elseif kind == "UltimateBanner" then
			self:Play("Ultimate")
		end
	end)

	Net.Get("BossEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "Start" then
			bossPhase = 1
			self:Play("BossIntro")
		elseif kind == "Phase" then
			bossPhase = 2
			self:Play("BossPhase")
		elseif kind == "End" then
			bossPhase = 1
			self:Play(type(data) == "table" and data.Result == "Victory" and "Victory" or "Defeat")
		end
	end)

	Net.Get("DuelEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "Banner" and type(data) == "table" and type(data.Title) == "string" and data.Title:find("^ROUND") then
			self:Play("DuelBell")
		elseif kind == "MatchEnd" and type(data) == "table" then
			self:Play(data.Result == "Win" and "Victory" or "Defeat")
		end
	end)

	controllers.ClientState.ServerEvent:Connect(function(kind, data)
		if kind == "LevelUp" then
			self:Play("LevelUp")
		elseif kind == "Toast" and type(data) == "table" and type(data.Text) == "string" and data.Text:find("CHALLENGE COMPLETE") then
			self:Play("ChallengeComplete")
		end
	end)

	-- Music director: check once a second what should be playing.
	task.spawn(function()
		while true do
			self:SetTrack(self:WantedTrack())
			task.wait(1)
		end
	end)
end

return AudioController
