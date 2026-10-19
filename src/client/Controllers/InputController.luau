--[[
	InputController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/InputController

	Maps keyboard/mouse and gamepad input to actions. Touch uses HUD buttons that call
	the same methods. While POSSESSING, combat inputs drive the Nightmare instead.

	  Action           Keyboard/Mouse   Gamepad        Possessed meaning
	  Attack (punch)   Left Click       R2             Nightmare 3-hit combo
	  Kick             Right Click*     X              Nightmare HEAVY attack
	                   (* a quick click; holding and dragging still turns the camera)
	  Weapon hotbar    1-3, ` = fists   Y cycles       -   (ARSENAL button by the hotbar: loadout)
	  Guard (hold)     Left Ctrl        L2             Nightmare HEAVY attack
	  Dodge (DIVE)     Shift            B              Nightmare dodge
	  Step back        X (or Shift      stick back + B
	                   while moving back)  (attack right after it = COUNTER punch / kick)
	  Lock-on camera   Z                Select / View  (same: locks from the Nightmare; LOCK button on phones)
	  Ability 1 / 2    Q / E            L1 / R1        (same)
	  Possession       F                D-Pad Left     exit possession
	  Ultimate         G                R3 (stick)     (same)
	  Command menu     V                L3 (stick)
	  Sic target       R                (command menu)
	  Defend/Aggress.  T (toggle)       (command menu)
	  Retreat          C                D-Pad Down
	  Summon           H                D-Pad Up
	  Build            B                (MENU hub → Workshop)
  MENU hub         (HUD on phones)  D-Pad Right     every menu in one place
  Close a menu     X button         B
	  PvP Colosseum    P                (HUD button)
  Codex            M                (HUD button)
  Goals            J                (HUD button)
  Party            L                (HUD button)
  Fighter          U                (HUD button)    moves, weapons (loadout) & run styles
  Settings         K                (⚙ HUD button)

	While a ProximityPrompt (Workshop, Forge, Boss Portal, Colosseum) is on screen, its
	key (E / gamepad X by default) belongs to the prompt and does NOT also fire the
	action above, so opening a station never wastes an ability or a Sic command.
]]

local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local InputController = {}

local controllers
local shownPrompts: { [ProximityPrompt]: true } = {}
local rightDown = nil -- { At, Moved } while the right mouse button is held
local RIGHT_CLICK_TIME = 0.3 -- seconds: a right-click shorter than this is a kick...
local RIGHT_CLICK_DRAG = 8 -- ...if the mouse barely moved (a drag turns the camera)

-- True if a visible prompt is listening for this key (it gets the press instead).
local function promptOwnsKey(keyCode: Enum.KeyCode): boolean
	for prompt in shownPrompts do
		if not prompt:IsDescendantOf(workspace) then
			shownPrompts[prompt] = nil -- removed while on screen (Hidden never fired): forget it
		elseif prompt.Enabled and (prompt.KeyboardKeyCode == keyCode or prompt.GamepadKeyCode == keyCode) then
			return true
		end
	end
	return false
end

local BINDINGS = {
	[Enum.UserInputType.MouseButton1] = "Attack",
	[Enum.KeyCode.ButtonR2] = "Attack",
	-- (right-click: a quick click = Kick, handled in Start, so dragging still turns the
	-- camera; while possessing it's the Nightmare's heavy attack)
	[Enum.KeyCode.ButtonX] = "Kick",
	[Enum.KeyCode.Backquote] = "Slot0", -- fists
	[Enum.KeyCode.One] = "Slot1",
	[Enum.KeyCode.Two] = "Slot2",
	[Enum.KeyCode.Three] = "Slot3",
	[Enum.KeyCode.ButtonY] = "CycleWeapon",
	[Enum.KeyCode.LeftControl] = "Guard", -- (in Studio only, Ctrl+WASD also triggers editor shortcuts)
	[Enum.KeyCode.ButtonL2] = "Guard",
	[Enum.KeyCode.LeftShift] = "Dodge",
	[Enum.KeyCode.RightShift] = "Dodge",
	[Enum.KeyCode.ButtonB] = "Dodge",
	[Enum.KeyCode.X] = "StepBack",
	[Enum.KeyCode.Q] = "Ability1",
	[Enum.KeyCode.ButtonL1] = "Ability1",
	[Enum.KeyCode.E] = "Ability2",
	[Enum.KeyCode.ButtonR1] = "Ability2",
	[Enum.KeyCode.F] = "Possess",
	[Enum.KeyCode.DPadLeft] = "Possess",
	[Enum.KeyCode.G] = "Ultimate",
	[Enum.KeyCode.ButtonR3] = "Ultimate",
	[Enum.KeyCode.V] = "CommandMenu", -- (Tab is taken by Roblox's player list)
	[Enum.KeyCode.ButtonL3] = "CommandMenu",
	[Enum.KeyCode.R] = "Sic", -- (controller: ATTACK TARGET in the command menu, L3)
	[Enum.KeyCode.T] = "Stance", -- (controller: DEFEND / AGGRESSIVE in the command menu)
	[Enum.KeyCode.C] = "Retreat",
	[Enum.KeyCode.DPadDown] = "Retreat",
	[Enum.KeyCode.H] = "Summon",
	[Enum.KeyCode.DPadUp] = "Summon",
	[Enum.KeyCode.B] = "Build",
	[Enum.KeyCode.P] = "PvP",
	[Enum.KeyCode.M] = "Codex",
	[Enum.KeyCode.J] = "Goals",
	[Enum.KeyCode.L] = "Party", -- (not O: Roblox uses I / O to zoom the camera)
	[Enum.KeyCode.K] = "Settings",
	[Enum.KeyCode.U] = "Fighter", -- moves, weapons (loadout) & run styles
	[Enum.KeyCode.DPadRight] = "Menu", -- controller: the MENU hub (Workshop is its first tile)
	[Enum.KeyCode.Z] = "LockOn",
	[Enum.KeyCode.ButtonSelect] = "LockOn",
}

-- Every menu that blocks combat input, with how to close it (controller B closes the
-- top-most open one). The reward screen isn't here: it has its own buttons.
local function openMenus()
	return {
		{ controllers.MenuController, "Close" },
		{ controllers.FighterController, "Close" },
		{ controllers.SettingsController, "Close" },
		{ controllers.ShowcaseController, "Close" },
		{ controllers.CodexController, "Close" },
		{ controllers.GoalsController, "Close" },
		{ controllers.PartyController, "Close" },
		{ controllers.CraftingController, "Close" },
		{ controllers.WorkshopController, "Close" },
		{ controllers.PvPController, "ClosePanel", "IsPanelOpen" },
		{ controllers.BossController, "ClosePortal", "IsPortalOpen" },
	}
end

local function anyMenuOpen(): boolean
	for _, entry in openMenus() do
		local controller, _, isOpen = entry[1], entry[2], entry[3] or "IsOpen"
		if controller[isOpen](controller) then
			return true
		end
	end
	return false
end

-- Controller B: close the top-most open menu. Returns true if it closed something.
local function closeTopMenu(): boolean
	for _, entry in openMenus() do
		local controller, close, isOpen = entry[1], entry[2], entry[3] or "IsOpen"
		if controller[isOpen](controller) then
			controller[close](controller)
			return true
		end
	end
	return false
end

function InputController:Init(registry)
	controllers = registry
end

function InputController:Perform(action: string)
	local combat = controllers.CombatController
	local workshop = controllers.WorkshopController
	local possession = controllers.PossessionController

	if action == "PvP" then
		controllers.PvPController:TogglePanel()
		return
	end
	if action == "Codex" then
		controllers.CodexController:Toggle()
		return
	end
	if action == "Goals" then
		controllers.GoalsController:Toggle()
		return
	end
	if action == "Party" then
		controllers.PartyController:Toggle()
		return
	end
	if action == "Settings" then
		controllers.SettingsController:Toggle()
		return
	end
	if action == "Menu" then
		controllers.MenuController:Toggle()
		return
	end
	if action == "Fighter" then
		controllers.FighterController:Toggle()
		return
	end
	if action == "Build" then
		if not possession:IsPossessing() and not controllers.PvPController:IsInMatch() then
			workshop:Toggle()
		end
		return
	end
	if anyMenuOpen() or controllers.RewardController:IsOpen() then
		return -- combat input is ignored while menus are open
	end

	-- While possessing, combat inputs control the Nightmare.
	if possession:IsPossessing() then
		if action == "Attack" then
			possession:Light()
		elseif action == "Guard" or action == "PossessedHeavy" or action == "Kick" then
			possession:Heavy()
		elseif action == "Dodge" or action == "StepBack" then
			possession:Dodge()
		elseif action == "Ability1" then
			combat:UseAbility(1)
		elseif action == "Ability2" then
			combat:UseAbility(2)
		elseif action == "Ultimate" then
			combat:Ultimate()
		elseif action == "Possess" then
			possession:Toggle()
		elseif action == "LockOn" then
			controllers.LockOnController:Toggle()
		end
		return
	end

	if action == "Attack" then
		combat:BasicAttack()
	elseif action == "Kick" then
		combat:Kick()
	elseif action:sub(1, 4) == "Slot" then
		controllers.MeleeController:EquipSlot(tonumber(action:sub(5)) or 0)
	elseif action == "CycleWeapon" then
		controllers.MeleeController:CycleWeapon()
	elseif action == "LockOn" then
		controllers.LockOnController:Toggle()
	elseif action == "Guard" then
		combat:SetGuard(true)
	elseif action == "Dodge" then
		combat:Dodge()
	elseif action == "StepBack" then
		combat:StepBack()
	elseif action == "Ability1" then
		combat:UseAbility(1)
	elseif action == "Ability2" then
		combat:UseAbility(2)
	elseif action == "Possess" then
		possession:Toggle()
	elseif action == "Ultimate" then
		combat:Ultimate()
	elseif action == "CommandMenu" then
		controllers.HUDController:ToggleCommandMenu()
	elseif action == "Sic" then
		combat:CommandAttackTarget()
	elseif action == "Stance" then
		combat:ToggleStance()
	elseif action == "Retreat" then
		combat:CommandRetreat()
	elseif action == "Summon" then
		combat:ToggleSummon()
	end
end

function InputController:Start()
	ProximityPromptService.PromptShown:Connect(function(prompt)
		shownPrompts[prompt] = true
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		shownPrompts[prompt] = nil
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		-- Controller B backs out of menus. Checked before gameProcessed: while you're
		-- navigating a menu with the pad, Roblox marks B as processed.
		if input.KeyCode == Enum.KeyCode.ButtonB and closeTopMenu() then
			return
		end
		if gameProcessed then
			return -- typing in a TextBox, clicking UI, etc.
		end
		if input.KeyCode ~= Enum.KeyCode.Unknown and promptOwnsKey(input.KeyCode) then
			return -- e.g. E at the Forge opens the Forge, not Ability 2
		end
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			rightDown = { At = os.clock(), Moved = 0 }
			if controllers.PossessionController:IsPossessing() then
				self:Perform("PossessedHeavy")
			end
			return
		end
		local action = BINDINGS[input.KeyCode] or BINDINGS[input.UserInputType]
		if action then
			self:Perform(action)
		end
	end)

	-- Right-click: holding and dragging turns the camera; a quick click is a KICK.
	UserInputService.InputChanged:Connect(function(input)
		if rightDown and input.UserInputType == Enum.UserInputType.MouseMovement then
			rightDown.Moved += input.Delta.Magnitude
		end
	end)

	-- Guard is held: release on button up (even if the UI ate the press).
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			local click = rightDown
			rightDown = nil
			if click and os.clock() - click.At <= RIGHT_CLICK_TIME and click.Moved <= RIGHT_CLICK_DRAG and not controllers.PossessionController:IsPossessing() then
				self:Perform("Kick")
			end
			return
		end
		local action = BINDINGS[input.KeyCode] or BINDINGS[input.UserInputType]
		if action == "Guard" then
			controllers.CombatController:SetGuard(false)
		end
	end)
end

return InputController
