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

return {
	MirrorWarden = MirrorWarden,
	ScrapTitan = {
		-- GROUND SLAM: it squats deep with both fists coming up, springs into the air
		-- arching back with the fists high over its head, then comes down with its whole
		-- weight: a deep landing squat as both fists smash the floor in front of it. Holds
		-- the impact for a beat (the punish window starts here), then heaves itself upright.
		Slam = {
			Duration = 1.9,
			Markers = { { 0.35, "StepL" }, { 0.8, "Whoosh" }, { 1.3, "Hit" }, { 1.3, "Land" } },
			Keys = {
				{ T = 0 },
				-- load: squat, lean in, fists starting up
				{ T = 0.35, Joint_CorePos = { 0, -1.3, 0.2 }, Joint_Core = { -12, 0, 0 }, Joint_Head = { 8, 0, 0 }, Joint_RightArm = { 70, 0, 18 }, Joint_LeftArm = { 70, 0, -18 }, Sub_Legs_L = { 40, 0, 0 }, Knee_L = { -70, 0, 0 }, Sub_Legs_R = { 40, 0, 0 }, Knee_R = { -70, 0, 0 } },
				-- spring: legs drive straight, arching back, fists overhead
				{ T = 0.8, Joint_CorePos = { 0, 0.6, 0 }, Joint_Core = { 14, 0, 0 }, Joint_Head = { -10, 0, 0 }, Joint_RightArm = { 172, 0, 10 }, Joint_LeftArm = { 172, 0, -10 }, Sub_Legs_L = { -6, 0, 0 }, Knee_L = { -8, 0, 0 }, Sub_Legs_R = { -6, 0, 0 }, Knee_R = { -8, 0, 0 } },
				-- airborne: legs tucked, fists drawn right back for the hammer blow
				{ T = 1.05, Joint_CorePos = { 0, 0.4, 0 }, Joint_Core = { 18, 0, 0 }, Joint_Head = { -12, 0, 0 }, Joint_RightArm = { 188, 0, 8 }, Joint_LeftArm = { 188, 0, -8 }, Sub_Legs_L = { 34, 0, 0 }, Knee_L = { -55, 0, 0 }, Sub_Legs_R = { 26, 0, 0 }, Knee_R = { -48, 0, 0 } },
				-- IMPACT: lands in a deep squat, bent right over, both fists into the floor
				{ T = 1.3, Joint_CorePos = { 0, -1.9, -0.4 }, Joint_Core = { -38, 0, 0 }, Joint_Head = { 22, 0, 0 }, Joint_RightArm = { 72, 0, 8 }, Joint_LeftArm = { 72, 0, -8 }, Sub_Legs_L = { 72, 0, 0 }, Knee_L = { -105, 0, 0 }, Sub_Legs_R = { 66, 0, 0 }, Knee_R = { -100, 0, 0 } },
				-- holds the impact: the punish window
				{ T = 1.52, Joint_CorePos = { 0, -1.7, -0.35 }, Joint_Core = { -34, 0, 0 }, Joint_Head = { 18, 0, 0 }, Joint_RightArm = { 64, 0, 8 }, Joint_LeftArm = { 64, 0, -8 }, Sub_Legs_L = { 66, 0, 0 }, Knee_L = { -96, 0, 0 }, Sub_Legs_R = { 60, 0, 0 }, Knee_R = { -92, 0, 0 } },
				-- heaves itself upright
				{ T = 1.9 },
			},
		},
	},
}
