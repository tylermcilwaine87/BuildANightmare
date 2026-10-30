--[[
	UltimateService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UltimateService

	ULTIMATE ENERGY (0-100, attribute "UltimateEnergy" on the Nightmare) builds from
	damage the Nightmare deals and takes and from ability use. G fires the build's
	Ultimate (AbilityDefinitions.Ultimates; chosen by Core or a signature Back part).

	Rules (spec section 11): never spammable (needs a full bar, which resets), always a
	visible telegraphed STARTUP, damage goes through the normal pipeline (defence, guard,
	dodge i-frames all apply), and Config.Ultimate.PvPDamageCapFraction caps it in PvP
	(Phase 4). Works whether or not the Nightmare is possessed.

	Each Ultimate is its own move (MOVES below, in step with its clip in NightmarePoses and
	its effects in UltimateEffects). The bodies they catch really move: the server carries
	what it can hold (AbilityService:Hold), a player's own character is pushed by their
	client (PlayerFX "Impulse"), a boss stands its ground and just takes the damage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))

local UltimateService = {}

local U = Config.Ultimate

function UltimateService:Init(services)
	self.Services = services
	self.PlayerFX = Net.Get("PlayerFX")
end

function UltimateService:AddEnergy(brain, amount: number)
	if not brain or amount <= 0 or brain.ultimateFiring then
		return
	end
	brain.ultimateEnergy = math.min(U.EnergyMax, (brain.ultimateEnergy or 0) + amount)
	brain.model:SetAttribute("UltimateEnergy", math.floor(brain.ultimateEnergy))
end

-- The Ultimate CANCELS a basic combo / heavy / ability in progress (it's the big
-- moment, so it should feel instant). If the Nightmare is staggered or already mid-
-- Ultimate, the press is buffered for up to 2 seconds instead of being ignored.
function UltimateService:Request(player: Player)
	local ai = self.Services.NightmareAIService
	local brain = ai:GetBrain(player)
	if not brain or brain.humanoid.Health <= 0 or brain.ultimateQueued or self.Services.DuelService:IsFrozen(player) then
		return
	end
	local def = AbilityDefinitions.GetUltimate(brain.model:GetAttribute("UltimateId"))
	if not def or (brain.ultimateEnergy or 0) < U.EnergyMax then
		return
	end

	local status = self.Services.StatusService
	local function blocked()
		return brain.ultimateFiring or status:IsStaggered(brain.model)
	end

	if blocked() then
		brain.ultimateQueued = true
		task.spawn(function()
			local deadline = os.clock() + 2
			while blocked() and os.clock() < deadline and brain.model.Parent do
				task.wait(0.1)
			end
			brain.ultimateQueued = false
			if not blocked() and brain.model.Parent and brain.humanoid.Health > 0 and (brain.ultimateEnergy or 0) >= U.EnergyMax then
				self:Fire(brain, def)
			end
		end)
		return
	end
	self:Fire(brain, def)
end

function UltimateService:Fire(brain, def)
	brain.ultimateEnergy = 0
	brain.model:SetAttribute("UltimateEnergy", 0)
	brain.queuedAbility = nil
	self:Execute(brain, def) -- Execute bumps castToken, cancelling any pending combo/heavy hit
	self.Services.ChallengeService:Notify(brain.owner, "UltimateUsed")
end

-- STUDIO ONLY (the AbilityLab): fire the body's Ultimate now, on a full bar.
function UltimateService:DevFire(player: Player)
	local brain = RunService:IsStudio() and self.Services.NightmareAIService:GetBrain(player)
	local def = brain and AbilityDefinitions.GetUltimate(brain.model:GetAttribute("UltimateId"))
	if not def then
		return false
	end
	self:Fire(brain, def)
	return true
end

------------------------------------------------------------------------------------------
-- Who it catches, and what happens to them
------------------------------------------------------------------------------------------
local function ignoreList(brain)
	local ignore = { brain.model }
	if brain.owner.Character then
		table.insert(ignore, brain.owner.Character)
	end
	return ignore
end

local function isAlive(model: Model): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return model.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

