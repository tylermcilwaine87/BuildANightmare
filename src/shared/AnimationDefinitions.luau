--[[
	AnimationDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/AnimationDefinitions

	EVERY HANDLER ANIMATION SLOT IN THE GAME. Each move has a slot:

	  Id    an uploaded animation ("rbxassetid://..."). When filled, the game plays it.
	  Code  the built-in code animation used while Id is empty (HandlerAnimator's poses).

	To upgrade a move to a hand-made / motion-captured animation:
	  1. Studio → Avatar tab → Animation Editor (or Animation Capture from a video).
	  2. Make the move on an R15 rig and click Publish to Roblox.
	  3. Copy the animation's id and paste it into that move's Id below. Done: no other
	     code changes.
	Leave Id = "" to keep the code animation.

	Run / Walk replace Roblox's default run and walk cycles (any R15 run animation works;
	Roblox's own animation-pack animations are free for every game). If an id fails to
	load, the default cycle is kept, so a bad id never breaks movement.
]]

local AnimationDefinitions = {}

AnimationDefinitions.Handler = {
	-- Movement
	-- Run: with no Id, the CHARGE style plays: Roblox's default running legs with a code
	-- upper body on top (leaning in, fists up and pumping, like you're rushing someone).
	Run = { Id = "", Code = "CombatRun", Note = "charging at someone, fists up" },
	Walk = { Id = "", Note = "empty = Roblox default walk" },

	-- Combat
	Dive = { Id = "", Code = "Dive", Note = "Shift: dive forward, roll on the floor, come up on your feet" },
	StepBack = { Id = "", Code = "StepBack", Note = "X: quick hop straight back, guard up" },
	SupermanPunch = { Id = "", Code = "SupermanPunch", Note = "step back, then P: fly back in with a superman punch" },
	CounterHeadKick = { Id = "", Code = "CounterHeadKick", Note = "step back, then K: Head Hunter, a step-in head kick" },

	-- Punches, UFC orthodox (MeleeDefinitions: P, PP, PPP, PPPP, KP)
	Jab = { Id = "", Code = "Jab", Note = "P: lead-hand jab, half-step in" },
	Cross = { Id = "", Code = "Cross", Note = "PP: rear straight, hips through, back foot pivots" },
	Hook = { Id = "", Code = "Hook", Note = "PPP: lead hook, elbow level, whole body turning" },
	Overhand = { Id = "", Code = "Overhand", Note = "PPPP (unlock): looping overhand right, knockdown" },
	Uppercut = { Id = "", Code = "Uppercut", Note = "KP: dip and drive the rear uppercut" },
	-- Kicks (K, KK, KKK, PK, PPK, KPK, running K)
	HeadKick = { Id = "", Code = "HeadKick", Note = "K / PPK: UFC head kick, hip turning over" },
	LegKick = { Id = "", Code = "LegKick", Note = "KK: chopping leg kick" },
	SpinKick = { Id = "", Code = "SpinKick", Note = "KKK (unlock): spinning kick, knockdown" },
	Knee = { Id = "", Code = "Knee", Note = "PK: clinch knee" },
	FrontKick = { Id = "", Code = "FrontKick", Note = "KPK: teep (push kick)" },
	SprintCharge = { Id = "", Code = "SprintCharge", Note = "the flat-out sprint before a drop kick (one stride, loops)" },
	DropKick = { Id = "", Code = "DropKick", Note = "K while running (unlock): leap flat out, both feet in, land and get up" },
	-- Weapons
	ScytheReap = { Id = "", Code = "ScytheReap", Note = "Reaper Scythe: two-handed sweep" },
	ScytheReturn = { Id = "", Code = "ScytheReturn", Note = "Reaper Scythe: return sweep" },
	ScytheWhirl = { Id = "", Code = "ScytheWhirl", Note = "Reaper Scythe: full spin (knockdown)" },
	BladeForehand = { Id = "", Code = "BladeForehand", Note = "Rust Blade: full forehand swing" },
	BladeBackhand = { Id = "", Code = "BladeBackhand", Note = "Rust Blade: full backhand swing" },
	BladeCleave = { Id = "", Code = "BladeCleave", Note = "Rust Blade: diagonal cleave" },
	Thrust = { Id = "", Code = "Thrust", Note = "Rust Blade: lunging stab" },
	WhipCrack = { Id = "", Code = "WhipCrack", Note = "Chain Whip: overhead crack (the chain is physics)" },
	WhipSweep = { Id = "", Code = "WhipSweep", Note = "Chain Whip: flat sweep round" },
	SpearThrow = { Id = "", Code = "SpearThrow", Note = "Storm Spear: javelin throw" },
	MagnetPull = { Id = "", Code = "MagnetPull", Note = "Magnet: held out, braced, dragging them in" },
	GetUpFront = { Id = "", Code = "GetUpFront", Note = "knocked down face-first: push up, knees under, stand" },
	GetUpBack = { Id = "", Code = "GetUpBack", Note = "knocked onto your back: sit up, feet under, stand" },
	DodgeLeft = { Id = "", Code = "DodgeLeft", Note = "Shift + left while facing someone: side dive, shoulder roll, still facing them" },
	DodgeRight = { Id = "", Code = "DodgeRight", Note = "Shift + right while facing someone: side dive (mirror of DodgeLeft)" },
}

-- NIGHTMARE attacks, per body plan: "Nightmare_<Archetype>_<Action>" (the server's
-- ActionName). With no Id the keyframes in NightmarePoses play (and, in Studio, the
-- editable KeyframeSequence of the same name in Shared/Animations). Publish that
-- KeyframeSequence and paste its Id here to use it everywhere.
AnimationDefinitions.Nightmare = {
	Nightmare_Biped_Heavy = { Id = "", Note = "Biped heavy haymaker: coil, lunge, over and through" },
}

-- BOSS attacks: "Boss_<BossId>_<Action>" (BossPoses; same rules as above).
AnimationDefinitions.Boss = {
	Boss_ScrapTitan_Slam = { Id = "", Note = "Scrap Titan leaping double-fist ground slam" },
}

return AnimationDefinitions
