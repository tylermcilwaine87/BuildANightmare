--[[
	ChainSimulator  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/ChainSimulator

	The Chain Whip's chain, simulated like a real chain on every client (visual only: the
	server's hit boxes decide the hits). A rope of points (Verlet integration):
	  * each frame every point keeps its momentum, falls under gravity, and the links pull
	    it back to exactly one link-length from its neighbours (the chain can't stretch);
	  * the first point is pinned to the whip's cap in the hand, so walking drags the chain
	    behind you, stopping lets it swing and settle, backing up folds it into a heap;
	  * points that reach the floor rest on it (raycast) and scrape to a stop (friction);
	  * the end weight is heavier, so it swings wide and pulls the chain straight;
	  * Lash(): a crack flings the chain out along the swing, the far end fastest, so it
	    unrolls off the floor, snaps straight with a flash at the tip, and drops again.
	Other players' whips crack from the "HPose" stamp the server puts on their character.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Melee = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeleeDefinitions"))

local ChainSimulator = {}

local LINK = 0.46 -- studs between points
local SUBSTEPS = 2
local ITERATIONS = 10 -- link constraint passes per substep (higher = stiffer, no stretch)
local AIR_DAMPING = 0.992
local GROUND_FRICTION = 0.55 -- horizontal speed kept per substep while touching the floor
local GRAVITY_SCALE = 0.75
local SIMULATE_DISTANCE = 220 -- chains further from the camera than this are frozen

local localPlayer = Players.LocalPlayer
local chains = {} -- [Model character] = chain
local folder: Folder

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local paramsAt = 0
local function groundParams(): RaycastParams
	if os.clock() - paramsAt > 1 then
		paramsAt = os.clock()
		local ignore = { folder }
		for _, name in { "Nightmares", "Enemies", "ClientEffects" } do
			local f = Workspace:FindFirstChild(name)
			if f then
				table.insert(ignore, f)
			end
		end
		for _, player in Players:GetPlayers() do
			if player.Character then
				table.insert(ignore, player.Character)
			end
		end
		rayParams.FilterDescendantsInstances = ignore
	end
	return rayParams
end

local function visualPart(name: string, size: Vector3, color: Color3, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Parent = folder
	return p
end

------------------------------------------------------------------------------------------
-- A chain
------------------------------------------------------------------------------------------
local function create(character: Model, held: Model)
	local cap = held:FindFirstChild("Cap")
	local anchor = cap and cap:FindFirstChild("ChainStart")
	if not anchor then
		return
	end
	local links = held:GetAttribute("ChainLinks") or 12
	local count = links + 1 -- points after the anchor; the last is the weight
	local start = anchor.WorldPosition
	local chain = { anchor = anchor, held = held, count = count, p = {}, prev = {}, links = {}, grounded = {} }
	for i = 0, count do
		local pos = start - Vector3.new(0, i * LINK, 0)
		chain.p[i] = pos
		chain.prev[i] = pos
	end
	local metal = Color3.fromRGB(130, 132, 140)
	for i = 1, links do
		chain.links[i] = visualPart("Link", Vector3.new(0.16, 0.34, LINK + 0.08), metal, Enum.Material.Metal)
	end
	chain.weight = visualPart("Weight", Vector3.new(0.7, 0.7, 0.7), Color3.fromRGB(70, 66, 62), Enum.Material.CorrodedMetal, Enum.PartType.Ball)
	chain.spikes = {}
	for _, rot in { CFrame.identity, CFrame.Angles(math.rad(90), 0, 0), CFrame.Angles(0, math.rad(90), 0) } do
		table.insert(chain.spikes, { Part = visualPart("Spike", Vector3.new(0.12, 1.2, 0.12), Color3.fromRGB(160, 160, 170), Enum.Material.Metal), Rot = rot })
	end
	chains[character] = chain
end

local function destroy(character: Model)
	local chain = chains[character]
	if not chain then
		return
	end
	chains[character] = nil
	for _, link in chain.links do
		link:Destroy()
	end
	chain.weight:Destroy()
	for _, spike in chain.spikes do
		spike.Part:Destroy()
	end
end

-- Mass per point: the end weight is ~3x a link, so it carries the swing.
local function inverseMass(chain, i: number): number
	return i == chain.count and 0.35 or 1
end

local function simulate(chain, dt: number)
	local p, prev = chain.p, chain.prev
	local count = chain.count
	local h = dt / SUBSTEPS
	local gravity = Vector3.new(0, -Workspace.Gravity * GRAVITY_SCALE, 0) * h * h
	local params = groundParams()

	-- where the floor is under each point (once per frame)
	local floors = {}
	for i = 1, count do
		local hit = Workspace:Raycast(p[i] + Vector3.new(0, 3, 0), Vector3.new(0, -9, 0), params)
		floors[i] = hit and hit.Position.Y or -math.huge
	end

	for _ = 1, SUBSTEPS do
		p[0] = chain.anchor.WorldPosition
		-- momentum + gravity
		for i = 1, count do
			local velocity = (p[i] - prev[i]) * AIR_DAMPING
			if chain.grounded[i] then
				velocity = Vector3.new(velocity.X * GROUND_FRICTION, velocity.Y, velocity.Z * GROUND_FRICTION)
			end
			prev[i] = p[i]
			p[i] = p[i] + velocity + gravity
		end
		-- links: exactly one link-length apart (the anchor never moves)
		for _ = 1, ITERATIONS do
			for i = 1, count do
				local a, b = p[i - 1], p[i]
				local delta = b - a
				local length = delta.Magnitude
				if length > 1e-4 then
					local wa = i == 1 and 0 or inverseMass(chain, i - 1)
					local wb = inverseMass(chain, i)
					local correction = delta * ((length - LINK) / length / (wa + wb))
					p[i - 1] = a + correction * wa
					p[i] = b - correction * wb
				end
			end
			p[0] = chain.anchor.WorldPosition
		end
		-- a real chain can't stretch at all: one last pass from the hand outward pulls any
		-- link that's still too long back to exactly its length (fast cracks stay honest)
		for i = 1, count do
			local delta = p[i] - p[i - 1]
			local length = delta.Magnitude
			if length > LINK then
				p[i] = p[i - 1] + delta * (LINK / length)
			end
		end
		-- the floor
		for i = 1, count do
			local radius = i == count and 0.35 or 0.1
			local floorY = floors[i] + radius
			if p[i].Y < floorY then
				p[i] = Vector3.new(p[i].X, floorY, p[i].Z)
				if prev[i].Y < floorY then
					prev[i] = Vector3.new(prev[i].X, floorY, prev[i].Z)
				end
				chain.grounded[i] = true
			else
				chain.grounded[i] = p[i].Y < floorY + 0.05
			end
		end
	end
end

local function render(chain)
	local p = chain.p
	for i, link in chain.links do
		local a, b = p[i - 1], p[i]
		if (b - a).Magnitude > 1e-3 then
			local roll = (i % 2 == 0) and CFrame.Angles(0, 0, math.rad(90)) or CFrame.identity
			link.CFrame = CFrame.lookAt((a + b) / 2, b) * roll
		end
	end
	local last, beforeLast = p[chain.count], p[chain.count - 1]
	local weightCF = (last - beforeLast).Magnitude > 1e-3 and CFrame.lookAt(last, last + (last - beforeLast)) or CFrame.new(last)
	chain.weight.CFrame = weightCF
	for _, spike in chain.spikes do
		spike.Part.CFrame = weightCF * spike.Rot
	end
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------
-- A crack: fling the chain out along `direction` (or round to the side for a sweep).
function ChainSimulator:Lash(character: Model?, direction: Vector3, sweep: boolean?)
	local chain = character and chains[character]
	if not chain then
		return
	end
	local side = Vector3.new(-direction.Z, 0, direction.X)
	local step = 1 / (60 * SUBSTEPS) -- velocity lives in the per-substep displacement
	for i = 1, chain.count do
		local f = i / chain.count -- 0 near the hand .. 1 at the weight
		local velocity = if sweep then direction * 20 - side * (45 + 75 * f) else direction * (45 + 95 * f)
		velocity += Vector3.new(0, 22 - 18 * f, 0)
		chain.prev[i] = chain.p[i] - velocity * step
		chain.grounded[i] = false
	end
	-- the crack: a flash where the tip snaps straight
	task.delay(0.13, function()
		if chains[character] ~= chain then
			return
		end
		local flash = visualPart("Crack", Vector3.one * 0.6, Color3.fromRGB(255, 245, 220), Enum.Material.Neon, Enum.PartType.Ball)
		flash.CFrame = CFrame.new(chain.p[chain.count])
		flash.CastShadow = false
		local start = os.clock()
		local connection
		connection = RunService.RenderStepped:Connect(function()
			local t = (os.clock() - start) / 0.15
			if t >= 1 then
				connection:Disconnect()
				flash:Destroy()
				return
			end
			flash.Size = Vector3.one * (0.6 + 2.2 * t)
			flash.Transparency = t
		end)
	end)
end

local function watchCharacter(character: Model)
	local function check()
		local held = character:FindFirstChild("HeldWeapon")
		local isWhip = held ~= nil and held:GetAttribute("WeaponId") == "ChainWhip"
		local chain = chains[character]
		if isWhip and (not chain or chain.held ~= held) then
			destroy(character)
			create(character, held)
		elseif not isWhip and chain then
			destroy(character)
		end
	end
	character.ChildAdded:Connect(function(child)
		if child.Name == "HeldWeapon" then
			task.defer(check) -- (its parts arrive with it)
		end
	end)
	character.ChildRemoved:Connect(function(child)
		if child.Name == "HeldWeapon" then
			check()
		end
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			destroy(character)
		end
	end)
	-- other players' cracks (yours come straight from MeleeController)
	if character ~= localPlayer.Character then
		character:GetAttributeChangedSignal("HPose"):Connect(function()
			local stamp = character:GetAttribute("HPose")
			local pose = type(stamp) == "string" and stamp:match("^([^#]+)")
			if pose == "WhipCrack" or pose == "WhipSweep" then
				local move = pose == "WhipSweep" and Melee.Moves.WhipSweep or Melee.Moves.WhipCrack
				task.delay(move.HitTime * 0.75, function()
					local root = character:FindFirstChild("HumanoidRootPart")
					if root then
						ChainSimulator:Lash(character, root.CFrame.LookVector, pose == "WhipSweep")
					end
				end)
			end
		end)
	end
	check()
end

function ChainSimulator:Start()
	folder = Instance.new("Folder")
	folder.Name = "Chains"
	folder.Parent = Workspace:FindFirstChild("ClientEffects") or Workspace

	local function onPlayer(player: Player)
		if player.Character then
			watchCharacter(player.Character)
		end
		player.CharacterAdded:Connect(watchCharacter)
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerAdded:Connect(onPlayer)

	RunService.Heartbeat:Connect(function(dt)
		dt = math.min(dt, 1 / 30)
		local camera = Workspace.CurrentCamera
		local cameraPosition = camera and camera.CFrame.Position
		for character, chain in chains do
			if not chain.anchor.Parent then
				destroy(character)
			elseif not cameraPosition or (chain.p[0] - cameraPosition).Magnitude < SIMULATE_DISTANCE then
				simulate(chain, dt)
				render(chain)
			end
		end
	end)
end

return ChainSimulator
