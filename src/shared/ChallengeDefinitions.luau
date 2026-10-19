--[[
	ChallengeDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/ChallengeDefinitions

	Daily and weekly CHALLENGES (Phase 5). Everyone gets the same set for a given
	day / week: the set is picked from the pool with a seed made from the period key, so
	it needs no shared storage. Days reset at 00:00 UTC, weeks on Monday 00:00 UTC.

	Progress comes from server events (ChallengeService:Notify). Rewards are granted
	automatically when a challenge completes. PvP is optional, so no challenge needs it.

	Event names: BossWin (data: BossId, Mode), EnemyDefeated, AbilityUsed, UltimateUsed,
	Possessed, Crafted, Dismantled (amount = parts dismantled)
]]

local ChallengeDefinitions = {}

ChallengeDefinitions.Periods = {
	Daily = { Count = 3, Rewards = { XP = 60, Coins = 80, Essence = 15 } },
	Weekly = { Count = 2, Rewards = { XP = 250, Coins = 300, Essence = 60 } },
}

-- Match(data) -> bool filters which events count (nil = every event of that name).
ChallengeDefinitions.Pool = {
	Daily = {
		{ Id = "DailyBoss", Text = "Defeat any boss", Event = "BossWin", Target = 1 },
		{ Id = "DailyScraplings", Text = "Defeat 15 Scraplings in the Training Arena", Event = "EnemyDefeated", Target = 15 },
		{ Id = "DailyAbilities", Text = "Use 20 Nightmare abilities (Q / E)", Event = "AbilityUsed", Target = 20 },
		{ Id = "DailyUltimate", Text = "Unleash your Ultimate 2 times", Event = "UltimateUsed", Target = 2 },
		{ Id = "DailyPossess", Text = "Possess your Nightmare 3 times", Event = "Possessed", Target = 3 },
		{ Id = "DailyDismantle", Text = "Dismantle 3 spare parts at the Forge", Event = "Dismantled", Target = 3 },
		{ Id = "DailyTitan", Text = "Defeat the Scrap Titan", Event = "BossWin", Target = 1, Match = function(data)
			return data and data.BossId == "ScrapTitan"
		end },
	},
	Weekly = {
		{ Id = "WeeklyBosses", Text = "Defeat 8 bosses", Event = "BossWin", Target = 8 },
		{ Id = "WeeklyHard", Text = "Defeat 3 bosses on Hard or Nightmare", Event = "BossWin", Target = 3, Match = function(data)
			return data and (data.Mode == "Hard" or data.Mode == "Nightmare")
		end },
		{ Id = "WeeklyWarden", Text = "Defeat the Mirror Warden 2 times", Event = "BossWin", Target = 2, Match = function(data)
			return data and data.BossId == "MirrorWarden"
		end },
		{ Id = "WeeklyStorm", Text = "Defeat the Storm Beast 2 times", Event = "BossWin", Target = 2, Match = function(data)
			return data and data.BossId == "StormBeast"
		end },
		{ Id = "WeeklyMaw", Text = "Defeat the Abyssal Maw", Event = "BossWin", Target = 1, Match = function(data)
			return data and data.BossId == "AbyssalMaw"
		end },
		{ Id = "WeeklyScraplings", Text = "Defeat 75 Scraplings", Event = "EnemyDefeated", Target = 75 },
		{ Id = "WeeklyCraft", Text = "Craft a part at the Crafting Forge", Event = "Crafted", Target = 1 },
		{ Id = "WeeklyUltimate", Text = "Unleash your Ultimate 10 times", Event = "UltimateUsed", Target = 10 },
	},
}

ChallengeDefinitions.ById = {}
for period, pool in ChallengeDefinitions.Pool do
	for _, def in pool do
		def.Period = period
		ChallengeDefinitions.ById[def.Id] = def
	end
end

function ChallengeDefinitions.Get(id)
	return type(id) == "string" and ChallengeDefinitions.ById[id] or nil
end

local DAY = 86400
local WEEK = 7 * DAY
local MONDAY_OFFSET = 3 * DAY -- the Unix epoch (1 Jan 1970) was a Thursday

-- Current period key and the time (Unix seconds) it ends.
function ChallengeDefinitions.PeriodInfo(period: string, now: number): (string, number)
	if period == "Daily" then
		local index = now // DAY
		return ("D%d"):format(index), (index + 1) * DAY
	end
	local index = (now + MONDAY_OFFSET) // WEEK
	return ("W%d"):format(index), (index + 1) * WEEK - MONDAY_OFFSET
end

-- The challenge ids for a period key: same for everyone, different each period.
function ChallengeDefinitions.Pick(period: string, key: string): { string }
	local seed = 0
	for i = 1, #key do
		seed = (seed * 31 + string.byte(key, i)) % 2147483647
	end
	local random = Random.new(seed)
	local ids = {}
	for _, def in ChallengeDefinitions.Pool[period] do
		table.insert(ids, def.Id)
	end
	for i = #ids, 2, -1 do -- shuffle
		local j = random:NextInteger(1, i)
		ids[i], ids[j] = ids[j], ids[i]
	end
	local picked = {}
	for i = 1, math.min(ChallengeDefinitions.Periods[period].Count, #ids) do
		table.insert(picked, ids[i])
	end
	return picked
end

return ChallengeDefinitions
