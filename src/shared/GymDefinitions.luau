--[[
	GymDefinitions  (ModuleScript, data only)
	Location: ReplicatedStorage/Shared/GymDefinitions

	THE NIGHTMARE GYM (AFK training): reward tiers and their honest odds, what each tier
	pays out, the boosts you can buy, the bag-work routines and how hard each strike hits
	the heavy bag. GymService (server) is the only thing that rolls or grants anything;
	the client just shows these numbers.

	Odds: each tier has a base Weight (they add up to 100, so a weight IS its % at 1x
	luck). Luck multiplies the weight of Rare and above, then everything is renormalised,
	so the shown % is always the real chance (GymDefinitions.Odds).

	Balance: AFK training is deliberately slower than fighting (a boss win pays ~60 coins
	and a part in a few minutes; an hour in the gym is ~40 rolls, mostly coins), so
	playing stays the best way to progress and long AFK sessions can't out-earn it.
]]

local RGB = Color3.fromRGB

local Gym = {}

-- Where the gym hall is built (far from the map, like the boss arenas) and where its
-- lift entrance stands in the Forge.
Gym.Origin = CFrame.new(-2000, 1, -2000)
Gym.HubEntrance = Vector3.new(122, 1, 36) -- east side of the Forge, between the gate and the Colosseum
Gym.EnterRadius = 22 -- how close to the lift you must be to go in (server check)

