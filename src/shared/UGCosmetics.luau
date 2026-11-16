--[[
	UGCosmetics  (ModuleScript, shared)
	Location: ReplicatedStorage/Shared/UGCosmetics

	NIGHTMARE UNDERGROUND's cosmetic fight presentation: the ENTRANCE your Nightmare makes
	before round 1, and the VICTORY POSE it strikes when it wins. Earned by fighting, never
	stronger: they change nothing about the fight itself.

	Each one is a keyframed clip on the Nightmare (NightmarePoses, made for every anatomy:
	the four-legged bodies get their own version) plus the client's staging around it
	(UndergroundController: the camera, the spotlight, the dust and the sparks).

	Unlock = nil: everyone has it. Otherwise { Stat, Count, Text }: a career number in
	profile.Underground (Wins, KOs, Fights, Knockdowns...), or Stat = "Title" (any season
	title in profile.UGRanked.Titles) / "Champion" (a season's #1 title).
]]

local UGCosmetics = {}

UGCosmetics.Intros = {
	{
		Id = "Contender",
		Name = "THE CONTENDER",
		Clip = "UG_IntroContender",
		Duration = 2.2,
		Desc = "Walks out loose and shadowboxes: jab, cross, gloves up.",
	},
	{
		Id = "Champion",
		Name = "THE CHAMPION",
		Clip = "UG_IntroChampion",
		Duration = 2.2,
		Desc = "Enters like it owns the place and throws both arms up to the crowd.",
		Unlock = { Stat = "Wins", Count = 5, Text = "Win 5 Underground fights" },
	},
	{
		Id = "Beast",
		Name = "THE BEAST",
		Clip = "UG_IntroBeast",
		Duration = 2.4,
		Desc = "Roars, then slams its claws into the floor. The dust comes up.",
		Unlock = { Stat = "KOs", Count = 5, Text = "Win 5 rounds by knockout" },
	},
	{
		Id = "Machine",
		Name = "THE MACHINE",
		Clip = "UG_IntroMachine",
		Duration = 2.4,
		Desc = "Powers up joint by joint, sparks at every lock, then snaps into its stance.",
		Unlock = { Stat = "Fights", Count = 15, Text = "Fight 15 Underground fights" },
	},
	{
		Id = "Predator",
		Name = "THE PREDATOR",
		Clip = "UG_IntroPredator",
		Duration = 2.4,
		Circle = true, -- (it circles on the way in before it settles on its prey)
		Desc = "Circles in low, then locks its eyes on the other corner.",
		Unlock = { Stat = "Knockdowns", Count = 15, Text = "Score 15 knockdowns" },
	},
	{
		Id = "King",
		Name = "THE KING",
		Clip = "UG_IntroKing",
		Duration = 2.4,
		Spotlight = true, -- (it walks under a golden spotlight, its title over its name)
		Desc = "Walks under golden spotlights, chin up, its title on the screen.",
		Unlock = { Stat = "Title", Text = "Earn any ranked season title" },
	},
}

UGCosmetics.Victories = {
	{
		Id = "Roar",
		Name = "THE ROAR",
		Clip = "UG_Victory",
		Duration = 2.6,
		Desc = "Both fists up, roaring to one side of the crowd and then the other.",
	},
	{
		Id = "Flex",
		Name = "THE FLEX",
		Clip = "UG_VictoryFlex",
		Duration = 2.6,
		Desc = "A double-biceps pose, then a turn to show the other side.",
		Unlock = { Stat = "Wins", Count = 3, Text = "Win 3 Underground fights" },
	},
	{
		Id = "ChestPound",
		Name = "THE CHEST POUND",
		Clip = "UG_VictoryChest",
		Duration = 2.6,
		Desc = "Pounds its chest, left, right, left, and roars.",
		Unlock = { Stat = "KOs", Count = 3, Text = "Win 3 rounds by knockout" },
	},
	{
		Id = "Bow",
		Name = "THE BOW",
		Clip = "UG_VictoryBow",
		Duration = 2.6,
		Desc = "A deep bow to the beaten fighter, then one fist up.",
		Unlock = { Stat = "Fights", Count = 10, Text = "Fight 10 Underground fights" },
	},
	{
		Id = "Champion",
		Name = "THE CHAMPION'S SALUTE",
		Clip = "UG_VictoryChampion",
		Duration = 2.6,
		Desc = "One fist driven straight up and held; it points out the crowd.",
		Unlock = { Stat = "Champion", Text = "Finish a ranked season as the #1 Champion" },
	},
}

UGCosmetics.IntroById, UGCosmetics.VictoryById = {}, {}
for _, def in UGCosmetics.Intros do
	UGCosmetics.IntroById[def.Id] = def
end
for _, def in UGCosmetics.Victories do
	UGCosmetics.VictoryById[def.Id] = def
end
UGCosmetics.DefaultIntro, UGCosmetics.DefaultVictory = "Contender", "Roar"

-- How far `profile` is toward `def`: (unlocked, have, need). profile is the player's whole
-- profile (Underground career numbers + UGRanked titles).
function UGCosmetics.Progress(def, profile): (boolean, number, number)
	local unlock = def.Unlock
	if not unlock then
		return true, 1, 1
	end
	if unlock.Stat == "Title" or unlock.Stat == "Champion" then
		local titles = profile and profile.UGRanked and profile.UGRanked.Titles or {}
		for id in titles do
			if unlock.Stat == "Title" or tostring(id):match("_Champion$") then
				return true, 1, 1
			end
		end
		return false, 0, 1
	end
	local career = profile and profile.Underground or {}
	local have = math.floor(career[unlock.Stat] or 0)
	return have >= unlock.Count, math.min(have, unlock.Count), unlock.Count
end

function UGCosmetics.Unlocked(def, profile): boolean
	return (UGCosmetics.Progress(def, profile))
end

-- The entrance / victory pose `profile` has chosen, if they still have it (else the default).
function UGCosmetics.IntroFor(profile)
	local id = profile and profile.Underground and profile.Underground.Intro
	local def = id and UGCosmetics.IntroById[id]
	return (def and UGCosmetics.Unlocked(def, profile)) and def or UGCosmetics.IntroById[UGCosmetics.DefaultIntro]
end

function UGCosmetics.VictoryFor(profile)
	local id = profile and profile.Underground and profile.Underground.Victory
	local def = id and UGCosmetics.VictoryById[id]
	return (def and UGCosmetics.Unlocked(def, profile)) and def or UGCosmetics.VictoryById[UGCosmetics.DefaultVictory]
end

return UGCosmetics
