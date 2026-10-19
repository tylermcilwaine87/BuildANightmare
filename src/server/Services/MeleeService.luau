--[[
	MeleeService  (ModuleScript)
	Location: ServerScriptService/Server/Services/MeleeService

	The server side of the Handler's hand-to-hand fighting (Shared/MeleeDefinitions):
	  * "Melee", seq, flag (CombatAction): the client sends the combo string so far
	    ("PPK"...). The server works out the move itself, checks it's unlocked, that the
	    combo really continues the last move inside its timing (or starts a new one), and
	    that nothing is spammed faster than a move's Cancel time. Then, at the move's
	    HitTime, it lands the hit on everything inside the move's ARC (a slice of circle in
	    front of you: swings sweep, a spin hits all round) from wherever the Handler is by
	    then (the client lunges). flag "Counter" = right after a step back, "Drop" = a
	    running drop kick.
	  * WEAPON CHARGES: each weapon attack spends a charge; when the last is spent the
	    weapon goes back on your belt (your fists come up) and recharges. Mirrored to the
	    client as character attributes "Uses_<id>" and "ReadyAt_<id>" (server time).
	  * The MAGNET: held out, it drags the enemy in front of you to you over PullTime.
	    Bosses / anything anchored don't budge, so it drags YOU to them. Client-owned bodies
	    (players, a possessed Nightmare) are moved by their owner's client (PlayerFX).
	  * The STORM SPEAR is thrown: it flies along your aim to the first enemy in its path
	    (clients draw it: WorldFX "SpearThrow") and strikes on arrival.
	  * "Equip", weaponId / "Loadout", { ids }: put a weapon from your loadout in your hand
	    (or Fists); choose the (up to 3) weapons you carry. The loadout is saved.
	Every move stamps the character's "HPose" attribute so other players' clients play it.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Melee = require(Shared:WaitForChild("MeleeDefinitions"))
local WeaponModels = require(script.Parent:WaitForChild("WeaponModels"))

local MeleeService = {}

local MOVES = Melee.Moves
local WEAPONS = Melee.WeaponsById
local states: { [Player]: any } = {}
local poseCounter = 0

function MeleeService:Init(services)
	self.Services = services
	self.PlayerFX = Net.Get("PlayerFX")
	self.UIState = Net.Get("UIStateUpdate")
end

local function stateOf(player: Player)
	local state = states[player]
	if not state then
		state = { Seq = "", Start = -math.huge, Move = nil, Weapon = "Fists", Uses = {}, ReadyAt = {} }
		states[player] = state
	end
	return state
end

function MeleeService:LevelOf(player: Player): number
	local profile = self.Services.PlayerDataService:Get(player)
	return profile and profile.Level or 1
end

function MeleeService:LoadoutOf(player: Player): { string }
	local profile = self.Services.PlayerDataService:Get(player)
	return profile and profile.Loadout or { "Magnet" }
end

-- Tells every other client to play this pose on the character.
function MeleeService:StampPose(character: Model?, pose: string)
	if not character then
		return
	end
	poseCounter += 1
	character:SetAttribute("HPose", pose .. "#" .. poseCounter)
end

------------------------------------------------------------------------------------------
-- Weapon charges
------------------------------------------------------------------------------------------
-- Charges left for `weaponId` right now (refilled once its recharge has finished).
function MeleeService:UsesLeft(player: Player, weaponId: string): number
	local weapon = WEAPONS[weaponId]
	if not weapon then
		return math.huge
	end
	local state = stateOf(player)
	if (state.ReadyAt[weaponId] or 0) > os.clock() then
		return 0
	end
	return state.Uses[weaponId] or weapon.Uses
end

-- Mirrors one weapon's charges to the client (hotbar).
local function publishCharges(player: Player, weaponId: string)
	local character = player.Character
	local state = stateOf(player)
	if not character then
		return
	end
	local readyIn = math.max(0, (state.ReadyAt[weaponId] or 0) - os.clock())
	character:SetAttribute("Uses_" .. weaponId, readyIn > 0 and 0 or (state.Uses[weaponId] or WEAPONS[weaponId].Uses))
	character:SetAttribute("ReadyAt_" .. weaponId, readyIn > 0 and Workspace:GetServerTimeNow() + readyIn or nil)
end

-- Spends one charge; the last one sends the weapon back to recharge (fists come up once
-- the swing that spent it has finished).
function MeleeService:SpendCharge(player: Player, weaponId: string, afterSeconds: number)
	local weapon = WEAPONS[weaponId]
	local state = stateOf(player)
	local left = self:UsesLeft(player, weaponId) - 1
	if left <= 0 then
		state.Uses[weaponId] = nil
		state.ReadyAt[weaponId] = os.clock() + weapon.Recharge
		task.delay(afterSeconds, function()
			if state.Weapon == weaponId then
				state.Weapon = "Fists"
				state.Seq = ""
				self:ApplyWeapon(player)
			end
		end)
		task.delay(weapon.Recharge + 0.05, function()
			if player.Parent then
				publishCharges(player, weaponId)
			end
		end)
	else
		state.Uses[weaponId] = left
	end
	publishCharges(player, weaponId)
end

------------------------------------------------------------------------------------------
-- Moves
------------------------------------------------------------------------------------------
function MeleeService:HandleMelee(player: Player, seq, flag)
	if type(seq) ~= "string" or #seq < 1 or #seq > 5 or seq:find("[^PK]") then
		return
	end
	if flag ~= nil and flag ~= "Counter" and flag ~= "Drop" then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or humanoid.Health <= 0 or not root or character:GetAttribute("Ragdolled") then
		return
	end
	local services = self.Services
	if services.HandlerService:IsGuarding(player) or services.PossessionService:IsPossessing(player) or services.DuelService:IsFrozen(player) then
		return
	end

	local state = stateOf(player)
	local now = os.clock()
	local tol = Melee.Tolerance
	local level = self:LevelOf(player)
	local weapon = state.Weapon

	local moveId
	local free = false -- counters skip the timing checks (one per step back)
	if flag == "Counter" and #seq == 1 and services.HandlerService:ConsumeCounter(player) then
		moveId = seq == "K" and "CounterKick" or "CounterPunch"
		free = true
	elseif flag == "Drop" and seq == "K" and Melee.MoveUnlocked("DropKick", level) then
		moveId = "DropKick"
	else
		moveId = Melee.Resolve(weapon, seq, level)
		-- A combo string must continue the last move inside its window. If it doesn't
		-- (lag, a dropped input), start fresh from this input instead of locking up.
		local last = state.Move
		local continues = #seq > 1 and last ~= nil and state.Seq == seq:sub(1, -2) and now <= state.Start + last.Duration + Melee.ComboWindow + tol
		if #seq > 1 and not continues then
			seq = seq:sub(-1)
			moveId = Melee.Resolve(weapon, seq, level)
		end
	end
	if not moveId then
		return
	end
	local move = MOVES[moveId]
	if not free and state.Move and now < state.Start + state.Move.Cancel - tol then
		return -- faster than the last move allows
	end
	if move.Weapon then
		if self:UsesLeft(player, weapon) <= 0 then
			return -- recharging (the client shows it)
		end
		-- (a thrown spear leaves your hand at the release, not at the end of the throw)
		self:SpendCharge(player, weapon, move.Throw and move.HitTime or move.Duration)
	end

	state.Seq = seq
	state.Start = now
	state.Move = move
	self:StampPose(character, move.Pose)

	-- the weapon's motion trail, for the length of the swing
	local trail = move.Trail and character:FindFirstChild("HeldWeapon") and character.HeldWeapon:FindFirstChild("SwingTrail", true)
	if trail then
		trail.Enabled = true
		task.delay(move.Duration * 0.75, function()
			-- (unless a newer swing has taken it over)
			local newerSwing = state.Start > now and state.Move and state.Move.Trail
			if trail.Parent and not newerSwing then
				trail.Enabled = false
			end
		end)
	end

	-- a signature combo pulled off for the first time: DISCOVERED
	local comboKey = (flag == "Counter" and "Counter:" .. seq) or (flag == "Drop" and "Drop:K") or (Melee.Resolve("Fists", seq, level) == moveId and seq) or nil
	local combo = comboKey and Melee.CombosBySeq[comboKey]
	if combo then
		self:Discover(player, combo)
	end

	task.delay(move.HitTime, function()
		if not root.Parent or humanoid.Health <= 0 or character:GetAttribute("Ragdolled") or state.Move ~= move or state.Start ~= now then
			return -- knocked down (or interrupted) before it landed
		end
		if move.Pull then
			self:MagnetPull(player, character, root, move)
		elseif move.Throw then
			self:ThrowSpear(player, character, root, move)
		else
			self:LandHit(player, character, root, move)
		end
	end)
end

function MeleeService:Discover(player: Player, combo)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile or profile.Combos[combo.Id] then
		return
	end
	profile.Combos[combo.Id] = true
	self.UIState:FireClient(player, "ComboDiscovered", { Id = combo.Id })
	self.UIState:FireClient(player, "Profile", self.Services.PlayerDataService:Snapshot(player))
end

------------------------------------------------------------------------------------------
-- Run styles (FIGHTER menu)
------------------------------------------------------------------------------------------
-- Buy (with coins) or switch to a run style. Returns a result for the client.
function MeleeService:HandleRun(player: Player, action, runId)
	local run = type(runId) == "string" and Melee.RunsById[runId]
	local profile = self.Services.PlayerDataService:Get(player)
	if not run or not profile then
		return
	end
	if action == "BuyRun" and not profile.Runs[run.Id] then
		if (profile.Coins or 0) < run.Cost then
			self.UIState:FireClient(player, "Toast", { Text = ("%s costs %d coins."):format(run.Name, run.Cost) })
			return
		end
		profile.Coins -= run.Cost
		profile.Runs[run.Id] = true
		profile.RunStyle = run.Id
	elseif action == "SetRun" and profile.Runs[run.Id] then
		profile.RunStyle = run.Id
	else
		return
	end
	if player.Character then
		player.Character:SetAttribute("RunStyle", profile.RunStyle)
	end
	self.UIState:FireClient(player, "Profile", self.Services.PlayerDataService:Snapshot(player))
end

local function ignoreFor(self, player: Player, character: Model)
	local ignore = { character }
	local nightmare = self.Services.NightmareSpawnService:GetNightmare(player)
	if nightmare then
		table.insert(ignore, nightmare)
	end
	return ignore
end

-- Everything you could hit inside `range` and an `arc` (degrees) in front of you, nearest first.
function MeleeService:TargetsInArc(player: Player, character: Model, root: BasePart, range: number, arc: number): { Model }
	local services = self.Services
	local look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	local cosHalf = math.cos(math.rad(math.min(arc, 360) / 2))
	local found = {}
	for _, model in services.HitDetectionService:QueryRadius(root.Position, range + 4, ignoreFor(self, player, character), root.Position) do
		local targetRoot = model:FindFirstChild("HumanoidRootPart")
		if targetRoot and services.CombatService:CanDamage(character, model) and math.abs(targetRoot.Position.Y - root.Position.Y) <= Melee.HitHeight + targetRoot.Size.Y / 2 then
			local offset = Vector3.new(targetRoot.Position.X - root.Position.X, 0, targetRoot.Position.Z - root.Position.Z)
			local radius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
			local distance = offset.Magnitude
			-- inside the arc (big bodies count from their edge), within reach of their edge
			local inArc = arc >= 360 or distance < radius + 1 or offset.Unit:Dot(look) >= cosHalf - radius / math.max(distance, 1)
			if inArc and distance - radius <= range then
				table.insert(found, { Model = model, Distance = distance })
			end
		end
	end
	table.sort(found, function(a, b)
		return a.Distance < b.Distance
	end)
	local models = {}
	for _, entry in found do
		table.insert(models, entry.Model)
	end
	return models
end

function MeleeService:LandHit(player: Player, character: Model, root: BasePart, move)
	-- the client slid forward during the windup; reach a little further to match
	local range = move.Range + (move.Lunge or 0) * 0.4 + (move.Leap or 0) * 0.4
	-- the way the strike's force travels (MeleeDefinitions HitDir, in the striker's frame)
	local hitDirection = move.HitDir and root.CFrame:VectorToWorldSpace(Vector3.new(move.HitDir[1], move.HitDir[2], -move.HitDir[3])).Unit
	local hitSomething = false
	for _, target in self:TargetsInArc(player, character, root, range, move.Arc) do
		local dealt = self.Services.CombatService:ApplyDamage({
			Attacker = character,
			Target = target,
			BaseDamage = move.Damage,
			AttackPower = 100,
			Knockback = move.Knockback,
			Heavy = move.Heavy,
			Stagger = move.Stagger,
			Status = move.Status,
			HitDirection = hitDirection,
			Crumple = move.Crumple,
			Source = "Handler:" .. move.Id,
		})
		hitSomething = hitSomething or dealt > 0
	end
	if hitSomething then
		self.Services.TutorialService:Notify(player, "HandlerHit")
	end