-- Everything this body may hurt within `radius` (monsters, and opponents in a live duel).
function UltimateService:EnemiesNear(brain, position: Vector3, radius: number): { Model }
	local combat = self.Services.CombatService
	local list = {}
	for _, model in self.Services.HitDetectionService:QueryRadius(position, radius, ignoreList(brain)) do
		if isAlive(model) and model:FindFirstChild("HumanoidRootPart") and combat:CanDamage(brain.model, model) then
			table.insert(list, model)
		end
	end
	return list
end

-- Damage to each of `targets`. opts: Share (of def.Damage), Knockback, Stagger, Launch, Heavy,
-- NoKnockdown, From (a centre point: each is driven straight away from it).
function UltimateService:Damage(brain, def, targets, opts)
	opts = opts or {}
	local combat = self.Services.CombatService
	local launch = opts.Launch and table.clone(opts.Launch)
	if launch then
		launch.MinScale = 0.85 -- (the last blow throws them, however small the body throwing)
	end
	for _, target in targets do
		combat:ApplyDamage({
			Attacker = brain.model,
			Target = target,
			BaseDamage = def.Damage * (opts.Share or 1),
			AttackPower = brain.stats.AttackPower,
			Knockback = opts.Knockback or 25,
			Stagger = opts.Stagger or def.Stagger,
			Heavy = opts.Heavy,
			Launch = launch,
			-- (a launch always throws a body the server moves; against a player it stays the
			-- usual knockdown chance, so PvP isn't decided by one throw)
			Thrown = (launch ~= nil and not Players:GetPlayerFromCharacter(target)) or nil,
			NoKnockdown = opts.NoKnockdown,
			HitDirection = opts.From and Util.FlatUnit(target:GetPivot().Position - opts.From) or nil,
			Status = def.Element and StatusDefinitions.ByElement[def.Element] or nil,
			CastKey = brain.ultimateCastKey, -- PvP cap: max 45% of a target's HP per Ultimate
			Source = "Ultimate:" .. def.DisplayName,
		})
	end
end

-- Pushes a player's own character (moved by their client) along `velocity`.
function UltimateService:PushPlayer(target: Model, velocity: Vector3, duration: number)
	local player = Players:GetPlayerFromCharacter(target)
	if player then
		self.PlayerFX:FireClient(player, "Impulse", { Velocity = velocity, Duration = duration })
	end
end

-- Keyed height over a move's length: { { seconds, k }, ... } -> an ease for AbilityService:Drive.
local function profile(keys, length: number)
	return function(fraction: number): number
		local t = fraction * length
		for i = 2, #keys do
			local a, b = keys[i - 1], keys[i]
			if t <= b[1] then
				local x = (t - a[1]) / math.max(b[1] - a[1], 0.001)
				if b[3] then
					x = x * x * x -- (a key marked true is dropped into: it slams)
				else
					x = x * x * (3 - 2 * x)
				end
				return a[2] + (b[2] - a[2]) * x
			end
		end
		return keys[#keys][2]
	end
end

------------------------------------------------------------------------------------------
-- The moves. Each runs on its own thread from the moment the clip starts; `cast` carries
-- brain, def, token, alive(), ground(), fx(position, data) and look (flat, at the cast).
------------------------------------------------------------------------------------------
local MOVES = {}

-- SPLINTER STORM: the crate blows apart in a storm of stakes (1.0, 1.6, 2.2). Between bursts
-- it hauls itself back together, and the stakes stuck in whatever they hit come back too,
-- dragging the bodies in for the next one; the last throws them off.
function MOVES.SplinterStorm(self, cast)
	local brain, def = cast.brain, cast.def
	local ability = self.Services.AbilityService
	self.Services.TelegraphService:Circle(cast.ground(), def.Radius, def.Startup, "Friendly")
	task.wait(def.Startup)
	for pulse = 1, def.Pulses do
		if not cast.alive() then
			return
		end
		local center = cast.ground()
		local last = pulse == def.Pulses
		local hits = self:EnemiesNear(brain, center, def.Radius)
		cast.fx(center, { Kind = "SplinterBurst", Position = center, Radius = def.Radius, Size = pulse })
		self:Damage(brain, def, hits, {
			From = center,
			Knockback = last and 30 or 6,
			NoKnockdown = (not last) or nil,
			Heavy = last or nil,
			Launch = last and { Lift = 24, Push = 34, Spin = 7 } or nil,
		})
		if last then
			return
		end
		task.wait(def.Interval * 0.45)
		if not cast.alive() then
			return
		end
		local pull = def.Interval * 0.45
		for _, target in hits do
			local targetRoot = target:FindFirstChild("HumanoidRootPart")
			local offset = targetRoot and Util.Flat(center - targetRoot.Position)
			if offset and offset.Magnitude > 4 then
				local travel = math.min(offset.Magnitude - 4, 7)
				local step = offset.Unit * travel
				if ability:CanHold(brain, target) then
					local from = targetRoot.CFrame
					ability:Hold(brain, cast.token, target, pull, function(t)
						local k = t / pull
						return from + step * (k * k)
					end, function() end, false)
				else
					self:PushPlayer(target, offset.Unit * (travel / pull), pull)
				end
			end
		end
		task.wait(def.Interval * 0.55)
	end
end

-- THOUSAND-EYE GLARE: the body turns on its target, every eye opens, and the beam burns down
-- the line (1.2 - 2.35), following them slowly: it can be outrun. The model's "GlareDir"
-- attribute points the beam for every client. Each tick shoves them back along it; the last
-- blasts them off their feet.
function MOVES.ThousandEyeGlare(self, cast)
	local brain, def = cast.brain, cast.def
	local root = brain.root
	local hitDetection = self.Services.HitDetectionService
	local combat = self.Services.CombatService
	local model = brain.model
	local possessed = brain.possessedBy ~= nil

	local function nearest(): Model?
		local best, bestDistance
		for _, enemy in self:EnemiesNear(brain, root.Position, def.Reach) do
			local distance = (enemy:GetPivot().Position - root.Position).Magnitude
			if not bestDistance or distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
		return best
	end
	local target = nearest()
	local function flatTo(body: Model?): Vector3?
		local part = body and body:FindFirstChild("HumanoidRootPart")
		return part and Util.FlatUnit(part.Position - root.Position) or nil
	end
	local aim = flatTo(target) or cast.look
	local position = root.Position
	local began = os.clock()
	local startFacing = Util.FlatUnit(root.CFrame.LookVector) or aim
	local beamUntil = began + def.Startup + def.Ticks * def.Interval + 0.05
	local rate = math.rad(32)

	local function beamFrame()
		local start = cast.ground()
		local centre = start + aim * (brain.hitboxSize.Z / 2 + def.Reach / 2)
		return CFrame.lookAt(centre, centre + aim)
	end
	self.Services.TelegraphService:Box(beamFrame(), Vector3.new(def.Width, 1, def.Reach), def.Startup, "Friendly")

	-- (planted while it glares; a possessed body keeps turning under its player's hand)
	if not possessed then
		root.Anchored = true
	end
	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		if not cast.alive() or now > beamUntil then
			connection:Disconnect()
			model:SetAttribute("GlareDir", nil)
			if root.Parent and not possessed then
				root.Anchored = false
				root.AssemblyLinearVelocity = Vector3.zero
			end
			return
		end
		if possessed then
			aim = Util.FlatUnit(root.CFrame.LookVector) or aim
		else
			if not target or not isAlive(target) then
				target = nearest()
			end
			local wanted = flatTo(target)
			if wanted and now - began >= def.Startup then
				local angle = math.acos(math.clamp(aim:Dot(wanted), -1, 1))
				if angle > 0.001 then
					local side = aim:Cross(wanted).Y >= 0 and 1 or -1
					local turn = math.min(rate * dt, angle) * side
					aim = (CFrame.Angles(0, turn, 0) * aim).Unit
				end
			end
			-- (spins round to the aim in the first moments of the windup)
			local k = math.clamp((now - began) / 0.3, 0, 1)
			local facing = startFacing:Lerp(aim, k * k * (3 - 2 * k))
			if facing.Magnitude > 0.01 then
				root.CFrame = CFrame.lookAt(position, position + facing)
			end
		end
		-- (the beam dips from the chest to waist height at its far end)
		local height = root.Position.Y - cast.ground().Y
		model:SetAttribute("GlareDir", (aim * def.Reach + Vector3.new(0, 1.2 - height, 0)).Unit)
	end)

	task.wait(def.Startup)
	for tick = 1, def.Ticks do
		if not cast.alive() then
			return
		end
		local last = tick == def.Ticks
		local frame = beamFrame()
		local hits = {}
		for _, enemy in hitDetection:QueryBox(frame * CFrame.new(0, 4, 0), Vector3.new(def.Width, 10, def.Reach), ignoreList(brain)) do
			if isAlive(enemy) and combat:CanDamage(model, enemy) then
				table.insert(hits, enemy)
			end
		end
		self:Damage(brain, def, hits, {
			From = root.Position,
			Knockback = last and 34 or 16,
			NoKnockdown = (not last) or nil,
			Heavy = last or nil,
			Launch = last and { Lift = 16, Push = 40, Spin = 5 } or nil,
		})
		task.wait(def.Interval)
	end
end

-- BASTION QUAKE: it jumps and comes down with every plate it has (1.1), the wave rolling out
-- across the floor and bouncing everything it reaches; heaves up again and drops harder
-- (1.9), and the second wave throws them. The waves travel, and pass under a body in the air.
local QUAKE_SPEED = 42
function UltimateService:Quake(brain, cast, center: Vector3, last: boolean)
	local def = cast.def
	local ability = self.Services.AbilityService
	local radius = last and def.Radius * 1.15 or def.Radius
	cast.fx(center, { Kind = "QuakeWave", Position = center, Radius = radius, Time = radius / QUAKE_SPEED, Size = last and 2 or 1 })
	local reached = {}
	local began = os.clock()
	while cast.alive() do
		local front = math.min((os.clock() - began) * QUAKE_SPEED, radius)
		for _, enemy in self:EnemiesNear(brain, center, front + 6) do
			local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
			local size = enemy:GetExtentsSize()
			local distance = enemyRoot and Util.FlatDistance(enemyRoot.Position, center)
			if distance and not reached[enemy] and distance <= front + math.max(size.X, size.Z) / 2 then
				reached[enemy] = true
				local airborne = enemyRoot.Position.Y - center.Y > size.Y + 2
				if not airborne then
					self:Damage(brain, def, { enemy }, {
						From = center,
						Knockback = last and 40 or 0,
						NoKnockdown = (not last) or nil,
						Heavy = last or nil,
						Launch = last and { Lift = 34, Push = 22, Spin = 6 } or nil,
					})
					if not last then
						if ability:CanHold(brain, enemy) then
							-- bounced off the floor by the wave
							local from = enemyRoot.CFrame
							ability:Hold(brain, cast.token, enemy, 0.42, function(t)
								local k = t / 0.42
								return from + Vector3.new(0, 4 * k * (1 - k) * 3.5, 0)
							end, function() end, false)
						else
							self:PushPlayer(enemy, Vector3.new(0, 26, 0), 0.2)
						end
					end
				end
			end
		end
		if front >= radius then
			break
		end
		task.wait()
	end
end

function MOVES.BastionQuake(self, cast)
	local brain, def = cast.brain, cast.def
	local root = brain.root
	self.Services.TelegraphService:Circle(cast.ground(), def.Radius, def.Startup, "Friendly")
	-- the jumps are its real body in the air: keyed so it lands on the slam frames
	local from = root.CFrame
	local slamTwo = def.Startup + def.Interval
	self.Services.AbilityService:Drive(brain, cast.token, from, from + Vector3.new(0, 6, 0), slamTwo, profile({
		{ 0, 0 }, { 0.62, 0 }, { 0.94, 1 }, { def.Startup, 0, true },
		{ 1.45, 0 }, { 1.76, 0.8 }, { slamTwo, 0, true },
	}, slamTwo), 0)
	task.wait(def.Startup)
	if not cast.alive() then
		return
	end
	task.spawn(function()
		self:Quake(brain, cast, cast.ground(), false)
	end)
	task.wait(def.Interval)
	if cast.alive() then
		self:Quake(brain, cast, cast.ground(), true)
	end
end

-- CRYSTAL CATACLYSM: both arms drive into the floor and the crystals run out through it to
-- every enemy, one spire after another erupting under them (each one lifts what it catches
-- up onto its point, frozen there); at 2.4 the whole field SHATTERS, dropping and throwing them.
function MOVES.CrystalCataclysm(self, cast)
	local brain, def = cast.brain, cast.def
	local ability = self.Services.AbilityService
	local origin = cast.ground()
	local targets = self:EnemiesNear(brain, origin, def.Area)
	local random = Random.new()
	local points = {}
	for i = 1, def.Count do
		local base
		if #targets > 0 then
			base = targets[(i - 1) % #targets + 1]:GetPivot().Position
			base = Vector3.new(base.X, origin.Y, base.Z)
			-- (the first under each of them, the rest a stride around it)
			if i > #targets then
				base += Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
			end
		else
			base = origin + cast.look * random:NextNumber(6, def.Area * 0.6) + Vector3.new(random:NextNumber(-4, 4), 0, random:NextNumber(-4, 4))
		end
		table.insert(points, base)
		self.Services.TelegraphService:Circle(base, def.Radius, def.Startup + (i - 1) * def.Interval, "Friendly")
	end
	task.wait(def.Startup)

	local impaled, spires = {}, {}
	local travel = 0.16 -- (the crystal's run through the floor, from the body to the point)
	for i, point in points do
		if not cast.alive() then
			return
		end
		local untilShatter = def.ShatterAt - def.Startup - (i - 1) * def.Interval - travel
		cast.fx(point, { Kind = "CrystalSpire", From = origin, Position = point, Size = i <= #targets and 1.5 or 1, Travel = travel, Until = untilShatter })
		table.insert(spires, point)
		task.delay(travel, function()
			if not cast.alive() then
				return
			end
			local hits = self:EnemiesNear(brain, point, def.Radius)
			-- (a body already up on a spire is still in reach of the ones going up round it)
			for enemy, spire in impaled do
				if Util.FlatDistance(spire, point) <= def.Radius and isAlive(enemy) and not table.find(hits, enemy) then
					table.insert(hits, enemy)
				end
			end
			self:Damage(brain, def, hits, { Share = 0.75, Knockback = 0, NoKnockdown = true })
			for _, enemy in hits do
				local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
				if enemyRoot and not impaled[enemy] and ability:CanHold(brain, enemy) then
					impaled[enemy] = point
					local start = enemyRoot.CFrame
					ability:Hold(brain, cast.token, enemy, untilShatter, function(t)
						local up = 1 - (1 - math.min(t / 0.16, 1)) ^ 3
						local shiver = t > 0.16 and math.sin(t * 40) * 0.06 or 0
						return start + Vector3.new(shiver, 5.5 * up, 0)
					end, function() end, false)
				end
			end
		end)
		task.wait(def.Interval)
	end
	-- (a moment past the holds' end: a held body can't be thrown anywhere)
	task.wait(math.max(def.ShatterAt - def.Startup - def.Count * def.Interval, 0) + 0.04)
	if not cast.alive() then
		return
	end
	cast.fx(origin, { Kind = "CrystalShatter", Points = spires })
	local thrown = {}
	for _, point in spires do
		for _, enemy in self:EnemiesNear(brain, point, def.Radius) do
			thrown[enemy] = point
		end
	end
	for enemy, point in impaled do
		thrown[enemy] = point
	end
	for enemy, point in thrown do
		self:Damage(brain, def, { enemy }, { Share = 1.5, From = point + (origin - point).Unit * 2, Knockback = 28, Heavy = true, Launch = { Lift = 22, Push = 22, Spin = 8 } })
	end
end

-- SCRAP APOCALYPSE: the reactor rips the scrap up out of the ground around it, red-hot, then
-- the arms hurl it: a throw with each hand (1.4, 1.75, 2.1, 2.45), the last with both (2.8),
-- two pieces a throw, each one arcing onto where they're standing NOW and going off on impact.
function MOVES.ScrapApocalypse(self, cast)
	local brain, def = cast.brain, cast.def
	local origin = cast.ground()
	local random = Random.new()
	local throws = math.ceil(def.Count / 2)
	self.Services.TelegraphService:Circle(origin, 8, def.Startup, "Friendly")
	task.wait(def.Startup)
	local left = false
	for throw = 1, throws do
		if not cast.alive() then
			return
		end
		local targets = self:EnemiesNear(brain, cast.ground(), def.Area)
		for piece = 1, 2 do
			if (throw - 1) * 2 + piece > def.Count then
				break
			end
			local point
			local victim = #targets > 0 and targets[(throw + piece - 2) % #targets + 1]
			if victim then
				point = victim:GetPivot().Position
				point = Vector3.new(point.X, origin.Y, point.Z) + Vector3.new(random:NextNumber(-2.5, 2.5), 0, random:NextNumber(-2.5, 2.5))
			else
				point = origin + cast.look * random:NextNumber(8, def.Area * 0.7) + Vector3.new(random:NextNumber(-8, 8), 0, random:NextNumber(-8, 8))
			end
			local finale = throw == throws
			self.Services.TelegraphService:Circle(point, def.Radius, def.Flight, "Friendly")
			cast.fx(point, { Kind = "ScrapThrow", Model = brain.model, Arm = (finale and piece == 2 or (not finale and left)) and "LeftArm" or "RightArm", To = point, Time = def.Flight, Big = finale })
			task.delay(def.Flight, function()
				if cast.alive() then
					local hits = self:EnemiesNear(brain, point, def.Radius)
					self:Damage(brain, def, hits, {
						From = point,
						Knockback = finale and 34 or 14,
						NoKnockdown = (not finale) or nil,
						Heavy = finale or nil,
						Launch = finale and { Lift = 26, Push = 26, Spin = 8 } or nil,
					})
				end
			end)
		end
		left = not left
		task.wait(def.Interval)
	end
	task.wait(def.Flight)
end

-- VOID COLLAPSE: the claws tear a well open in front of it (0.3); everything in reach is dragged
-- in round it, faster and faster, up off the ground, and held at its heart. At 1.5 the well
-- COLLAPSES to a point, a held breath of nothing, and at 1.7 it goes off, throwing them
-- straight out. A boss won't be moved, but stands in the blast if it's close.
function MOVES.VoidCollapse(self, cast)
	local brain, def = cast.brain, cast.def
	local ability = self.Services.AbilityService
	local center = cast.ground() + cast.look * def.Offset
	local heart = center + Vector3.new(0, 3.2, 0)
	self.Services.TelegraphService:Circle(center, def.PullRadius, def.Startup, "Pull")
	self.Services.TelegraphService:Circle(center, def.Radius, def.Startup, "Friendly")
	task.wait(def.OpenAt)
	if not cast.alive() then
		return
	end
	cast.fx(center, { Kind = "VoidWell", Model = brain.model, Position = heart, Radius = def.PullRadius, Blast = def.Radius, Collapse = def.Startup - def.OpenAt - 0.2, Detonate = def.Startup - def.OpenAt })

	local caught = {}
	local detonateAt = os.clock() + (def.Startup - def.OpenAt)
	local spin = 1
	while cast.alive() and os.clock() < detonateAt do
		for _, enemy in self:EnemiesNear(brain, center, def.PullRadius) do
			local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
			if enemyRoot and not caught[enemy] and ability:CanHold(brain, enemy) then
				caught[enemy] = true
				local remaining = detonateAt - os.clock()
				local start = enemyRoot.CFrame
				local offset = Util.Flat(start.Position - center)
				local radius = math.max(offset.Magnitude, 1)
				local angle0 = math.atan2(offset.Z, offset.X)
				local turn = spin * 2.2
				spin = -spin
				ability:Hold(brain, cast.token, enemy, remaining, function(t)
					local k = t / remaining
					-- (a slow drag that accelerates: it can't be walked out of once it has you)
					local fall = k * k * k * 0.75 + k * 0.25
					local r = radius * (1 - fall) + 0.6 * fall
					local a = angle0 + turn * fall
					local p = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
					local y = start.Position.Y + (heart.Y - start.Position.Y) * fall
					return CFrame.new(p.X, y, p.Z) * start.Rotation * CFrame.Angles(0, fall * 2, fall * 1.4)
				end, function() end, false)
			elseif enemyRoot and not caught[enemy] then
				local toward = Util.FlatUnit(center - enemyRoot.Position)
				if toward then
					if Players:GetPlayerFromCharacter(enemy) then
						self:PushPlayer(enemy, toward * 28, 0.25)
					elseif not enemyRoot.Anchored and not enemy:GetAttribute("KnockbackImmune") and not enemy:GetAttribute("BossId") and enemyRoot:GetNetworkOwner() == nil then
						enemyRoot.AssemblyLinearVelocity = toward * 24 + Vector3.new(0, enemyRoot.AssemblyLinearVelocity.Y, 0)
					end
				end
			end
		end
		task.wait(0.2)
	end
	-- (the holds end at this same moment: a held body can't be knocked anywhere)
	task.wait(math.max(detonateAt - os.clock(), 0) + 0.03)
	if cast.alive() then
		self:Damage(brain, def, self:EnemiesNear(brain, heart, def.Radius), { From = center, Knockback = 50, Heavy = true, Launch = { Lift = 28, Push = 44, Spin = 9 } })
	end
end

-- SUPERNOVA: it lifts off with the wings wrapped round it, burning brighter, and FLARES three
-- times in the air (1.2, 1.8, 2.4), each wave reaching further across the floor; the last
-- throws everything off and it drops back to the ground in the scorch it made.
function MOVES.Supernova(self, cast)
	local brain, def = cast.brain, cast.def
	local root = brain.root
	local center = cast.ground()
	local from = root.CFrame
	local length = def.Length - 0.25
	local flareTwo, flareThree = def.Startup + def.Interval, def.Startup + def.Interval * 2
	self.Services.TelegraphService:Circle(center, def.Radius, def.Startup, "Friendly")
	self.Services.AbilityService:Drive(brain, cast.token, from, from + Vector3.new(0, def.Rise, 0), length, profile({
		{ 0, 0 }, { 0.15, 0 }, { def.Startup - 0.05, 1 },
		{ def.Startup + 0.12, 0.92 }, { flareTwo - 0.05, 1 },
		{ flareTwo + 0.12, 0.9 }, { flareThree - 0.05, 1.08 },
		{ flareThree + 0.15, 1 }, { 2.72, 0.98 }, { length, 0, true },
	}, length), 0)
	task.wait(def.Startup)
	for pulse = 1, def.Pulses do
		if not cast.alive() then
			return
		end
		local last = pulse == def.Pulses
		local radius = def.Radius * (0.7 + 0.3 * (pulse - 1) / math.max(def.Pulses - 1, 1)) * (last and 1.15 or 1)
		cast.fx(center, { Kind = "SupernovaFlare", Model = brain.model, Position = center, Radius = radius, Size = pulse })
		self:Damage(brain, def, self:EnemiesNear(brain, center, radius), {
			From = center,
			Knockback = last and 38 or 16,
			NoKnockdown = (not last) or nil,
			Heavy = last or nil,
			Launch = last and { Lift = 26, Push = 34, Spin = 7 } or nil,
		})
		task.wait(def.Interval)
	end
end

-- ERUPTION: the heart splits (1.3) and a column of lava goes up out of the chest; the bombs it
-- throws fall on them one after another, each landing where they stand as it's thrown, each
-- leaving a pool of lava burning on the floor. The last lands with the whole weight of it.
function MOVES.Eruption(self, cast)
	local brain, def = cast.brain, cast.def
	local root = brain.root
	local origin = cast.ground()
	local random = Random.new()
	self.Services.TelegraphService:Circle(origin, 7, def.Startup, "Friendly")
	task.wait(def.Startup)
	if not cast.alive() then
		return
	end
	local chest = root.Position + Vector3.new(0, 1, 0)
	for i = 1, def.Count do
		if not cast.alive() then
			return
		end
		local targets = self:EnemiesNear(brain, origin, def.Area)
		local point
		if #targets > 0 then
			point = targets[(i - 1) % #targets + 1]:GetPivot().Position
			point = Vector3.new(point.X, origin.Y, point.Z) + Vector3.new(random:NextNumber(-3, 3), 0, random:NextNumber(-3, 3))
		else
			local angle = random:NextNumber(0, math.pi * 2)
			point = origin + Vector3.new(math.cos(angle), 0, math.sin(angle)) * random:NextNumber(7, def.Area * 0.7)
		end
		local finale = i == def.Count
		self.Services.TelegraphService:Circle(point, def.Radius, def.Flight, "Friendly")
		cast.fx(point, { Kind = "LavaBomb", From = chest, To = point, Time = def.Flight, Big = finale })
		task.delay(def.Flight, function()
			if cast.alive() then
				self:Damage(brain, def, self:EnemiesNear(brain, point, def.Radius), {
					From = point,
					Knockback = finale and 34 or 14,
					NoKnockdown = (not finale) or nil,
					Heavy = finale or nil,
					Launch = finale and { Lift = 28, Push = 24, Spin = 8 } or nil,
				})
			end
		end)
		task.wait(def.Interval)
	end
	task.wait(def.Flight)
end

------------------------------------------------------------------------------------------
-- Execution
------------------------------------------------------------------------------------------
function UltimateService:Execute(brain, def)
	local ai = self.Services.NightmareAIService
	local telegraphs = self.Services.TelegraphService
	local root = brain.root
	local hitbox = brain.hitboxSize
	local now = os.clock()

	brain.ultimateFiring = true
	brain.ultimateCastKey = HttpService:GenerateGUID(false)
	brain.castToken = (brain.castToken or 0) + 1
	local castToken = brain.castToken
	brain.busyUntil = now + def.Length
	if not brain.possessedBy then
		ai:Stop(brain)
	end
	-- each ultimate has its own animation (NightmarePoses "Ultimate_<Id>")
	ai:PlayAction(brain, "Ultimate_" .. def.Id, def.Startup, def.Length)
	Net.FireNearby(telegraphs.WorldFX, root.Position, Config.Performance.EffectRadius, "UltimateBanner", { Name = def.DisplayName, Model = brain.model, Position = root.Position })

	-- (the real floor under it, where it stood when it left the ground, for a move that flies)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { Workspace:FindFirstChild("Nightmares"), Workspace:FindFirstChild("Enemies"), brain.owner.Character }
	params.RespectCanCollide = true
	local floor = Workspace:Raycast(root.Position, Vector3.new(0, -40, 0), params)
	local floorY = floor and floor.Position.Y or root.Position.Y - hitbox.Y / 2 - brain.humanoid.HipHeight
	local cast = {
		brain = brain,
		def = def,
		token = castToken,
		look = Util.FlatUnit(root.CFrame.LookVector) or Vector3.zAxis,
	}
	function cast.alive()
		return brain.castToken == castToken and brain.model.Parent ~= nil and brain.humanoid.Health > 0
	end
	function cast.ground()
		local p = root.Position
		return Vector3.new(p.X, floorY, p.Z)
	end
	function cast.fx(position: Vector3, data)
		Net.FireNearby(telegraphs.WorldFX, position, Config.Performance.EffectRadius, "AbilityFX", data)
	end

	task.spawn(function()
		local move = MOVES[def.Id]
		local ok, err = pcall(move, self, cast)
		if not ok then
			warn("[Ultimate] " .. def.Id .. ": " .. tostring(err))
		end
		-- (the move's threads can finish early; the body stays committed for the whole clip)
		local rest = brain.busyUntil - os.clock()
		if rest > 0 and brain.castToken == castToken then
			task.wait(rest)
		end
		if brain.castToken == castToken then
			brain.ultimateFiring = false
		end
	end)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function UltimateService:Start()
	local ai = self.Services.NightmareAIService
	self.Services.CombatService:OnDamaged(function(target, attacker, amount)
		if amount <= 0 then
			return
		end
		local dealerBrain = attacker and ai:GetBrainByModel(attacker)
		if dealerBrain then
			self:AddEnergy(dealerBrain, amount * U.PerDamageDealt)
		end
		local victimBrain = ai:GetBrainByModel(target)
		if victimBrain then
			self:AddEnergy(victimBrain, amount * U.PerDamageTaken)
		end
	end)
end

return UltimateService
