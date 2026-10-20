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
local BITE = {
	Duration = 0.7,
	Markers = { { 0.22, "Whoosh" }, { 0.3, "Hit" }, { 0.3, "JawSnap" }, { 0.3, "StepL" } },
	Keys = {
		{ T = 0 },
		-- prepare: rear back, head up, lips part, arms rise to grab
		{ T = 0.12, Joint_CorePos = { 0, -0.3, 0.25 }, Joint_Core = { 10, 0, 0 }, Joint_Head = { 14, 0, 0 }, Sub_Head_Jaw = { -12, 0, 0 }, Joint_RightArm = { 35, 0, 12 }, Joint_LeftArm = { 35, 0, -12 }, Sub_Legs_L = { 14, 0, 0 }, Sub_Legs_R = { -10, 0, 0 } },
		-- lunge: neck and torso driving forward, jaw dropped wide, claws reaching
		{ T = 0.22, Joint_CorePos = { 0, -0.25, -0.7 }, Joint_Core = { -18, 0, 0 }, Joint_Head = { -6, 0, 0 }, Sub_Head_Jaw = { -62, 0, 0 }, Joint_RightArm = { 70, 0, 22 }, Joint_LeftArm = { 70, 0, -22 }, Sub_Legs_L = { 30, 0, 0 }, Sub_Legs_R = { -24, 0, 0 } },
		-- SNAP: the jaws slam shut on them, claws clamp in
		{ T = 0.3, Joint_CorePos = { 0, -0.35, -1.0 }, Joint_Core = { -26, 0, 0 }, Joint_Head = { -16, 0, 0 }, Sub_Head_Jaw = { 0, 0, 0 }, Joint_RightArm = { 78, 0, 6 }, Joint_LeftArm = { 78, 0, -6 }, Sub_Legs_L = { 36, 0, 0 }, Sub_Legs_R = { -30, 0, 0 } },
		-- tear: wrench the head one way...
		{ T = 0.38, Joint_CorePos = { 0, -0.32, -0.85 }, Joint_Core = { -22, 8, 0 }, Joint_Head = { -14, 18, 6 }, Sub_Head_Jaw = { 2, 0, 0 }, Joint_RightArm = { 74, 0, 4 }, Joint_LeftArm = { 74, 0, -4 }, Sub_Legs_L = { 34, 0, 0 }, Sub_Legs_R = { -28, 0, 0 } },
		-- ...then the other, pulling back
		{ T = 0.46, Joint_CorePos = { 0, -0.28, -0.6 }, Joint_Core = { -18, -8, 0 }, Joint_Head = { -12, -18, -6 }, Sub_Head_Jaw = { 2, 0, 0 }, Joint_RightArm = { 66, 0, 6 }, Joint_LeftArm = { 66, 0, -6 }, Sub_Legs_L = { 28, 0, 0 }, Sub_Legs_R = { -22, 0, 0 } },
		-- release: jaw opens to let go, head comes up, body settles back
		{ T = 0.56, Joint_CorePos = { 0, -0.12, 0.1 }, Joint_Core = { 4, 0, 0 }, Joint_Head = { 6, 0, 0 }, Sub_Head_Jaw = { -30, 0, 0 }, Joint_RightArm = { 30, 0, 10 }, Joint_LeftArm = { 30, 0, -10 }, Sub_Legs_L = { 10, 0, 0 }, Sub_Legs_R = { -6, 0, 0 } },
		{ T = 0.7 },
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

return {
	-- Any body (Nightmares, enemies, bosses: everything has Joint_Core; legs / arms / head
	-- are used where they exist).
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
