--[[
	BossPoses  (ModuleScript, data only)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/BossPoses

	Keyframed boss attacks, per boss (the model's BossId), keyed by the boss rig's joint
	names. Same format and conventions as NightmarePoses; played by NightmareAnimator at the
	speed that lands each "Hit" marker on the server's impact (the attack's windup), and
	exported to editable KeyframeSequences named Boss_<BossId>_<Action>.

	Scrap Titan rig (ScrapTitan.BuildModel): Joint_Core (+ Joint_CorePos), Joint_Head,
	Joint_RightArm (wrecking-ball fist), Joint_LeftArm (magnet), Sub_Legs_L/R (hips),
	Knee_L/R (-X bends the shin back).
	Mirror Warden rig (MirrorWarden.BuildModel): a floating knight, no legs: Joint_Core (the
	torso and its crystal tail), Joint_Head (mirror mask), Joint_RightArm (glass blade),
	Joint_LeftArm (mirror shield).
]]

-- Mirror Warden: the blade arm's swings, its shield, and the spells it reflects.
local MirrorWarden = {
	-- MIRROR COMBO 1: the blade drawn back high on the right, then cut down diagonally across
	-- them, the body unwinding behind it, the shield held in close (pose lab: the blade
	-- crosses the centre line on the hit frame, then carries on across to the left).
	Combo1 = {
		Duration = 1.1,
		Markers = { { 0.6, "Whoosh" }, { 0.75, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.45, Joint_CorePos = { 0, 0.3, 0.4 }, Joint_Core = { 6, -30, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 150, 0, 50 }, Joint_LeftArm = { 40, 0, -20 } },
			{ T = 0.75, Joint_CorePos = { 0, -0.4, -1.2 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -6, -4, 0 }, Joint_RightArm = { 70, 0, -25 }, Joint_LeftArm = { 50, 0, -30 } },
			{ T = 0.95, Joint_CorePos = { 0, -0.4, -1.2 }, Joint_Core = { -14, 34, 0 }, Joint_Head = { -6, -18, 0 }, Joint_RightArm = { 40, 0, -60 }, Joint_LeftArm = { 50, 0, -30 } },
			{ T = 1.1 },
		},
	},
	-- MIRROR COMBO 2: straight back across the other way, a flat backhand cut (pose lab: on
	-- the hit frame the blade tip crosses the centre line ~13 studs out).
	Combo2 = {
		Duration = 0.95,
		Markers = { { 0.48, "Whoosh" }, { 0.6, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.35, Joint_CorePos = { 0, 0, 0.2 }, Joint_Core = { 4, 35, 0 }, Joint_Head = { 0, -20, 0 }, Joint_RightArm = { 90, 0, -70 }, Joint_LeftArm = { 40, 0, -10 } },
			{ T = 0.6, Joint_CorePos = { 0, -0.3, -1.0 }, Joint_Core = { -8, 0, 0 }, Joint_Head = { -4, 8, 0 }, Joint_RightArm = { 90, 0, -25 }, Joint_LeftArm = { 40, 0, -20 } },
			{ T = 0.8, Joint_CorePos = { 0, -0.3, -1.0 }, Joint_Core = { -8, -40, 0 }, Joint_Head = { -4, 20, 0 }, Joint_RightArm = { 80, 0, 60 }, Joint_LeftArm = { 40, 0, -20 } },
			{ T = 0.95 },
		},
	},
	-- MIRROR COMBO 3 (heavy): it rises with the blade raised straight up, shield forward, then
	-- drops and drives the blade down through them in an overhead cleave.
	Combo3 = {
		Duration = 1.25,
		Markers = { { 0.55, "Whoosh" }, { 0.9, "Hit" }, { 0.9, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.55, Joint_CorePos = { 0, 1.2, 0.4 }, Joint_Core = { 14, -10, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 185, 0, 10 }, Joint_LeftArm = { 80, 0, -10 } },
			{ T = 0.9, Joint_CorePos = { 0, -0.8, -1.6 }, Joint_Core = { -30, 10, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 60, 0, -10 }, Joint_LeftArm = { 30, 0, -30 } },
			{ T = 1.1, Joint_CorePos = { 0, -0.8, -1.6 }, Joint_Core = { -28, 10, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 56, 0, -10 }, Joint_LeftArm = { 30, 0, -30 } },
			{ T = 1.25 },
		},
	},
	-- REFLECTED SLAM: the mirror shield raised high overhead, then brought down flat on the
	-- floor: the slam lands on them AND their reflection.
	Slam = {
		Duration = 1.9,
		Markers = { { 1.1, "Whoosh" }, { 1.3, "Hit" }, { 1.3, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.8, Joint_CorePos = { 0, 1.8, 0.3 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 12, 0, 0 }, Joint_LeftArm = { 175, 0, 0 }, Joint_RightArm = { 140, 0, 20 } },
			{ T = 1.3, Joint_CorePos = { 0, -0.6, -0.8 }, Joint_Core = { -30, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_LeftArm = { 70, 0, 0 }, Joint_RightArm = { 60, 0, 20 } },
			{ T = 1.55, Joint_CorePos = { 0, -0.6, -0.8 }, Joint_Core = { -28, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_LeftArm = { 66, 0, 0 }, Joint_RightArm = { 56, 0, 20 } },
			{ T = 1.9 },
		},
	},
	-- SHARD STORM: blade and shield raised to the sky, head thrown back, calling the glass
	-- down; then flung wide as it falls.
	Barrage = {
		Duration = 1.9,
		Markers = { { 0.9, "Whoosh" }, { 1.1, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.7, Joint_CorePos = { 0, 0.8, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 24, 0, 0 }, Joint_RightArm = { 170, 0, 30 }, Joint_LeftArm = { 170, 0, -30 } },
			{ T = 1.1, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { -4, 0, 0 }, Joint_RightArm = { 110, 0, 70 }, Joint_LeftArm = { 110, 0, -70 } },
			{ T = 1.5, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { -2, 0, 0 }, Joint_RightArm = { 106, 0, 66 }, Joint_LeftArm = { 106, 0, -66 } },
			{ T = 1.9 },
		},
	},
	-- SHATTER NOVA: it curls in behind blade and shield crossed, then bursts outward, arms
	-- thrown wide, everything around it blasted away.
	ShatterNova = {
		Duration = 1.9,
		Markers = { { 1.1, "Hit" }, { 1.1, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.7, Joint_CorePos = { 0, -0.5, 0 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { -20, 0, 0 }, Joint_RightArm = { 60, 0, -50 }, Joint_LeftArm = { 60, 0, 50 } },
			{ T = 1.1, Joint_CorePos = { 0, 0.6, 0 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { 24, 0, 0 }, Joint_RightArm = { 100, 0, 90 }, Joint_LeftArm = { 100, 0, -90 } },
			{ T = 1.4, Joint_CorePos = { 0, 0.5, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 96, 0, 86 }, Joint_LeftArm = { 96, 0, -86 } },
			{ T = 1.9 },
		},
	},
	-- THE MIRROR CRACKS (phase 2): convulsing, head thrown back, arms wide, shuddering.
	Roar = {
		Duration = 2.0,
		Markers = { { 0.3, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.3, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 30, 0, 0 }, Joint_RightArm = { 80, 0, 60 }, Joint_LeftArm = { 80, 0, -60 } },
			{ T = 0.6, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 14, 0, 6 }, Joint_Head = { 30, 6, 0 }, Joint_RightArm = { 84, 0, 64 }, Joint_LeftArm = { 76, 0, -56 } },
			{ T = 0.9, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 14, 0, -6 }, Joint_Head = { 30, -6, 0 }, Joint_RightArm = { 76, 0, 56 }, Joint_LeftArm = { 84, 0, -64 } },
			{ T = 1.2, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 14, 0, 6 }, Joint_Head = { 30, 6, 0 }, Joint_RightArm = { 84, 0, 64 }, Joint_LeftArm = { 76, 0, -56 } },
			{ T = 1.6, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 20, 0, 0 }, Joint_RightArm = { 70, 0, 50 }, Joint_LeftArm = { 70, 0, -50 } },
			{ T = 2.0 },
		},
	},
	-- PRISM BEAM (cracked): the shield held out in front angled like a prism, the blade laid
	-- across it; the light gathers, then splits into the two crossing beams.
	PrismBeam = {
		Duration = 2.3,
		Markers = { { 1.2, "Whoosh" }, { 1.4, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.9, Joint_CorePos = { 0, 0.4, 0.4 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_LeftArm = { 95, 0, 0 }, Joint_RightArm = { 120, 0, -30 } },
			{ T = 1.4, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_LeftArm = { 92, 0, 0 }, Joint_RightArm = { 95, 0, -40 } },
			{ T = 1.7, Joint_CorePos = { 0, 0, -0.55 }, Joint_Core = { -10, 0, 3 }, Joint_Head = { -6, 0, 0 }, Joint_LeftArm = { 92, 0, 2 }, Joint_RightArm = { 95, 0, -38 } },
			{ T = 2.0, Joint_CorePos = { 0, 0, -0.55 }, Joint_Core = { -10, 0, -3 }, Joint_Head = { -6, 0, 0 }, Joint_LeftArm = { 92, 0, -2 }, Joint_RightArm = { 95, 0, -42 } },
			{ T = 2.3 },
		},
	},
}

