--[[
	HandlerPoses  (ModuleScript, data only)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/HandlerPoses

	The built-in CODE animations HandlerAnimator plays for every Handler move whose
	AnimationDefinitions slot has no uploaded Id. Keyframed joint angles, smoothstep-blended.

	Angles in degrees per joint (X, Y, Z), in the joint's own space (signs MEASURED in Studio
	with the scrub tool, see HandlerAnimator):
	  Root / Waist  -X leans FORWARD, +X back; +Y turns LEFT (counter-clockwise from above:
	    the right shoulder comes forward, as in a cross), -Y turns right; +Z leans LEFT
	  Hips  Y = minus the Root's Y keeps the feet planted while the body turns
	  Neck  +Y turns the head left
	  Shoulder / Hip  +X swings the limb FORWARD (up in front); Z swings it out sideways
	  Elbow  +X bends the forearm;  Knee  -X bends the shin back
	  Neck  +X tilts the head back (-X = chin tucked)
	  RootPos (studs, X right / Y up / -Z forward) moves the whole body off its feet's spot:
	  the weight shifting forward into a punch, dipping under, leaping...
	  Wrist (weapon moves) turns the held weapon in the fist: it's built pointing out of the
	  front of the fist, so with the arm reaching forward it points UP; Wrist -X tips it
	  forward until, at -90, it runs straight on from the forearm (a thrust).
	Joints not listed in a key are neutral (0) for the pose's duration.
	UpperBody = true: only the waist, neck and arms are posed, the legs keep Roblox's
	walk / run cycle. Hold = true: a single static key, blended in as an OVERLAY while a
	weapon is out (or your guard is up) and nothing else is playing.

	The fists are thrown like a UFC striker (orthodox): a bladed stance, left foot forward,
	chin tucked behind the shoulder; every punch turns the hips and pivots the feet into it
	and snaps straight back to the guard.
]]

-- The orthodox fighting stance every strike starts from and returns to: bladed (turned a
-- little to the right, left foot forward), knees soft, chin down, elbows tucked to the
-- ribs and the forearms turned in so both fists sit by the jaw (measured: fists at jaw
-- height, 0.6 either side of centre). (Shoulder +Y turns the right arm in; -Y the left.)
local STANCE = {
	RootPos = { 0, -0.15, 0 }, -- knees soft: sitting slightly down into the stance
	Root = { -6, -12, 0 }, Waist = { -2, 6, 0 }, Neck = { -10, 0, 0 },
	LeftShoulder = { 64, -62, 0 }, LeftElbow = { 132, 0, 0 },
	RightShoulder = { 58, 66, 0 }, RightElbow = { 138, 0, 0 },
	LeftHip = { 22, 0, 0 }, LeftKnee = { -22, 0, 0 },
	RightHip = { -16, 0, 0 }, RightKnee = { -30, 0, 0 },
}

-- A key: the stance with some joints changed.
local function stance(t: number, changes)
	local key = table.clone(STANCE)
	for joint, angles in changes or {} do
		key[joint] = angles
	end
	key.T = t
	return key
end

-- A set of joint changes mirrored left <-> right: Left*/Right* joints swap, and every Y
-- (twist) and Z (sideways) angle flips, as does RootPos X. (X angles, forward/back,
-- stay.) Mirrored moves are built as stance(t, mirror(changes)), so they still start and
-- end in the orthodox stance.
local function mirror(changes)
	local out = {}
	for joint, v in changes do
		local name = joint
		if joint:sub(1, 4) == "Left" then
			name = "Right" .. joint:sub(5)
		elseif joint:sub(1, 5) == "Right" then
			name = "Left" .. joint:sub(6)
		end
		if joint == "RootPos" then
			out[name] = { -v[1], v[2], v[3] }
		else
			out[name] = { v[1], -v[2], -v[3] }
		end
	end
	return out
end

-- Builds a move from (t, changes) pairs, optionally mirrored.
local function keys(list, mirrored: boolean?)
	local out = {}
	for _, entry in list do
		table.insert(out, stance(entry[1], mirrored and mirror(entry[2] or {}) or entry[2]))
	end
	return out
end

