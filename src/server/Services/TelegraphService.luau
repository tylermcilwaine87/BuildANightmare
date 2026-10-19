--[[
	TelegraphService  (ModuleScript)
	Location: ServerScriptService/Server/Services/TelegraphService

	Every telegraphed attack goes through here, which does two jobs:
	  1. Sends the warning shape to every client near it (WorldFX "Telegraph"), so players
	     always get a readable warning before it hits.
	  2. Keeps a server-side registry of active HOSTILE zones, so companion AI can "see"
	     danger and (imperfectly) step out of it.

	The caller still applies the damage when the warning ends (keeps timing in one place).

	Shapes:  Circle(position, radius, duration, style)
	         Box(cframe, size, duration, style)       size.Y is ignored (flat on the floor)
	Styles:  "Hostile" (red), "Pull" (blue), "Friendly" (purple)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))

local TelegraphService = {}
-- Warnings go to players near them (plus the shape's own size, so long beams reach
-- everyone they could hit).
local RADIUS = Config.Performance.EffectRadius

local zones = {} -- [id] = zone
local nextId = 0

function TelegraphService:Init()
	self.WorldFX = Net.Get("WorldFX")
end

local function register(zone)
	nextId += 1
	zone.Id = nextId
	zone.EndTime = os.clock() + zone.Duration
	if zone.Style ~= "Friendly" then
		zones[zone.Id] = zone
		task.delay(zone.Duration + 0.1, function()
			zones[zone.Id] = nil
		end)
	end
	return zone
end

function TelegraphService:Circle(position: Vector3, radius: number, duration: number, style: string?)
	local zone = register({ Shape = "Circle", Position = position, Radius = radius, Duration = duration, Style = style or "Hostile" })
	Net.FireNearby(self.WorldFX, position, RADIUS + radius, "Telegraph", {
		Shape = "Circle",
		Position = position,
		Radius = radius,
		Duration = duration,
		Style = zone.Style,
	})
	return zone
end

function TelegraphService:Box(cframe: CFrame, size: Vector3, duration: number, style: string?)
	local zone = register({ Shape = "Box", CFrame = cframe, Size = size, Duration = duration, Style = style or "Hostile" })
	Net.FireNearby(self.WorldFX, cframe.Position, RADIUS + math.max(size.X, size.Z), "Telegraph", {
		Shape = "Box",
		CFrame = cframe,
		Size = size,
		Duration = duration,
		Style = zone.Style,
	})
	return zone
end

function TelegraphService:Impact(position: Vector3, radius: number, style: string?)
	Net.FireNearby(self.WorldFX, position, RADIUS + radius, "Impact", { Position = position, Radius = radius, Style = style or "Hostile" })
end

function TelegraphService:Projectile(from: Vector3, to: Vector3, duration: number)
	Net.FireNearby(self.WorldFX, to, RADIUS + (to - from).Magnitude, "Projectile", { From = from, To = to, Duration = duration })
end

local function contains(zone, position: Vector3, padding: number): boolean
	if zone.Shape == "Circle" then
		local d = Vector3.new(position.X - zone.Position.X, 0, position.Z - zone.Position.Z).Magnitude
		return d <= zone.Radius + padding
	end
	local localPos = zone.CFrame:PointToObjectSpace(position)
	return math.abs(localPos.X) <= zone.Size.X / 2 + padding and math.abs(localPos.Z) <= zone.Size.Z / 2 + padding
end

-- Returns the most urgent hostile zone containing `position`, or nil.
function TelegraphService:FindHostileZone(position: Vector3, padding: number?)
	local best = nil
	for _, zone in zones do
		if contains(zone, position, padding or 0) and (not best or zone.EndTime < best.EndTime) then
			best = zone
		end
	end
	return best
end

-- A point just outside the zone, moving away from its centre.
function TelegraphService:EscapePoint(zone, position: Vector3, margin: number): Vector3
	if zone.Shape == "Circle" then
		local away = Vector3.new(position.X - zone.Position.X, 0, position.Z - zone.Position.Z)
		if away.Magnitude < 0.5 then
			away = Vector3.new(1, 0, 0)
		end
		return zone.Position + away.Unit * (zone.Radius + margin) + Vector3.new(0, position.Y - zone.Position.Y, 0)
	end
	local localPos = zone.CFrame:PointToObjectSpace(position)
	local side = localPos.X >= 0 and 1 or -1
	local out = Vector3.new(side * (zone.Size.X / 2 + margin), localPos.Y, localPos.Z)
	return zone.CFrame:PointToWorldSpace(out)
end

return TelegraphService
