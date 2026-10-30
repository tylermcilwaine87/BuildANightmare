--[[
	SettingsDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/SettingsDefinitions

	Player SETTINGS (Phase 7), saved in profile.Settings. Shared so the server validates
	and the client shows / applies exactly the same list.

	Types: Toggle (boolean) · Choice (one of Options) · Slider (Min..Max in Step)
	Server: NightmareBuildService "SetSetting", key, value (validated by Sanitize).
	Client: SettingsController applies them (EffectsController, HUD, Nightmare hiding,
	AudioController volumes).
]]

local SettingsDefinitions = {}

SettingsDefinitions.List = {
	{ Key = "MusicVolume", Label = "Music volume", Type = "Slider", Min = 0, Max = 100, Step = 10, Default = 60 },
	{ Key = "SfxVolume", Label = "Sound effects volume", Type = "Slider", Min = 0, Max = 100, Step = 10, Default = 80 },
	{ Key = "CameraShake", Label = "Camera shake", Type = "Choice", Options = { "Full", "Reduced", "Off" }, Default = "Full" },
	{ Key = "HitFlashes", Label = "Hit flashes", Type = "Toggle", Default = true, Hint = "The white flash when something takes a hit." },
	{ Key = "ImpactEffects", Label = "Impact effects", Type = "Choice", Options = { "Full", "Reduced", "Minimal" }, Default = "Full", Hint = "Dust, debris, shockwaves, hit-stop and slow-motion on big moments. Reduced keeps the big ones; Minimal turns them all down." },
	{ Key = "DamageNumbers", Label = "Damage numbers", Type = "Toggle", Default = true },
	{ Key = "FinisherCamera", Label = "Finisher camera", Type = "Toggle", Default = true, Hint = "A one-second side-on camera swing when your Nightmare lands a signature finisher (and now and then another finisher)." },
	{ Key = "OtherNightmares", Label = "Other players' Nightmares (outside fights)", Type = "Toggle", Default = true, Hint = "Turn off for better performance in busy servers. Always shown in your boss fights and duels." },
	-- HUD: which parts of it show (Section: a heading in the panel; the whole HUD also goes off and
	-- on with Y, for the moment, HUDController:ToggleHideAll)
	{ Key = "HudStatus", Section = "HUD", Label = "Health and Nightmare panel", Type = "Toggle", Default = true },
	{ Key = "HudAbilities", Section = "HUD", Label = "Ability buttons (Q / E)", Type = "Toggle", Default = true },
	{ Key = "HudMeters", Section = "HUD", Label = "Sync, Possession and Ultimate bars", Type = "Toggle", Default = true },
	{ Key = "HudHotbar", Section = "HUD", Label = "Weapon hotbar", Type = "Toggle", Default = true },
	{ Key = "HudButtons", Section = "HUD", Label = "Menu buttons (top right)", Type = "Toggle", Default = true, Hint = "Every menu still opens with its key. A small button stays in the corner to get back here." },
	{ Key = "HudTarget", Section = "HUD", Label = "Target's health bar", Type = "Toggle", Default = true },
	{ Key = "HudHurtEdges", Section = "HUD", Label = "Red screen edges at low health", Type = "Toggle", Default = true },
	{ Key = "ControlHints", Section = "HUD", Label = "Control hints (bottom left)", Type = "Toggle", Default = true },
}

SettingsDefinitions.ByKey = {}
for _, def in SettingsDefinitions.List do
	SettingsDefinitions.ByKey[def.Key] = def
end

-- A clean value for this setting, or nil if the key / value is invalid.
function SettingsDefinitions.Sanitize(key, value)
	local def = type(key) == "string" and SettingsDefinitions.ByKey[key]
	if not def then
		return nil
	end
	if def.Type == "Toggle" then
		if type(value) == "boolean" then
			return value -- (not `x and x or nil`: that would turn false into nil)
		end
		return nil
	elseif def.Type == "Choice" then
		return table.find(def.Options, value) and value or nil
	elseif def.Type == "Slider" then
		if type(value) ~= "number" or value ~= value then
			return nil
		end
		local stepped = math.floor(math.clamp(value, def.Min, def.Max) / def.Step + 0.5) * def.Step
		return math.clamp(stepped, def.Min, def.Max)
	end
	return nil
end

-- The player's value (or the default). `settings` = profile.Settings (may be nil).
function SettingsDefinitions.Get(settings, key: string)
	local def = SettingsDefinitions.ByKey[key]
	local value = type(settings) == "table" and settings[key]
	if def and SettingsDefinitions.Sanitize(key, value) ~= nil then
		return value
	end
	return def and def.Default
end

return SettingsDefinitions