local POSES = {
	------------------------------------------------------------------------------------
	-- Movement
	------------------------------------------------------------------------------------
	-- Shift: crouch, dive stretched out, hands hit the floor, tucked forward roll, come up
	-- on your feet. The Root turns a full circle (-360 = upright again).
	Dive = {
		Duration = 0.95,
		Keys = {
			{ T = 0, Root = { -20, 0, 0 }, LeftHip = { 35, 0, 0 }, RightHip = { 35, 0, 0 }, LeftKnee = { -55, 0, 0 }, RightKnee = { -55, 0, 0 }, LeftShoulder = { -25, 0, 0 }, RightShoulder = { -25, 0, 0 } },
			{ T = 0.1, Root = { -72, 0, 0 }, Neck = { 45, 0, 0 }, LeftShoulder = { 165, 0, -8 }, RightShoulder = { 165, 0, 8 }, LeftHip = { -12, 0, 0 }, RightHip = { -12, 0, 0 }, LeftKnee = { -8, 0, 0 }, RightKnee = { -20, 0, 0 } },
			{ T = 0.3, Root = { -85, 0, 0 }, Neck = { 40, 0, 0 }, LeftShoulder = { 160, 0, -10 }, RightShoulder = { 160, 0, 10 }, LeftHip = { -10, 0, 0 }, RightHip = { -5, 0, 0 }, LeftKnee = { -15, 0, 0 }, RightKnee = { -25, 0, 0 } },
			{ T = 0.4, Root = { -135, 0, 0 }, Neck = { -30, 0, 0 }, LeftShoulder = { 100, 0, -10 }, RightShoulder = { 100, 0, 10 }, LeftElbow = { 50, 0, 0 }, RightElbow = { 50, 0, 0 }, LeftHip = { 90, 0, 0 }, RightHip = { 90, 0, 0 }, LeftKnee = { -110, 0, 0 }, RightKnee = { -110, 0, 0 } },
			{ T = 0.6, Root = { -250, 0, 0 }, Neck = { -40, 0, 0 }, LeftShoulder = { 60, 0, -15 }, RightShoulder = { 60, 0, 15 }, LeftElbow = { 100, 0, 0 }, RightElbow = { 100, 0, 0 }, LeftHip = { 120, 0, 0 }, RightHip = { 120, 0, 0 }, LeftKnee = { -135, 0, 0 }, RightKnee = { -135, 0, 0 } },
			{ T = 0.78, Root = { -340, 0, 0 }, Neck = { -10, 0, 0 }, LeftShoulder = { 35, 0, -15 }, RightShoulder = { 35, 0, 15 }, LeftElbow = { 60, 0, 0 }, RightElbow = { 60, 0, 0 }, LeftHip = { 70, 0, 0 }, RightHip = { 60, 0, 0 }, LeftKnee = { -90, 0, 0 }, RightKnee = { -80, 0, 0 } },
			{ T = 0.95, Root = { -360, 0, 0 } },
		},
	},
	-- X: hop straight back on the balls of the feet, guard up, eyes on the target.
	StepBack = {
		Duration = 0.42,
		Keys = {
			{ T = 0 },
			{ T = 0.07, Root = { 10, 0, 0 }, Neck = { -8, 0, 0 }, LeftShoulder = { 55, 0, -12 }, RightShoulder = { 60, 0, 12 }, LeftElbow = { 105, 0, 0 }, RightElbow = { 110, 0, 0 }, LeftHip = { 10, 0, 0 }, RightHip = { -30, 0, 0 }, LeftKnee = { -35, 0, 0 }, RightKnee = { -25, 0, 0 } },
			{ T = 0.22, Root = { 6, 0, 0 }, Neck = { -6, 0, 0 }, LeftShoulder = { 55, 0, -12 }, RightShoulder = { 60, 0, 12 }, LeftElbow = { 105, 0, 0 }, RightElbow = { 110, 0, 0 }, LeftHip = { 25, 0, 0 }, RightHip = { -10, 0, 0 }, LeftKnee = { -45, 0, 0 }, RightKnee = { -40, 0, 0 } },
			{ T = 0.42 },
		},
	},
	-- Knocked down face-first: push up off the floor, pull the knees under, stand.
	GetUpFront = {
		Duration = 0.95,
		Keys = {
			{ T = 0, Root = { -85, 0, 0 }, Neck = { 35, 0, 0 }, LeftShoulder = { 75, 0, -20 }, RightShoulder = { 75, 0, 20 }, LeftElbow = { 70, 0, 0 }, RightElbow = { 70, 0, 0 }, LeftHip = { 15, 0, 0 }, RightHip = { 15, 0, 0 }, LeftKnee = { -15, 0, 0 }, RightKnee = { -15, 0, 0 } },
			{ T = 0.35, Root = { -60, 0, 0 }, Neck = { 25, 0, 0 }, LeftShoulder = { 45, 0, -20 }, RightShoulder = { 45, 0, 20 }, LeftElbow = { 15, 0, 0 }, RightElbow = { 15, 0, 0 }, LeftHip = { 85, 0, 0 }, RightHip = { 70, 0, 0 }, LeftKnee = { -115, 0, 0 }, RightKnee = { -100, 0, 0 } },
			{ T = 0.68, Root = { -22, 0, 0 }, LeftShoulder = { 20, 0, -15 }, RightShoulder = { 20, 0, 15 }, LeftHip = { 55, 0, 0 }, RightHip = { 45, 0, 0 }, LeftKnee = { -75, 0, 0 }, RightKnee = { -65, 0, 0 } },
			{ T = 0.95 },
		},
	},
	-- Knocked onto your back: sit up, plant the feet, rise.
	GetUpBack = {
		Duration = 1,
		Keys = {
			{ T = 0, Root = { 70, 0, 0 }, Neck = { -25, 0, 0 }, LeftShoulder = { -35, 0, -20 }, RightShoulder = { -35, 0, 20 }, LeftElbow = { 30, 0, 0 }, RightElbow = { 30, 0, 0 }, LeftHip = { 75, 0, 0 }, RightHip = { 75, 0, 0 }, LeftKnee = { -35, 0, 0 }, RightKnee = { -35, 0, 0 } },
			{ T = 0.35, Root = { 30, 0, 0 }, Neck = { -15, 0, 0 }, LeftShoulder = { -15, 0, -20 }, RightShoulder = { 10, 0, 20 }, LeftHip = { 105, 0, 0 }, RightHip = { 95, 0, 0 }, LeftKnee = { -125, 0, 0 }, RightKnee = { -115, 0, 0 } },
			{ T = 0.7, Root = { -18, 0, 0 }, LeftShoulder = { 25, 0, -15 }, RightShoulder = { 25, 0, 15 }, LeftHip = { 60, 0, 0 }, RightHip = { 50, 0, 0 }, LeftKnee = { -80, 0, 0 }, RightKnee = { -70, 0, 0 } },
			{ T = 1 },
		},
	},

	------------------------------------------------------------------------------------
	-- Striking: punches (UFC orthodox)
	------------------------------------------------------------------------------------
	-- Jab: the front foot steps in and the weight goes with it, the lead shoulder turns over
	-- to cover the chin, the fist snaps all the way out at head height, then straight back.
	Jab = {
		Duration = 0.34,
		Markers = { { 0.04, "Whoosh" }, { 0.11, "Hit" } },
		Keys = {
			stance(0),
			stance(0.04, { RootPos = { 0, -0.18, 0.05 }, Root = { -7, -8, 0 }, LeftShoulder = { 70, 0, -10 }, LeftElbow = { 85, 0, 0 } }),
			stance(0.11, { RootPos = { 0, -0.2, -0.75 }, Root = { -13, -28, 0 }, Waist = { -8, -26, 0 }, Neck = { -16, 8, 0 }, LeftShoulder = { 116, 6, 4 }, LeftElbow = { 0, 0, 0 }, LeftHip = { 38, 28, 0 }, LeftKnee = { -28, 0, 0 }, RightHip = { -24, 28, 0 }, RightKnee = { -16, 0, 0 } }),
			stance(0.16, { RootPos = { 0, -0.2, -0.7 }, Root = { -12, -26, 0 }, Waist = { -7, -24, 0 }, Neck = { -16, 8, 0 }, LeftShoulder = { 114, 6, 4 }, LeftElbow = { 4, 0, 0 }, LeftHip = { 36, 26, 0 }, LeftKnee = { -27, 0, 0 }, RightHip = { -22, 26, 0 }, RightKnee = { -17, 0, 0 } }),
			stance(0.24, { RootPos = { 0, -0.17, -0.3 }, Root = { -8, -16, 0 }, Waist = { -4, -8, 0 }, LeftShoulder = { 76, 0, -10 }, LeftElbow = { 70, 0, 0 } }),
			stance(0.34),
		},
	},
	-- Cross: the back foot drives, the hips and shoulders turn all the way through (rear
	-- heel pivots out), the weight lands on the front leg and the rear fist goes the full
	-- length of the arm into the target; the lead hand stays home on the chin.
	Cross = {
		Duration = 0.4,
		Markers = { { 0.05, "Whoosh" }, { 0.14, "Hit" }, { 0.14, "StepL" } },
		Keys = {
			stance(0),
			stance(0.05, { RootPos = { 0, -0.2, 0.08 }, Root = { -7, -18, 0 }, Waist = { -2, -6, 0 }, RightShoulder = { 58, 0, 18 }, RightElbow = { 110, 0, 0 } }),
			stance(0.14, { RootPos = { 0, -0.24, -1.05 }, Root = { -15, 24, 0 }, Waist = { -8, 22, 0 }, Neck = { -18, -10, 0 }, RightShoulder = { 118, -8, -8 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 64, -62, 0 }, LeftElbow = { 132, 0, 0 }, LeftHip = { 40, -24, 0 }, LeftKnee = { -36, 0, 0 }, RightHip = { -6, -20, 0 }, RightKnee = { -8, 0, 0 } }),
			stance(0.19, { RootPos = { 0, -0.24, -1.0 }, Root = { -14, 22, 0 }, Waist = { -7, 20, 0 }, Neck = { -18, -10, 0 }, RightShoulder = { 116, -8, -8 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 64, -62, 0 }, LeftElbow = { 132, 0, 0 }, LeftHip = { 38, -22, 0 }, LeftKnee = { -35, 0, 0 }, RightHip = { -8, -18, 0 }, RightKnee = { -9, 0, 0 } }),
			stance(0.28, { RootPos = { 0, -0.18, -0.45 }, Root = { -10, 14, 0 }, Waist = { -5, 16, 0 }, RightShoulder = { 72, 0, 6 }, RightElbow = { 80, 0, 0 }, LeftHip = { 22, -14, 0 }, RightHip = { -12, -10, 0 } }),
			stance(0.4),
		},
	},
	-- Elbow (PP, behind the jab): step in close, the rear elbow cocks up and out, then the
	-- hips and shoulders slam round and the point of the elbow cuts across at head height,
	-- the forearm folded tight, the bodyweight falling through it; the lead hand stays on
	-- the chin and the eyes stay on them.
	Elbow = {
		Duration = 0.5,
		Markers = { { 0.07, "Whoosh" }, { 0.17, "Hit" }, { 0.17, "StepL" } },
		Keys = {
			stance(0),
			-- cock it: a small coil right, the rear elbow up and out to the side
			stance(0.07, { RootPos = { 0, -0.24, 0 }, Root = { -6, -26, 0 }, Waist = { -2, -12, 0 }, Neck = { -12, 12, 0 }, RightShoulder = { 120, 0, 40 }, RightElbow = { 150, 0, 0 }, LeftHip = { 22, 14, 0 }, RightHip = { -16, 14, 0 } }),
			-- IMPACT: stepped in, hips and shoulders turned hard through, the elbow point on
			-- the centre line at jaw height (pose lab, measured: 1.0 above your hips, 2.0
			-- out; Contact.Elbow stops the step-in there)
			stance(0.17, { RootPos = { 0.1, -0.25, -1.0 }, Root = { -4, 30, 0 }, Waist = { 0, 20, 0 }, Neck = { -14, -16, 0 }, RightShoulder = { 160, 0, -45 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 70, -64, 0 }, LeftElbow = { 136, 0, 0 }, LeftHip = { 32, -30, 0 }, LeftKnee = { -34, 0, 0 }, RightHip = { -10, -26, 0 }, RightKnee = { -10, 0, 0 } }),
			-- follow-through: the weight keeps turning through, the elbow carrying on across
			stance(0.25, { RootPos = { 0.15, -0.28, -1.05 }, Root = { -8, 48, 0 }, Waist = { -4, 30, 0 }, Neck = { -16, -24, 0 }, RightShoulder = { 140, 0, -72 }, RightElbow = { 148, 0, 0 }, LeftShoulder = { 70, -64, 0 }, LeftElbow = { 136, 0, 0 }, LeftHip = { 34, -48, 0 }, LeftKnee = { -36, 0, 0 }, RightHip = { -8, -44, 0 }, RightKnee = { -12, 0, 0 } }),
			stance(0.37, { RootPos = { 0, -0.2, -0.45 }, Root = { -10, 16, 0 }, Waist = { -4, 14, 0 }, RightShoulder = { 66, 40, 0 }, RightElbow = { 140, 0, 0 }, LeftHip = { 24, -20, 0 }, RightHip = { -12, -18, 0 } }),
			stance(0.5),
		},
	},
	-- Lead hook: the elbow comes up level with the fist, the arm locks at 90 degrees and the
	-- whole body turns it through like a door slamming; the lead foot pivots on its ball.
	Hook = {
		Duration = 0.46,
		Markers = { { 0.07, "Whoosh" }, { 0.17, "Hit" } },
		Keys = {
			stance(0),
			stance(0.07, { RootPos = { 0.15, -0.22, 0 }, Root = { -7, 28, 0 }, Waist = { -2, 28, 0 }, LeftShoulder = { 84, 0, 38 }, LeftElbow = { 92, 0, 0 } }),
			stance(0.17, { RootPos = { -0.2, -0.24, -0.6 }, Root = { -11, -34, 0 }, Waist = { -6, -46, 0 }, Neck = { -18, -6, 0 }, LeftShoulder = { 94, 0, -48 }, LeftElbow = { 90, 0, 0 }, LeftHip = { 30, -32, 0 }, LeftKnee = { -32, 0, 0 }, RightHip = { -14, -14, 0 } }),
			stance(0.22, { RootPos = { -0.2, -0.24, -0.55 }, Root = { -10, -32, 0 }, Waist = { -6, -44, 0 }, Neck = { -18, -6, 0 }, LeftShoulder = { 92, 0, -46 }, LeftElbow = { 92, 0, 0 }, LeftHip = { 28, -30, 0 }, LeftKnee = { -31, 0, 0 } }),
			stance(0.32, { RootPos = { 0, -0.18, -0.2 }, Root = { -8, -10, 0 }, Waist = { -4, -16, 0 }, LeftShoulder = { 74, 0, -16 }, LeftElbow = { 100, 0, 0 } }),
			stance(0.46),
		},
	},
	-- Rear uppercut: sink low on bent knees, then drive up from the legs, hips turning, the
	-- fist rising straight up through the chin.
	Uppercut = {
		Duration = 0.48,
		Keys = {
			stance(0),
			stance(0.08, { RootPos = { 0, -0.6, 0 }, Root = { -16, -20, 0 }, Waist = { -8, -16, 0 }, Neck = { -14, 0, 0 }, RightShoulder = { 16, 0, 10 }, RightElbow = { 108, 0, 0 }, LeftKnee = { -50, 0, 0 }, RightKnee = { -56, 0, 0 }, LeftHip = { 34, 20, 0 }, RightHip = { 4, 20, 0 } }),
			stance(0.18, { RootPos = { 0, 0.05, -0.6 }, Root = { 2, 28, 0 }, Waist = { 6, 24, 0 }, Neck = { 2, 0, 0 }, RightShoulder = { 146, 0, -8 }, RightElbow = { 66, 0, 0 }, LeftKnee = { -14, 0, 0 }, RightKnee = { -8, 0, 0 }, LeftHip = { 22, -28, 0 }, RightHip = { -8, -22, 0 } }),
			stance(0.24, { RootPos = { 0, 0, -0.55 }, Root = { 1, 26, 0 }, Waist = { 5, 22, 0 }, RightShoulder = { 140, 0, -8 }, RightElbow = { 70, 0, 0 }, LeftHip = { 22, -26, 0 }, RightHip = { -8, -20, 0 } }),
			stance(0.34, { RootPos = { 0, -0.15, -0.2 }, Root = { -4, 8, 0 }, RightShoulder = { 80, 0, 6 }, RightElbow = { 100, 0, 0 } }),
			stance(0.48),
		},
	},
	-- Overhand (finisher), thrown like a real one: sit down into the legs, the rear elbow
	-- comes up and out, then the body BENDS forward and over to the lead side, the head
	-- slipping off the centre line, and the fist drops over the top in a looping hook,
	-- elbow bent, the whole bodyweight falling through it, the lead hand on the chin.
	--   LOAD     knees sink, the weight rocks back onto the rear foot, the body coils a little
	--            to the right and the rear elbow lifts out: the punch is cocked
	--   LAUNCH   the rear foot drives, the hips snap round to the left, the fist rises up
	--            and OVER in an arc above head height, the head slipping off to the left
	--   IMPACT   the body bent forward and over to the lead side, chest turned right
	--            through, the fist coming DOWN onto their head on the centre line with the
	--            elbow slightly bent; feet planted, the rear heel turned out; lead hand on
	--            the chin
	--   FOLLOW   the bodyweight keeps falling through: the fist carries on down and across
	--   RECOVER  back up and round into the stance
	-- (Tuned in Studio with the pose lab, by measuring the fist against the body each frame:
	-- the fist climbs half a stud above your own head while the body drops under it, comes
	-- over and DOWN onto the jaw on the centre line ~3 studs out at 0.34 s (HitTime), and
	-- carries on down through the target.)
	Overhand = {
		Duration = 0.86,
		Markers = { { 0.24, "Whoosh" }, { 0.34, "Hit" }, { 0.34, "StepL" } },
		Keys = {
			stance(0),
			-- load: sink and coil, the fist stays home by the jaw
			stance(0.13, { RootPos = { 0.08, -0.36, 0.2 }, Root = { -4, -22, -4 }, Waist = { 0, -12, -2 }, Neck = { -12, 10, 0 }, RightShoulder = { 50, 56, 0 }, RightElbow = { 134, 0, 0 }, LeftHip = { 22, 22, 4 }, LeftKnee = { -32, 0, 0 }, RightHip = { -12, 22, 4 }, RightKnee = { -46, 0, 0 } }),
			-- launch: hips snap round, the body tilts to the lead side, elbow up and out, the
			-- fist looping over the top
			stance(0.24, { RootPos = { -0.15, -0.55, -0.55 }, Root = { -22, 18, 14 }, Waist = { -12, 14, 12 }, Neck = { -12, -14, -10 }, RightShoulder = { 100, 0, 100 }, RightElbow = { 104, 0, 0 }, LeftHip = { 44, -18, -14 }, LeftKnee = { -50, 0, 0 }, RightHip = { -4, -18, -14 }, RightKnee = { -24, 0, 0 } }),
			-- impact: folded right over at the waist, chin tucked so the face points at the
			-- floor, head off the line, the fist dropping over the top onto the jaw (the
			-- shoulder lifts to make up for the bend, so it still lands at head height)
			-- (measured: fist on the centre line at jaw height 1.1, 2.7 studs out; face
			-- pitched 60 degrees down at the floor)
			stance(0.34, { RootPos = { -0.25, -0.3, -1.0 }, Root = { -20, 26, 22 }, Waist = { -28, 16, 14 }, Neck = { -42, -20, -16 }, RightShoulder = { 155, 0, 70 }, RightElbow = { 70, 0, 0 }, LeftHip = { 50, -26, -22 }, LeftKnee = { -60, 0, 0 }, RightHip = { -4, -30, -22 }, RightKnee = { -14, 0, 0 } }),
			-- follow-through: the bodyweight keeps falling through, still bent over looking at
			-- the floor, the fist down and across
			stance(0.47, { RootPos = { -0.3, -0.4, -1.1 }, Root = { -26, 40, 24 }, Waist = { -30, 24, 14 }, Neck = { -40, -26, -16 }, RightShoulder = { 100, 0, 30 }, RightElbow = { 70, 0, 0 }, LeftHip = { 58, -40, -24 }, LeftKnee = { -64, 0, 0 }, RightHip = { 0, -44, -24 }, RightKnee = { -16, 0, 0 } }),
			-- recover: unfold, back up and round into the guard
			stance(0.66, { RootPos = { -0.1, -0.4, -0.5 }, Root = { -20, 8, 6 }, Waist = { -8, 6, 4 }, RightShoulder = { 60, 50, 0 }, RightElbow = { 128, 0, 0 }, LeftHip = { 42, -10, -6 }, LeftKnee = { -40, 0, 0 }, RightHip = { -6, -10, -6 } }),
			stance(0.86),
		},
	},

	------------------------------------------------------------------------------------
	-- Striking: kicks
	------------------------------------------------------------------------------------
	-- Head kick (UFC roundhouse): load, then spring up off the standing foot as the hips
	-- turn OVER to the left and the right leg whips round from the side into their head;
	-- the right arm swings down and back for balance, the lead hand guards the face, eyes
	-- stay on them. (Rebuilt from measurements: the old one turned the hips the wrong way
	-- and its foot was 1.1 studs out at hip height on the hit frame. Now: the foot arcs in
	-- from the right, 1.9 studs out, centred, at head height (1.4 above the hips) at 0.24 s;
	-- MeleeDefinitions Contact.HeadKick stops the step-in exactly there.)
	HeadKick = {
		Duration = 0.6,
		Markers = { { 0.09, "StepL" }, { 0.18, "Whoosh" }, { 0.24, "Hit" }, { 0.4, "Land" } },
		Keys = {
			stance(0),
			stance(0.09, { Root = { 0, -15, 0 }, RootPos = { 0, -0.25, 0 }, RightHip = { 30, 0, 30 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -25, 0, 0 } }),
			stance(0.24, { Root = { 25, 90, 25 }, RootPos = { 0, 0.6, -0.3 }, Neck = { -6, -60, 0 }, RightHip = { 0, 0, 90 }, RightKnee = { -4, 0, 0 }, LeftHip = { 0, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightShoulder = { -30, 0, 40 }, RightElbow = { 20, 0, 0 } }),
			stance(0.4, { Root = { 10, 110, 15 }, RootPos = { 0, 0.2, -0.3 }, Neck = { 0, -70, 0 }, RightHip = { 0, 0, 50 }, RightKnee = { -70, 0, 0 }, LeftHip = { 0, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightShoulder = { 10, 0, 30 }, RightElbow = { 60, 0, 0 } }),
			stance(0.6),
		},
	},
	-- Leg kick: a short, chopping shin into the thigh / calf, hips turning through.
	LegKick = {
		Duration = 0.42,
		Keys = {
			stance(0),
			stance(0.07, { Root = { 4, 18, 0 }, RightHip = { 20, 0, -16 }, RightKnee = { -44, 0, 0 }, LeftHip = { 18, 24, 0 } }),
			stance(0.16, { Root = { 10, -48, -4 }, Waist = { 0, -14, 0 }, RightHip = { 46, 0, -46 }, RightKnee = { -8, 0, 0 }, LeftHip = { 14, 40, 0 }, LeftKnee = { -18, 0, 0 }, RightShoulder = { -24, 0, 36 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 72, 0, -26 } }),
			stance(0.28, { Root = { 6, -26, 0 }, RightHip = { 24, 0, -20 }, RightKnee = { -42, 0, 0 } }),
			stance(0.42),
		},
	},
	-- Leg sweep (PPK, after the elbow): drop into a deep crouch on the lead leg, the rear leg
	-- stretched out wide, one hand posting toward the floor, then the hips whip round and the
	-- straight rear leg scythes along the floor through their ankles, carrying on across,
	-- before you rise back into the stance. (Hips: Y = minus the Root's turn keeps the lead
	-- foot planted. RightHip +Z swings the leg out to the right.)
	-- (Tuned in the pose lab by scanning the whole move every 0.025 s: neither foot goes more
	-- than 0.12 through the floor or lifts off it, and the body holds one crouch height
	-- through the swing instead of bobbing.)
	LegSweep = {
		Duration = 0.85,
		Markers = { { 0.06, "StepL" }, { 0.21, "Whoosh" }, { 0.3, "Hit" }, { 0.64, "StepR" } },
		Keys = {
			stance(0),
			-- dropping: the lead knee bends, the rear leg starts to swing out
			stance(0.06, { RootPos = { 0, -0.55, 0.05 }, Root = { -15, -24, 0 }, Waist = { -5, -2, 0 }, Neck = { -7, 16, 0 }, LeftHip = { 52, 10, 0 }, LeftKnee = { -78, 0, 0 }, RightHip = { -10, 0, 40 }, RightKnee = { -14, 0, 0 }, LeftShoulder = { 50, -30, -12 }, LeftElbow = { 80, 0, 0 } }),
			-- loaded: deep on the lead leg, the rear leg out wide, the body wound right
			stance(0.12, { RootPos = { 0, -1.15, 0.1 }, Root = { -24, -34, 0 }, Waist = { -8, -8, 0 }, Neck = { -4, 30, 0 }, LeftHip = { 82, 22, 0 }, LeftKnee = { -122, 0, 0 }, RightHip = { -6, 0, 72 }, RightKnee = { -6, 0, 0 }, LeftShoulder = { 36, 0, -24 }, LeftElbow = { 24, 0, 0 }, RightShoulder = { 58, 50, 0 }, RightElbow = { 120, 0, 0 } }),
			-- the hips whip round, the straight leg swinging in wide and low
			stance(0.21, { RootPos = { 0, -1.0, -0.05 }, Root = { -22, -12, 0 }, Waist = { -8, 0, 0 }, Neck = { -5, 14, 0 }, LeftHip = { 83, 0, 0 }, LeftKnee = { -123, 0, 0 }, RightHip = { 35, 0, 55 }, RightKnee = { -5, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 20, 0, 0 }, RightShoulder = { 58, 50, 0 }, RightElbow = { 120, 0, 0 } }),
			stance(0.255, { RootPos = { 0, -0.97, -0.12 }, Root = { -21, -1, 0 }, Waist = { -8, 3, 0 }, Neck = { -6, 5, 0 }, LeftHip = { 76, -11, 0 }, LeftKnee = { -114, 0, 0 }, RightHip = { 70, 0, 28 }, RightKnee = { -4, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 20, 0, 0 }, RightShoulder = { 58, 50, 0 }, RightElbow = { 120, 0, 0 } }),
			-- IMPACT: the straight leg sweeping across the front through their ankles (measured:
			-- the foot 0.4 above the floor, 2.1 out in front; Contact.LegSweep stops the
			-- step-in there)
			stance(0.3, { RootPos = { 0, -1.02, -0.2 }, Root = { -20, 10, 0 }, Waist = { -8, 6, 0 }, Neck = { -6, -4, 0 }, LeftHip = { 78, -22, 0 }, LeftKnee = { -114, 0, 0 }, RightHip = { 92, 0, 0 }, RightKnee = { -4, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 20, 0, 0 }, RightShoulder = { 58, 50, 0 }, RightElbow = { 120, 0, 0 } }),
			-- follow-through: the leg carries on across to the left, lifting off the floor
			stance(0.42, { RootPos = { 0, -1.08, -0.2 }, Root = { -20, 40, 0 }, Waist = { -8, 12, 0 }, Neck = { -6, -24, 0 }, LeftHip = { 68, -52, 0 }, LeftKnee = { -98, 0, 0 }, RightHip = { 92, 0, -45 }, RightKnee = { -8, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 20, 0, 0 }, RightShoulder = { 58, 50, 0 }, RightElbow = { 120, 0, 0 } }),
			-- the knee folds the leg back in, off the floor
			stance(0.5, { RootPos = { 0, -0.82, -0.1 }, Root = { -18, 28, 0 }, Waist = { -6, 10, 0 }, Neck = { -6, -16, 0 }, LeftHip = { 62, -40, 0 }, LeftKnee = { -94, 0, 0 }, RightHip = { 66, 0, -28 }, RightKnee = { -120, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 20, 0, 0 }, RightShoulder = { 58, 50, 0 }, RightElbow = { 120, 0, 0 } }),
			-- rise back into the stance
			stance(0.64, { RootPos = { 0, -0.32, 0 }, Root = { -12, 10, 0 }, Waist = { -4, 6, 0 }, LeftHip = { 40, -22, 0 }, LeftKnee = { -52, 0, 0 }, RightHip = { 14, 0, 0 }, RightKnee = { -46, 0, 0 } }),
			stance(0.85),
		},
	},
	-- Spinning back kick (finisher): turn your back on them, eyes over the shoulder, knee
	-- chambered tight, then spring and drive the heel STRAIGHT BACK through their chest,
	-- landing out of the turn back into your stance. (Rebuilt from measurements: the old
	-- version's foot was behind you at knee height on the hit frame. Now, at 0.36 s: heel
	-- 2.4 studs out toward them at chest height; MeleeDefinitions Contact.SpinKick makes the
	-- lunge stop exactly where it lands.)
	-- (Root's lean is applied before its turn: with the back turned, +X tips the torso AWAY
	-- from them and lifts the kicking leg TOWARD them.)
	SpinKick = {
		Duration = 0.75,
		Markers = { { 0.12, "StepR" }, { 0.28, "Whoosh" }, { 0.36, "Hit" }, { 0.62, "Land" } },
		Keys = {
			{ T = 0 },
			-- step across and start the turn, looking back at them
			{ T = 0.12, Root = { 0, -90, 0 }, RootPos = { 0, -0.25, 0 }, Neck = { 0, 60, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -60, 0, 0 }, LeftKnee = { -30, 0, 0 }, LeftShoulder = { 40, 0, -40 }, RightShoulder = { 40, 0, 40 }, LeftElbow = { 70, 0, 0 }, RightElbow = { 70, 0, 0 } },
			-- back fully turned, knee chambered to the chest, springing up
			{ T = 0.24, Root = { 10, -180, 0 }, RootPos = { 0, 0.25, -0.3 }, Neck = { 0, 75, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -115, 0, 0 }, LeftKnee = { -35, 0, 0 }, LeftShoulder = { 30, 0, -60 }, RightShoulder = { 30, 0, 60 }, LeftElbow = { 60, 0, 0 }, RightElbow = { 60, 0, 0 } },
			-- IMPACT: airborne, torso tipped away, the leg locked out behind into their chest
			{ T = 0.36, Root = { 20, -180, 0 }, RootPos = { 0, 0.6, -0.7 }, Neck = { -10, 75, 0 }, RightHip = { -100, 0, 0 }, RightKnee = { -5, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -40, 0, 0 }, LeftShoulder = { 20, 0, -80 }, RightShoulder = { 20, 0, 80 }, LeftElbow = { 30, 0, 0 }, RightElbow = { 30, 0, 0 } },
			-- snap the leg back in
			{ T = 0.48, Root = { 10, -200, 0 }, RootPos = { 0, 0.3, -0.7 }, Neck = { 0, 60, 0 }, RightHip = { -30, 0, 0 }, RightKnee = { -90, 0, 0 }, LeftKnee = { -30, 0, 0 }, LeftShoulder = { 40, 0, -50 }, RightShoulder = { 40, 0, 50 }, LeftElbow = { 70, 0, 0 }, RightElbow = { 70, 0, 0 } },
			-- land and finish the turn facing them
			{ T = 0.62, Root = { 0, -300, 0 }, RootPos = { 0, -0.2, -0.4 }, RightHip = { 10, 0, 0 }, RightKnee = { -30, 0, 0 }, LeftKnee = { -25, 0, 0 }, LeftShoulder = { 55, 0, -14 }, RightShoulder = { 45, 0, 14 }, LeftElbow = { 110, 0, 0 }, RightElbow = { 110, 0, 0 } },
			{ T = 0.75, Root = { 0, -360, 0 } },
		},
	},
	-- Clinch knee: hands pull the head down, the knee drives up.
	Knee = {
		Duration = 0.4,
		Keys = {
			stance(0),
			stance(0.08, { Root = { -4, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -80, 0, 0 }, LeftShoulder = { 88, 0, -10 }, RightShoulder = { 88, 0, 10 }, LeftElbow = { 55, 0, 0 }, RightElbow = { 55, 0, 0 } }),
			stance(0.15, { Root = { -14, 0, 0 }, RightHip = { 108, 0, 0 }, RightKnee = { -130, 0, 0 }, LeftKnee = { -10, 0, 0 }, LeftShoulder = { 60, 0, -10 }, RightShoulder = { 60, 0, 10 }, LeftElbow = { 95, 0, 0 }, RightElbow = { 95, 0, 0 } }),
			stance(0.26, { Root = { -10, 0, 0 }, RightHip = { 90, 0, 0 }, RightKnee = { -125, 0, 0 }, LeftShoulder = { 60, 0, -10 }, RightShoulder = { 60, 0, 10 }, LeftElbow = { 95, 0, 0 }, RightElbow = { 95, 0, 0 } }),
			stance(0.4),
		},
	},
	-- Teep: chamber the knee, push the foot straight through their middle.
	FrontKick = {
		Duration = 0.46,
		Keys = {
			stance(0),
			stance(0.08, { Root = { 6, 0, 0 }, RightHip = { 70, 0, 0 }, RightKnee = { -95, 0, 0 }, LeftKnee = { -12, 0, 0 } }),
			stance(0.18, { Root = { 14, 0, 0 }, RightHip = { 95, 0, 0 }, RightKnee = { -5, 0, 0 }, LeftKnee = { -10, 0, 0 }, LeftShoulder = { 45, 0, -20 }, RightShoulder = { 25, 0, 20 }, LeftElbow = { 100, 0, 0 }, RightElbow = { 90, 0, 0 } }),
			stance(0.32, { Root = { 6, 0, 0 }, RightHip = { 60, 0, 0 }, RightKnee = { -55, 0, 0 } }),
			stance(0.46),
		},
	},
	-- The charge before a drop kick: a flat-out sprint, one full stride (it loops): leaning
	-- hard into it, head up on the target, knees driving high, arms pumping from the
	-- shoulder, the back foot kicking up behind.
	SprintCharge = {
		Duration = 0.34,
		Keys = {
			{ T = 0, RootPos = { 0, -0.1, 0 }, Root = { -26, 8, 0 }, Waist = { -6, -10, 0 }, Neck = { 22, 0, 0 }, LeftHip = { 72, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { -38, 0, 0 }, RightKnee = { -95, 0, 0 }, LeftShoulder = { -48, 0, -6 }, LeftElbow = { 95, 0, 0 }, RightShoulder = { 72, 0, 6 }, RightElbow = { 95, 0, 0 } },
			{ T = 0.085, RootPos = { 0, 0.15, 0 }, Root = { -26, 0, 0 }, Waist = { -6, 0, 0 }, Neck = { 22, 0, 0 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightHip = { 10, 0, 0 }, RightKnee = { -120, 0, 0 }, LeftShoulder = { 10, 0, -6 }, LeftElbow = { 95, 0, 0 }, RightShoulder = { 10, 0, 6 }, RightElbow = { 95, 0, 0 } },
			{ T = 0.17, RootPos = { 0, -0.1, 0 }, Root = { -26, -8, 0 }, Waist = { -6, 10, 0 }, Neck = { 22, 0, 0 }, LeftHip = { -38, 0, 0 }, LeftKnee = { -95, 0, 0 }, RightHip = { 72, 0, 0 }, RightKnee = { -40, 0, 0 }, LeftShoulder = { 72, 0, -6 }, LeftElbow = { 95, 0, 0 }, RightShoulder = { -48, 0, 6 }, RightElbow = { 95, 0, 0 } },
			{ T = 0.255, RootPos = { 0, 0.15, 0 }, Root = { -26, 0, 0 }, Waist = { -6, 0, 0 }, Neck = { 22, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -120, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -20, 0, 0 }, LeftShoulder = { 10, 0, -6 }, LeftElbow = { 95, 0, 0 }, RightShoulder = { 10, 0, 6 }, RightElbow = { 95, 0, 0 } },
			{ T = 0.34, RootPos = { 0, -0.1, 0 }, Root = { -26, 8, 0 }, Waist = { -6, -10, 0 }, Neck = { 22, 0, 0 }, LeftHip = { 72, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { -38, 0, 0 }, RightKnee = { -95, 0, 0 }, LeftShoulder = { -48, 0, -6 }, LeftElbow = { 95, 0, 0 }, RightShoulder = { 72, 0, 6 }, RightElbow = { 95, 0, 0 } },
		},
	},
	-- Drop kick (after the sprint): plant and spring, the body lays back nearly flat in the
	-- air, both legs together driving the feet into them, arms flung out for balance; then
	-- the fall onto the back, a sit-up and back onto the feet.
	DropKick = {
		Duration = 1.3,
		Markers = { { 0.12, "Whoosh" }, { 0.26, "Hit" }, { 0.82, "Land" } },
		Keys = {
			{ T = 0, RootPos = { 0, -0.5, 0 }, Root = { -22, 0, 0 }, Neck = { 10, 0, 0 }, LeftHip = { 55, 0, 0 }, RightHip = { 50, 0, 0 }, LeftKnee = { -85, 0, 0 }, RightKnee = { -80, 0, 0 }, LeftShoulder = { -45, 0, -20 }, RightShoulder = { -45, 0, 20 }, LeftElbow = { 30, 0, 0 }, RightElbow = { 30, 0, 0 } },
			{ T = 0.12, RootPos = { 0, 0.4, 0 }, Root = { 40, 0, 0 }, Neck = { -15, 0, 0 }, LeftHip = { 70, 0, 0 }, RightHip = { 70, 0, 0 }, LeftKnee = { -75, 0, 0 }, RightKnee = { -70, 0, 0 }, LeftShoulder = { 60, 0, -30 }, RightShoulder = { 60, 0, 30 }, LeftElbow = { 40, 0, 0 }, RightElbow = { 40, 0, 0 } },
			-- the strike: flat out, feet first
			{ T = 0.26, RootPos = { 0, 0.8, 0 }, Root = { 84, 0, 0 }, Neck = { -38, 0, 0 }, LeftHip = { 14, 0, 2 }, RightHip = { 10, 0, -2 }, LeftKnee = { -3, 0, 0 }, RightKnee = { -6, 0, 0 }, LeftShoulder = { -70, 0, -62 }, RightShoulder = { -70, 0, 62 }, LeftElbow = { 18, 0, 0 }, RightElbow = { 18, 0, 0 } },
			{ T = 0.42, RootPos = { 0, 0.7, 0 }, Root = { 86, 0, 0 }, Neck = { -36, 0, 0 }, LeftHip = { 18, 0, 2 }, RightHip = { 14, 0, -2 }, LeftKnee = { -10, 0, 0 }, RightKnee = { -14, 0, 0 }, LeftShoulder = { -60, 0, -62 }, RightShoulder = { -60, 0, 62 }, LeftElbow = { 22, 0, 0 }, RightElbow = { 22, 0, 0 } },
			-- falling: arms reaching back to break the fall
			{ T = 0.62, RootPos = { 0, -0.6, 0 }, Root = { 82, 0, 0 }, Neck = { -20, 0, 0 }, LeftHip = { 45, 0, 0 }, RightHip = { 40, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightKnee = { -35, 0, 0 }, LeftShoulder = { -20, 0, -55 }, RightShoulder = { -20, 0, 55 }, LeftElbow = { 20, 0, 0 }, RightElbow = { 20, 0, 0 } },
			-- down on the back, sitting up
			{ T = 0.82, RootPos = { 0, -2.0, 0 }, Root = { 66, 0, 0 }, Neck = { -24, 0, 0 }, LeftHip = { 78, 0, 0 }, RightHip = { 75, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightKnee = { -36, 0, 0 }, LeftShoulder = { -38, 0, -22 }, RightShoulder = { -38, 0, 22 }, LeftElbow = { 28, 0, 0 }, RightElbow = { 28, 0, 0 } },
			-- feet under, rising
			{ T = 1.02, RootPos = { 0, -1.3, 0 }, Root = { 24, 0, 0 }, Neck = { -10, 0, 0 }, LeftHip = { 108, 0, 0 }, RightHip = { 96, 0, 0 }, LeftKnee = { -125, 0, 0 }, RightKnee = { -112, 0, 0 }, LeftShoulder = { 30, 0, -20 }, RightShoulder = { 30, 0, 20 }, LeftElbow = { 40, 0, 0 }, RightElbow = { 40, 0, 0 } },
			stance(1.3),
		},
	},

	------------------------------------------------------------------------------------
	-- Counters (attack right after a step back)
	------------------------------------------------------------------------------------
	-- SUPERMAN PUNCH (step back, then P): sink, fake the knee, kick the back leg out behind
	-- and fly in with the rear straight, body stretched out like Superman, then land in
	-- stance right on top of them.
	SupermanPunch = {
		Duration = 0.55,
		Keys = {
			stance(0, { RootPos = { 0, -0.45, 0.2 }, Root = { -6, -18, 0 }, LeftHip = { 30, 0, 0 }, LeftKnee = { -46, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -52, 0, 0 } }),
			stance(0.08, { RootPos = { 0, 0.5, -0.8 }, Root = { -14, -12, 0 }, LeftHip = { 58, 0, 0 }, LeftKnee = { -84, 0, 0 }, RightHip = { -32, 0, 0 }, RightKnee = { -72, 0, 0 }, RightShoulder = { -28, 0, 22 }, RightElbow = { 46, 0, 0 }, LeftShoulder = { 82, 0, -10 }, LeftElbow = { 40, 0, 0 } }),
			stance(0.17, { RootPos = { 0, 0.65, -1.9 }, Root = { -26, 32, 0 }, Waist = { -8, 30, 0 }, Neck = { -18, -10, 0 }, RightShoulder = { 101, -8, -6 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { -36, 0, -22 }, LeftElbow = { 22, 0, 0 }, RightHip = { -58, 0, 0 }, RightKnee = { -22, 0, 0 }, LeftHip = { 22, 0, 0 }, LeftKnee = { -42, 0, 0 } }),
			stance(0.26, { RootPos = { 0, 0.45, -1.9 }, Root = { -25, 30, 0 }, Waist = { -8, 28, 0 }, Neck = { -18, -10, 0 }, RightShoulder = { 99, -8, -6 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { -30, 0, -22 }, LeftElbow = { 26, 0, 0 }, RightHip = { -50, 0, 0 }, RightKnee = { -26, 0, 0 }, LeftHip = { 24, 0, 0 }, LeftKnee = { -44, 0, 0 } }),
			stance(0.38, { RootPos = { 0, -0.4, -1.2 }, Root = { -14, 18, 0 }, LeftHip = { 46, 0, 0 }, LeftKnee = { -56, 0, 0 }, RightHip = { -16, 0, 0 }, RightShoulder = { 70, 0, 6 }, RightElbow = { 62, 0, 0 } }),
			stance(0.55),
		},
	},
	-- HEAD HUNTER (step back, then K): the step-in head kick. Load on bent knees, skip in
	-- off the back foot, the lead foot turns out as the rear knee chambers, then rise onto
	-- the ball of the standing foot and the hip turns completely over: the leg whips round
	-- straight, shin-first, at head height, leaning away with the rear arm flung back for
	-- balance and the lead glove on the chin. It follows through past them, then the leg
	-- recoils and you land back in stance.
	-- (Rebuilt from measurements: the old one turned the hips the wrong way and landed
	-- the foot at CHEST height, 2.5 studs out, while the step-in stopped 3.2 from them.
	-- The impact now uses the measured head-kick contact: foot 1.9 out, centred, at head
	-- height; the dash in (Lunge) carries you to exactly that range.)
	CounterHeadKick = {
		Duration = 0.72,
		Markers = { { 0.1, "StepL" }, { 0.22, "Whoosh" }, { 0.3, "Hit" }, { 0.56, "Land" } },
		Keys = {
			-- load on bent knees
			stance(0, { RootPos = { 0, -0.35, 0.1 }, LeftKnee = { -40, 0, 0 }, RightKnee = { -46, 0, 0 } }),
			-- skip in off the back foot, the rear knee chambering
			stance(0.1, { RootPos = { 0, 0.15, -0.3 }, Root = { 0, -15, 0 }, RightHip = { 30, 0, 30 }, RightKnee = { -70, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightShoulder = { -20, 0, 30 }, RightElbow = { 30, 0, 0 } }),
			-- rising onto the ball of the foot, the hip starting to turn over
			stance(0.2, { RootPos = { 0, 0.45, -0.3 }, Root = { 12, 45, 12 }, Neck = { -6, -30, 0 }, RightHip = { 10, 0, 70 }, RightKnee = { -40, 0, 0 }, LeftKnee = { -24, 0, 0 }, RightShoulder = { -26, 0, 40 }, RightElbow = { 20, 0, 0 } }),
			-- IMPACT: hip all the way over, leg straight, shin through the head
			stance(0.3, { RootPos = { 0, 0.6, -0.3 }, Root = { 25, 90, 25 }, Neck = { -6, -60, 0 }, RightHip = { 0, 0, 90 }, RightKnee = { -4, 0, 0 }, LeftHip = { 0, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightShoulder = { -36, 0, 46 }, RightElbow = { 14, 0, 0 } }),
			-- follow-through: the leg carries on round past them
			stance(0.42, { RootPos = { 0, 0.3, -0.3 }, Root = { 14, 125, 15 }, Neck = { 0, -75, 0 }, RightHip = { 0, 0, 55 }, RightKnee = { -60, 0, 0 }, LeftHip = { 0, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightShoulder = { 10, 0, 40 }, RightElbow = { 40, 0, 0 } }),
			-- recoil and land back in stance
			stance(0.56, { RootPos = { 0, -0.1, -0.2 }, Root = { 4, 40, 0 }, RightHip = { 20, 0, 10 }, RightKnee = { -80, 0, 0 } }),
			stance(0.72),
		},
	},

	------------------------------------------------------------------------------------
	-- Weapons (right hand; the scythe two-handed). Full-body swings: the hips and
	-- shoulders wind right round and the weapon travels the whole arc through the target.
	------------------------------------------------------------------------------------
	-- REAP: coil right round with the scythe raised high behind the right shoulder, eyes on
	-- them, then explode: step through low, hips whipping round, the blade tearing across
	-- in a huge flat arc and carrying on past them, the body following it right through.
	ScytheReap = {
		Duration = 0.66,
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			{ T = 0.15, RootPos = { 0.25, -0.4, 0.35 }, Root = { 6, 72, 0 }, Waist = { 0, 46, 0 }, Neck = { -6, -34, 0 }, RightShoulder = { 132, 0, 82 }, RightElbow = { 58, 0, 0 }, LeftShoulder = { 102, 0, 52 }, LeftElbow = { 80, 0, 0 }, LeftKnee = { -36, 0, 0 }, RightKnee = { -48, 0, 0 }, RightHip = { -6, 0, 0 } },
			{ T = 0.27, RootPos = { -0.3, -0.6, -1.25 }, Root = { -16, -72, 0 }, Waist = { -10, -50, 0 }, Neck = { -10, 40, 0 }, RightShoulder = { 88, 0, -66 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 86, 0, -30 }, LeftElbow = { 18, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightHip = { -32, -32, 0 }, RightKnee = { -18, 0, 0 } },
			{ T = 0.4, RootPos = { -0.35, -0.65, -1.35 }, Root = { -20, -98, 0 }, Waist = { -12, -62, 0 }, Neck = { -10, 50, 0 }, RightShoulder = { 60, 0, -82 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 60, 0, -52 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 48, 0, 0 }, LeftKnee = { -58, 0, 0 }, RightHip = { -30, -34, 0 } },
			{ T = 0.66, RootPos = { 0, -0.15, -0.6 }, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- RETURN: the backswing, launched off the ground: a hop as the blade rips back across the
	-- other way, landing in a deep crouch with the blade low behind.
	ScytheReturn = {
		Duration = 0.66,
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			{ T = 0.12, RootPos = { -0.2, -0.35, 0.2 }, Root = { 4, -76, 0 }, Waist = { 0, -46, 0 }, Neck = { -6, 36, 0 }, RightShoulder = { 96, 0, -82 }, RightElbow = { 82, 0, 0 }, LeftShoulder = { 92, 0, -72 }, LeftElbow = { 40, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightKnee = { -44, 0, 0 } },
			{ T = 0.26, RootPos = { 0.3, 0.55, -1.1 }, Root = { -12, 72, 0 }, Waist = { -8, 50, 0 }, Neck = { -8, -40, 0 }, RightShoulder = { 90, 0, 78 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 90, 0, 36 }, LeftElbow = { 24, 0, 0 }, RightHip = { 42, 0, 0 }, RightKnee = { -62, 0, 0 }, LeftHip = { -10, 0, 0 }, LeftKnee = { -50, 0, 0 } },
			{ T = 0.4, RootPos = { 0.3, -0.6, -1.25 }, Root = { -18, 96, 0 }, Waist = { -10, 56, 0 }, Neck = { -8, -48, 0 }, RightShoulder = { 56, 0, 86 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 60, 0, 42 }, LeftElbow = { 36, 0, 0 }, RightHip = { 48, 0, 0 }, RightKnee = { -58, 0, 0 }, LeftKnee = { -56, 0, 0 } },
			{ T = 0.66, RootPos = { 0, -0.15, -0.6 }, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- WHIRL (finisher): coil low, then LEAP into a full spin in the air with the scythe at
	-- arm's length, a reaping circle all the way round, and slam it down on landing.
	ScytheWhirl = {
		Duration = 0.95,
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			{ T = 0.15, RootPos = { 0, -0.65, 0 }, Root = { 2, 62, 0 }, Waist = { 0, 34, 0 }, RightShoulder = { 96, 0, 80 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 90, 0, 30 }, LeftElbow = { 40, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightKnee = { -64, 0, 0 }, LeftHip = { 30, 0, 0 }, RightHip = { 26, 0, 0 } },
			{ T = 0.3, RootPos = { 0, 1.5, 0 }, Root = { -6, -110, 0 }, Waist = { -4, -30, 0 }, RightShoulder = { 92, 0, -36 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 88, 0, -8 }, LeftElbow = { 18, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -80, 0, 0 } },
			{ T = 0.48, RootPos = { 0, 1.8, 0 }, Root = { -6, -290, 0 }, Waist = { -4, -30, 0 }, RightShoulder = { 92, 0, -36 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 88, 0, -8 }, LeftElbow = { 18, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -80, 0, 0 } },
			{ T = 0.64, RootPos = { 0, -0.75, -0.6 }, Root = { -30, -360, 0 }, Waist = { -14, -10, 0 }, RightShoulder = { 40, 0, -28 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 46, 0, -14 }, LeftElbow = { 14, 0, 0 }, LeftHip = { 52, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -60, 0, 0 } },
			{ T = 0.95, Root = { 0, -360, 0 }, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- HARVEST (Reaper Scythe P P K): drop into a deep crouch with the blade hooked low in
	-- front, behind their legs, then explode upward, both arms ripping the scythe up through
	-- them and on over your head, rising onto your toes, eyes following them into the sky.
	ScytheHarvest = {
		Duration = 0.9,
		Markers = { { 0.16, "Whoosh" }, { 0.28, "Hit" } },
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			-- hooked low: crouched deep, the blade down at their ankles (pose lab grid, measured:
			-- the tip just off the floor 6.5 studs out in front; the snath runs along the
			-- forearms, so the arms reach well forward to keep it out of the ground)
			{ T = 0.16, RootPos = { 0, -1.0, -0.4 }, Root = { -30, 0, 0 }, Waist = { -10, 0, 0 }, Neck = { 10, 0, 0 }, RightShoulder = { 85, 0, 30 }, RightElbow = { 35, 0, 0 }, LeftShoulder = { 95, 0, 10 }, LeftElbow = { 45, 0, 0 }, LeftHip = { 60, 0, 0 }, LeftKnee = { -90, 0, 0 }, RightHip = { 20, 0, 0 }, RightKnee = { -90, 0, 0 } },
			-- the Hit frame: on its way up through them (the in-between pose, so the motion is
			-- unchanged and an exported asset keeps the marker)
			{ T = 0.28, RootPos = { 0, -0.22, -0.72 }, Root = { -6.7, 6.5, 0 }, Waist = { 0.4, 3.9, 0 }, Neck = { 16.5, 0, 0 }, RightShoulder = { 127, 0, 17 }, RightElbow = { 25.3, 0, 0 }, LeftShoulder = { 124, 0, -3 }, LeftElbow = { 35.3, 0, 0 }, LeftHip = { 34.1, 0, 0 }, LeftKnee = { -44.6, 0, 0 }, RightHip = { 0.6, 0, 0 }, RightKnee = { -38.2, 0, 0 } },
			-- RIP UP: rising out of the crouch, the blade tearing up through them
			{ T = 0.36, RootPos = { 0, 0.2, -0.9 }, Root = { 6, 10, 0 }, Waist = { 6, 6, 0 }, Neck = { 20, 0, 0 }, RightShoulder = { 150, 0, 10 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 140, 0, -10 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -10, 0, 0 } },
			-- carried on over the head, up on the toes, watching them fly
			{ T = 0.52, RootPos = { 0, 0.5, -0.9 }, Root = { 14, 10, 0 }, Waist = { 8, 6, 0 }, Neck = { 28, 0, 0 }, RightShoulder = { 190, 0, 10 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 175, 0, -10 }, LeftElbow = { 50, 0, 0 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -10, 0, 0 }, RightHip = { -14, 0, 0 }, RightKnee = { -8, 0, 0 } },
			{ T = 0.9, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- Blade forehand: cocked back by the right ear (shoulders turned away), then the body
	-- unwinds and rips the blade across through the target. On the hit frame the blade runs
	-- straight out through them like a clock hand passing twelve (pose lab, measured: the
	-- tip 6.5 out, crossing the centre line at waist height).
	BladeForehand = {
		Duration = 0.4,
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			{ T = 0.06, Root = { 0, -36, 0 }, Waist = { 0, -42, 0 }, RightShoulder = { 72, 0, 84 }, RightElbow = { 52, 0, 0 }, LeftShoulder = { 45, 0, -20 }, LeftElbow = { 60, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -24, 0, 0 }, Wrist = { -70, 0, 0 } },
			{ T = 0.15, Root = { -8, -8, 0 }, Waist = { -8, -10, 0 }, RightShoulder = { 86, 0, -30 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 28, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightHip = { -12, 0, 0 }, Wrist = { -80, 0, 0 } },
			{ T = 0.26, Root = { -4, 40, 0 }, Waist = { -4, 46, 0 }, RightShoulder = { 56, 0, -76 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 40, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.4, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},
	-- Blade backhand: the return swing straight back across, the body unwinding the other way
	-- (the same blade-through-them hit frame).
	BladeBackhand = {
		Duration = 0.4,
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			{ T = 0.06, Root = { 0, 36, 0 }, Waist = { 0, 42, 0 }, RightShoulder = { 78, 0, -72 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 45, 0, -20 }, LeftElbow = { 60, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -24, 0, 0 }, Wrist = { -70, 0, 0 } },
			{ T = 0.15, Root = { -8, -8, 0 }, Waist = { -8, -10, 0 }, RightShoulder = { 86, 0, -30 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 40, 0, 0 }, RightHip = { 26, 0, 0 }, RightKnee = { -30, 0, 0 }, Wrist = { -80, 0, 0 } },
			{ T = 0.26, Root = { -4, -40, 0 }, Waist = { -4, -46, 0 }, RightShoulder = { 56, 0, 82 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 40, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.4, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},
	-- Blade cleave: over the top and diagonally down through them.
	BladeCleave = {
		Duration = 0.5,
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			{ T = 0.1, Root = { 8, 22, 0 }, Waist = { 4, 20, 0 }, RightShoulder = { 172, 0, 22 }, RightElbow = { 42, 0, 0 }, LeftShoulder = { 60, 0, -20 }, LeftElbow = { 40, 0, 0 } },
			{ T = 0.2, Root = { -22, -24, 0 }, Waist = { -8, -20, 0 }, RightShoulder = { 42, 0, -34 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 60, 0, 0 }, LeftHip = { 42, 0, 0 }, LeftKnee = { -46, 0, 0 }, RightHip = { -20, 0, 0 } },
			{ T = 0.32, Root = { -16, -20, 0 }, RightShoulder = { 30, 0, -40 }, RightElbow = { 10, 0, 0 }, LeftHip = { 36, 0, 0 }, LeftKnee = { -40, 0, 0 } },
			{ T = 0.5, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},
	-- Straight stab: the hand drawn back to the hip with the point already forward, then step
	-- in on the front foot and drive it straight through them, the blade running on from the
	-- forearm (pose lab, measured: the tip 7.2 out on the centre line at stomach height).
	Thrust = {
		Duration = 0.5,
		Keys = {
			{ T = 0 },
			{ T = 0.08, Root = { 4, 0, 0 }, Waist = { 0, -20, 0 }, RightShoulder = { -20, 0, 10 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 60, 0, -20 }, LeftElbow = { 80, 0, 0 }, Wrist = { -85, 0, 0 } },
			{ T = 0.16, Root = { -18, 0, 0 }, Waist = { 0, 10, 0 }, RightShoulder = { 92, 0, -8 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 30, 0, -25 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 45, 0, 0 }, LeftKnee = { -42, 0, 0 }, RightHip = { -25, 0, 0 }, Wrist = { -76, 0, 0 } },
			{ T = 0.3, Root = { -14, 0, 0 }, Waist = { 0, 10, 0 }, RightShoulder = { 88, 0, -8 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 30, 0, -25 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { -20, 0, 0 }, Wrist = { -76, 0, 0 } },
			{ T = 0.5 },
		},
	},
	-- GUT STAB (Rust Blade P P K): draw the blade back low at the hip, then lunge in under
	-- their guard and drive it up into the stomach, the free hand grabbing their shoulder.
	-- It sticks: you lean into it, twist it, eyes locked on theirs, then wrench it out with
	-- the whole body, shoving them off it, and flick the blood off to the side.
	-- (MeleeService.Impale holds them on the blade for the hold; the rip lands at 1.24 s.)
	BladeGutStab = {
		Duration = 1.75,
		Markers = { { 0.12, "Whoosh" }, { 0.24, "Hit" }, { 1.26, "Rip" } },
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			-- draw back: coiled right, the blade low at the hip, point forward
			{ T = 0.12, RootPos = { 0, -0.35, 0.25 }, Root = { 6, -30, 0 }, Waist = { 2, -16, 0 }, Neck = { -8, 26, 0 }, RightShoulder = { -30, 0, 10 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 70, 0, -20 }, LeftElbow = { 50, 0, 0 }, LeftHip = { 30, 30, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { -10, 30, 0 }, RightKnee = { -40, 0, 0 } },
			-- IN: lunging deep off the front leg, the blade driven up into the stomach and on
			-- through (measured in the pose lab: the tip on the centre line at stomach height,
			-- 6.5 studs out; Contact.BladeGutStab puts it through them and out the back)
			{ T = 0.24, RootPos = { 0, -0.5, -1.3 }, Root = { -18, 4, 0 }, Waist = { -8, 2, 0 }, Neck = { -16, -4, 0 }, RightShoulder = { 52, 0, -10 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 100, 0, -12 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 58, -4, 0 }, LeftKnee = { -68, 0, 0 }, RightHip = { -26, -4, 0 }, RightKnee = { -12, 0, 0 } },
			-- it sticks: lean in and push it deeper...
			{ T = 0.55, RootPos = { 0, -0.55, -1.38 }, Root = { -20, 6, 0 }, Waist = { -9, 3, 0 }, Neck = { -20, -4, 0 }, RightShoulder = { 54, 0, -8 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 102, 0, -12 }, LeftElbow = { 42, 0, 0 }, LeftHip = { 60, -6, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { -27, -6, 0 }, RightKnee = { -12, 0, 0 } },
			-- ...and twist it
			{ T = 0.9, RootPos = { 0, -0.55, -1.36 }, Root = { -19, 8, 0 }, Waist = { -9, 4, 0 }, Neck = { -20, -6, 0 }, RightShoulder = { 50, -14, -10 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 102, 0, -12 }, LeftElbow = { 42, 0, 0 }, LeftHip = { 60, -8, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { -27, -8, 0 }, RightKnee = { -12, 0, 0 } },
			{ T = 1.18, RootPos = { 0, -0.52, -1.3 }, Root = { -14, 8, 0 }, Waist = { -6, 4, 0 }, Neck = { -18, -6, 0 }, RightShoulder = { 50, -14, -10 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 100, 0, -12 }, LeftElbow = { 36, 0, 0 }, LeftHip = { 58, -8, 0 }, LeftKnee = { -68, 0, 0 }, RightHip = { -26, -8, 0 }, RightKnee = { -12, 0, 0 } },
			-- RIP: wrench it out with the whole body, the free hand shoving them off the blade
			{ T = 1.26, RootPos = { 0, -0.35, -0.5 }, Root = { -2, -20, 0 }, Waist = { 2, -14, 0 }, Neck = { -8, 10, 0 }, RightShoulder = { -40, 0, 30 }, RightElbow = { 50, 0, 0 }, LeftShoulder = { 82, 0, -8 }, LeftElbow = { 0, 0, 0 }, LeftHip = { 40, 20, 0 }, LeftKnee = { -40, 0, 0 }, RightHip = { -30, 20, 0 }, RightKnee = { -20, 0, 0 } },
			-- and flick it clean off to the side
			{ T = 1.48, RootPos = { 0, -0.2, -0.25 }, Root = { 0, -6, 0 }, RightShoulder = { 60, 0, 50 }, RightElbow = { 80, 0, 0 }, LeftShoulder = { 30, 0, -20 }, LeftElbow = { 40, 0, 0 } },
			{ T = 1.75, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},
	-- Whip crack: the arm goes up and back, then snaps forward and down; the chain itself is
	-- physics, flung out along the swing (MeleeController lashes it).
	WhipCrack = {
		Duration = 0.6,
		Keys = {
			{ T = 0, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } },
			{ T = 0.15, Root = { 6, 18, 0 }, Waist = { 10, 24, 0 }, RightShoulder = { 176, 0, 16 }, RightElbow = { 62, 0, 0 }, LeftShoulder = { 45, 0, -25 }, LeftElbow = { 50, 0, 0 }, RightHip = { -14, 0, 0 } },
			{ T = 0.27, Root = { -12, -16, 0 }, Waist = { -12, -14, 0 }, RightShoulder = { 96, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 25, 0, -30 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 34, 0, 0 }, LeftKnee = { -36, 0, 0 } },
			{ T = 0.36, Root = { -8, -12, 0 }, Waist = { -8, -10, 0 }, RightShoulder = { 58, 0, 0 }, RightElbow = { 12, 0, 0 } },
			{ T = 0.6, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } },
		},
	},
	-- CHAIN SNARE (Chain Whip P P K): crack it out so it wraps them, then grab the chain
	-- with both hands and HAUL, leaning right back, dragging them in off their feet, and
	-- meet them with both hands on their head and a knee driven up into the face.
	-- (MeleeService.Snare: the haul starts at 0.44 s, the knee lands at 0.78 s.)
	WhipSnare = {
		Duration = 1.15,
		Markers = { { 0.15, "Whoosh" }, { 0.3, "Hit" }, { 0.78, "Knee" } },
		Keys = {
			{ T = 0, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } },
			{ T = 0.15, Root = { 6, 18, 0 }, Waist = { 10, 24, 0 }, RightShoulder = { 176, 0, 16 }, RightElbow = { 62, 0, 0 }, LeftShoulder = { 45, 0, -25 }, LeftElbow = { 50, 0, 0 }, RightHip = { -14, 0, 0 } },
			-- the crack that wraps them (on the Hit frame, so an exported asset keeps the marker)
			{ T = 0.3, Root = { -12, -16, 0 }, Waist = { -12, -14, 0 }, RightShoulder = { 96, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 70, 0, -10 }, LeftElbow = { 30, 0, 0 }, LeftHip = { 34, 0, 0 }, LeftKnee = { -36, 0, 0 } },
			-- both hands on the chain, sitting back into the haul
			{ T = 0.44, RootPos = { 0, -0.35, 0.6 }, Root = { 16, 8, 0 }, Waist = { 8, 4, 0 }, Neck = { -10, -6, 0 }, RightShoulder = { 50, 0, 10 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 80, 0, -10 }, LeftElbow = { 60, 0, 0 }, LeftHip = { -10, -8, 0 }, LeftKnee = { -30, 0, 0 }, RightHip = { 30, -8, 0 }, RightKnee = { -50, 0, 0 } },
			-- hauled in past the hip
			{ T = 0.62, RootPos = { 0, -0.25, 0.4 }, Root = { 10, 10, 0 }, Waist = { 4, 6, 0 }, Neck = { -10, -6, 0 }, RightShoulder = { -20, 0, 20 }, RightElbow = { 100, 0, 0 }, LeftShoulder = { 30, 0, -20 }, LeftElbow = { 110, 0, 0 }, LeftHip = { 6, -10, 0 }, LeftKnee = { -26, 0, 0 }, RightHip = { 16, -10, 0 }, RightKnee = { -36, 0, 0 } },
			-- KNEE: both hands on their head, the knee driven up into it
			{ T = 0.78, RootPos = { 0, 0.1, -0.3 }, Root = { -14, 0, 0 }, Waist = { -6, 0, 0 }, Neck = { -18, 0, 0 }, RightShoulder = { 100, 0, -14 }, RightElbow = { 60, 0, 0 }, LeftShoulder = { 100, 0, 14 }, LeftElbow = { 60, 0, 0 }, LeftHip = { 0, 0, 0 }, LeftKnee = { -10, 0, 0 }, RightHip = { 110, 0, 0 }, RightKnee = { -120, 0, 0 } },
			{ T = 0.92, RootPos = { 0, 0, -0.25 }, Root = { -10, 0, 0 }, Neck = { -14, 0, 0 }, RightShoulder = { 90, 0, -14 }, RightElbow = { 70, 0, 0 }, LeftShoulder = { 90, 0, 14 }, LeftElbow = { 70, 0, 0 }, LeftKnee = { -12, 0, 0 }, RightHip = { 90, 0, 0 }, RightKnee = { -110, 0, 0 } },
			{ T = 1.15, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } },
		},
	},
	-- Whip sweep: the chain swung flat round in a big circle at waist height.
	WhipSweep = {
		Duration = 0.85,
		Keys = {
			{ T = 0, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } },
			{ T = 0.16, Root = { 0, 48, 0 }, Waist = { 0, 36, 0 }, RightShoulder = { 88, 0, 84 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 40, 0, -30 }, LeftElbow = { 50, 0, 0 }, LeftKnee = { -24, 0, 0 }, RightKnee = { -28, 0, 0 } },
			{ T = 0.38, Root = { -6, -62, 0 }, Waist = { -6, -44, 0 }, RightShoulder = { 90, 0, -66 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 30, 0, -40 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 26, 0, 0 }, LeftKnee = { -30, 0, 0 } },
			{ T = 0.6, Root = { -4, -72, 0 }, Waist = { -4, -50, 0 }, RightShoulder = { 58, 0, -80 }, RightElbow = { 10, 0, 0 } },
			{ T = 0.85, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } },
		},
	},
	-- Spear throw: lead arm points at the target, the spear cocked back over the shoulder,
	-- then the whole body unwinds and the arm whips through.
	SpearThrow = {
		Duration = 0.7,
		Keys = {
			{ T = 0, RightShoulder = { 125, 0, 22 }, RightElbow = { 100, 0, 0 } },
			{ T = 0.18, Root = { 10, 36, 0 }, Waist = { 6, 22, 0 }, RightShoulder = { 168, 0, 28 }, RightElbow = { 112, 0, 0 }, LeftShoulder = { 82, 0, -10 }, LeftElbow = { 15, 0, 0 }, LeftHip = { 26, 0, 0 }, RightHip = { -22, 0, 0 }, RightKnee = { -30, 0, 0 } },
			{ T = 0.32, Root = { -20, -32, 0 }, Waist = { -8, -22, 0 }, RightShoulder = { 96, 0, -12 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 20, 0, -30 }, LeftElbow = { 90, 0, 0 }, LeftHip = { 42, 0, 0 }, LeftKnee = { -38, 0, 0 }, RightHip = { -36, -20, 0 } },
			{ T = 0.5, Root = { -12, -36, 0 }, Waist = { -4, -24, 0 }, RightShoulder = { 46, 0, -32 }, RightElbow = { 10, 0, 0 }, LeftHip = { 36, 0, 0 }, LeftKnee = { -34, 0, 0 } },
			{ T = 0.7 },
		},
	},
	-- Magnet: arm locked straight out at them, braced and leaning back as it drags them in.
	MagnetPull = {
		Duration = 0.8,
		UpperBody = true,
		Keys = {
			{ T = 0, RightShoulder = { 80, 0, 0 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 60, 0, -25 }, LeftElbow = { 60, 0, 0 } },
			{ T = 0.12, Waist = { -6, 8, 0 }, RightShoulder = { 92, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 78, 0, -18 }, LeftElbow = { 36, 0, 0 } },
			{ T = 0.55, Waist = { 8, 8, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 90, 0, 0 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 78, 0, -18 }, LeftElbow = { 36, 0, 0 } },
			{ T = 0.8, RightShoulder = { 80, 0, 0 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 60, 0, -25 }, LeftElbow = { 60, 0, 0 } },
		},
	},

	------------------------------------------------------------------------------------
	-- SHOP exclusive weapons
	------------------------------------------------------------------------------------
	-- THUNDER HAMMER swings: two-handed like the scythe (the haft along the forearms), the
	-- same full-body sweeps, the head out at arm's length + 4 studs.
	HammerSwing = {
		Duration = 0.62,
		Markers = { { 0.16, "Whoosh" }, { 0.26, "Hit" } },
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			-- wound round to the right, the head out behind the right shoulder
			{ T = 0.13, RootPos = { 0.2, -0.35, 0.3 }, Root = { 4, -70, 0 }, Waist = { 0, -40, 0 }, Neck = { -6, 42, 0 }, RightShoulder = { 92, 0, -10 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 92, 0, 10 }, LeftElbow = { 22, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightKnee = { -36, 0, 0 } },
			-- the Hit frame: arms straight out, the body turned square, the head dead ahead at
			-- belly height (measured: 7.1 studs out on the centre line)
			{ T = 0.26, RootPos = { 0, -0.4, -0.8 }, Root = { -10, 0, 0 }, Waist = { -4, 0, 0 }, Neck = { -8, 0, 0 }, RightShoulder = { 96, 0, -10 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 96, 0, 10 }, LeftElbow = { 16, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -50, 0, 0 }, RightHip = { -20, 0, 0 }, RightKnee = { -20, 0, 0 } },
			-- carried on round to the left
			{ T = 0.4, RootPos = { -0.2, -0.4, -0.9 }, Root = { -12, 80, 0 }, Waist = { -6, 44, 0 }, Neck = { -8, -40, 0 }, RightShoulder = { 90, 0, -10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 90, 0, 10 }, LeftElbow = { 18, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -50, 0, 0 } },
			{ T = 0.62, RootPos = { 0, -0.15, -0.6 }, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	HammerBackswing = {
		Duration = 0.62,
		Markers = { { 0.16, "Whoosh" }, { 0.26, "Hit" } },
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			{ T = 0.13, RootPos = { -0.2, -0.35, 0.3 }, Root = { 4, 70, 0 }, Waist = { 0, 40, 0 }, Neck = { -6, -42, 0 }, RightShoulder = { 92, 0, -10 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 92, 0, 10 }, LeftElbow = { 22, 0, 0 }, LeftKnee = { -36, 0, 0 }, RightKnee = { -30, 0, 0 } },
			{ T = 0.26, RootPos = { 0, -0.4, -0.8 }, Root = { -10, 0, 0 }, Waist = { -4, 0, 0 }, Neck = { -8, 0, 0 }, RightShoulder = { 96, 0, -10 }, RightElbow = { 8, 0, 0 }, LeftShoulder = { 96, 0, 10 }, LeftElbow = { 16, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -50, 0, 0 }, LeftHip = { -20, 0, 0 }, LeftKnee = { -20, 0, 0 } },
			{ T = 0.4, RootPos = { 0.2, -0.4, -0.9 }, Root = { -12, -80, 0 }, Waist = { -6, -44, 0 }, Neck = { -8, 40, 0 }, RightShoulder = { 90, 0, -10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 90, 0, 10 }, LeftElbow = { 18, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -50, 0, 0 } },
			{ T = 0.62, RootPos = { 0, -0.15, -0.6 }, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- HAMMER SMASH (P P P): heave it straight up overhead, leaning back on the heels, then
	-- bring it down with everything, folding over it, the head cracking into the floor in
	-- front of them (and through them) on the Hit frame; drag it back up.
	HammerSmash = {
		Duration = 0.9,
		Markers = { { 0.3, "Whoosh" }, { 0.42, "Hit" }, { 0.42, "Land" } },
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			{ T = 0.22, RootPos = { 0, 0.1, 0.3 }, Root = { 14, 0, 0 }, Waist = { 8, 0, 0 }, Neck = { 10, 0, 0 }, RightShoulder = { 175, 0, 10 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 170, 0, -10 }, LeftElbow = { 50, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightKnee = { -24, 0, 0 } },
			-- (measured: the head's underside on the floor 7.7 studs out)
			{ T = 0.42, RootPos = { 0, -0.7, -1.0 }, Root = { -30, 0, 0 }, Waist = { -14, 0, 0 }, Neck = { -6, 0, 0 }, RightShoulder = { 110, 0, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 116, 0, -6 }, LeftElbow = { 14, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightHip = { -20, 0, 0 }, RightKnee = { -30, 0, 0 } },
			{ T = 0.62, RootPos = { 0, -0.7, -1.0 }, Root = { -29, 0, 0 }, Waist = { -14, 0, 0 }, Neck = { -6, 0, 0 }, RightShoulder = { 111, 0, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 117, 0, -6 }, LeftElbow = { 14, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightHip = { -20, 0, 0 }, RightKnee = { -30, 0, 0 } },
			{ T = 0.9, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- EARTHSHAKER (Thunder Hammer P P K): sink deep with the hammer dragged back low, then
	-- spring up and forward (the Lunge carries you in) with it raised over your head, legs
	-- tucked, and come down with it into the floor in front of you on the Hit frame: the
	-- ground cracks and they're thrown up off it.
	HammerEarthshaker = {
		Duration = 1.2,
		Markers = { { 0.15, "StepL" }, { 0.42, "Whoosh" }, { 0.55, "Hit" }, { 0.55, "Land" } },
		Keys = {
			{ T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
			{ T = 0.15, RootPos = { 0, -0.75, 0.2 }, Root = { -12, 0, 0 }, Waist = { -6, 0, 0 }, RightShoulder = { -20, 0, 14 }, RightElbow = { 30, 0, 0 }, LeftShoulder = { 10, 0, -20 }, LeftElbow = { 40, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -80, 0, 0 }, RightHip = { 40, 0, 0 }, RightKnee = { -80, 0, 0 } },
			{ T = 0.35, RootPos = { 0, 1.6, -0.5 }, Root = { 12, 0, 0 }, Waist = { 6, 0, 0 }, Neck = { 10, 0, 0 }, RightShoulder = { 175, 0, 10 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 170, 0, -10 }, LeftElbow = { 50, 0, 0 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { 30, 0, 0 }, RightKnee = { -80, 0, 0 } },
			-- (the smash's measured floor contact: the head's underside on the floor 7.7 out)
			{ T = 0.55, RootPos = { 0, -0.7, -1.0 }, Root = { -30, 0, 0 }, Waist = { -14, 0, 0 }, Neck = { -8, 0, 0 }, RightShoulder = { 110, 0, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 116, 0, -6 }, LeftElbow = { 14, 0, 0 }, LeftHip = { 50, 0, 0 }, LeftKnee = { -60, 0, 0 }, RightHip = { -20, 0, 0 }, RightKnee = { -30, 0, 0 } },
			{ T = 0.85, RootPos = { 0, -0.7, -1.0 }, Root = { -29, 0, 0 }, Waist = { -14, 0, 0 }, RightShoulder = { 111, 0, 0 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { 117, 0, -6 }, LeftElbow = { 14, 0, 0 }, LeftHip = { 55, 0, 0 }, LeftKnee = { -70, 0, 0 }, RightHip = { -20, 0, 0 }, RightKnee = { -40, 0, 0 } },
			{ T = 1.2, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } },
		},
	},
	-- SHADOW KUNAI: a flat side-arm flick, the blades cocked back across the body, then the
	-- arm whips out and opens, letting the fan go on the Hit frame (the Wrist points them
	-- straight out ahead).
	KunaiFlick = {
		Duration = 0.45,
		Markers = { { 0.1, "Whoosh" }, { 0.16, "Hit" } },
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			{ T = 0.08, Root = { 0, -30, 0 }, Waist = { 0, -30, 0 }, Neck = { 0, 24, 0 }, RightShoulder = { 90, 0, -60 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 40, 0, -20 }, LeftElbow = { 60, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.16, Root = { -6, 24, 0 }, Waist = { -4, 20, 0 }, Neck = { 0, -16, 0 }, RightShoulder = { 92, 0, 26 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 50, 0, 0 }, LeftHip = { 24, 0, 0 }, LeftKnee = { -26, 0, 0 }, Wrist = { -85, 0, 0 } },
			{ T = 0.3, Root = { -4, 30, 0 }, Waist = { -2, 24, 0 }, RightShoulder = { 72, 0, 40 }, RightElbow = { 20, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.45, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},
	-- the return flick: out wide on the right, then whipped back across, letting go in front
	KunaiBackhand = {
		Duration = 0.45,
		Markers = { { 0.1, "Whoosh" }, { 0.16, "Hit" } },
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			{ T = 0.08, Root = { 0, 30, 0 }, Waist = { 0, 26, 0 }, Neck = { 0, -20, 0 }, RightShoulder = { 82, 0, 62 }, RightElbow = { 90, 0, 0 }, LeftShoulder = { 40, 0, -20 }, LeftElbow = { 60, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.16, Root = { -6, -20, 0 }, Waist = { -4, -18, 0 }, Neck = { 0, 14, 0 }, RightShoulder = { 92, 0, -24 }, RightElbow = { 4, 0, 0 }, LeftShoulder = { 30, 0, -30 }, LeftElbow = { 50, 0, 0 }, RightHip = { 24, 0, 0 }, RightKnee = { -26, 0, 0 }, Wrist = { -85, 0, 0 } },
			{ T = 0.3, Root = { -4, -26, 0 }, Waist = { -2, -20, 0 }, RightShoulder = { 72, 0, -40 }, RightElbow = { 20, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.45, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},
	-- KUNAI STORM (P P P): both arms cross tight at the chest, crouched, then fling out wide
	-- together on the Hit frame, five blades fanning off them.
	KunaiStorm = {
		Duration = 0.7,
		Markers = { { 0.2, "Whoosh" }, { 0.28, "Hit" } },
		Keys = {
			{ T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
			{ T = 0.14, RootPos = { 0, -0.3, 0.2 }, Root = { -8, 0, 0 }, Neck = { -8, 0, 0 }, RightShoulder = { 90, 0, -50 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 90, 0, 50 }, LeftElbow = { 120, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightKnee = { -30, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.28, RootPos = { 0, 0.1, -0.4 }, Root = { 4, 0, 0 }, Neck = { 4, 0, 0 }, RightShoulder = { 95, 0, 55 }, RightElbow = { 6, 0, 0 }, LeftShoulder = { 95, 0, -55 }, LeftElbow = { 6, 0, 0 }, LeftHip = { 20, 0, 0 }, LeftKnee = { -20, 0, 0 }, Wrist = { -85, 0, 0 } },
			{ T = 0.45, RootPos = { 0, 0, -0.3 }, RightShoulder = { 70, 0, 70 }, RightElbow = { 14, 0, 0 }, LeftShoulder = { 70, 0, -70 }, LeftElbow = { 14, 0, 0 }, Wrist = { -60, 0, 0 } },
			{ T = 0.7, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } },
		},
	},

	------------------------------------------------------------------------------------
	-- Holds: overlays while a weapon is out (or your guard is up) and nothing else plays
	------------------------------------------------------------------------------------
	Guard = { Hold = true, Keys = { { T = 0, LeftShoulder = { 64, -62, 0 }, LeftElbow = { 132, 0, 0 }, RightShoulder = { 58, 66, 0 }, RightElbow = { 138, 0, 0 }, Neck = { -8, 0, 0 } } } },
	HoldMagnet = { Hold = true, Keys = { { T = 0, RightShoulder = { 80, 0, 0 }, RightElbow = { 12, 0, 0 }, LeftShoulder = { 60, 0, -25 }, LeftElbow = { 60, 0, 0 } } } },
	HoldScythe = { Hold = true, Keys = { { T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } } } },
	HoldBlade = { Hold = true, Keys = { { T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } } } },
	HoldWhip = { Hold = true, Keys = { { T = 0, RightShoulder = { 15, 0, 10 }, RightElbow = { 25, 0, 0 } } } },
	HoldSpear = { Hold = true, Keys = { { T = 0, RightShoulder = { 125, 0, 22 }, RightElbow = { 100, 0, 0 } } } },
	HoldHammer = { Hold = true, Keys = { { T = 0, RightShoulder = { 10, 0, 14 }, RightElbow = { 150, 0, 0 }, LeftShoulder = { 55, 0, -30 }, LeftElbow = { 70, 0, 0 } } } },
	HoldKunai = { Hold = true, Keys = { { T = 0, RightShoulder = { 25, 0, 15 }, RightElbow = { 40, 0, 0 } } } },
}

------------------------------------------------------------------------------------------
-- Directional dodges (facing an opponent: you dodge sideways and keep your eyes on them)
------------------------------------------------------------------------------------------
-- SIDE DIVE: load onto the outside leg (a small counter-lean), launch off it laid out
-- sideways and low, tuck and roll over the near shoulder (the body turns a full circle
-- around its own front-to-back axis), land in a crouch still facing them, rise into the
-- guard. Root +Z leans left, so a left roll runs Z 0 -> 360.
local SIDE_DIVE = {
	{ 0 },
	-- load: weight onto the right (outside) leg, leaning into it before pushing off
	{ 0.07, { RootPos = { 0.25, -0.55, 0 }, Root = { -10, -12, -12 }, RightHip = { 10, 0, -14 }, RightKnee = { -62, 0, 0 }, LeftHip = { 30, 0, 10 }, LeftKnee = { -50, 0, 0 } } },
	-- launch: laid out sideways in the air, the push-off leg trailing, chin tucked
	{ 0.17, { RootPos = { -0.7, 0, 0 }, Root = { -6, -12, 62 }, Waist = { 0, 6, 10 }, Neck = { -20, 0, -20 }, LeftHip = { 40, 0, -10 }, LeftKnee = { -70, 0, 0 }, RightHip = { 10, 0, 30 }, RightKnee = { -30, 0, 0 } } },
	-- the shoulder meets the floor: tucked tight
	{ 0.29, { RootPos = { -1.3, -1.5, 0 }, Root = { -20, -12, 140 }, Neck = { -35, 0, 0 }, LeftHip = { 100, 0, 0 }, LeftKnee = { -120, 0, 0 }, RightHip = { 100, 0, 0 }, RightKnee = { -120, 0, 0 } } },
	-- over the back
	{ 0.4, { RootPos = { -1.5, -1.6, 0 }, Root = { -20, -12, 240 }, Neck = { -35, 0, 0 }, LeftHip = { 100, 0, 0 }, LeftKnee = { -120, 0, 0 }, RightHip = { 100, 0, 0 }, RightKnee = { -120, 0, 0 } } },
	-- land: feet under, crouched, still facing them
	{ 0.52, { RootPos = { -1.2, -0.9, 0 }, Root = { -14, -12, 335 }, Neck = { -15, 0, 0 }, LeftHip = { 70, 0, -10 }, LeftKnee = { -100, 0, 0 }, RightHip = { 40, 0, 10 }, RightKnee = { -90, 0, 0 } } },
	-- rise
	{ 0.68, { RootPos = { -0.5, -0.45, 0 }, Root = { -8, -12, 358 }, LeftHip = { 40, 0, 0 }, LeftKnee = { -55, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { -50, 0, 0 } } },
	{ 0.8, { Root = { -6, -12, 360 } } },
}
POSES.DodgeLeft = { Duration = 0.8, Keys = keys(SIDE_DIVE), Markers = { { 0.07, "StepR" }, { 0.52, "Land" } } }
POSES.DodgeRight = { Duration = 0.8, Keys = keys(SIDE_DIVE, true), Markers = { { 0.07, "StepL" }, { 0.52, "Land" } } }

------------------------------------------------------------------------------------------
-- Taking hits (HandlerAnimator:React): the body goes the way the blow drove it. Light: the
-- head and shoulders take it; harder: the torso turns and a foot goes back; HEAVY: a real
-- stagger, two steps back. (Bigger blows than that knock you down: ragdoll + get-up.)
-- A blow on your LEFT side drives you to the RIGHT (RootPos +X, head turned right).
------------------------------------------------------------------------------------------
POSES.HitHighLight = {
	Duration = 0.38,
	Keys = {
		stance(0),
		stance(0.06, { Neck = { 14, 0, 0 }, Waist = { 4, 6, 0 }, Root = { -2, -12, 0 }, RootPos = { 0, -0.15, 0.15 } }),
		stance(0.16, { Neck = { 6, 0, 0 }, RootPos = { 0, -0.15, 0.1 } }),
		stance(0.38),
	},
}
POSES.HitHigh = {
	Duration = 0.55,
	Markers = { { 0.2, "StepR" } },
	Keys = {
		stance(0),
		stance(0.07, { Neck = { 26, 0, 0 }, Waist = { 10, 6, 0 }, Root = { 4, -12, 0 }, RootPos = { 0, -0.1, 0.45 }, LeftShoulder = { 50, -50, -10 }, LeftElbow = { 110, 0, 0 }, RightShoulder = { 46, 56, 10 }, RightElbow = { 116, 0, 0 } }),
		stance(0.2, { Neck = { 12, 0, 0 }, Waist = { 4, 6, 0 }, RootPos = { 0, -0.2, 0.35 }, RightHip = { -26, 0, 0 }, RightKnee = { -22, 0, 0 } }),
		stance(0.55),
	},
}
-- sign +1: hit on the LEFT (driven right); -1: hit on the right
local function sideHit(sign: number, hard: boolean)
	local k = hard and 1 or 0.55
	local list = {
		stance(0),
		stance(0.07, { Neck = { 6, -38 * sign * k, -12 * sign * k }, Waist = { 2, 6 - 12 * sign * k, -6 * sign * k }, Root = { -2, -12 - 10 * sign * k, -6 * sign * k }, RootPos = { 0.35 * sign * k, -0.1, 0.1 * k } }),
		stance(hard and 0.22 or 0.16, { Neck = { 2, -16 * sign * k, -4 * sign * k }, Waist = { 0, 6 - 6 * sign * k, 0 }, RootPos = { 0.25 * sign * k, -0.12, 0.08 * k } }),
		stance(hard and 0.55 or 0.38),
	}
	if hard then
		-- the arms fly open with it
		list[2].LeftShoulder = { 44, -40, -20 * sign }
		list[2].RightShoulder = { 44, 40, -20 * sign }
	end
	return { Duration = hard and 0.55 or 0.38, Keys = list }
end
POSES.HitLeftLight = sideHit(1, false)
POSES.HitLeft = sideHit(1, true)
POSES.HitRightLight = sideHit(-1, false)
POSES.HitRight = sideHit(-1, true)
POSES.Stagger = {
	Duration = 0.85,
	Markers = { { 0.25, "StepR" }, { 0.5, "StepL" } },
	Keys = {
		stance(0),
		stance(0.08, { Neck = { 24, 0, 0 }, Waist = { 16, 6, 0 }, Root = { 10, -12, 0 }, RootPos = { 0, -0.12, 0.7 }, LeftShoulder = { 30, 0, -50 }, LeftElbow = { 40, 0, 0 }, RightShoulder = { 30, 0, 50 }, RightElbow = { 40, 0, 0 } }),
		stance(0.25, { Neck = { 14, 0, 0 }, Waist = { 10, 6, 0 }, Root = { 6, -12, 0 }, RootPos = { 0, -0.14, 0.9 }, RightHip = { -34, 0, 0 }, RightKnee = { -26, 0, 0 }, LeftShoulder = { 40, 0, -40 }, RightShoulder = { 40, 0, 40 } }),
		stance(0.5, { Neck = { 4, 0, 0 }, Waist = { 4, 6, 0 }, RootPos = { 0, -0.14, 0.7 }, LeftHip = { 10, 0, 0 }, LeftKnee = { -40, 0, 0 } }),
		stance(0.85),
	},
}

-- PARRY: the guard SNAPS up and out at the last moment and knocks the blow off line.
POSES.Parry = {
	Duration = 0.4,
	Keys = {
		stance(0),
		stance(0.06, { LeftShoulder = { 140, -30, 24 }, LeftElbow = { 60, 0, 0 }, RightShoulder = { 132, 34, -18 }, RightElbow = { 70, 0, 0 }, RootPos = { 0, -0.24, -0.12 }, Neck = { -18, 0, 0 } }),
		stance(0.18, { LeftShoulder = { 120, -20, 10 }, LeftElbow = { 80, 0, 0 }, RightShoulder = { 100, 40, -6 }, RightElbow = { 100, 0, 0 } }),
		stance(0.4),
	},
}
-- PARRIED (a Handler whose strike was parried): the arm knocked off line, the body
-- twisted open and rocked back on its heels, guard down.
POSES.Parried = {
	Duration = 0.7,
	Keys = {
		stance(0),
		stance(0.08, { RootPos = { 0, -0.12, 0.35 }, Root = { 8, 22, -6 }, Waist = { 6, 22, 0 }, Neck = { 10, -20, 0 }, RightShoulder = { 40, 0, 62 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 34, -30, -24 }, LeftElbow = { 60, 0, 0 }, RightHip = { -28, 0, 0 }, RightKnee = { -22, 0, 0 } }),
		stance(0.45, { RootPos = { 0, -0.14, 0.3 }, Root = { 6, 16, -4 }, Waist = { 4, 16, 0 }, Neck = { 6, -14, 0 }, RightShoulder = { 34, 0, 46 }, RightElbow = { 40, 0, 0 }, LeftShoulder = { 40, -40, -16 }, LeftElbow = { 80, 0, 0 }, RightHip = { -26, 0, 0 } }),
		stance(0.7),
	},
}

return POSES
