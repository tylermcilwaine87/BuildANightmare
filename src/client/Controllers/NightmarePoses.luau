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
	local out = { Duration = def.Duration, Curve = def.Curve, Keys = {}, Markers = {} }
	for _, key in def.Keys do
		local k = { T = key.T, Ease = key.Ease, Stop = key.Stop }
		for name, v in key do
			if type(v) == "table" then
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
-- A move for a FOUR-LEGGED body (a Common clip is authored on a biped): on a quadruped the
-- head hangs off the front of the body, so its pitch runs the other way (+X tips the snout
-- down); the front legs do what a biped's legs do, the hind legs brace against them.
local function forQuadruped(def)
	local out = { Duration = def.Duration, Curve = def.Curve, Keys = {}, Markers = def.Markers }
	for _, key in def.Keys do
		local k = { T = key.T, Ease = key.Ease, Stop = key.Stop }
		for name, v in key do
			if type(v) ~= "table" then
				continue
			elseif name == "Joint_Head" then
				k[name] = { -v[1], v[2], v[3] }
			elseif name == "Sub_Legs_L" or name == "Sub_Legs_R" then
				local side = name:sub(-1)
				k["Sub_Legs_F" .. side] = v
				k["Sub_Legs_B" .. side] = { -v[1] * 0.5, 0, 0 }
			else
				k[name] = v
			end
		end
		table.insert(out.Keys, k)
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

