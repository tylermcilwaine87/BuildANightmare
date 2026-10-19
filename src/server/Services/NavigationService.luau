--[[
	NavigationService  (ModuleScript)
	Location: ServerScriptService/Server/Services/NavigationService

	Cheap-first movement for AI-controlled creatures:
	  1. If the straight line to the goal is clear (one raycast), just Humanoid:MoveTo.
	  2. Otherwise compute a PathfindingService path IN THE BACKGROUND (never blocks the
	     shared AI loop), sized for the creature's hitbox, and follow its waypoints.
	  3. Paths are recomputed at most once per Config.Navigation.RepathInterval, or when
	     the goal has moved more than RepathDistance studs. No constant recomputing.
	4. Stuck detection: a creature that stops making progress (e.g. pressed against a
	   pillar corner) ignores the straight line for a while and pathfinds, or sidesteps
	   when no path exists.

	Usage:
	  local nav = NavigationService:Create(humanoid, root, hitboxSize)
	  nav:MoveTo(goal)   -- call every AI tick; cheap when nothing changed
	  nav:Stop()
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local PathfindingService = game:GetService("PathfindingService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local NavigationService = {}
local NAV = Config.Navigation

local Navigator = {}
Navigator.__index = Navigator

-- Things that move around (creatures, effects) never count as obstacles.
-- Cached and rebuilt at most every Config.Performance.FilterRefresh seconds: this runs
-- for every moving creature, every AI tick.
local cachedParams: RaycastParams? = nil
local cachedAt = 0
local function obstacleParams(): RaycastParams
	if cachedParams and os.clock() - cachedAt < Config.Performance.FilterRefresh then
		return cachedParams
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, name in { "Nightmares", "Enemies", "ClientEffects" } do
		local folder = Workspace:FindFirstChild(name)
		if folder then
			table.insert(ignore, folder)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	cachedParams, cachedAt = params, os.clock()
	return params
end

local function dot(position: Vector3, color: Color3)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 0.8
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Position = position
	p.Parent = Workspace
	Debris:AddItem(p, 1.5)
end

-- DEV: green dots along a found path; one red dot at the goal when no path exists.
local function drawPath(waypoints, goal: Vector3)
	if waypoints then
		for _, waypoint in waypoints do
			dot(waypoint.Position + Vector3.new(0, 1, 0), Color3.fromRGB(80, 255, 120))
		end
	else
		dot(goal, Color3.fromRGB(255, 60, 60))
	end
end

function NavigationService:Create(humanoid: Humanoid, root: BasePart, hitboxSize: Vector3)
	local radius = math.max(hitboxSize.X, hitboxSize.Z) / 2
	return setmetatable({
		humanoid = humanoid,
		root = root,
		radius = radius,
		path = PathfindingService:CreatePath({
			AgentRadius = math.max(radius, 2),
			AgentHeight = hitboxSize.Y + humanoid.HipHeight,
			AgentCanJump = false,
			WaypointSpacing = 6,
		}),
		waypoints = nil,
		index = 0,
		goal = nil,
		lastPath = 0,
		computing = false,
		checkPosition = nil,
		checkTime = 0,
		detourUntil = 0,
		sidestep = nil,
		sidestepSign = 1,
	}, Navigator)
end

-- Sweeps a sphere roughly the creature's width, so it can't clip a corner that a thin
-- centre-line ray would miss.
function Navigator:IsDirectClear(goal: Vector3): boolean
	local from = self.root.Position
	local to = Vector3.new(goal.X, from.Y, goal.Z)
	local offset = to - from
	if offset.Magnitude < 1 then
		return true
	end
	local params = obstacleParams()
	if Workspace:Raycast(from, offset, params) then
		return false
	end
	-- Sweeps ignore anything they START inside, so a pillar the creature is pressed
	-- against would be invisible. Start the sweep from a little behind it instead.
	local radius = math.max(self.radius * 0.9, 0.5)
	local back = offset.Unit * (radius + 0.5)
	return Workspace:Spherecast(from - back, radius, offset + back, params) == nil
end

-- True once per StuckCheckInterval if the creature barely moved while far from its goal.
function Navigator:CheckStuck(goal: Vector3, now: number): boolean
	local position = self.root.Position
	-- No sample yet, or movement was paused (attacking, stunned): start a fresh sample.
	if not self.checkPosition or now - self.checkTime > NAV.StuckCheckInterval * 3 then
		self.checkPosition, self.checkTime = position, now
		return false
	end
	if now - self.checkTime < NAV.StuckCheckInterval then
		return false
	end
	local moved = Vector3.new(position.X - self.checkPosition.X, 0, position.Z - self.checkPosition.Z).Magnitude
	local remaining = Vector3.new(goal.X - position.X, 0, goal.Z - position.Z).Magnitude
	self.checkPosition, self.checkTime = position, now
	return moved < NAV.StuckMinProgress and remaining > self.radius + 3
end

function Navigator:ComputeAsync(goal: Vector3)
	if self.computing then
		return
	end
	self.computing = true
	self.lastPath = os.clock()
	task.spawn(function()
		local ok = pcall(function()
			self.path:ComputeAsync(self.root.Position, goal)
		end)
		self.computing = false
		if ok and self.path.Status == Enum.PathStatus.Success then
			self.waypoints = self.path:GetWaypoints()
			self.index = math.min(2, #self.waypoints)
		else
			self.waypoints = nil -- unreachable: fall back to walking straight at it
		end
		if Config.Dev.DebugNavigation then
			drawPath(self.waypoints, goal)
		end
	end)
end

function Navigator:MoveTo(goal: Vector3)
	local now = os.clock()
	local goalMoved = not self.goal or (goal - self.goal).Magnitude > NAV.RepathDistance
	self.goal = goal

	if self:CheckStuck(goal, now) then
		self.detourUntil = now + NAV.DetourDuration
		if self.waypoints or self.sidestep then
			-- Already detouring and still stuck: try the other side next time.
			self.sidestepSign = -self.sidestepSign
		end
		self.waypoints = nil
		self.sidestep = nil
		self.lastPath = 0 -- allow an immediate repath
	end

	local detouring = now < self.detourUntil
	if not detouring and self:IsDirectClear(goal) then
		self.waypoints = nil
		self.sidestep = nil
		self.humanoid:MoveTo(goal)
		return
	end

	if (goalMoved or not self.waypoints) and now - self.lastPath >= NAV.RepathInterval then
		self:ComputeAsync(goal)
	end

	-- No path (goal unreachable or still computing) while stuck: step sideways around
	-- the obstacle instead of pushing into it.
	if detouring and not self.waypoints and not self.computing then
		if not self.sidestep then
			local toGoal = Vector3.new(goal.X - self.root.Position.X, 0, goal.Z - self.root.Position.Z)
			local forward = toGoal.Magnitude > 0.1 and toGoal.Unit or self.root.CFrame.LookVector
			local side = Vector3.new(-forward.Z, 0, forward.X) * self.sidestepSign
			self.sidestep = self.root.Position + side * (self.radius + 6) + forward * 2
		end
		self.humanoid:MoveTo(self.sidestep)
		return
	end

	local waypoints = self.waypoints
	if waypoints and waypoints[self.index] then
		local target = waypoints[self.index].Position
		local flat = Vector3.new(target.X - self.root.Position.X, 0, target.Z - self.root.Position.Z)
		if flat.Magnitude < NAV.WaypointReach and self.index < #waypoints then
			self.index += 1
			target = waypoints[self.index].Position
		end
		self.humanoid:MoveTo(target)
	else
		self.humanoid:MoveTo(goal)
	end
end

function Navigator:Stop()
	self.waypoints = nil
	self.sidestep = nil
	self.checkPosition = nil -- standing still on purpose isn't being stuck
	self.humanoid:MoveTo(self.root.Position)
end

return NavigationService
