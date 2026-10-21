--[[
	NightmarePoses  (ModuleScript, data only)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/NightmarePoses

	Keyframed attacks for Nightmares, per ARCHETYPE (body plan), keyed by the Nightmare
	skeleton's joint names (NightmareAssembler: Joint_Core from the root, Joint_<Slot> from
	the core, Sub_<Slot>_<Group> for leg / wing pairs). Because every Nightmare of a body
	plan shares those names, one animation drives ANY parts combination; a slot that isn't
	fitted is simply skipped. Played by NightmareAnimator (exactly like HandlerPoses: the
	same keyframes are exported to an editable KeyframeSequence by tools/AnimationExporter).

	Angles in degrees (X, Y, Z) in the joint's own frame (model axes: +X right, +Y up,
	-Z forward):
	  Joint_Core  +X leans BACK, -X forward; +Y turns left; +Z leans left.
	              Joint_CorePos = { x, y, z } studs moves the whole body (-Z forward).
	  Arms        +X swings the arm forward / up from hanging; Z swings it out to the side
	              (+Z = toward the right for both arms).
	  Legs        Sub_Legs_L / Sub_Legs_R: +X swings the leg forward.
	  Head        +X tilts back.
	Markers: { time, name }; "Hit" must sit on the frame the server lands the hit (the
	animation is played at whatever speed puts it there: the attack's windup).
]]

-- A move mirrored left <-> right (for an arm ability performed by the left limb): the
-- Right/Left arm joints and the L/R leg joints swap, every Y (turn) and Z (sideways)
-- angle flips, and so does any position's X.
local function mirrorJoint(name: string): string
	if name:find("Right") then
		return (name:gsub("Right", "Left"))
	elseif name:find("Left") then
		return (name:gsub("Left", "Right"))
	elseif name:sub(-2) == "_L" then
		return name:sub(1, -3) .. "_R"
	elseif name:sub(-2) == "_R" then
		return name:sub(1, -3) .. "_L"
	end
	return name
end
local function mirrored(def)
	local out = { Duration = def.Duration, Keys = {}, Markers = {} }
	for _, key in def.Keys do
		local k = { T = key.T }
		for name, v in key do
			if name ~= "T" then
				k[mirrorJoint(name)] = name:match("Pos$") and { -v[1], v[2], v[3] } or { v[1], -v[2], -v[3] }
			end
		end
		table.insert(out.Keys, k)
	end
	for _, marker in def.Markers or {} do
		local name = marker[2] == "StepL" and "StepR" or marker[2] == "StepR" and "StepL" or marker[2]
		table.insert(out.Markers, { marker[1], name })
	end
	return out
end
-- The same move stretched in time (a slower, heavier variant).
local function scaled(def, factor: number)
	local out = { Duration = def.Duration * factor, Keys = {}, Markers = {} }
	for _, key in def.Keys do
		local k = table.clone(key)
		k.T = key.T * factor
		table.insert(out.Keys, k)
	end
	for _, marker in def.Markers or {} do
		table.insert(out.Markers, { marker[1] * factor, marker[2] })
	end
	return out
end

