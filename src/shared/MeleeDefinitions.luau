--[[
	MeleeDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/MeleeDefinitions

	The Handler's hand-to-hand fighting: every move, how moves COMBO into each other, the
	weapons, and what unlocks them. Shared: the client plays and chains the moves, the
	server checks every one (timing, chain, unlocks, weapon charges) and lands the hits.

	INPUTS:  P = attack (LMB / R2 / ATTACK)   K = kick (right-click / X / KICK)
	A combo is the string of inputs so far, e.g. "PPK" = punch, punch, kick. Each input
	continues the combo if that string is a known move (and unlocked); otherwise it starts a
	new combo with that one input. The next input is accepted from a move's Cancel time
	(right after its hit lands) until ComboWindow seconds after it ends; pressed earlier, it
	is buffered and fires at Cancel.

	FISTS (the default, fought like a UFC striker):
	  P Jab · PP Cross · PPP Lead hook · PPPP OVERHAND (knockdown, unlock)
	  K Head kick · KK Leg kick · KKK SPIN KICK (knockdown, unlock)
	  PK Knee · PPK Head kick · KP Uppercut · KPK Teep (push kick)
	  K while running: DROP KICK (knockdown, unlock)
	  Right after a step back: P / K = COUNTER punch / kick (dash back in)

	WEAPONS are much stronger than fists, so each has CHARGES: Uses attacks, then it goes
	back on your belt and recharges for Recharge seconds (your fists come back up by
	themselves). You take your fists plus up to LoadoutSlots weapons into a fight (the
	ARSENAL picks them). Kicks never use charges and mix into every weapon's chain.
	  Magnet       hold it out: drags the enemy in front of you to you (bosses: you to them)
	  Reaper Scythe  big two-handed sweeps, the third a full spin (knockdown)
	  Rust Blade   full swings through the target, then a lunging stab
	  Chain Whip   a real chain: drags on the floor, lashes out and cracks at range
	  Storm Spear  thrown: flies at the target, lightning on impact (knockdown + Shock)

	Move fields:
	  Pose       HandlerAnimator code animation (AnimationDefinitions slot of the same name)
	  Duration   total seconds;  HitTime  when the hit lands;  Cancel  earliest next input
	  Damage     base damage (x the Handler's 100 attack power)
	  Range      reach (studs) from the Handler;  Arc  degrees of the swing in front of you
	             (360 = all around)
	  Knockback, Stagger, Heavy (Heavy = knocks the target down: CombatService ragdoll)
	  Lunge      studs the Handler slides forward during the windup (stopping at Contact)
	  Weapon     true: this attack spends one of the weapon's charges
	  Pull / Throw / Lash   the Magnet's pull, the Spear's throw, the Whip's crack
	  Status     status effect on hit (StatusDefinitions id)
	  Unlock     { Level = n } (moves and weapons; purchases arrive with the shop)
]]

local RunService = game:GetService("RunService")
local Config = require(script.Parent:WaitForChild("Config"))

local MeleeDefinitions = {}

MeleeDefinitions.ComboWindow = 0.6 -- seconds after a move ends that the combo can continue
MeleeDefinitions.Tolerance = 0.12 -- server latency allowance on every timing check
MeleeDefinitions.HitHeight = 8 -- a target this far above / below you can still be hit
MeleeDefinitions.LoadoutSlots = 3 -- weapons you take into a fight (plus your fists)

local Moves = {
	-- Fists (striker) --------------------------------------------------------------------
	-- (Lunge: the step in; the client stops it with your fist on them, see MeleeController)
	Jab = { Pose = "Jab", Duration = 0.34, HitTime = 0.11, Cancel = 0.2, Damage = 5, Range = 6.5, Arc = 60, Stagger = 3, Lunge = 1.8 },
	Cross = { Pose = "Cross", Duration = 0.4, HitTime = 0.14, Cancel = 0.24, Damage = 7, Range = 7, Arc = 60, Stagger = 4, Lunge = 2.4 },
	Hook = { Pose = "Hook", Duration = 0.46, HitTime = 0.17, Cancel = 0.28, Damage = 8, Range = 6, Arc = 100, Knockback = 8, Stagger = 6, Lunge = 1.5 },
	-- (HitDir: the way the force goes, in YOUR frame {right, up, forward}: the overhand
	-- comes over the top, so it drives down, forward and across to your left. Crumple: a
	-- heavy enough hit buckles their legs and drops them where they stand instead of
	-- launching them.)
	Overhand = { Pose = "Overhand", Duration = 0.86, HitTime = 0.34, Cancel = 0.62, Damage = 14, Range = 7, Arc = 70, Knockback = 35, Stagger = 18, Heavy = true, Lunge = 3, HitDir = { -0.4, -0.65, 0.65 }, Crumple = true, Unlock = { Level = 2 }, Display = "Overhand Knockdown" },
	Uppercut = { Pose = "Uppercut", Duration = 0.48, HitTime = 0.18, Cancel = 0.3, Damage = 9, Range = 5.5, Arc = 60, Knockback = 12, Stagger = 9, Lunge = 1.8 },
	HeadKick = { Pose = "HeadKick", Duration = 0.6, HitTime = 0.24, Cancel = 0.4, Damage = 10, Range = 7.5, Arc = 110, Knockback = 18, Stagger = 9, Lunge = 1.6 },
	LegKick = { Pose = "LegKick", Duration = 0.42, HitTime = 0.16, Cancel = 0.28, Damage = 7, Range = 6.5, Arc = 90, Stagger = 10, Lunge = 1.3 },
	SpinKick = { Pose = "SpinKick", Duration = 0.75, HitTime = 0.36, Cancel = 0.58, Damage = 13, Range = 8, Arc = 140, Knockback = 34, Stagger = 16, Heavy = true, Lunge = 1.5, Unlock = { Level = 4 }, Display = "Spin Kick" },
	Knee = { Pose = "Knee", Duration = 0.4, HitTime = 0.15, Cancel = 0.26, Damage = 8, Range = 5, Arc = 60, Stagger = 8, Lunge = 1.5 },
	Teep = { Pose = "FrontKick", Duration = 0.46, HitTime = 0.18, Cancel = 0.3, Damage = 7, Range = 7, Arc = 60, Knockback = 20, Stagger = 5, Lunge = 0.8 },
	-- (the client first SPRINTS at the target, up to SprintTime, then leaps: this move
	-- starts at the leap)
	DropKick = { Pose = "DropKick", Duration = 1.3, HitTime = 0.26, Cancel = 1.2, Damage = 14, Range = 8, Arc = 70, Knockback = 40, Stagger = 15, Heavy = true, Leap = 11, SprintRange = 30, SprintSpeed = 30, SprintTime = 1.1, Unlock = { Level = 6 }, Display = "Drop Kick" },
	-- 1-2-3 then the head kick: the classic finisher (harder than a lone head kick, knocks down)
	HeadKickFinisher = { Pose = "HeadKick", Duration = 0.62, HitTime = 0.24, Cancel = 0.5, Damage = 15, Range = 7.5, Arc = 110, Knockback = 38, Stagger = 16, Heavy = true, Lunge = 1.6, Display = "1-2-3 Head Kick" },
	-- Counters (right after a step back): the client dashes the whole gap back in; Lunge
	-- here only widens the server's reach to cover that dash.
	CounterPunch = { Pose = "SupermanPunch", Duration = 0.55, HitTime = 0.22, Cancel = 0.36, Damage = 14, Range = 8, Arc = 80, Knockback = 32, Stagger = 15, Lunge = 9, Display = "Superman Punch" },
	CounterKick = { Pose = "CounterHeadKick", Duration = 0.72, HitTime = 0.3, Cancel = 0.52, Damage = 16, Range = 7.5, Arc = 110, Knockback = 36, Stagger = 18, Heavy = true, Lunge = 9, Display = "Head Hunter" },

	-- Reaper Scythe: wide two-handed sweeps --------------------------------------------
	ScytheReap = { Pose = "ScytheReap", Duration = 0.66, HitTime = 0.27, Cancel = 0.44, Damage = 16, Range = 9, Arc = 180, Knockback = 16, Stagger = 10, Lunge = 2, Weapon = true, Trail = true },
	ScytheReturn = { Pose = "ScytheReturn", Duration = 0.66, HitTime = 0.26, Cancel = 0.44, Damage = 16, Range = 9, Arc = 180, Knockback = 16, Stagger = 10, Lunge = 2, Weapon = true, Trail = true },
	ScytheWhirl = { Pose = "ScytheWhirl", Duration = 0.95, HitTime = 0.42, Cancel = 0.78, Damage = 24, Range = 10, Arc = 360, Knockback = 40, Stagger = 24, Heavy = true, Weapon = true, Trail = true },
	-- Rust Blade: full swings through the target ----------------------------------------
	BladeSlash = { Pose = "BladeForehand", Duration = 0.4, HitTime = 0.15, Cancel = 0.24, Damage = 10, Range = 8, Arc = 150, Stagger = 4, Lunge = 1.2, Weapon = true, Trail = true },
	BladeSlash2 = { Pose = "BladeBackhand", Duration = 0.4, HitTime = 0.15, Cancel = 0.24, Damage = 10, Range = 8, Arc = 150, Stagger = 4, Lunge = 1.2, Weapon = true, Trail = true },
	BladeCleave = { Pose = "BladeCleave", Duration = 0.5, HitTime = 0.2, Cancel = 0.32, Damage = 12, Range = 8, Arc = 90, Stagger = 6, Lunge = 1.2, Weapon = true, Trail = true },
	BladeLunge = { Pose = "Thrust", Duration = 0.6, HitTime = 0.2, Cancel = 0.42, Damage = 16, Range = 10, Arc = 40, Knockback = 22, Stagger = 10, Lunge = 5, Weapon = true, Trail = true },
	-- Chain Whip: a physical chain that lashes out --------------------------------------
	-- (Range = how far the simulated chain actually reaches: arm + ~8.5 studs of chain)
	WhipCrack = { Pose = "WhipCrack", Duration = 0.6, HitTime = 0.3, Cancel = 0.42, Damage = 11, Range = 11, Arc = 35, Stagger = 6, Lash = true, Weapon = true },
	WhipCrack2 = { Pose = "WhipCrack", Duration = 0.6, HitTime = 0.3, Cancel = 0.42, Damage = 11, Range = 11, Arc = 35, Stagger = 6, Lash = true, Weapon = true },
	WhipSweep = { Pose = "WhipSweep", Duration = 0.85, HitTime = 0.38, Cancel = 0.6, Damage = 15, Range = 10, Arc = 200, Knockback = 20, Stagger = 12, Lash = true, Weapon = true },
	-- Storm Spear: thrown ----------------------------------------------------------------
	SpearThrow = { Pose = "SpearThrow", Duration = 0.7, HitTime = 0.32, Cancel = 0.6, Damage = 24, Range = 45, Arc = 30, Knockback = 30, Stagger = 20, Heavy = true, Status = "Shock", Throw = true, Speed = 110, Weapon = true },
	-- Magnet -----------------------------------------------------------------------------
	-- (on a boss: it yanks YOU in, deals 4x and BossStagger: a big bite of its stagger bar)
	MagnetPull = { Pose = "MagnetPull", Duration = 0.8, HitTime = 0.22, Cancel = 0.7, Damage = 3, Range = 30, Arc = 50, Stagger = 12, BossStagger = 90, Pull = true, PullTime = 0.5, Weapon = true },
}
-- Contact: studs from the target's body where the step-in (Lunge) stops, so the fist /
-- shin / blade lands right ON them (fists 2.3 by default; legs and weapons reach further).
local CONTACT = {
	Knee = 1.7, LegKick = 2.8, HeadKick = 3.2, Teep = 3.2, SpinKick = 3.4, CounterKick = 3.2,
	BladeSlash = 3.4, BladeSlash2 = 3.4, BladeCleave = 3.4, BladeLunge = 3.6,
	ScytheReap = 5.5, ScytheReturn = 5.5, -- (the blade is out at arm's length + the snath)
}
for id, contact in CONTACT do
	Moves[id].Contact = contact
end
for id, move in Moves do
	move.Id = id
	move.Knockback = move.Knockback or 0
	move.Arc = move.Arc or 60
	move.Display = move.Display or id
end
MeleeDefinitions.Moves = Moves

-- Combo strings per style. Weapons fall back to the Fists table for kick-led strings.
local Styles = {
	Fists = {
		P = "Jab", PP = "Cross", PPP = "Hook", PPPP = "Overhand",
		PPK = "LegKick", PPPK = "HeadKickFinisher", -- 1-2 low kick / 1-2-3 head kick
		PK = "Knee", PKP = "Uppercut", -- clinch: knee, then the uppercut through the middle
		K = "HeadKick", KK = "LegKick", KKK = "SpinKick",
		KP = "Cross", KPP = "Hook", KPK = "Teep", -- kick, then box
	},
	ReaperScythe = { P = "ScytheReap", PP = "ScytheReturn", PPP = "ScytheWhirl" },
	RustBlade = { P = "BladeSlash", PP = "BladeSlash2", PPP = "BladeCleave", PPPP = "BladeLunge", KP = "BladeLunge" },
	ChainWhip = { P = "WhipCrack", PP = "WhipCrack2", PPP = "WhipSweep", KP = "WhipCrack" },
	StormSpear = { P = "SpearThrow" },
	Magnet = { P = "MagnetPull" },
}

-- SIGNATURE COMBOS: the moves worth finding. Pull one off for the first time and it's
-- DISCOVERED (a banner, and it's saved in your FIGHTER menu); until then the menu only shows
-- the Hint. Seq = the combo string ("Counter" / "Drop" for the step-back and running ones).
MeleeDefinitions.Combos = {
	{ Id = "OneTwo", Name = "The 1-2", Seq = "PP", Inputs = "P P", Hint = "Jab, then the straight behind it." },
	{ Id = "OneTwoThree", Name = "1-2-3", Seq = "PPP", Inputs = "P P P", Hint = "Finish the 1-2 with a hook." },
	{ Id = "Overhand", Name = "Overhand Knockdown", Seq = "PPPP", Inputs = "P P P P", Hint = "Keep punching after the hook: loop one over the top.", Move = "Overhand" },
	{ Id = "LowKick", Name = "1-2 Low Kick", Seq = "PPK", Inputs = "P P K", Hint = "Two punches upstairs, then chop the leg." },
	{ Id = "HeadKickFinisher", Name = "1-2-3 Head Kick", Seq = "PPPK", Inputs = "P P P K", Hint = "Three punches... and finish with your leg.", Move = "HeadKickFinisher" },
	{ Id = "KneeUppercut", Name = "Clinch Knee & Uppercut", Seq = "PKP", Inputs = "P K P", Hint = "A jab, a knee, then come up the middle." },
	{ Id = "SpinKick", Name = "Spin Kick", Seq = "KKK", Inputs = "K K K", Hint = "Kick, kick... and spin.", Move = "SpinKick" },
	{ Id = "KickBox", Name = "Kick & Box", Seq = "KPP", Inputs = "K P P", Hint = "Land a kick, then follow it in with your hands." },
	{ Id = "Teep", Name = "Kick-Punch-Teep", Seq = "KPK", Inputs = "K P K", Hint = "Kick, punch, then push them away." },
	{ Id = "SupermanPunch", Name = "Superman Punch", Seq = "Counter:P", Inputs = "X then P", Hint = "Step back out of range... then punch.", Move = "CounterPunch" },
	{ Id = "HeadHunter", Name = "Head Hunter", Seq = "Counter:K", Inputs = "X then K", Hint = "Step back out of range... then kick.", Move = "CounterKick" },
	{ Id = "DropKick", Name = "Drop Kick", Seq = "Drop:K", Inputs = "Run, then K", Hint = "Get up to full speed... and kick.", Move = "DropKick" },
}
MeleeDefinitions.CombosBySeq = {}
for _, combo in MeleeDefinitions.Combos do
	MeleeDefinitions.CombosBySeq[combo.Seq] = combo
end

-- RUN STYLES (FIGHTER menu): how you run around, on everyone's screen. Every style
-- blends straight into any strike the moment you attack. Cost in coins (0 = free).
MeleeDefinitions.Runs = {
	{ Id = "Charge", Name = "Fighter's Charge", Cost = 0, Blurb = "Leaning in, fists up and pumping: rushing someone." },
	{ Id = "Ninja", Name = "Ninja Run", Cost = 120, Blurb = "Bent double, arms streaming straight back." },
	{ Id = "Swagger", Name = "Tough Guy Swagger", Cost = 160, Blurb = "Shoulders rolling, arms out wide, nobody's scared of you." },
	{ Id = "Zombie", Name = "Zombie Lurch", Cost = 200, Blurb = "Arms straight out, head lolling, still somehow fast." },
	{ Id = "Chicken", Name = "Headless Chicken", Cost = 260, Blurb = "Elbows flapping, head bobbing. Terrifying, honestly." },
	{ Id = "Gorilla", Name = "Gorilla Charge", Cost = 320, Blurb = "Low and heavy, knuckles swinging at the floor." },
	{ Id = "Superhero", Name = "Superhero Dash", Cost = 450, Blurb = "One fist punching the sky, cape optional." },
}
MeleeDefinitions.RunsById = {}
for _, run in MeleeDefinitions.Runs do
	MeleeDefinitions.RunsById[run.Id] = run
end

-- Weapons in ARSENAL order.
--   Uses / Recharge  attacks before it goes back on your belt / seconds to recharge
--   Hold             HandlerPoses pose while it's out;  WalkSpeed  (optional) slows you
MeleeDefinitions.Weapons = {
	{ Id = "Magnet", Display = "The Magnet", Short = "MAGNET", Icon = "🧲", Color = Color3.fromRGB(220, 60, 60), Unlock = { Level = 1 }, Uses = 1, Recharge = 15, Hold = "HoldMagnet", WalkSpeed = 9,
		Blurb = "Hold it out and drag the enemy in front of you right to your fists. Bosses don't budge: it drags YOU to them. Once every 15 s." },
	{ Id = "ReaperScythe", Display = "Reaper Scythe", Short = "SCYTHE", Icon = "☠", Color = Color3.fromRGB(170, 90, 255), Unlock = { Level = 3 }, Uses = 5, Recharge = 24, Hold = "HoldScythe",
		Blurb = "Huge two-handed sweeps that hit everything in front of you; the third whirls all the way round and knocks down." },
	{ Id = "RustBlade", Display = "Rust Blade", Short = "BLADE", Icon = "🗡", Color = Color3.fromRGB(200, 200, 210), Unlock = { Level = 5 }, Uses = 8, Recharge = 20, Hold = "HoldBlade",
		Blurb = "Fast full swings straight through the target, finishing with a lunging stab." },
	{ Id = "ChainWhip", Display = "Chain Whip", Short = "WHIP", Icon = "⛓", Color = Color3.fromRGB(150, 150, 165), Unlock = { Level = 8 }, Uses = 6, Recharge = 22, Hold = "HoldWhip",
		Blurb = "A real chain: it drags on the floor, lashes out and cracks from far away. The third lash sweeps a crowd." },
	{ Id = "StormSpear", Display = "Storm Spear", Short = "SPEAR", Icon = "⚡", Color = Color3.fromRGB(120, 210, 255), Unlock = { Level = 12 }, Uses = 1, Recharge = 10, Hold = "HoldSpear",
		Blurb = "Throw it: it flies straight at your target and strikes with lightning (knockdown + Shock). Back in your hand 10 s later." },
}
MeleeDefinitions.WeaponsById = {}
for _, weapon in MeleeDefinitions.Weapons do
	MeleeDefinitions.WeaponsById[weapon.Id] = weapon
end

local STUDIO_UNLOCK = RunService:IsStudio() and Config.Dev.UnlockAllMovesInStudio == true

local function unlocked(def, level: number?): boolean
	return def ~= nil and (STUDIO_UNLOCK or def.Unlock == nil or (level or 1) >= (def.Unlock.Level or 1))
end

function MeleeDefinitions.MoveUnlocked(moveId: string, level: number?): boolean
	return unlocked(Moves[moveId], level)
end

function MeleeDefinitions.WeaponUnlocked(weaponId: string?, level: number?): boolean
	if weaponId == nil or weaponId == "Fists" then
		return true
	end
	return unlocked(MeleeDefinitions.WeaponsById[weaponId], level)
end

-- The move for combo string `seq` with `weapon` out, or nil (not a known / unlocked move).
function MeleeDefinitions.Resolve(weapon: string?, seq: string, level: number?): string?
	local style = Styles[weapon or "Fists"] or Styles.Fists
	local id = style[seq]
	if id == nil and not seq:find("P") then
		id = Styles.Fists[seq] -- kicks work with every weapon
	end
	if id and MeleeDefinitions.MoveUnlocked(id, level) then
		return id
	end
	return nil
end

-- A clean loadout: up to LoadoutSlots distinct, known weapon ids (unlock not checked).
function MeleeDefinitions.CleanLoadout(list): { string }
	local clean = {}
	if type(list) ~= "table" then
		return clean
	end
	for _, id in list do
		if type(id) == "string" and MeleeDefinitions.WeaponsById[id] and not table.find(clean, id) and #clean < MeleeDefinitions.LoadoutSlots then
			table.insert(clean, id)
		end
	end
	return clean
end

-- Every unlock with a level above 1, for LevelUnlocks / the GOALS screen.
function MeleeDefinitions.Unlocks(): { { Level: number, Text: string } }
	local list = {}
	for _, move in Moves do
		if move.Unlock and (move.Unlock.Level or 1) > 1 then
			table.insert(list, { Level = move.Unlock.Level, Text = ("New move: %s"):format(move.Display) })
		end
	end
	for _, weapon in MeleeDefinitions.Weapons do
		if (weapon.Unlock.Level or 1) > 1 then
			table.insert(list, { Level = weapon.Unlock.Level, Text = ("New weapon: %s"):format(weapon.Display) })
		end
	end
	return list
end

return MeleeDefinitions
