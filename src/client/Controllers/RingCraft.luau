--[[
	RingCraft  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/RingCraft

	HOW A NIGHTMARE CARRIES ITSELF BETWEEN BLOWS: a heavy machine that really boxes. Laid over
	the fighting stance (NightmareAnimator), in fights and in the Nightmare Gym.

	  Pendulum   the weight rocks from foot to foot, the guard working in time with it
	  Beats      head movement every moment or two: slips, rolls under a shot, bobs, a pull
	             back, a feint with the lead hand, a roll of the shoulders
	  Weight     the body lags behind where the feet take it and settles past it, a footfall
	             lands hard, and every blow it throws sends a shudder through it

	The legs are one piece, so the hips do what knees would: they swing to keep the feet where
	they stood when the body moves, and split apart when it sinks. Keyframed clips override all
	of this, except Weight, which goes on top of them.
]]

local RingCraft = {}

local pi, sin, rad = math.pi, math.sin, math.rad
local clamp, min, abs, asin, acos = math.clamp, math.min, math.abs, math.asin, math.acos

local LEG = 3.2 -- studs, hip to floor (near enough on every body)
local BEAT_GAP = { 0.3, 1.2 }
local LEAN_SPRING, LEAN_DAMP = 90, 10 -- under-damped: the body swings past and settles
local DIP_SPRING, DIP_DAMP = 130, 13

-- Each beat: its length, how often it's picked, and what the body does at u (0..1) on a side
-- (+1 = right): studs { x, y, z }, degrees { pitch, yaw, roll }, arms { left, right, left
-- forearm, right forearm }. -pitch tips forward; -roll leans right.
local BEATS = {
	{
		Name = "Slip",
		Time = { 0.36, 0.5 },
		Weight = 4,
		Move = function(u, side)
			local e = sin(pi * u)
			return side * 0.55 * e, -0.14 * e, 0, -9 * e, 9 * side * e, -14 * side * e, 0, 0, 0, 0
		end,
	},
	{
		Name = "Roll", -- the U: off to one side, down under the shot, up on the other
		Time = { 0.78, 1 },
		Weight = 3,
		Move = function(u, side)
			local across, down = sin(2 * pi * u), sin(pi * u) ^ 2
			return side * 0.55 * across, -0.5 * down, 0, -20 * down, 10 * side * across, -13 * side * across, 0, 0, 0, 0
		end,
	},
	{
		Name = "Bob",
		Time = { 0.36, 0.52 },
		Weight = 2,
		Move = function(u)
			local e = sin(pi * u)
			return 0, -0.42 * e, -0.06 * e, -15 * e, 0, 0, 0, 0, 0, 0
		end,
	},
	{
		Name = "Pull", -- leans just out of reach, weight on the back foot
		Time = { 0.34, 0.48 },
		Weight = 2,
		Move = function(u)
			local e = sin(pi * u)
			return 0, 0.04 * e, 0.42 * e, 11 * e, 0, 0, 0, 0, 0, 0
		end,
	},
	{
		Name = "Feint", -- the lead shoulder and hand twitch out, and don't commit
		Time = { 0.28, 0.38 },
		Weight = 3,
		Arms = true,
		Move = function(u)
			local e = sin(pi * u)
			return 0, -0.05 * e, -0.2 * e, -5 * e, -16 * e, 0, 22 * e, 0, -42 * e, 0
		end,
	},
	{
		Name = "Shoulders", -- rolling the guard across, one shoulder then the other
		Time = { 0.5, 0.7 },
		Weight = 2,
		Arms = true,
		Move = function(u, side)
			local across = sin(2 * pi * u)
			return 0, 0, 0, -3, 15 * side * across, 0, 8 * across * side, -8 * across * side, 0, 0
		end,
	},
}