end

------------------------------------------------------------------------------------------
-- The Magnet
------------------------------------------------------------------------------------------
-- Drags a body owned by the server toward `to` over `time` seconds.
local function pullServerBody(targetRoot: BasePart, to: Vector3, time: number)
	local attachment = Instance.new("Attachment")
	attachment.Name = "MagnetPull"
	attachment.Parent = targetRoot
	local mover = Instance.new("LinearVelocity")
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	mover.PrimaryTangentAxis = Vector3.xAxis
	mover.SecondaryTangentAxis = Vector3.zAxis
	local offset = to - targetRoot.Position
	mover.PlaneVelocity = Vector2.new(offset.X, offset.Z) / time
	mover.MaxForce = 1e6
	mover.Parent = targetRoot
	targetRoot.AssemblyLinearVelocity += Vector3.new(0, 10, 0) -- lifted just off the floor
	task.delay(time, function()
		attachment:Destroy()
	end)
end

function MeleeService:MagnetPull(player: Player, character: Model, root: BasePart, move)
	local services = self.Services
	local best = self:TargetsInArc(player, character, root, move.Range, move.Arc)[1]
	if RunService:IsStudio() then
		print(("[Melee] magnet grabbed %s"):format(best and best.Name or "nothing"))
	end
	if not best then
		return
	end
	local targetRoot = best.HumanoidRootPart
	local look = Util.FlatUnit(targetRoot.Position - root.Position) or Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis
	local targetRadius = math.max(targetRoot.Size.X, targetRoot.Size.Z) / 2
	Net.FireNearby(services.TelegraphService.WorldFX, root.Position, Config.Performance.EffectRadius, "MagnetBeam", { From = character, To = best, Time = move.PullTime })

	local isBoss = best:GetAttribute("KnockbackImmune") or CollectionService:HasTag(best, "Boss")
	if isBoss then
		-- a boss is far too heavy to move: the magnet yanks YOU in to IT, and the jolt
		-- rattles the boss hard (a big chunk of stagger: line up a punish)
		local stop = targetRoot.Position - look * (targetRadius + 4)
		self.PlayerFX:FireClient(player, "MagnetZip", { To = stop, Time = move.PullTime })
	elseif targetRoot.Anchored then
		-- bolted down (training dummies): it just takes the jolt
	else
		local dest = root.Position + look * (targetRadius + 3.5)
		local owner = targetRoot:GetNetworkOwner()
		if owner then
			-- a player (or a Nightmare they're possessing) moves their own body
			self.PlayerFX:FireClient(owner, "Pulled", { Model = best, To = dest, Time = move.PullTime })
		else
			pullServerBody(targetRoot, dest, move.PullTime)
		end
	end
	services.CombatService:ApplyDamage({
		Attacker = character,
		Target = best,
		BaseDamage = isBoss and move.Damage * 4 or move.Damage,
		AttackPower = 100,
		Stagger = isBoss and move.BossStagger or move.Stagger,
		Source = "Handler:MagnetPull",
	})
end

------------------------------------------------------------------------------------------
-- The Storm Spear (thrown)
------------------------------------------------------------------------------------------
function MeleeService:ThrowSpear(player: Player, character: Model, root: BasePart, move)
	local services = self.Services
	local from = root.Position + root.CFrame.LookVector * 1.5 + Vector3.new(0, 1.6, 0)
	local target = self:TargetsInArc(player, character, root, move.Range, move.Arc)[1]
	local to
	if target then
		to = target.HumanoidRootPart.Position
	else
		-- nothing to hit: it flies straight out until it meets the ground or a wall
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = ignoreFor(self, player, character)
		local hit = Workspace:Raycast(from, root.CFrame.LookVector * move.Range + Vector3.new(0, -4, 0), params)
		to = hit and hit.Position or from + root.CFrame.LookVector * move.Range
	end
	local flight = math.max((to - from).Magnitude / move.Speed, 0.08)
	Net.FireNearby(services.TelegraphService.WorldFX, root.Position, Config.Performance.EffectRadius + move.Range, "SpearThrow", { From = from, To = to, Time = flight })
	if not target then
		return
	end
	task.delay(flight, function()
		if not target.Parent or not character.Parent then
			return
		end
		local dealt = services.CombatService:ApplyDamage({
			Attacker = character,
			Target = target,
			BaseDamage = move.Damage,
			AttackPower = 100,
			Knockback = move.Knockback,
			Heavy = move.Heavy,
			Stagger = move.Stagger,
			Status = move.Status,
			Source = "Handler:SpearThrow",
		})
		if dealt > 0 then
			services.TutorialService:Notify(player, "HandlerHit")
		end
	end)
end

------------------------------------------------------------------------------------------
-- Weapons in hand
------------------------------------------------------------------------------------------
function MeleeService:Equip(player: Player, weaponId)
	if type(weaponId) ~= "string" then
		return
	end
	if weaponId ~= "Fists" then
		if not WEAPONS[weaponId] or not table.find(self:LoadoutOf(player), weaponId) then
			return -- only what you brought
		end
		if not Melee.WeaponUnlocked(weaponId, self:LevelOf(player)) or self:UsesLeft(player, weaponId) <= 0 then
			return
		end
	end
	local state = stateOf(player)
	if state.Weapon == weaponId then
		return
	end
	state.Weapon = weaponId
	state.Seq = "" -- a new weapon starts a new combo
	self:ApplyWeapon(player)
end

function MeleeService:ApplyWeapon(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local old = character:FindFirstChild("HeldWeapon")
	if old then
		old:Destroy()
	end
	local weaponId = stateOf(player).Weapon
	character:SetAttribute("Weapon", weaponId)
	if weaponId == "Fists" then
		return
	end
	local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	if not hand then
		return
	end
	local model = WeaponModels.Build(weaponId, hand :: BasePart)
	if model then
		model.Parent = character
	end
end

-- Choose the weapons you carry (max LoadoutSlots, unlocked ones only). Saved.
function MeleeService:SetLoadout(player: Player, list)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return
	end
	local level = self:LevelOf(player)
	local clean = {}
	for _, id in Melee.CleanLoadout(list) do
		if Melee.WeaponUnlocked(id, level) then
			table.insert(clean, id)
		end
	end
	profile.Loadout = clean
	-- holding something you just left behind: fists up
	local state = stateOf(player)
	if state.Weapon ~= "Fists" and not table.find(clean, state.Weapon) then
		state.Weapon = "Fists"
		self:ApplyWeapon(player)
	end
	self.UIState:FireClient(player, "Profile", self.Services.PlayerDataService:Snapshot(player))
end

-- Real closed fists, in the avatar's own skin colour: a human hand balled up, sculpted
-- from rounded pieces and sized to the FOREARM (Roblox hands are flat slabs or open
-- meshes). The back of the hand, four knuckles, the fingers curled into the palm (the
-- flat of the fist across the end, the middle joints folded back up the palm side, the
-- pinky smaller) and the thumb wrapped across the index and middle fingers. The avatar's
-- hand is hidden; weapons are still gripped in it.
local function buildFist(character: Model, hand: BasePart, isRight: boolean): Model
	local lowerArm = character:FindFirstChild(isRight and "RightLowerArm" or "LeftLowerArm")
	local armSize = lowerArm and lowerArm:IsA("BasePart") and lowerArm.Size or hand.Size
	-- a fist is about as wide as the wrist and a bit shorter than that, wrist to knuckles
	local w = math.clamp(armSize.X, 0.45, 1.3)
	local d = math.clamp(armSize.Z, 0.45, 1.3)
	local length = math.max(w, d) * 0.85
	local skin = hand.Color
	-- (R15 hand frame: -Y = down the arm, toward the knuckles; -Z = the front (thumb side);
	-- the palm faces the body)
	local wrist = hand.CFrame * CFrame.new(0, hand.Size.Y / 2, 0) -- top of the hand
	local model = Instance.new("Model")
	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material, shape)
		local p = Instance.new("Part")
		if shape then
			p.Shape = shape
		end
		p.Name = name
		p.Size = size
		p.CFrame = wrist * offset
		p.Color = color
		p.Material = material
		p.Massless = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hand
		weld.Part1 = p
		weld.Parent = p
		return p
	end
	local Ball, Cyl, M = Enum.PartType.Ball, Enum.PartType.Cylinder, Enum.Material.SmoothPlastic
	local ALONG_Y = CFrame.Angles(0, 0, math.rad(90)) -- cylinders lie along X; turn onto Y
	local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)
	local inner = isRight and -1 or 1 -- the palm side (the palm faces the body)

	local function ball(name: string, diameter: number, at: Vector3)
		return piece(name, Vector3.new(diameter, diameter, diameter), CFrame.new(at), skin, M, Ball)
	end

	-- the palm / back of the hand: a stadium in cross-section, rounded at the index and
	-- pinky edges (thinner palm to back than across the knuckles)
	local t = w * 0.64 -- palm-to-back thickness
	local span = d * 0.84 -- across the four knuckles
	local palmLength = length * 0.5
	piece("Palm", Vector3.new(t, palmLength, span - t), CFrame.new(0, -palmLength / 2, 0), skin, M)
	for _, side in { -1, 1 } do
		piece("PalmEdge", Vector3.new(palmLength, t, t), CFrame.new(0, -palmLength / 2, side * (span / 2 - t / 2)) * ALONG_Y, skin, M, Cyl)
	end

	local finger = span / 4 * 1.04 -- (a touch of overlap so no light shows between them)
	local reach = { 0.02, 0.06, 0.04, -0.03 } -- index .. pinky: the middle finger sits lowest
	for i = 1, 4 do
		-- index at the front (thumb side, -Z) back to the pinky, which is smaller
		local z = -span / 2 + span / 4 * (i - 0.5)
		local size = i == 4 and finger * 0.86 or finger
		local y = -palmLength - size * 0.15 - reach[i] * length
		-- the curled finger: a capsule running palm to back across the end of the fist
		piece("Finger", Vector3.new(t - size, size, size), CFrame.new(0, y, z), skin, M, Cyl)
		ball("Knuckle", size * 1.02, Vector3.new(-inner * (t / 2 - size * 0.5), y + size * 0.14, z))
		ball("FingerBend", size * 0.98, Vector3.new(inner * (t / 2 - size * 0.5), y, z))
		-- the middle joint folded back up the palm side, the fingertip tucked into the palm
		local mid = length * 0.28
		piece("FingerMid", Vector3.new(mid, size * 0.92, size * 0.92), CFrame.new(inner * (t / 2 - size * 0.3), y + mid / 2, z) * ALONG_Y, skin, M, Cyl)
		ball("FingerTip", size * 0.9, Vector3.new(inner * (t / 2 - size * 0.3), y + mid, z))
	end

	-- the thumb: its fleshy base down the front-inner edge, then folded across the index
	-- and middle fingers on the palm side
	local thumb = finger * 1.02
	local front = -span / 2
	local baseX, baseZ = inner * t * 0.2, front + thumb * 0.3
	local turnY = -palmLength + length * 0.06
	piece("ThumbBase", Vector3.new(-turnY - 0.05, thumb * 1.1, thumb * 1.1), CFrame.new(baseX, (turnY - 0.05) / 2, baseZ) * ALONG_Y, skin, M, Cyl)
	ball("ThumbJoint", thumb * 1.08, Vector3.new(baseX, turnY, baseZ))
	local from, to = Vector3.new(baseX, turnY, baseZ), Vector3.new(inner * (t / 2 + thumb * 0.12), turnY, front + span * 0.45)
	piece("Thumb", Vector3.new((to - from).Magnitude, thumb, thumb), CFrame.lookAt((from + to) / 2, to) * ALONG_Z, skin, M, Cyl)
	ball("ThumbTip", thumb * 0.96, to)
	return model
