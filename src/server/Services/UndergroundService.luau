--[[
	UndergroundService  (ModuleScript)
	Location: ServerScriptService/Server/Services/UndergroundService

	NIGHTMARE UNDERGROUND: a 1v1 where each player IS their Nightmare (Config.Underground).

	DuelService runs the match (rounds, forfeits, leaving, rewards) with Mode "Underground";
	this service does what is different about it:
	  * its own arenas: a boxing ring in a hall, the two Handlers in their corner booths
	  * the Handler sits the fight out: parked in its booth, untouchable (CombatService only
	    lets the two Nightmares hurt each other), and the player's controls drive the
	    Nightmare for the whole round (PossessionService:Bind: no meter, no timer)
	  * the fighters are frozen in their corners until FIGHT, and again when the round ends
	  * every fighter gets the same health (a build changes how it fights, not how long)
	  * a round ends on a KNOCKOUT (the Nightmare goes down for good) or, at the bell, on a
	    DECISION: damage landed + KnockdownPoints per knockdown; too close to call = drawn
	  * the in-server queue: the UndergroundQueue prompt (the kiosk at the Colosseum) pairs
	    the first two players who use it

	Remote DuelEvent (server -> client) "UGQueue" { Searching, Waiting }.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))

local Kit = require(script.Parent:WaitForChild("World"):WaitForChild("Kit"))

local UndergroundService = {}

local UG = Config.Underground
local V3, CF, ANG, RGB = Vector3.new, CFrame.new, CFrame.Angles, Color3.fromRGB
local rad = math.rad
local M = Enum.Material
local P, cyl = Kit.P, Kit.Cyl
local glow = { NoCollide = true, Shadow = false }

local CORNER_COLORS = { RGB(255, 60, 70), RGB(70, 140, 255) } -- side 1 red, side 2 blue

local arenas = {} -- [slot] = arena
local slotInUse = {}
local queue: { Player } = {}