-- Scrap Titan: no ankles, so the SHINS stay vertical (the foot flat on the floor): the
-- thigh tilts forward by the angle that drops the hips exactly as far as the body sinks
-- (thigh ~3.1 studs), the knee bends back by the same angle, and the hips also take up
-- any lean of the torso (leaning forward would otherwise swing the legs back).
local THIGH = 3.1
local function titanKey(t: number, sink: number, changes)
	local drop = 0.6 * sink
	local angle = math.deg(math.acos(math.clamp(1 - drop / THIGH, -1, 1)))
	local lean = changes.Joint_Core and changes.Joint_Core[1] or 0
	local key = { T = t, Joint_CorePos = { 0, -drop, 0 }, Sub_Legs_L = { angle - lean, 0, 0 }, Sub_Legs_R = { angle - lean, 0, 0 }, Knee_L = { -angle, 0, 0 }, Knee_R = { -angle, 0, 0 } }
	for joint, v in changes do
		key[joint] = v
	end
	return key
end
local ScrapTitan = {
	-- SWIPE: the wrecking-ball fist swung out wide to the right, then backhanded right across
	-- the front through everything in the box, the whole torso turning after it.
	Swipe = {
		Duration = 1.75,
		Markers = { { 0.5, "StepR" }, { 0.5, "Whoosh" }, { 0.85, "Hit" }, { 0.85, "StepL" } },
		Keys = {
			{ T = 0 },
			titanKey(0.5, 1, { Joint_Core = { 4, -25, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 70, 0, 75 }, Joint_LeftArm = { 30, 0, -20 } }),
			titanKey(0.85, 1.2, { Joint_Core = { -10, 20, 0 }, Joint_Head = { -4, -10, 0 }, Joint_RightArm = { 85, 0, -30 }, Joint_LeftArm = { 20, 0, -30 } }),
			titanKey(1.1, 1.2, { Joint_Core = { -12, 35, 0 }, Joint_Head = { -4, -20, 0 }, Joint_RightArm = { 70, 0, -70 }, Joint_LeftArm = { 20, 0, -30 } }),
			titanKey(1.45, 0.5, { Joint_Core = { -4, 20, 0 }, Joint_RightArm = { 30, 0, -20 } }),
			{ T = 1.75 },
		},
	},
	-- SCRAP BARRAGE: it hunkers down and the reactor builds, then it throws its chest up to
	-- the sky, arms flung up and out, venting a storm of scrap into the air.
	Barrage = {
		Duration = 1.9,
		Markers = { { 0.7, "StepL" }, { 0.7, "Whoosh" }, { 1.1, "Hit" } },
		Keys = {
			{ T = 0 },
			titanKey(0.7, 1.3, { Joint_Core = { -14, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 30, 0, 40 }, Joint_LeftArm = { 30, 0, -40 } }),
			titanKey(1.1, 0, { Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 20, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 125, 0, 60 }, Joint_LeftArm = { 125, 0, -60 } }),
			titanKey(1.5, 0.2, { Joint_CorePos = { 0, 0.15, 0 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 118, 0, 56 }, Joint_LeftArm = { 118, 0, -56 } }),
			{ T = 1.9 },
		},
	},
	-- MAGNET PULL: braced wide, the magnet arm thrust out at them, shaking as it drags them
	-- in (the pull lands at the windup), then the wrecking ball comes up and SMASHES down at
	-- its feet into whoever it dragged in (0.7 s later).
	MagnetPull = {
		Duration = 2.6,
		Markers = { { 0.8, "StepL" }, { 1.2, "Hit" }, { 1.65, "Whoosh" }, { 1.9, "Land" } },
		Keys = {
			{ T = 0 },
			titanKey(0.8, 1, { Joint_Core = { -6, -15, 0 }, Joint_Head = { -6, 10, 0 }, Joint_LeftArm = { 95, 0, 10 }, Joint_RightArm = { 30, 0, 20 } }),
			titanKey(1.2, 1, { Joint_Core = { -6, -15, 3 }, Joint_Head = { -6, 10, 0 }, Joint_LeftArm = { 98, 0, 8 }, Joint_RightArm = { 30, 0, 20 } }),
			titanKey(1.35, 1, { Joint_Core = { -6, -15, -3 }, Joint_Head = { -6, 10, 0 }, Joint_LeftArm = { 93, 0, 12 }, Joint_RightArm = { 30, 0, 20 } }),
			titanKey(1.65, 0.3, { Joint_Core = { 12, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 175, 0, 10 }, Joint_LeftArm = { 60, 0, -10 } }),
			titanKey(1.9, 1.8, { Joint_Core = { -30, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 50, 0, 0 }, Joint_LeftArm = { 40, 0, -10 } }),
			titanKey(2.2, 1.6, { Joint_Core = { -26, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 46, 0, 0 }, Joint_LeftArm = { 40, 0, -10 } }),
			{ T = 2.6 },
		},
	},
	-- OVERDRIVE: the reactor overheats: chest thrown out, arms wide, head back, shuddering.
	Roar = {
		Duration = 2.0,
		Markers = { { 0.3, "Hit" }, { 0.3, "Land" } },
		Keys = {
			{ T = 0 },
			titanKey(0.3, 0.4, { Joint_Core = { 16, 0, 0 }, Joint_Head = { 30, 0, 0 }, Joint_RightArm = { 80, 0, 70 }, Joint_LeftArm = { 80, 0, -70 } }),
			titanKey(0.7, 0.4, { Joint_Core = { 16, 0, 5 }, Joint_Head = { 30, 6, 0 }, Joint_RightArm = { 84, 0, 74 }, Joint_LeftArm = { 76, 0, -66 } }),
			titanKey(1.1, 0.4, { Joint_Core = { 16, 0, -5 }, Joint_Head = { 30, -6, 0 }, Joint_RightArm = { 76, 0, 66 }, Joint_LeftArm = { 84, 0, -74 } }),
			titanKey(1.6, 0.3, { Joint_Core = { 10, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 60, 0, 50 }, Joint_LeftArm = { 60, 0, -50 } }),
			{ T = 2.0 },
		},
	},
}

-- Storm Beast: four rigid legs on the core (Sub_Legs_FL/FR/BL/BR, no knees). REARING: the
-- body pitches back about its middle, so it rises to keep the hind paws on the floor and the
-- hind legs turn against the pitch to stay upright (measured hips: 4.4 back, 2 down).
local function rear(t: number, pitch: number, changes)
	local a = math.rad(pitch)
	local rise = 2 * (1 - math.cos(a)) + 4.4 * math.sin(a)
	local key = { T = t, Joint_CorePos = { 0, rise, 0 }, Joint_Core = { pitch, 0, 0 }, Sub_Legs_BL = { -pitch, 0, 0 }, Sub_Legs_BR = { -pitch, 0, 0 } }
	for joint, v in changes do
		key[joint] = v
	end
	return key
