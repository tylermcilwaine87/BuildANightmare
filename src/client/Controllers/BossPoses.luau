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
]]

return {
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