------------------------------------------------------------------------------------------
-- The arena: a raised ring in a dark concrete hall, crowds on the bleachers, the
-- Handlers' booths at the red and blue corners
------------------------------------------------------------------------------------------
local function buildArena(slot: number)
	local c = UG.ArenaOrigin + V3((slot - 1) * UG.ArenaSpacing, 0, 0)
	local root = Workspace:FindFirstChild("UndergroundArenas") or Kit.Folder("UndergroundArenas", Workspace)
	local a = Kit.Model("Underground" .. slot, root)
	local half = UG.RingHalf
	local apron = 3 -- the ring floor's height above the hall floor
	local floorY = c.Y + apron -- where the fighters stand

	local CONCRETE, DARK, STEEL = RGB(44, 42, 48), RGB(22, 20, 26), RGB(70, 68, 76)
	local ROPE = RGB(150, 24, 34)

	-- the hall: floor, four walls and a roof (closed: the fight is the only light)
	local hall = 72
	P(a, CF(c + V3(0, -0.5, 0)), V3(hall * 2, 1, hall * 2), CONCRETE, M.Concrete, { Name = "HallFloor" })
	for _, side in { { V3(hall, 20, 0), V3(2, 42, hall * 2) }, { V3(-hall, 20, 0), V3(2, 42, hall * 2) }, { V3(0, 20, hall), V3(hall * 2, 42, 2) }, { V3(0, 20, -hall), V3(hall * 2, 42, 2) } } do
		P(a, CF(c + side[1]), side[2], DARK, M.Concrete, { Name = "HallWall" })
	end
	P(a, CF(c + V3(0, 41, 0)), V3(hall * 2, 2, hall * 2), DARK, M.Concrete, { Name = "HallRoof" })

	-- the ring: a raised apron, the canvas, a red circle in the middle
	P(a, CF(c + V3(0, apron / 2, 0)), V3(half * 2 + 8, apron, half * 2 + 8), RGB(30, 28, 34), M.Metal, { Name = "Apron" })
	P(a, CF(c + V3(0, apron + 0.1, 0)), V3(half * 2 + 6, 0.2, half * 2 + 6), RGB(64, 62, 70), M.Fabric, { Name = "Canvas" })
	Kit.Ring(a, CF(c + V3(0, apron + 0.22, 0)), 8, 0.05, 0.6, 40, ROPE, M.Neon, glow)
	Kit.Ring(a, CF(c + V3(0, apron + 0.22, 0)), half - 1.5, 0.05, 0.3, 64, RGB(90, 30, 36), M.SmoothPlastic, glow)

	-- corner posts (red, blue and two neutral), three ropes between them
	local corners = { V3(-half, 0, half), V3(half, 0, -half), V3(half, 0, half), V3(-half, 0, -half) }
	local postColors = { CORNER_COLORS[1], CORNER_COLORS[2], RGB(210, 210, 220), RGB(210, 210, 220) }
	for i, corner in corners do
		local base = c + corner + V3(0, apron, 0)
		cyl(a, base, base + V3(0, 7, 0), 1.2, postColors[i], M.Metal)
		cyl(a, base + V3(0, 6.6, 0), base + V3(0, 7.4, 0), 1.6, postColors[i], M.Neon, glow)
	end
	local ring = { corners[1], corners[3], corners[2], corners[4] } -- (round the square)
	for i = 1, 4 do
		local from, to = ring[i], ring[i % 4 + 1]
		for _, height in { 2.2, 4, 5.8 } do
			cyl(a, c + from + V3(0, apron + height, 0), c + to + V3(0, apron + height, 0), 0.35, ROPE, M.SmoothPlastic, glow)
		end
		-- the ropes hold: an invisible wall the fighters can't get through or over
		local mid = c + (from + to) / 2 + V3(0, apron + 8, 0)
		local along = (to - from)
		local size = math.abs(along.X) > 0.1 and V3(math.abs(along.X) + 2, 16, 1) or V3(1, 16, math.abs(along.Z) + 2)
		P(a, CF(mid), size, Color3.new(), M.SmoothPlastic, { Transparency = 1, Shadow = false, Name = "RingWall" })
	end

	-- the lighting rig over the ring: a square truss, four spotlights straight down
	local rigY = floorY + 26
	for i = 1, 4 do
		local from, to = ring[i], ring[i % 4 + 1]
		Kit.Rod(a, c + from + V3(0, rigY - c.Y, 0), c + to + V3(0, rigY - c.Y, 0), 1, 1, STEEL, M.DiamondPlate)
	end
	for _, corner in corners do
		local lamp = P(a, CF(c + corner * 0.55 + V3(0, rigY - c.Y - 1, 0)), V3(3, 1.4, 3), RGB(240, 230, 210), M.Neon, glow)
		Kit.Light(lamp, RGB(255, 240, 220), 4, 46, { Kind = "SpotLight", Face = Enum.NormalId.Bottom, Angle = 70 })
	end
	local fill = P(a, CF(c + V3(0, rigY - c.Y + 2, 0)), V3(1, 1, 1), Color3.new(), M.SmoothPlastic, { Transparency = 1, NoCollide = true, Shadow = false })
	Kit.Light(fill, RGB(255, 120, 130), 1.2, 70)

	-- the crowd: stepped bleachers on all four sides, a packed house of silhouettes
	local rng = Random.new(slot * 977)
	for side = 0, 3 do
		local frame = CF(c) * ANG(0, rad(side * 90), 0)
		for row = 0, 3 do
			local z = half + 14 + row * 5
			local y = 1 + row * 2.4
			P(a, frame * CF(0, y / 2, z), V3(half * 2 + 30, y, 5), RGB(34, 32, 38), M.Concrete, { Name = "Bleacher" })
			for x = -half - 12, half + 12, 4.2 do
				if rng:NextNumber() < 0.82 then
					local tone = RGB(rng:NextInteger(30, 80), rng:NextInteger(26, 60), rng:NextInteger(30, 70))
					local spot = frame * CF(x + rng:NextNumber(-0.8, 0.8), y + 1.6, z)
					P(a, spot, V3(1.8, 2.6, 1.2), tone, M.SmoothPlastic, { Name = "Fan", Shadow = false, NoCollide = true })
					Kit.Ball(a, (spot * CF(0, 1.9, 0)).Position, 1.3, RGB(rng:NextInteger(60, 120), rng:NextInteger(45, 90), rng:NextInteger(40, 80)), M.SmoothPlastic, { Shadow = false, NoCollide = true })
				end
			end
		end
	end

	-- the Handlers' corner booths, outside the red and blue corners
	local booths = {}
	for side = 1, 2 do
		local corner = corners[side]
		local out = V3(math.sign(corner.X), 0, math.sign(corner.Z))
		local spot = c + corner + out * 7 + V3(0, 0, 0)
		P(a, CF(spot + V3(0, apron / 2, 0)), V3(7, apron, 7), RGB(30, 28, 34), M.Metal, { Name = "Booth" })
		P(a, CF(spot + V3(0, apron + 0.1, 0)), V3(6.4, 0.2, 6.4), CORNER_COLORS[side], M.Neon, glow)
		for _, edge in { V3(3.3, 0, 0), V3(-3.3, 0, 0), V3(0, 0, 3.3), V3(0, 0, -3.3) } do
			local size = edge.X ~= 0 and V3(0.3, 3, 7) or V3(7, 3, 0.3)
			P(a, CF(spot + edge + V3(0, apron + 1.5, 0)), size, STEEL, M.Metal, { Name = "BoothRail" })
		end
		local stand = spot + V3(0, apron + 3.2, 0)
		booths[side] = CFrame.lookAt(stand, V3(c.X, stand.Y, c.Z))
	end

	-- the name over the hall's far wall
	Kit.Sign(a, CF(c + V3(0, 30, -hall + 1.2)), V3(70, 9, 0.6), "NIGHTMARE UNDERGROUND", RGB(255, 70, 80), { Color = RGB(14, 12, 18) })
	Kit.Sign(a, CF(c + V3(0, 30, hall - 1.2)) * ANG(0, rad(180), 0), V3(70, 9, 0.6), "NIGHTMARE UNDERGROUND", RGB(255, 70, 80), { Color = RGB(14, 12, 18) })

	-- the fighters' corners (facing the middle)
	local starts = {}
	for side = 1, 2 do
		local corner = corners[side]
		local spot = c + V3(math.sign(corner.X) * UG.CornerInset, apron, math.sign(corner.Z) * UG.CornerInset)
		starts[side] = CFrame.lookAt(spot, V3(c.X, spot.Y, c.Z))
	end

	return { Model = a, Center = V3(c.X, floorY, c.Z), Starts = starts, Booths = booths }