end
local StormBeast = {
	-- THUNDER POUNCE: crouch, spring HIGH (it vanishes up into the air: the server lands it on
	-- the marked spot at the windup), and come down paws-first on them.
	ThunderPounce = {
		Duration = 1.4,
		Markers = { { 0.3, "StepL" }, { 0.55, "Whoosh" }, { 1.0, "Hit" }, { 1.0, "Land" } },
		Keys = {
			{ T = 0 },
			-- (rigid legs: the paws tip with them, so the crouch is a lean, not a sink)
			{ T = 0.45, Joint_CorePos = { 0, 0, 0.6 }, Joint_Core = { 4, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Legs_FL = { -10, 0, 0 }, Sub_Legs_FR = { -10, 0, 0 }, Sub_Legs_BL = { 6, 0, 0 }, Sub_Legs_BR = { 6, 0, 0 }, Joint_Tail = { 0, 0, 0 } },
			{ T = 0.7, Joint_CorePos = { 0, 7, -1 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { -10, 0, 0 }, Sub_Legs_FL = { 70, 0, 0 }, Sub_Legs_FR = { 70, 0, 0 }, Sub_Legs_BL = { -50, 0, 0 }, Sub_Legs_BR = { -50, 0, 0 } },
			{ T = 0.9, Joint_CorePos = { 0, 9, -1 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -20, 0, 0 }, Sub_Legs_FL = { 50, 0, 0 }, Sub_Legs_FR = { 50, 0, 0 }, Sub_Legs_BL = { -20, 0, 0 }, Sub_Legs_BR = { -20, 0, 0 } },
			-- IMPACT on the spot: landed on them, chest down, paws spread
			{ T = 1.0, Joint_CorePos = { 0, 0.2, 0 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { -20, 0, 0 }, Sub_Legs_FL = { 10, 0, -5 }, Sub_Legs_FR = { 10, 0, 5 }, Sub_Legs_BL = { -6, 0, -3 }, Sub_Legs_BR = { -6, 0, 3 } },
			{ T = 1.2, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { -3, 0, 0 }, Joint_Head = { -8, 0, 0 }, Sub_Legs_FL = { 6, 0, -3 }, Sub_Legs_FR = { 6, 0, 3 } },
			{ T = 1.4 },
		},
	},
	-- CHAIN LIGHTNING: it rears back, head thrown up, horns crackling, then snaps the head
	-- forward and spits the bolt that hops between them.
	ChainLightning = {
		Duration = 1.8,
		Markers = { { 0.3, "StepL" }, { 0.75, "Whoosh" }, { 0.9, "Hit" } },
		Keys = {
			{ T = 0 },
			rear(0.6, 18, { Joint_Head = { 30, 0, 0 }, Sub_Legs_FL = { 20, 0, 0 }, Sub_Legs_FR = { 10, 0, 0 }, Joint_Tail = { 20, 0, 0 } }),
			rear(0.9, 4, { Joint_Head = { -24, 0, 0 }, Sub_Legs_FL = { -10, 0, 0 }, Sub_Legs_FR = { -10, 0, 0 } }),
			rear(1.3, 4, { Joint_Head = { -20, 0, 0 } }),
			{ T = 1.8 },
		},
	},
	-- THUNDERSTORM: it rears up high on its hind legs and howls at the sky, front paws
	-- pawing the air, then slams them down as the storm breaks.
	Thunderstorm = {
		Duration = 1.8,
		Markers = { { 0.4, "StepR" }, { 0.85, "Whoosh" }, { 1.0, "Hit" }, { 1.0, "Land" } },
		Keys = {
			{ T = 0 },
			rear(0.5, 32, { Joint_Head = { 34, 0, 0 }, Sub_Legs_FL = { 60, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 } }),
			rear(0.75, 34, { Joint_Head = { 38, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 64, 0, 0 } }),
			{ T = 1.0, Joint_CorePos = { 0, 0.15, 0 }, Joint_Core = { -3, 0, 0 }, Joint_Head = { -14, 0, 0 }, Sub_Legs_FL = { 8, 0, -4 }, Sub_Legs_FR = { 8, 0, 4 }, Sub_Legs_BL = { 3, 0, 0 }, Sub_Legs_BR = { 3, 0, 0 } },
			{ T = 1.4, Joint_CorePos = { 0, 0.05, 0 }, Joint_Core = { -2, 0, 0 }, Joint_Head = { -8, 0, 0 }, Sub_Legs_FL = { 4, 0, -2 }, Sub_Legs_FR = { 4, 0, 2 } },
			{ T = 1.8 },
		},
	},
	-- CLAW SWIPE: it rises onto its hind legs a little and rakes the right forepaw out and
	-- across the front, the head lunging after it.
	Swipe = {
		Duration = 1.5,
		Markers = { { 0.3, "StepL" }, { 0.65, "Whoosh" }, { 0.8, "Hit" } },
		Keys = {
			{ T = 0 },
			rear(0.5, 14, { Joint_Head = { 10, -14, 0 }, Sub_Legs_FR = { 80, 0, 40 }, Sub_Legs_FL = { 10, 0, 0 } }),
			rear(0.8, 4, { Joint_CorePos = { 0, 0.4, -0.8 }, Joint_Head = { -14, 16, 0 }, Sub_Legs_FR = { 55, 0, -40 }, Sub_Legs_FL = { 6, 0, 0 } }),
			rear(1.05, 2, { Joint_Head = { -8, 20, 0 }, Sub_Legs_FR = { 30, 0, -40 } }),
			{ T = 1.5 },
		},
	},
	-- STATIC NOVA: it hunkers down, every spike blazing, shuddering, then jolts up stiff-legged
	-- as the ring of static bursts out of it.
	StaticNova = {
		Duration = 1.9,
		Markers = { { 1.1, "Hit" }, { 1.1, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.6, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { -2, 0, 3 }, Joint_Head = { -24, 0, 0 }, Sub_Legs_FL = { 3, 0, -5 }, Sub_Legs_FR = { 3, 0, 5 }, Sub_Legs_BL = { -3, 0, -5 }, Sub_Legs_BR = { -3, 0, 5 } },
			{ T = 0.85, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { -2, 0, -3 }, Joint_Head = { -24, 0, 0 }, Sub_Legs_FL = { 3, 0, -5 }, Sub_Legs_FR = { 3, 0, 5 }, Sub_Legs_BL = { -3, 0, -5 }, Sub_Legs_BR = { -3, 0, 5 } },
			{ T = 1.1, Joint_CorePos = { 0, 1.2, 0 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 24, 0, 0 }, Sub_Legs_FL = { 0, 0, -22 }, Sub_Legs_FR = { 0, 0, 22 }, Sub_Legs_BL = { 0, 0, -22 }, Sub_Legs_BR = { 0, 0, 22 }, Joint_Tail = { 30, 0, 0 } },
			{ T = 1.45, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 2, 0, 0 }, Joint_Head = { 10, 0, 0 }, Sub_Legs_FL = { 0, 0, -8 }, Sub_Legs_FR = { 0, 0, 8 }, Sub_Legs_BL = { 0, 0, -8 }, Sub_Legs_BR = { 0, 0, 8 } },
			{ T = 1.9 },
		},
	},
}

-- Abyssal Maw: a worm rising out of the floor (its lower body lives below it): Joint_Core
-- (the body column), Joint_Head (the maw), Joint_LeftArm / Joint_RightArm (tentacles).
local AbyssalMaw = {
	-- BURROW: it rears up, then dives head-first back down into the ground.
	Burrow = {
		Duration = 1.0,
		Markers = { { 0.3, "Hit" }, { 0.5, "Whoosh" }, { 0.8, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.3, Joint_CorePos = { 0, 1.5, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 140, 0, 30 }, Joint_LeftArm = { 140, 0, -30 } },
			{ T = 0.8, Joint_CorePos = { 0, -8, -2 }, Joint_Core = { -45, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { -20, 0, 20 }, Joint_LeftArm = { -20, 0, -20 } },
			{ T = 1.0, Joint_CorePos = { 0, -10, -2 }, Joint_Core = { -45, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { -20, 0, 20 }, Joint_LeftArm = { -20, 0, -20 } },
		},
	},
	-- ERUPT: it bursts up out of the ground under them, maw gaping, tentacles flung up, then
	-- crashes back to its height.
	Erupt = {
		Duration = 0.8,
		Markers = { { 0.05, "Hit" }, { 0.05, "Land" } },
		Keys = {
			{ T = 0, Joint_CorePos = { 0, -6, 0 }, Joint_Core = { 0, 0, 0 }, Joint_Head = { 30, 0, 0 } },
			{ T = 0.05, Joint_CorePos = { 0, 3, 0 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { 30, 0, 0 }, Joint_RightArm = { 160, 0, 50 }, Joint_LeftArm = { 160, 0, -50 } },
			{ T = 0.35, Joint_CorePos = { 0, 1.2, 0 }, Joint_Core = { 8, 0, 0 }, Joint_Head = { 12, 0, 0 }, Joint_RightArm = { 90, 0, 40 }, Joint_LeftArm = { 90, 0, -40 } },
			{ T = 0.8 },
		},
	},
	-- TENTACLE SLAM: both tentacles rear up high behind it, then whip down and forward along
	-- the lines at them, the maw dipping after them.
	TentacleSlam = {
		Duration = 1.9,
		Markers = { { 0.9, "Whoosh" }, { 1.1, "Hit" }, { 1.1, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.75, Joint_CorePos = { 0, 0.8, 0.5 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 14, 0, 0 }, Joint_RightArm = { 175, 0, 20 }, Joint_LeftArm = { 175, 0, -20 } },
			{ T = 1.1, Joint_CorePos = { 0, -0.8, -1.2 }, Joint_Core = { -22, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 55, 0, -10 }, Joint_LeftArm = { 55, 0, 10 } },
			{ T = 1.4, Joint_CorePos = { 0, -0.8, -1.2 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 50, 0, -10 }, Joint_LeftArm = { 50, 0, 10 } },
			{ T = 1.9 },
		},
	},
	-- ABYSSAL INHALE: the maw gapes up and back, tentacles spread wide, dragging everything in
	-- (the pull lands at the windup), then the whole head slams forward in a BITE (0.7 s on).
	Inhale = {
		Duration = 2.6,
		Markers = { { 1.2, "Hit" }, { 1.75, "Whoosh" }, { 1.9, "JawSnap" }, { 1.9, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.8, Joint_CorePos = { 0, 1, 0.6 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 26, 0, 0 }, Joint_RightArm = { 90, 0, 75 }, Joint_LeftArm = { 90, 0, -75 } },
			{ T = 1.2, Joint_CorePos = { 0, 1.2, 0.8 }, Joint_Core = { 20, 0, 0 }, Joint_Head = { 30, 0, 0 }, Joint_RightArm = { 95, 0, 40 }, Joint_LeftArm = { 95, 0, -40 } },
			{ T = 1.6, Joint_CorePos = { 0, 1.2, 0.8 }, Joint_Core = { 20, 0, 0 }, Joint_Head = { 30, 0, 0 }, Joint_RightArm = { 80, 0, 10 }, Joint_LeftArm = { 80, 0, -10 } },
			{ T = 1.9, Joint_CorePos = { 0, -1, -2.2 }, Joint_Core = { -32, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { 40, 0, 20 }, Joint_LeftArm = { 40, 0, -20 } },
			{ T = 2.2, Joint_CorePos = { 0, -0.9, -2 }, Joint_Core = { -28, 0, 0 }, Joint_Head = { -26, 0, 0 }, Joint_RightArm = { 40, 0, 20 }, Joint_LeftArm = { 40, 0, -20 } },
			{ T = 2.6 },
		},
	},
	-- INK SPIT: it rears back, then pumps its head forward, spitting a glob at each one.
	InkSpit = {
		Duration = 1.8,
		Markers = { { 0.85, "Whoosh" }, { 1.0, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.7, Joint_CorePos = { 0, 0.6, 0.6 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 } },
			{ T = 1.0, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -18, 0, 0 } },
			{ T = 1.1, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 4, 0, 0 }, Joint_Head = { 6, 0, 0 } },
			{ T = 1.2, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -10, 6, 0 }, Joint_Head = { -18, 6, 0 } },
			{ T = 1.3, Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 4, 0, 0 }, Joint_Head = { 6, 0, 0 } },
			{ T = 1.4, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -10, -6, 0 }, Joint_Head = { -18, -6, 0 } },
			{ T = 1.8 },
		},
	},
	-- ABYSS POOLS: it curls over and drives its maw into the ground, and the dark pools well up.
	AbyssPools = {
		Duration = 1.6,
		Markers = { { 0.8, "Whoosh" }, { 1.0, "Hit" }, { 1.0, "Land" } },
		Keys = {
			{ T = 0 },
			{ T = 0.6, Joint_CorePos = { 0, 1, 0.5 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 16, 0, 0 }, Joint_RightArm = { 120, 0, 40 }, Joint_LeftArm = { 120, 0, -40 } },
			{ T = 1.0, Joint_CorePos = { 0, -2, -1.5 }, Joint_Core = { -40, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { 20, 0, 50 }, Joint_LeftArm = { 20, 0, -50 } },
			{ T = 1.3, Joint_CorePos = { 0, -1.8, -1.4 }, Joint_Core = { -36, 0, 0 }, Joint_Head = { -26, 0, 0 }, Joint_RightArm = { 20, 0, 50 }, Joint_LeftArm = { 20, 0, -50 } },
			{ T = 1.6 },
		},
	},
	-- THE ABYSS OPENS: it rears to its full height, maw wide at the sky, tentacles thrashing.
	Roar = {
		Duration = 2.0,
		Markers = { { 0.3, "Hit" } },
		Keys = {
			{ T = 0 },
			{ T = 0.3, Joint_CorePos = { 0, 2, 0 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 34, 0, 0 }, Joint_RightArm = { 150, 0, 60 }, Joint_LeftArm = { 150, 0, -60 } },
			{ T = 0.7, Joint_CorePos = { 0, 2, 0 }, Joint_Core = { 16, 0, 6 }, Joint_Head = { 34, 8, 0 }, Joint_RightArm = { 120, 0, 80 }, Joint_LeftArm = { 170, 0, -40 } },
			{ T = 1.1, Joint_CorePos = { 0, 2, 0 }, Joint_Core = { 16, 0, -6 }, Joint_Head = { 34, -8, 0 }, Joint_RightArm = { 170, 0, 40 }, Joint_LeftArm = { 120, 0, -80 } },
			{ T = 1.6, Joint_CorePos = { 0, 1, 0 }, Joint_Core = { 8, 0, 0 }, Joint_Head = { 16, 0, 0 }, Joint_RightArm = { 90, 0, 40 }, Joint_LeftArm = { 90, 0, -40 } },
			{ T = 2.0 },
		},
	},
}


------------------------------------------------------------------------------------------
-- SIGNATURE COMBOS: one continuous clip each, several beats (the server's ctx:Combo lands
-- every beat on its frame; the "Hit" marker is the FIRST beat, which syncs the speed).
-- Built from each boss's own measured poses above, so the body moves the same way.
------------------------------------------------------------------------------------------
-- SCRAP TITAN
-- WRECKING COMBO: the wrecking ball swung across, backhanded back, raised and smashed down.
ScrapTitan.WreckingCombo = {
	Duration = 3.0,
	Markers = { { 0.5, "StepR" }, { 0.5, "Whoosh" }, { 0.85, "Hit" }, { 1.1, "Whoosh" }, { 1.45, "Strike" }, { 1.8, "Whoosh" }, { 2.15, "Land" } },
	Keys = {
		{ T = 0 },
		titanKey(0.5, 1, { Joint_Core = { 4, -25, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 70, 0, 75 }, Joint_LeftArm = { 30, 0, -20 } }),
		titanKey(0.85, 1.2, { Joint_Core = { -10, 20, 0 }, Joint_Head = { -4, -10, 0 }, Joint_RightArm = { 85, 0, -30 }, Joint_LeftArm = { 20, 0, -30 } }),
		titanKey(1.1, 1.2, { Joint_Core = { -12, 35, 0 }, Joint_Head = { -4, -20, 0 }, Joint_RightArm = { 70, 0, -70 }, Joint_LeftArm = { 20, 0, -30 } }),
		-- the BACKHAND: back across to the right
		titanKey(1.45, 1.2, { Joint_Core = { -10, -30, 0 }, Joint_Head = { -4, 15, 0 }, Joint_RightArm = { 85, 0, 55 }, Joint_LeftArm = { 20, 0, -30 } }),
		titanKey(1.8, 0.3, { Joint_Core = { 12, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 175, 0, 10 }, Joint_LeftArm = { 60, 0, -10 } }),
		-- the SMASH
		titanKey(2.15, 1.8, { Joint_Core = { -30, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 50, 0, 0 }, Joint_LeftArm = { 40, 0, -10 } }),
		titanKey(2.5, 1.6, { Joint_Core = { -26, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 46, 0, 0 }, Joint_LeftArm = { 40, 0, -10 } }),
		{ T = 3.0 },
	},
}
-- MAGNET UPPERCUT: the magnet drags them in, the ball comes up under them, a stomp.
ScrapTitan.MagnetUppercut = {
	Duration = 2.8,
	Markers = { { 0.8, "StepL" }, { 1.0, "Hit" }, { 1.25, "Whoosh" }, { 1.5, "Strike" }, { 2.15, "Land" } },
	Keys = {
		{ T = 0 },
		titanKey(0.8, 1, { Joint_Core = { -6, -15, 0 }, Joint_Head = { -6, 10, 0 }, Joint_LeftArm = { 95, 0, 10 }, Joint_RightArm = { 30, 0, 20 } }),
		titanKey(1.0, 1, { Joint_Core = { -6, -15, 3 }, Joint_Head = { -6, 10, 0 }, Joint_LeftArm = { 98, 0, 8 }, Joint_RightArm = { 30, 0, 20 } }),
		titanKey(1.25, 1.6, { Joint_Core = { -16, -20, 0 }, Joint_Head = { -6, 10, 0 }, Joint_RightArm = { 20, 0, 30 }, Joint_LeftArm = { 60, 0, -10 } }),
		-- UPPERCUT: up out of the squat, the ball driven up through them
		titanKey(1.5, 0.2, { Joint_Core = { 12, 15, 0 }, Joint_Head = { 14, 0, 0 }, Joint_RightArm = { 165, 0, -10 }, Joint_LeftArm = { 40, 0, -20 } }),
		-- the right foot up...
		titanKey(1.85, 0.6, { Joint_Core = { 6, 0, 0 }, Joint_RightArm = { 60, 0, 20 }, Joint_LeftArm = { 60, 0, -20 }, Sub_Legs_R = { 55, 0, 0 }, Knee_R = { -60, 0, 0 } }),
		-- ...STOMP
		titanKey(2.15, 1.2, { Joint_Core = { -14, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 40, 0, 20 }, Joint_LeftArm = { 40, 0, -20 } }),
		titanKey(2.45, 0.6, { Joint_Core = { -6, 0, 0 } }),
		{ T = 2.8 },
	},
}
-- SCRAP QUAKE: stomp left, stomp right, both fists into the floor.
ScrapTitan.ScrapQuake = {
	Duration = 2.8,
	Markers = { { 0.45, "Whoosh" }, { 0.7, "Hit" }, { 0.7, "Land" }, { 1.2, "Land" }, { 1.5, "Whoosh" }, { 1.85, "Land" } },
	Keys = {
		{ T = 0 },
		titanKey(0.45, 0.5, { Joint_Core = { 6, 0, -6 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 }, Sub_Legs_L = { 55, 0, 0 }, Knee_L = { -55, 0, 0 } }),
		titanKey(0.7, 1.2, { Joint_Core = { -10, 10, 4 }, Joint_RightArm = { 30, 0, 30 }, Joint_LeftArm = { 30, 0, -30 } }),
		titanKey(0.95, 0.5, { Joint_Core = { 6, 0, 6 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 }, Sub_Legs_R = { 55, 0, 0 }, Knee_R = { -55, 0, 0 } }),
		titanKey(1.2, 1.2, { Joint_Core = { -10, -10, -4 }, Joint_RightArm = { 30, 0, 30 }, Joint_LeftArm = { 30, 0, -30 } }),
		titanKey(1.5, 0.3, { Joint_Core = { 14, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 175, 0, 10 }, Joint_LeftArm = { 175, 0, -10 } }),
		titanKey(1.85, 1.9 / 0.6, { Joint_CorePos = { 0, -1.9, -0.4 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 72, 0, 8 }, Joint_LeftArm = { 72, 0, -8 } }),
		titanKey(2.2, 1.7 / 0.6, { Joint_CorePos = { 0, -1.7, -0.35 }, Joint_Core = { -34, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 64, 0, 8 }, Joint_LeftArm = { 64, 0, -8 } }),
		{ T = 2.8 },
	},
}
-- REACTOR RUSH (Overdrive): shoulder down, the charge, a backhand, the reactor bursts.
ScrapTitan.ReactorRush = {
	Duration = 3.2,
	Markers = { { 0.6, "StepL" }, { 1.0, "Hit" }, { 1.0, "StepR" }, { 1.25, "Whoosh" }, { 1.6, "Strike" }, { 2.3, "Land" } },
	Keys = {
		{ T = 0 },
		titanKey(0.6, 1.4, { Joint_Core = { -24, -20, 0 }, Joint_Head = { 10, 10, 0 }, Joint_RightArm = { 30, 0, 20 }, Joint_LeftArm = { 60, 0, -30 } }),
		titanKey(1.0, 1.0, { Joint_Core = { -28, -25, 0 }, Joint_Head = { 12, 12, 0 }, Joint_RightArm = { 20, 0, 30 }, Joint_LeftArm = { 70, 0, -30 } }),
		titanKey(1.25, 1.2, { Joint_Core = { -14, -25, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 70, 0, 75 }, Joint_LeftArm = { 30, 0, -20 } }),
		titanKey(1.6, 1.2, { Joint_Core = { -10, 30, 0 }, Joint_Head = { -4, -15, 0 }, Joint_RightArm = { 80, 0, -70 }, Joint_LeftArm = { 20, 0, -30 } }),
		titanKey(1.95, 1.3, { Joint_Core = { -14, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 30, 0, 40 }, Joint_LeftArm = { 30, 0, -40 } }),
		titanKey(2.3, 0, { Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 20, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 125, 0, 60 }, Joint_LeftArm = { 125, 0, -60 } }),
		titanKey(2.7, 0.2, { Joint_CorePos = { 0, 0.15, 0 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 118, 0, 56 }, Joint_LeftArm = { 118, 0, -56 } }),
		{ T = 3.2 },
	},
}

-- MIRROR WARDEN
local W_RAISE = { Joint_CorePos = { 0, 1.2, 0.4 }, Joint_Core = { 14, -10, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 185, 0, 10 }, Joint_LeftArm = { 80, 0, -10 } }
local W_STAB = { Joint_CorePos = { 0, -0.8, -1.6 }, Joint_Core = { -30, 10, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 60, 0, -10 }, Joint_LeftArm = { 30, 0, -30 } }
local W_DRAW = { Joint_CorePos = { 0, 0.2, 0.6 }, Joint_Core = { 4, -25, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 90, 0, 40 }, Joint_LeftArm = { 60, 0, -10 } }
local W_THRUST = { Joint_CorePos = { 0, -0.2, -1.6 }, Joint_Core = { -12, 10, 0 }, Joint_Head = { -6, -6, 0 }, Joint_RightArm = { 92, 0, -5 }, Joint_LeftArm = { 40, 0, -30 } }
local function wkey(t: number, pose)
	local key = table.clone(pose)
	key.T = t
	return key
end
-- MIRRORED STRIKE: a diagonal cut (it lands twice: here and in the reflection), a shield
-- bash, a rising cleave.
MirrorWarden.MirroredStrike = {
	Duration = 2.3,
	Markers = { { 0.45, "Whoosh" }, { 0.75, "Hit" }, { 1.25, "Strike" }, { 1.5, "Whoosh" }, { 1.75, "Strike" } },
	Keys = {
		{ T = 0 },
		{ T = 0.45, Joint_CorePos = { 0, 0.3, 0.4 }, Joint_Core = { 6, -30, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 150, 0, 50 }, Joint_LeftArm = { 40, 0, -20 } },
		{ T = 0.75, Joint_CorePos = { 0, -0.4, -1.2 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { -6, -4, 0 }, Joint_RightArm = { 70, 0, -25 }, Joint_LeftArm = { 50, 0, -30 } },
		{ T = 1.0, Joint_CorePos = { 0, 0, 0.2 }, Joint_Core = { 4, 20, 0 }, Joint_Head = { 0, -10, 0 }, Joint_LeftArm = { 100, 0, 30 }, Joint_RightArm = { 60, 0, 30 } },
		-- SHIELD BASH
		{ T = 1.25, Joint_CorePos = { 0, -0.2, -1.4 }, Joint_Core = { -10, -10, 0 }, Joint_Head = { -6, 0, 0 }, Joint_LeftArm = { 95, 0, -10 }, Joint_RightArm = { 50, 0, 30 } },
		{ T = 1.5, Joint_CorePos = { 0, -0.4, -0.6 }, Joint_Core = { 10, -20, 0 }, Joint_Head = { 0, 10, 0 }, Joint_RightArm = { -20, 0, 40 }, Joint_LeftArm = { 40, 0, -20 } },
		-- RISING CLEAVE
		{ T = 1.75, Joint_CorePos = { 0, 1.0, -1.2 }, Joint_Core = { 16, 10, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 175, 0, -5 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 2.0, Joint_CorePos = { 0, 0.8, -1.0 }, Joint_Core = { 12, 8, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 170, 0, -5 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 2.3 },
	},
}
-- SHARD LANCE: two long thrusts, then the blade raised and driven down at the far point.
MirrorWarden.ShardLance = {
	Duration = 2.4,
	Markers = { { 0.55, "Whoosh" }, { 0.8, "Hit" }, { 1.05, "Whoosh" }, { 1.3, "Strike" }, { 1.55, "Whoosh" }, { 1.8, "Strike" } },
	Keys = {
		{ T = 0 },
		wkey(0.55, W_DRAW),
		wkey(0.8, W_THRUST),
		wkey(1.05, W_DRAW),
		wkey(1.3, W_THRUST),
		{ T = 1.55, Joint_CorePos = { 0, 0.6, 0 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 10, 0, 0 }, Joint_RightArm = { 175, 0, 0 }, Joint_LeftArm = { 60, 0, -20 } },
		{ T = 1.8, Joint_CorePos = { 0, -0.3, -1.2 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 90, 0, -5 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 2.05, Joint_CorePos = { 0, -0.3, -1.1 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -6, 0, 0 }, Joint_RightArm = { 86, 0, -5 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 2.4 },
	},
}
-- SHIELD RIPOSTE: covered behind the mirror, a bash, then a full spin of the blade.
MirrorWarden.ShieldRiposte = {
	Duration = 2.4,
	Markers = { { 0.3, "Whoosh" }, { 1.1, "Hit" }, { 1.35, "Whoosh" }, { 1.7, "Strike" } },
	Keys = {
		{ T = 0 },
		{ T = 0.3, Joint_CorePos = { 0, -0.2, 0.3 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_LeftArm = { 95, 0, 15 }, Joint_RightArm = { 40, 0, 40 } },
		{ T = 0.9, Joint_CorePos = { 0, -0.25, 0.3 }, Joint_Core = { -8, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_LeftArm = { 96, 0, 14 }, Joint_RightArm = { 40, 0, 40 } },
		{ T = 1.1, Joint_CorePos = { 0, -0.2, -1.5 }, Joint_Core = { -12, -10, 0 }, Joint_Head = { -6, 0, 0 }, Joint_LeftArm = { 95, 0, -15 }, Joint_RightArm = { 40, 0, 40 } },
		{ T = 1.35, Joint_CorePos = { 0, 0, -0.8 }, Joint_Core = { 0, 60, 0 }, Joint_Head = { 0, -30, 0 }, Joint_RightArm = { 90, 0, 70 }, Joint_LeftArm = { 50, 0, -20 } },
		-- the BLADE SPIN: round once, arm out
		{ T = 1.5, Joint_CorePos = { 0, 0, -0.8 }, Joint_Core = { 0, -60, 0 }, Joint_RightArm = { 90, 0, 85 }, Joint_LeftArm = { 50, 0, -20 } },
		{ T = 1.6, Joint_CorePos = { 0, 0, -0.8 }, Joint_Core = { 0, -180, 0 }, Joint_RightArm = { 90, 0, 85 }, Joint_LeftArm = { 50, 0, -20 } },
		{ T = 1.7, Joint_CorePos = { 0, 0, -0.8 }, Joint_Core = { 0, -300, 0 }, Joint_RightArm = { 90, 0, 85 }, Joint_LeftArm = { 50, 0, -20 } },
		{ T = 2.0, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { 0, -360, 0 }, Joint_RightArm = { 60, 0, 30 }, Joint_LeftArm = { 40, 0, -20 } },
		{ T = 2.4, Joint_Core = { 0, -360, 0 } },
	},
}
-- KALEIDOSCOPE (cracked): three stabs from three sides (it blinks between them), an X-cut.
MirrorWarden.Kaleidoscope = {
	Duration = 2.6,
	Markers = { { 0.5, "Whoosh" }, { 0.7, "Hit" }, { 1.15, "Strike" }, { 1.6, "Strike" }, { 1.95, "Whoosh" }, { 2.2, "Strike" } },
	Keys = {
		{ T = 0 },
		wkey(0.5, W_RAISE),
		wkey(0.7, W_STAB),
		wkey(0.95, W_RAISE),
		wkey(1.15, W_STAB),
		wkey(1.4, W_RAISE),
		wkey(1.6, W_STAB),
		{ T = 1.95, Joint_CorePos = { 0, 0.3, 0.4 }, Joint_Core = { 6, -30, 0 }, Joint_Head = { 0, 20, 0 }, Joint_RightArm = { 150, 0, 50 }, Joint_LeftArm = { 40, 0, -20 } },
		{ T = 2.2, Joint_CorePos = { 0, -0.4, -1.2 }, Joint_Core = { -12, 30, 0 }, Joint_Head = { -6, -18, 0 }, Joint_RightArm = { 50, 0, -65 }, Joint_LeftArm = { 50, 0, -30 } },
		{ T = 2.6 },
	},
}

-- STORM BEAST
local SB_CROUCH = { Joint_CorePos = { 0, 0, 0.5 }, Joint_Core = { 4, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Legs_FL = { -10, 0, 0 }, Sub_Legs_FR = { -10, 0, 0 }, Sub_Legs_BL = { 6, 0, 0 }, Sub_Legs_BR = { 6, 0, 0 } }
local SB_AIR = { Joint_CorePos = { 0, 0.3, 0 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Legs_FL = { 60, 0, 0 }, Sub_Legs_FR = { 60, 0, 0 }, Sub_Legs_BL = { -40, 0, 0 }, Sub_Legs_BR = { -40, 0, 0 } }
local SB_LAND = { Joint_CorePos = { 0, 0.2, 0 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { -20, 0, 0 }, Sub_Legs_FL = { 10, 0, -5 }, Sub_Legs_FR = { 10, 0, 5 }, Sub_Legs_BL = { -6, 0, -3 }, Sub_Legs_BR = { -6, 0, 3 } }
local SB_SLAM = { Joint_CorePos = { 0, 0.15, 0 }, Joint_Core = { -3, 0, 0 }, Joint_Head = { -14, 0, 0 }, Sub_Legs_FL = { 8, 0, -4 }, Sub_Legs_FR = { 8, 0, 4 }, Sub_Legs_BL = { 3, 0, 0 }, Sub_Legs_BR = { 3, 0, 0 } }
-- THUNDER MAUL: left paw, right paw, a lunging bite, then round it goes, the tail scything.
StormBeast.ThunderMaul = {
	Duration = 2.4,
	Markers = { { 0.4, "Whoosh" }, { 0.6, "Hit" }, { 0.8, "Whoosh" }, { 1.0, "Strike" }, { 1.25, "JawSnap" }, { 1.5, "StepL" }, { 1.8, "Whoosh" } },
	Keys = {
		{ T = 0 },
		rear(0.4, 14, { Joint_Head = { 10, 14, 0 }, Sub_Legs_FL = { 80, 0, -40 }, Sub_Legs_FR = { 10, 0, 0 } }),
		rear(0.6, 4, { Joint_CorePos = { 0, 0.4, -0.8 }, Joint_Head = { -14, -16, 0 }, Sub_Legs_FL = { 55, 0, 40 }, Sub_Legs_FR = { 6, 0, 0 } }),
		rear(0.8, 14, { Joint_Head = { 10, -14, 0 }, Sub_Legs_FR = { 80, 0, 40 }, Sub_Legs_FL = { 10, 0, 0 } }),
		rear(1.0, 4, { Joint_CorePos = { 0, 0.4, -0.8 }, Joint_Head = { -14, 16, 0 }, Sub_Legs_FR = { 55, 0, -40 }, Sub_Legs_FL = { 6, 0, 0 } }),
		-- the LUNGING BITE
		{ T = 1.25, Joint_CorePos = { 0, 0.2, -2.0 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -30, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 30, 0, 0 }, Sub_Legs_BL = { -15, 0, 0 }, Sub_Legs_BR = { -15, 0, 0 } },
		-- whips round: the TAIL
		{ T = 1.5, Joint_CorePos = { 0, 0.1, -0.8 }, Joint_Core = { 0, -120, 0 }, Joint_Head = { -6, 30, 0 }, Joint_Tail = { 0, 40, 0 } },
		{ T = 1.8, Joint_CorePos = { 0, 0.1, -0.6 }, Joint_Core = { 0, -240, 0 }, Joint_Head = { -6, 20, 0 }, Joint_Tail = { 0, 60, 0 } },
		{ T = 2.05, Joint_CorePos = { 0, 0, -0.4 }, Joint_Core = { 0, -360, 0 }, Joint_Tail = { 0, 10, 0 } },
		{ T = 2.4, Joint_Core = { 0, -360, 0 } },
	},
}
-- STORM CHARGE: head down and charge through them, skid, rear and slam a burst, howl bolts.
StormBeast.StormCharge = {
	Duration = 2.8,
	Markers = { { 0.5, "StepL" }, { 0.8, "Hit" }, { 1.0, "StepR" }, { 1.15, "Land" }, { 1.45, "Whoosh" }, { 1.75, "Land" }, { 2.1, "Roar" } },
	Keys = {
		{ T = 0 },
		wkey(0.5, SB_CROUCH),
		{ T = 0.8, Joint_CorePos = { 0, 0.6, -1 }, Joint_Core = { -8, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Legs_FL = { 60, 0, 0 }, Sub_Legs_FR = { 40, 0, 0 }, Sub_Legs_BL = { -50, 0, 0 }, Sub_Legs_BR = { -40, 0, 0 } },
		{ T = 1.0, Joint_CorePos = { 0, 0.4, -0.6 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { -12, 0, 0 }, Sub_Legs_FL = { -30, 0, 0 }, Sub_Legs_FR = { -20, 0, 0 }, Sub_Legs_BL = { 30, 0, 0 }, Sub_Legs_BR = { 40, 0, 0 } },
		{ T = 1.15, Joint_CorePos = { 0, 0.2, -0.3 }, Joint_Core = { -6, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Legs_FL = { 20, 0, 0 }, Sub_Legs_FR = { 10, 0, 0 }, Sub_Legs_BL = { -10, 0, 0 }, Sub_Legs_BR = { -15, 0, 0 } },
		rear(1.45, 26, { Joint_Head = { 32, 0, 0 }, Sub_Legs_FL = { 55, 0, 0 }, Sub_Legs_FR = { 50, 0, 0 } }),
		wkey(1.75, SB_SLAM),
		rear(2.1, 10, { Joint_Head = { 36, 0, 0 } }),
		rear(2.45, 4, { Joint_Head = { 10, 0, 0 } }),
		{ T = 2.8 },
	},
}
-- ROLLING THUNDER: three bounds (the server flies it), a nova.
StormBeast.RollingThunder = {
	Duration = 2.6,
	Markers = { { 0.2, "StepL" }, { 0.7, "Hit" }, { 0.7, "Land" }, { 1.25, "Land" }, { 1.8, "Land" }, { 2.3, "Strike" } },
	Keys = {
		{ T = 0 },
		wkey(0.2, SB_CROUCH),
		wkey(0.45, SB_AIR),
		wkey(0.7, SB_LAND),
		wkey(0.85, SB_CROUCH),
		wkey(1.0, SB_AIR),
		wkey(1.25, SB_LAND),
		wkey(1.4, SB_CROUCH),
		wkey(1.55, SB_AIR),
		wkey(1.8, SB_LAND),
		{ T = 2.0, Joint_CorePos = { 0, 0.1, 0 }, Joint_Core = { -2, 0, 3 }, Joint_Head = { -24, 0, 0 }, Sub_Legs_FL = { 3, 0, -5 }, Sub_Legs_FR = { 3, 0, 5 }, Sub_Legs_BL = { -3, 0, -5 }, Sub_Legs_BR = { -3, 0, 5 } },
		{ T = 2.3, Joint_CorePos = { 0, 1.2, 0 }, Joint_Core = { 6, 0, 0 }, Joint_Head = { 24, 0, 0 }, Sub_Legs_FL = { 0, 0, -22 }, Sub_Legs_FR = { 0, 0, 22 }, Sub_Legs_BL = { 0, 0, -22 }, Sub_Legs_BR = { 0, 0, 22 }, Joint_Tail = { 30, 0, 0 } },
		{ T = 2.6 },
	},
}
-- SKY SPLITTER (supercharged): rear up high, slam three forks of lightning, howl bolts down.
StormBeast.SkySplitter = {
	Duration = 2.8,
	Markers = { { 0.5, "StepR" }, { 0.8, "Whoosh" }, { 1.2, "Hit" }, { 1.2, "Land" }, { 2.0, "Roar" } },
	Keys = {
		{ T = 0 },
		rear(0.5, 20, { Joint_Head = { 24, 0, 0 }, Sub_Legs_FL = { 30, 0, 0 }, Sub_Legs_FR = { 20, 0, 0 } }),
		rear(0.8, 34, { Joint_Head = { 38, 0, 0 }, Sub_Legs_FL = { 60, 0, 0 }, Sub_Legs_FR = { 64, 0, 0 } }),
		wkey(1.2, SB_SLAM),
		rear(1.6, 12, { Joint_Head = { 34, 0, 0 } }),
		rear(2.0, 14, { Joint_Head = { 40, 0, 0 }, Joint_Tail = { 30, 0, 0 } }),
		{ T = 2.4, Joint_CorePos = { 0, 0.05, 0 }, Joint_Core = { -2, 0, 0 }, Joint_Head = { -8, 0, 0 } },
		{ T = 2.8 },
	},
}

-- ABYSSAL MAW
local M_REAR = { Joint_CorePos = { 0, 0.8, 0.5 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 14, 0, 0 }, Joint_RightArm = { 175, 0, 20 }, Joint_LeftArm = { 175, 0, -20 } }
local M_BITE = { Joint_CorePos = { 0, -1, -2.2 }, Joint_Core = { -32, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { 40, 0, 20 }, Joint_LeftArm = { 40, 0, -20 } }
-- ABYSSAL LASH: the right tentacle across, the left back, both slammed down long.
AbyssalMaw.AbyssalLash = {
	Duration = 2.4,
	Markers = { { 0.45, "Whoosh" }, { 0.7, "Hit" }, { 0.9, "Whoosh" }, { 1.1, "Strike" }, { 1.4, "Whoosh" }, { 1.7, "Land" } },
	Keys = {
		{ T = 0 },
		{ T = 0.45, Joint_CorePos = { 0, 0.4, 0.3 }, Joint_Core = { 6, -20, 0 }, Joint_Head = { 10, 15, 0 }, Joint_RightArm = { 170, 0, 40 }, Joint_LeftArm = { 60, 0, -20 } },
		{ T = 0.7, Joint_CorePos = { 0, -0.4, -0.8 }, Joint_Core = { -10, 20, 0 }, Joint_Head = { -10, -10, 0 }, Joint_RightArm = { 60, 0, -50 }, Joint_LeftArm = { 60, 0, -20 } },
		{ T = 0.9, Joint_CorePos = { 0, 0.4, 0.3 }, Joint_Core = { 6, 20, 0 }, Joint_Head = { 10, -15, 0 }, Joint_LeftArm = { 170, 0, -40 }, Joint_RightArm = { 60, 0, 20 } },
		{ T = 1.1, Joint_CorePos = { 0, -0.4, -0.8 }, Joint_Core = { -10, -20, 0 }, Joint_Head = { -10, 10, 0 }, Joint_LeftArm = { 60, 0, 50 }, Joint_RightArm = { 60, 0, 20 } },
		wkey(1.4, M_REAR),
		{ T = 1.7, Joint_CorePos = { 0, -0.8, -1.2 }, Joint_Core = { -22, 0, 0 }, Joint_Head = { -16, 0, 0 }, Joint_RightArm = { 55, 0, -10 }, Joint_LeftArm = { 55, 0, 10 } },
		{ T = 2.0, Joint_CorePos = { 0, -0.8, -1.2 }, Joint_Core = { -20, 0, 0 }, Joint_Head = { -14, 0, 0 }, Joint_RightArm = { 50, 0, -10 }, Joint_LeftArm = { 50, 0, 10 } },
		{ T = 2.4 },
	},
}
-- DEVOUR: two lunging bites, then the dark spat straight out.
AbyssalMaw.Devour = {
	Duration = 2.6,
	Markers = { { 0.5, "Whoosh" }, { 0.8, "Hit" }, { 0.8, "JawSnap" }, { 1.4, "JawSnap" }, { 2.0, "Strike" } },
	Keys = {
		{ T = 0 },
		{ T = 0.5, Joint_CorePos = { 0, 1, 0.6 }, Joint_Core = { 16, 0, 0 }, Joint_Head = { 26, 0, 0 }, Joint_RightArm = { 90, 0, 60 }, Joint_LeftArm = { 90, 0, -60 } },
		wkey(0.8, M_BITE),
		{ T = 1.1, Joint_CorePos = { 0, 0.8, 0.4 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 80, 0, 50 }, Joint_LeftArm = { 80, 0, -50 } },
		wkey(1.4, M_BITE),
		{ T = 1.7, Joint_CorePos = { 0, 0.6, 0.6 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 2.0, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 2.3, Joint_CorePos = { 0, 0.2, -0.3 }, Joint_Core = { -4, 0, 0 }, Joint_Head = { -6, 0, 0 } },
		{ T = 2.6 },
	},
}
-- UNDERTOW's finish: up out of the second eruption, tentacles thrashing round once.
AbyssalMaw.Undertow = {
	Duration = 1.6,
	Markers = { { 0.3, "Whoosh" }, { 0.6, "Hit" } },
	Keys = {
		{ T = 0 },
		{ T = 0.3, Joint_CorePos = { 0, 1, 0 }, Joint_Core = { 10, 40, 0 }, Joint_Head = { 14, -20, 0 }, Joint_RightArm = { 100, 0, 80 }, Joint_LeftArm = { 100, 0, -80 } },
		{ T = 0.6, Joint_CorePos = { 0, 0.6, 0 }, Joint_Core = { 6, -60, 0 }, Joint_Head = { 6, 20, 0 }, Joint_RightArm = { 80, 0, 90 }, Joint_LeftArm = { 80, 0, -90 } },
		{ T = 0.9, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 4, -150, 0 }, Joint_RightArm = { 70, 0, 80 }, Joint_LeftArm = { 70, 0, -80 } },
		{ T = 1.2, Joint_CorePos = { 0, 0.2, 0 }, Joint_Core = { 0, -260, 0 }, Joint_RightArm = { 60, 0, 60 }, Joint_LeftArm = { 60, 0, -60 } },
		{ T = 1.45, Joint_Core = { 0, -360, 0 } },
		{ T = 1.6, Joint_Core = { 0, -360, 0 } },
	},
}
-- INK TIDE (the abyss open): spit a fan of ink, sweep the tentacles flat round, geysers.
AbyssalMaw.InkTide = {
	Duration = 2.8,
	Markers = { { 0.7, "Whoosh" }, { 1.0, "Hit" }, { 1.3, "Whoosh" }, { 1.6, "Strike" }, { 2.2, "Land" } },
	Keys = {
		{ T = 0 },
		{ T = 0.7, Joint_CorePos = { 0, 0.6, 0.6 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 1.0, Joint_CorePos = { 0, 0, -0.6 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -18, 0, 0 }, Joint_RightArm = { 40, 0, 30 }, Joint_LeftArm = { 40, 0, -30 } },
		{ T = 1.3, Joint_CorePos = { 0, 0.8, 0.5 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { 14, 0, 0 }, Joint_RightArm = { 120, 0, 70 }, Joint_LeftArm = { 120, 0, -70 } },
		{ T = 1.6, Joint_CorePos = { 0, -0.6, -1.0 }, Joint_Core = { -10, 0, 0 }, Joint_Head = { -8, 0, 0 }, Joint_RightArm = { 70, 0, -60 }, Joint_LeftArm = { 70, 0, 60 } },
		{ T = 1.85, Joint_CorePos = { 0, 0.6, 0.4 }, Joint_Core = { 12, 0, 0 }, Joint_Head = { 16, 0, 0 }, Joint_RightArm = { 120, 0, 40 }, Joint_LeftArm = { 120, 0, -40 } },
		{ T = 2.2, Joint_CorePos = { 0, -2, -1.5 }, Joint_Core = { -40, 0, 0 }, Joint_Head = { -30, 0, 0 }, Joint_RightArm = { 20, 0, 50 }, Joint_LeftArm = { 20, 0, -50 } },
		{ T = 2.5, Joint_CorePos = { 0, -1.8, -1.4 }, Joint_Core = { -36, 0, 0 }, Joint_Head = { -26, 0, 0 }, Joint_RightArm = { 20, 0, 50 }, Joint_LeftArm = { 20, 0, -50 } },
		{ T = 2.8 },
	},
}

local LIBRARY = {
	AbyssalMaw = AbyssalMaw,
	StormBeast = StormBeast,
	MirrorWarden = MirrorWarden,
	ScrapTitan = {
		Swipe = ScrapTitan.Swipe,
		Barrage = ScrapTitan.Barrage,
		MagnetPull = ScrapTitan.MagnetPull,
		Roar = ScrapTitan.Roar,
		WreckingCombo = ScrapTitan.WreckingCombo,
		MagnetUppercut = ScrapTitan.MagnetUppercut,
		ScrapQuake = ScrapTitan.ScrapQuake,
		ReactorRush = ScrapTitan.ReactorRush,
		-- GROUND SLAM: it squats deep with both fists coming up, springs into the air
		-- arching back with the fists high over its head, then comes down with its whole
		-- weight: a deep landing squat as both fists smash the floor in front of it. Holds
		-- the impact for a beat (the punish window starts here), then heaves itself upright.
		Slam = {
			Duration = 1.9,
			Markers = { { 0.35, "StepL" }, { 0.8, "Whoosh" }, { 1.3, "Hit" }, { 1.3, "Land" } },
			Keys = {
				{ T = 0 },
				-- load: squat, lean in, fists starting up (squats keep the shins vertical so the
				-- ankle-less feet stay flat on the floor: titanKey)
				titanKey(0.35, 1.3 / 0.6, { Joint_CorePos = { 0, -1.3, 0.2 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 70, 0, 18 }, Joint_LeftArm = { 70, 0, -18 } }),
				-- spring: legs drive straight, arching back, fists overhead
				{ T = 0.8, Joint_CorePos = { 0, 0.6, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 172, 0, 10 }, Joint_LeftArm = { 172, 0, -10 }, Sub_Legs_L = { -6, 0, 0 }, Knee_L = { -8, 0, 0 }, Sub_Legs_R = { -6, 0, 0 }, Knee_R = { -8, 0, 0 } },
				-- airborne: legs tucked, fists drawn right back for the hammer blow
				{ T = 1.05, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 188, 0, 8 }, Joint_LeftArm = { 188, 0, -8 }, Sub_Legs_L = { 34, 0, 0 }, Knee_L = { -55, 0, 0 }, Sub_Legs_R = { 26, 0, 0 }, Knee_R = { -48, 0, 0 } },
				-- IMPACT: lands in a deep squat, bent right over, both fists into the floor
				titanKey(1.3, 1.9 / 0.6, { Joint_CorePos = { 0, -1.9, -0.4 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 72, 0, 8 }, Joint_LeftArm = { 72, 0, -8 } }),
				-- holds the impact: the punish window
				titanKey(1.52, 1.7 / 0.6, { Joint_CorePos = { 0, -1.7, -0.35 }, Joint_Core = { -34, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 64, 0, 8 }, Joint_LeftArm = { 64, 0, -8 } }),
				-- heaves itself upright
				{ T = 1.9 },
			},
		},
	},
}

-- Every boss attack lands with its whole mass: flows through its keys, fast into each contact,
-- stopped on it, and the body carries on past it a little before it comes back.
local PoseTools = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("PoseTools"))
for _, boss in LIBRARY do
	for _, def in boss do
		PoseTools.Punch(def, 0.1)
	end
end

-- The limb that lands each blow goes out at what it's hitting (FightAim): the ball, the blade,
-- the paw, the tentacle really reach whoever is standing there.
local function aim(boss, name: string, list)
	local def = LIBRARY[boss][name]
	if def then
		def.Aim = {}
		for _, strike in list do
			table.insert(def.Aim, { T = strike[1], Arm = strike[2], At = "Body", Lead = 0.14 })
		end
	end
end
aim("ScrapTitan", "Swipe", { { 0.85, "Right" } })
aim("ScrapTitan", "WreckingCombo", { { 0.85, "Right" }, { 1.45, "Right" } })
aim("ScrapTitan", "MagnetUppercut", { { 1.5, "Right" } })
aim("ScrapTitan", "ReactorRush", { { 1.6, "Right" } })
aim("MirrorWarden", "Combo1", { { 0.75, "Right" } })
aim("MirrorWarden", "Combo2", { { 0.6, "Right" } })
aim("MirrorWarden", "Combo3", { { 0.9, "Right" } })
aim("MirrorWarden", "MirroredStrike", { { 0.75, "Right" }, { 1.25, "Left" }, { 1.75, "Right" } })
aim("MirrorWarden", "ShardLance", { { 0.8, "Right" }, { 1.3, "Right" }, { 1.8, "Right" } })
aim("MirrorWarden", "ShieldRiposte", { { 1.1, "Left" } })
aim("MirrorWarden", "Kaleidoscope", { { 0.7, "Right" }, { 1.15, "Right" }, { 1.6, "Right" }, { 2.2, "Right" } })
aim("StormBeast", "Swipe", { { 0.8, "FrontRight" } })
aim("StormBeast", "ThunderMaul", { { 0.6, "FrontLeft" }, { 1.0, "FrontRight" } })
aim("AbyssalMaw", "TentacleSlam", { { 1.1, "Right" }, { 1.1, "Left" } })
aim("AbyssalMaw", "AbyssalLash", { { 0.7, "Right" }, { 1.1, "Left" }, { 1.7, "Right" }, { 1.7, "Left" } })

return LIBRARY
