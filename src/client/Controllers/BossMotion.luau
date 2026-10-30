--[[
	BossMotion  (ModuleScript, client)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/BossMotion

	How each boss stands and moves when it isn't attacking: every boss is its own creature, so
	each has its own idle and its own way across the floor, driven by how fast it's really
	going. BossMotion[bossId](state, motors, root, dt, now, speed, markerEvent) lays that over
	the animator's base pose each frame (hit rocking stays; attack clips still override it).

	Joints: +X on arms is forward / up, Z +=toward its right; Joint_Core +X leans back, +Y turns
	left, +Z leans left; Knee -X bends the shin back; Sub_Legs +X forward.
]]

local BossMotion = {}

local function add(motor: Motor6D?, cframe: CFrame)
	if motor then
		motor.Transform = motor.Transform * cframe
	end
end

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- A stride's phase that really covers the ground (one full step cycle per `length` studs), with
-- footfall markers (the animator's usual StepL / StepR sounds).
local function strideOf(state, dt: number, speed: number, length: number, markerEvent): (number, number)
	local move = math.clamp(speed / 4, 0, 1)
	local before = state.bossStride or 0
	local stride = before + dt * speed / length * math.pi * 2
	if move < 0.05 then
		-- standing: settles to the feet together, no more steps
		stride = before
	end
	state.bossStride = stride
	if move > 0.2 and markerEvent then
		local a, b = math.floor(before / math.pi), math.floor(stride / math.pi)
		if a ~= b then
			markerEvent:Fire(state.model, state.action, b % 2 == 0 and "StepL" or "StepR")
		end
	end
	return stride, move
end

-- SCRAP TITAN: tons of walking scrap. Each step is a lift, a swing and a plant: the knee bends
-- through the swing, the whole mass rises over the planted leg and drops into the next, the
-- shoulders roll against the hips, and the wrecking ball hangs and swings on its own weight.
-- Standing, the reactor breathes: a slow heave of the chest, the head turning.
function BossMotion.ScrapTitan(state, motors, _root, dt: number, now: number, speed: number, markerEvent)
	local stride, move = strideOf(state, dt, speed, 15, markerEvent)
	local swing = math.sin(stride)
	local thighL, thighR = swing * 26 * move, -swing * 26 * move
	-- the knee bends only while that leg swings through (going forward)
	local kneeL = -math.max(0, math.cos(stride)) * 48 * move - 4
	local kneeR = -math.max(0, -math.cos(stride)) * 48 * move - 4
	add(motors.Sub_Legs_L, angles(thighL + 2, 0, 0))
	add(motors.Sub_Legs_R, angles(thighR + 2, 0, 0))
	add(motors.Knee_L, angles(kneeL, 0, 0))
	add(motors.Knee_R, angles(kneeR, 0, 0))

	local heave = math.sin(now * 1.15 + state.seed)
	local rise = math.abs(math.cos(stride)) * 0.5 * move - 0.25 * move
	local core = CFrame.new(0, rise + heave * 0.05 * (1 - move), 0)
		* angles(heave * 1.2 * (1 - move) - 7 * move, -swing * 9 * move, swing * 4 * move)
	if motors.Joint_Core then
		motors.Joint_Core.Transform = motors.Joint_Core.Transform * core
	end
	add(motors.Joint_Head, angles(4 * move, math.sin(now * 0.4 + state.seed) * 16 * (1 - move) + swing * 6 * move, 0))
	-- the ball swings late and heavy; the magnet arm is carried, ready
	local ballLag = math.sin(stride - 0.9)
	add(motors.Joint_RightArm, angles(14 + ballLag * 22 * move + heave * 2, 0, 16))
	add(motors.Joint_LeftArm, angles(32 - swing * 12 * move - heave * 2, 0, -12))
end

-- MIRROR WARDEN: floats, and never hurries: it glides on a slow figure of eight, the blade held
-- low and out, the mirror up. It leans into where it's going, and the blade trails behind it.
function BossMotion.MirrorWarden(state, motors, root, dt: number, now: number, speed: number)
	local velocity = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local lastLean = state.bossLean or Vector3.zero
	local lean = lastLean:Lerp(Vector3.new(velocity.X, 0, velocity.Z) / 22, math.min(1, dt * 4))
	state.bossLean = lean
	local a = now * 0.9 + state.seed
	local core = CFrame.new(math.sin(a) * 0.25, 0.3 + math.sin(a * 2) * 0.12, 0) * angles(lean.Z * 22 - 5, math.sin(a * 0.5) * 6, -lean.X * 18 + math.sin(a) * 2)
	if motors.Joint_Core then
		motors.Joint_Core.Transform = motors.Joint_Core.Transform * core
	end
	add(motors.Joint_Head, angles(-lean.Z * 10 - 3, -math.sin(a * 0.5) * 8, 0))
	add(motors.Joint_RightArm, angles(30 + math.sin(a * 1.3) * 3 + math.clamp(lean.Z, -1, 1) * 22, 0, 34 + math.cos(a) * 3))
	add(motors.Joint_LeftArm, angles(62 + math.sin(a * 1.1 + 1) * 3, 0, 8 - math.clamp(lean.X, -1, 1) * 8))
	local _ = speed
end

-- STORM BEAST: a big cat on rigid legs. It prowls shoulders-low with the head level and the tail
-- out behind; at speed the walk becomes a bound, front pair then back pair, the body rocking
-- over them. Standing, it's never still: it breathes hard, tail lashing, head scanning.
function BossMotion.StormBeast(state, motors, _root, dt: number, now: number, speed: number, markerEvent)
	local stride, move = strideOf(state, dt, speed, 17, markerEvent)
	local run = math.clamp((speed - 14) / 14, 0, 1)
	local s = math.sin(stride)
	local gait = 24 * move
	-- walk: diagonal pairs. Run: front pair against back pair, the feet bunching and spreading.
	local fl, fr, bl, br = s * gait, -s * gait, -s * gait, s * gait
	local bound = math.sin(stride) * 38 * move
	fl, fr = fl + (bound - fl) * run, fr + (bound * 0.85 - fr) * run
	bl, br = bl + (-bound - bl) * run, br + (-bound * 0.85 - br) * run
	add(motors.Sub_Legs_FL, angles(fl + 3, 0, 0))
	add(motors.Sub_Legs_FR, angles(fr + 3, 0, 0))
	add(motors.Sub_Legs_BL, angles(bl - 3, 0, 0))
	add(motors.Sub_Legs_BR, angles(br - 3, 0, 0))
	local breath = math.sin(now * 2.6 + state.seed)
	local rock = math.cos(stride) * (2 + run * 9) * move
	local core = CFrame.new(0, math.abs(s) * (0.18 + run * 0.6) * move + breath * 0.04, 0) * angles(-4 + rock + breath * 0.8 * (1 - move), s * 5 * move * (1 - run), s * 2 * move * (1 - run))
	if motors.Joint_Core then
		motors.Joint_Core.Transform = motors.Joint_Core.Transform * core
	end
	add(motors.Joint_Head, angles(4 - rock * 0.7, math.sin(now * 0.7 + state.seed) * 14 * (1 - move), 0))
	-- the tail: a lash that travels, stiffer at a run
	add(motors.Joint_Tail, angles(-12 - run * 14 + math.cos(stride * 0.5) * 8 * move, math.sin(now * (3.4 + move * 2) + state.seed) * (26 - run * 14), 0))
end

-- ABYSSAL MAW: a column of muscle rising out of the floor, always moving: an S-curve running up
-- the body, the maw held out over it swaying the other way, each tentacle coiling on its own.
function BossMotion.AbyssalMaw(state, motors, _root, _dt: number, now: number, _speed: number)
	local a = now * 1.05 + state.seed
	local core = CFrame.new(math.sin(a) * 0.3, math.sin(a * 0.7) * 0.35, math.cos(a * 0.8) * 0.2) * angles(math.cos(a * 0.8) * 5, math.sin(a * 0.5) * 8, math.sin(a) * 6)
	if motors.Joint_Core then
		motors.Joint_Core.Transform = motors.Joint_Core.Transform * core
	end
	-- the maw lags the body and leans the opposite way, like the top of a whip
	add(motors.Joint_Head, angles(math.cos(a * 0.8 - 0.7) * 8 - 6, -math.sin(a * 0.5 - 0.7) * 10, -math.sin(a - 0.7) * 9))
	add(motors.Joint_RightArm, angles(55 + math.sin(a * 1.6) * 26, math.sin(a * 0.9) * 18, 34 + math.cos(a * 1.3) * 20))
	add(motors.Joint_LeftArm, angles(55 + math.sin(a * 1.45 + 2) * 26, math.sin(a * 1.1 + 1) * 18, -34 - math.cos(a * 1.2 + 2) * 20))
end

return BossMotion
