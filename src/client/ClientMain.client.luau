--[[
	ClientMain  (LocalScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/ClientMain

	Client bootstrap. Requires each controller, runs Init(controllers) on all of them,
	then Start(). Controllers reach each other through the shared `controllers` table.
]]

local Controllers = script.Parent:WaitForChild("Controllers")

local LOAD_ORDER = {
	"ClientState",
	"SettingsController",
	"AudioController",
	"NightmareAnimator",
	"EffectsController",
	"HUDController",
	"WorkshopController",
	"TutorialController",
	"BossController",
	"RewardController",
	"PvPController",
	"CraftingController",
	"CodexController",
	"GoalsController",
	"PartyController",
	"ShowcaseController",
	"MenuController",
	"FighterController",
	"WorldController",
	"GymController",
	"HandlerAnimator",
	"ChainSimulator",
	"PossessionController",
	"CombatController",
	"MeleeController",
	"LockOnController",
	"StanceController",
	"InputController",
}

local controllers = {}
for _, name in LOAD_ORDER do
	controllers[name] = require(Controllers:WaitForChild(name))
end

for _, name in LOAD_ORDER do
	local controller = controllers[name]
	if controller.Init then
		controller:Init(controllers)
	end
end

for _, name in LOAD_ORDER do
	local controller = controllers[name]
	if controller.Start then
		controller:Start()
	end
end