-- BITE (any Nightmare with a head; jaw-equipped heads open and snap their Sub_Head_Jaw).
-- Ability windup 0.3 s = the Hit frame; the body also physically lunges ~3 studs at the
-- target during the windup (AbilityService), so the jaws really reach them.
-- Then it CLAMPS: the jaw stays locked while the head and body thrash side to side, the
-- victim held in the mouth and shaken in step (AbilityService:ClampAndRip, Clamp.Shake
-- 2.6 per second: head left at 0.396 s, right at 0.588 s, ...), grinding in. At 1.75 s
-- ("Rip", = windup + Clamp.Hold) the head tears away to the LEFT and the jaw lets go.
local CLAMPED = { Joint_CorePos = { 0, -0.38, -0.95 }, Sub_Head_Jaw = { 2, 0, 0 }, Joint_RightArm = { 78, 0, 6 }, Joint_LeftArm = { 78, 0, -6 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }
local function thrash(t: number, side: number, depth: number)
	local key = table.clone(CLAMPED)
	key.T = t
	key.Joint_Core = { -24 + depth, 9 * side, -4 * side }
	key.Joint_Head = { -14, 22 * side, 7 * side }
	key.Joint_RightArm = { 78 - depth, 0, 6 + 6 * side }
	key.Joint_LeftArm = { 78 - depth, 0, -6 + 6 * side }
	return key
end
local BITE = {
	Duration = 2.3,
	Markers = {
		{ 0.22, "Whoosh" }, { 0.3, "Hit" }, { 0.3, "JawSnap" }, { 0.3, "StepL" },
		{ 0.588, "Grind" }, { 0.973, "Grind" }, { 1.358, "Grind" },
		{ 1.65, "Whoosh" }, { 1.75, "Rip" }, { 1.75, "StepR" },
	},
	Keys = {
		{ T = 0 },
		-- prepare: rear back, head up, lips part, arms rise to grab
		{ T = 0.12, Joint_CorePos = { 0, -0.3, 0.25 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Head_Jaw = { -12, 0, 0 }, Joint_RightArm = { 35, 0, 12 }, Joint_LeftArm = { 35, 0, -12 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
		-- lunge: neck and torso driving forward, jaw dropped wide, claws reaching
		{ T = 0.22, Joint_CorePos = { 0, -0.25, -0.7 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Head_Jaw = { -62, 0, 0 }, Joint_RightArm = { 70, 0, 22 }, Joint_LeftArm = { 70, 0, -22 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
		-- SNAP: the jaws slam shut on them, claws clamp in
		{ T = 0.3, Joint_CorePos = { 0, -0.35, -1.0 }, Joint_Core = { -26, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Joint_RightArm = { 78, 0, 6 }, Joint_LeftArm = { 78, 0, -6 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
		-- CLAMPED: thrashing them side to side, digging in harder each shake
		thrash(0.396, 1, 0),
		thrash(0.588, -1, 1),
		thrash(0.781, 1, 2),
		thrash(0.973, -1, 3),
		thrash(1.165, 1, 4),
		thrash(1.358, -1, 5),
		thrash(1.55, 1, 6),
		-- load the rip: brace, twist the other way, jaws still locked
		{ T = 1.65, Joint_CorePos = { 0, -0.45, -0.8 }, Joint_Core = { -20, -16, 2 }, Joint_Head = { -10, -26, -6 }, Sub_Head_Jaw = { 0, 0, 0 }, Joint_RightArm = { 70, 0, 4 }, Joint_LeftArm = { 70, 0, -10 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } },
		-- RIP: the head tears away to the left and up, the body pulling back off them
		{ T = 1.75, Joint_CorePos = { 0, -0.2, 0.2 }, Joint_Core = { 8, 34, 0 }, Joint_Head = { 12, 40, 10 }, Sub_Head_Jaw = { -10, 0, 0 }, Joint_RightArm = { 20, 0, 30 }, Joint_LeftArm = { 20, 0, -30 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
		-- release: the jaw falls open, the head comes round
		{ T = 1.88, Joint_CorePos = { 0, -0.12, 0.15 }, Joint_Core = { 4, 20, 0 }, Joint_Head = { 6, 30, 0 }, Sub_Head_Jaw = { -34, 0, 0 }, Joint_RightArm = { 26, 0, 20 }, Joint_LeftArm = { 26, 0, -20 } },
		{ T = 2.05, Joint_Core = { 0, 6, 0 }, Joint_Head = { 0, 8, 0 }, Sub_Head_Jaw = { -8, 0, 0 }, Joint_RightArm = { 10, 0, 8 }, Joint_LeftArm = { 10, 0, -8 } },
		{ T = 2.3 },
	},
}

-- RUSTY SLASH (authored for the RIGHT arm; the left-arm claw plays the mirror): coil the
-- body away with the claw arm drawn back out to the side, then the hips and shoulders
-- unwind and the claw rips across through the space in front at chest height, carries on
-- across, and the body resets. Windup 0.3 s = the Hit frame (mid-sweep, in front).
local RUSTY_SLASH = {
	Duration = 0.7,
	Markers = { { 0.14, "StepR" }, { 0.14, "Whoosh" }, { 0.3, "Hit" } }, -- whoosh starts with the swing so it peaks mid-arc
	Keys = {
		{ T = 0 },
		-- wind up: torso turned right and low, claw drawn back out wide, eyes on them
		{ T = 0.14, Joint_CorePos = { 0.15, -0.22, 0.15 }, Joint_Core = { 4, -32, 0 }, Joint_Head = { 0, 26, 0 }, Joint_RightArm = { 40, 0, 72 }, Joint_LeftArm = { 42, 0, -12 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
		-- contact: unwinding hard, the claw sweeping through in front at chest height
		{ T = 0.3, Joint_CorePos = { -0.1, -0.28, -0.55 }, Joint_Core = { -10, 22, 0 }, Joint_Head = { -6, -14, 0 }, Joint_RightArm = { 95, 0, -20 }, Joint_LeftArm = { 12, 0, -22 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
		-- follow-through: across and down to the far side
		{ T = 0.42, Joint_CorePos = { -0.15, -0.3, -0.6 }, Joint_Core = { -12, 40, 0 }, Joint_Head = { -6, -26, 0 }, Joint_RightArm = { 78, 0, -66 }, Joint_LeftArm = { -10, 0, -26 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
		-- recover
		{ T = 0.58, Joint_CorePos = { 0, -0.1, -0.2 }, Joint_Core = { -4, 12, 0 }, Joint_Head = { 0, -6, 0 }, Joint_RightArm = { 30, 0, -14 }, Joint_LeftArm = { 6, 0, -8 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
		{ T = 0.7 },
	},
}

-- THE NIGHTMARE GYM: bag work (GymService plays these on the heavy bag; GymController
-- swings the bag on the Bag* markers, scaled per strike in GymDefinitions.Strikes).
-- Nightmare arms are rigid, so every punch is thrown from the shoulder and the core:
-- the torso turns into the shot and the body steps in behind it. Every combo works from
-- one fighting GUARD (orthodox: left side forward, chin down, hands up) and returns to it
-- between punches instead of dropping the hands.
local GUARD = {
	Joint_CorePos = { 0, -0.28, 0 },
	Joint_Core = { -6, -8, 0 },
	Joint_Head = { -6, 8, 0 },
	Joint_RightArm = { 64, 0, -20 },
	Joint_LeftArm = { 72, 0, 16 },
	Sub_Legs_L = { 14, 0, 0 },
	Sub_Legs_R = { -10, 0, 0 },
}
-- each strike's pose = the guard with these joints changed
local JAB = { Joint_LeftArm = { 92, 0, 6 }, Joint_Core = { -10, -14, 0 }, Joint_CorePos = { 0, -0.3, -0.45 }, Joint_Head = { -8, 12, 0 }, Joint_RightArm = { 64, 0, -22 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } }
local CROSS = { Joint_RightArm = { 94, 0, -6 }, Joint_LeftArm = { 66, 0, 26 }, Joint_Core = { -14, 26, 0 }, Joint_CorePos = { 0, -0.36, -0.6 }, Joint_Head = { -8, -20, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }
local HOOK_WIND = { Joint_LeftArm = { 82, 0, -46 }, Joint_Core = { -8, 18, 0 }, Joint_CorePos = { 0, -0.36, -0.25 }, Joint_RightArm = { 64, 0, -24 }, Joint_Head = { -6, -12, 0 } }
local HOOK = { Joint_LeftArm = { 86, 0, 16 }, Joint_Core = { -12, -32, 0 }, Joint_CorePos = { 0, -0.4, -0.45 }, Joint_Head = { -6, 26, 0 }, Joint_RightArm = { 66, 0, -24 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } }
local HOOK_FOLLOW = { Joint_LeftArm = { 80, 0, 34 }, Joint_Core = { -10, -40, 0 }, Joint_CorePos = { 0, -0.38, -0.4 }, Joint_Head = { -6, 30, 0 } }
local OVER_LOAD = { Joint_RightArm = { 150, 0, 22 }, Joint_LeftArm = { 62, 0, 22 }, Joint_Core = { 6, -26, 0 }, Joint_CorePos = { 0, -0.45, 0.25 }, Joint_Head = { -12, 22, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } }
local OVERHAND = { Joint_RightArm = { 80, 0, -14 }, Joint_LeftArm = { 20, 0, 22 }, Joint_Core = { -24, 26, -6 }, Joint_CorePos = { 0, -0.55, -0.85 }, Joint_Head = { 4, -18, 0 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } }
local OVER_FOLLOW = { Joint_RightArm = { 40, 0, -34 }, Joint_LeftArm = { 16, 0, 20 }, Joint_Core = { -26, 34, -6 }, Joint_CorePos = { 0, -0.55, -0.95 }, Joint_Head = { 6, -22, 0 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } }
local BODY_WIND = { Joint_CorePos = { 0.2, -0.8, 0 }, Joint_Core = { -14, 12, 8 }, Joint_LeftArm = { 48, 0, -50 }, Joint_RightArm = { 60, 0, -22 }, Joint_Head = { -2, -8, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } }
local BODY_HOOK = { Joint_LeftArm = { 62, 0, 10 }, Joint_Core = { -16, -26, 6 }, Joint_CorePos = { 0, -0.85, -0.6 }, Joint_RightArm = { 62, 0, -22 }, Joint_Head = { -2, 22, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } }
local UPPER_LOAD = { Joint_RightArm = { 22, 0, -8 }, Joint_LeftArm = { 66, 0, 20 }, Joint_Core = { -12, -10, 0 }, Joint_CorePos = { 0, -0.8, -0.2 }, Joint_Head = { -4, 6, 0 } }
local UPPER = { Joint_RightArm = { 118, 0, -12 }, Joint_LeftArm = { 64, 0, 22 }, Joint_Core = { 2, 22, 0 }, Joint_CorePos = { 0, -0.25, -0.75 }, Joint_Head = { 10, -14, 0 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }

-- Kicks (two-legged bodies: Sub_Legs_L / Sub_Legs_R; +X swings a leg forward, +Z swings
-- the RIGHT leg out to its right). Contact poses measured on the gym bag in Studio (the
-- Tank, leg 3.09 studs): teep tip 2.8 studs out at mid-bag, roundhouse 3.65 (the side of
-- the bag), spinning back kick 3.95. GymService stands the body so each one lands.
-- (Joint_Core's lean is applied before its turn: with the back turned, +X lifts the leg
-- TOWARD the bag.)
local TEEP = { Sub_Legs_R = { 95, 0, -18 }, Sub_Legs_L = { -6, 0, 0 }, Joint_Core = { 14, 0, 0 }, Joint_CorePos = { 0, 0.1, -0.3 }, Joint_Head = { -14, 0, 0 } }
local ROUND_LOAD = { Joint_Core = { 0, -22, 0 }, Sub_Legs_R = { 35, 0, 50 }, Joint_Head = { -6, 22, 0 } }
local ROUND = { Joint_Core = { 4, 50, 0 }, Sub_Legs_R = { 100, 0, 45 }, Sub_Legs_L = { -4, 0, 0 }, Joint_CorePos = { 0, 0.2, -0.2 }, Joint_Head = { -6, -40, 0 }, Joint_RightArm = { 20, 0, 40 }, Joint_LeftArm = { 70, 0, 20 } }
local ROUND_FOLLOW = { Joint_Core = { 2, 70, 0 }, Sub_Legs_R = { 70, 0, 10 }, Joint_Head = { -6, -50, 0 }, Joint_RightArm = { 30, 0, 30 } }
local CLINCH = { Joint_RightArm = { 135, 0, -18 }, Joint_LeftArm = { 135, 0, 18 }, Joint_Core = { -12, 0, 0 }, Joint_CorePos = { 0, -0.1, -0.4 }, Joint_Head = { -16, 0, 0 } }
local KNEE_R = { Sub_Legs_R = { 100, 0, -12 }, Sub_Legs_L = { -6, 0, 0 }, Joint_Core = { -16, 6, 0 }, Joint_CorePos = { 0, 0.1, -0.5 } }
local KNEE_L = { Sub_Legs_L = { 100, 0, 12 }, Sub_Legs_R = { -6, 0, 0 }, Joint_Core = { -16, -6, 0 }, Joint_CorePos = { 0, 0.1, -0.5 } }

-- A key at time t: `base` (usually GUARD) with `change`'s joints laid over it.
local function at(t: number, base, change)
	local key = { T = t }
	for joint, v in base or {} do
		key[joint] = v
	end
	for joint, v in change or {} do
		key[joint] = v
	end
	return key
end
-- the guard, breathing: slightly lower / higher
local SETTLE = { Joint_CorePos = { 0, -0.2, 0.05 } }
local SINK = { Joint_CorePos = { 0, -0.36, 0 } }

local GYM = {
	-- JAB, JAB, CROSS
	Gym_ComboA = {
		Duration = 1.6,
		Markers = { { 0.24, "Whoosh" }, { 0.3, "BagJab" }, { 0.48, "Whoosh" }, { 0.54, "BagJab" }, { 0.72, "Whoosh" }, { 0.8, "BagCross" }, { 0.8, "StepR" } },
		Keys = {
			{ T = 0 },
			at(0.18, GUARD),
			at(0.3, GUARD, JAB),
			at(0.42, GUARD),
			at(0.54, GUARD, JAB),
			at(0.64, GUARD, { Joint_Core = { -6, -14, 0 } }),
			at(0.8, GUARD, CROSS),
			at(1.0, GUARD),
			at(1.3, GUARD, SETTLE),
			{ T = 1.6 },
		},
	},
	-- JAB, CROSS, LEFT HOOK
	Gym_ComboB = {
		Duration = 1.8,
		Markers = { { 0.24, "Whoosh" }, { 0.3, "BagJab" }, { 0.5, "Whoosh" }, { 0.56, "BagCross" }, { 0.56, "StepR" }, { 0.78, "Whoosh" }, { 0.86, "BagHook" }, { 0.86, "StepL" } },
		Keys = {
			{ T = 0 },
			at(0.18, GUARD),
			at(0.3, GUARD, JAB),
			at(0.42, GUARD),
			at(0.56, GUARD, CROSS),
			at(0.7, GUARD, HOOK_WIND),
			at(0.86, GUARD, HOOK),
			at(0.98, GUARD, HOOK_FOLLOW),
			at(1.15, GUARD),
			at(1.45, GUARD, SETTLE),
			{ T = 1.8 },
		},
	},
	-- JAB, LEFT HOOK, RIGHT OVERHAND
	Gym_ComboC = {
		Duration = 2.1,
		Markers = { { 0.24, "Whoosh" }, { 0.3, "BagJab" }, { 0.5, "Whoosh" }, { 0.58, "BagHook" }, { 0.58, "StepL" }, { 0.94, "Whoosh" }, { 1.04, "BagOverhand" }, { 1.04, "StepL" } },
		Keys = {
			{ T = 0 },
			at(0.18, GUARD),
			at(0.3, GUARD, JAB),
			at(0.44, GUARD, HOOK_WIND),
			at(0.58, GUARD, HOOK),
			at(0.68, GUARD, HOOK_FOLLOW),
			at(0.84, GUARD, OVER_LOAD),
			at(1.04, GUARD, OVERHAND),
			at(1.2, GUARD, OVER_FOLLOW),
			at(1.5, GUARD),
			at(1.8, GUARD, SETTLE),
			{ T = 2.1 },
		},
	},
	-- dip into a LEFT HOOK TO THE BODY, then rip a RIGHT UPPERCUT up the middle
	Gym_BodyRip = {
		Duration = 1.5,
		Markers = { { 0.4, "Whoosh" }, { 0.46, "BagBody" }, { 0.46, "StepL" }, { 0.68, "Whoosh" }, { 0.74, "BagUpper" }, { 0.74, "StepR" } },
		Keys = {
			{ T = 0 },
			at(0.18, GUARD),
			at(0.32, GUARD, BODY_WIND),
			at(0.46, GUARD, BODY_HOOK),
			at(0.6, GUARD, UPPER_LOAD),
			at(0.74, GUARD, UPPER),
			at(0.9, GUARD),
			at(1.2, GUARD, SETTLE),
			{ T = 1.5 },
		},
	},
	-- one big RIGHT OVERHAND, everything behind it
	Gym_Power = {
		Duration = 1.4,
		Markers = { { 0.4, "Whoosh" }, { 0.5, "BagOverhand" }, { 0.5, "StepL" } },
		Keys = {
			{ T = 0 },
			at(0.12, GUARD),
			at(0.3, GUARD, OVER_LOAD),
			at(0.5, GUARD, OVERHAND),
			at(0.66, GUARD, OVER_FOLLOW),
			at(1.0, GUARD),
			{ T = 1.4 },
		},
	},
	-- TEEP: the rear leg driven straight up through the middle of the bag, leaning back off
	-- it: a push kick that shoves the bag away
	Gym_Teep = {
		Duration = 1.3,
		Markers = { { 0.3, "Whoosh" }, { 0.42, "BagTeep" }, { 0.56, "StepR" } },
		Keys = {
			{ T = 0 },
			at(0.15, GUARD),
			at(0.3, GUARD, { Sub_Legs_R = { 60, 0, -10 }, Joint_Core = { 8, 0, 0 } }),
			at(0.42, GUARD, TEEP),
			at(0.56, GUARD, { Sub_Legs_R = { 50, 0, -10 }, Joint_Core = { 6, 0, 0 } }),
			at(0.8, GUARD),
			at(1.05, GUARD, SETTLE),
			{ T = 1.3 },
		},
	},
	-- ROUNDHOUSE: turn the hip over and whip the right leg round into the side of the bag,
	-- the right arm swinging down and back for balance
	Gym_Roundhouse = {
		Duration = 1.5,
		Markers = { { 0.32, "StepL" }, { 0.42, "Whoosh" }, { 0.5, "BagRound" } },
		Keys = {
			{ T = 0 },
			at(0.15, GUARD),
			at(0.32, GUARD, ROUND_LOAD),
			at(0.5, GUARD, ROUND),
			at(0.64, GUARD, ROUND_FOLLOW),
			at(0.9, GUARD),
			at(1.2, GUARD, SETTLE),
			{ T = 1.5 },
		},
	},
	-- CLINCH KNEES: grab the bag over the top and drive knees up into it, right, left, right
	Gym_KneeClinch = {
		Duration = 1.8,
		Markers = { { 0.2, "Clinch" }, { 0.5, "BagKnee" }, { 0.95, "BagKnee" }, { 1.35, "BagKnee" }, { 0.5, "StepL" }, { 0.95, "StepR" }, { 1.35, "StepL" } },
		Keys = {
			{ T = 0 },
			at(0.2, CLINCH),
			at(0.36, CLINCH, { Sub_Legs_R = { 40, 0, -8 } }),
			at(0.5, CLINCH, KNEE_R),
			at(0.65, CLINCH),
			at(0.82, CLINCH, { Sub_Legs_L = { 40, 0, 8 } }),
			at(0.95, CLINCH, KNEE_L),
			at(1.1, CLINCH),
			at(1.24, CLINCH, { Sub_Legs_R = { 40, 0, -8 } }),
			at(1.35, CLINCH, KNEE_R),
			at(1.5, CLINCH),
			{ T = 1.8 },
		},
	},
	-- SPINNING BACK KICK: turn the back on the bag, eyes over the shoulder, then drive the
	-- heel straight back through it and come round out of the spin
	Gym_SpinBackKick = {
		Duration = 1.6,
		Markers = { { 0.15, "StepR" }, { 0.5, "Whoosh" }, { 0.56, "BagSpin" }, { 0.95, "StepL" } },
		Keys = {
			{ T = 0 },
			at(0.12, GUARD),
			at(0.3, GUARD, { Joint_Core = { 0, -90, 0 }, Joint_Head = { 0, 70, 0 }, Sub_Legs_R = { 30, 0, 0 }, Joint_CorePos = { 0, -0.2, 0 } }),
			at(0.44, GUARD, { Joint_Core = { 15, -180, 0 }, Joint_Head = { 0, 80, 0 }, Sub_Legs_R = { 20, 0, 0 }, Joint_CorePos = { 0, 0.1, -0.2 } }),
			at(0.56, GUARD, { Joint_Core = { 35, -180, 0 }, Sub_Legs_R = { -100, 0, 0 }, Sub_Legs_L = { 6, 0, 0 }, Joint_CorePos = { 0, 0.3, -0.4 }, Joint_Head = { -10, 80, 0 }, Joint_RightArm = { 40, 0, 60 }, Joint_LeftArm = { 40, 0, -60 } }),
			at(0.7, GUARD, { Joint_Core = { 15, -200, 0 }, Sub_Legs_R = { -30, 0, 0 }, Joint_CorePos = { 0, 0.1, -0.3 }, Joint_Head = { 0, 60, 0 } }),
			at(0.95, GUARD, { Joint_Core = { 0, -300, 0 }, Sub_Legs_R = { 10, 0, 0 } }),
			at(1.2, GUARD, { Joint_Core = { -6, -368, 0 } }),
			{ T = 1.6, Joint_Core = { 0, -360, 0 } },
		},
	},
	-- footwork: bounce in the stance, a feint jab, a slip to each side, reset
	Gym_Bounce = {
		Duration = 1.6,
		Markers = { { 0.2, "StepL" }, { 0.6, "StepR" }, { 1.0, "StepL" } },
		Keys = {
			{ T = 0 },
			at(0.2, GUARD, SINK),
			at(0.4, GUARD, SETTLE),
			at(0.55, GUARD, { Joint_LeftArm = { 82, 0, 10 }, Joint_Core = { -8, -12, 0 }, Joint_CorePos = { 0, -0.3, -0.15 } }), -- feint
			at(0.75, GUARD, { Joint_Core = { -10, -4, 14 }, Joint_CorePos = { 0.45, -0.4, 0 }, Joint_Head = { -6, 8, 10 } }), -- slip right
			at(0.95, GUARD, SETTLE),
			at(1.15, GUARD, { Joint_Core = { -10, -12, -14 }, Joint_CorePos = { -0.45, -0.4, 0 }, Joint_Head = { -6, 8, -10 } }), -- slip left
			at(1.35, GUARD, SINK),
			{ T = 1.6 },
		},
	},
	-- REST: hands on the knees catching its breath, straighten up, shake the arms out
	Gym_Rest = {
		Duration = 3.2,
		Keys = {
			{ T = 0 },
			{ T = 0.5, Joint_Core = { -30, 0, 0 }, Joint_CorePos = { 0, -0.6, 0.2 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 28, 0, 4 }, Joint_LeftArm = { 28, 0, -4 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { 14, 0, 0 } },
			{ T = 0.9, Joint_Core = { -34, 0, 0 }, Joint_CorePos = { 0, -0.7, 0.2 }, Joint_Head = { 24, 0, 0 }, Joint_RightArm = { 30, 0, 4 }, Joint_LeftArm = { 30, 0, -4 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { 14, 0, 0 } },
			{ T = 1.3, Joint_Core = { -28, 0, 0 }, Joint_CorePos = { 0, -0.55, 0.2 }, Joint_Head = { 20, 0, 0 }, Joint_RightArm = { 28, 0, 4 }, Joint_LeftArm = { 28, 0, -4 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { 14, 0, 0 } },
			{ T = 1.7, Joint_Core = { -33, 0, 0 }, Joint_CorePos = { 0, -0.68, 0.2 }, Joint_Head = { 24, 0, 0 }, Joint_RightArm = { 30, 0, 4 }, Joint_LeftArm = { 30, 0, -4 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { 14, 0, 0 } },
			{ T = 2.1, Joint_Core = { -6, 0, 0 }, Joint_CorePos = { 0, -0.1, 0 }, Joint_RightArm = { 6, 0, 10 }, Joint_LeftArm = { 6, 0, -10 } },
			{ T = 2.4, Joint_Core = { 0, 10, 4 }, Joint_RightArm = { 10, 0, 22 }, Joint_LeftArm = { 10, 0, -22 }, Joint_Head = { -4, -8, 0 } },
			{ T = 2.7, Joint_Core = { 0, -10, -4 }, Joint_RightArm = { 14, 0, 10 }, Joint_LeftArm = { 14, 0, -10 }, Joint_Head = { -4, 8, 0 } },
			{ T = 3.2 },
		},
	},
}

local POSES = {
	-- Any body (Nightmares, enemies, bosses: everything has Joint_Core; legs / arms / head
	-- are used where they exist). The gym's bag work (GYM above) is merged in below.
	Common = {
		-- Abilities by id ("Ability_<Id>", the server's ActionName). "_Left" = mirrored for a
		-- left-limb source.
		Ability_Bite = BITE,
		Ability_ChargedBite = scaled(BITE, 1.5), -- windup 0.45: the same bite, heavier
		Ability_RustySlash = RUSTY_SLASH,
		Ability_RustySlash_Left = mirrored(RUSTY_SLASH),

		-- GET UP after a knockdown: the server stands the body upright when the ragdoll
		-- ends; this starts it low and folded over, pushing up off its arms, then rising
		-- onto its legs into its stance, instead of popping straight up.
		GetUp = {
			Duration = 1.0,
			Markers = { { 0.35, "StepL" }, { 0.7, "StepR" } },
			Keys = {
				{ T = 0, Joint_CorePos = { 0, -2.2, 0.4 }, Joint_Core = { -58, 0, 8 }, Joint_Head = { 32, 0, 0 }, Joint_RightArm = { 42, 0, 22 }, Joint_LeftArm = { 42, 0, -22 }, Sub_Legs_L = { 85, 0, 0 }, Sub_Legs_R = { 70, 0, 0 } },
				{ T = 0.35, Joint_CorePos = { 0, -1.5, 0.25 }, Joint_Core = { -38, 0, 4 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 26, 0, 16 }, Joint_LeftArm = { 30, 0, -16 }, Sub_Legs_L = { 62, 0, 0 }, Sub_Legs_R = { 70, 0, 0 } },
				{ T = 0.7, Joint_CorePos = { 0, -0.55, 0.05 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 10, 0, 8 }, Joint_LeftArm = { 10, 0, -8 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { 18, 0, 0 } },
				{ T = 1.0 },
			},
		},
	},

	Biped = {
		-- HEAVY HAYMAKER: the Nightmare coils back, sinking and twisting away with the right
		-- arm drawn high behind it, then lunges in off the back leg, the core whipping round
		-- as the arm comes over and down through the target, carries on past, and resets.
		Heavy = {
			Duration = 1.0,
			Markers = { { 0.18, "StepR" }, { 0.36, "Whoosh" }, { 0.45, "Hit" }, { 0.45, "StepL" } },
			Keys = {
				{ T = 0 },
				-- anticipation: sink, lean back, turn away, arm drawn back high
				{ T = 0.18, Joint_CorePos = { 0, -0.45, 0.35 }, Joint_Core = { 12, -28, 4 }, Joint_Head = { -14, 18, 0 }, Joint_RightArm = { 150, 0, 28 }, Joint_LeftArm = { 55, 0, -12 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- acceleration: drive forward, the arm starts to come over
				{ T = 0.36, Joint_CorePos = { 0, -0.25, -0.55 }, Joint_Core = { -10, 10, -2 }, Joint_Head = { -6, -6, 0 }, Joint_RightArm = { 125, 0, 12 }, Joint_LeftArm = { 18, 0, -18 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } },
				-- contact: lunged in, core turned right through, arm down through the target
				{ T = 0.45, Joint_CorePos = { 0, -0.4, -1.0 }, Joint_Core = { -22, 34, -6 }, Joint_Head = { 6, -22, 0 }, Joint_RightArm = { 72, 0, -24 }, Joint_LeftArm = { -28, 0, -24 }, Sub_Legs_L = { 42, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } },
				-- follow-through: the weight carries on, arm down and across
				{ T = 0.6, Joint_CorePos = { 0, -0.48, -1.1 }, Joint_Core = { -26, 44, -6 }, Joint_Head = { 8, -28, 0 }, Joint_RightArm = { 22, 0, -42 }, Joint_LeftArm = { -20, 0, -20 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
				-- recover
				{ T = 0.82, Joint_CorePos = { 0, -0.15, -0.4 }, Joint_Core = { -6, 10, 0 }, Joint_Head = { 0, -6, 0 }, Joint_RightArm = { 12, 0, -6 }, Joint_LeftArm = { 6, 0, -6 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } },
				{ T = 1.0 },
			},
		},
	},
}

for name, def in GYM do
	POSES.Common[name] = def
end

return POSES