-- Layout (shared so the builder, GymService and the client's cameras agree). The hall's
-- frame is Origin: floor top at y = 0, -Z = north. The arrival lift is in the south wall.
Gym.HallHalf = Vector3.new(56, 36, 64) -- half width, height, half length
Gym.BayCount = 6

-- The lift in the Forge, its door facing the Engine (-Z of this frame = toward the hub).
function Gym.EntranceCF(): CFrame
	local pos = Gym.HubEntrance
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

-- Where you stand when you come out of the lift in the Forge (in front of its door).
function Gym.ExitCF(): CFrame
	return Gym.EntranceCF() * CFrame.new(0, 3, -9) -- facing the hub
end

-- The arrival doorway inside the hall (-Z of this frame looks into the hall).
function Gym.ArrivalCF(): CFrame
	return Gym.Origin * CFrame.new(0, 0, Gym.HallHalf.Z)
end

-- Training bay i (1..BayCount): three down each side of the hall. -Z of the frame faces
-- the side wall (where the bag hangs); +Z is the aisle.
function Gym.BayCF(i: number): CFrame
	local west = i <= 3
	local row = (i - 1) % 3
	local z = 34 - row * 30
	local x = west and -32 or 32
	local center = Gym.Origin * CFrame.new(x, 0, z)
	local outward = Gym.Origin:VectorToWorldSpace(Vector3.new(west and -1 or 1, 0, 0))
	return CFrame.lookAt(center.Position, center.Position + outward)
end
Gym.BagOffset = Vector3.new(0, 0, -3) -- the bag's hang point in the bay frame (y set per Nightmare)
Gym.BeamHeight = 22 -- the gantry beam each bag hangs from
Gym.HandlerOffset = CFrame.new(7.5, 3, 7) -- where your Handler watches from (bay frame)
Gym.ScreenOffset = CFrame.new(-7, 0, -2.5) -- the bay's little reward screen
Gym.CrateOffset = CFrame.new(10, 0, -9) -- the reward crate that glows open on a good roll (clear of the gantry)

-- Seconds between reward rolls (Haste boosts divide this).
Gym.RewardInterval = 90

Gym.TierOrder = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Secret" }
Gym.Tiers = {
	Common = { Weight = 62, Color = RGB(190, 190, 200), Lucky = false },
	Uncommon = { Weight = 24, Color = RGB(80, 205, 100), Lucky = false },
	Rare = { Weight = 9.5, Color = RGB(70, 140, 255), Lucky = true },
	Epic = { Weight = 3.6, Color = RGB(170, 90, 255), Lucky = true },
	Legendary = { Weight = 0.8, Color = RGB(255, 195, 50), Lucky = true },
	Mythic = { Weight = 0.09, Color = RGB(255, 70, 110), Lucky = true },
	Secret = { Weight = 0.01, Color = RGB(20, 255, 220), Lucky = true },
}
for index, id in Gym.TierOrder do
	Gym.Tiers[id].Rank = index
end

-- What each tier pays. Part tiers pick a random equippable part of that rarity (falling
-- back to a lower rarity if there are none); Mutated = it also rolls a mutation.
Gym.Rewards = {
	Common = { Coins = { 8, 15 } },
	Uncommon = { Coins = { 6, 10 }, Essence = { 3, 6 } },
	Rare = { Part = "Rare", Fallback = { Essence = { 15, 20 } } },
	Epic = { Part = "Epic", Fallback = { Essence = { 30, 40 } } },
	Legendary = { Part = "Legendary", Fallback = { Essence = { 60, 80 } } },
	Mythic = { Part = "Legendary", Mutated = true, Coins = { 400, 400 }, Title = "IronWill" },
	Secret = { Part = "Legendary", Mutated = true, Coins = { 2000, 2000 }, Title = "GymPhantom" },
}

-- Training-exclusive titles (kept in profile.Gym.Titles).
Gym.Titles = {
	IronWill = { Name = "Iron Will", Tier = "Mythic" },
	GymPhantom = { Name = "Gym Phantom", Tier = "Secret" },
}

-- Boosts, bought with coins. They run on real time (they keep ticking when you leave),
-- buying one you already have adds its duration. Luck boosts don't stack with each other:
-- the strongest active one applies.
Gym.Boosts = {
	Luck2 = { Name = "2x Luck", Cost = 250, Duration = 15 * 60, Luck = 2, Text = "Rare and better rewards are twice as likely." },
	Luck3 = { Name = "3x Luck", Cost = 600, Duration = 15 * 60, Luck = 3, Text = "Rare and better rewards are three times as likely." },
	Haste = { Name = "Fast Training", Cost = 200, Duration = 15 * 60, Speed = 1.5, Text = "Rewards arrive 1.5x as often." },
	-- SHOP only (Robux; MonetizationDefinitions grants the time). No coin Cost.
	Luck5 = { Name = "Mega Luck", Duration = 30 * 60, Luck = 5, Text = "Rare and better rewards are five times as likely." },
	Turbo = { Name = "Turbo Training", Duration = 30 * 60, Speed = 2, Text = "Rewards arrive twice as often." },
}
Gym.BoostOrder = { "Luck2", "Luck3", "Haste" } -- (bought with coins in the gym)

-- The real chance of each tier at a luck multiplier: { [tier] = 0..1 }.
function Gym.Odds(luck: number)
	local weights, total = {}, 0
	for _, id in Gym.TierOrder do
		local tier = Gym.Tiers[id]
		local w = tier.Weight * (tier.Lucky and luck or 1)
		weights[id] = w
		total += w
	end
	for id, w in weights do
		weights[id] = w / total
	end
	return weights
end

-- Active multipliers from a profile.Gym.Boosts table ({ [id] = expiresAt os.time }): the
-- strongest luck boost and the strongest speed boost. `extra` (optional, from the SHOP's
-- passes and Server Luck: { Luck = x, Speed = x, MaxLuck, MaxSpeed }) multiplies on top.
function Gym.Multipliers(boosts, now: number, extra)
	local luck, speed = 1, 1
	for id, expires in boosts or {} do
		local def = Gym.Boosts[id]
		if def and expires > now then
			luck = math.max(luck, def.Luck or 1)
			speed = math.max(speed, def.Speed or 1)
		end
	end
	if extra then
		luck = math.min(luck * (extra.Luck or 1), extra.MaxLuck or math.huge)
		speed = math.min(speed * (extra.Speed or 1), extra.MaxSpeed or math.huge)
	end
	return luck, speed
end

------------------------------------------------------------------------------------------
-- Bag work
------------------------------------------------------------------------------------------
-- Routines the server cycles through (an action = a NightmarePoses.Common "Gym_*" pose
-- played at its own speed). Arms = true needs an arm, false is for armless bodies (they
-- train their jaws on the bag), no Arms = any body. Weight = how often it's picked (never
-- twice in a row while there's a choice).
Gym.Routines = {
	{ Action = "Gym_ComboA", Duration = 1.6, Weight = 3, Arms = true }, -- jab, jab, cross
	{ Action = "Gym_ComboB", Duration = 1.8, Weight = 3, Arms = true }, -- jab, cross, hook
	{ Action = "Gym_ComboC", Duration = 2.1, Weight = 2, Arms = true }, -- jab, hook, overhand
	{ Action = "Gym_BodyRip", Duration = 1.5, Weight = 2, Arms = true }, -- body hook, uppercut
	{ Action = "Gym_Power", Duration = 1.4, Weight = 1, Arms = true }, -- one big overhand
	{ Action = "Gym_Bounce", Duration = 1.6, Weight = 2 }, -- stance, feints, footwork (any body)
	{ Action = "Gym_Weave", Duration = 2.4, Weight = 3 }, -- slips, a weave under, a pull back (any body)
	{ Action = "Gym_SlipCounter", Duration = 1.9, Weight = 3, Arms = true }, -- slip, slip, cross, hook
	{ Action = "Gym_RollHook", Duration = 2, Weight = 3, Arms = true }, -- roll under, hook, overhand
	{ Action = "Gym_PullCounter", Duration = 1.6, Weight = 2, Arms = true }, -- jab, pull back, cross
	{ Action = "Gym_DuckUpper", Duration = 1.7, Weight = 2, Arms = true }, -- duck, uppercut, hook
	{ Action = "Ability_Bite", Duration = 2.3, Weight = 3, Arms = false, Windup = 0.3, Spot = "Bite" }, -- jaw work: clamp, thrash, rip
	-- kicks (two-legged bodies). Reach = how far out the foot lands on the contact frame, as
	-- a fraction of the leg's length (measured on the gym bag): GymService steps the body
	-- in or out to that range first, so each kick lands on the leather, not through it.
	{ Action = "Gym_Teep", Duration = 1.3, Weight = 2, Legs = true, Reach = 0.91 },
	-- (measured gaps on the bag: teep +0.3..−0.1; roundhouse / spin kick tuned back from
	-- −0.8 / −1.0 deep; the clinch holds the bag so all three knees land)
	{ Action = "Gym_Roundhouse", Duration = 1.5, Weight = 3, Legs = true, Reach = 1.1 },
	{ Action = "Gym_KneeClinch", Duration = 1.8, Weight = 2, Legs = true, Reach = 0.95 },
	{ Action = "Gym_SpinBackKick", Duration = 1.6, Weight = 1, Legs = true, Reach = 1.16 },
	-- its OWN abilities, picked at random from its loadout and practised on the bag
	{ Abilities = true, Weight = 4 },
	{ Action = "Gym_Rest", Duration = 3.2, Weight = 1, Rest = true }, -- hands on knees, breathe, shake out
}
-- Pause between routines (seconds), and how many routines before a rest is due.
Gym.RoutineGap = { 0.4, 1.2 }
-- It works its way around the bag between routines: chance to move, and the angles (degrees
-- around the bag from the front of the bay) it boxes from.
Gym.RingMoveChance = 0.65
Gym.RingAngles = { -40, -22, 0, 22, 40 }
Gym.RestEvery = { 5, 8 }

-- How each strike marker pushes the bag (studs/s at the bag, in the striker's frame:
-- Forward = away from it, Side = toward its right, Twist = spin in rad/s) and what it
-- sounds like. "Hit" is any other attack's contact frame (e.g. a bite).
Gym.Strikes = {
	BagJab = { Forward = 3.2, Side = 0.3, Twist = 0.2, Sound = "BagHit" },
	BagCross = { Forward = 5.2, Side = -0.6, Twist = -0.5, Sound = "BagHit" },
	BagHook = { Forward = 2.6, Side = 4.6, Twist = 1.6, Sound = "BagHeavy" },
	BagBody = { Forward = 3.6, Side = 2.2, Twist = 0.8, Sound = "BagHit" },
	BagUpper = { Forward = 3.4, Side = -0.4, Twist = -0.3, Sound = "BagHit" },
	BagOverhand = { Forward = 7.2, Side = -1.4, Twist = -0.9, Sound = "BagHeavy" },
	BagTeep = { Forward = 7.8, Side = 0, Twist = 0.3, Sound = "BagHeavy" },
	BagRound = { Forward = 3.2, Side = -7, Twist = -2.4, Sound = "BagHeavy" }, -- whips it round to the left
	BagKnee = { Forward = 3.8, Side = 0, Twist = 0.4, Sound = "BagHit" },
	BagSpin = { Forward = 8.6, Side = 0.6, Twist = 1.2, Sound = "BagHeavy" },
	Hit = { Forward = 4.2, Side = 0, Twist = 0.6, Sound = "BagHit" },
	-- a bite: the jaws CLAMP on (the bag is held, thrashed with the head), then RIP it away
	BiteClamp = { Hold = true, Sound = "BagHit" },
	-- the clinch: both hands grab it over the top and hold it in close for the knees
	Clinch = { Hold = true, Duration = 1.35, Pull = 0.3, Sound = "ChainRattle" },
	Rip = { Forward = -1.5, Side = -6.5, Twist = 2.8, Sound = "BagHeavy" },
}

-- The heavy bag itself.
Gym.Bag = {
	Radius = 1.7,
	Height = 6.4,
	Gravity = 120, -- effective, so it swings with a heavy bag's slow period (~1.6 s)
	Damping = 1.1, -- per second
	MaxSwing = 3.2, -- studs the bag centre may swing from rest
}

return Gym