-- THE BOXER'S GUARD (every standard strike, the autonomous combos, the fighting stance):
-- bladed, chin down, fists by the face, elbows bent (Sub_*Arm_Fore), the feet planted while
-- the hips turn (Joint_Legs counter-turns the core). Keys are this with a few joints changed.
local BOXER = {
	Joint_CorePos = { 0, 0.12, 0 }, Joint_Core = { -6, -10, 0 }, Joint_Legs = { 6, 10, 0 }, Joint_Head = { -10, 10, 0 },
	Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 },
	Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 },
}
-- (the Brutal Boxer's measured punches, reused: lead hook and rear uppercut contact frames)
local B_HOOK_LOAD = { Joint_Core = { -8, 22, 2 }, Joint_Legs = { 8, -22, 0 }, Joint_Head = { -10, -6, 0 }, Joint_LeftArm = { 84, 0, -8 }, Sub_LeftArm_Fore = { 72, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }
local B_HOOK = { Joint_Core = { -8, -35, 4 }, Joint_Legs = { 8, 35, -4 }, Joint_Head = { -10, 14, 0 }, Joint_LeftArm = { 80, 0, 40 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 22, 0, 0 } }
local B_DIP = { Joint_Core = { -14, -22, 0 }, Joint_Legs = { 14, 22, 0 }, Joint_Head = { -12, 8, 0 }, Joint_RightArm = { 38, 0, -42 }, Sub_RightArm_Fore = { 112, 0, 0 }, Joint_LeftArm = { 56, 0, 48 }, Sub_LeftArm_Fore = { 98, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }
local B_UPPER = { Joint_Core = { 2, 28, 0 }, Joint_Legs = { -2, -28, 0 }, Joint_Head = { -6, -10, 0 }, Joint_RightArm = { 60, 0, -45 }, Sub_RightArm_Fore = { 85, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }

local function with(...)
	local out = {}
	for _, part in { ... } do
		for joint, v in part do
			out[joint] = v
		end
	end
	return out
end
-- A key at time t: `base` with `change`'s joints laid over it.
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
-- the guard with these joints changed; a blow landing (fast into it, stopped dead on it)
local function pose(t: number, change)
	return at(t, BOXER, change)
end
local function blow(t: number, change)
	local key = at(t, BOXER, change)
	key.Ease, key.Stop = "Snap", true
	return key
end
-- the punches (contact frames from the Brutal Boxer's pose lab: fist on the centre line at the
-- height of another Nightmare's head)
local P_JAB = { Joint_CorePos = { 0, 0.08, -0.35 }, Joint_Core = { -10, -24, 0 }, Joint_Legs = { 10, 24, 0 }, Joint_Head = { -10, 16, 0 }, Joint_LeftArm = { 100, 0, 22 }, Sub_LeftArm_Fore = { 8, 0, 0 }, Sub_Legs_L = { 22, 0, 0 } }
local P_JAB_BACK = { Joint_CorePos = { 0, 0.13, -0.15 }, Joint_Core = { -8, -4, 0 }, Joint_Legs = { 8, 4, 0 }, Joint_Head = { -10, 6, 0 } }
local P_CROSS_LOAD = { Joint_CorePos = { 0, 0.13, -0.25 }, Joint_Core = { -10, 4, 0 }, Joint_Legs = { 10, -4, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 70, 0, -42 }, Sub_RightArm_Fore = { 70, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }
local P_CROSS = { Joint_CorePos = { 0, 0.22, -0.5 }, Joint_Core = { -12, 30, 0 }, Joint_Legs = { 12, -30, 0 }, Joint_Head = { -12, -12, 0 }, Joint_RightArm = { 100, 0, -22 }, Sub_RightArm_Fore = { 6, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }
local P_HOOK_LOAD = { Joint_CorePos = { 0, 0.15, -0.3 }, Joint_Core = B_HOOK_LOAD.Joint_Core, Joint_Legs = B_HOOK_LOAD.Joint_Legs, Joint_Head = B_HOOK_LOAD.Joint_Head, Joint_LeftArm = B_HOOK_LOAD.Joint_LeftArm, Sub_LeftArm_Fore = B_HOOK_LOAD.Sub_LeftArm_Fore, Sub_Legs_L = B_HOOK_LOAD.Sub_Legs_L, Sub_Legs_R = B_HOOK_LOAD.Sub_Legs_R }
local P_HOOK = { Joint_CorePos = { 0, 0.08, -0.3 }, Joint_Core = B_HOOK.Joint_Core, Joint_Legs = B_HOOK.Joint_Legs, Joint_Head = B_HOOK.Joint_Head, Joint_LeftArm = B_HOOK.Joint_LeftArm, Sub_LeftArm_Fore = B_HOOK.Sub_LeftArm_Fore, Sub_Legs_L = B_HOOK.Sub_Legs_L }
local P_HOOK_FOLLOW = { Joint_CorePos = { 0, 0.05, -0.2 }, Joint_Core = { -12, -42, 4 }, Joint_Legs = { 12, 42, -4 }, Joint_Head = { -10, 20, 0 }, Joint_LeftArm = { 72, 0, 56 }, Sub_LeftArm_Fore = { 80, 0, 0 } }
local P_OVER_LOAD = { Joint_CorePos = { 0, 0.21, 0.1 }, Joint_Core = { 12, -30, 0 }, Joint_Legs = { -12, 30, 0 }, Joint_Head = { -6, 18, 0 }, Joint_RightArm = { 160, 0, 10 }, Sub_RightArm_Fore = { 70, 0, 0 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } }
local P_OVERHAND = { Joint_CorePos = { 0, -0.01, -0.9 }, Joint_Core = { -24, 40, -6 }, Joint_Legs = { 24, -40, 6 }, Joint_Head = { -10, -15, 0 }, Joint_RightArm = { 118, 0, -24 }, Sub_RightArm_Fore = { 14, 0, 0 }, Sub_Legs_L = { 35, 0, 0 }, Sub_Legs_R = { -25, 0, 0 } }
local P_OVER_FOLLOW = { Joint_CorePos = { 0, -0.29, -1.0 }, Joint_Core = { -32, 50, -6 }, Joint_Legs = { 32, -50, 6 }, Joint_Head = { -12, -22, 0 }, Joint_RightArm = { 62, 0, -40 }, Sub_RightArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } }
local P_BODY_LOAD = { Joint_CorePos = { 0.15, -0.22, -0.1 }, Joint_Core = { -16, 18, 8 }, Joint_Legs = { 16, -18, -8 }, Joint_Head = { -6, -8, 0 }, Joint_LeftArm = { 40, 0, 6 }, Sub_LeftArm_Fore = { 95, 0, 0 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }
local P_BODY = { Joint_CorePos = { 0.05, -0.28, -0.45 }, Joint_Core = { -20, -32, 6 }, Joint_Legs = { 20, 32, -6 }, Joint_Head = { -6, 18, 0 }, Joint_LeftArm = { 64, 0, 36 }, Sub_LeftArm_Fore = { 72, 0, 0 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }
local P_UPPER_LOAD = { Joint_CorePos = { 0, 0.02, -0.2 }, Joint_Core = B_DIP.Joint_Core, Joint_Legs = B_DIP.Joint_Legs, Joint_Head = B_DIP.Joint_Head, Joint_RightArm = B_DIP.Joint_RightArm, Sub_RightArm_Fore = B_DIP.Sub_RightArm_Fore, Sub_Legs_L = B_DIP.Sub_Legs_L, Sub_Legs_R = B_DIP.Sub_Legs_R }
local P_UPPER = { Joint_CorePos = { 0, 0.13, -0.35 }, Joint_Core = B_UPPER.Joint_Core, Joint_Legs = B_UPPER.Joint_Legs, Joint_Head = B_UPPER.Joint_Head, Joint_RightArm = B_UPPER.Joint_RightArm, Sub_RightArm_Fore = B_UPPER.Sub_RightArm_Fore, Sub_Legs_L = B_UPPER.Sub_Legs_L, Sub_Legs_R = B_UPPER.Sub_Legs_R }
-- the kicks (+X swings a leg forward, +Z swings the RIGHT leg out to its right): the rear
-- leg, the hip turned over behind it, the hands kept up
local K_TEEP_CHAMBER = { Joint_CorePos = { 0, -0.02, -0.1 }, Joint_Core = { 6, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -12, 0, 0 }, Sub_Legs_R = { 70, 0, -10 }, Sub_Legs_L = { -2, 0, 0 } }
local K_TEEP = { Joint_CorePos = { 0, -0.05, -0.35 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Legs_R = { 95, 0, -18 }, Sub_Legs_L = { -6, 0, 0 } }
local K_ROUND_LOAD = { Joint_CorePos = { 0.1, 0.02, -0.1 }, Joint_Core = { -4, -24, 0 }, Joint_Legs = { 4, 24, 0 }, Joint_Head = { -8, 22, 0 }, Sub_Legs_R = { 35, 0, 50 }, Sub_Legs_L = { 6, 0, 0 } }
local K_ROUND = { Joint_CorePos = { 0, 0.2, -0.2 }, Joint_Core = { 6, 52, 0 }, Joint_Legs = { -6, -16, 0 }, Joint_Head = { -8, -40, 0 }, Joint_RightArm = { -25, 0, 32 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 70, 0, 30 }, Sub_LeftArm_Fore = { 90, 0, 0 }, Sub_Legs_R = { 100, 0, 45 }, Sub_Legs_L = { -4, 0, 0 } }
local K_ROUND_FOLLOW = { Joint_CorePos = { 0, 0.1, -0.15 }, Joint_Core = { 2, 72, 0 }, Joint_Legs = { -2, -30, 0 }, Joint_Head = { -6, -52, 0 }, Joint_RightArm = { 10, 0, 30 }, Sub_RightArm_Fore = { 50, 0, 0 }, Sub_Legs_R = { 70, 0, 10 }, Sub_Legs_L = { 0, 0, 0 } }
local K_LOW = { Joint_CorePos = { 0, 0.05, -0.25 }, Joint_Core = { 8, 44, 0 }, Joint_Legs = { -8, -14, 0 }, Joint_Head = { -14, -30, 0 }, Joint_RightArm = { -10, 0, 30 }, Sub_RightArm_Fore = { 40, 0, 0 }, Sub_Legs_R = { 58, 0, 40 }, Sub_Legs_L = { 2, 0, 0 } }
local K_CLINCH = { Joint_CorePos = { 0, 0.05, -0.4 }, Joint_Core = { -14, 0, 0 }, Joint_Legs = { 8, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 135, 0, -18 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 135, 0, 18 }, Sub_LeftArm_Fore = { 40, 0, 0 } }
local function knee(side: string)
	local r = side == "R"
	return { Joint_CorePos = { 0, 0.15, -0.55 }, Joint_Core = { -18, r and 8 or -8, 0 }, Joint_Legs = { 10, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 125, 0, -16 }, Sub_RightArm_Fore = { 55, 0, 0 }, Joint_LeftArm = { 125, 0, 16 }, Sub_LeftArm_Fore = { 55, 0, 0 },
		Sub_Legs_R = r and { 105, 0, -12 } or { -8, 0, 0 }, Sub_Legs_L = r and { -8, 0, 0 } or { 105, 0, 12 } }
end
local GUARD_REST = { Joint_CorePos = { 0, 0.06, 0.02 } }
-- head movement (-Z leans the body to its right): the head comes off the line, the hips swing
-- under it so the feet stay put, and the hands stay home
local SLIP_R = { Joint_CorePos = { 0.55, -0.1, -0.05 }, Joint_Core = { -12, -2, -15 }, Joint_Legs = { 12, 2, 5 }, Joint_Head = { -12, 8, 9 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }
local SLIP_L = { Joint_CorePos = { -0.55, -0.1, -0.05 }, Joint_Core = { -12, -18, 15 }, Joint_Legs = { 12, 18, -5 }, Joint_Head = { -12, 12, -9 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }
local DIP = { Joint_CorePos = { 0, -0.5, -0.12 }, Joint_Core = { -24, -8, 0 }, Joint_Legs = { 24, 8, 0 }, Joint_Head = { -4, 8, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } }
local PULL = { Joint_CorePos = { 0, 0.1, 0.42 }, Joint_Core = { 9, -8, 0 }, Joint_Legs = { -2, 8, 0 }, Joint_Head = { -18, 8, 0 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } }

local GYM = {
	-- JAB, JAB, CROSS: the double jab walks in behind the lead hand, the second one loads the
	-- rear hip, and the cross comes down the middle with the whole body behind it
	Gym_ComboA = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = { { 0.24, "Whoosh" }, { 0.3, "BagJab" }, { 0.48, "Whoosh" }, { 0.54, "BagJab" }, { 0.72, "Whoosh" }, { 0.8, "BagCross" }, { 0.8, "StepR" } },
		Keys = {
			pose(0),
			pose(0.16),
			blow(0.3, P_JAB),
			pose(0.42, P_JAB_BACK),
			blow(0.54, P_JAB),
			pose(0.68, P_CROSS_LOAD),
			blow(0.8, P_CROSS),
			pose(0.98, { Joint_CorePos = { 0, 0.15, -0.3 }, Joint_Core = { -8, 14, 0 }, Joint_Legs = { 8, -14, 0 } }),
			pose(1.25, GUARD_REST),
			pose(1.6),
		},
	},
	-- JAB, CROSS, LEFT HOOK: the cross turns the hips left, which is exactly what loads the hook
	Gym_ComboB = {
		Duration = 1.8,
		Curve = "Spline",
		Markers = { { 0.24, "Whoosh" }, { 0.3, "BagJab" }, { 0.5, "Whoosh" }, { 0.56, "BagCross" }, { 0.56, "StepR" }, { 0.78, "Whoosh" }, { 0.86, "BagHook" }, { 0.86, "StepL" } },
		Keys = {
			pose(0),
			pose(0.16),
			blow(0.3, P_JAB),
			pose(0.43, P_CROSS_LOAD),
			blow(0.56, P_CROSS),
			pose(0.72, P_HOOK_LOAD),
			blow(0.86, P_HOOK),
			pose(1.0, P_HOOK_FOLLOW),
			pose(1.25, { Joint_CorePos = { 0, 0.1, -0.1 } }),
			pose(1.5, GUARD_REST),
			pose(1.8),
		},
	},
	-- JAB, LEFT HOOK, RIGHT OVERHAND: the hook's follow-through rises straight into the overhand
	Gym_ComboC = {
		Duration = 2.1,
		Curve = "Spline",
		Markers = { { 0.24, "Whoosh" }, { 0.3, "BagJab" }, { 0.5, "Whoosh" }, { 0.58, "BagHook" }, { 0.58, "StepL" }, { 0.94, "Whoosh" }, { 1.04, "BagOverhand" }, { 1.04, "StepL" } },
		Keys = {
			pose(0),
			pose(0.16),
			blow(0.3, P_JAB),
			pose(0.45, P_HOOK_LOAD),
			blow(0.58, P_HOOK),
			pose(0.68, P_HOOK_FOLLOW),
			pose(0.88, P_OVER_LOAD),
			blow(1.04, P_OVERHAND),
			pose(1.22, P_OVER_FOLLOW),
			pose(1.55, { Joint_CorePos = { 0, 0.1, -0.3 } }),
			pose(1.85, GUARD_REST),
			pose(2.1),
		},
	},
	-- level change: dip to the side, a LEFT HOOK INTO THE LIVER, then rip the RIGHT UPPERCUT up
	-- the middle out of the same dip
	Gym_BodyRip = {
		Duration = 1.5,
		Curve = "Spline",
		Markers = { { 0.4, "Whoosh" }, { 0.46, "BagBody" }, { 0.46, "StepL" }, { 0.68, "Whoosh" }, { 0.74, "BagUpper" }, { 0.74, "StepR" } },
		Keys = {
			pose(0),
			pose(0.14),
			pose(0.32, P_BODY_LOAD),
			blow(0.46, P_BODY),
			pose(0.6, P_UPPER_LOAD),
			blow(0.74, P_UPPER),
			pose(0.92, { Joint_CorePos = { 0, 0.15, -0.25 }, Joint_Core = { 0, 16, 0 }, Joint_Legs = { 0, -16, 0 }, Joint_RightArm = { 62, 0, -45 } }),
			pose(1.2, GUARD_REST),
			pose(1.5),
		},
	},
	-- one big RIGHT OVERHAND: a long load, over the top, and everything falls through it
	Gym_Power = {
		Duration = 1.4,
		Curve = "Spline",
		Markers = { { 0.4, "Whoosh" }, { 0.5, "BagOverhand" }, { 0.5, "StepL" } },
		Keys = {
			pose(0),
			pose(0.1),
			pose(0.32, P_OVER_LOAD),
			blow(0.5, P_OVERHAND),
			pose(0.68, P_OVER_FOLLOW),
			pose(1.0, { Joint_CorePos = { 0, 0.1, -0.35 } }),
			pose(1.4),
		},
	},
	-- TEEP: chamber the knee and drive the sole straight through the middle, leaning back off
	-- it, hands still up: a push kick that shoves them away
	Gym_Teep = {
		Duration = 1.3,
		Curve = "Spline",
		Markers = { { 0.3, "Whoosh" }, { 0.42, "BagTeep" }, { 0.56, "StepR" } },
		Keys = {
			pose(0),
			pose(0.14),
			pose(0.3, K_TEEP_CHAMBER),
			blow(0.42, K_TEEP),
			pose(0.56, K_TEEP_CHAMBER),
			pose(0.8, { Joint_CorePos = { 0, 0.1, -0.1 } }),
			pose(1.05, GUARD_REST),
			pose(1.3),
		},
	},
	-- ROUNDHOUSE: step out, turn the hip right over and whip the shin through them, the rear arm
	-- thrown down and back for balance, carrying on through
	Gym_Roundhouse = {
		Duration = 1.5,
		Curve = "Spline",
		Markers = { { 0.32, "StepL" }, { 0.42, "Whoosh" }, { 0.5, "BagRound" } },
		Keys = {
			pose(0),
			pose(0.14),
			pose(0.32, K_ROUND_LOAD),
			blow(0.5, K_ROUND),
			pose(0.66, K_ROUND_FOLLOW),
			pose(0.92, { Joint_CorePos = { 0, 0.1, -0.1 }, Joint_Core = { -4, 14, 0 }, Joint_Legs = { 4, -14, 0 } }),
			pose(1.2, GUARD_REST),
			pose(1.5),
		},
	},
	-- CLINCH KNEES: hands locked behind the neck, hauling down into each knee, right, left, right
	Gym_KneeClinch = {
		Duration = 1.8,
		Curve = "Spline",
		Markers = { { 0.2, "Clinch" }, { 0.5, "BagKnee" }, { 0.95, "BagKnee" }, { 1.35, "BagKnee" }, { 0.5, "StepL" }, { 0.95, "StepR" }, { 1.35, "StepL" } },
		Keys = {
			pose(0),
			pose(0.2, K_CLINCH),
			pose(0.36, with(K_CLINCH, { Joint_Core = { -8, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } })),
			blow(0.5, knee("R")),
			pose(0.68, K_CLINCH),
			pose(0.82, with(K_CLINCH, { Joint_Core = { -8, 0, 0 }, Sub_Legs_L = { -24, 0, 0 } })),
			blow(0.95, knee("L")),
			pose(1.1, K_CLINCH),
			pose(1.24, with(K_CLINCH, { Joint_Core = { -8, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } })),
			blow(1.35, knee("R")),
			pose(1.52, K_CLINCH),
			pose(1.8),
		},
	},
	-- SPINNING BACK KICK: step across and turn the back on them, eyes over the shoulder, then drive
	-- the heel straight back through them and come round out of the spin, hands up again
	Gym_SpinBackKick = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = { { 0.15, "StepR" }, { 0.5, "Whoosh" }, { 0.56, "BagSpin" }, { 0.95, "StepL" } },
		Keys = {
			pose(0),
			pose(0.12),
			pose(0.3, { Joint_Core = { 0, -90, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { 0, 70, 0 }, Sub_Legs_R = { 30, 0, 0 }, Joint_CorePos = { 0, -0.05, 0 } }),
			pose(0.44, { Joint_Core = { 15, -180, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { 0, 80, 0 }, Sub_Legs_R = { 20, 0, 0 }, Joint_CorePos = { 0, 0.15, -0.2 } }),
			blow(0.56, { Joint_Core = { 35, -180, 0 }, Joint_Legs = { 0, 0, 0 }, Sub_Legs_R = { -100, 0, 0 }, Sub_Legs_L = { 6, 0, 0 }, Joint_CorePos = { 0, 0.3, -0.4 }, Joint_Head = { -10, 80, 0 }, Joint_RightArm = { 40, 0, 60 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 40, 0, -60 }, Sub_LeftArm_Fore = { 30, 0, 0 } }),
			pose(0.72, { Joint_Core = { 15, -200, 0 }, Joint_Legs = { 0, 0, 0 }, Sub_Legs_R = { -30, 0, 0 }, Joint_CorePos = { 0, 0.1, -0.3 }, Joint_Head = { 0, 60, 0 } }),
			pose(0.98, { Joint_Core = { 0, -300, 0 }, Joint_Legs = { 0, 0, 0 }, Sub_Legs_R = { 10, 0, 0 } }),
			pose(1.25, { Joint_Core = { -6, -368, 0 }, Joint_Legs = { 6, 8, 0 } }),
			pose(1.6, { Joint_Core = { -6, -370, 0 } }),
		},
	},
	-- JAB, CROSS, LOW KICK: the punches draw the hands up, then the rear shin chops the lead leg
	Gym_OneTwoLow = {
		Duration = 1.7,
		Curve = "Spline",
		Markers = { { 0.2, "Whoosh" }, { 0.26, "Strike" }, { 0.42, "Whoosh" }, { 0.5, "Strike" }, { 0.5, "StepR" }, { 0.72, "StepL" }, { 0.8, "Whoosh" }, { 0.88, "Strike" } },
		Keys = {
			pose(0),
			pose(0.14),
			blow(0.26, P_JAB),
			pose(0.38, P_CROSS_LOAD),
			blow(0.5, P_CROSS),
			pose(0.72, K_ROUND_LOAD),
			blow(0.88, K_LOW),
			pose(1.06, { Joint_CorePos = { 0, 0.1, -0.1 }, Joint_Core = { 2, 34, 0 }, Joint_Legs = { -2, -18, 0 }, Sub_Legs_R = { 18, 0, 20 } }),
			pose(1.38, GUARD_REST),
			pose(1.7),
		},
	},
	-- LIVER, THEN HEAD: the same left hand twice: dip and dig it in under the ribs, then up over
	-- the top onto the jaw they just dropped their guard from
	Gym_LiverHead = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = { { 0.32, "Whoosh" }, { 0.4, "Strike" }, { 0.4, "StepL" }, { 0.62, "Whoosh" }, { 0.72, "Strike" } },
		Keys = {
			pose(0),
			pose(0.14),
			pose(0.28, P_BODY_LOAD),
			blow(0.4, P_BODY),
			pose(0.56, P_HOOK_LOAD),
			blow(0.72, P_HOOK),
			pose(0.88, P_HOOK_FOLLOW),
			pose(1.25, GUARD_REST),
			pose(1.6),
		},
	},
	-- FOOTWORK: bounce in the stance, a feint with the jab, a slip each way under a shot, reset
	Gym_Bounce = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = { { 0.2, "StepL" }, { 0.6, "StepR" }, { 1.0, "StepL" } },
		Keys = {
			pose(0),
			pose(0.2, { Joint_CorePos = { 0, 0, 0 } }),
			pose(0.38, { Joint_CorePos = { 0, 0.18, 0.05 } }),
			pose(0.55, { Joint_LeftArm = { 84, 0, 30 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Joint_Core = { -10, -18, 0 }, Joint_Legs = { 10, 18, 0 }, Joint_CorePos = { 0, 0.08, -0.2 } }), -- feint
			pose(0.75, { Joint_Core = { -14, -6, -14 }, Joint_Legs = { 14, 6, 5 }, Joint_CorePos = { 0.5, -0.05, 0 }, Joint_Head = { -14, 10, 10 } }), -- slip right
			pose(0.95, { Joint_CorePos = { 0, 0.15, 0.05 } }),
			pose(1.15, { Joint_Core = { -14, -14, 14 }, Joint_Legs = { 14, 14, -5 }, Joint_CorePos = { -0.5, -0.05, 0 }, Joint_Head = { -14, 10, -10 } }), -- slip left
			pose(1.35, { Joint_CorePos = { 0, 0.02, 0 } }),
			pose(1.6),
		},
	},
	-- DEFENCE DRILLS: the head moves first, and the punches come out of where it went.
	-- SLIP, SLIP, then the CROSS and HOOK off the second one
	Gym_SlipCounter = {
		Duration = 1.9,
		Curve = "Spline",
		Markers = { { 0.2, "StepR" }, { 0.6, "StepL" }, { 0.84, "Whoosh" }, { 0.92, "BagCross" }, { 0.92, "StepR" }, { 1.14, "Whoosh" }, { 1.22, "BagHook" }, { 1.22, "StepL" } },
		Keys = {
			pose(0),
			pose(0.2, SLIP_R),
			pose(0.4),
			pose(0.6, SLIP_L),
			pose(0.78, P_CROSS_LOAD),
			blow(0.92, P_CROSS),
			pose(1.08, P_HOOK_LOAD),
			blow(1.22, P_HOOK),
			pose(1.4, P_HOOK_FOLLOW),
			pose(1.62, GUARD_REST),
			pose(1.9),
		},
	},
	-- ROLL under a hook, come up loaded on the far side: LEFT HOOK, RIGHT OVERHAND
	Gym_RollHook = {
		Duration = 2,
		Curve = "Spline",
		Markers = { { 0.22, "StepL" }, { 0.68, "StepR" }, { 0.9, "Whoosh" }, { 0.96, "BagHook" }, { 0.96, "StepL" }, { 1.22, "Whoosh" }, { 1.3, "BagOverhand" }, { 1.3, "StepL" } },
		Keys = {
			pose(0),
			pose(0.22, SLIP_L),
			pose(0.46, DIP),
			pose(0.68, SLIP_R),
			pose(0.82, P_HOOK_LOAD),
			blow(0.96, P_HOOK),
			pose(1.12, P_OVER_LOAD),
			blow(1.3, P_OVERHAND),
			pose(1.48, P_OVER_FOLLOW),
			pose(1.75, GUARD_REST),
			pose(2),
		},
	},
	-- JAB, lean back from the answer on the back foot, and fire the CROSS as it comes forward
	Gym_PullCounter = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = { { 0.22, "Whoosh" }, { 0.28, "BagJab" }, { 0.5, "StepR" }, { 0.72, "Whoosh" }, { 0.8, "BagCross" }, { 0.8, "StepR" } },
		Keys = {
			pose(0),
			pose(0.14),
			blow(0.28, P_JAB),
			pose(0.5, PULL),
			pose(0.66, P_CROSS_LOAD),
			blow(0.8, P_CROSS),
			pose(1, { Joint_CorePos = { 0, 0.15, -0.3 }, Joint_Core = { -8, 14, 0 }, Joint_Legs = { 8, -14, 0 } }),
			pose(1.3, GUARD_REST),
			pose(1.6),
		},
	},
	-- DUCK low, drive up out of the legs: RIGHT UPPERCUT, LEFT HOOK
	Gym_DuckUpper = {
		Duration = 1.7,
		Curve = "Spline",
		Markers = { { 0.24, "StepL" }, { 0.6, "Whoosh" }, { 0.66, "BagUpper" }, { 0.66, "StepR" }, { 0.92, "Whoosh" }, { 0.98, "BagHook" }, { 0.98, "StepL" } },
		Keys = {
			pose(0),
			pose(0.24, DIP),
			pose(0.5, P_UPPER_LOAD),
			blow(0.66, P_UPPER),
			pose(0.84, P_HOOK_LOAD),
			blow(0.98, P_HOOK),
			pose(1.16, P_HOOK_FOLLOW),
			pose(1.44, GUARD_REST),
			pose(1.7),
		},
	},
	-- NOTHING BUT MOVEMENT (any body): slip, slip, a full weave under, lean back, a feint, reset
	Gym_Weave = {
		Duration = 2.4,
		Curve = "Spline",
		Markers = { { 0.2, "StepL" }, { 0.56, "StepR" }, { 1.26, "StepL" }, { 1.56, "StepR" } },
		Keys = {
			pose(0),
			pose(0.2, SLIP_L),
			pose(0.38),
			pose(0.56, SLIP_R),
			pose(0.82, DIP),
			pose(1.06, SLIP_L),
			pose(1.26),
			pose(1.56, PULL),
			pose(1.74),
			pose(1.92, { Joint_LeftArm = { 84, 0, 30 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Joint_Core = { -10, -18, 0 }, Joint_Legs = { 10, 18, 0 }, Joint_CorePos = { 0, 0.08, -0.2 } }),
			pose(2.14, GUARD_REST),
			pose(2.4),
		},
	},
	-- what the fighting brain does when it reads a shot coming (NightmareAIService:React): the
	-- feet carry it out of range, and the head goes first
	Slip_R = {
		Duration = 0.5,
		Curve = "Spline",
		Markers = { { 0.2, "StepR" } },
		Keys = { pose(0), pose(0.17, SLIP_R), pose(0.34, { Joint_CorePos = { 0.2, 0.02, 0 } }), pose(0.5) },
	},
	Slip_L = {
		Duration = 0.5,
		Curve = "Spline",
		Markers = { { 0.2, "StepL" } },
		Keys = { pose(0), pose(0.17, SLIP_L), pose(0.34, { Joint_CorePos = { -0.2, 0.02, 0 } }), pose(0.5) },
	},
	RollUnder = {
		Duration = 0.72,
		Curve = "Spline",
		Markers = { { 0.5, "StepL" } },
		Keys = { pose(0), pose(0.14, SLIP_R), pose(0.32, DIP), pose(0.5, SLIP_L), pose(0.72) },
	},
	PullBack = {
		Duration = 0.55,
		Curve = "Spline",
		Markers = { { 0.2, "StepR" } },
		Keys = { pose(0), pose(0.18, PULL), pose(0.38, { Joint_CorePos = { 0, 0.1, 0.12 } }), pose(0.55) },
	},
	-- THE GUARD BREAKS (BlockService.BrokenTime, any body): arms knocked wide, the head snapping
	-- back, it reels with nothing up, the legs give, and it hauls itself back together
	Guard_Crumble = {
		Duration = 1.3,
		Curve = "Spline",
		Markers = { { 0.32, "StepR" }, { 0.68, "Land" } },
		Keys = {
			pose(0),
			{ T = 0.09, Ease = "Snap", Joint_CorePos = { 0, 0.1, 0.55 }, Joint_Core = { 16, 0, 0 }, Joint_Legs = { -10, 0, 0 }, Joint_Head = { -24, 0, 0 }, Joint_RightArm = { 18, 0, -74 }, Sub_RightArm_Fore = { 22, 0, 0 }, Joint_LeftArm = { 18, 0, 74 }, Sub_LeftArm_Fore = { 22, 0, 0 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 0.32, Joint_CorePos = { 0.15, -0.15, 0.8 }, Joint_Core = { 8, -10, 6 }, Joint_Legs = { 0, 10, -4 }, Joint_Head = { -12, 12, 0 }, Joint_RightArm = { 4, 0, -46 }, Sub_RightArm_Fore = { 34, 0, 0 }, Joint_LeftArm = { 8, 0, 42 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { -20, 0, 0 }, Sub_Legs_R = { 18, 0, 0 } },
			{ T = 0.68, Joint_CorePos = { 0, -0.75, 0.55 }, Joint_Core = { -34, 4, -3 }, Joint_Legs = { 30, -4, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 14, 0, -16 }, Sub_RightArm_Fore = { 50, 0, 0 }, Joint_LeftArm = { 18, 0, 14 }, Sub_LeftArm_Fore = { 54, 0, 0 }, Sub_Legs_L = { 46, 0, 0 }, Sub_Legs_R = { -38, 0, 0 } },
			{ T = 1.02, Joint_CorePos = { 0, -0.25, 0.2 }, Joint_Core = { -16, -6, 0 }, Joint_Legs = { 14, 6, 0 }, Joint_Head = { -6, 6, 0 }, Joint_RightArm = { 36, 0, -36 }, Sub_RightArm_Fore = { 84, 0, 0 }, Joint_LeftArm = { 40, 0, 34 }, Sub_LeftArm_Fore = { 80, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			pose(1.3),
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

-- BEAST MOVES (Config.Nightmare.Moveset: four-legged, armless, tailed bodies). No "Hit"
-- marker: like the gym strings they play at 1 / the AttackSpeed scale, the server landing
-- each hit at its time. Four legs: Sub_Legs_FL / FR / BL / BR (+X swings a leg forward).
-- The server slides the body onto the target during a leap (Leap), so the keys only carry
-- the height and the body's shape, not the distance.
local BEAST = {
	-- POUNCE: sink low on coiled hind legs, eyes up on them; spring, front paws reaching,
	-- jaws wide; land ON them nose-down; maul (two savage shakes) and tear loose.
	Beast_Pounce = {
		Duration = 1.5,
		Markers = { { 0.3, "StepL" }, { 0.32, "Whoosh" }, { 0.58, "Land" }, { 0.58, "JawSnap" }, { 0.82, "Grind" }, { 1.0, "Rip" } },
		Keys = {
			{ T = 0 },
			{ T = 0.28, Joint_CorePos = { 0, -0.12, 0.45 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { 16, 0, 0 }, Sub_Head_Jaw = { -8, 0, 0 }, Sub_Legs_FL = { -22, 0, 0 }, Sub_Legs_FR = { -22, 0, 0 }, Sub_Legs_BL = { 34, 0, 0 }, Sub_Legs_BR = { 34, 0, 0 }, Joint_Tail = { 0, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { 30, 0, 0 } },
			{ T = 0.45, Joint_CorePos = { 0, 1.5, -0.3 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Head_Jaw = { -48, 0, 0 }, Sub_Legs_FL = { 72, 0, 0 }, Sub_Legs_FR = { 72, 0, 0 }, Sub_Legs_BL = { -52, 0, 0 }, Sub_Legs_BR = { -52, 0, 0 }, Sub_Legs_L = { -30, 0, 0 }, Sub_Legs_R = { -30, 0, 0 }, Joint_RightArm = { 120, 0, 20 }, Joint_LeftArm = { 120, 0, -20 } },
			{ T = 0.58, Joint_CorePos = { 0, 0.15, -0.6 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { -22, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 42, 0, 0 }, Sub_Legs_FR = { 42, 0, 0 }, Sub_Legs_BL = { -12, 0, 0 }, Sub_Legs_BR = { -12, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -10, 0, 0 }, Joint_RightArm = { 80, 0, 10 }, Joint_LeftArm = { 80, 0, -10 } },
			-- maul: head and shoulders wrenching side to side, jaw clamping
			{ T = 0.72, Joint_CorePos = { 0, 0.1, -0.6 }, Joint_Core = { -16, 12, 6 }, Joint_Head = { -30, 26, 8 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 34, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 } },
			{ T = 0.82, Joint_CorePos = { 0, 0.1, -0.6 }, Joint_Core = { -18, -14, -6 }, Joint_Head = { -34, -28, -8 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 34, 0, 0 } },
			-- tear loose: rip the head up and away, hopping back off them
			{ T = 1.02, Joint_CorePos = { 0, 0.1, 0.1 }, Joint_Core = { 10, 24, 0 }, Joint_Head = { 18, 36, 6 }, Sub_Head_Jaw = { -26, 0, 0 }, Sub_Legs_FL = { 20, 0, 0 }, Sub_Legs_FR = { 20, 0, 0 }, Sub_Legs_BL = { -10, 0, 0 }, Sub_Legs_BR = { -10, 0, 0 } },
			{ T = 1.25, Joint_Core = { 2, 8, 0 }, Joint_Head = { 4, 10, 0 }, Sub_Head_Jaw = { -6, 0, 0 } },
			{ T = 1.5 },
		},
	},
	-- ROLLING CHARGE: tuck everything in and curl into a ball, then roll forward twice right
	-- into them (one whole turn per hit), and uncurl back onto its feet.
	Beast_Roll = {
		Duration = 1.4,
		Markers = { { 0.28, "Whoosh" }, { 0.5, "StepL" }, { 0.68, "StepR" }, { 1.05, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.24, Joint_CorePos = { 0, -0.1, 0.2 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { -40, 0, 0 }, Sub_Legs_FL = { -60, 0, 0 }, Sub_Legs_FR = { -60, 0, 0 }, Sub_Legs_BL = { 60, 0, 0 }, Sub_Legs_BR = { 60, 0, 0 }, Sub_Legs_L = { 80, 0, 0 }, Sub_Legs_R = { 80, 0, 0 }, Joint_RightArm = { 60, 0, -30 }, Joint_LeftArm = { 60, 0, 30 }, Joint_Tail = { 0, 0, 0 } },
			-- (rolling high, a bouncing ball: the long body turning about its middle would
			-- sweep through the floor)
			{ T = 0.5, Joint_CorePos = { 0, 1.2, 0 }, Joint_Core = { -210, 0, 0 }, Joint_Head = { -40, 0, 0 }, Sub_Legs_FL = { -60, 0, 0 }, Sub_Legs_FR = { -60, 0, 0 }, Sub_Legs_BL = { 60, 0, 0 }, Sub_Legs_BR = { 60, 0, 0 }, Sub_Legs_L = { 80, 0, 0 }, Sub_Legs_R = { 80, 0, 0 }, Joint_RightArm = { 60, 0, -30 }, Joint_LeftArm = { 60, 0, 30 } },
			{ T = 0.68, Joint_CorePos = { 0, 0.5, 0 }, Joint_Core = { -390, 0, 0 }, Joint_Head = { -40, 0, 0 }, Sub_Legs_FL = { -60, 0, 0 }, Sub_Legs_FR = { -60, 0, 0 }, Sub_Legs_BL = { 60, 0, 0 }, Sub_Legs_BR = { 60, 0, 0 }, Sub_Legs_L = { 80, 0, 0 }, Sub_Legs_R = { 80, 0, 0 }, Joint_RightArm = { 60, 0, -30 }, Joint_LeftArm = { 60, 0, 30 } },
			-- uncurl onto its feet, shaking it off
			{ T = 1.05, Joint_CorePos = { 0, 0, 0 }, Joint_Core = { -366, 0, 4 }, Joint_Head = { 6, 0, 0 }, Sub_Legs_FL = { 10, 0, 0 }, Sub_Legs_FR = { 10, 0, 0 }, Sub_Legs_BL = { -6, 0, 0 }, Sub_Legs_BR = { -6, 0, 0 } },
			{ T = 1.4, Joint_Core = { -360, 0, 0 } },
		},
	},
	-- TAIL WHIP: wind the body one way, then spin hard the other way, the whole body coming
	-- round a full turn so the tail scythes through them at the front, and settle facing them.
	Beast_TailWhip = {
		Duration = 1.2,
		Markers = { { 0.24, "StepL" }, { 0.4, "Whoosh" }, { 0.52, "StepR" }, { 0.9, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.24, Joint_CorePos = { 0, -0.05, 0 }, Joint_Core = { 0, 40, 0 }, Joint_Head = { -6, -30, 0 }, Joint_Tail = { 0, -40, 0 } },
			{ T = 0.52, Joint_CorePos = { 0, 0, 0 }, Joint_Core = { 0, -180, 0 }, Joint_Head = { -6, 40, 0 }, Joint_Tail = { 0, 34, 0 } },
			{ T = 0.75, Joint_CorePos = { 0, 0, 0 }, Joint_Core = { 0, -300, 0 }, Joint_Head = { -4, 30, 0 }, Joint_Tail = { 0, 40, 0 } },
			{ T = 0.95, Joint_CorePos = { 0, -0.1, 0 }, Joint_Core = { 0, -360, 0 }, Joint_Head = { 0, 6, 0 }, Joint_Tail = { 0, 10, 0 } },
			{ T = 1.2, Joint_Core = { 0, -360, 0 } },
		},
	},
	-- HEADBUTT: rear back with the head pulled up, then drive the whole body forward behind the
	-- skull and slam it into them.
	Beast_Headbutt = {
		Duration = 1.0,
		Markers = { { 0.2, "StepL" }, { 0.32, "Whoosh" }, { 0.4, "StepR" } },
		Keys = {
			{ T = 0 },
			{ T = 0.22, Joint_CorePos = { 0, 0.15, 0.45 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 26, 0, 0 }, Joint_RightArm = { 30, 0, 20 }, Joint_LeftArm = { 30, 0, -20 }, Sub_Legs_FL = { -14, 0, 0 }, Sub_Legs_FR = { -14, 0, 0 }, Sub_Legs_BL = { 18, 0, 0 }, Sub_Legs_BR = { 18, 0, 0 } },
			{ T = 0.4, Joint_CorePos = { 0, 0.1, -0.9 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -38, 0, 0 }, Joint_RightArm = { -20, 0, 20 }, Joint_LeftArm = { -20, 0, -20 }, Sub_Legs_FL = { 26, 0, 0 }, Sub_Legs_FR = { 26, 0, 0 }, Sub_Legs_BL = { -24, 0, 0 }, Sub_Legs_BR = { -24, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.56, Joint_CorePos = { 0, 0.05, -0.8 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -22, 0, 0 } },
			{ T = 0.8, Joint_CorePos = { 0, -0.1, -0.2 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { 2, 0, 0 } },
			{ T = 1.0 },
		},
	},
}

-- ABILITIES ("Ability_<Id>", AbilityDefinitions): each its own move, performed by the limb it
-- comes from (arm abilities authored for the RIGHT arm; "_Left" = mirrored; a four-legged
-- body plays its own variant, forQuadruped). The "Hit" marker sits on the ability's Windup
-- (the frame the server lands it); Duration = AbilityDefinitions.Length. They flow through
-- their keys (Curve "Spline"; PoseCurve), with Stop keys on the impacts.
-- Their effects and sounds are cued by markers (AbilityEffects): "FX_<name>" an effect at
-- the limb doing it, "SFX_<sound>" a sound there (AudioDefinitions).

-- A deterministic wobble in -1..1 (the same every time the clip plays).
local function wobble(i: number, salt: number): number
	return math.sin(i * 12.9898 + salt * 78.233) * 0.5 + math.sin(i * 4.1 + salt * 1.7) * 0.5
end

-- Electrocution: from t0 to t1 every `step` seconds, a jolt about `pose` (a key table
-- without T) - small random twitches of the core, head and arms, the jaw grinding - and at
-- each of `spasms` a full-body spasm (thrown stiff and upright for a moment).
local function convulse(keys, pose, t0: number, t1: number, step: number, spasms)
	local i = 0
	local t = t0
	while t <= t1 + 1e-6 do
		i += 1
		local key = table.clone(pose)
		key.T = t
		key.Ease = "Linear"
		local spasm = false
		for _, s in spasms do
			if math.abs(t - s) < step / 2 then
				spasm = true
			end
		end
		local core, head = pose.Joint_Core, pose.Joint_Head
		if spasm then
			key.Joint_Core = { core[1] + 10, core[2], core[3] + 4 * wobble(i, 1) }
			key.Joint_Head = { head[1] + 16, head[2] + 8 * wobble(i, 2), head[3] }
			key.Joint_RightArm = { 55, 0, 34 }
			key.Joint_LeftArm = { 55, 0, -34 }
			key.Sub_Head_Jaw = { -8, 0, 0 }
		else
			key.Joint_Core = { core[1] + 3 * wobble(i, 3), core[2] + 4 * wobble(i, 4), core[3] + 3 * wobble(i, 5) }
			key.Joint_Head = { head[1] + 4 * wobble(i, 6), head[2] + 6 * wobble(i, 7), head[3] + 4 * wobble(i, 8) }
			key.Joint_RightArm = { 78 + 6 * wobble(i, 9), 0, 6 + 5 * wobble(i, 10) }
			key.Joint_LeftArm = { 78 + 6 * wobble(i, 11), 0, -6 + 5 * wobble(i, 12) }
			key.Sub_Head_Jaw = { -2 + 3 * wobble(i, 13), 0, 0 }
		end
		table.insert(keys, key)
		t += step
	end
end

-- A building shake (the reactor straining): from t0 to t1, jolts about `pose` growing from
-- `from` to `to` degrees.
local function strain(keys, pose, t0: number, t1: number, step: number, from: number, to: number)
	local i = 0
	local t = t0
	while t <= t1 + 1e-6 do
		i += 1
		local k = (t - t0) / math.max(t1 - t0, 0.01)
		local amp = from + (to - from) * k
		local key = table.clone(pose)
		key.T = t
		key.Ease = "Linear"
		local core, head = pose.Joint_Core, pose.Joint_Head
		key.Joint_Core = { core[1] + amp * wobble(i, 21), core[2] + amp * wobble(i, 22), core[3] + amp * 1.2 * wobble(i, 23) }
		key.Joint_Head = { head[1] + amp * wobble(i, 24), head[2] + amp * 1.4 * wobble(i, 25), head[3] }
		key.Joint_CorePos = { 0.04 * amp * wobble(i, 26), pose.Joint_CorePos[2], 0.04 * amp * wobble(i, 27) }
		table.insert(keys, key)
		t += step
	end
end

local CHARGED_BITE
do
	-- CHARGED BITE (Electric Jaw): rear back with the jaw cracking open, arcs crawling over
	-- it; lunge and SNAP (0.45, Hit). Locked on, the victim CONVULSES in the jaws (the
	-- server jolts it in step: Clamp.Style "Convulse"), three shocks running through it
	-- (0.8, 1.15, 1.5: full-body spasms), then the jaws DISCHARGE (1.85): head whipped up,
	-- arms flung wide, the victim blasted straight away.
	local held = { Joint_CorePos = { 0, -0.38, -1.0 }, Joint_Core = { -24, 0, 0 }, Joint_Head = { -14, 0, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }
	local keys = {
		{ T = 0 },
		{ T = 0.2, Joint_CorePos = { 0, -0.25, 0.3 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 18, 0, 0 }, Sub_Head_Jaw = { -22, 0, 0 }, Joint_RightArm = { 30, 0, 14 }, Joint_LeftArm = { 30, 0, -14 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
		{ T = 0.36, Ease = "Out", Joint_CorePos = { 0, -0.25, -0.8 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { -4, 0, 0 }, Sub_Head_Jaw = { -70, 0, 0 }, Joint_RightArm = { 72, 0, 24 }, Joint_LeftArm = { 72, 0, -24 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } },
		{ T = 0.45, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.35, -1.05 }, Joint_Core = { -26, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Joint_RightArm = { 80, 0, 6 }, Joint_LeftArm = { 80, 0, -6 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
	}
	convulse(keys, held, 0.5, 1.72, 0.055, { 0.8, 1.15, 1.5 })
	table.insert(keys, { T = 1.78, Joint_CorePos = { 0, -0.45, -0.85 }, Joint_Core = { -22, 0, 0 }, Joint_Head = { -20, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Joint_RightArm = { 70, 0, 4 }, Joint_LeftArm = { 70, 0, -4 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } })
	table.insert(keys, { T = 1.85, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.1, 0.15 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 30, 0, 0 }, Sub_Head_Jaw = { -55, 0, 0 }, Joint_RightArm = { 40, 0, 55 }, Joint_LeftArm = { 40, 0, -55 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -2, 0, 0 } })
	table.insert(keys, { T = 2.05, Joint_Core = { 4, 0, 0 }, Joint_Head = { 10, 0, 0 }, Sub_Head_Jaw = { -20, 0, 0 }, Joint_RightArm = { 16, 0, 20 }, Joint_LeftArm = { 16, 0, -20 } })
	table.insert(keys, { T = 2.45 })
	CHARGED_BITE = {
		Duration = 2.45,
		Curve = "Spline",
		Markers = {
			{ 0, "SFX_ElectricCharge" }, { 0.05, "FX_JawArcs" }, { 0.25, "FX_JawArcs" }, { 0.25, "SFX_ElectricArc" },
			{ 0.36, "Whoosh" }, { 0.45, "Hit" }, { 0.45, "JawSnap" }, { 0.45, "FX_ShockSnap" }, { 0.45, "StepL" },
			{ 0.8, "FX_Zap" }, { 0.8, "Grind" }, { 1.15, "FX_Zap" }, { 1.15, "Grind" }, { 1.5, "FX_Zap" }, { 1.5, "Grind" },
			{ 1.85, "FX_Discharge" }, { 1.85, "SFX_LightningCrack" }, { 1.85, "StepR" },
		},
		Keys = keys,
	}
end

local ABILITY = {
	Ability_ChargedBite = CHARGED_BITE,

	-- FROST RAM (head): head down, horns first, paw the ice twice snorting frost (0.12, 0.3),
	-- coil back on the haunches, and CHARGE (0.55, Hit: the server drives the body 14 studs
	-- over 0.45 s, goring the first thing it runs into and carrying it on the horns),
	-- galloping flat out bent low behind the skull; at 1.0 the head TOSSES up (the gored body
	-- goes up and over) and it skids to a stop, ice spraying off its feet.
	Ability_FrostRam = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = {
			{ 0.02, "SFX_FrostSnort" }, { 0.02, "FX_FrostBreath" }, { 0.12, "StepL" }, { 0.12, "FX_FrostScrape" }, { 0.12, "SFX_IceCrack" },
			{ 0.3, "StepL" }, { 0.3, "FX_FrostScrape" }, { 0.38, "SFX_FrostSnort" }, { 0.38, "FX_FrostBreath" }, { 0.48, "SFX_BeastRoar" },
			{ 0.55, "Hit" }, { 0.55, "Whoosh" }, { 0.55, "FX_FrostAura" }, { 0.68, "StepL" }, { 0.8, "StepR" }, { 0.92, "StepL" },
			{ 1.0, "FX_HornToss" }, { 1.0, "SFX_BigWhoosh" }, { 1.05, "FX_IceSkid" }, { 1.05, "SFX_Skid" }, { 1.35, "StepR" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.06, Joint_CorePos = { 0, -0.2, 0.25 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -26, 0, 0 }, Joint_RightArm = { -15, 0, 14 }, Joint_LeftArm = { -15, 0, -14 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } },
			{ T = 0.12, Ease = "Snap", Joint_CorePos = { 0, -0.25, 0.2 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { -18, 0, 14 }, Joint_LeftArm = { -18, 0, -14 }, Sub_Legs_L = { -28, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 0.21, Joint_CorePos = { 0, -0.22, 0.25 }, Joint_Core = { -15, 0, 0 }, Joint_Head = { -28, 0, 0 }, Joint_RightArm = { -16, 0, 14 }, Joint_LeftArm = { -16, 0, -14 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } },
			{ T = 0.3, Ease = "Snap", Joint_CorePos = { 0, -0.27, 0.2 }, Joint_Core = { -17, 0, 0 }, Joint_Head = { -32, 0, 0 }, Joint_RightArm = { -20, 0, 14 }, Joint_LeftArm = { -20, 0, -14 }, Sub_Legs_L = { -32, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 0.42, Stop = true, Joint_CorePos = { 0, -0.45, 0.45 }, Joint_Core = { -24, 0, 0 }, Joint_Head = { -36, 0, 0 }, Joint_RightArm = { -35, 0, 12 }, Joint_LeftArm = { -35, 0, -12 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
			{ T = 0.55, Ease = "Snap", Joint_CorePos = { 0, -0.3, -0.6 }, Joint_Core = { -34, 0, 0 }, Joint_Head = { -42, 0, 0 }, Joint_RightArm = { -55, 0, 10 }, Joint_LeftArm = { -55, 0, -10 }, Sub_Legs_L = { 44, 0, 0 }, Sub_Legs_R = { -36, 0, 0 } },
			{ T = 0.68, Joint_CorePos = { 0, -0.22, -0.7 }, Joint_Core = { -31, 0, 2 }, Joint_Head = { -40, 0, 0 }, Joint_RightArm = { -50, 0, 10 }, Joint_LeftArm = { -50, 0, -10 }, Sub_Legs_L = { -30, 0, 0 }, Sub_Legs_R = { 40, 0, 0 } },
			{ T = 0.8, Joint_CorePos = { 0, -0.4, -0.7 }, Joint_Core = { -36, 0, -2 }, Joint_Head = { -42, 0, 0 }, Joint_RightArm = { -55, 0, 10 }, Joint_LeftArm = { -55, 0, -10 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 0.92, Joint_CorePos = { 0, -0.22, -0.7 }, Joint_Core = { -31, 0, 2 }, Joint_Head = { -40, 0, 0 }, Joint_RightArm = { -50, 0, 10 }, Joint_LeftArm = { -50, 0, -10 }, Sub_Legs_L = { -30, 0, 0 }, Sub_Legs_R = { 40, 0, 0 } },
			{ T = 1.0, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.1, -0.4 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 34, 0, 0 }, Joint_RightArm = { 20, 0, 30 }, Joint_LeftArm = { 20, 0, -30 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 1.12, Joint_CorePos = { 0, -0.45, -0.2 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 6, 0, 0 }, Joint_RightArm = { 10, 0, 24 }, Joint_LeftArm = { 10, 0, -24 }, Sub_Legs_L = { 48, 0, 0 }, Sub_Legs_R = { 20, 0, 0 } },
			{ T = 1.35, Joint_CorePos = { 0, -0.15, 0 }, Joint_Core = { 2, 0, 0 }, Joint_RightArm = { 6, 0, 10 }, Joint_LeftArm = { 6, 0, -10 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 1.6 },
		},
	},
	-- VISOR GLARE (head, Scrap Visor): brace with the hands up as the visor charges white-hot,
	-- the head rocking back; then it snaps level and GLARES (0.55, Hit): a beam pours out of
	-- the visor for four ticks while the head sweeps it left, right, left, the body leaning
	-- into the recoil; it gutters out and the canister vents steam (1.38).
	Ability_ScrapVisorBeam = {
		Duration = 1.8,
		Curve = "Spline",
		Markers = {
			{ 0, "SFX_LaserCharge" }, { 0.02, "FX_VisorCharge" }, { 0.5, "SFX_Laser" }, { 0.55, "Hit" }, { 0.55, "FX_VisorBeam" }, { 0.55, "StepR" },
			{ 1.38, "FX_Vent" }, { 1.38, "SFX_SteamHiss" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.25, Joint_CorePos = { 0, -0.2, 0.2 }, Joint_Core = { 8, 0, 0 }, Joint_Head = { 20, 0, 0 }, Joint_RightArm = { 34, 0, 26 }, Joint_LeftArm = { 34, 0, -26 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
			{ T = 0.45, Joint_CorePos = { 0, -0.22, 0.2 }, Joint_Core = { 4, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 30, 0, 30 }, Joint_LeftArm = { 30, 0, -30 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			{ T = 0.55, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.25, 0.15 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 20, 0, 34 }, Joint_LeftArm = { 20, 0, -34 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.75, Joint_CorePos = { 0, -0.25, 0.18 }, Joint_Core = { 6, 6, 0 }, Joint_Legs = { 0, -6, 0 }, Joint_Head = { -8, 14, 0 }, Joint_RightArm = { 20, 0, 34 }, Joint_LeftArm = { 20, 0, -34 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.95, Joint_CorePos = { 0, -0.25, 0.2 }, Joint_Core = { 6, -6, 0 }, Joint_Legs = { 0, 6, 0 }, Joint_Head = { -8, -14, 0 }, Joint_RightArm = { 20, 0, 34 }, Joint_LeftArm = { 20, 0, -34 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 1.15, Joint_CorePos = { 0, -0.25, 0.22 }, Joint_Core = { 6, 4, 0 }, Joint_Legs = { 0, -4, 0 }, Joint_Head = { -8, 10, 0 }, Joint_RightArm = { 22, 0, 32 }, Joint_LeftArm = { 22, 0, -32 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 1.35, Joint_CorePos = { 0, -0.2, 0.1 }, Joint_Core = { 2, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 16, 0, 20 }, Joint_LeftArm = { 16, 0, -20 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
			{ T = 1.5, Joint_CorePos = { 0, -0.1, 0.05 }, Joint_Core = { 0, 0, 4 }, Joint_Head = { -6, 0, 12 }, Joint_RightArm = { 10, 0, 12 }, Joint_LeftArm = { 10, 0, -12 } },
			{ T = 1.8 },
		},
	},
	-- RUSTY SLASH (arm): coil away with the claw drawn back out wide, unwind and RAKE across
	-- through them (0.3, Hit), carry it round and fold the claw up, then BACKHAND it back the
	-- other way (0.62, Hit) stepping in, the claw trailing sparks.
	Ability_RustySlash = {
		Duration = 0.9,
		Curve = "Spline",
		Markers = {
			{ 0.1, "StepR" }, { 0.14, "FX_TrailOn" }, { 0.16, "Whoosh" }, { 0.16, "SFX_Servo" }, { 0.3, "Hit" },
			{ 0.44, "FX_TrailOff" }, { 0.47, "StepL" }, { 0.48, "FX_TrailOn" }, { 0.5, "Whoosh" }, { 0.62, "Hit" }, { 0.62, "SFX_ClawSlash" }, { 0.76, "FX_TrailOff" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.14, Joint_CorePos = { 0.15, -0.22, 0.15 }, Joint_Core = { 4, -32, 0 }, Joint_Legs = { 0, 26, 0 }, Joint_Head = { 0, 26, 0 }, Joint_RightArm = { 40, 0, 72 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 42, 0, -12 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
			{ T = 0.3, Ease = "In", Joint_CorePos = { -0.1, -0.28, -0.55 }, Joint_Core = { -10, 22, 0 }, Joint_Legs = { 0, -18, 0 }, Joint_Head = { -6, -14, 0 }, Joint_RightArm = { 95, 0, -20 }, Sub_RightArm_Fore = { 5, 0, 0 }, Joint_LeftArm = { 12, 0, -22 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 0.44, Joint_CorePos = { -0.15, -0.3, -0.6 }, Joint_Core = { -12, 40, 0 }, Joint_Legs = { 0, -32, 0 }, Joint_Head = { -6, -26, 0 }, Joint_RightArm = { 80, 0, -70 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { -10, 0, -26 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 0.62, Ease = "In", Joint_CorePos = { 0.1, -0.3, -0.75 }, Joint_Core = { -14, -24, 0 }, Joint_Legs = { 0, 20, 0 }, Joint_Head = { -8, 20, 0 }, Joint_RightArm = { 100, 0, 55 }, Sub_RightArm_Fore = { -5, 0, 0 }, Joint_LeftArm = { 30, 0, -10 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
			{ T = 0.76, Joint_CorePos = { 0.12, -0.25, -0.6 }, Joint_Core = { -10, -34, 0 }, Joint_Legs = { 0, 26, 0 }, Joint_Head = { -6, 24, 0 }, Joint_RightArm = { 70, 0, 75 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 20, 0, -10 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.9 },
		},
	},
	-- TENTACLE LASH (arm): coil it high behind, then crack it out to its full length (0.45,
	-- Hit: the crack at the tip), the end lagging behind the arm like a whip; what it caught
	-- is hauled in (to 0.7), hoisted high over the head (1.0) and SMASHED down into the floor
	-- (1.2) - the server carries the victim along the same path (Wrap).
	Ability_TentacleLash = {
		Duration = 1.7,
		Curve = "Spline",
		Markers = {
			{ 0.05, "SFX_TentacleSlime" }, { 0.25, "Whoosh" }, { 0.45, "Hit" }, { 0.45, "FX_WhipCrack" }, { 0.45, "SFX_WhipCrack" },
			{ 0.5, "SFX_TentacleSlime" }, { 0.62, "StepR" }, { 0.85, "SFX_BigWhoosh" }, { 1.2, "FX_Stomp" }, { 1.2, "SFX_BodySlam" }, { 1.2, "Land" }, { 1.25, "SFX_BoneCrack" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.22, Joint_CorePos = { 0, -0.15, 0.3 }, Joint_Core = { 8, -22, 0 }, Joint_Legs = { 0, 18, 0 }, Joint_Head = { -6, 18, 0 }, Joint_RightArm = { 160, 0, 30 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 40, 0, -20 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
			{ T = 0.36, Joint_CorePos = { 0, -0.18, -0.1 }, Joint_Core = { -4, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -6, 4, 0 }, Joint_RightArm = { 120, 0, 10 }, Sub_RightArm_Fore = { 90, 0, 0 }, Joint_LeftArm = { 30, 0, -22 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			{ T = 0.45, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.2, -0.5 }, Joint_Core = { -14, 16, 0 }, Joint_Legs = { 0, -12, 0 }, Joint_Head = { -6, -10, 0 }, Joint_RightArm = { 92, 0, -4 }, Sub_RightArm_Fore = { -15, 0, 0 }, Joint_LeftArm = { 20, 0, -24 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
			{ T = 0.7, Ease = "Out", Joint_CorePos = { 0, -0.25, 0.35 }, Joint_Core = { 14, -10, 0 }, Joint_Legs = { 0, 8, 0 }, Joint_Head = { 4, 6, 0 }, Joint_RightArm = { 70, 0, -10 }, Sub_RightArm_Fore = { 80, 0, 0 }, Joint_LeftArm = { 30, 0, -20 }, Sub_Legs_L = { -6, 0, 0 }, Sub_Legs_R = { 22, 0, 0 } },
			{ T = 1.0, Joint_CorePos = { 0, 0.05, 0.1 }, Joint_Core = { 16, -6, 0 }, Joint_Legs = { 0, 4, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 170, 0, -5 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 50, 0, -30 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 1.2, Ease = "In", Stop = true, Joint_CorePos = { 0, -0.45, -0.6 }, Joint_Core = { -30, -10, 0 }, Joint_Legs = { 0, 8, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 60, 0, -30 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 20, 0, -30 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } },
			{ T = 1.45, Joint_CorePos = { 0, -0.35, -0.45 }, Joint_Core = { -24, -8, 0 }, Joint_Legs = { 0, 6, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 50, 0, -25 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 20, 0, -26 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
			{ T = 1.7 },
		},
	},
	-- DEMON REND (arm): the blades IGNITE; rear up with the claw raised high behind the head,
	-- rend DOWN across through them (0.5, Hit), whip it back up and rend down the other way
	-- (0.72, Hit) - an X of fire - then drop low with the claw drawn back and RIP UPWARD
	-- through them (1.02, Hit), the body uncoiling after it, throwing them up in a burst.
	Ability_DemonRend = {
		Duration = 1.5,
		Curve = "Spline",
		Markers = {
			{ 0, "FX_Ignite" }, { 0, "SFX_FireIgnite" }, { 0.2, "StepR" }, { 0.36, "FX_TrailOn" }, { 0.4, "SFX_FireWhoosh" }, { 0.5, "Hit" }, { 0.5, "FX_RendA" },
			{ 0.62, "SFX_FireWhoosh" }, { 0.72, "Hit" }, { 0.72, "FX_RendB" }, { 0.72, "StepL" }, { 0.86, "SFX_BeastRoar" }, { 0.94, "Whoosh" },
			{ 1.02, "Hit" }, { 1.02, "FX_RendUp" }, { 1.02, "FX_FireBurst" }, { 1.02, "SFX_FireIgnite" }, { 1.2, "FX_TrailOff" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.3, Joint_CorePos = { 0, 0.1, 0.3 }, Joint_Core = { 14, -20, 0 }, Joint_Legs = { 0, 16, 0 }, Joint_Head = { 10, 14, 0 }, Joint_RightArm = { 170, 0, 20 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 60, 0, -30 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
			{ T = 0.5, Ease = "In", Joint_CorePos = { 0, -0.35, -0.8 }, Joint_Core = { -26, 28, 0 }, Joint_Legs = { 0, -22, 0 }, Joint_Head = { -10, -10, 0 }, Joint_RightArm = { 50, 0, -35 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 30, 0, -20 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } },
			{ T = 0.6, Joint_CorePos = { 0, -0.25, -0.75 }, Joint_Core = { -14, 30, 0 }, Joint_Legs = { 0, -24, 0 }, Joint_Head = { -6, -12, 0 }, Joint_RightArm = { 120, 0, -55 }, Sub_RightArm_Fore = { 50, 0, 0 }, Joint_LeftArm = { 30, 0, -24 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } },
			{ T = 0.72, Ease = "In", Joint_CorePos = { 0, -0.4, -0.9 }, Joint_Core = { -24, -20, 0 }, Joint_Legs = { 0, 16, 0 }, Joint_Head = { -8, 12, 0 }, Joint_RightArm = { 50, 0, 40 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 30, 0, -16 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } },
			{ T = 0.88, Stop = true, Joint_CorePos = { 0, -0.6, -0.7 }, Joint_Core = { -30, -10, 0 }, Joint_Legs = { 0, 8, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { -30, 0, 15 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 40, 0, -30 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 1.02, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0.1, -0.9 }, Joint_Core = { 12, 10, 0 }, Joint_Legs = { 0, -8, 0 }, Joint_Head = { 18, -6, 0 }, Joint_RightArm = { 175, 0, 10 }, Sub_RightArm_Fore = { -10, 0, 0 }, Joint_LeftArm = { 20, 0, -40 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 1.2, Joint_CorePos = { 0, 0.05, -0.8 }, Joint_Core = { 10, 8, 0 }, Joint_Legs = { 0, -6, 0 }, Joint_Head = { 14, -4, 0 }, Joint_RightArm = { 165, 0, 14 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 20, 0, -36 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } },
			{ T = 1.5 },
		},
	},
	-- MAGNET PULL (arm): thrust the magnet out flat at them, braced, humming and shaking as it
	-- LOCKS on (0.4, Hit); heave back, reeling them in along the floor (the server drags them
	-- in by 0.85), catch them in the claw, swing them up over the head (1.03) and SLAM them
	-- down in front (1.15).
	Ability_MagnetPull = {
		Duration = 1.6,
		Curve = "Spline",
		Markers = {
			{ 0, "SFX_Servo" }, { 0.05, "FX_MagnetCharge" }, { 0.2, "SFX_MagnetHum" }, { 0.4, "Hit" }, { 0.4, "SFX_Hydraulic" }, { 0.4, "StepR" },
			{ 0.62, "StepR" }, { 0.85, "SFX_MetalClang" }, { 0.95, "SFX_BigWhoosh" }, { 1.15, "SFX_BodySlam" }, { 1.15, "Land" }, { 1.15, "FX_Stomp" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.25, Joint_CorePos = { 0, -0.2, -0.2 }, Joint_Core = { -6, 10, 0 }, Joint_Legs = { 0, -8, 0 }, Joint_Head = { -6, -6, 0 }, Joint_RightArm = { 95, 0, 0 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 30, 0, -24 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.32, Ease = "Linear", Joint_CorePos = { 0, -0.2, -0.2 }, Joint_Core = { -6, 10, 2 }, Joint_Legs = { 0, -8, 0 }, Joint_Head = { -6, -6, 0 }, Joint_RightArm = { 97, 0, 3 }, Joint_LeftArm = { 30, 0, -24 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.36, Ease = "Linear", Joint_CorePos = { 0, -0.2, -0.2 }, Joint_Core = { -6, 10, -2 }, Joint_Legs = { 0, -8, 0 }, Joint_Head = { -6, -6, 0 }, Joint_RightArm = { 93, 0, -3 }, Joint_LeftArm = { 30, 0, -24 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.4, Stop = true, Joint_CorePos = { 0, -0.22, -0.2 }, Joint_Core = { -6, 10, 0 }, Joint_Legs = { 0, -8, 0 }, Joint_Head = { -6, -6, 0 }, Joint_RightArm = { 96, 0, 0 }, Joint_LeftArm = { 30, 0, -24 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.62, Joint_CorePos = { 0, -0.3, 0.35 }, Joint_Core = { 14, -12, 0 }, Joint_Legs = { 0, 10, 0 }, Joint_Head = { 6, 8, 0 }, Joint_RightArm = { 70, 0, 8 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 10, 0, -30 }, Sub_Legs_L = { -14, 0, 0 }, Sub_Legs_R = { 18, 0, 0 } },
			{ T = 0.85, Stop = true, Joint_CorePos = { 0, -0.25, 0 }, Joint_Core = { -4, -6, 0 }, Joint_Legs = { 0, 4, 0 }, Joint_Head = { -4, 0, 0 }, Joint_RightArm = { 80, 0, -6 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 30, 0, -24 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 1.03, Joint_CorePos = { 0, 0.05, 0.15 }, Joint_Core = { 16, -4, 0 }, Joint_Head = { 20, 0, 0 }, Joint_RightArm = { 175, 0, -4 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 60, 0, -30 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 1.15, Ease = "In", Stop = true, Joint_CorePos = { 0, -0.45, -0.55 }, Joint_Core = { -30, 4, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 55, 0, -6 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 30, 0, -20 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } },
			{ T = 1.35, Joint_CorePos = { 0, -0.35, -0.4 }, Joint_Core = { -22, 2, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 48, 0, -4 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 24, 0, -20 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 1.6 },
		},
	},
	-- HAMMER SLAM (arm): dip and swing the hammer under, then HEAVE it up overhead rising onto
	-- the toes, hang there, and bring it down into the floor with everything (0.8, Hit), the
	-- body folding over it; it's stuck - the body shudders, wrenches back - and tears it free
	-- in an AFTERSHOCK (1.25).
	Ability_HammerSlam = {
		Duration = 1.7,
		Curve = "Spline",
		Markers = {
			{ 0.1, "StepR" }, { 0.15, "SFX_Servo" }, { 0.3, "FX_HammerGlow" }, { 0.45, "SFX_PowerUp" }, { 0.55, "StepL" }, { 0.66, "Whoosh" }, { 0.66, "SFX_BigWhoosh" },
			{ 0.8, "Hit" }, { 0.8, "Land" }, { 0.8, "SFX_HammerClang" }, { 0.8, "FX_GroundCrack" }, { 0.82, "SFX_RockDebris" },
			{ 1.12, "SFX_Hydraulic" }, { 1.25, "SFX_Shockwave" }, { 1.25, "FX_GroundCrack" }, { 1.25, "StepR" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.3, Joint_CorePos = { 0, -0.35, 0.2 }, Joint_Core = { -10, -20, 0 }, Joint_Legs = { 0, 16, 0 }, Joint_Head = { -6, 10, 0 }, Joint_RightArm = { -30, 0, 20 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 20, 0, -10 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
			{ T = 0.55, Joint_CorePos = { 0, 0.35, 0.3 }, Joint_Core = { 18, -10, 0 }, Joint_Legs = { 0, 8, 0 }, Joint_Head = { 16, 6, 0 }, Joint_RightArm = { 185, 0, 6 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 130, 0, -20 }, Sub_Legs_L = { 4, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } },
			{ T = 0.66, Ease = "Out", Joint_CorePos = { 0, 0.45, 0.25 }, Joint_Core = { 22, -6, 0 }, Joint_Legs = { 0, 4, 0 }, Joint_Head = { 18, 4, 0 }, Joint_RightArm = { 195, 0, 4 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 140, 0, -18 }, Sub_Legs_L = { 2, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 0.8, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.55, -0.7 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 35, 0, 0 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 25, 0, -12 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 0.88, Ease = "Linear", Joint_CorePos = { 0, -0.55, -0.7 }, Joint_Core = { -36, 0, 2 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 36, 0, 0 }, Joint_LeftArm = { 25, 0, -12 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 0.96, Ease = "Linear", Joint_CorePos = { 0, -0.55, -0.7 }, Joint_Core = { -37, 0, -2 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 35, 0, 0 }, Joint_LeftArm = { 25, 0, -12 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 1.04, Ease = "Linear", Joint_CorePos = { 0, -0.55, -0.7 }, Joint_Core = { -36, 0, 2 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 36, 0, 0 }, Joint_LeftArm = { 25, 0, -12 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 1.18, Joint_CorePos = { 0, -0.3, 0.1 }, Joint_Core = { 6, 8, 0 }, Joint_Head = { 4, 0, 0 }, Joint_RightArm = { 60, 0, 10 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 20, 0, -16 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 1.25, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.4, -0.2 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 45, 0, 8 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 20, 0, -14 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			{ T = 1.45, Joint_CorePos = { 0, -0.15, -0.1 }, Joint_Core = { -4, 0, 0 }, Joint_RightArm = { 25, 0, 10 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 12, 0, -10 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 1.7 },
		},
	},
	-- BAT DIVE (wings): two hard flaps lift it (0.1, 0.2), it screeches and DIVES (the server
	-- flies it in an arc onto them, 0.2 - 0.45) with the wings swept back and the claws
	-- reaching, RAKES them as it lands on them (0.45, Hit), and kicks off backwards with the
	-- wings spread, landing at 0.7.
	Ability_BatDive = {
		Duration = 0.85,
		Curve = "Spline",
		Markers = {
			{ 0.04, "SFX_WingFlap" }, { 0.1, "FX_WingGust" }, { 0.14, "SFX_WingFlap" }, { 0.2, "FX_WingGust" }, { 0.2, "SFX_BatScreech" }, { 0.22, "FX_Ghosts" },
			{ 0.45, "Hit" }, { 0.45, "SFX_ClawSlash" }, { 0.52, "SFX_WingFlap" }, { 0.7, "Land" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.04, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { 4, 0, 0 }, Sub_Back_R = { 0, 0, 55 }, Sub_Back_L = { 0, 0, -55 }, Joint_RightArm = { 20, 0, 20 }, Joint_LeftArm = { 20, 0, -20 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { 6, 0, 0 } },
			{ T = 0.1, Ease = "Snap", Joint_CorePos = { 0, 0.5, 0 }, Joint_Core = { -8, 0, 0 }, Sub_Back_R = { 0, 0, -30 }, Sub_Back_L = { 0, 0, 30 }, Joint_RightArm = { 30, 0, 20 }, Joint_LeftArm = { 30, 0, -20 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { 20, 0, 0 } },
			{ T = 0.14, Joint_CorePos = { 0, 0.6, 0.05 }, Joint_Core = { -10, 0, 0 }, Sub_Back_R = { 0, 0, 55 }, Sub_Back_L = { 0, 0, -55 }, Joint_RightArm = { 40, 0, 24 }, Joint_LeftArm = { 40, 0, -24 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { 30, 0, 0 } },
			{ T = 0.2, Ease = "Snap", Joint_CorePos = { 0, 0.9, 0.1 }, Joint_Core = { -15, 0, 0 }, Joint_Head = { 6, 0, 0 }, Sub_Back_R = { 0, 0, -35 }, Sub_Back_L = { 0, 0, 35 }, Joint_RightArm = { 60, 0, 30 }, Joint_LeftArm = { 60, 0, -30 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { 40, 0, 0 } },
			{ T = 0.32, Joint_CorePos = { 0, 0.4, -0.6 }, Joint_Core = { -45, 0, 0 }, Joint_Head = { 25, 0, 0 }, Sub_Back_R = { 0, -40, -10 }, Sub_Back_L = { 0, 40, 10 }, Joint_RightArm = { 120, 0, 10 }, Joint_LeftArm = { 120, 0, -10 }, Sub_Legs_L = { -30, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 0.45, Ease = "In", Stop = true, Joint_CorePos = { 0, 0.1, -0.8 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { 10, 0, 0 }, Sub_Back_R = { 0, 0, 30 }, Sub_Back_L = { 0, 0, -30 }, Joint_RightArm = { 40, 0, -20 }, Joint_LeftArm = { 40, 0, 20 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
			{ T = 0.58, Joint_CorePos = { 0, 0.6, 0.2 }, Joint_Core = { 25, 0, 0 }, Joint_Head = { 10, 0, 0 }, Sub_Back_R = { 0, 0, 50 }, Sub_Back_L = { 0, 0, -50 }, Joint_RightArm = { 30, 0, 40 }, Joint_LeftArm = { 30, 0, -40 }, Sub_Legs_L = { 60, 0, 0 }, Sub_Legs_R = { 40, 0, 0 } },
			{ T = 0.7, Ease = "Out", Stop = true, Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -6, 0, 0 }, Sub_Back_R = { 0, 0, 10 }, Sub_Back_L = { 0, 0, -10 }, Joint_RightArm = { 16, 0, 20 }, Joint_LeftArm = { 16, 0, -20 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
			{ T = 0.85 },
		},
	},
	-- BLINK DASH (wings, Void Wings): wrap the wings round the body and crouch as the void
	-- gathers into it, VANISH (0.3) and come out 20 studs on (0.35, Hit) stretched low with
	-- the wings snapping open, skid, and look back over the shoulder as the tear left behind
	-- splits open and cuts everything on it (0.6).
	Ability_BlinkDash = {
		Duration = 0.8,
		Curve = "Spline",
		Markers = {
			{ 0, "FX_VoidGather" }, { 0, "SFX_VoidWhoosh" }, { 0.3, "FX_Vanish" }, { 0.35, "Hit" }, { 0.35, "SFX_Teleport" }, { 0.36, "FX_Appear" },
			{ 0.36, "Land" }, { 0.6, "SFX_GlassShatter" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.25, Joint_CorePos = { 0, -0.4, 0.2 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -20, 0, 0 }, Joint_RightArm = { 60, 0, -50 }, Joint_LeftArm = { 60, 0, 50 }, Sub_Back_R = { 0, -70, 0 }, Sub_Back_L = { 0, 70, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { 20, 0, 0 } },
			{ T = 0.33, Stop = true, Joint_CorePos = { 0, -0.45, 0.25 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 62, 0, -52 }, Joint_LeftArm = { 62, 0, 52 }, Sub_Back_R = { 0, -75, 0 }, Sub_Back_L = { 0, 75, 0 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { 22, 0, 0 } },
			{ T = 0.36, Ease = "Hold", Joint_CorePos = { 0, -0.3, -0.6 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { -50, 0, 20 }, Joint_LeftArm = { -50, 0, -20 }, Sub_Back_R = { 0, 20, 40 }, Sub_Back_L = { 0, -20, -40 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -36, 0, 0 } },
			{ T = 0.5, Joint_CorePos = { 0, -0.35, -0.3 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 4, 0, 0 }, Joint_RightArm = { 30, 0, 40 }, Joint_LeftArm = { 30, 0, -40 }, Sub_Back_R = { 0, 0, 25 }, Sub_Back_L = { 0, 0, -25 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
			{ T = 0.6, Joint_CorePos = { 0, -0.25, -0.2 }, Joint_Core = { 0, -25, 0 }, Joint_Legs = { 0, 25, 0 }, Joint_Head = { 0, -40, 0 }, Joint_RightArm = { 20, 0, 30 }, Joint_LeftArm = { 20, 0, -30 }, Sub_Back_R = { 0, 0, 20 }, Sub_Back_L = { 0, 0, -20 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 0.8 },
		},
	},
	-- TAIL SWEEP (tail): crouch and coil the other way, then spin round TWICE low to the
	-- floor, the tail out flat lagging behind the body and sweeping the legs out from under
	-- everything around (0.35, Hit), and come up out of it.
	Ability_TailSweep = {
		Duration = 0.9,
		Markers = {
			{ 0.08, "StepL" }, { 0.2, "SFX_BigWhoosh" }, { 0.3, "FX_SweepRing" }, { 0.35, "Hit" }, { 0.35, "Whoosh" }, { 0.55, "SFX_BigWhoosh" }, { 0.55, "StepR" }, { 0.75, "Land" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.15, Joint_CorePos = { 0, -0.5, 0 }, Joint_Core = { -8, 50, 0 }, Joint_Tail = { 0, -50, 10 }, Joint_Head = { 0, -30, 0 }, Joint_RightArm = { 40, 0, 40 }, Joint_LeftArm = { 40, 0, -40 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.35, Ease = "In", Joint_CorePos = { 0, -0.6, 0 }, Joint_Core = { -10, -250, 0 }, Joint_Tail = { 12, 45, -10 }, Joint_Head = { 0, 40, 0 }, Joint_RightArm = { 60, 0, 70 }, Joint_LeftArm = { 60, 0, -70 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
			{ T = 0.55, Ease = "Linear", Joint_CorePos = { 0, -0.6, 0 }, Joint_Core = { -10, -520, 0 }, Joint_Tail = { 12, 40, -10 }, Joint_Head = { 0, 40, 0 }, Joint_RightArm = { 60, 0, 70 }, Joint_LeftArm = { 60, 0, -70 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
			{ T = 0.75, Ease = "Out", Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -4, -720, 0 }, Joint_Tail = { 0, 10, 0 }, Joint_Head = { 0, 10, 0 }, Joint_RightArm = { 30, 0, 30 }, Joint_LeftArm = { 30, 0, -30 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
			{ T = 0.9, Joint_Core = { 0, -720, 0 } },
		},
	},
	-- REINFORCED GUARD (core): draw both fists back and BANG them together in front (0.15,
	-- sparks), lift a knee and STOMP down into a crossed-arm stance (0.35, Hit) as the plates
	-- lock round the body.
	Ability_ReinforcedGuard = {
		Duration = 0.75,
		Curve = "Spline",
		Markers = {
			{ 0.15, "SFX_MetalClang" }, { 0.15, "FX_Sparks" }, { 0.28, "SFX_Hydraulic" }, { 0.35, "Hit" }, { 0.35, "FX_PlateLock" }, { 0.35, "SFX_ArmorClank" }, { 0.35, "Land" }, { 0.35, "FX_Stomp" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.1, Joint_CorePos = { 0, 0, 0.1 }, Joint_Core = { 6, 0, 0 }, Joint_RightArm = { 50, 0, 30 }, Sub_RightArm_Fore = { 90, 0, 0 }, Joint_LeftArm = { 50, 0, -30 }, Sub_LeftArm_Fore = { 90, 0, 0 } },
			{ T = 0.15, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.05, -0.1 }, Joint_Core = { -6, 0, 0 }, Joint_RightArm = { 85, 0, -38 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 85, 0, 38 }, Sub_LeftArm_Fore = { 40, 0, 0 } },
			{ T = 0.26, Joint_CorePos = { 0, 0.25, 0 }, Joint_Core = { 2, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 84, 0, -40 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 84, 0, 40 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 0.35, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.35, 0 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 84, 0, -44 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 84, 0, 44 }, Sub_LeftArm_Fore = { 70, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			{ T = 0.5, Joint_CorePos = { 0, -0.32, 0 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 84, 0, -44 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 84, 0, 44 }, Sub_LeftArm_Fore = { 70, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			{ T = 0.75 },
		},
	},
	-- CRYSTAL BARRIER (core): sweep both arms up overhead, head back, then SLAM the palms
	-- down at the floor (0.45, Hit) - crystals erupt in a ring round it - and rise with the
	-- arms spread wide.
	Ability_CrystalBarrier = {
		Duration = 0.9,
		Curve = "Spline",
		Markers = { { 0.05, "SFX_CrystalHum" }, { 0.3, "Whoosh" }, { 0.45, "Hit" }, { 0.45, "FX_CrystalRing" }, { 0.45, "SFX_GlassShatter" }, { 0.45, "Land" }, { 0.52, "SFX_CrystalChime" } },
		Keys = {
			{ T = 0 },
			{ T = 0.25, Joint_CorePos = { 0, 0.2, 0 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 16, 0, 0 }, Joint_RightArm = { 170, 0, 25 }, Joint_LeftArm = { 170, 0, -25 } },
			{ T = 0.45, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.55, -0.2 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 40, 0, 25 }, Joint_LeftArm = { 40, 0, -25 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.62, Joint_CorePos = { 0, -0.1, 0 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 100, 0, 60 }, Joint_LeftArm = { 100, 0, -60 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
			{ T = 0.9 },
		},
	},

	-- SHOP EXCLUSIVES ----------------------------------------------------------------
	-- METEOR FIST (arm, Inferno Gauntlet): the fist IGNITES; sink deep with it drawn back,
	-- spring up (the server flies the body from 0.26: an arc onto the target) with the fist
	-- raised straight up trailing fire, tuck at the top, then come down FIST FIRST into the
	-- floor on the Hit frame (0.85, the landing), folded over it, and wrench it out of the
	-- crater.
	Ability_MeteorFist = {
		Duration = 1.55,
		Curve = "Spline",
		Markers = {
			{ 0.03, "FX_FistIgnite" }, { 0.03, "SFX_FireIgnite" }, { 0.1, "StepL" }, { 0.26, "FX_TrailOn" }, { 0.28, "Whoosh" }, { 0.28, "SFX_BigWhoosh" },
			{ 0.72, "SFX_FireWhoosh" }, { 0.85, "Hit" }, { 0.85, "Land" }, { 0.85, "SFX_Explosion" }, { 0.9, "FX_TrailOff" }, { 1.25, "SFX_Sizzle" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.22, Stop = true, Joint_CorePos = { 0, -0.55, 0.25 }, Joint_Core = { -14, -12, 0 }, Joint_Head = { -8, 8, 0 }, Joint_RightArm = { 140, 0, 30 }, Joint_LeftArm = { 40, 0, -30 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { 30, 0, 0 } },
			{ T = 0.32, Ease = "Snap", Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 175, 0, 8 }, Joint_LeftArm = { 60, 0, -40 }, Sub_Legs_L = { -22, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } },
			{ T = 0.6, Joint_CorePos = { 0, 0.2, 0 }, Joint_Core = { 8, 0, 0 }, Joint_Head = { 6, 0, 0 }, Joint_RightArm = { 172, 0, 6 }, Joint_LeftArm = { 70, 0, -40 }, Sub_Legs_L = { 45, 0, 0 }, Sub_Legs_R = { 38, 0, 0 } },
			-- (measured on the hit frame: the fist's knuckles on the floor 2.0 studs ahead of the
			-- body, the feet at their normal stance: AbilityDefinitions MeteorFist FistAhead)
			{ T = 0.85, Ease = "In", Stop = true, Joint_CorePos = { 0, -1.07, -1.0 }, Joint_Core = { -60, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 75, 0, 2 }, Joint_LeftArm = { 18, 0, -34 }, Sub_Legs_L = { 55, 0, 0 }, Sub_Legs_R = { -15, 0, 0 } },
			{ T = 1.1, Stop = true, Joint_CorePos = { 0, -1.07, -1.0 }, Joint_Core = { -58, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 75, 0, 2 }, Joint_LeftArm = { 20, 0, -34 }, Sub_Legs_L = { 55, 0, 0 }, Sub_Legs_R = { -15, 0, 0 } },
			{ T = 1.32, Joint_CorePos = { 0, -0.2, -0.25 }, Joint_Core = { -8, 6, 0 }, Joint_RightArm = { 30, 0, 12 }, Joint_LeftArm = { 14, 0, -14 } },
			{ T = 1.55 },
		},
	},
	-- DRAGON BREATH (head, Dragon Skull): DRAW BREATH - rear back, head thrown up, the air
	-- sucked into the jaws - then thrust the head forward with the jaw WIDE on the Hit frame
	-- and pour fire for the five ticks (0.5 - 1.5), sweeping it left and right across them,
	-- braced; then the jaw shuts and smoke curls out of the nostrils.
	Ability_DragonBreath = {
		Duration = 1.9,
		Curve = "Spline",
		Markers = {
			{ 0.05, "FX_Inhale" }, { 0.05, "SFX_BeastInhale" }, { 0.38, "Whoosh" }, { 0.46, "SFX_BeastRoar" }, { 0.5, "Hit" },
			{ 1.6, "FX_SmokeSnort" }, { 1.6, "SFX_SteamHiss" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.38, Joint_CorePos = { 0, -0.1, 0.35 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 28, 0, 0 }, Sub_Head_Jaw = { -10, 0, 0 }, Joint_RightArm = { 30, 0, 25 }, Joint_LeftArm = { 30, 0, -25 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
			{ T = 0.5, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.2, -0.45 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -12, 0, 0 }, Sub_Head_Jaw = { -36, 0, 0 }, Joint_RightArm = { -15, 0, 25 }, Joint_LeftArm = { -15, 0, -25 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 0.75, Joint_CorePos = { 0, -0.2, -0.45 }, Joint_Core = { -14, 10, 0 }, Joint_Legs = { 0, -8, 0 }, Joint_Head = { -12, 12, 0 }, Sub_Head_Jaw = { -38, 0, 0 }, Joint_RightArm = { -15, 0, 25 }, Joint_LeftArm = { -15, 0, -25 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 1.05, Joint_CorePos = { 0, -0.2, -0.45 }, Joint_Core = { -14, -10, 0 }, Joint_Legs = { 0, 8, 0 }, Joint_Head = { -12, -12, 0 }, Sub_Head_Jaw = { -38, 0, 0 }, Joint_RightArm = { -15, 0, 25 }, Joint_LeftArm = { -15, 0, -25 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 1.3, Joint_CorePos = { 0, -0.2, -0.42 }, Joint_Core = { -13, 6, 0 }, Joint_Legs = { 0, -5, 0 }, Joint_Head = { -11, 8, 0 }, Sub_Head_Jaw = { -36, 0, 0 }, Joint_RightArm = { -14, 0, 24 }, Joint_LeftArm = { -14, 0, -24 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 1.5, Joint_CorePos = { 0, -0.15, -0.35 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -10, 0, 0 }, Sub_Head_Jaw = { -32, 0, 0 }, Joint_RightArm = { -10, 0, 20 }, Joint_LeftArm = { -10, 0, -20 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
			{ T = 1.62, Ease = "Snap", Joint_Head = { -2, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 } },
			{ T = 1.9 },
		},
	},
	-- PHOENIX DIVE (wings): the wings flare up high and BURST INTO FLAME, the bird screeches,
	-- then they fold back as the body tips into the dive (0.35, Hit: the server streaks it 16
	-- studs through everything, leaving fire behind), and at the end of it they FLARE open in
	-- a blast of fire (0.65) as it pulls up.
	Ability_PhoenixDive = {
		Duration = 0.85,
		Curve = "Spline",
		Markers = {
			{ 0, "FX_WingsIgnite" }, { 0, "SFX_FireIgnite" }, { 0.18, "SFX_HawkScreech" }, { 0.3, "Whoosh" }, { 0.35, "Hit" }, { 0.35, "SFX_FireWhoosh" },
			{ 0.65, "FX_PhoenixFlare" }, { 0.65, "SFX_FireIgnite" }, { 0.72, "Land" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.2, Joint_CorePos = { 0, 0.4, 0.25 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Back_R = { 0, 0, 55 }, Sub_Back_L = { 0, 0, -55 }, Joint_RightArm = { 30, 0, 30 }, Joint_LeftArm = { 30, 0, -30 } },
			{ T = 0.35, Ease = "Snap", Joint_CorePos = { 0, 0.2, -0.7 }, Joint_Core = { -48, 0, 0 }, Joint_Head = { 28, 0, 0 }, Sub_Back_R = { 0, -45, -15 }, Sub_Back_L = { 0, 45, 15 }, Joint_RightArm = { -60, 0, 10 }, Joint_LeftArm = { -60, 0, -10 }, Sub_Legs_L = { -30, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 0.58, Joint_CorePos = { 0, 0.2, -0.7 }, Joint_Core = { -46, 0, 4 }, Joint_Head = { 26, 0, 0 }, Sub_Back_R = { 0, -48, -15 }, Sub_Back_L = { 0, 48, 15 }, Joint_RightArm = { -62, 0, 10 }, Joint_LeftArm = { -62, 0, -10 }, Sub_Legs_L = { -30, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
			{ T = 0.65, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0.3, -0.2 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { 20, 0, 0 }, Sub_Back_R = { 0, 10, 70 }, Sub_Back_L = { 0, -10, -70 }, Joint_RightArm = { 90, 0, 70 }, Joint_LeftArm = { 90, 0, -70 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
			{ T = 0.85 },
		},
	},
	-- MAGMA SHELL (core, Obsidian Heart): curl in tight round the heart as the lava wells up,
	-- then throw the arms wide and the head back as the crust bursts out over the body
	-- (0.35, Hit).
	Ability_MagmaShell = {
		Duration = 0.7,
		Curve = "Spline",
		Markers = { { 0, "SFX_LavaRumble" }, { 0.05, "FX_MagmaRise" }, { 0.35, "Hit" }, { 0.35, "FX_MagmaCrust" }, { 0.35, "SFX_RockDebris" }, { 0.35, "Land" }, { 0.4, "SFX_Sizzle" } },
		Keys = {
			{ T = 0 },
			{ T = 0.18, Joint_CorePos = { 0, -0.35, 0 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { -20, 0, 0 }, Joint_RightArm = { 55, 0, -45 }, Sub_RightArm_Fore = { 80, 0, 0 }, Joint_LeftArm = { 55, 0, 45 }, Sub_LeftArm_Fore = { 80, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
			{ T = 0.35, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 95, 0, 75 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 95, 0, -75 }, Sub_LeftArm_Fore = { 0, 0, 0 } },
			{ T = 0.5, Joint_CorePos = { 0, 0.02, 0 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 60, 0, 40 }, Joint_LeftArm = { 60, 0, -40 } },
			{ T = 0.7 },
		},
	},
	-- VENOM STING (tail, Scorpion Tail): lean back and cock the stinger back over the body,
	-- then lunge in and whip it forward over the head, STABBING down into what's in front
	-- (0.45, Hit). Pinned on it, they're pumped full of venom - the tail draws up and drives
	-- in three times (0.67, 0.91, 1.15) - then it YANKS the stinger out (1.35) in a spray.
	Ability_VenomSting = {
		Duration = 1.8,
		Curve = "Spline",
		Markers = {
			{ 0.05, "FX_VenomDrip" }, { 0.12, "StepR" }, { 0.36, "Whoosh" }, { 0.45, "Hit" }, { 0.45, "SFX_Stab" }, { 0.45, "StepL" },
			{ 0.67, "FX_VenomPump" }, { 0.67, "SFX_GoreSquish" }, { 0.91, "FX_VenomPump" }, { 0.91, "SFX_GoreSquish" }, { 1.15, "FX_VenomPump" }, { 1.15, "SFX_GoreSquish" },
			{ 1.35, "FX_VenomSpray" }, { 1.35, "SFX_Squirt" }, { 1.36, "SFX_AcidHiss" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.28, Joint_CorePos = { 0, 0, 0.3 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 6, 0, 0 }, Joint_Tail = { 28, 0, 0 }, Sub_Legs_L = { -10, 0, 0 }, Sub_Legs_R = { 14, 0, 0 } },
			{ T = 0.45, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.2, -0.5 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_Tail = { -60, 0, 0 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.6, Joint_CorePos = { 0, -0.18, -0.48 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_Tail = { -53, 0, 0 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.67, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.24, -0.55 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -9, 0, 0 }, Joint_Tail = { -63, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 0.84, Joint_CorePos = { 0, -0.18, -0.48 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_Tail = { -53, 0, 0 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 0.91, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.24, -0.55 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -9, 0, 0 }, Joint_Tail = { -63, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 1.08, Joint_CorePos = { 0, -0.18, -0.48 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_Tail = { -53, 0, 0 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			{ T = 1.15, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.24, -0.55 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -9, 0, 0 }, Joint_Tail = { -64, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 1.28, Joint_CorePos = { 0, -0.25, -0.55 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_Tail = { -66, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
			{ T = 1.35, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0, -0.1 }, Joint_Core = { 8, 0, 0 }, Joint_Head = { 6, 0, 0 }, Joint_Tail = { -10, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -4, 0, 0 } },
			{ T = 1.55, Joint_CorePos = { 0, 0, 0 }, Joint_Core = { 2, 0, 0 }, Joint_Tail = { 10, 0, 0 } },
			{ T = 1.8 },
		},
	},
}

-- ENERGY OVERLOAD (core): the reactor builds - hunched in on itself, shaking harder and
-- harder as the light swells (0 - 0.95) - then it VENTS (1.0, Hit): thrown upright, arms
-- flung wide, head back; it holds there smoking, then vents its stacks.
do
	local hunched = { Joint_CorePos = { 0, -0.35, 0 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 42, 0, -42 }, Joint_LeftArm = { 42, 0, 42 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } }
	local keys = {
		{ T = 0 },
		{ T = 0.4, Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { -20, 0, 0 }, Joint_RightArm = { 40, 0, -40 }, Joint_LeftArm = { 40, 0, 40 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
	}
	strain(keys, hunched, 0.46, 0.9, 0.045, 1.5, 7)
	table.insert(keys, { T = 0.95, Joint_CorePos = { 0, -0.45, 0 }, Joint_Core = { -24, 0, 0 }, Joint_Head = { -28, 0, 0 }, Joint_RightArm = { 46, 0, -46 }, Joint_LeftArm = { 46, 0, 46 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } })
	table.insert(keys, { T = 1.0, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 20, 0, 0 }, Joint_Head = { 30, 0, 0 }, Joint_RightArm = { 100, 0, 80 }, Joint_LeftArm = { 100, 0, -80 } })
	table.insert(keys, { T = 1.3, Joint_CorePos = { 0, 0.25, 0 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 24, 0, 0 }, Joint_RightArm = { 96, 0, 76 }, Joint_LeftArm = { 96, 0, -76 } })
	table.insert(keys, { T = 1.55, Joint_CorePos = { 0, -0.1, 0 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 30, 0, 20 }, Joint_LeftArm = { 30, 0, -20 } })
	table.insert(keys, { T = 1.9 })
	ABILITY.Ability_EnergyOverload = {
		Duration = 1.9,
		Curve = "Spline",
		Markers = {
			{ 0, "SFX_EnergyCharge" }, { 0.05, "FX_OverloadCharge" }, { 0.4, "SFX_ElectricArc" }, { 0.65, "SFX_PowerUp" }, { 0.95, "Whoosh" },
			{ 1.0, "Hit" }, { 1.0, "FX_OverloadBlast" }, { 1.0, "SFX_Explosion" }, { 1.0, "Land" }, { 1.4, "FX_Vent" }, { 1.4, "SFX_SteamHiss" },
		},
		Keys = keys,
	}
end

-- ULTIMATES ("Ultimate_<Id>"), each in step with its move (UltimateService) and its effects
-- (UltimateEffects): "Hit" = def.Startup, Duration = def.Length, so they play at speed 1.
-- `pose` + a time + changes = a key.
local function keyAt(pose, t: number, changes)
	local key = table.clone(pose)
	key.T = t
	for name, value in changes or {} do
		key[name] = value
	end
	return key
end
local CURLED = { Joint_CorePos = { 0, -0.45, 0.1 }, Joint_Core = { -26, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 55, 0, -42 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 55, 0, 42 }, Sub_LeftArm_Fore = { 70, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 }, Joint_Tail = { 20, 0, 0 } }
local THROWN_OPEN = { Joint_CorePos = { 0, 0.35, 0.1 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { 26, 0, 0 }, Joint_RightArm = { 105, 0, 75 }, Sub_RightArm_Fore = { 5, 0, 0 }, Joint_LeftArm = { 105, 0, -75 }, Sub_LeftArm_Fore = { 5, 0, 0 }, Sub_Legs_L = { -14, 0, 0 }, Sub_Legs_R = { 14, 0, 0 }, Joint_Tail = { -24, 0, 0 } }
local ULTIMATE = {}
do
	-- SPLINTER STORM (Wooden Body): it hunches in, the crate groaning and shaking itself loose,
	-- and BURSTS (1.0): the planks of its own body flung out, the stakes flying. It hauls itself
	-- back together (1.27 - 1.6), bursts again (1.6), again, then the last one spins it right
	-- round (2.2 - 2.58) with the storm going round it, and it's whole again by 2.9.
	local keys = { { T = 0 }, keyAt(CURLED, 0.35) }
	strain(keys, CURLED, 0.42, 0.88, 0.06, 0.6, 3.5)
	table.insert(keys, keyAt(CURLED, 0.94, { Joint_CorePos = { 0, -0.55, 0.1 } }))
	table.insert(keys, keyAt(THROWN_OPEN, 1.0, { Ease = "Snap", Stop = true }))
	table.insert(keys, keyAt(THROWN_OPEN, 1.25))
	table.insert(keys, keyAt(CURLED, 1.54))
	table.insert(keys, keyAt(THROWN_OPEN, 1.6, { Ease = "Snap", Stop = true, Joint_Core = { 22, 0, 0 } }))
	table.insert(keys, keyAt(THROWN_OPEN, 1.85))
	table.insert(keys, keyAt(CURLED, 2.14, { Joint_CorePos = { 0, -0.55, 0.1 } }))
	table.insert(keys, keyAt(THROWN_OPEN, 2.2, { Ease = "Snap", Stop = true, Joint_Core = { 24, 0, 0 }, Joint_RightArm = { 100, 0, 88 }, Joint_LeftArm = { 100, 0, -88 } }))
	table.insert(keys, keyAt(THROWN_OPEN, 2.4, { Ease = "Linear", Joint_Core = { 16, 190, 0 }, Joint_Legs = { 0, -190, 0 }, Joint_RightArm = { 100, 0, 88 }, Joint_LeftArm = { 100, 0, -88 } }))
	table.insert(keys, keyAt(CURLED, 2.62, { Stop = true, Joint_Core = { -14, 360, 0 }, Joint_Legs = { 0, -360, 0 } }))
	table.insert(keys, { T = 2.9, Joint_Core = { 0, 360, 0 }, Joint_Legs = { 0, -360, 0 } })
	ULTIMATE.Ultimate_SplinterStorm = {
		Duration = 2.9,
		Curve = "Spline",
		Markers = {
			{ 0.1, "FX_CrateStrain" }, { 0.1, "SFX_WoodCreak" }, { 0.5, "FX_CrateStrain" }, { 0.75, "SFX_WoodCreak" },
			{ 1.0, "Hit" }, { 1.0, "FX_CrateBurst" }, { 1.0, "Land" }, { 1.27, "FX_CrateGather" },
			{ 1.6, "FX_CrateBurst" }, { 1.6, "Land" }, { 1.87, "FX_CrateGather" },
			{ 2.2, "FX_CrateBurst" }, { 2.2, "Land" }, { 2.25, "Whoosh" }, { 2.3, "SFX_BigWhoosh" }, { 2.5, "FX_CrateGather" }, { 2.72, "StepL" }, { 2.8, "StepR" },
		},
		Keys = keys,
	}
end
do
	-- THOUSAND-EYE GLARE (Peeper Orb): it snaps round on them and every eye opens (0.3), floating
	-- up around it; it rears back, shaking, gathering it all (0.8 - 1.1), then throws its whole
	-- body behind the GLARE (1.2): braced, leaning into the beam, juddering under it until it
	-- gives out (2.35), and it sags.
	local reared = { Joint_CorePos = { 0, 0.3, 0.3 }, Joint_Core = { 24, 0, 0 }, Joint_Head = { 30, 0, 0 }, Sub_Head_Jaw = { -14, 0, 0 }, Joint_RightArm = { 70, 0, 62 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 70, 0, -62 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 8, 0, 0 }, Sub_Legs_R = { -12, 0, 0 }, Joint_Tail = { -14, 0, 0 } }
	local glaring = { Joint_CorePos = { 0, -0.3, -0.45 }, Joint_Core = { -24, 0, 0 }, Joint_Head = { -4, 0, 0 }, Sub_Head_Jaw = { -18, 0, 0 }, Joint_RightArm = { -24, 0, 42 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { -24, 0, -42 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -30, 0, 0 }, Joint_Tail = { 10, 0, 0 } }
	local keys = {
		{ T = 0 },
		{ T = 0.3, Ease = "Out", Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 40, 0, -20 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 40, 0, 20 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
		keyAt(reared, 0.72),
	}
	strain(keys, reared, 0.76, 1.08, 0.05, 0.8, 3)
	table.insert(keys, keyAt(reared, 1.13, { Joint_Core = { 28, 0, 0 } }))
	table.insert(keys, keyAt(glaring, 1.2, { Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.4, -0.6 } }))
	strain(keys, glaring, 1.26, 2.3, 0.06, 2.4, 1.4)
	table.insert(keys, keyAt(glaring, 2.36, { Joint_CorePos = { 0, -0.2, -0.2 } }))
	table.insert(keys, { T = 2.58, Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 8, 0, 8 }, Joint_LeftArm = { 8, 0, -8 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } })
	table.insert(keys, { T = 2.8 })
	ULTIMATE.Ultimate_ThousandEyeGlare = {
		Duration = 2.8,
		Curve = "Spline",
		Markers = {
			{ 0.05, "StepL" }, { 0.2, "StepR" }, { 0.3, "FX_EyesOpen" }, { 0.3, "SFX_LaserCharge" }, { 0.75, "SFX_EnergyCharge" },
			{ 1.2, "Hit" }, { 1.2, "FX_GlareFire" }, { 1.2, "SFX_Laser" }, { 1.2, "Land" }, { 1.7, "SFX_Laser" }, { 2.35, "FX_EyesClose" }, { 2.4, "SFX_SteamHiss" },
		},
		Keys = keys,
	}
end
do
	-- BASTION QUAKE (Reinforced Core): its plates lift off and swing out round it; it sinks and
	-- JUMPS (the server flies it, 0.62 - 0.94), arms overhead, and comes down with everything on
	-- the floor (1.1): plates, fists, the lot. It heaves up and does it again, harder (1.9).
	local sunk = { Joint_CorePos = { 0, -0.6, 0.1 }, Joint_Core = { -24, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { -35, 0, 20 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { -35, 0, -20 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } }
	local apex = { Joint_CorePos = { 0, 0.25, 0.25 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { 16, 0, 0 }, Joint_RightArm = { 185, 0, 8 }, Sub_RightArm_Fore = { 18, 0, 0 }, Joint_LeftArm = { 185, 0, -8 }, Sub_LeftArm_Fore = { 18, 0, 0 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { 24, 0, 0 }, Joint_Tail = { -30, 0, 0 } }
	local slammed = { Joint_CorePos = { 0, -0.7, -0.6 }, Joint_Core = { -40, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 32, 0, 10 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 32, 0, -10 }, Sub_LeftArm_Fore = { 0, 0, 0 }, Sub_Legs_L = { 42, 0, 0 }, Sub_Legs_R = { -34, 0, 0 }, Joint_Tail = { 24, 0, 0 } }
	ULTIMATE.Ultimate_BastionQuake = {
		Duration = 2.7,
		Curve = "Spline",
		Markers = {
			{ 0.1, "SFX_ArmorClank" }, { 0.25, "FX_PlatesRise" }, { 0.25, "SFX_Hydraulic" }, { 0.62, "Whoosh" }, { 0.62, "StepL" }, { 0.62, "StepR" },
			{ 1.0, "SFX_BigWhoosh" }, { 1.1, "Hit" }, { 1.1, "Land" }, { 1.1, "FX_PlatesSlam" }, { 1.1, "SFX_HammerClang" }, { 1.12, "SFX_RockDebris" },
			{ 1.42, "FX_PlatesRise" }, { 1.42, "SFX_Servo" }, { 1.5, "Whoosh" }, { 1.82, "SFX_BigWhoosh" },
			{ 1.9, "Land" }, { 1.9, "FX_PlatesSlam" }, { 1.9, "SFX_HammerClang" }, { 1.92, "SFX_RockDebris" }, { 2.3, "SFX_ArmorClank" }, { 2.45, "StepR" },
		},
		Keys = {
			{ T = 0 },
			{ T = 0.25, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { 6, 0, 0 }, Joint_RightArm = { 40, 0, 40 }, Joint_LeftArm = { 40, 0, -40 } },
			keyAt(sunk, 0.6, { Stop = true }),
			keyAt(apex, 0.86, { Ease = "Out" }),
			keyAt(apex, 0.97, { Joint_Core = { 22, 0, 0 } }),
			keyAt(slammed, 1.1, { Ease = "Snap", Stop = true }),
			keyAt(slammed, 1.18, { Ease = "Linear", Joint_Core = { -38, 0, 2 } }),
			keyAt(slammed, 1.26, { Ease = "Linear", Joint_Core = { -39, 0, -2 } }),
			keyAt(sunk, 1.46, { Joint_RightArm = { 10, 0, 14 }, Joint_LeftArm = { 10, 0, -14 }, Stop = true }),
			keyAt(apex, 1.68, { Ease = "Out" }),
			keyAt(apex, 1.78, { Joint_Core = { 26, 0, 0 }, Joint_RightArm = { 195, 0, 6 }, Joint_LeftArm = { 195, 0, -6 } }),
			keyAt(slammed, 1.9, { Ease = "Snap", Stop = true, Joint_Core = { -46, 0, 0 }, Joint_CorePos = { 0, -0.8, -0.7 } }),
			keyAt(slammed, 1.98, { Ease = "Linear", Joint_Core = { -44, 0, 2 }, Joint_CorePos = { 0, -0.8, -0.7 } }),
			keyAt(slammed, 2.06, { Ease = "Linear", Joint_Core = { -45, 0, -2 }, Joint_CorePos = { 0, -0.8, -0.7 } }),
			{ T = 2.4, Joint_CorePos = { 0, -0.2, -0.1 }, Joint_Core = { -8, 0, 0 }, Joint_RightArm = { 25, 0, 14 }, Joint_LeftArm = { 25, 0, -14 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } },
			{ T = 2.7 },
		},
	}
end
do
	-- CRYSTAL CATACLYSM (Crystal Shell): it spreads its hands and crystal grows up the arms as
	-- they rise (0.2 - 1.05); it drives both down into the floor (1.2) and stays down, straining,
	-- feeding the crystals out under them while they erupt; then it rips the hands up and out
	-- (2.4) and everything it made SHATTERS.
	local drawn = { Joint_CorePos = { 0, 0.3, 0.1 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 165, 0, 34 }, Sub_RightArm_Fore = { 12, 0, 0 }, Joint_LeftArm = { 165, 0, -34 }, Sub_LeftArm_Fore = { 12, 0, 0 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } }
	local driven = { Joint_CorePos = { 0, -0.75, -0.3 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 42, 0, 18 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 42, 0, -18 }, Sub_LeftArm_Fore = { 0, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 }, Joint_Tail = { 18, 0, 0 } }
	local keys = {
		{ T = 0 },
		{ T = 0.25, Joint_CorePos = { 0, -0.2, 0 }, Joint_Core = { -8, 0, 0 }, Joint_RightArm = { 25, 0, 50 }, Joint_LeftArm = { 25, 0, -50 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
		keyAt(drawn, 0.95),
		keyAt(drawn, 1.1, { Joint_Core = { 22, 0, 0 }, Joint_Head = { 28, 0, 0 } }),
		keyAt(driven, 1.2, { Ease = "Snap", Stop = true }),
	}
	strain(keys, driven, 1.28, 2.2, 0.07, 1, 3.2)
	table.insert(keys, keyAt(driven, 2.28, { Joint_CorePos = { 0, -0.85, -0.3 }, Joint_Core = { -44, 0, 0 } }))
	table.insert(keys, keyAt(THROWN_OPEN, 2.4, { Ease = "Snap", Stop = true, Joint_RightArm = { 150, 0, 62 }, Joint_LeftArm = { 150, 0, -62 } }))
	table.insert(keys, keyAt(THROWN_OPEN, 2.65, { Joint_RightArm = { 140, 0, 62 }, Joint_LeftArm = { 140, 0, -62 } }))
	table.insert(keys, { T = 3.0 })
	ULTIMATE.Ultimate_CrystalCataclysm = {
		Duration = 3.0,
		Curve = "Spline",
		Markers = {
			{ 0.2, "FX_CrystalGather" }, { 0.2, "SFX_CrystalHum" }, { 0.75, "SFX_CrystalChime" }, { 1.05, "Whoosh" },
			{ 1.2, "Hit" }, { 1.2, "Land" }, { 1.2, "FX_CrystalDrive" }, { 1.2, "SFX_IceCrack" }, { 1.22, "SFX_Shockwave" },
			{ 2.4, "FX_CrystalRelease" }, { 2.4, "SFX_GlassShatter" }, { 2.42, "SFX_IceShatter" },
		},
		Keys = keys,
	}
end
do
	-- SCRAP APOCALYPSE (Reactor Heart): the reactor shudders and vents, ripping scrap up out of
	-- the ground to circle it, red-hot. Then it goes to work: a full-body overhand throw with one
	-- arm (1.4), the other (1.75), again (2.1, 2.45), and both together over the head (2.8).
	local hunched = { Joint_CorePos = { 0, -0.4, 0 }, Joint_Core = { -22, 0, 0 }, Joint_Head = { -20, 0, 0 }, Joint_RightArm = { 45, 0, 32 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 45, 0, -32 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }
	local function windup(side: number)
		-- (side 1: the right arm is about to throw)
		return { Joint_CorePos = { 0, 0.15, 0.25 }, Joint_Core = { 12, -28 * side, 0 }, Joint_Legs = { 0, 22 * side, 0 }, Joint_Head = { 8, 18 * side, 0 },
			Joint_RightArm = side == 1 and { 180, 0, 26 } or { 40, 0, 26 }, Sub_RightArm_Fore = side == 1 and { 60, 0, 0 } or { 30, 0, 0 },
			Joint_LeftArm = side == 1 and { 40, 0, -26 } or { 180, 0, -26 }, Sub_LeftArm_Fore = side == 1 and { 30, 0, 0 } or { 60, 0, 0 },
			Sub_Legs_L = { -6 * side + 8, 0, 0 }, Sub_Legs_R = { 6 * side - 8, 0, 0 } }
	end
	local function release(side: number)
		return { Joint_CorePos = { 0, -0.3, -0.45 }, Joint_Core = { -22, 26 * side, 0 }, Joint_Legs = { 0, -20 * side, 0 }, Joint_Head = { -6, -14 * side, 0 },
			Joint_RightArm = side == 1 and { 62, 0, -14 } or { 130, 0, 26 }, Sub_RightArm_Fore = side == 1 and { 8, 0, 0 } or { 40, 0, 0 },
			Joint_LeftArm = side == 1 and { 130, 0, -26 } or { 62, 0, 14 }, Sub_LeftArm_Fore = side == 1 and { 40, 0, 0 } or { 8, 0, 0 },
			Sub_Legs_L = { 26 * side + 4, 0, 0 }, Sub_Legs_R = { -26 * side - 4, 0, 0 } }
	end
	local keys = { { T = 0 }, keyAt(hunched, 0.25) }
	strain(keys, hunched, 0.3, 0.98, 0.06, 1, 4)
	table.insert(keys, keyAt(windup(1), 1.22))
	table.insert(keys, keyAt(windup(1), 1.31, { Joint_Core = { 16, -32, 0 } }))
	for i, t in { 1.4, 1.75, 2.1, 2.45 } do
		local side = i % 2 == 1 and 1 or -1
		table.insert(keys, keyAt(release(side), t, { Ease = "Snap", Stop = true }))
		if i < 4 then
			table.insert(keys, keyAt(windup(-side), t + 0.24, { Ease = "Out" }))
		end
	end
	table.insert(keys, { T = 2.68, Ease = "Out", Joint_CorePos = { 0, 0.35, 0.3 }, Joint_Core = { 24, 0, 0 }, Joint_Head = { 16, 0, 0 }, Joint_RightArm = { 190, 0, 8 }, Sub_RightArm_Fore = { 50, 0, 0 }, Joint_LeftArm = { 190, 0, -8 }, Sub_LeftArm_Fore = { 50, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } })
	table.insert(keys, { T = 2.8, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.6, -0.6 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 50, 0, 8 }, Sub_RightArm_Fore = { 4, 0, 0 }, Joint_LeftArm = { 50, 0, -8 }, Sub_LeftArm_Fore = { 4, 0, 0 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } })
	table.insert(keys, { T = 3.05, Joint_CorePos = { 0, -0.5, -0.45 }, Joint_Core = { -32, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 30, 0, 8 }, Joint_LeftArm = { 30, 0, -8 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } })
	table.insert(keys, { T = 3.5 })
	ULTIMATE.Ultimate_ScrapApocalypse = {
		Duration = 3.5,
		Curve = "Spline",
		Markers = {
			{ 0.1, "FX_ReactorVent" }, { 0.1, "SFX_SteamHiss" }, { 0.3, "SFX_EnergyCharge" }, { 0.35, "FX_ScrapRise" }, { 0.4, "SFX_RockDebris" }, { 0.7, "SFX_MetalClang" }, { 0.8, "FX_ReactorVent" },
			{ 1.3, "Whoosh" }, { 1.4, "Hit" }, { 1.4, "StepR" }, { 1.65, "Whoosh" }, { 1.75, "StepL" }, { 2.0, "Whoosh" }, { 2.1, "StepR" }, { 2.35, "Whoosh" }, { 2.45, "StepL" },
			{ 2.7, "SFX_BigWhoosh" }, { 2.8, "Land" }, { 3.05, "SFX_SteamHiss" },
		},
		Keys = keys,
	}
end
do
	-- VOID COLLAPSE (Void Wings): wings wide, it tears the air open with both claws (0.3) and
	-- starts HAULING on it, hand over hand, leaning back against the weight, the bodies coming
	-- with it. It clenches (1.5): fists to the chest, wings snapping shut, everything crushed to
	-- a point, a held moment, and it throws itself open as it goes off (1.7).
	local function haul(t: number, side: number)
		return { T = t, Joint_CorePos = { 0, -0.15, 0.3 }, Joint_Core = { 12, 8 * side, 0 }, Joint_Legs = { 0, -6 * side, 0 }, Joint_Head = { -6, -5 * side, 0 },
			Joint_RightArm = side == 1 and { 105, 0, -6 } or { 55, 0, 10 }, Sub_RightArm_Fore = side == 1 and { 10, 0, 0 } or { 95, 0, 0 },
			Joint_LeftArm = side == 1 and { 55, 0, -10 } or { 105, 0, 6 }, Sub_LeftArm_Fore = side == 1 and { 95, 0, 0 } or { 10, 0, 0 },
			Sub_Back_R = { 0, -12, 40 }, Sub_Back_L = { 0, 12, -40 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -34, 0, 0 }, Joint_Tail = { 14, 0, 0 } }
	end
	local clenched = { Joint_CorePos = { 0, -0.55, 0 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 45, 0, -48 }, Sub_RightArm_Fore = { 115, 0, 0 }, Joint_LeftArm = { 45, 0, 48 }, Sub_LeftArm_Fore = { 115, 0, 0 }, Sub_Back_R = { 0, 40, -24 }, Sub_Back_L = { 0, -40, 24 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -24, 0, 0 }, Joint_Tail = { 26, 0, 0 } }
	local keys = {
		{ T = 0 },
		{ T = 0.18, Joint_CorePos = { 0, 0.1, 0.15 }, Joint_Core = { 8, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 110, 0, 40 }, Joint_LeftArm = { 110, 0, -40 }, Sub_Back_R = { 0, 0, 60 }, Sub_Back_L = { 0, 0, -60 } },
		{ T = 0.3, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.25, -0.4 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 112, 0, -8 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 112, 0, 8 }, Sub_LeftArm_Fore = { 0, 0, 0 }, Sub_Back_R = { 0, -10, 72 }, Sub_Back_L = { 0, 10, -72 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
		haul(0.56, 1), haul(0.82, -1), haul(1.08, 1), haul(1.32, -1),
		keyAt(clenched, 1.5, { Ease = "Snap", Stop = true }),
		keyAt(clenched, 1.56, { Ease = "Linear", Joint_Core = { -32, 0, 2 } }),
		keyAt(clenched, 1.62, { Ease = "Linear", Joint_Core = { -31, 0, -2 } }),
		keyAt(clenched, 1.66, { Ease = "Linear", Joint_CorePos = { 0, -0.62, 0 } }),
		keyAt(THROWN_OPEN, 1.7, { Ease = "Snap", Stop = true, Joint_Core = { 26, 0, 0 }, Joint_Head = { 32, 0, 0 }, Sub_Back_R = { 0, -6, 78 }, Sub_Back_L = { 0, 6, -78 } }),
		keyAt(THROWN_OPEN, 2.05, { Joint_Core = { 16, 0, 0 }, Sub_Back_R = { 0, -6, 62 }, Sub_Back_L = { 0, 6, -62 } }),
		{ T = 2.4, Joint_CorePos = { 0, -0.1, 0 }, Joint_Core = { -6, 0, 0 }, Joint_RightArm = { 25, 0, 16 }, Joint_LeftArm = { 25, 0, -16 }, Sub_Back_R = { 0, 0, 16 }, Sub_Back_L = { 0, 0, -16 } },
		{ T = 2.7 },
	}
	ULTIMATE.Ultimate_VoidCollapse = {
		Duration = 2.7,
		Curve = "Spline",
		Markers = {
			{ 0.05, "SFX_WingFlap" }, { 0.2, "Whoosh" }, { 0.3, "SFX_VoidWhoosh" }, { 0.56, "StepR" }, { 0.82, "StepL" }, { 1.08, "StepR" }, { 1.32, "StepL" },
			{ 1.7, "Hit" }, { 1.7, "SFX_WingFlap" },
		},
		Keys = keys,
	}
end
do
	-- SUPERNOVA (Phoenix Wings): the wings wrap right round it and it lifts off the ground in a
	-- cocoon of fire (the server flies it), shaking, burning brighter; the wings burst open (1.2),
	-- fold back to the half (1.72), burst wider (1.8), fold, and the last takes everything it has
	-- (2.4), head thrown back, until it gives out (2.75) and drops, landing hard (3.05).
	local cocoon = { Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -24, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 50, 0, -40 }, Sub_RightArm_Fore = { 80, 0, 0 }, Joint_LeftArm = { 50, 0, 40 }, Sub_LeftArm_Fore = { 80, 0, 0 }, Sub_Back_R = { 0, 52, -34 }, Sub_Back_L = { 0, -52, 34 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { 22, 0, 0 }, Joint_Tail = { 24, 0, 0 } }
	local function flare(t: number, size: number)
		return { T = t, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0.3, 0.1 }, Joint_Core = { 16 + 10 * size, 0, 0 }, Joint_Head = { 22 + 10 * size, 0, 0 }, Joint_RightArm = { 110, 0, 58 + 22 * size }, Sub_RightArm_Fore = { 6, 0, 0 }, Joint_LeftArm = { 110, 0, -58 - 22 * size }, Sub_LeftArm_Fore = { 6, 0, 0 }, Sub_Back_R = { 0, -6, 52 + 28 * size }, Sub_Back_L = { 0, 6, -52 - 28 * size }, Sub_Legs_L = { -10, 0, 0 }, Sub_Legs_R = { -18, 0, 0 }, Joint_Tail = { -30, 0, 0 } }
	end
	local function hold(t: number, size: number)
		local key = flare(t, size)
		key.Ease, key.Stop = nil, nil
		return key
	end
	local function half(t: number)
		return { T = t, Joint_CorePos = { 0, -0.1, 0 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 70, 0, -10 }, Sub_RightArm_Fore = { 50, 0, 0 }, Joint_LeftArm = { 70, 0, 10 }, Sub_LeftArm_Fore = { 50, 0, 0 }, Sub_Back_R = { 0, 30, -8 }, Sub_Back_L = { 0, -30, 8 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { 10, 0, 0 } }
	end
	local keys = { { T = 0 }, keyAt(cocoon, 0.5) }
	strain(keys, cocoon, 0.55, 1.08, 0.06, 0.6, 3.5)
	table.insert(keys, keyAt(cocoon, 1.14, { Joint_CorePos = { 0, -0.4, 0 } }))
	table.insert(keys, flare(1.2, 0.5))
	table.insert(keys, hold(1.42, 0.45))
	table.insert(keys, half(1.74))
	table.insert(keys, flare(1.8, 0.75))
	table.insert(keys, hold(2.02, 0.7))
	table.insert(keys, half(2.34))
	table.insert(keys, flare(2.4, 1))
	table.insert(keys, hold(2.72, 0.95))
	table.insert(keys, { T = 2.92, Joint_CorePos = { 0, 0.4, 0.2 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 150, 0, 40 }, Joint_LeftArm = { 150, 0, -40 }, Sub_Back_R = { 0, -20, 72 }, Sub_Back_L = { 0, 20, -72 }, Sub_Legs_L = { -6, 0, 0 }, Sub_Legs_R = { 8, 0, 0 } })
	table.insert(keys, { T = 3.05, Ease = "Snap", Stop = true, Joint_CorePos = { 0, -0.8, -0.2 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 25, 0, 26 }, Joint_LeftArm = { 25, 0, -26 }, Sub_Back_R = { 0, -8, 30 }, Sub_Back_L = { 0, 8, -30 }, Sub_Legs_L = { 44, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } })
	table.insert(keys, { T = 3.3 })
	ULTIMATE.Ultimate_Supernova = {
		Duration = 3.3,
		Curve = "Spline",
		Markers = {
			{ 0.1, "FX_WingsCocoon" }, { 0.1, "SFX_FireIgnite" }, { 0.2, "SFX_WingFlap" }, { 0.5, "SFX_PowerUp" }, { 1.05, "SFX_HawkScreech" },
			{ 1.2, "Hit" }, { 1.72, "SFX_FireWhoosh" }, { 2.32, "SFX_FireWhoosh" }, { 2.3, "SFX_HawkScreech" }, { 2.75, "Whoosh" }, { 3.05, "Land" }, { 3.05, "FX_PhoenixLand" }, { 3.05, "SFX_BodySlam" },
		},
		Keys = keys,
	}
end
do
	-- ERUPTION (Obsidian Heart): it curls round the heart as the floor cracks glowing beneath it,
	-- shaking harder and harder (0.25 - 1.2), then the heart SPLITS (1.3): thrown back arched,
	-- arms up, a column of lava going up out of its chest, the whole body juddering while the
	-- bombs pour out of it; at the end it sags, spent and steaming, and the heart seals.
	local arched = { Joint_CorePos = { 0, 0.45, 0.25 }, Joint_Core = { 30, 0, 0 }, Joint_Head = { 36, 0, 0 }, Sub_Head_Jaw = { -18, 0, 0 }, Joint_RightArm = { 160, 0, 40 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 160, 0, -40 }, Sub_LeftArm_Fore = { 10, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -22, 0, 0 }, Joint_Tail = { -26, 0, 0 } }
	local keys = { { T = 0 }, keyAt(CURLED, 0.22) }
	strain(keys, CURLED, 0.26, 1.16, 0.06, 0.8, 5)
	table.insert(keys, keyAt(CURLED, 1.22, { Joint_CorePos = { 0, -0.65, 0.1 }, Joint_Core = { -34, 0, 0 } }))
	table.insert(keys, keyAt(arched, 1.3, { Ease = "Snap", Stop = true }))
	strain(keys, arched, 1.36, 2.72, 0.07, 3, 1.2)
	table.insert(keys, { T = 2.92, Joint_CorePos = { 0, -0.45, -0.1 }, Joint_Core = { -26, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { 14, 0, 10 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 14, 0, -10 }, Sub_LeftArm_Fore = { 20, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } })
	table.insert(keys, { T = 3.15, Joint_CorePos = { 0, -0.35, -0.05 }, Joint_Core = { -18, 0, 2 }, Joint_Head = { -24, 0, 0 }, Joint_RightArm = { 12, 0, 8 }, Joint_LeftArm = { 12, 0, -8 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } })
	table.insert(keys, { T = 3.4 })
	ULTIMATE.Ultimate_Eruption = {
		Duration = 3.4,
		Curve = "Spline",
		Markers = {
			{ 0.2, "SFX_LavaRumble" }, { 0.25, "FX_HeartCrack" }, { 0.55, "SFX_Sizzle" }, { 0.65, "FX_HeartCrack" }, { 1.0, "FX_HeartCrack" }, { 1.1, "SFX_PowerUp" },
			{ 1.3, "Hit" }, { 1.3, "FX_HeartSplit" }, { 1.3, "SFX_Explosion" }, { 1.32, "SFX_FireWhoosh" }, { 1.8, "SFX_LavaRumble" }, { 2.85, "FX_HeartSeal" }, { 2.9, "SFX_SteamHiss" }, { 3.0, "StepL" },
		},
		Keys = keys,
	}
end


-- A MASTERED version of a combo: the base clip's keys and markers up to `upTo`, then new
-- beats (Combo Mastery unlocks it: NightmareCombatDefinitions / Config Moveset Unlock).
local function extend(base, upTo: number, duration: number, keys, markers)
	local out = { Duration = duration, Keys = {}, Markers = {} }
	for _, key in base.Keys do
		if key.T <= upTo + 1e-6 then
			table.insert(out.Keys, key)
		end
	end
	for _, key in keys do
		table.insert(out.Keys, key)
	end
	for _, marker in base.Markers or {} do
		if marker[1] <= upTo + 1e-6 then
			table.insert(out.Markers, marker)
		end
	end
	for _, marker in markers do
		table.insert(out.Markers, marker)
	end
	return out
end
-- the Frenzy's swipes: right claw raking across, the left cocked out for the next (and its mirror)
local SWIPE_R = { Joint_Core = { -12, -25, 0 }, Joint_Legs = { 12, 25, 0 }, Joint_RightArm = { 95, 0, -60 }, Sub_RightArm_Fore = { 15, 0, 0 }, Joint_LeftArm = { 115, 0, -35 }, Sub_LeftArm_Fore = { 45, 0, 0 }, Joint_Head = { -14, 15, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } }
local SWIPE_L = { Joint_Core = { -12, 25, 0 }, Joint_Legs = { 12, -25, 0 }, Joint_LeftArm = { 95, 0, 60 }, Sub_LeftArm_Fore = { 15, 0, 0 }, Joint_RightArm = { 115, 0, 35 }, Sub_RightArm_Fore = { 45, 0, 0 }, Joint_Head = { -14, -15, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_L = { -12, 0, 0 }, Sub_Legs_R = { 20, 0, 0 } }
local function step(t: number, pose, z: number)
	return at(t, pose, { Joint_CorePos = { 0, 0, z } })
end

local POSES = {
	-- Any body (Nightmares, enemies, bosses: everything has Joint_Core; legs / arms / head
	-- are used where they exist). The gym's bag work (GYM above) is merged in below.
	Common = {
		-- Abilities by id ("Ability_<Id>", the server's ActionName). "_Left" = mirrored for a
		-- left-limb source.
		Ability_Bite = BITE,

		-- GUARD (the combat brain covering up, NightmareCombatDefinitions.Guard): any body
		-- sinks, tucks the head and brings up whatever arms it has; held, a small breathing
		-- bob, then lets it go. (Played over the guard's time, 0.7 - 1.3 s.)
		Guard_Hold = {
			Duration = 1.0,
			Markers = { { 0.12, "StepL" } },
			Keys = {
				{ T = 0 },
				{ T = 0.12, Joint_CorePos = { 0, -0.35, 0.1 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 70, 0, -30 }, Joint_LeftArm = { 70, 0, 30 } },
				{ T = 0.5, Joint_CorePos = { 0, -0.42, 0.1 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -20, 0, 0 }, Joint_RightArm = { 72, 0, -30 }, Joint_LeftArm = { 72, 0, 30 } },
				{ T = 0.85, Joint_CorePos = { 0, -0.35, 0.1 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 70, 0, -30 }, Joint_LeftArm = { 70, 0, 30 } },
				{ T = 1.0 },
			},
		},

		-- NIGHTMARE FRENZY (any body with two arms; a MUTATED part unlocks it): it loses
		-- itself - six wild alternating claw rakes stepping in, a roar, and a two-handed
		-- shove that sends them flying.
		Combo_NightmareFrenzy = {
			Duration = 2.3,
			Markers = {
				{ 0.12, "Whoosh" }, { 0.3, "Strike" }, { 0.48, "Strike" }, { 0.66, "Strike" }, { 0.84, "Strike" }, { 1.02, "Strike" }, { 1.2, "Strike" },
				{ 1.45, "Roar" }, { 1.72, "Strike" }, { 1.72, "StepL" },
			},
			Keys = {
				{ T = 0 },
				{ T = 0.12, Joint_Core = { -14, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Head_Jaw = { -35, 0, 0 }, Joint_RightArm = { 110, 0, 40 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 110, 0, -40 }, Sub_LeftArm_Fore = { 40, 0, 0 } },
				step(0.3, SWIPE_R, -0.25),
				step(0.48, SWIPE_L, -0.3),
				step(0.66, SWIPE_R, -0.4),
				step(0.84, SWIPE_L, -0.45),
				step(1.02, SWIPE_R, -0.55),
				step(1.2, SWIPE_L, -0.6),
				-- ROAR: up and open, arms flung wide
				{ T = 1.45, Joint_CorePos = { 0, 0, -0.5 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { -14, 0, 0 }, Joint_Head = { 18, 0, 0 }, Sub_Head_Jaw = { -50, 0, 0 }, Joint_RightArm = { 60, 0, 60 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 60, 0, -60 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
				-- the SHOVE: both hands straight through them
				{ T = 1.72, Joint_CorePos = { 0, 0, -0.9 }, Joint_Core = { -18, 0, 0 }, Joint_Legs = { 18, 0, 0 }, Joint_Head = { -10, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Joint_RightArm = { 90, 0, -8 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 90, 0, 8 }, Sub_LeftArm_Fore = { 0, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
				{ T = 2.0, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -4, 0, 0 }, Joint_Legs = { 4, 0, 0 }, Joint_RightArm = { 40, 0, -20 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 40, 0, 20 }, Sub_LeftArm_Fore = { 30, 0, 0 } },
				{ T = 2.3 },
			},
		},
		-- TENTACLE SLAM (a Shadow Tentacle right arm): coil, lash out and wrap them at range,
		-- haul them in, hoist them high over its head and smash them down into the floor.
		-- (The server carries the victim along the tentacle: Config Moveset Hold.Path.)
		Combo_TentacleSlam = {
			Duration = 2.2,
			Markers = { { 0.15, "Whoosh" }, { 0.32, "Strike" }, { 0.6, "Grind" }, { 0.95, "Whoosh" }, { 1.25, "Strike" }, { 1.25, "Land" } },
			Keys = {
				{ T = 0 },
				{ T = 0.15, Joint_Core = { -6, 25, 0 }, Joint_Legs = { 6, -25, 0 }, Joint_Head = { -10, -15, 0 }, Joint_RightArm = { 40, 0, 40 }, Sub_RightArm_Fore = { 60, 0, 0 } },
				{ T = 0.32, Joint_CorePos = { 0, 0, -0.3 }, Joint_Core = { -12, -15, 0 }, Joint_Legs = { 12, 15, 0 }, Joint_Head = { -10, 10, 0 }, Joint_RightArm = { 85, 0, -25 }, Sub_RightArm_Fore = { -10, 0, 0 } },
				{ T = 0.6, Joint_CorePos = { 0, 0, 0.1 }, Joint_Core = { 6, 10, 0 }, Joint_Legs = { -6, -10, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 60, 0, -35 }, Sub_RightArm_Fore = { 40, 0, 0 } },
				{ T = 0.95, Joint_Core = { 10, 0, 0 }, Joint_Legs = { -10, 0, 0 }, Joint_Head = { 12, 0, 0 }, Joint_RightArm = { 125, 0, -25 }, Sub_RightArm_Fore = { 10, 0, 0 } },
				{ T = 1.25, Joint_CorePos = { 0, 0, -0.4 }, Joint_Core = { -30, -10, 0 }, Joint_Legs = { 24, 10, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 65, 0, -35 }, Sub_RightArm_Fore = { 0, 0, 0 } },
				{ T = 1.55, Joint_CorePos = { 0, 0, -0.4 }, Joint_Core = { -26, -8, 0 }, Joint_Legs = { 22, 8, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 55, 0, -30 }, Sub_RightArm_Fore = { 10, 0, 0 } },
				{ T = 1.9, Joint_Core = { -4, 0, 0 }, Joint_Legs = { 4, 0, 0 }, Joint_RightArm = { 15, 0, 0 }, Sub_RightArm_Fore = { 20, 0, 0 } },
				{ T = 2.2 },
			},
		},

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
		-- AUTONOMOUS COMBOS (Shared/NightmareComboDefinitions picks them; "Combo_<Id>").
		-- BRUTAL BOXER: jab, cross, lead hook, rear uppercut, OVERHAND, one continuous clip:
		-- every punch winds up the next (the cross turns the hips left, which loads the
		-- hook; the hook's follow-through drops into the dip for the uppercut; the uppercut
		-- rises straight into the overhand's wind-up), the elbows (Sub_*Arm_Fore) bend and
		-- extend, the hips pivot with the feet planted (Joint_Legs counter-turns the core).
		-- Contact frames measured in the pose lab on a Reinforced Core + Inferno Gauntlets
		-- body (fist centre, studs: x right, y up, f ahead of the root): jab (0.1, 1.8, 4.4),
		-- cross (-0.6, 1.6, 4.6), hook (0.2, 2.1, 3.5), uppercut (0.5, 2.2, 3.1),
		-- overhand (-0.3, 1.7, 5.1): all on the centre line at head height.
		-- (Joint_CorePos Y on each key lifts the body by the amount the legs sank on that frame,
		-- measured: the feet stay at their standing height all the way through)
		Combo_BrutalBoxer = {
			Duration = 2.4,
			Markers = {
				-- (every marker sits on a keyframe, so the exported asset keeps all of them)
				{ 0.22, "Whoosh" }, { 0.3, "Strike" }, { 0.42, "Whoosh" }, { 0.55, "Strike" }, { 0.55, "StepL" },
				{ 0.7, "Whoosh" }, { 0.82, "Strike" }, { 1.0, "StepR" }, { 1.0, "Whoosh" }, { 1.1, "Strike" },
				{ 1.4, "Whoosh" }, { 1.62, "Strike" }, { 1.62, "StepL" },
			},
			Keys = {
				{ T = 0 },
				-- up into the guard: bladed, chin down, fists by the face
				{ T = 0.12, Joint_CorePos = { 0, 0.12, 0 }, Joint_Core = { -6, -10, 0 }, Joint_Legs = { 6, 10, 0 }, Joint_Head = { -10, 10, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- JAB: the lead hand snaps straight out, shoulder turned in behind it
				{ T = 0.22, Joint_CorePos = { 0, 0.11, -0.15 }, Joint_Core = { -8, -18, 0 }, Joint_Legs = { 8, 18, 0 }, Joint_Head = { -10, 14, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 82, 0, 36 }, Sub_LeftArm_Fore = { 50, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				{ T = 0.3, Joint_CorePos = { 0, 0.08, -0.35 }, Joint_Core = { -10, -24, 0 }, Joint_Legs = { 10, 24, 0 }, Joint_Head = { -10, 16, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 100, 0, 22 }, Sub_LeftArm_Fore = { 8, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- the jab snaps back as the rear hip starts to drive
				{ T = 0.42, Joint_CorePos = { 0, 0.13, -0.3 }, Joint_Core = { -10, 4, 0 }, Joint_Legs = { 10, -4, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 70, 0, -42 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 58, 0, 48 }, Sub_LeftArm_Fore = { 95, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
				-- CROSS: the rear hand straight down the middle, hips and shoulders fully turned
				{ T = 0.55, Joint_CorePos = { 0, 0.22, -0.5 }, Joint_Core = { -12, 30, 0 }, Joint_Legs = { 12, -30, 0 }, Joint_Head = { -12, -12, 0 }, Joint_RightArm = { 100, 0, -22 }, Sub_RightArm_Fore = { 6, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
				-- the cross comes home; the lead arm cocks out wide, loaded by the turned hips
				{ T = 0.7, Joint_CorePos = { 0, 0.15, -0.4 }, Joint_Core = { -8, 22, 2 }, Joint_Legs = { 8, -22, 0 }, Joint_Head = { -10, -6, 0 }, Joint_RightArm = { 52, 0, -55 }, Sub_RightArm_Fore = { 100, 0, 0 }, Joint_LeftArm = { 84, 0, -8 }, Sub_LeftArm_Fore = { 72, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
				-- LEAD HOOK: elbow up, the whole body whips back round to the right through it
				{ T = 0.82, Joint_CorePos = { 0, 0.08, -0.3 }, Joint_Core = { -8, -35, 4 }, Joint_Legs = { 8, 35, -4 }, Joint_Head = { -10, 14, 0 }, Joint_RightArm = { 52, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 80, 0, 40 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- follow-through, dropping into the dip that loads the uppercut
				{ T = 1.0, Joint_CorePos = { 0, 0.05, -0.2 }, Joint_Core = { -14, -22, 0 }, Joint_Legs = { 14, 22, 0 }, Joint_Head = { -12, 8, 0 }, Joint_RightArm = { 38, 0, -42 }, Sub_RightArm_Fore = { 112, 0, 0 }, Joint_LeftArm = { 56, 0, 48 }, Sub_LeftArm_Fore = { 98, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
				-- REAR UPPERCUT: drive up out of the dip, the fist rising under the chin
				{ T = 1.1, Joint_CorePos = { 0, 0.13, -0.35 }, Joint_Core = { 2, 28, 0 }, Joint_Legs = { -2, -28, 0 }, Joint_Head = { -6, -10, 0 }, Joint_RightArm = { 60, 0, -45 }, Sub_RightArm_Fore = { 85, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
				-- rising straight on into the overhand's wind-up: rear arm high and back
				{ T = 1.4, Joint_CorePos = { 0, 0.21, 0.1 }, Joint_Core = { 12, -30, 0 }, Joint_Legs = { -12, 30, 0 }, Joint_Head = { -6, 18, 0 }, Joint_RightArm = { 160, 0, 10 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 60, 0, 46 }, Sub_LeftArm_Fore = { 95, 0, 0 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
				-- OVERHAND: over the top and down through them with everything, stepping in
				{ T = 1.62, Joint_CorePos = { 0, -0.01, -0.9 }, Joint_Core = { -24, 40, -6 }, Joint_Legs = { 24, -40, 6 }, Joint_Head = { -10, -15, 0 }, Joint_RightArm = { 118, 0, -24 }, Sub_RightArm_Fore = { 14, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 35, 0, 0 }, Sub_Legs_R = { -25, 0, 0 } },
				-- the weight carries on through
				{ T = 1.85, Joint_CorePos = { 0, -0.29, -1.0 }, Joint_Core = { -32, 50, -6 }, Joint_Legs = { 32, -50, 6 }, Joint_Head = { -12, -22, 0 }, Joint_RightArm = { 62, 0, -40 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 50, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } },
				-- and back up into the guard
				{ T = 2.15, Joint_CorePos = { 0, 0.12, -0.3 }, Joint_Core = { -6, -10, 0 }, Joint_Legs = { 6, 10, 0 }, Joint_Head = { -10, 10, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				{ T = 2.4 },
			},
		},

		-- PERFECT COUNTER (React: their attack comes in): SLIP it - a sharp sidestep down and
		-- to the right, head off the line (the server slides the body and gives it i-frames
		-- for the slip) - and come straight back up off the slip with the lead hook, dip,
		-- rear uppercut, then chamber the knee and drive a push kick through them.
		Combo_PerfectCounter = {
			Duration = 1.9,
			Markers = {
				{ 0.22, "StepR" }, { 0.34, "Whoosh" }, { 0.46, "Strike" }, { 0.6, "Whoosh" }, { 0.7, "Strike" },
				{ 0.86, "Whoosh" }, { 1.0, "Strike" }, { 1.45, "StepR" },
			},
			Keys = {
				{ T = 0 },
				at(0.08, BOXER),
				-- the slip: down and right, the head off the line
				at(0.22, BOXER, { Joint_CorePos = { 0.6, -0.07, 0.15 }, Joint_Core = { -16, -20, 14 }, Joint_Legs = { 16, 20, -14 }, Joint_Head = { -16, 16, 10 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } }),
				-- up out of it, the hips loading the hook
				at(0.34, BOXER, with(B_HOOK_LOAD, { Joint_CorePos = { 0.35, 0.08, -0.2 } })),
				at(0.46, BOXER, with(B_HOOK, { Joint_CorePos = { 0.2, 0.08, -0.35 } })),
				at(0.6, BOXER, with(B_DIP, { Joint_CorePos = { 0.1, 0.05, -0.25 } })),
				at(0.7, BOXER, with(B_UPPER, { Joint_CorePos = { 0, 0.13, -0.35 } })),
				-- chamber the knee, then the push kick through the middle
				at(0.86, BOXER, { Joint_CorePos = { 0, -0.02, -0.1 }, Joint_Core = { 6, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -12, 0, 0 }, Sub_Legs_R = { 70, 0, -10 }, Sub_Legs_L = { -2, 0, 0 } }),
				at(1.0, BOXER, { Joint_CorePos = { 0, -0.05, -0.35 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Legs_R = { 95, 0, -18 }, Sub_Legs_L = { -6, 0, 0 } }),
				at(1.18, BOXER, { Joint_CorePos = { 0, -0.02, -0.3 }, Joint_Core = { 6, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Sub_Legs_R = { 55, 0, -10 }, Sub_Legs_L = { 0, 0, 0 } }),
				at(1.45, BOXER, { Joint_CorePos = { 0, 0.12, -0.2 } }),
				{ T = 1.9 },
			},
		},
		-- SAVAGE EXECUTION (a grab): both hands shoot out and take them by the collar (the
		-- server holds them there, in front of the chest), haul them in, two headbutts, then
		-- a hip toss: load left, whip the hips round to the right and throw them away.
		Combo_SavageExecution = {
			Duration = 2.2,
			Markers = {
				{ 0.3, "Strike" }, { 0.3, "StepL" }, { 0.45, "Whoosh" }, { 0.62, "Strike" }, { 0.78, "Whoosh" }, { 0.94, "Strike" },
				{ 1.12, "StepR" }, { 1.12, "Whoosh" }, { 1.38, "Strike" }, { 1.38, "StepL" },
			},
			Keys = {
				{ T = 0 },
				at(0.1, BOXER),
				-- the grab: both hands shoot out to them, stepping in
				at(0.3, BOXER, { Joint_CorePos = { 0, 0.1, -0.5 }, Joint_Core = { -14, 0, 0 }, Joint_Legs = { 14, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 100, 0, -34 }, Sub_RightArm_Fore = { 15, 0, 0 }, Joint_LeftArm = { 100, 0, 34 }, Sub_LeftArm_Fore = { 15, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }),
				-- haul them up and in (the server lifts them to the hands), head back: loading
				at(0.45, BOXER, { Joint_CorePos = { 0, 0.12, -0.2 }, Joint_Core = { -6, 0, 0 }, Joint_Legs = { 6, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 100, 0, -32 }, Sub_RightArm_Fore = { 25, 0, 0 }, Joint_LeftArm = { 100, 0, 32 }, Sub_LeftArm_Fore = { 25, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }),
				-- HEADBUTT: the skull driven into their face, the hands pulling them onto it
				at(0.62, BOXER, { Joint_CorePos = { 0, 0.05, -0.45 }, Joint_Core = { -22, 0, 0 }, Joint_Legs = { 22, 0, 0 }, Joint_Head = { -38, 0, 0 }, Joint_RightArm = { 92, 0, -32 }, Sub_RightArm_Fore = { 35, 0, 0 }, Joint_LeftArm = { 92, 0, 32 }, Sub_LeftArm_Fore = { 35, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }),
				at(0.78, BOXER, { Joint_CorePos = { 0, 0.12, -0.2 }, Joint_Core = { -4, 0, 0 }, Joint_Legs = { 4, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 100, 0, -32 }, Sub_RightArm_Fore = { 25, 0, 0 }, Joint_LeftArm = { 100, 0, 32 }, Sub_LeftArm_Fore = { 25, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }),
				-- and again
				at(0.94, BOXER, { Joint_CorePos = { 0, 0.05, -0.45 }, Joint_Core = { -22, 0, 0 }, Joint_Legs = { 22, 0, 0 }, Joint_Head = { -38, 0, 0 }, Joint_RightArm = { 92, 0, -32 }, Sub_RightArm_Fore = { 35, 0, 0 }, Joint_LeftArm = { 92, 0, 32 }, Sub_LeftArm_Fore = { 35, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }),
				-- load the throw: hips turned left, them carried round with the arms
				at(1.12, BOXER, { Joint_CorePos = { 0, 0.18, -0.1 }, Joint_Core = { -10, 30, 0 }, Joint_Legs = { 10, -30, 0 }, Joint_Head = { -6, -20, 0 }, Joint_RightArm = { 100, 0, -20 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 100, 0, 40 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }),
				-- THE TOSS: the hips whip round to the right, the arms sling them across
				at(1.38, BOXER, { Joint_CorePos = { 0, 0.01, -0.4 }, Joint_Core = { -28, -75, -10 }, Joint_Legs = { 20, 45, 8 }, Joint_Head = { -14, 30, 0 }, Joint_RightArm = { 70, 0, -60 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 95, 0, 55 }, Sub_LeftArm_Fore = { 20, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } }),
				at(1.6, BOXER, { Joint_CorePos = { 0, 0.03, -0.45 }, Joint_Core = { -20, -85, -6 }, Joint_Legs = { 16, 50, 4 }, Joint_Head = { -12, 36, 0 }, Joint_RightArm = { 40, 0, -50 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 70, 0, 60 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } }),
				at(1.95, BOXER, { Joint_CorePos = { 0, 0.12, -0.3 } }),
				{ T = 2.2 },
			},
		},
		-- CYCLONE DESTROYER (a SIGNATURE: rare, only on a staggered or beaten target): jab,
		-- spin away to the right and whip the back of the right fist round into them, come
		-- out of the spin into a crouch, LEAP with both fists high, and crash a double
		-- hammerfist down through them. (The spin runs -360 on through to the end: the code
		-- poses interpolate the numbers.)
		Combo_CycloneDestroyer = {
			Duration = 2.3,
			Markers = {
				{ 0.22, "Whoosh" }, { 0.3, "Strike" }, { 0.45, "StepR" }, { 0.6, "Whoosh" }, { 0.72, "Strike" }, { 1.0, "StepL" },
				{ 1.2, "StepR" }, { 1.42, "Whoosh" }, { 1.58, "Strike" }, { 1.58, "Land" },
			},
			Keys = {
				{ T = 0 },
				at(0.1, BOXER),
				-- JAB (the Brutal Boxer's)
				{ T = 0.22, Joint_CorePos = { 0, 0.11, -0.15 }, Joint_Core = { -8, -18, 0 }, Joint_Legs = { 8, 18, 0 }, Joint_Head = { -10, 14, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 82, 0, 36 }, Sub_LeftArm_Fore = { 50, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				{ T = 0.3, Joint_CorePos = { 0, 0.08, -0.35 }, Joint_Core = { -10, -24, 0 }, Joint_Legs = { 10, 24, 0 }, Joint_Head = { -10, 16, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 100, 0, 22 }, Sub_LeftArm_Fore = { 8, 0, 0 }, Sub_Legs_L = { 22, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- the spin: turning away to the right, everything tucked
				{ T = 0.45, Joint_CorePos = { 0, 0.15, -0.4 }, Joint_Core = { -6, -90, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 40, 0, -30 }, Sub_RightArm_Fore = { 110, 0, 0 }, Joint_LeftArm = { 50, 0, 30 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
				-- back turned, the head whipping round first to find them
				{ T = 0.6, Joint_CorePos = { 0, 0.06, -0.4 }, Joint_Core = { -6, -180, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -6, -70, 0 }, Joint_RightArm = { 30, 0, 40 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 50, 0, 30 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- SPINNING BACKFIST: the right side comes round to them, the arm whipping out straight
				{ T = 0.72, Joint_CorePos = { 0, 0.28, -0.3 }, Joint_Core = { -8, -265, -6 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -6, -85, 0 }, Joint_RightArm = { 35, 0, 88 }, Sub_RightArm_Fore = { 55, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } },
				{ T = 0.86, Joint_CorePos = { 0, 0.15, -0.45 }, Joint_Core = { -6, -320, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -6, -40, 0 }, Joint_RightArm = { 30, 0, 60 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				{ T = 1.0, Joint_CorePos = { 0, 0.12, -0.6 }, Joint_Core = { -6, -360, 0 }, Joint_Legs = { 6, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				-- crouch to spring, both fists going up
				{ T = 1.2, Joint_CorePos = { 0, 0.1, -0.4 }, Joint_Core = { -14, -360, 0 }, Joint_Legs = { 14, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 165, 0, -10 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 165, 0, 10 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
				-- the LEAP: up and arched back, fists high
				{ T = 1.42, Joint_CorePos = { 0, 1.3, -0.9 }, Joint_Core = { 12, -360, 0 }, Joint_Legs = { -12, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 178, 0, -8 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 178, 0, 8 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
				-- DOUBLE HAMMERFIST: crashing down through them as it lands
				{ T = 1.58, Joint_CorePos = { 0, -0.47, -1.3 }, Joint_Core = { -38, -360, 0 }, Joint_Legs = { 30, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 80, 0, -14 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 80, 0, 14 }, Sub_LeftArm_Fore = { 10, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
				{ T = 1.8, Joint_CorePos = { 0, -0.59, -1.35 }, Joint_Core = { -42, -360, 0 }, Joint_Legs = { 32, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 45, 0, -18 }, Sub_RightArm_Fore = { 20, 0, 0 }, Joint_LeftArm = { 45, 0, 18 }, Sub_LeftArm_Fore = { 20, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
				-- and up, back into the guard
				{ T = 2.05, Joint_CorePos = { 0, 0.12, -0.9 }, Joint_Core = { -6, -370, 0 }, Joint_Legs = { 6, 10, 0 }, Joint_Head = { -10, 10, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 55, 0, 50 }, Sub_LeftArm_Fore = { 100, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				{ T = 2.3, Joint_Core = { 0, -360, 0 } },
			},
		},

		-- GROUND BREAKER (unlocked by beating the Abyssal Maw): a low kick to the legs, a
		-- rising knee, then up off both feet and down with both fists into the FLOOR: a
		-- shockwave that throws everything around it.
		Combo_GroundBreaker = {
			Duration = 2.3,
			Markers = { { 0.3, "Strike" }, { 0.48, "StepR" }, { 0.7, "Strike" }, { 0.95, "StepL" }, { 1.15, "Whoosh" }, { 1.32, "Strike" }, { 1.32, "Land" } },
			Keys = {
				{ T = 0 },
				at(0.1, BOXER),
				-- LOW KICK: the hips turn over, the shin chops into their legs
				at(0.3, BOXER, { Joint_CorePos = { 0, 0.05, -0.2 }, Joint_Core = { -4, 35, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -10, -25, 0 }, Joint_RightArm = { 20, 0, 30 }, Sub_RightArm_Fore = { 40, 0, 0 }, Sub_Legs_R = { 55, 0, 45 }, Sub_Legs_L = { -4, 0, 0 } }),
				at(0.48, BOXER, { Joint_CorePos = { 0, 0.1, -0.2 }, Joint_Core = { -6, 10, 0 }, Joint_Legs = { 6, -10, 0 } }),
				-- RISING KNEE, hands pulling their head down onto it
				at(0.7, BOXER, { Joint_CorePos = { 0, 0.1, -0.5 }, Joint_Core = { -16, 6, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_RightArm = { 110, 0, -30 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 110, 0, 30 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_R = { 100, 0, -12 }, Sub_Legs_L = { -6, 0, 0 } }),
				-- gather: both fists going up
				at(0.95, BOXER, { Joint_CorePos = { 0, 0.1, -0.4 }, Joint_Core = { -14, 0, 0 }, Joint_Legs = { 14, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 165, 0, -10 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 165, 0, 10 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }),
				-- off the floor
				at(1.15, BOXER, { Joint_CorePos = { 0, 1.6, -0.6 }, Joint_Core = { 10, 0, 0 }, Joint_Legs = { -10, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 178, 0, -8 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 178, 0, 8 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 25, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
				-- GROUND POUND: both fists into the floor as it lands
				at(1.32, BOXER, { Joint_CorePos = { 0, -1.0, -0.8 }, Joint_Core = { -62, 0, 0 }, Joint_Legs = { 50, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 55, 0, -12 }, Sub_RightArm_Fore = { 0, 0, 0 }, Joint_LeftArm = { 55, 0, 12 }, Sub_LeftArm_Fore = { 0, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
				at(1.6, BOXER, { Joint_CorePos = { 0, -1.02, -0.8 }, Joint_Core = { -63, 0, 0 }, Joint_Legs = { 51, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 54, 0, -14 }, Sub_RightArm_Fore = { 5, 0, 0 }, Joint_LeftArm = { 54, 0, 14 }, Sub_LeftArm_Fore = { 5, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
				at(1.95, BOXER, { Joint_CorePos = { 0, 0.12, -0.5 } }),
				{ T = 2.3 },
			},
		},
		-- AERIAL CRUSHER (a SIGNATURE; unlocked by beating the Mirror Warden): a jumping
		-- uppercut LAUNCHES them, it springs up after them, a flying knee in the air, then a
		-- two-fisted spike that smashes them back down, and it lands.
		Combo_AerialCrusher = {
			Duration = 2.0,
			Markers = { { 0.22, "StepR" }, { 0.36, "Strike" }, { 0.55, "Whoosh" }, { 0.72, "Strike" }, { 0.92, "Whoosh" }, { 1.08, "Strike" }, { 1.35, "Land" } },
			Keys = {
				{ T = 0 },
				at(0.1, BOXER),
				at(0.22, BOXER, with(B_DIP, { Joint_CorePos = { 0, 0, -0.3 } })),
				-- LAUNCHER: up off the dip, the rear fist driving straight up through the chin
				at(0.36, BOXER, { Joint_CorePos = { 0, 0.5, -0.45 }, Joint_Core = { 6, 25, 0 }, Joint_Legs = { -6, -25, 0 }, Joint_Head = { -4, -10, 0 }, Joint_RightArm = { 150, 0, -25 }, Sub_RightArm_Fore = { 35, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -25, 0, 0 } }),
				-- jump after them, the knee chambered
				at(0.55, BOXER, { Joint_CorePos = { 0, 1.4, -0.5 }, Joint_Core = { 4, 0, 0 }, Joint_Legs = { -4, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 100, 0, 30 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 100, 0, -30 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_R = { 85, 0, 0 }, Sub_Legs_L = { -10, 0, 0 } }),
				-- FLYING KNEE
				at(0.72, BOXER, { Joint_CorePos = { 0, 2.2, -0.6 }, Joint_Core = { -12, 0, 0 }, Joint_Legs = { 0, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 125, 0, -25 }, Sub_RightArm_Fore = { 70, 0, 0 }, Joint_LeftArm = { 125, 0, 25 }, Sub_LeftArm_Fore = { 70, 0, 0 }, Sub_Legs_R = { 115, 0, -10 }, Sub_Legs_L = { -15, 0, 0 } }),
				-- both fists up at the top of the jump
				at(0.92, BOXER, { Joint_CorePos = { 0, 2.4, -0.6 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { -14, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 178, 0, -8 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 178, 0, 8 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } }),
				-- SPIKE: the double fist smashes them back down
				at(1.08, BOXER, { Joint_CorePos = { 0, 1.7, -0.7 }, Joint_Core = { -35, 0, 0 }, Joint_Legs = { 30, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 75, 0, -14 }, Sub_RightArm_Fore = { 8, 0, 0 }, Joint_LeftArm = { 75, 0, 14 }, Sub_LeftArm_Fore = { 8, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }),
				-- land heavy, absorbing it
				at(1.35, BOXER, { Joint_CorePos = { 0, 0.01, -0.7 }, Joint_Core = { -22, 0, 0 }, Joint_Legs = { 22, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 40, 0, -20 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 40, 0, 20 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } }),
				at(1.7, BOXER, { Joint_CorePos = { 0, 0.12, -0.4 } }),
				{ T = 2.0 },
			},
		},
		-- TITAN COMBINATION (unlocked by beating the Scrap Titan; a heavyweight's combo):
		-- a wound-up right haymaker, a left uppercut to the body, then both fists clasped
		-- high and an axe-handle smash that cracks the floor.
		Combo_TitanCombination = {
			Duration = 2.6,
			Markers = { { 0.45, "StepR" }, { 0.72, "Strike" }, { 0.92, "Whoosh" }, { 1.1, "Strike" }, { 1.42, "Whoosh" }, { 1.7, "Strike" }, { 1.7, "Land" } },
			Keys = {
				{ T = 0 },
				at(0.15, BOXER),
				-- wind it all the way back
				at(0.45, BOXER, { Joint_CorePos = { 0, 0.21, 0.15 }, Joint_Core = { -4, 45, 0 }, Joint_Legs = { 4, -45, 0 }, Joint_Head = { -10, -30, 0 }, Joint_RightArm = { 95, 0, 60 }, Sub_RightArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }),
				-- HAYMAKER
				at(0.72, BOXER, { Joint_CorePos = { 0, 0.05, -0.5 }, Joint_Core = { -14, -45, 0 }, Joint_Legs = { 14, 45, 0 }, Joint_Head = { -10, 25, 0 }, Joint_RightArm = { 90, 0, -75 }, Sub_RightArm_Fore = { 25, 0, 0 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }),
				at(0.92, BOXER, { Joint_CorePos = { 0, 0, -0.45 }, Joint_Core = { -18, -25, 0 }, Joint_Legs = { 18, 25, 0 }, Joint_Head = { -12, 10, 0 }, Joint_RightArm = { 50, 0, -50 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 40, 0, 40 }, Sub_LeftArm_Fore = { 100, 0, 0 } }),
				-- LEFT UPPERCUT to the body
				at(1.1, BOXER, { Joint_CorePos = { 0, 0.12, -0.5 }, Joint_Core = { 0, -28, 0 }, Joint_Legs = { 0, 28, 0 }, Joint_Head = { -6, 10, 0 }, Joint_LeftArm = { 65, 0, 45 }, Sub_LeftArm_Fore = { 85, 0, 0 } }),
				-- fists clasped high
				at(1.42, BOXER, { Joint_CorePos = { 0, 0.25, -0.4 }, Joint_Core = { 12, 0, 0 }, Joint_Legs = { -12, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 172, 0, -18 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 172, 0, 18 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 16, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } }),
				-- AXE-HANDLE SMASH
				at(1.7, BOXER, { Joint_CorePos = { 0, -0.4, -0.9 }, Joint_Core = { -42, 0, 0 }, Joint_Legs = { 34, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 75, 0, -14 }, Sub_RightArm_Fore = { 5, 0, 0 }, Joint_LeftArm = { 75, 0, 14 }, Sub_LeftArm_Fore = { 5, 0, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } }),
				at(2.0, BOXER, { Joint_CorePos = { 0, -0.42, -0.9 }, Joint_Core = { -40, 0, 0 }, Joint_Legs = { 32, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 60, 0, -16 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 60, 0, 16 }, Sub_LeftArm_Fore = { 10, 0, 0 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } }),
				at(2.35, BOXER, { Joint_CorePos = { 0, 0.12, -0.5 } }),
				{ T = 2.6 },
			},
		},

		-- HIGH GUARD (the combat brain covering up): elbows in, forearms stood up in front of
		-- the face, chin down behind them, knees soft; it breathes behind it, then opens up.
		Guard_Hold = {
			Duration = 1.0,
			Markers = { { 0.12, "StepL" } },
			Keys = {
				{ T = 0 },
				{ T = 0.12, Joint_CorePos = { 0, -0.2, 0.1 }, Joint_Core = { -10, -6, 0 }, Joint_Legs = { 10, 6, 0 }, Joint_Head = { -16, 6, 0 }, Joint_RightArm = { 62, 0, -48 }, Sub_RightArm_Fore = { 125, 0, 0 }, Joint_LeftArm = { 66, 0, 46 }, Sub_LeftArm_Fore = { 122, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
				{ T = 0.5, Joint_CorePos = { 0, -0.28, 0.1 }, Joint_Core = { -13, -6, 0 }, Joint_Legs = { 13, 6, 0 }, Joint_Head = { -18, 6, 0 }, Joint_RightArm = { 64, 0, -50 }, Sub_RightArm_Fore = { 128, 0, 0 }, Joint_LeftArm = { 68, 0, 48 }, Sub_LeftArm_Fore = { 125, 0, 0 }, Sub_Legs_L = { 20, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } },
				{ T = 0.85, Joint_CorePos = { 0, -0.2, 0.1 }, Joint_Core = { -10, -6, 0 }, Joint_Legs = { 10, 6, 0 }, Joint_Head = { -16, 6, 0 }, Joint_RightArm = { 62, 0, -48 }, Sub_RightArm_Fore = { 125, 0, 0 }, Joint_LeftArm = { 66, 0, 46 }, Sub_LeftArm_Fore = { 122, 0, 0 }, Sub_Legs_L = { 18, 0, 0 }, Sub_Legs_R = { -12, 0, 0 } },
				{ T = 1.0 },
			},
		},

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
	-- Four-legged bodies (Sub_Legs_FL/FR/BL/BR; +X swings a leg forward; Joint_Core +X
	-- rears the front up). The shared beast moves are in Common (BEAST).
	Quadruped = {
		-- PREDATOR RUSH: crouch, eyes fixed on them; spring in (the server carries the body)
		-- with the right forepaw raking across their face, bite, bite again and wrench, then
		-- rear up on the hind legs and slam both forepaws down through them.
		Combo_PredatorRush = {
			Duration = 1.9,
			Markers = {
				{ 0.2, "StepL" }, { 0.3, "Whoosh" }, { 0.42, "Strike" }, { 0.42, "Land" }, { 0.6, "Whoosh" }, { 0.7, "JawSnap" },
				{ 0.9, "Whoosh" }, { 1.0, "JawSnap" }, { 1.25, "StepR" }, { 1.45, "Strike" }, { 1.45, "Land" },
			},
			Keys = {
				{ T = 0 },
				-- the crouch: low, coiled on the hind legs, head level and still
				{ T = 0.2, Joint_CorePos = { 0, 0.19, 0.35 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { 6, 0, 0 }, Sub_Head_Jaw = { -6, 0, 0 }, Sub_Legs_FL = { -18, 0, 0 }, Sub_Legs_FR = { -18, 0, 0 }, Sub_Legs_BL = { 30, 0, 0 }, Sub_Legs_BR = { 30, 0, 0 }, Joint_Tail = { 10, 0, 0 } },
				-- spring, the right forepaw cocked high
				{ T = 0.3, Joint_CorePos = { 0, 0.6, -0.3 }, Joint_Core = { 12, 0, -6 }, Joint_Head = { 4, -10, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 50, 0, 0 }, Sub_Legs_FR = { 110, 0, 0 }, Sub_Legs_BL = { -40, 0, 0 }, Sub_Legs_BR = { -40, 0, 0 }, Joint_Tail = { -10, 0, 0 } },
				-- RAKE: the paw comes down and across through them as it lands
				{ T = 0.42, Joint_CorePos = { 0, 0.39, -0.7 }, Joint_Core = { -10, -16, 8 }, Joint_Head = { 14, 16, 0 }, Sub_Head_Jaw = { -36, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 60, -30, -20 }, Sub_Legs_BL = { -14, 0, 0 }, Sub_Legs_BR = { -14, 0, 0 }, Joint_Tail = { 0, 20, 0 } },
				-- jaws wide, reaching in
				{ T = 0.6, Joint_CorePos = { 0, 0.27, -0.6 }, Joint_Core = { -14, 6, 0 }, Joint_Head = { 10, -6, 0 }, Sub_Head_Jaw = { -50, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 26, 0, 0 }, Sub_Legs_BL = { -12, 0, 0 }, Sub_Legs_BR = { -12, 0, 0 }, Joint_Tail = { 0, -10, 0 } },
				-- BITE
				{ T = 0.7, Joint_CorePos = { 0, 0.23, -1.0 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { 75, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 48, 0, 0 }, Sub_Legs_FR = { 48, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 }, Joint_Tail = { 0, 0, 0 } },
				{ T = 0.9, Joint_CorePos = { 0, 0.25, -0.55 }, Joint_Core = { -12, -10, -4 }, Joint_Head = { 6, 14, 0 }, Sub_Head_Jaw = { -50, 0, 0 }, Sub_Legs_FL = { 28, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { -12, 0, 0 }, Sub_Legs_BR = { -12, 0, 0 }, Joint_Tail = { 0, 10, 0 } },
				-- BITE and WRENCH: clamp and twist the head
				{ T = 1.0, Joint_CorePos = { 0, 0.23, -1.0 }, Joint_Core = { -38, 10, 6 }, Joint_Head = { 75, -20, -14 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 48, 0, 0 }, Sub_Legs_FR = { 48, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 }, Joint_Tail = { 0, -14, 0 } },
				-- rear up on the hind legs, forepaws high
				{ T = 1.25, Joint_CorePos = { 0, 0.28, 0.3 }, Joint_Core = { 35, 0, 0 }, Joint_Head = { 24, 0, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 80, 0, 0 }, Sub_Legs_FR = { 80, 0, 0 }, Sub_Legs_BL = { -35, 0, 0 }, Sub_Legs_BR = { -35, 0, 0 }, Joint_Tail = { -20, 0, 0 } },
				-- SLAM: both forepaws down through them
				{ T = 1.45, Joint_CorePos = { 0, -0.05, -1.0 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { 10, 0, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 60, 0, 0 }, Sub_Legs_FR = { 60, 0, 0 }, Sub_Legs_BL = { -6, 0, 0 }, Sub_Legs_BR = { -6, 0, 0 }, Joint_Tail = { 10, 0, 0 } },
				{ T = 1.65, Joint_CorePos = { 0, 0.19, -0.5 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { 0, 0, 0 }, Sub_Head_Jaw = { -10, 0, 0 }, Sub_Legs_FL = { 20, 0, 0 }, Sub_Legs_FR = { 20, 0, 0 }, Sub_Legs_BL = { -4, 0, 0 }, Sub_Legs_BR = { -4, 0, 0 } },
				{ T = 1.9 },
			},
		},
		-- BEASTLY ASSAULT (four legs, no head needed): drop the shoulder and RAM them, rear
		-- and rake with the left forepaw, then the right, spin round and BUCK both hind legs
		-- back into them.
		Combo_BeastlyAssault = {
			Duration = 2.3,
			Markers = { { 0.15, "StepL" }, { 0.35, "Strike" }, { 0.35, "Land" }, { 0.6, "Strike" }, { 0.85, "Strike" }, { 1.15, "StepR" }, { 1.45, "Strike" }, { 1.95, "Land" } },
			Keys = {
				{ T = 0 },
				{ T = 0.15, Joint_CorePos = { 0, 0.15, 0.3 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { 20, 0, 0 }, Sub_Legs_FL = { -15, 0, 0 }, Sub_Legs_FR = { -15, 0, 0 }, Sub_Legs_BL = { 25, 0, 0 }, Sub_Legs_BR = { 25, 0, 0 } },
				-- RAM
				{ T = 0.35, Joint_CorePos = { 0, 0.25, -1.0 }, Joint_Core = { -22, 0, 0 }, Joint_Head = { 30, 0, 0 }, Sub_Legs_FL = { 40, 0, 0 }, Sub_Legs_FR = { 40, 0, 0 }, Sub_Legs_BL = { 10, 0, 0 }, Sub_Legs_BR = { 10, 0, 0 } },
				-- LEFT RAKE, rearing
				{ T = 0.6, Joint_CorePos = { 0, 0.23, -0.5 }, Joint_Core = { 12, 15, -8 }, Joint_Head = { 10, -10, 0 }, Sub_Legs_FL = { 95, 25, 20 }, Sub_Legs_FR = { 10, 0, 0 }, Sub_Legs_BL = { -12, 0, 0 }, Sub_Legs_BR = { -12, 0, 0 }, Joint_Tail = { 0, -20, 0 } },
				-- RIGHT RAKE
				{ T = 0.85, Joint_CorePos = { 0, 0.23, -0.5 }, Joint_Core = { 12, -15, 8 }, Joint_Head = { 10, 10, 0 }, Sub_Legs_FR = { 95, -25, -20 }, Sub_Legs_FL = { 10, 0, 0 }, Sub_Legs_BL = { -12, 0, 0 }, Sub_Legs_BR = { -12, 0, 0 }, Joint_Tail = { 0, 20, 0 } },
				-- spin round, looking back over the shoulder
				{ T = 1.15, Joint_CorePos = { 0, -0.06, -0.3 }, Joint_Core = { 0, -150, 0 }, Joint_Head = { 0, -40, 0 }, Joint_Tail = { 0, 30, 0 } },
				-- BUCK: hindquarters up, both hind legs driven back into them
				{ T = 1.45, Joint_CorePos = { 0, 0.22, -0.3 }, Joint_Core = { 28, -180, 0 }, Joint_Head = { -10, -30, 0 }, Sub_Legs_BL = { -80, 0, 0 }, Sub_Legs_BR = { -80, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Joint_Tail = { 30, 0, 0 } },
				{ T = 1.7, Joint_CorePos = { 0, -0.06, -0.3 }, Joint_Core = { 0, -280, 0 }, Joint_Head = { 0, 20, 0 } },
				{ T = 1.95, Joint_CorePos = { 0, 0.1, -0.2 }, Joint_Core = { -4, -360, 0 } },
				{ T = 2.3, Joint_Core = { 0, -360, 0 } },
			},
		},
		-- PREDATOR COUNTER (React; four legs and a head): hop sideways out of the attack (the
		-- server slides it, untouchable), then pounce on them jaws-first and shake.
		Combo_PredatorCounter = {
			Duration = 1.7,
			Markers = { { 0.2, "StepR" }, { 0.45, "Whoosh" }, { 0.55, "JawSnap" }, { 0.8, "Grind" }, { 1.05, "Rip" } },
			Keys = {
				{ T = 0 },
				{ T = 0.2, Joint_CorePos = { 0.8, 0.4, 0.1 }, Joint_Core = { 6, 20, -10 }, Joint_Head = { 0, -20, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { -20, 0, 0 }, Sub_Legs_BR = { -20, 0, 0 } },
				{ T = 0.38, Joint_CorePos = { 0.3, 0.15, 0.2 }, Joint_Core = { -8, -10, 0 }, Joint_Head = { 10, 10, 0 }, Sub_Head_Jaw = { -20, 0, 0 }, Sub_Legs_FL = { -10, 0, 0 }, Sub_Legs_FR = { -10, 0, 0 }, Sub_Legs_BL = { 20, 0, 0 }, Sub_Legs_BR = { 20, 0, 0 } },
				{ T = 0.45, Joint_CorePos = { 0.1, 0.3, -0.6 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { 40, 0, 0 }, Sub_Head_Jaw = { -50, 0, 0 }, Sub_Legs_FL = { 40, 0, 0 }, Sub_Legs_FR = { 40, 0, 0 }, Sub_Legs_BL = { 0, 0, 0 }, Sub_Legs_BR = { 0, 0, 0 } },
				-- the POUNCE BITE (the measured Predator Rush bite)
				{ T = 0.55, Joint_CorePos = { 0, 0.23, -1.0 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { 75, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 48, 0, 0 }, Sub_Legs_FR = { 48, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 } },
				-- shake one way...
				{ T = 0.8, Joint_CorePos = { 0, 0.23, -1.0 }, Joint_Core = { -36, 14, 8 }, Joint_Head = { 75, -24, -14 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 48, 0, 0 }, Sub_Legs_FR = { 44, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 } },
				-- ...and fling them the other
				{ T = 1.05, Joint_CorePos = { 0, 0.23, -0.9 }, Joint_Core = { -30, -20, -8 }, Joint_Head = { 60, 30, 14 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 44, 0, 0 }, Sub_Legs_FR = { 48, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 } },
				{ T = 1.35, Joint_CorePos = { 0, 0.19, -0.4 }, Joint_Core = { -8, 0, 0 }, Joint_Head = { 4, 0, 0 }, Sub_Head_Jaw = { -8, 0, 0 }, Sub_Legs_FL = { 16, 0, 0 }, Sub_Legs_FR = { 16, 0, 0 }, Sub_Legs_BL = { -4, 0, 0 }, Sub_Legs_BR = { -4, 0, 0 } },
				{ T = 1.7 },
			},
		},
	},
}

-- MASTERED combos (Combo Mastery: the brain switches to these once the base combo has
-- finished enough fights; Config Moveset Unlock.Mastery / Replaces).
-- BRUTAL BOXER II: the four punches, then a dip to the body - a lead hook into the ribs -
-- and the overhand off it.
do
	local base = POSES.Biped.Combo_BrutalBoxer
	local b = {}
	for _, key in base.Keys do
		b[key.T] = key
	end
	POSES.Biped.Combo_BrutalBoxerII = extend(base, 1.1, 2.6, {
		{ T = 1.22, Joint_CorePos = { 0, 0.05, -0.35 }, Joint_Core = { -16, -18, 4 }, Joint_Legs = { 16, 18, -4 }, Joint_Head = { -12, 10, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 50, 0, 10 }, Sub_LeftArm_Fore = { 80, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
		{ T = 1.32, Joint_CorePos = { 0, 0, -0.45 }, Joint_Core = { -20, -38, 6 }, Joint_Legs = { 20, 38, -6 }, Joint_Head = { -12, 18, 0 }, Joint_RightArm = { 50, 0, -55 }, Sub_RightArm_Fore = { 105, 0, 0 }, Joint_LeftArm = { 58, 0, 42 }, Sub_LeftArm_Fore = { 70, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } },
		table.clone(b[1.4]), table.clone(b[1.62]), table.clone(b[1.85]), table.clone(b[2.15]), { T = 2.6 },
	}, {
		{ 1.22, "Whoosh" }, { 1.32, "Strike" }, { 1.32, "StepL" }, { 1.6, "Whoosh" }, { 1.84, "Strike" }, { 1.84, "StepL" },
	})
	-- (the borrowed overhand keys, moved later in time)
	local keys = POSES.Biped.Combo_BrutalBoxerII.Keys
	keys[#keys - 4].T, keys[#keys - 3].T, keys[#keys - 2].T, keys[#keys - 1].T = 1.6, 1.84, 2.05, 2.35
end
-- PREDATOR RUSH II: after the slam, nose down onto them where they fell, bite, and rip away.
POSES.Quadruped.Combo_PredatorRushII = extend(POSES.Quadruped.Combo_PredatorRush, 1.45, 2.6, {
	{ T = 1.65, Joint_CorePos = { 0, 0.23, -1.2 }, Joint_Core = { -40, 0, 0 }, Joint_Head = { 85, 0, 0 }, Sub_Head_Jaw = { -50, 0, 0 }, Sub_Legs_FL = { 50, 0, 0 }, Sub_Legs_FR = { 50, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 } },
	{ T = 1.82, Joint_CorePos = { 0, 0.23, -1.2 }, Joint_Core = { -42, 0, 0 }, Joint_Head = { 90, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 50, 0, 0 }, Sub_Legs_FR = { 50, 0, 0 }, Sub_Legs_BL = { 14, 0, 0 }, Sub_Legs_BR = { 14, 0, 0 } },
	{ T = 2.05, Joint_CorePos = { 0, 0.25, -0.5 }, Joint_Core = { -10, 25, 0 }, Joint_Head = { 20, 40, 10 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 20, 0, 0 }, Sub_Legs_FR = { 20, 0, 0 }, Sub_Legs_BL = { -4, 0, 0 }, Sub_Legs_BR = { -4, 0, 0 } },
	{ T = 2.35, Joint_CorePos = { 0, 0.19, -0.3 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { 0, 0, 0 }, Sub_Head_Jaw = { -6, 0, 0 } },
	{ T = 2.6 },
}, {
	{ 1.65, "Whoosh" }, { 1.82, "JawSnap" }, { 2.05, "Rip" },
})

------------------------------------------------------------------------------------------
-- NIGHTMARE UNDERGROUND (Config.Underground.Fight Moves.Biped): ONE strike per clip, thrown
-- by the player and chained by input. Heavyweight: each one shifts the weight before it goes,
-- stops dead on the contact (the server's hit time), carries on past it (PoseTools overshoot)
-- and comes back to the guard. Contact frames: jab 0.2, cross 0.26, hook 0.3, uppercut and
-- liver 0.32, body blast 0.42, launcher 0.44, overhand 0.5.
------------------------------------------------------------------------------------------
local UG = {
	-- the lead hand: a small step in behind it, snapped out and straight back
	UG_Jab = {
		Duration = 0.62,
		Markers = { { 0.13, "Whoosh" }, { 0.2, "Strike" }, { 0.2, "StepL" } },
		Keys = {
			pose(0),
			pose(0.1, { Joint_CorePos = { 0, 0.1, -0.08 }, Joint_Core = { -8, -8, 0 }, Joint_Legs = { 8, 8, 0 }, Joint_LeftArm = { 66, 0, 42 }, Sub_LeftArm_Fore = { 78, 0, 0 } }),
			blow(0.2, P_JAB),
			pose(0.32, P_JAB_BACK),
			pose(0.46, GUARD_REST),
			pose(0.62),
		},
	},
	-- the rear hand down the middle: the right hip turns over and the weight goes onto the lead leg
	UG_Cross = {
		Duration = 0.72,
		Markers = { { 0.18, "Whoosh" }, { 0.26, "Strike" }, { 0.26, "StepR" } },
		Keys = {
			pose(0),
			pose(0.12, P_CROSS_LOAD),
			blow(0.26, P_CROSS),
			pose(0.4, { Joint_CorePos = { 0, 0.15, -0.3 }, Joint_Core = { -8, 14, 0 }, Joint_Legs = { 8, -14, 0 } }),
			pose(0.56, GUARD_REST),
			pose(0.72),
		},
	},
	-- the lead hook: the hips wind right, then the whole trunk turns through it, elbow level
	UG_HookL = {
		Duration = 0.8,
		Markers = { { 0.22, "Whoosh" }, { 0.3, "Strike" }, { 0.3, "StepL" } },
		Keys = {
			pose(0),
			pose(0.15, P_HOOK_LOAD),
			blow(0.3, P_HOOK),
			pose(0.42, P_HOOK_FOLLOW),
			pose(0.6, { Joint_CorePos = { 0, 0.1, -0.1 } }),
			pose(0.8),
		},
	},
	-- the rear uppercut out of a dip: legs first, then the hip, then the fist up the middle
	UG_Uppercut = {
		Duration = 0.85,
		Markers = { { 0.24, "Whoosh" }, { 0.32, "Strike" }, { 0.32, "StepR" } },
		Keys = {
			pose(0),
			pose(0.16, P_UPPER_LOAD),
			blow(0.32, P_UPPER),
			pose(0.46, { Joint_CorePos = { 0, 0.2, -0.25 }, Joint_Core = { 4, 20, 0 }, Joint_Legs = { -4, -20, 0 }, Joint_RightArm = { 118, 0, -32 }, Sub_RightArm_Fore = { 72, 0, 0 } }),
			pose(0.66, GUARD_REST),
			pose(0.85),
		},
	},
	-- level change, the lead hand dug in under the ribs
	UG_LiverHook = {
		Duration = 0.85,
		Markers = { { 0.24, "Whoosh" }, { 0.32, "Strike" }, { 0.32, "StepL" } },
		Keys = {
			pose(0),
			pose(0.16, P_BODY_LOAD),
			blow(0.32, P_BODY),
			pose(0.46, { Joint_CorePos = { 0, -0.15, -0.3 }, Joint_Core = { -14, -38, 4 }, Joint_Legs = { 14, 38, -4 }, Joint_LeftArm = { 50, 0, 50 }, Sub_LeftArm_Fore = { 86, 0, 0 } }),
			pose(0.66, GUARD_REST),
			pose(0.85),
		},
	},
	-- POWER: rocks back to load, the rear hand comes over the top and everything falls through it
	UG_Overhand = {
		Duration = 1.15,
		Markers = { { 0.4, "Whoosh" }, { 0.5, "Strike" }, { 0.5, "StepL" } },
		Keys = {
			pose(0),
			pose(0.12, { Joint_CorePos = { 0, 0.08, 0.18 }, Joint_Core = { 4, -14, 0 }, Joint_Legs = { -4, 14, 0 } }),
			pose(0.32, P_OVER_LOAD),
			blow(0.5, P_OVERHAND),
			pose(0.68, P_OVER_FOLLOW),
			pose(0.9, { Joint_CorePos = { 0, 0.1, -0.35 } }),
			pose(1.15),
		},
	},
	-- POWER: sunk all the way down, coiled, then exploding up through them onto the toes
	UG_Launcher = {
		Duration = 1.1,
		Markers = { { 0.14, "StepL" }, { 0.36, "Whoosh" }, { 0.44, "Strike" }, { 0.44, "StepR" } },
		Keys = {
			pose(0),
			pose(0.14, { Joint_CorePos = { 0, -0.55, -0.1 }, Joint_Core = { -26, -22, 0 }, Joint_Legs = { 26, 22, 0 }, Joint_Head = { -10, 8, 0 }, Joint_RightArm = { 30, 0, -40 }, Sub_RightArm_Fore = { 115, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
			pose(0.3, { Joint_CorePos = { 0, -0.66, -0.15 }, Joint_Core = { -28, -30, 0 }, Joint_Legs = { 28, 30, 0 }, Joint_Head = { -10, 12, 0 }, Joint_RightArm = { 20, 0, -36 }, Sub_RightArm_Fore = { 120, 0, 0 }, Sub_Legs_L = { 44, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } }),
			blow(0.44, { Joint_CorePos = { 0, 0.45, -0.45 }, Joint_Core = { 8, 34, 0 }, Joint_Legs = { -8, -34, 0 }, Joint_Head = { 6, -12, 0 }, Joint_RightArm = { 150, 0, -20 }, Sub_RightArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } }),
			pose(0.6, { Joint_CorePos = { 0, 0.35, -0.35 }, Joint_Core = { 12, 40, 0 }, Joint_Legs = { -12, -40, 0 }, Joint_RightArm = { 165, 0, -15 }, Sub_RightArm_Fore = { 30, 0, 0 } }),
			pose(0.85, GUARD_REST),
			pose(1.1),
		},
	},
	-- POWER: dropped level, the rear hand driven straight through the stomach
	UG_BodyBlast = {
		Duration = 1.05,
		Markers = { { 0.2, "StepL" }, { 0.34, "Whoosh" }, { 0.42, "Strike" }, { 0.42, "StepR" } },
		Keys = {
			pose(0),
			pose(0.22, { Joint_CorePos = { 0, -0.3, 0 }, Joint_Core = { -16, -16, 0 }, Joint_Legs = { 16, 16, 0 }, Joint_Head = { -8, 8, 0 }, Joint_RightArm = { 40, 0, -45 }, Sub_RightArm_Fore = { 110, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }),
			blow(0.42, { Joint_CorePos = { 0, -0.45, -0.6 }, Joint_Core = { -24, 30, 0 }, Joint_Legs = { 24, -30, 0 }, Joint_Head = { -8, -10, 0 }, Joint_RightArm = { 70, 0, -18 }, Sub_RightArm_Fore = { 12, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -26, 0, 0 } }),
			pose(0.6, { Joint_CorePos = { 0, -0.45, -0.7 }, Joint_Core = { -26, 38, 0 }, Joint_Legs = { 26, -38, 0 }, Joint_RightArm = { 60, 0, -30 }, Sub_RightArm_Fore = { 30, 0, 0 } }),
			pose(0.8, { Joint_CorePos = { 0, -0.1, -0.2 } }),
			pose(1.05),
		},
	},
	-- PARRIED: the strike knocked away, the arms flung wide, it reels a step back open
	UG_Parried = {
		Duration = 0.7,
		Markers = { { 0.3, "StepR" } },
		Keys = {
			pose(0),
			{ T = 0.08, Ease = "Snap", Joint_CorePos = { 0, 0.05, 0.4 }, Joint_Core = { 14, 18, 0 }, Joint_Legs = { -6, -10, 0 }, Joint_Head = { -14, 10, 0 }, Joint_RightArm = { 30, 0, -80 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 80, 0, 70 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } },
			pose(0.3, { Joint_CorePos = { 0, -0.1, 0.5 }, Joint_Core = { 6, 8, 0 }, Joint_Legs = { -2, -6, 0 }, Joint_RightArm = { 30, 0, -60 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 50, 0, 60 }, Sub_LeftArm_Fore = { 60, 0, 0 } }),
			pose(0.7),
		},
	},
	-- FEINT: the power shot's load pulled back into the stance before it goes
	UG_Feint = {
		Duration = 0.45,
		Curve = "Spline",
		Keys = {
			pose(0, P_OVER_LOAD),
			pose(0.18, { Joint_CorePos = { 0, 0.1, 0.15 }, Joint_Core = { 4, -8, 0 }, Joint_Legs = { -4, 8, 0 } }),
			pose(0.45),
		},
	},
	-- VICTORY (the winner, over a fighter it has stopped): both fists thrown up, chest out,
	-- head back and roaring; pumped twice, turning to the crowd; back to its stance
	UG_Victory = {
		Duration = 2.6,
		Curve = "Spline",
		Markers = { { 0.5, "StepL" }, { 1.25, "StepR" } },
		Keys = {
			pose(0),
			pose(0.22, { Joint_CorePos = { 0, 0.02, 0.05 }, Joint_Core = { -10, 0, 0 }, Joint_Legs = { 10, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 40, 0, -20 }, Sub_RightArm_Fore = { 110, 0, 0 }, Joint_LeftArm = { 40, 0, 20 }, Sub_LeftArm_Fore = { 110, 0, 0 } }),
			pose(0.5, { Joint_CorePos = { 0, 0.25, 0.1 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { -6, 0, 0 }, Joint_Head = { 22, 0, 0 }, Sub_Head_Jaw = { -40, 0, 0 }, Joint_RightArm = { 165, 0, 26 }, Sub_RightArm_Fore = { 18, 0, 0 }, Joint_LeftArm = { 165, 0, -26 }, Sub_LeftArm_Fore = { 18, 0, 0 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } }),
			pose(0.9, { Joint_CorePos = { 0, 0.05, 0.05 }, Joint_Core = { 6, 12, 0 }, Joint_Legs = { -2, -12, 0 }, Joint_Head = { 10, 8, 0 }, Sub_Head_Jaw = { -14, 0, 0 }, Joint_RightArm = { 138, 0, 20 }, Sub_RightArm_Fore = { 62, 0, 0 }, Joint_LeftArm = { 138, 0, -20 }, Sub_LeftArm_Fore = { 62, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } }),
			pose(1.25, { Joint_CorePos = { 0, 0.28, 0.1 }, Joint_Core = { 16, 22, 0 }, Joint_Legs = { -6, -22, 0 }, Joint_Head = { 24, 10, 0 }, Sub_Head_Jaw = { -44, 0, 0 }, Joint_RightArm = { 168, 0, 28 }, Sub_RightArm_Fore = { 14, 0, 0 }, Joint_LeftArm = { 168, 0, -28 }, Sub_LeftArm_Fore = { 14, 0, 0 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } }),
			pose(1.65, { Joint_CorePos = { 0, 0.05, 0.05 }, Joint_Core = { 6, -14, 0 }, Joint_Legs = { -2, 14, 0 }, Joint_Head = { 10, -10, 0 }, Sub_Head_Jaw = { -14, 0, 0 }, Joint_RightArm = { 138, 0, 20 }, Sub_RightArm_Fore = { 62, 0, 0 }, Joint_LeftArm = { 138, 0, -20 }, Sub_LeftArm_Fore = { 62, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } }),
			pose(2.0, { Joint_CorePos = { 0, 0.26, 0.1 }, Joint_Core = { 14, -20, 0 }, Joint_Legs = { -6, 20, 0 }, Joint_Head = { 22, -10, 0 }, Sub_Head_Jaw = { -40, 0, 0 }, Joint_RightArm = { 165, 0, 26 }, Sub_RightArm_Fore = { 18, 0, 0 }, Joint_LeftArm = { 165, 0, -26 }, Sub_LeftArm_Fore = { 18, 0, 0 }, Sub_Legs_L = { 6, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } }),
			pose(2.35, { Joint_CorePos = { 0, 0.08, 0.02 }, Joint_Core = { -2, -6, 0 }, Joint_Legs = { 2, 6, 0 } }),
			pose(2.6),
		},
	},
}
local UGPoseTools = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PoseTools"))
for name, def in UG do
	if name ~= "UG_Feint" and name ~= "UG_Victory" then
		POSES.Common[name] = UGPoseTools.Punch(def, 0.3)
	else
		POSES.Common[name] = def
	end
end
-- LOW GUARD (Underground: guard + pulling back): elbows clamped to the ribs, forearms across
-- the stomach, sunk and bent over it, chin tucked (NightmareAnimator plays Keys[3] while held)
local LOW_GUARD = { Joint_CorePos = { 0, -0.4, 0.1 }, Joint_Core = { -18, -6, 0 }, Joint_Legs = { 18, 6, 0 }, Joint_Head = { -22, 6, 0 }, Joint_RightArm = { 28, 0, -30 }, Sub_RightArm_Fore = { 120, 0, 0 }, Joint_LeftArm = { 32, 0, 28 }, Sub_LeftArm_Fore = { 118, 0, 0 }, Sub_Legs_L = { 24, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }
POSES.Common.Guard_Low = { Duration = 1.0, Keys = { { T = 0 }, at(0.12, LOW_GUARD), at(0.5, LOW_GUARD), { T = 1.0 } } }

for name, def in GYM do
	POSES.Common[name] = def
end
for name, def in BEAST do
	POSES.Common[name] = def
end
for name, def in ABILITY do
	POSES.Common[name] = def
end
-- (arm abilities: the left-arm version)
for _, id in { "RustySlash", "TentacleLash", "DemonRend", "MagnetPull", "HammerSlam", "MeteorFist" } do
	POSES.Common["Ability_" .. id .. "_Left"] = mirrored(ABILITY["Ability_" .. id])
end
for name, def in ULTIMATE do
	POSES.Common[name] = def
end
-- (every ability and Ultimate on a four-legged body: its quadruped variant, found before Common)
local RING_CLIPS = { Guard_Crumble = true, Slip_R = true, Slip_L = true, RollUnder = true, PullBack = true, Gym_SlipCounter = true, Gym_RollHook = true, Gym_PullCounter = true, Gym_DuckUpper = true, Gym_Weave = true, UG_Parried = true, UG_Feint = true, UG_Victory = true }
for name, def in POSES.Common do
	if name:sub(1, 8) == "Ability_" or name:sub(1, 9) == "Ultimate_" or RING_CLIPS[name] then
		POSES.Quadruped[name] = forQuadruped(def)
	end
end

------------------------------------------------------------------------------------------
-- THE BASIC THREE (Config.Nightmare.Combo: a body's plainest attack): jab, cross, hook
------------------------------------------------------------------------------------------
POSES.Common.Combo1 = {
	Duration = 0.55,
	Curve = "Spline",
	Markers = { { 0.14, "Whoosh" }, { 0.22, "Hit" } },
	Keys = { pose(0), pose(0.08), blow(0.22, P_JAB), pose(0.36, P_JAB_BACK), pose(0.55) },
}
POSES.Common.Combo2 = {
	Duration = 0.63,
	Curve = "Spline",
	Markers = { { 0.16, "Whoosh" }, { 0.25, "Hit" }, { 0.25, "StepR" } },
	Keys = { pose(0), pose(0.1, P_CROSS_LOAD), blow(0.25, P_CROSS), pose(0.42, { Joint_CorePos = { 0, 0.15, -0.25 }, Joint_Core = { -8, 14, 0 }, Joint_Legs = { 8, -14, 0 } }), pose(0.63) },
}
POSES.Common.Combo3 = {
	Duration = 1.0,
	Curve = "Spline",
	Markers = { { 0.24, "Whoosh" }, { 0.35, "Hit" }, { 0.35, "StepL" } },
	Keys = { pose(0), pose(0.18, P_HOOK_LOAD), blow(0.35, P_HOOK), pose(0.52, P_HOOK_FOLLOW), pose(0.78, GUARD_REST), pose(1.0) },
}
-- four legs: forepaw, other forepaw, and a lunge with the teeth
local function rake(t: number, side: number, out: number, up: number, extra: boolean?)
	local lead, other = side > 0 and "Sub_Legs_FR" or "Sub_Legs_FL", side > 0 and "Sub_Legs_FL" or "Sub_Legs_FR"
	return { T = t, Ease = extra and "Snap" or nil, Stop = extra or nil, Joint_CorePos = { 0, up * 0.3, -0.5 * up }, Joint_Core = { 8 * up, 12 * side, 0 }, Joint_Head = { -8, -14 * side, 0 }, [lead] = { 80 * up, 0, out * side }, [other] = { 8, 0, 0 }, Sub_Legs_BL = { -6, 0, 0 }, Sub_Legs_BR = { -6, 0, 0 } }
end
POSES.Quadruped.Combo1 = {
	Duration = 0.55,
	Curve = "Spline",
	Markers = { { 0.14, "Whoosh" }, { 0.22, "Hit" } },
	Keys = { { T = 0 }, rake(0.12, 1, 30, 1), rake(0.22, 1, -30, 0.7, true), { T = 0.55 } },
}
POSES.Quadruped.Combo2 = {
	Duration = 0.63,
	Curve = "Spline",
	Markers = { { 0.16, "Whoosh" }, { 0.25, "Hit" } },
	Keys = { { T = 0 }, rake(0.14, -1, 30, 1), rake(0.25, -1, -30, 0.7, true), { T = 0.63 } },
}
POSES.Quadruped.Combo3 = {
	Duration = 1.0,
	Curve = "Spline",
	Markers = { { 0.24, "Whoosh" }, { 0.35, "Hit" }, { 0.35, "JawSnap" } },
	Keys = {
		{ T = 0 },
		{ T = 0.2, Joint_CorePos = { 0, -0.1, 0.45 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { -22, 0, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { -14, 0, 0 }, Sub_Legs_FR = { -14, 0, 0 }, Sub_Legs_BL = { 16, 0, 0 }, Sub_Legs_BR = { 16, 0, 0 } },
		{ T = 0.35, Ease = "Snap", Stop = true, Joint_CorePos = { 0, 0.05, -1.0 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Head_Jaw = { 4, 0, 0 }, Sub_Legs_FL = { 34, 0, 0 }, Sub_Legs_FR = { 34, 0, 0 }, Sub_Legs_BL = { -24, 0, 0 }, Sub_Legs_BR = { -24, 0, 0 } },
		{ T = 0.6, Joint_CorePos = { 0, 0, -0.4 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { 4, 0, 0 } },
		{ T = 1.0 },
	},
}

------------------------------------------------------------------------------------------
-- THE FIGHTING STANCE (attribute FightStance, while it has someone to fight): every strike
-- starts from and comes back to this, so the hands never drop between exchanges.
------------------------------------------------------------------------------------------
POSES.Stance = {
	Biped = BOXER,
	Floating = { Joint_CorePos = { 0, 0, 0 }, Joint_Core = { -6, -10, 0 }, Joint_Head = { -8, 10, 0 }, Joint_RightArm = { 50, 0, -50 }, Sub_RightArm_Fore = { 95, 0, 0 }, Joint_LeftArm = { 55, 0, 45 }, Sub_LeftArm_Fore = { 95, 0, 0 } },
	-- stalking: shoulders down, head level and pointed at them, tail up, ready to spring
	Quadruped = { Joint_CorePos = { 0, -0.12, 0 }, Joint_Core = { -5, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Legs_FL = { 10, 0, 0 }, Sub_Legs_FR = { -4, 0, 0 }, Sub_Legs_BL = { -6, 0, 0 }, Sub_Legs_BR = { 8, 0, 0 }, Joint_Tail = { -16, 0, 0 },
		Joint_RightArm = { 50, 0, -40 }, Sub_RightArm_Fore = { 95, 0, 0 }, Joint_LeftArm = { 55, 0, 40 }, Sub_LeftArm_Fore = { 90, 0, 0 } },
}
-- a clip that starts or ends on "rest" starts and ends in the stance instead (or the blend
-- into it dips the hands at both ends)
local function fromStance(library, stance)
	for name, def in library do
		if type(def) == "table" and def.Keys and (name:sub(1, 6) == "Combo_" or name:sub(1, 6) == "Beast_" or name == "Heavy" or name == "Guard_Hold") then
			for index, key in def.Keys do
				local empty = true
				for _, value in key do
					if type(value) == "table" then
						empty = false
						break
					end
				end
				if empty and (index == 1 or index == #def.Keys) then
					def.Keys[index] = at(key.T, stance)
				end
			end
		end
	end
end
fromStance(POSES.Biped, BOXER)
fromStance(POSES.Quadruped, POSES.Stance.Quadruped)
for _, name in { "Combo_NightmareFrenzy", "Combo_TentacleSlam" } do
	fromStance({ [name] = POSES.Common[name] }, BOXER)
end

------------------------------------------------------------------------------------------
-- UNLEASHED (Config.Possession.Rampage): the heavy moveset of a POSSESSED Nightmare. Every
-- blow is thrown with the whole body: big loads, the hips all the way through, the weight
-- dropped onto the contact, and follow-throughs that carry on past it. Contact frames are
-- the server's hit times (Rampage Hits), with no "Hit" marker: the clip plays at the speed
-- the server's timing implies, like the wild moveset's strings.
------------------------------------------------------------------------------------------
local RAGE = {
	-- a wild right HAYMAKER: wound right round, then the whole body thrown through it
	Rage_Haymaker = {
		Duration = 1.0,
		Markers = { { 0.26, "Whoosh" }, { 0.36, "Strike" }, { 0.36, "StepL" } },
		Keys = {
			pose(0),
			pose(0.16, { Joint_CorePos = { 0, 0.05, 0.3 }, Joint_Core = { 8, -42, 4 }, Joint_Legs = { -8, 42, -4 }, Joint_Head = { -8, 24, 0 }, Joint_RightArm = { 62, 0, 72 }, Sub_RightArm_Fore = { 50, 0, 0 }, Joint_LeftArm = { 70, 0, 40 }, Sub_LeftArm_Fore = { 105, 0, 0 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -16, 0, 0 } }),
			blow(0.36, { Joint_CorePos = { 0, -0.08, -0.95 }, Joint_Core = { -18, 50, -8 }, Joint_Legs = { 18, -50, 8 }, Joint_Head = { -12, -18, 0 }, Joint_RightArm = { 90, 0, -30 }, Sub_RightArm_Fore = { 28, 0, 0 }, Joint_LeftArm = { 40, 0, 30 }, Sub_LeftArm_Fore = { 110, 0, 0 }, Sub_Legs_L = { 38, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } }),
			pose(0.52, { Joint_CorePos = { 0, -0.2, -1.05 }, Joint_Core = { -26, 70, -8 }, Joint_Legs = { 26, -56, 8 }, Joint_Head = { -12, -30, 0 }, Joint_RightArm = { 70, 0, -62 }, Sub_RightArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } }),
			pose(0.78, { Joint_CorePos = { 0, 0.05, -0.4 }, Joint_Core = { -8, 20, 0 }, Joint_Legs = { 8, -20, 0 } }),
			pose(1.0),
		},
	},
	-- a lead ELBOW: the arm folded tight so the point of the elbow leads, smashed across
	Rage_Elbow = {
		Duration = 0.95,
		Markers = { { 0.22, "Whoosh" }, { 0.3, "Strike" }, { 0.3, "StepL" } },
		Keys = {
			pose(0),
			pose(0.13, { Joint_CorePos = { 0, 0.05, -0.1 }, Joint_Core = { -8, 30, 2 }, Joint_Legs = { 8, -30, 0 }, Joint_Head = { -10, -8, 0 }, Joint_LeftArm = { 78, 0, -26 }, Sub_LeftArm_Fore = { 138, 0, 0 }, Sub_Legs_L = { 26, 0, 0 }, Sub_Legs_R = { -18, 0, 0 } }),
			blow(0.3, { Joint_CorePos = { 0, -0.12, -0.8 }, Joint_Core = { -16, -40, 6 }, Joint_Legs = { 16, 40, -6 }, Joint_Head = { -12, 18, 0 }, Joint_LeftArm = { 95, 0, 40 }, Sub_LeftArm_Fore = { 142, 0, 0 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } }),
			pose(0.46, { Joint_CorePos = { 0, -0.1, -0.85 }, Joint_Core = { -18, -56, 6 }, Joint_Legs = { 18, 46, -6 }, Joint_Head = { -12, 26, 0 }, Joint_LeftArm = { 86, 0, 58 }, Sub_LeftArm_Fore = { 130, 0, 0 } }),
			pose(0.72, { Joint_CorePos = { 0, 0.08, -0.35 } }),
			pose(0.95),
		},
	},
	-- the LAUNCHER: dropped deep into the legs, then everything explodes upward behind the
	-- rear uppercut, up onto the toes and carrying on over the top
	Rage_Uppercut = {
		Duration = 1.1,
		Markers = { { 0.26, "Whoosh" }, { 0.34, "Strike" }, { 0.34, "StepR" } },
		Keys = {
			pose(0),
			pose(0.18, { Joint_CorePos = { 0, -0.62, -0.15 }, Joint_Core = { -28, -26, 0 }, Joint_Legs = { 28, 26, 0 }, Joint_Head = { -10, 10, 0 }, Joint_RightArm = { 18, 0, -28 }, Sub_RightArm_Fore = { 122, 0, 0 }, Sub_Legs_L = { 48, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
			blow(0.34, { Joint_CorePos = { 0, 0.42, -0.6 }, Joint_Core = { 6, 32, 0 }, Joint_Legs = { -6, -32, 0 }, Joint_Head = { 8, -12, 0 }, Joint_RightArm = { 128, 0, -28 }, Sub_RightArm_Fore = { 48, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } }),
			pose(0.5, { Joint_CorePos = { 0, 0.6, -0.65 }, Joint_Core = { 14, 38, 0 }, Joint_Legs = { -10, -34, 0 }, Joint_Head = { 14, -14, 0 }, Joint_RightArm = { 168, 0, -14 }, Sub_RightArm_Fore = { 26, 0, 0 }, Sub_Legs_L = { 4, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } }),
			pose(0.8, { Joint_CorePos = { 0, 0.1, -0.3 } }),
			pose(1.1),
		},
	},
	-- both fists high over the head, up off the floor, and DOWN: the weight lands with the fists
	Rage_Smash = {
		Duration = 1.4,
		Markers = { { 0.42, "Whoosh" }, { 0.52, "Land" }, { 0.52, "Strike" } },
		Keys = {
			pose(0),
			pose(0.2, { Joint_CorePos = { 0, 0.25, 0.3 }, Joint_Core = { 18, 0, 0 }, Joint_Legs = { -18, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 168, 0, -12 }, Sub_RightArm_Fore = { 46, 0, 0 }, Joint_LeftArm = { 168, 0, 12 }, Sub_LeftArm_Fore = { 46, 0, 0 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } }),
			pose(0.38, { Joint_CorePos = { 0, 0.75, 0.1 }, Joint_Core = { 24, 0, 0 }, Joint_Legs = { -24, 0, 0 }, Joint_Head = { 14, 0, 0 }, Joint_RightArm = { 178, 0, -8 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { 178, 0, 8 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { -4, 0, 0 }, Sub_Legs_R = { -4, 0, 0 } }),
			blow(0.52, { Joint_CorePos = { 0, -0.95, -0.9 }, Joint_Core = { -46, 0, 0 }, Joint_Legs = { 46, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 38, 0, -14 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 38, 0, 14 }, Sub_LeftArm_Fore = { 10, 0, 0 }, Sub_Legs_L = { 54, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } }),
			pose(0.82, { Joint_CorePos = { 0, -0.85, -0.85 }, Joint_Core = { -40, 0, 0 }, Joint_Legs = { 40, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 44, 0, -14 }, Sub_RightArm_Fore = { 16, 0, 0 }, Joint_LeftArm = { 44, 0, 14 }, Sub_LeftArm_Fore = { 16, 0, 0 }, Sub_Legs_L = { 52, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
			pose(1.12, { Joint_CorePos = { 0, -0.1, -0.3 }, Joint_Core = { -10, 0, 0 }, Joint_Legs = { 10, 0, 0 } }),
			pose(1.4),
		},
	},
	-- GRAB SLAM: both hands lock on, a squat under the weight, hoisted to arm's length over the
	-- head, a lean back to load it, and driven down into the floor (the server carries the
	-- body along Rampage.Grab.Hold.Path: in front, overhead by 0.96 s, slammed down at 1.12)
	Rage_GrabSlam = {
		Duration = 1.9,
		Markers = { { 0.22, "Whoosh" }, { 0.3, "Strike" }, { 0.3, "StepL" }, { 1.04, "Whoosh" }, { 1.12, "Land" }, { 1.12, "Strike" } },
		Keys = {
			pose(0),
			pose(0.16, { Joint_CorePos = { 0, -0.1, -0.45 }, Joint_Core = { -14, 0, 0 }, Joint_Legs = { 14, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 98, 0, -14 }, Sub_RightArm_Fore = { 18, 0, 0 }, Joint_LeftArm = { 98, 0, 14 }, Sub_LeftArm_Fore = { 18, 0, 0 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }),
			blow(0.3, { Joint_CorePos = { 0, -0.15, -0.65 }, Joint_Core = { -16, 0, 0 }, Joint_Legs = { 16, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 92, 0, -4 }, Sub_RightArm_Fore = { 48, 0, 0 }, Joint_LeftArm = { 92, 0, 4 }, Sub_LeftArm_Fore = { 48, 0, 0 }, Sub_Legs_L = { 32, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } }),
			pose(0.52, { Joint_CorePos = { 0, -0.6, -0.25 }, Joint_Core = { -22, 0, 0 }, Joint_Legs = { 22, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 84, 0, -6 }, Sub_RightArm_Fore = { 60, 0, 0 }, Joint_LeftArm = { 84, 0, 6 }, Sub_LeftArm_Fore = { 60, 0, 0 }, Sub_Legs_L = { 46, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } }),
			pose(0.76, { Joint_CorePos = { 0, 0.4, 0.1 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { -14, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 170, 0, -10 }, Sub_RightArm_Fore = { 34, 0, 0 }, Joint_LeftArm = { 170, 0, 10 }, Sub_LeftArm_Fore = { 34, 0, 0 }, Sub_Legs_L = { 4, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } }),
			pose(0.96, { Joint_CorePos = { 0, 0.55, 0.25 }, Joint_Core = { 24, 0, 0 }, Joint_Legs = { -24, 0, 0 }, Joint_Head = { 20, 0, 0 }, Joint_RightArm = { 180, 0, -6 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 180, 0, 6 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { 0, 0, 0 }, Sub_Legs_R = { -8, 0, 0 } }),
			blow(1.12, { Joint_CorePos = { 0, -0.95, -0.95 }, Joint_Core = { -48, 0, 0 }, Joint_Legs = { 48, 0, 0 }, Joint_Head = { -24, 0, 0 }, Joint_RightArm = { 34, 0, -12 }, Sub_RightArm_Fore = { 12, 0, 0 }, Joint_LeftArm = { 34, 0, 12 }, Sub_LeftArm_Fore = { 12, 0, 0 }, Sub_Legs_L = { 56, 0, 0 }, Sub_Legs_R = { -32, 0, 0 } }),
			pose(1.42, { Joint_CorePos = { 0, -0.8, -0.85 }, Joint_Core = { -40, 0, 0 }, Joint_Legs = { 40, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 40, 0, -12 }, Joint_LeftArm = { 40, 0, 12 }, Sub_Legs_L = { 52, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
			pose(1.66, { Joint_CorePos = { 0, -0.1, -0.3 }, Joint_Core = { -10, 0, 0 }, Joint_Legs = { 10, 0, 0 } }),
			pose(1.9),
		},
	},
	-- CRUSHING LEAP: sunk into a crouch with the arms flung back, sprung up and out with both
	-- fists raised, knees tucked in the air, and crashed down fists-first (the server carries
	-- the body Leap.Max studs onto them, landing on the 0.6 s hit)
	Rage_Leap = {
		Duration = 1.5,
		Markers = { { 0.22, "Whoosh" }, { 0.6, "Land" }, { 0.6, "Strike" } },
		Keys = {
			pose(0),
			pose(0.16, { Joint_CorePos = { 0, -0.65, 0.25 }, Joint_Core = { -24, 0, 0 }, Joint_Legs = { 24, 0, 0 }, Joint_Head = { -4, 0, 0 }, Joint_RightArm = { -35, 0, 20 }, Sub_RightArm_Fore = { 30, 0, 0 }, Joint_LeftArm = { -35, 0, -20 }, Sub_LeftArm_Fore = { 30, 0, 0 }, Sub_Legs_L = { 52, 0, 0 }, Sub_Legs_R = { -14, 0, 0 } }),
			pose(0.26, { Joint_CorePos = { 0, 0.9, -0.4 }, Joint_Core = { -6, 0, 0 }, Joint_Legs = { 6, 0, 0 }, Joint_Head = { 6, 0, 0 }, Joint_RightArm = { 160, 0, -14 }, Sub_RightArm_Fore = { 40, 0, 0 }, Joint_LeftArm = { 160, 0, 14 }, Sub_LeftArm_Fore = { 40, 0, 0 }, Sub_Legs_L = { -10, 0, 0 }, Sub_Legs_R = { -20, 0, 0 } }),
			pose(0.42, { Joint_CorePos = { 0, 2.4, -0.5 }, Joint_Core = { 14, 0, 0 }, Joint_Legs = { -14, 0, 0 }, Joint_Head = { 14, 0, 0 }, Joint_RightArm = { 178, 0, -8 }, Sub_RightArm_Fore = { 34, 0, 0 }, Joint_LeftArm = { 178, 0, 8 }, Sub_LeftArm_Fore = { 34, 0, 0 }, Sub_Legs_L = { 40, 0, 0 }, Sub_Legs_R = { 30, 0, 0 } }),
			blow(0.6, { Joint_CorePos = { 0, -1.0, -0.8 }, Joint_Core = { -46, 0, 0 }, Joint_Legs = { 46, 0, 0 }, Joint_Head = { -22, 0, 0 }, Joint_RightArm = { 36, 0, -14 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { 36, 0, 14 }, Sub_LeftArm_Fore = { 10, 0, 0 }, Sub_Legs_L = { 58, 0, 0 }, Sub_Legs_R = { -34, 0, 0 } }),
			pose(0.9, { Joint_CorePos = { 0, -0.85, -0.8 }, Joint_Core = { -38, 0, 0 }, Joint_Legs = { 38, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 44, 0, -14 }, Joint_LeftArm = { 44, 0, 14 }, Sub_Legs_L = { 52, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } }),
			pose(1.2, { Joint_CorePos = { 0, -0.1, -0.3 }, Joint_Core = { -10, 0, 0 }, Joint_Legs = { 10, 0, 0 } }),
			pose(1.5),
		},
	},
}
-- the same moves on FOUR LEGS (the head pitch runs the other way: +X tips the snout down)
local QS = POSES.Stance.Quadruped
local function qpose(t: number, change)
	return at(t, QS, change)
end
local function qblow(t: number, change)
	local key = at(t, QS, change)
	key.Ease, key.Stop = "Snap", true
	return key
end
local RAGE_QUAD = {
	-- right forepaw reared high and raked down across them
	Rage_Haymaker = {
		Duration = 1.0,
		Markers = { { 0.26, "Whoosh" }, { 0.36, "Strike" } },
		Keys = {
			qpose(0),
			qpose(0.16, { Joint_CorePos = { 0, 0.3, 0.2 }, Joint_Core = { 14, -18, 0 }, Joint_Head = { -10, 16, 0 }, Sub_Legs_FR = { 110, 0, 40 }, Sub_Legs_FL = { 10, 0, 0 }, Sub_Legs_BL = { -10, 0, 0 }, Sub_Legs_BR = { -10, 0, 0 } }),
			qblow(0.36, { Joint_CorePos = { 0, -0.1, -0.9 }, Joint_Core = { -8, 22, 0 }, Joint_Head = { -10, -18, 0 }, Sub_Legs_FR = { 60, 0, -40 }, Sub_Legs_FL = { 14, 0, 0 }, Sub_Legs_BL = { -20, 0, 0 }, Sub_Legs_BR = { -20, 0, 0 } }),
			qpose(0.55, { Joint_CorePos = { 0, -0.15, -0.8 }, Joint_Core = { -6, 30, 0 }, Joint_Head = { -6, -24, 0 }, Sub_Legs_FR = { 30, 0, -50 } }),
			qpose(0.8, { Joint_CorePos = { 0, 0, -0.3 } }),
			qpose(1.0),
		},
	},
	-- and the left one back the other way
	Rage_Elbow = {
		Duration = 0.95,
		Markers = { { 0.22, "Whoosh" }, { 0.3, "Strike" } },
		Keys = {
			qpose(0),
			qpose(0.13, { Joint_CorePos = { 0, 0.3, 0.1 }, Joint_Core = { 14, 18, 0 }, Joint_Head = { -10, -16, 0 }, Sub_Legs_FL = { 110, 0, -40 }, Sub_Legs_FR = { 10, 0, 0 }, Sub_Legs_BL = { -10, 0, 0 }, Sub_Legs_BR = { -10, 0, 0 } }),
			qblow(0.3, { Joint_CorePos = { 0, -0.1, -0.85 }, Joint_Core = { -8, -22, 0 }, Joint_Head = { -10, 18, 0 }, Sub_Legs_FL = { 60, 0, 40 }, Sub_Legs_FR = { 14, 0, 0 }, Sub_Legs_BL = { -20, 0, 0 }, Sub_Legs_BR = { -20, 0, 0 } }),
			qpose(0.48, { Joint_CorePos = { 0, -0.15, -0.75 }, Joint_Core = { -6, -30, 0 }, Joint_Head = { -6, 24, 0 }, Sub_Legs_FL = { 30, 0, 50 } }),
			qpose(0.72, { Joint_CorePos = { 0, 0, -0.3 } }),
			qpose(0.95),
		},
	},
	-- head low under them, jaws open, then TOSSED: snapped shut and flung upward
	Rage_Uppercut = {
		Duration = 1.1,
		Markers = { { 0.26, "Whoosh" }, { 0.34, "JawSnap" } },
		Keys = {
			qpose(0),
			qpose(0.18, { Joint_CorePos = { 0, -0.35, 0.15 }, Joint_Core = { -8, 0, 0 }, Joint_Head = { 30, 0, 0 }, Sub_Head_Jaw = { -38, 0, 0 }, Sub_Legs_FL = { -10, 0, 0 }, Sub_Legs_FR = { -10, 0, 0 }, Sub_Legs_BL = { 22, 0, 0 }, Sub_Legs_BR = { 22, 0, 0 } }),
			qblow(0.34, { Joint_CorePos = { 0, 0.45, -0.85 }, Joint_Core = { 20, 0, 0 }, Joint_Head = { -42, 0, 0 }, Sub_Head_Jaw = { 4, 0, 0 }, Sub_Legs_FL = { 46, 0, 0 }, Sub_Legs_FR = { 46, 0, 0 }, Sub_Legs_BL = { -26, 0, 0 }, Sub_Legs_BR = { -26, 0, 0 } }),
			qpose(0.55, { Joint_CorePos = { 0, 0.4, -0.7 }, Joint_Core = { 24, 0, 0 }, Joint_Head = { -30, 0, 0 }, Sub_Head_Jaw = { -14, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 } }),
			qpose(0.85, { Joint_CorePos = { 0, 0, -0.3 } }),
			qpose(1.1),
		},
	},
	-- reared right up on the hind legs and both forepaws STAMPED down
	Rage_Smash = {
		Duration = 1.4,
		Markers = { { 0.44, "Whoosh" }, { 0.52, "Land" }, { 0.52, "Strike" } },
		Keys = {
			qpose(0),
			qpose(0.2, { Joint_CorePos = { 0, 0.2, 0.3 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { -10, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { 14, 0, 0 }, Sub_Legs_BR = { 14, 0, 0 } }),
			qpose(0.38, { Joint_CorePos = { 0, 1.1, 0.45 }, Joint_Core = { 38, 0, 0 }, Joint_Head = { -26, 0, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Sub_Legs_FL = { 105, 0, 0 }, Sub_Legs_FR = { 95, 0, 0 }, Sub_Legs_BL = { -30, 0, 0 }, Sub_Legs_BR = { -30, 0, 0 }, Joint_Tail = { -30, 0, 0 } }),
			qblow(0.52, { Joint_CorePos = { 0, -0.55, -0.8 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { 20, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 28, 0, 0 }, Sub_Legs_FR = { 28, 0, 0 }, Sub_Legs_BL = { 14, 0, 0 }, Sub_Legs_BR = { 14, 0, 0 }, Joint_Tail = { 10, 0, 0 } }),
			qpose(0.85, { Joint_CorePos = { 0, -0.45, -0.75 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Legs_FL = { 24, 0, 0 }, Sub_Legs_FR = { 24, 0, 0 }, Sub_Legs_BL = { 12, 0, 0 }, Sub_Legs_BR = { 12, 0, 0 } }),
			qpose(1.1, { Joint_CorePos = { 0, -0.05, -0.3 } }),
			qpose(1.4),
		},
	},
	-- jaws clamped on, hauled up as it rears, and WHIPPED down into the floor
	Rage_GrabSlam = {
		Duration = 1.9,
		Markers = { { 0.22, "Whoosh" }, { 0.3, "JawSnap" }, { 1.04, "Whoosh" }, { 1.12, "Land" }, { 1.12, "Strike" } },
		Keys = {
			qpose(0),
			qpose(0.16, { Joint_CorePos = { 0, -0.2, -0.6 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Head_Jaw = { -55, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { -20, 0, 0 }, Sub_Legs_BR = { -20, 0, 0 } }),
			qblow(0.3, { Joint_CorePos = { 0, -0.25, -0.9 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { 8, 0, 0 }, Sub_Head_Jaw = { 2, 0, 0 }, Sub_Legs_FL = { 36, 0, 0 }, Sub_Legs_FR = { 36, 0, 0 }, Sub_Legs_BL = { -26, 0, 0 }, Sub_Legs_BR = { -26, 0, 0 } }),
			qpose(0.6, { Joint_CorePos = { 0, 0.3, -0.2 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { -30, 0, 0 }, Sub_Head_Jaw = { 2, 0, 0 }, Sub_Legs_FL = { 60, 0, 0 }, Sub_Legs_FR = { 60, 0, 0 }, Sub_Legs_BL = { -20, 0, 0 }, Sub_Legs_BR = { -20, 0, 0 } }),
			qpose(0.96, { Joint_CorePos = { 0, 0.9, 0.3 }, Joint_Core = { 34, 0, 0 }, Joint_Head = { -44, 0, 0 }, Sub_Head_Jaw = { 2, 0, 0 }, Sub_Legs_FL = { 95, 0, 0 }, Sub_Legs_FR = { 95, 0, 0 }, Sub_Legs_BL = { -30, 0, 0 }, Sub_Legs_BR = { -30, 0, 0 }, Joint_Tail = { -30, 0, 0 } }),
			qblow(1.12, { Joint_CorePos = { 0, -0.6, -0.9 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { 34, 0, 0 }, Sub_Head_Jaw = { -20, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { 14, 0, 0 }, Sub_Legs_BR = { 14, 0, 0 }, Joint_Tail = { 10, 0, 0 } }),
			qpose(1.45, { Joint_CorePos = { 0, -0.4, -0.7 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { 22, 0, 0 }, Sub_Head_Jaw = { -10, 0, 0 } }),
			qpose(1.9),
		},
	},
	-- a pounce from a crouch, flying in with the forepaws out, crashing down on them
	Rage_Leap = {
		Duration = 1.5,
		Markers = { { 0.22, "Whoosh" }, { 0.6, "Land" }, { 0.6, "Strike" } },
		Keys = {
			qpose(0),
			qpose(0.16, { Joint_CorePos = { 0, -0.5, 0.3 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { 10, 0, 0 }, Sub_Legs_FL = { -20, 0, 0 }, Sub_Legs_FR = { -20, 0, 0 }, Sub_Legs_BL = { 40, 0, 0 }, Sub_Legs_BR = { 40, 0, 0 } }),
			qpose(0.26, { Joint_CorePos = { 0, 0.8, -0.4 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { -20, 0, 0 }, Sub_Legs_FL = { 80, 0, 0 }, Sub_Legs_FR = { 80, 0, 0 }, Sub_Legs_BL = { -50, 0, 0 }, Sub_Legs_BR = { -50, 0, 0 } }),
			qpose(0.42, { Joint_CorePos = { 0, 2.2, -0.5 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { -10, 0, 0 }, Sub_Head_Jaw = { -40, 0, 0 }, Sub_Legs_FL = { 100, 0, 0 }, Sub_Legs_FR = { 100, 0, 0 }, Sub_Legs_BL = { -60, 0, 0 }, Sub_Legs_BR = { -60, 0, 0 }, Joint_Tail = { -30, 0, 0 } }),
			qblow(0.6, { Joint_CorePos = { 0, -0.6, -0.8 }, Joint_Core = { -16, 0, 0 }, Joint_Head = { 26, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { 20, 0, 0 }, Sub_Legs_BR = { 20, 0, 0 } }),
			qpose(0.9, { Joint_CorePos = { 0, -0.45, -0.7 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { 18, 0, 0 } }),
			qpose(1.2, { Joint_CorePos = { 0, -0.05, -0.3 } }),
			qpose(1.5),
		},
	},
}
-- weight: flowing between keys, dead stop on each contact, and the body carrying on past it
local RagePoseTools = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PoseTools"))
for name, def in RAGE do
	POSES.Common[name] = RagePoseTools.Punch(def, 0.3)
end
for name, def in RAGE_QUAD do
	POSES.Quadruped[name] = RagePoseTools.Punch(def, 0.3)
end

-- The punches go all the way out and connect (FightAim): each contact frame, which arm, where.
local function aim(library, name: string, list)
	local def = library[name]
	if def then
		def.Aim = {}
		for _, strike in list do
			local limb = strike[2] == "L" and "Left" or strike[2] == "R" and "Right" or strike[2]
			table.insert(def.Aim, { T = strike[1], Arm = limb, At = strike[3] == "B" and "Body" or strike[3] == "F" and "Legs" or "Head" })
		end
	end
end
-- the kicks
aim(POSES.Common, "Gym_Teep", { { 0.42, "RightLeg", "B" } })
aim(POSES.Common, "Gym_Roundhouse", { { 0.5, "RightLeg" } })
aim(POSES.Common, "Gym_SpinBackKick", { { 0.56, "RightLeg", "B" } })
-- (paws: a four-legged body's rakes)
aim(POSES.Quadruped, "Combo1", { { 0.22, "FrontRight", "B" } })
aim(POSES.Quadruped, "Combo2", { { 0.25, "FrontLeft", "B" } })
-- the arm abilities that land on their "Hit" frame, by the limb doing them
for _, id in { "RustySlash", "DemonRend", "MeteorFist" } do
	local name = "Ability_" .. id
	for _, marker in POSES.Common[name].Markers do
		if marker[2] == "Hit" then
			aim(POSES.Common, name, { { marker[1], "R", "B" } })
			aim(POSES.Common, name .. "_Left", { { marker[1], "L", "B" } })
			if POSES.Quadruped[name] then
				aim(POSES.Quadruped, name, { { marker[1], "R", "B" } })
			end
		end
	end
end
aim(POSES.Common, "Combo1", { { 0.22, "L" } })
aim(POSES.Common, "Combo2", { { 0.25, "R" } })
aim(POSES.Common, "Combo3", { { 0.35, "L" } })
aim(POSES.Common, "Gym_ComboA", { { 0.3, "L" }, { 0.54, "L" }, { 0.8, "R" } })
aim(POSES.Common, "Gym_ComboB", { { 0.3, "L" }, { 0.56, "R" }, { 0.86, "L" } })
aim(POSES.Common, "Gym_ComboC", { { 0.3, "L" }, { 0.58, "L" }, { 1.04, "R" } })
aim(POSES.Common, "Gym_BodyRip", { { 0.46, "L", "B" }, { 0.74, "R" } })
aim(POSES.Common, "Gym_Power", { { 0.5, "R" } })
aim(POSES.Common, "Gym_OneTwoLow", { { 0.26, "L" }, { 0.5, "R" }, { 0.88, "RightLeg", "F" } })
aim(POSES.Common, "Gym_LiverHead", { { 0.4, "L", "B" }, { 0.72, "L" } })
aim(POSES.Common, "Combo_NightmareFrenzy", { { 0.3, "R" }, { 0.48, "L" }, { 0.66, "R" }, { 0.84, "L" }, { 1.02, "R" }, { 1.2, "L" }, { 1.72, "R", "B" }, { 1.72, "L", "B" } })
aim(POSES.Biped, "Combo_BrutalBoxer", { { 0.3, "L" }, { 0.55, "R" }, { 0.82, "L" }, { 1.1, "R" }, { 1.62, "R" } })
aim(POSES.Biped, "Combo_BrutalBoxerII", { { 0.3, "L" }, { 0.55, "R" }, { 0.82, "L" }, { 1.1, "R" }, { 1.32, "L", "B" }, { 1.84, "R" } })
aim(POSES.Biped, "Combo_PerfectCounter", { { 0.46, "L" }, { 0.7, "R" }, { 1.0, "RightLeg", "B" } })
aim(POSES.Biped, "Combo_CycloneDestroyer", { { 0.3, "L" }, { 0.72, "R" } })
aim(POSES.Biped, "Combo_TitanCombination", { { 0.72, "R" }, { 1.1, "L", "B" } })
aim(POSES.Biped, "Combo_AerialCrusher", { { 0.36, "R" } })
aim(POSES.Biped, "Heavy", { { 0.45, "R" } })
-- UNLEASHED: the haymaker and the launcher drive the fist into them (the elbow, the smashes
-- and the grab aren't a straight arm)
aim(POSES.Common, "Rage_Haymaker", { { 0.36, "R" } })
aim(POSES.Common, "Rage_Uppercut", { { 0.34, "R" } })
-- NIGHTMARE UNDERGROUND: every strike reaches the body it hits (head or body, by Height)
aim(POSES.Common, "UG_Jab", { { 0.2, "L" } })
aim(POSES.Common, "UG_Cross", { { 0.26, "R" } })
aim(POSES.Common, "UG_HookL", { { 0.3, "L" } })
aim(POSES.Common, "UG_Uppercut", { { 0.32, "R" } })
aim(POSES.Common, "UG_LiverHook", { { 0.32, "L", "B" } })
aim(POSES.Common, "UG_Overhand", { { 0.5, "R" } })
aim(POSES.Common, "UG_BodyBlast", { { 0.42, "R", "B" } })
aim(POSES.Quadruped, "Rage_Haymaker", { { 0.36, "FrontRight", "B" } })
aim(POSES.Quadruped, "Rage_Elbow", { { 0.3, "FrontLeft", "B" } })

-- every combination lands: flows through its keys, fast into each contact, stopped dead on it
local PoseTools = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PoseTools"))
for _, library in { POSES.Common, POSES.Biped, POSES.Quadruped } do
	for name, def in library do
		if name:sub(1, 6) == "Combo_" or name:sub(1, 6) == "Beast_" or name == "Heavy" then
			PoseTools.Punch(def)
		end
	end
end

------------------------------------------------------------------------------------------
-- HOW A BLOW LANDS (Config.Nightmare.Reactions; NightmareAnimator:React): added on top of
-- whatever the body is doing, so it can happen mid-punch; zero at both ends. Authored facing
-- the attacker: +X leans / tips back, +Y turns to its left, +Z leans to its left, CorePos in
-- studs (+Z back). The attacker's left hook comes from the victim's right, so it whips the
-- head to the victim's left.
------------------------------------------------------------------------------------------
local REACTIONS = {
	Jab = {
		Duration = 0.34,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.06, Ease = "Out", Joint_CorePos = { 0, 0, 0.12 }, Joint_Core = { 5, 0, 0 }, Joint_Head = { 16, 0, 0 } },
			{ T = 0.34 },
		},
	},
	Cross = {
		Duration = 0.46,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.07, Ease = "Out", Joint_CorePos = { 0, -0.03, 0.26 }, Joint_Core = { 10, -4, 0 }, Joint_Head = { 26, -6, 0 }, Joint_RightArm = { -14, 0, 10 }, Joint_LeftArm = { -14, 0, -10 }, Sub_Legs_R = { -8, 0, 0 } },
			{ T = 0.22, Joint_CorePos = { 0, -0.04, 0.14 }, Joint_Core = { 4, -2, 0 }, Joint_Head = { 10, -3, 0 } },
			{ T = 0.46 },
		},
	},
	HookL = {
		Duration = 0.5,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.08, Ease = "Out", Joint_CorePos = { -0.22, -0.06, 0.08 }, Joint_Core = { 4, 12, 6 }, Joint_Head = { 6, 34, 14 }, Joint_RightArm = { -10, 0, -8 }, Joint_LeftArm = { -18, 0, -14 } },
			{ T = 0.26, Joint_CorePos = { -0.12, -0.06, 0.04 }, Joint_Core = { 2, 6, 3 }, Joint_Head = { 2, 12, 6 } },
			{ T = 0.5 },
		},
	},
	Upper = {
		Duration = 0.55,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.09, Ease = "Out", Joint_CorePos = { 0, 0.2, 0.12 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 36, 0, 0 }, Joint_RightArm = { -22, 0, 14 }, Joint_LeftArm = { -22, 0, -14 }, Sub_Legs_L = { -8, 0, 0 }, Sub_Legs_R = { 6, 0, 0 } },
			{ T = 0.28, Joint_CorePos = { 0, 0.02, 0.08 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 12, 0, 0 } },
			{ T = 0.55 },
		},
	},
	-- doubled over it: the guard comes down, the elbows clamp in, the knees give
	Body = {
		Duration = 0.6,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.1, Ease = "Out", Joint_CorePos = { 0, -0.28, 0.2 }, Joint_Core = { -22, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { -24, 0, 6 }, Sub_RightArm_Fore = { 18, 0, 0 }, Joint_LeftArm = { -24, 0, -6 }, Sub_LeftArm_Fore = { 18, 0, 0 }, Sub_Legs_L = { 12, 0, 0 }, Sub_Legs_R = { 6, 0, 0 } },
			{ T = 0.32, Joint_CorePos = { 0, -0.2, 0.1 }, Joint_Core = { -14, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { -10, 0, 0 }, Joint_LeftArm = { -10, 0, 0 }, Sub_Legs_L = { 6, 0, 0 } },
			{ T = 0.6 },
		},
	},
	-- the lead leg chopped out from under it
	Leg = {
		Duration = 0.5,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.08, Ease = "Out", Joint_CorePos = { -0.12, -0.24, 0 }, Joint_Core = { -6, -8, -8 }, Joint_Head = { 8, 6, 4 }, Sub_Legs_L = { -24, 0, -14 }, Joint_LeftArm = { -14, 0, -18 } },
			{ T = 0.28, Joint_CorePos = { -0.04, -0.12, 0 }, Joint_Core = { -2, -3, -3 }, Sub_Legs_L = { -8, 0, -4 } },
			{ T = 0.5 },
		},
	},
	-- rocked: thrown back with the arms gone, then the legs nearly go under it
	Heavy = {
		Duration = 0.85,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.09, Ease = "Out", Joint_CorePos = { 0, -0.1, 0.42 }, Joint_Core = { 22, -6, 6 }, Joint_Head = { 38, 8, 0 }, Joint_RightArm = { -28, 0, 26 }, Sub_RightArm_Fore = { -30, 0, 0 }, Joint_LeftArm = { -28, 0, -26 }, Sub_LeftArm_Fore = { -30, 0, 0 } },
			{ T = 0.36, Joint_CorePos = { 0, -0.42, 0.3 }, Joint_Core = { -14, 4, -4 }, Joint_Head = { -12, -4, 0 }, Joint_RightArm = { -22, 0, 8 }, Joint_LeftArm = { -22, 0, -8 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { 10, 0, 0 } },
			{ T = 0.85 },
		},
	},
	-- it took it on the arms
	Block = {
		Duration = 0.3,
		Curve = "Spline",
		Keys = {
			{ T = 0 },
			{ T = 0.05, Ease = "Out", Joint_CorePos = { 0, -0.04, 0.2 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { -3, 0, 0 }, Joint_RightArm = { -14, 0, 0 }, Sub_RightArm_Fore = { 10, 0, 0 }, Joint_LeftArm = { -14, 0, 0 }, Sub_LeftArm_Fore = { 10, 0, 0 } },
			{ T = 0.3 },
		},
	},
}
REACTIONS.HookR = mirrored(REACTIONS.HookL)
POSES.Reactions = { Biped = REACTIONS, Quadruped = {} }
for kind, def in REACTIONS do
	POSES.Reactions.Quadruped[kind] = forQuadruped(def)
end

return POSES