local function ringOf(state, model: Model)
	local ring = state.ring
	if not ring then
		-- (each body has its own rhythm)
		local rng = Random.new(math.floor(state.seed * 1000) + #model.Name)
		ring = {
			rng = rng,
			w = 0,
			phase = rng:NextNumber(0, 2 * pi),
			rate = rng:NextNumber(3.1, 3.9),
			nextBeat = 0,
			side = rng:NextNumber() < 0.5 and 1 or -1,
			pitch = 0, pitchVel = 0,
			roll = 0, rollVel = 0,
			dip = 0, dipVel = 0,
			lastSpeed = 0,
			lastStep = 0,
		}
		state.ring = ring
	end
	return ring
end

local function pickBeat(ring, armed: boolean)
	local total = 0
	for _, beat in BEATS do
		if armed or not beat.Arms then
			total += beat.Weight
		end
	end
	local roll = ring.rng:NextNumber(0, total)
	for _, beat in BEATS do
		if armed or not beat.Arms then
			roll -= beat.Weight
			if roll <= 0 then
				return beat
			end
		end
	end
	return BEATS[1]
end

-- A blow landed (a clip's stopped contact frame): the shock runs back through the machine.
function RingCraft.Thud(state, amount: number?)
	local ring = state.ring
	if ring then
		local a = amount or 1
		ring.dipVel -= 2.6 * a
		ring.pitchVel -= 1.5 * a
	end
end

-- Pendulum and head movement, over the stance. `stance` is how far into it the body is.
function RingCraft.Apply(state, root: BasePart, stance: number, dt: number, now: number, speed: number, velocity: Vector3, markerEvent)
	local model, motors = state.model, state.motors
	local ring = ringOf(state, model)
	dt = min(dt, 0.05)

	-- WEIGHT: leaning the way the feet are going, swinging past when they stop (see Settle)
	local localVelocity = root.CFrame:VectorToObjectSpace(velocity)
	ring.pitchVel += ((localVelocity.Z * 0.009 - ring.pitch) * LEAN_SPRING - ring.pitchVel * LEAN_DAMP) * dt
	ring.pitch += ring.pitchVel * dt
	ring.rollVel += ((-localVelocity.X * 0.013 - ring.roll) * LEAN_SPRING - ring.rollVel * LEAN_DAMP) * dt
	ring.roll += ring.rollVel * dt
	ring.dipVel += (-ring.dip * DIP_SPRING - ring.dipVel * DIP_DAMP) * dt
	ring.dip += ring.dipVel * dt
	local braked = ring.lastSpeed - speed
	if braked > 6 and stance > 0.5 then
		ring.dipVel -= min(braked, 24) * 0.09 -- stopped dead: all that mass arrives
	end
	ring.lastSpeed = speed

	local busy = state.pose ~= nil or state.react ~= nil or state.track ~= nil or (state.action ~= nil and now - state.actionStart <= state.duration)
	ring.w += ((busy and 0 or stance) - ring.w) * min(1, dt * (busy and 16 or 6))
	local w = ring.w
	if w <= 0.01 then
		ring.beat = nil
		return
	end

	-- footfalls while it moves in the stance
	local walk = sin(state.walkPhase)
	local stepSide = walk > 0 and 1 or -1
	if speed > 5 and stepSide ~= ring.lastStep and stance > 0.5 then
		markerEvent:Fire(model, "RingCraft", stepSide > 0 and "StepL" or "StepR")
		ring.dipVel -= 0.9
	end
	ring.lastStep = stepSide

	local floating = model:GetAttribute("Archetype") == "Floating"
	local quadruped = model:GetAttribute("Archetype") == "Quadruped"
	local armed = motors.Joint_RightArm ~= nil or motors.Joint_LeftArm ~= nil
	local calm = 1 - 0.65 * clamp(speed / 14, 0, 1) -- (it doesn't slip at a dead run)

	-- PENDULUM
	ring.phase += dt * ring.rate
	local rock = sin(ring.phase)
	local x, y, z = rock * 0.16, abs(sin(ring.phase)) * 0.07 - 0.03, 0
	local pitch, yaw, roll = 0, sin(ring.phase * 0.5 + 1) * 6, -rock * 3.5
	local armL, armR = rock * 4, -rock * 4
	local foreL, foreR = -rock * 5, rock * 5

	-- BEATS
	if not ring.beat and now >= ring.nextBeat and speed < 9 then
		local beat = pickBeat(ring, armed)
		ring.side = ring.rng:NextNumber() < 0.75 and -ring.side or ring.side -- (mostly side to side)
		ring.beat = beat
		ring.beatStart = now
		ring.beatTime = ring.rng:NextNumber(beat.Time[1], beat.Time[2])
	end
	if ring.beat then
		local u = (now - ring.beatStart) / ring.beatTime
		if u >= 1 then
			ring.beat = nil
			ring.nextBeat = now + ring.rng:NextNumber(BEAT_GAP[1], BEAT_GAP[2])
		else
			local bx, by, bz, bp, by2, br, al, ar, fl, fr = ring.beat.Move(u, ring.side)
			x, y, z = x + bx * calm, y + by * calm, z + bz * calm
			pitch, yaw, roll = pitch + bp * calm, yaw + by2 * calm, roll + br * calm
			armL, armR, foreL, foreR = armL + al, armR + ar, foreL + fl, foreR + fr
		end
	end

	local function turn(joint: string, ax: number, ay: number, az: number)
		local motor = motors[joint]
		if motor then
			motor.Transform = motor.Transform * CFrame.Angles(ax * w, ay * w, az * w)
		end
	end
	local core = motors.Joint_Core
	if core then
		core.Transform = CFrame.new(x * w, y * w, z * w) * core.Transform * CFrame.Angles(rad(pitch) * w, rad(yaw) * w, rad(roll) * w)
	end
	-- the eyes stay level and on the target (a four-legged head pitches the other way)
	turn("Joint_Head", rad(-pitch) * (quadruped and -0.55 or 0.55), rad(-yaw) * 0.7, rad(-roll) * 0.7)
	turn("Joint_LeftArm", rad(armL), 0, 0)
	turn("Joint_RightArm", rad(armR), 0, 0)
	turn("Sub_LeftArm_Fore", rad(foreL), 0, 0)
	turn("Sub_RightArm_Fore", rad(foreR), 0, 0)
	if floating then
		return
	end
	-- the hips keep the feet where they stood...
	turn("Joint_Legs", rad(-pitch) + asin(clamp(z / LEG, -0.6, 0.6)), rad(-yaw), rad(-roll) - asin(clamp(x / LEG, -0.6, 0.6)))
	-- ...and split when it sinks, the weight rolling from foot to foot
	local split = y < 0 and acos(clamp(1 + y / LEG, 0.5, 1)) or 0
	local rollWeight = rad(rock * 5)
	turn("Sub_Legs_L", split + rollWeight, 0, 0)
	turn("Sub_Legs_R", -split - rollWeight, 0, 0)
	turn("Sub_Legs_FL", split + rollWeight, 0, 0)
	turn("Sub_Legs_BR", -split + rollWeight, 0, 0)
	turn("Sub_Legs_FR", split - rollWeight, 0, 0)
	turn("Sub_Legs_BL", -split - rollWeight, 0, 0)
end

-- The body's mass, on top of whatever else is moving it (clips included). Last thing each frame.
function RingCraft.Settle(state)
	local ring = state.ring
	local core = state.motors.Joint_Core
	if ring and core then
		core.Transform = CFrame.new(0, ring.dip, 0) * core.Transform * CFrame.Angles(ring.pitch, 0, ring.roll)
	end
end

return RingCraft
