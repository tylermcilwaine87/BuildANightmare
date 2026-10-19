--[[
	MeleeController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/MeleeController

	Your hand-to-hand fighting (Shared/MeleeDefinitions), the weapon HOTBAR and the ARSENAL.

	COMBOS: every attack (P) or kick (K) press adds to the combo string ("P", "PP", "PPK"...).
	If that string is a known, unlocked move it plays, otherwise a new combo starts with
	this press. Presses during a move are BUFFERED and fire the moment it can be chained
	(its Cancel time), so mashing in rhythm flows. The server re-checks everything.
	  * right after a step back (CombatController:TakeCounter): COUNTER punch / kick
	  * K after running for a moment: DROP KICK (once unlocked)
	  * a weapon out: P is the weapon's chain (each attack spends a charge; the last one puts
	    it away to recharge and your fists come back up), K still kicks
	Each move: face your target (lock-on, else the closest enemy where you're aiming),
	slide in (Lunge), play the pose. The Chain Whip's physical chain is flung out along the
	swing (lash). Nothing is drawn in front of you: the hits themselves show.

	HOTBAR: ` = fists, 1-3 = the weapons in your loadout; gamepad Y cycles; on phones, tap.
	ARSENAL (the button by the hotbar): opens the FIGHTER menu's WEAPONS tab
	(FighterController), where you choose which (up to 3) weapons you carry. Saved.
	Also handles being pulled by someone's magnet (PlayerFX "Pulled") and your own magnet
	dragging you to a boss (PlayerFX "MagnetZip"), and marks you "InFight" (a client-only
	attribute: HandlerAnimator raises your guard) while locked on or trading blows.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Melee = require(Shared:WaitForChild("MeleeDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local MeleeController = {}

local localPlayer = Players.LocalPlayer
local MOVES = Melee.Moves
local WEAPONS = Melee.WeaponsById
local C = UIKit.Colors
local AIM_ASSIST_RANGE = 12 -- studs: swings turn toward an enemy this close where you aim
-- studs from the target's body where your root stops when you step in: with the weight
-- shift in the pose, a straight arm puts the fist right on them
local CONTACT = 2.3
local IN_FIGHT_TIME = 4 -- seconds after your last strike that your guard stays up

local controllers
local combatAction: RemoteEvent

local seq = "" -- the combo so far
local current = nil -- the move playing now
local currentStart = -math.huge
local buffered: string? = nil
local lastStrike = -math.huge
local runningFor = 0 -- seconds of continuous running (drop kick)
local hotbar = {} -- UI

function MeleeController:Init(registry)
	controllers = registry
	combatAction = Net.Get("CombatAction")
end

local function level(): number
	local profile = controllers.ClientState.Profile
	return profile and profile.Level or 1
end

local function loadout(): { string }
	local profile = controllers.ClientState.Profile
	return profile and profile.Loadout or { "Magnet" }
end

local function weaponOf(character: Model?): string
	return character and character:GetAttribute("Weapon") or "Fists"
end

-- Seconds until a weapon is back from recharging (0 = ready), and its charges left.
local function charges(weaponId: string): (number, number)
	local character = localPlayer.Character
	local weapon = WEAPONS[weaponId]
	if not character or not weapon then
		return 0, math.huge
	end
	local readyAt = character:GetAttribute("ReadyAt_" .. weaponId)
	local wait = readyAt and math.max(0, readyAt - Workspace:GetServerTimeNow()) or 0
	local uses = character:GetAttribute("Uses_" .. weaponId) or weapon.Uses
	return wait, wait > 0 and 0 or uses
end

-- A quick flat slide of your own character.
local function slide(root: BasePart, direction: Vector3, distance: number, duration: number)
	local attachment = root:FindFirstChild("RootAttachment")
	if not attachment or distance <= 0.2 then
		return
	end
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e6 -- (strong enough that the floor's friction never cuts it short)
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * (distance / duration)
	mover.Parent = root
	task.delay(duration, function()
		mover:Destroy()
	end)
end

-- What to swing at: the lock-on target, else the closest living enemy within `range` that
-- lies roughly where you're aiming (within ~65 degrees of the camera's direction, or of
-- your facing on touch screens), else nothing. Never turns you to something behind you.
local function aimTarget(root: BasePart, range: number): BasePart?
	local locked = controllers.LockOnController:GetTarget()
	local lockedRoot = locked and locked:FindFirstChild("HumanoidRootPart")
	if lockedRoot then
		return lockedRoot
	end
	local camera = Workspace.CurrentCamera
	local aim = (UserInputService.TouchEnabled or not camera) and Util.FlatUnit(root.CFrame.LookVector) or Util.FlatUnit(camera.CFrame.LookVector)
	if not aim then
		return nil
	end
	local candidates = CollectionService:GetTagged("Enemy")
	for _, model in controllers.PvPController:GetOpponentModels() do
		table.insert(candidates, model)
	end
	local best, bestDistance = nil, range
	for _, model in candidates do
		local enemyRoot = model:FindFirstChild("HumanoidRootPart")
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if enemyRoot and humanoid and humanoid.Health > 0 and not model:GetAttribute("Defeated") then
			local offset = Vector3.new(enemyRoot.Position.X - root.Position.X, 0, enemyRoot.Position.Z - root.Position.Z)
			local distance = offset.Magnitude - math.max(enemyRoot.Size.X, enemyRoot.Size.Z) / 2
			if distance < bestDistance and (offset.Magnitude < 0.1 or offset.Unit:Dot(aim) > 0.42) then
				best, bestDistance = enemyRoot, distance
			end
		end
	end
	return best
end

local function face(root: BasePart, direction: Vector3?)
	if direction then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direction)
	end
end

-- Can you start a move at all right now?
local function canFight(character: Model?, humanoid: Humanoid?): boolean
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if character:GetAttribute("Ragdolled") or character:GetAttribute("Diving") or character:GetAttribute("GuardBroken") then
		return false
	end
	if controllers.WorkshopController:IsOpen() or controllers.PossessionController:IsPossessing() then
		return false
	end
	return true
end

local sprinting = false

-- DROP KICK: sprint flat out at the target (its own sprint animation) until you're in
-- range, then plant, spring off the floor laid back almost flat and drive both feet in.
-- No target: you leap straight out of your run.
function MeleeController:DropKick(character: Model, humanoid: Humanoid, root: BasePart)
	local move = MOVES.DropKick
	sprinting = true
	seq, current, buffered = "", nil, nil
	lastStrike = os.clock()
	local targetRoot = aimTarget(root, move.SprintRange)
	local attachment = root:FindFirstChild("RootAttachment")
	if targetRoot and attachment then
		local mover = Instance.new("LinearVelocity")
		mover.Attachment0 = attachment
		mover.MaxForce = 1e5
		mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		mover.PrimaryTangentAxis = Vector3.xAxis
		mover.SecondaryTangentAxis = Vector3.zAxis
		mover.RelativeTo = Enum.ActuatorRelativeTo.World
		mover.Parent = root
		local start, lastStride = os.clock(), -math.huge
		local strideTime = controllers.HandlerAnimator:Duration("SprintCharge") or 0.34
		while targetRoot.Parent and character:GetAttribute("Ragdolled") == nil and humanoid.Health > 0 do
			local offset = Vector3.new(targetRoot.Position.X - root.Position.X, 0, targetRoot.Position.Z - root.Position.Z)
			local gap = offset.Magnitude - math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
			if gap <= move.Range - 1 or os.clock() - start >= move.SprintTime or offset.Magnitude < 0.1 then
				break
			end
			local direction = offset.Unit
			mover.PlaneVelocity = Vector2.new(direction.X, direction.Z) * move.SprintSpeed
			face(root, direction)
			if os.clock() - lastStride >= strideTime then
				lastStride = os.clock()
				controllers.HandlerAnimator:Play("SprintCharge")
			end
			RunService.Heartbeat:Wait()
		end
		mover:Destroy()
	end
	sprinting = false
	if not canFight(character, humanoid) then
		return
	end
	-- the leap
	local direction = targetRoot and targetRoot.Parent and Util.FlatUnit(targetRoot.Position - root.Position) or Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	face(root, direction)
	current, currentStart, seq = move, os.clock(), "K"
	humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	root.AssemblyLinearVelocity = direction * (move.Leap / 0.3) + Vector3.new(0, 26, 0)
	controllers.HandlerAnimator:Play(move.Pose)
	controllers.EffectsController:Afterimage(character)
	combatAction:FireServer("Melee", "K", "Drop")
end

------------------------------------------------------------------------------------------
-- Combos
------------------------------------------------------------------------------------------
function MeleeController:Press(input: string)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not canFight(character, humanoid) then
		return
	end
	if sprinting then
		return -- committed to the drop kick
	end
	local now = os.clock()
	-- mid-move: remember the press and fire it the moment the move can be chained
	if current and now < currentStart + current.Cancel then
		buffered = input
		return
	end
	self:Fire(input)
end

function MeleeController:Fire(input: string)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not canFight(character, humanoid) or not root then
		return
	end
	local now = os.clock()
	local lvl = level()
	local weapon = weaponOf(character)

	local moveId, flag, nextSeq
	if controllers.CombatController:TakeCounter() then
		-- right after a step back: dash back in with a counter punch / kick
		moveId = input == "K" and "CounterKick" or "CounterPunch"
		flag, nextSeq = "Counter", input
	elseif input == "K" and runningFor >= 0.35 and seq == "" and Melee.MoveUnlocked("DropKick", lvl) then
		-- running K: sprint at them, then leap into the drop kick
		task.spawn(self.DropKick, self, character, humanoid, root)
		return
	else
		local continuing = current ~= nil and now <= currentStart + current.Duration + Melee.ComboWindow
		nextSeq = (continuing and seq or "") .. input
		moveId = #nextSeq <= 5 and Melee.Resolve(weapon, nextSeq, lvl) or nil
		if not moveId then
			nextSeq = input -- not a known combo: start a new one with this press
			moveId = Melee.Resolve(weapon, nextSeq, lvl)
		end
	end
	local move = moveId and MOVES[moveId]
	if not move then
		return
	end
	if move.Weapon then
		local wait = charges(weapon)
		if wait > 0 then
			return -- recharging (the server is putting it away)
		end
	end

	seq = nextSeq
	current = move
	currentStart = now
	buffered = nil
	lastStrike = now

	-- face what you're fighting, then move into it
	local reach = move.Range + (move.Lunge or 0)
	local assist = math.max(AIM_ASSIST_RANGE, flag == "Counter" and Config.Handler.StepBack.CounterDistance + reach or reach + 2)
	local targetRoot = aimTarget(root, assist)
	local direction
	if targetRoot then
		direction = Util.FlatUnit(targetRoot.Position - root.Position)
	elseif UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		direction = Util.FlatUnit(Workspace.CurrentCamera.CFrame.LookVector) -- mouse aims with the camera
	end
	direction = direction or Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	face(root, direction)

	if flag == "Counter" then
		-- fly the whole gap back in and land the strike ON them (Superman punch / flying knee)
		local step = Config.Handler.StepBack
		local distance = step.CounterDistance * 0.7
		if targetRoot then
			local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
			distance = math.clamp(Util.FlatDistance(targetRoot.Position, root.Position) - radius - (move.Contact or CONTACT), 0, step.CounterDistance)
		end
		slide(root, direction, distance, step.CounterDuration)
		controllers.EffectsController:Afterimage(character)
	elseif move.Lunge then
		local distance = move.Lunge
		if targetRoot then
			-- step in until the strike lands ON them (fist / shin right at their body),
			-- never through them
			local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
			distance = math.clamp(Util.FlatDistance(targetRoot.Position, root.Position) - radius - (move.Contact or CONTACT), 0, move.Lunge)
		end
		slide(root, direction, distance, math.max(move.HitTime, 0.08))
	end

	controllers.HandlerAnimator:Play(move.Pose)
	combatAction:FireServer("Melee", seq, flag)

	if move.Lash then
		-- the chain leaves just before the arm finishes its snap
		task.delay(move.HitTime * 0.75, function()
			if current == move and currentStart == now and character.Parent then
				controllers.ChainSimulator:Lash(character, Util.FlatUnit(root.CFrame.LookVector) or direction, move.Arc > 90)
			end
		end)
	end
	-- fire a buffered press as soon as this move can be chained
	task.delay(move.Cancel, function()
		if current == move and currentStart == now and buffered then
			local nextInput = buffered
			buffered = nil
			self:Fire(nextInput)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Hotbar & Arsenal
------------------------------------------------------------------------------------------
-- Slot 0 = fists, 1..3 = your loadout in order.
local function weaponForSlot(slot: number): string?
	if slot == 0 then
		return "Fists"
	end
	return loadout()[slot]
end

function MeleeController:EquipSlot(slot: number)
	local character = localPlayer.Character
	if not character or controllers.PossessionController:IsPossessing() then
		return
	end
	local weaponId = weaponForSlot(slot)
	if not weaponId then
		controllers.HUDController:Toast("Empty slot: pick its weapon in the ARSENAL (button by the hotbar).", nil, 2)
		return
	end
	-- pressing the slot you already hold puts your fists back up
	if weaponOf(character) == weaponId and slot ~= 0 then
		weaponId = "Fists"
	end
	if weaponId ~= "Fists" then
		local weapon = WEAPONS[weaponId]
		if not Melee.WeaponUnlocked(weaponId, level()) then
			controllers.HUDController:Toast(("%s unlocks at level %d."):format(weapon.Display, weapon.Unlock.Level), nil, 2)
			return
		end
		local wait = charges(weaponId)
		if wait > 0 then
			controllers.HUDController:Toast(("%s is recharging: %ds"):format(weapon.Display, math.ceil(wait)), nil, 1.5)
			return
		end
	end
	seq, current, buffered = "", nil, nil
	combatAction:FireServer("Equip", weaponId)
end

-- Gamepad Y: fists -> each ready weapon in your loadout -> fists...
function MeleeController:CycleWeapon()
	local held = weaponOf(localPlayer.Character)
	local order = { "Fists" }
	for _, id in loadout() do
		if Melee.WeaponUnlocked(id, level()) and charges(id) <= 0 then
			table.insert(order, id)
		end
	end
	local index = table.find(order, held) or 1
	seq, current, buffered = "", nil, nil
	combatAction:FireServer("Equip", order[index % #order + 1])
end

function MeleeController:SetLoadout(list: { string })
	combatAction:FireServer("Loadout", list)
end

-- (the ARSENAL lives in the FIGHTER menu now: FighterController's WEAPONS tab)
function MeleeController:ToggleArsenal()
	controllers.FighterController:Toggle("Weapons")
end

local function buildHotbar()
	local gui = UIKit.New("ScreenGui", {
		Name = "Hotbar",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 6,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	local count = 1 + Melee.LoadoutSlots + 1
	local bar = UIKit.New("Frame", {
		Name = "Slots",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -140),
		Size = UDim2.fromOffset(count * 58 + (count - 1) * 6, 58),
		BackgroundTransparency = 1,
		Parent = gui,
	}, { UIKit.List(6, Enum.FillDirection.Horizontal) })
	bar:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
	UIKit.AutoScale(bar)
	hotbar.Gui = gui
	hotbar.Slots = {}
	local keyboard = UserInputService.KeyboardEnabled
	for slot = 0, Melee.LoadoutSlots do
		local button = UIKit.Button({
			Text = "",
			Size = UDim2.fromOffset(58, 58),
			BackgroundColor3 = C.Panel,
			BackgroundTransparency = 0.15,
			LayoutOrder = slot,
			Parent = bar,
		}, function()
			MeleeController:EquipSlot(slot)
		end)
		local stroke = UIKit.Stroke(C.Accent, 2, 0.6)
		stroke.Parent = button
		local icon = UIKit.Label({ Text = slot == 0 and "👊" or "", Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 24, Parent = button })
		local name = UIKit.Label({ Text = slot == 0 and "FISTS" or "", Position = UDim2.new(0, 0, 1, -20), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 11, Parent = button })
		UIKit.Label({ Text = keyboard and (slot == 0 and "`" or tostring(slot)) or "", Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(14, 14), TextColor3 = C.Warn, MaxTextSize = 11, Parent = button })
		local usesLabel = UIKit.Label({ Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(24, 14), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Text, MaxTextSize = 11, Parent = button })
		-- recharge: a dark overlay that drains, with the seconds left on top
		local cooldown = UIKit.New("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			Parent = button,
		})
		local timer = UIKit.Label({ Text = "", Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Text, MaxTextSize = 18, Font = UIKit.FontHeavy, ZIndex = 3, Parent = button })
		hotbar.Slots[slot] = { Button = button, Stroke = stroke, Icon = icon, Name = name, Uses = usesLabel, Cooldown = cooldown, Timer = timer }
	end
	-- the ARSENAL button
	UIKit.Button({ Text = "ARSENAL", Size = UDim2.fromOffset(58, 58), BackgroundColor3 = C.PanelLighter, BackgroundTransparency = 0.15, LayoutOrder = 99, MaxTextSize = 11, Parent = bar }, function()
		MeleeController:ToggleArsenal()
	end)
end

local function refreshHotbar()
	if not hotbar.Slots then
		return
	end
	local held = weaponOf(localPlayer.Character)
	local carried = loadout()
	for slot, ui in hotbar.Slots do
		local id = slot == 0 and "Fists" or carried[slot]
		local weapon = id and WEAPONS[id]
		local equipped = id ~= nil and held == id
		ui.Stroke.Color = weapon and weapon.Color or C.Accent
		ui.Stroke.Transparency = equipped and 0 or 0.6
		ui.Stroke.Thickness = equipped and 3 or 2
		ui.Button.BackgroundColor3 = equipped and C.PanelLighter or C.Panel
		if slot > 0 then
			ui.Icon.Text = weapon and weapon.Icon or "+"
			ui.Name.Text = weapon and weapon.Short or "EMPTY"
		end
		ui.Name.TextColor3 = equipped and C.Text or C.SubText
		local wait, uses = 0, nil
		if weapon then
			wait, uses = charges(id)
		end
		ui.Cooldown.Size = UDim2.fromScale(1, weapon and wait > 0 and wait / weapon.Recharge or 0)
		ui.Timer.Text = wait > 0 and tostring(math.ceil(wait)) or ""
		ui.Uses.Text = weapon and wait <= 0 and weapon.Uses > 1 and ("x" .. uses) or ""
	end
end

------------------------------------------------------------------------------------------
-- Being moved by magnets
------------------------------------------------------------------------------------------
local function moveBody(model: Model?, to: Vector3, time: number)
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local attachment = root and (root:FindFirstChild("RootAttachment") or root:FindFirstChild("FacingAttachment"))
	if not root or not attachment then
		return
	end
	local offset = to - root.Position
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.MaxForce = 1e6
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.PlaneVelocity = Vector2.new(offset.X, offset.Z) / time
	mover.Parent = root
	root.AssemblyLinearVelocity += Vector3.new(0, 10, 0)
	task.delay(time, function()
		mover:Destroy()
	end)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function MeleeController:Start()
	buildHotbar()
	local function watch(character: Model)
		character:GetAttributeChangedSignal("Weapon"):Connect(function()
			seq, current, buffered = "", nil, nil -- a new weapon starts a new combo
			refreshHotbar()
		end)
		-- knocked down mid-combo: the combo is over
		character:GetAttributeChangedSignal("Ragdolled"):Connect(function()
			seq, current, buffered = "", nil, nil
		end)
	end
	localPlayer.CharacterAdded:Connect(function(character)
		seq, current, buffered = "", nil, nil
		watch(character)
	end)
	if localPlayer.Character then
		watch(localPlayer.Character)
	end
	controllers.ClientState.Changed:Connect(refreshHotbar)

	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		local character = localPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		-- how long you've been running flat out (drop kick needs a run-up)
		local running = humanoid ~= nil
			and humanoid.MoveDirection.Magnitude > 0.5
			and humanoid.WalkSpeed >= 12
			and humanoid:GetState() == Enum.HumanoidStateType.Running
		runningFor = running and runningFor + dt or 0
		-- a combo left alone long enough is over
		if current and os.clock() > currentStart + current.Duration + Melee.ComboWindow then
			seq, current = "", nil
		end
		-- guard up while you're locked on or trading blows (HandlerAnimator)
		if character then
			local inFight = controllers.LockOnController:IsLocked() or os.clock() - lastStrike < IN_FIGHT_TIME
			if character:GetAttribute("InFight") ~= (inFight or nil) then
				character:SetAttribute("InFight", inFight or nil)
			end
		end
		elapsed += dt
		if elapsed >= 0.1 then
			elapsed = 0
			refreshHotbar()
		end
	end)

	Net.Get("PlayerFX").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" or typeof(data.To) ~= "Vector3" then
			return
		end
		local time = math.clamp(tonumber(data.Time) or 0.4, 0.1, 0.8)
		if kind == "MagnetZip" then
			moveBody(localPlayer.Character, data.To, time) -- your magnet hauls you to a boss
		elseif kind == "Pulled" then
			local model = data.Model
			if typeof(model) ~= "Instance" or not model:IsA("Model") then
				return
			end
			-- only bodies this client actually moves: your character or your possessed Nightmare
			if model == localPlayer.Character or model == controllers.PossessionController:GetModel() then
				moveBody(model, data.To, time)
			end
		end
	end)
end

return MeleeController