end

function MeleeService:ApplyFists(character: Model)
	for _, name in { "RightHand", "LeftHand" } do
		local hand = character:FindFirstChild(name)
		if hand and hand:IsA("BasePart") and not character:FindFirstChild("Fist" .. name) then
			local fist = buildFist(character, hand, name == "RightHand")
			fist.Name = "Fist" .. name
			fist.Parent = character
			hand.Transparency = 1 -- the glove is the hand now
			hand:SetAttribute("Gloved", true)
		end
	end
end

function MeleeService:GetWeapon(player: Player): string
	return stateOf(player).Weapon
end

-- Magnet held: you walk, you don't run (HandlerService asks).
function MeleeService:WalkSpeedCap(player: Player): number?
	local weapon = WEAPONS[stateOf(player).Weapon]
	return weapon and weapon.WalkSpeed or nil
end

function MeleeService:Start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			local state = stateOf(player)
			state.Seq, state.Move = "", nil
			-- give the avatar a moment to finish loading its hands
			local hand = character:WaitForChild("RightHand", 5) or character:FindFirstChild("Right Arm")
			if hand and character.Parent then
				character:WaitForChild("LeftHand", 2)
				task.wait(0.3) -- (the avatar's body colours / parts finish applying)
				self:ApplyFists(character)
				self:ApplyWeapon(player)
				local profile = self.Services.PlayerDataService:Get(player)
				character:SetAttribute("RunStyle", profile and profile.RunStyle or "Charge")
				for id in WEAPONS do
					publishCharges(player, id)
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return MeleeService