end

function UndergroundService:ReserveArena()
	for slot = 1, UG.MaxArenas do
		if not slotInUse[slot] then
			slotInUse[slot] = true
			arenas[slot] = arenas[slot] or buildArena(slot)
			return slot, arenas[slot]
		end
	end
	return nil, nil
end

function UndergroundService:ReleaseArena(slot: number)
	slotInUse[slot] = nil
end

------------------------------------------------------------------------------------------
-- Fighters
------------------------------------------------------------------------------------------
local function fighterOf(self, player: Player): Model?
	return self.Services.NightmareSpawnService:GetNightmare(player)
end

local function handlerRoot(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root:IsA("BasePart") and root or nil
end

-- The Handler to its booth (anchored there: it watches), the Nightmare to its corner.
function UndergroundService:Place(match, player: Player)
	local side = match.Side[player]
	local arena = match.Arena
	local root = handlerRoot(player)
	if root then
		root.Anchored = false
		player.Character:PivotTo(arena.Booths[side])
		root.Anchored = true
	end
	self.Services.NightmareSpawnService:TeleportNightmare(player, arena.Starts[side])
end

function UndergroundService:Unpark(player: Player)
	local root = handlerRoot(player)
	if root then
		root.Anchored = false
	end
end

-- A fresh body for the round: the match's health, marked as a fighter (knockdowns count).
function UndergroundService:PrepareFighter(match, player: Player)
	local model = fighterOf(self, player)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.MaxHealth = UG.FighterHealth
	humanoid.Health = UG.FighterHealth
	model:SetAttribute("UGFighter", true)
	-- (the two fighters collide with each other: Nightmares normally walk through one another)
	self.Services.WorldBuilder.SetCollisionGroup(model, self.Services.WorldBuilder.CollisionGroups.UGFighters)
	self.Services.UndergroundFightService:Register(model, player) -- (fresh stamina, no guard)
	-- (once per body: a body kept from the round before mustn't count a knockdown twice; the
	-- match is looked up when it happens, not kept from the first one)
	if model:GetAttribute("UGWatched") then
		return
	end
	model:SetAttribute("UGWatched", true)
	model:GetAttributeChangedSignal("Ragdolled"):Connect(function()
		local now = self.Services.DuelService:GetMatch(player)
		local ug = now and now.Mode == "Underground" and now.UG
		local side = now and now.Side[player]
		if ug and side and model:GetAttribute("Ragdolled") and now.State == "Live" and humanoid.Health > 0 and not model:GetAttribute("UGKO") then
			match = now
			-- (a knockdown scores for the other side)
			ug.Knockdowns[3 - side] += 1
			self.Services.DuelService:Broadcast(match, "Banner", { Title = "KNOCKDOWN!", Subtitle = string.upper(player.DisplayName) .. " IS DOWN" })
		end
	end)
end

local function setFrozen(self, match, frozen: boolean)
	for _, player in match.Players do
		local model = fighterOf(self, player)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health > 0 then
			humanoid.WalkSpeed = frozen and 0 or (model:GetAttribute("MoveSpeed") or 16)
			humanoid.JumpPower = 0
		end
	end
end

-- Countdown: everyone in control of their Nightmare, frozen in their corner.
function UndergroundService:BeginCountdown(match)
	match.UG = { Points = { [1] = 0, [2] = 0 }, Knockdowns = { [1] = 0, [2] = 0 }, Landed = { [1] = 0, [2] = 0 } }
	setFrozen(self, match, true)
	-- (the new bodies were just put in their corners: let that reach the clients before they
	-- take over the physics, or a client still holding the old spot drags it back)
	local token = match.Token
	task.delay(0.6, function()
		if match.Token ~= token or match.State ~= "Countdown" then
			return
		end
		for _, player in match.Players do
			if player.Parent and not match.Left[player] then
				self.Services.PossessionService:Bind(player)
			end
		end
		setFrozen(self, match, true)
	end)
end

function UndergroundService:BeginLive(match)
	setFrozen(self, match, false)
end

function UndergroundService:Freeze(match)
	setFrozen(self, match, true)
end

-- The bell: the winning side on points (damage + knockdowns), nil when it's too close.
function UndergroundService:Decide(match): number?
	local ug = match.UG
	if not ug then
		return nil
	end
	local score = {}
	for side = 1, 2 do
		score[side] = ug.Points[side] + ug.Knockdowns[side] * UG.KnockdownPoints
	end
	match.UG.Scorecard = score
	if math.abs(score[1] - score[2]) <= UG.DrawMargin then
		return nil
	end
	return score[1] > score[2] and 1 or 2
end

------------------------------------------------------------------------------------------
-- The in-server queue (the kiosk at the Colosseum)
------------------------------------------------------------------------------------------
local function tell(self, player: Player, text: string)
	self.Services.DuelService.DuelEvent:FireClient(player, "RequestResult", { Text = text })
end

local function publishQueue(self)
	for _, player in queue do
		self.Services.DuelService.DuelEvent:FireClient(player, "UGQueue", { Searching = true, Waiting = #queue })
	end
end

function UndergroundService:Leave(player: Player, message: string?)
	local index = table.find(queue, player)
	if index then
		table.remove(queue, index)
		if player.Parent then
			self.Services.DuelService.DuelEvent:FireClient(player, "UGQueue", { Searching = false })
			if message then
				tell(self, player, message)
			end
		end
	end
end

function UndergroundService:Join(player: Player)
	local duel = self.Services.DuelService
	if table.find(queue, player) then
		self:Leave(player, "You left the Underground queue.")
		return { Ok = true }
	end
	local busy, why = duel:IsBusy(player)
	if busy then
		tell(self, player, "You can't queue: you're " .. (why or "busy") .. ".")
		return { Ok = false }
	end
	if not duel:HasLegalBuild(player) then
		tell(self, player, "None of your saved Nightmares fit the PvP Power budget (100).")
		return { Ok = false }
	end
	table.insert(queue, player)
	tell(self, player, "NIGHTMARE UNDERGROUND: searching for an opponent... (use the terminal again to cancel)")
	publishQueue(self)
	self:TryPair()
	return { Ok = true }
end

function UndergroundService:TryPair()
	-- drop anyone who can't fight any more
	for i = #queue, 1, -1 do
		local player = queue[i]
		if not player.Parent or self.Services.DuelService:IsBusy(player) then
			table.remove(queue, i)
		end
	end
	while #queue >= 2 do
		local a = table.remove(queue, 1)
		local b = table.remove(queue, 1)
		for _, player in { a, b } do
			self.Services.DuelService.DuelEvent:FireClient(player, "UGQueue", { Searching = false })
		end
		local result = self.Services.DuelService:StartMatch(a, b, UG.BestOf, { Mode = "Underground" })
		if not result.Ok then
			for _, player in { a, b } do
				tell(self, player, result.Error or "Couldn't start the fight.")
			end
		end
	end
	publishQueue(self)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function UndergroundService:Init(services)
	self.Services = services
end

function UndergroundService:Start()
	local duel = self.Services.DuelService

	-- the decision: what each side landed on the other's Nightmare during a live round
	self.Services.CombatService:OnDamaged(function(target, attacker, amount)
		if not attacker or amount <= 0 or not target:GetAttribute("UGFighter") then
			return
		end
		local owner = self.Services.CombatService:GetOwnerPlayer(attacker)
		local match = owner and duel:GetMatch(owner)
		if match and match.Mode == "Underground" and match.State == "Live" and match.UG and duel:IsOpponentModel(owner, target) then
			local side = match.Side[owner]
			match.UG.Points[side] += amount
			match.UG.Landed[side] += 1
		end
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if prompt.Name == "UndergroundQueue" then
			if not self.Services.AntiExploitService:Allow(player, "DuelRequest") then
				return
			end
			self:Join(player)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:Leave(player, nil)
		publishQueue(self)
	end)
end

-- (used by tests and other services)
function UndergroundService:IsQueued(player: Player): boolean
	return table.find(queue, player) ~= nil
end

function UndergroundService:IsFighter(model: Model?): boolean
	return model ~= nil and CollectionService:HasTag(model, "Nightmare") and model:GetAttribute("UGFighter") == true
end

return UndergroundService
