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

return {
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
