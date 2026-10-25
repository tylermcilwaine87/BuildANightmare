--[[
	PlayerDataService  (ModuleScript)
	Location: ServerScriptService/Server/Services/PlayerDataService

	Owns every player's profile. The authoritative copy lives ONLY on the server.

	PERSISTENCE (Phase 2)
	  * DataStoreService, one key per player ("Player_<UserId>").
	  * Every read/write uses UpdateAsync, never SetAsync.
	  * SESSION LOCKING: the profile stores { JobId, Time } of the server using it.
	    - Load waits while another live server holds the lock (e.g. a fast rejoin), and
	      takes over a lock older than Config.Data.SessionLockTimeout (crashed server).
	    - Saves are refused if another server owns the lock, so a stale server can never
	      overwrite newer data.
	  * Retries with exponential backoff on every DataStore call.
	  * Autosave every Config.Data.AutosaveInterval seconds, save + release on leave,
	    and save everything in game:BindToClose on shutdown.
	  * SCHEMA VERSIONING: Migrate() upgrades old profiles step by step.
	  * VALIDATION: loaded data is type-checked and repaired. Unknown part ids are KEPT
	    in the inventory (never deleted because a definition changed), just not shown.
	  * If loading fails on a live server, the player is kicked with a friendly message.
	    A blank profile is NEVER substituted, because it would overwrite their real save.
	  * In Studio without API access, a temporary in-memory profile is used and nothing
	    is written (Output explains how to enable saving).

	Public API: Get(player), WaitFor(player, timeout), Snapshot(player), SaveNow(player),
	            IsPersistent(player)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local BuildValidator = require(Shared:WaitForChild("BuildValidator"))
local Util = require(Shared:WaitForChild("Util"))
local LevelUnlocks = require(Shared:WaitForChild("LevelUnlocks"))
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local MeleeDefinitions = require(Shared:WaitForChild("MeleeDefinitions"))
local SettingsDefinitions = require(Shared:WaitForChild("SettingsDefinitions"))

local MonetizationDefinitions = require(Shared:WaitForChild("MonetizationDefinitions"))
local NightmareCombat = require(Shared:WaitForChild("NightmareCombatDefinitions"))

local PlayerDataService = {}
PlayerDataService.SCHEMA_VERSION = 11

-- Extra fields for Snapshot() from services that load later (MonetizationService sets it:
-- owned passes / perks for the SHOP and the Workshop's build slots).
PlayerDataService.SnapshotExtras = nil :: ((Player) -> { [string]: any })?

local PURCHASE_LOG_SIZE = 60 -- receipts remembered (a re-sent receipt is never granted twice)

type Session = {
	Data: any,
	Persistent: boolean,
	Loaded: boolean,
	Saving: boolean,
	LastSave: number,
	Released: boolean?, -- final save started (player leaving / server closing)
	ReleaseOk: boolean?, -- that final save was written
}

local sessions: { [Player]: Session } = {}
local store = nil
local storeError = nil
local shuttingDown = false

local DATA = Config.Data

------------------------------------------------------------------------------------------
-- Defaults, migration & validation
------------------------------------------------------------------------------------------
-- The starter build for slot `index` (slots past the starter list copy the first one).
function PlayerDataService.DefaultBuild(index: number)
	local template = Config.StarterBuilds[index] or Config.StarterBuilds[1]
	local build = BuildValidator.Sanitize(template)
	build.Name = Config.StarterBuilds[index] and template.Name or ("Nightmare %d"):format(index)
	return build
end

local function defaultBuilds()
	local builds = {}
	for index = 1, Config.Builds.SlotCount do
		builds[index] = PlayerDataService.DefaultBuild(index)
	end
	return builds
end

local function makeDefaultProfile()
	local inventory = table.clone(Config.StarterInventory)
	if Config.Dev.GrantAllPartsInStudio and RunService:IsStudio() then
		for id, def in PartDefinitions.ById do
			if def.Equippable then
				inventory[id] = math.max(inventory[id] or 0, 2)
			end
		end
	end

	local discovered = {}
	for id in inventory do
		discovered[id] = true
	end

	local tutorial = { Step = 1, Done = false }
	if Config.Dev.SkipTutorialInStudio and RunService:IsStudio() then
		tutorial = { Step = 99, Done = true }
	end

	return {
		Version = PlayerDataService.SCHEMA_VERSION,
		Inventory = inventory,
		Discovered = discovered,
		Builds = defaultBuilds(),
		ActiveBuild = 1,
		Level = 1,
		XP = 0,
		Coins = 0,
		Essence = 0,
		Pity = { Legendary = 0 },
		Bosses = {},
		Tutorial = tutorial,
		Stats = { BossWins = 0 },
		ArenaTokens = 0,
		PvP = { Wins = 0, Losses = 0, Draws = 0 },
		Settings = { AllowDuels = true },
		Mutations = {}, -- { [partId] = { [mutationId] = count } } (also counted in Inventory)
		MutationBook = {}, -- { [mutationId] = { Found = n, Parts = { [partId] = true } } }
		-- { Daily/Weekly = { Key, List = { { Id, Progress, Done } } } } (ChallengeService)
		Challenges = {},
		Ranked = { Rating = 1000, Peak = 1000, Wins = 0, Losses = 0, Draws = 0, Games = 0 }, -- RankDefinitions
		Showcase = { Likes = 0 }, -- likes your showcased Nightmares have received
		LikesGiven = { Day = "", To = {} }, -- who you liked today (one like per player per day)
		Relics = {}, -- { [relicId] = true } hidden relics found along the routes (WorldDefinitions)
		Loadout = { "Magnet" }, -- weapons taken into a fight (MeleeDefinitions, max LoadoutSlots)
		Combos = {}, -- { [comboId] = true } signature combos discovered (MeleeDefinitions.Combos)
		Runs = { Charge = true }, -- { [runId] = true } run styles owned (MeleeDefinitions.Runs)
		RunStyle = "Charge",
		-- The Nightmare Gym (GymService): lifetime training seconds, rewards collected, best
		-- tier ever (GymDefinitions.TierOrder rank), titles earned, boosts { [id] = expires os.time }
		Gym = { TotalTime = 0, Rewards = 0, Best = 0, Titles = {}, Boosts = {}, ShiftFrom = 0 },
		-- The SHOP (MonetizationService). Purchases.Log = { [receipt PurchaseId] = os.time }
		-- (the newest PURCHASE_LOG_SIZE), Robux = lifetime Robux spent. Owned = what passes
		-- have been granted ({ ["Pass:<key>"] = true }, for one-time grants). Titles = shop
		-- titles ({ [MonetizationDefinitions.Titles id] = true }).
		Purchases = { Log = {}, Robux = 0, Count = 0 },
		Owned = {},
		Titles = {},
		-- How the Nightmare fights (NightmareCombatDefinitions): personality ("Auto" = from its
		-- body) and mode; Mastery = { [Moveset action] = times it landed one in a fight }
		NightmareStyle = { Personality = "Auto", Mode = "Balanced" },
		ComboMastery = {},
		CreatedAt = os.time(),
	}
end

-- Each step upgrades exactly one version.
local MIGRATIONS = {
	[1] = function(data)
		-- v1 (Phase 1) had only Inventory/Builds/ActiveBuild.
		data.Level = data.Level or 1
		data.XP = data.XP or 0
		data.Coins = data.Coins or 0
		data.Essence = data.Essence or 0
		data.Pity = data.Pity or { Legendary = 0 }
		data.Bosses = data.Bosses or {}
		-- Existing players skip the tutorial.
		data.Tutorial = data.Tutorial or { Step = 99, Done = true }
		data.Stats = data.Stats or { BossWins = 0 }
		data.Discovered = data.Discovered or {}
		for id in data.Inventory or {} do
			data.Discovered[id] = true
		end
		data.Version = 2
		return data
	end,
	[2] = function(data)
		-- v3 (Phase 3): everyone gets the new Quadruped starter legs.
		data.Inventory = data.Inventory or {}
		data.Discovered = data.Discovered or {}
		if (data.Inventory.MangyHoundLegs or 0) < 1 then
			data.Inventory.MangyHoundLegs = 1
		end
		data.Discovered.MangyHoundLegs = true
		data.Version = 3
		return data
	end,
	[3] = function(data)
		-- v4 (Phase 4): PvP stats, Arena Tokens, settings.
		data.ArenaTokens = data.ArenaTokens or 0
		data.PvP = data.PvP or { Wins = 0, Losses = 0, Draws = 0 }
		data.Settings = data.Settings or { AllowDuels = true }
		data.Version = 4
		return data
	end,
	[4] = function(data)
		-- v5 (Phase 5): boss wins are tracked per difficulty. A BestTime was only ever
		-- recorded for Normal (never Tutorial) victories, so it proves a Normal win and
		-- keeps Hard unlocked for players who already beat the boss.
		for _, record in data.Bosses or {} do
			if type(record) == "table" and record.Modes == nil and record.BestTime then
				record.Modes = { Normal = { Wins = math.max(1, (record.Wins or 1) - 1), BestTime = record.BestTime } }
			end
		end
		data.Version = 5
		return data
	end,
	[5] = function(data)
		-- v6 (Phase 5): mutated parts and the Mutation Book.
		data.Mutations = data.Mutations or {}
		data.MutationBook = data.MutationBook or {}
		data.Version = 6
		return data
	end,
	[6] = function(data)
		-- v7 (Phase 5): daily / weekly challenges.
		data.Challenges = data.Challenges or {}
		data.Version = 7
		return data
	end,
	[7] = function(data)
		-- v8 (Phase 6): ranked PvP rating.
		data.Ranked = data.Ranked or { Rating = 1000, Peak = 1000, Wins = 0, Losses = 0, Draws = 0, Games = 0 }
		data.Version = 8
		return data
	end,
	[8] = function(data)
		-- v9 (Phase 6): the Nightmare Showcase (likes).
		data.Showcase = data.Showcase or { Likes = 0 }
		data.LikesGiven = data.LikesGiven or { Day = "", To = {} }
		data.Version = 9
		return data
	end,
	[9] = function(data)
		-- v10 (map rebuild): relics found along the boss routes.
		data.Relics = data.Relics or {}
		data.Version = 10
		return data
	end,
	[10] = function(data)
		-- v11 (the SHOP): purchase log, granted passes, shop titles (validate fills them in).
		data.Version = 11
		return data
	end,
}

local function migrate(data)
	data.Version = data.Version or 1
	while data.Version < PlayerDataService.SCHEMA_VERSION do
		local step = MIGRATIONS[data.Version]
		if not step then
			error("No migration from profile version " .. tostring(data.Version))
		end
		data = step(data)
	end
	return data
end

local function isNonNegativeInteger(x)
	return Util.IsFiniteNumber(x) and x >= 0 and x % 1 == 0
end

-- Repairs anything malformed without discarding legitimate items.
local function validate(data)
	local default = makeDefaultProfile()
	for key, value in default do
		if type(data[key]) ~= type(value) then
			data[key] = value
		end
	end

	for id, count in data.Inventory do
		if type(id) ~= "string" or not isNonNegativeInteger(count) then
			data.Inventory[id] = nil
		end
	end
	for _, key in { "Level", "XP", "Coins", "Essence", "ArenaTokens" } do
		if not isNonNegativeInteger(data[key]) then
			data[key] = default[key]
		end
	end
	data.Level = math.clamp(data.Level, 1, Config.Progression.MaxLevel)

	-- Settings: keep AllowDuels; drop any other key that isn't a valid setting.
	for key, value in data.Settings do
		if key ~= "AllowDuels" and SettingsDefinitions.Sanitize(key, value) == nil then
			data.Settings[key] = nil
		end
	end

	for id, found in data.Relics do
		if type(id) ~= "string" or found ~= true then
			data.Relics[id] = nil
		end
	end

	data.Loadout = MeleeDefinitions.CleanLoadout(data.Loadout)
	for id, value in data.Combos do
		if type(id) ~= "string" or value ~= true then
			data.Combos[id] = nil
		end
	end
	for id, value in data.Runs do
		if not MeleeDefinitions.RunsById[id] or value ~= true then
			data.Runs[id] = nil
		end
	end
	data.Runs.Charge = true
	if not data.Runs[data.RunStyle] then
		data.RunStyle = "Charge"
	end

	if not isNonNegativeInteger(data.Showcase.Likes) then
		data.Showcase.Likes = 0
	end
	if type(data.LikesGiven.Day) ~= "string" or type(data.LikesGiven.To) ~= "table" then
		data.LikesGiven = { Day = "", To = {} }
	end

	-- Gym: numbers stay whole and non-negative, titles / boosts only known ids.
	local gym = data.Gym
	for _, key in { "TotalTime", "Rewards", "Best" } do
		if not isNonNegativeInteger(gym[key]) then
			gym[key] = 0
		end
	end
	gym.Titles = type(gym.Titles) == "table" and gym.Titles or {}
	gym.Boosts = type(gym.Boosts) == "table" and gym.Boosts or {}
	for id, value in gym.Titles do
		if not GymDefinitions.Titles[id] or value ~= true then
			gym.Titles[id] = nil
		end
	end
	for id, expires in gym.Boosts do
		if not GymDefinitions.Boosts[id] or type(expires) ~= "number" or expires < os.time() then
			gym.Boosts[id] = nil
		end
	end
	if not isNonNegativeInteger(gym.ShiftFrom) then
		gym.ShiftFrom = 0
	end

	-- Shop: the receipt log (ids are strings, times whole numbers), granted passes, titles.
	local purchases = data.Purchases
	purchases.Log = type(purchases.Log) == "table" and purchases.Log or {}
	for _, key in { "Robux", "Count" } do
		if not isNonNegativeInteger(purchases[key]) then
			purchases[key] = 0
		end
	end
	for id, at in purchases.Log do
		if type(id) ~= "string" or not isNonNegativeInteger(at) then
			purchases.Log[id] = nil
		end
	end
	for key, value in data.Owned do
		if type(key) ~= "string" or value ~= true then
			data.Owned[key] = nil
		end
	end
	for id, value in data.Titles do
		if not MonetizationDefinitions.Titles[id] or value ~= true then
			data.Titles[id] = nil
		end
	end
	-- Nightmare fighting style: known values only
	local style = data.NightmareStyle
	if style.Personality ~= "Auto" and not NightmareCombat.Personalities[style.Personality] then
		style.Personality = "Auto"
	end
	if not NightmareCombat.Modes[style.Mode] then
		style.Mode = "Balanced"
	end
	for id, count in data.ComboMastery do
		if type(id) ~= "string" or not isNonNegativeInteger(count) then
			data.ComboMastery[id] = nil
		end
	end

	-- Ranked record: whole, non-negative numbers only.
	for _, key in { "Rating", "Peak", "Wins", "Losses", "Draws", "Games" } do
		if not isNonNegativeInteger(data.Ranked[key]) then
			data.Ranked[key] = default.Ranked[key]
		end
	end

	-- Mutated copies: drop malformed entries and never claim more mutated copies than
	-- the part's total count (keeps Inventory the single source of "how many you own").
	for partId, byMutation in data.Mutations do
		if type(partId) ~= "string" or type(byMutation) ~= "table" then
			data.Mutations[partId] = nil
			continue
		end
		local remaining = data.Inventory[partId] or 0
		for mutationId, count in byMutation do
			if type(mutationId) ~= "string" or not isNonNegativeInteger(count) or count == 0 then
				byMutation[mutationId] = nil
			else
				byMutation[mutationId] = math.min(count, remaining)
				remaining -= byMutation[mutationId]
			end
		end
	end
	if not isNonNegativeInteger(data.Pity.Legendary) then
		data.Pity.Legendary = 0
	end

	-- SlotCount builds, or up to MaxSlotCount (the +3 Build Slots pass grows the list;
	-- extra slots are kept even if the pass goes away, so nothing is ever lost)
	local slots = math.clamp(#data.Builds, Config.Builds.SlotCount, Config.Builds.MaxSlotCount)
	for index = 1, slots do
		local fallback = default.Builds[index] or PlayerDataService.DefaultBuild(index)
		local build = BuildValidator.Sanitize(data.Builds[index])
		if not build or not build.Parts.Core or not build.Parts.Head or not build.Parts.Legs then
			build = fallback
		end
		if build.Name == "" then
			build.Name = fallback.Name
		end
		data.Builds[index] = build
	end
	for index = #data.Builds, slots + 1, -1 do
		data.Builds[index] = nil
	end
	if not isNonNegativeInteger(data.ActiveBuild) or data.ActiveBuild < 1 or data.ActiveBuild > #data.Builds then
		data.ActiveBuild = 1
	end
	return data
end

------------------------------------------------------------------------------------------
-- DataStore helpers
------------------------------------------------------------------------------------------
local function keyFor(player: Player): string
	return DATA.KeyPrefix .. player.UserId
end

local function withRetries(label: string, fn)
	local delaySeconds = 1
	local lastError
	for attempt = 1, DATA.WriteRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(("[PlayerData] %s failed (attempt %d/%d): %s"):format(label, attempt, DATA.WriteRetries, tostring(result)))
		-- Studio without API access fails with 403 every time: don't make the tester wait.
		if RunService:IsStudio() and string.find(tostring(result), "403") then
			break
		end
		if attempt < DATA.WriteRetries then
			task.wait(delaySeconds)
			delaySeconds *= 2
		end
	end
	return false, lastError
end

-- Returns: data | nil, reason ("locked" | "error")
local function loadFromStore(player: Player)
	local key = keyFor(player)
	for _ = 1, DATA.LoadRetries do
		local lockedElsewhere = false
		local loaded = nil
		local ok, err = withRetries("Load " .. key, function()
			store:UpdateAsync(key, function(old)
				lockedElsewhere = false
				if old and old.SessionLock and old.SessionLock.JobId ~= game.JobId and os.time() - (old.SessionLock.Time or 0) < DATA.SessionLockTimeout then
					lockedElsewhere = true
					return nil -- cancel the write; another server is still using this profile
				end
				local data = old and validate(migrate(old)) or makeDefaultProfile()
				data.SessionLock = { JobId = game.JobId, Time = os.time() }
				loaded = data
				return data
			end)
		end)
		if not ok then
			return nil, "error", err
		end
		if not lockedElsewhere and loaded then
			loaded.SessionLock = nil
			return loaded
		end
		if not player.Parent then
			return nil, "left"
		end
		task.wait(DATA.LoadRetryDelay)
	end
	return nil, "locked"
end

local function writeToStore(player: Player, session: Session, release: boolean): boolean
	if not session.Persistent or not session.Loaded then
		return true
	end
	if not release and (session.Saving or session.Released) then
		return false -- (a released session must never be re-locked by a late autosave)
	end
	session.Saving = true
	local snapshot = Util.DeepCopy(session.Data)
	local key = keyFor(player)
	local refused = false

	local ok = withRetries("Save " .. key, function()
		store:UpdateAsync(key, function(old)
			refused = false
			if old and old.SessionLock and old.SessionLock.JobId ~= game.JobId then
				refused = true -- another server took over; never overwrite its newer data
				return nil
			end
			snapshot.SessionLock = (not release) and { JobId = game.JobId, Time = os.time() } or nil
			return snapshot
		end)
	end)

	session.Saving = false
	if refused then
		warn(("[PlayerData] Save of %s refused: session owned by another server."):format(key))
		return false
	end
	if ok then
		session.LastSave = os.clock()
	end
	return ok
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	if sessions[player] then
		return
	end

	if not store then
		if RunService:IsStudio() then
			warn("[PlayerData] DataStores unavailable in Studio (" .. tostring(storeError) .. "). Using a TEMPORARY profile. To test saving: publish the place, then Home > Game Settings > Security > enable 'Enable Studio Access to API Services'.")
			sessions[player] = { Data = makeDefaultProfile(), Persistent = false, Loaded = true, Saving = false, LastSave = os.clock() }
		else
			player:Kick("Nightmare data servers are unavailable right now. Please rejoin in a minute.")
		end
		return
	end

	local data, reason, err = loadFromStore(player)
	if not player.Parent then
		return
	end
	if not data then
		if RunService:IsStudio() then
			warn(("[PlayerData] Load failed in Studio (%s %s). Using a TEMPORARY profile; nothing will be saved."):format(tostring(reason), tostring(err or "")))
			sessions[player] = { Data = makeDefaultProfile(), Persistent = false, Loaded = true, Saving = false, LastSave = os.clock() }
			return
		end
		if reason == "locked" then
			player:Kick("Your Nightmares are still being saved on another server. Please rejoin in a minute.")
		else
			player:Kick("Couldn't load your Nightmares (Roblox data error). Your save is safe. Please rejoin.")
		end
		return
	end

	-- Studio test players (Player1, Player2... have UserId <= 0) may have a saved profile
	-- from an earlier test that's stuck mid-tutorial. Real accounts are left alone.
	if Config.Dev.SkipTutorialInStudio and RunService:IsStudio() and player.UserId <= 0 then
		data.Tutorial = { Step = 99, Done = true }
	end

	sessions[player] = { Data = data, Persistent = true, Loaded = true, Saving = false, LastSave = os.clock() }
end

-- Final save when a player leaves. Order matters:
--  1. wait a moment: other services' PlayerRemoving handlers still change this profile
--     (a forfeited duel records the loss / rating change, leaderboards read it). Saving
--     first would lose those changes, e.g. quitting a ranked match would dodge the loss.
--  2. block new autosaves and wait for one already in flight; otherwise it could land
--     AFTER the release and re-lock the profile, so the player couldn't rejoin.
--  3. release-save.
local RELEASE_DELAY = 0.5
local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if not session or session.Released then
		return
	end
	task.wait(RELEASE_DELAY)
	if session.Released then
		return -- BindToClose took over the final save while we waited
	end
	session.Released = true
	local deadline = os.clock() + 10
	while session.Saving and os.clock() < deadline do
		task.wait(0.1)
	end
	session.ReleaseOk = writeToStore(player, session, true)
	if sessions[player] == session then
		sessions[player] = nil
	end
end

function PlayerDataService:Init()
	local ok, result = pcall(function()
		local name = DATA.StoreName .. (RunService:IsStudio() and (DATA.StudioStoreSuffix or "") or "")
		return DataStoreService:GetDataStore(name)
	end)
	if ok then
		store = result
	else
		storeError = result
	end
end

function PlayerDataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Autosave loop.
	task.spawn(function()
		while not shuttingDown do
			task.wait(DATA.AutosaveInterval)
			for player, session in sessions do
				if os.clock() - session.LastSave >= DATA.AutosaveInterval * 0.9 then
					task.spawn(writeToStore, player, session, false)
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player, session in sessions do
			pending += 1
			if session.Released then
				-- onPlayerRemoving is already releasing it: wait for that save to finish
				task.spawn(function()
					local waitUntil = os.clock() + 25
					while sessions[player] == session and os.clock() < waitUntil do
						task.wait(0.2)
					end
					pending -= 1
				end)
				continue
			end
			session.Released = true
			task.spawn(function()
				local deadline = os.clock() + 5
				while session.Saving and os.clock() < deadline do
					task.wait(0.1) -- let an in-flight autosave finish first
				end
				session.ReleaseOk = writeToStore(player, session, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

------------------------------------------------------------------------------------------
-- API
------------------------------------------------------------------------------------------
function PlayerDataService:Get(player: Player)
	local session = sessions[player]
	return session and session.Data or nil
end

function PlayerDataService:IsPersistent(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.Persistent
end

-- Yields until the profile is loaded (or the player leaves / times out).
function PlayerDataService:WaitFor(player: Player, timeout: number?)
	local deadline = os.clock() + (timeout or 60)
	while not sessions[player] and player.Parent and os.clock() < deadline do
		task.wait(0.1)
	end
	return self:Get(player)
end

-- Saves immediately (used right after rewards so loot is committed promptly).
function PlayerDataService:SaveNow(player: Player)
	local session = sessions[player]
	if session then
		task.spawn(writeToStore, player, session, false)
	end
end

-- A copy of everything the client needs to render menus. Never hand out the real table.
function PlayerDataService:Snapshot(player: Player)
	local session = sessions[player]
	if not session then
		return nil
	end
	local data = session.Data
	return {
		Inventory = Util.DeepCopy(data.Inventory),
		Discovered = Util.DeepCopy(data.Discovered),
		Builds = Util.DeepCopy(data.Builds),
		ActiveBuild = data.ActiveBuild,
		PowerBudget = LevelUnlocks.PvEBudget(data.Level),
		Persistence = session.Persistent,
		Level = data.Level,
		XP = data.XP,
		XPToNext = Config.Progression.XPForLevel(data.Level),
		Coins = data.Coins,
		Essence = data.Essence,
		Pity = Util.DeepCopy(data.Pity),
		Bosses = Util.DeepCopy(data.Bosses),
		Tutorial = Util.DeepCopy(data.Tutorial),
		ArenaTokens = data.ArenaTokens,
		PvP = Util.DeepCopy(data.PvP),
		Settings = Util.DeepCopy(data.Settings),
		Mutations = Util.DeepCopy(data.Mutations),
		MutationBook = Util.DeepCopy(data.MutationBook),
		Challenges = Util.DeepCopy(data.Challenges),
		Ranked = Util.DeepCopy(data.Ranked),
		Showcase = Util.DeepCopy(data.Showcase),
		Relics = Util.DeepCopy(data.Relics),
		Loadout = Util.DeepCopy(data.Loadout),
		Combos = Util.DeepCopy(data.Combos),
		Runs = Util.DeepCopy(data.Runs),
		RunStyle = data.RunStyle,
		Gym = Util.DeepCopy(data.Gym),
		Owned = Util.DeepCopy(data.Owned),
		Titles = Util.DeepCopy(data.Titles),
		NightmareStyle = Util.DeepCopy(data.NightmareStyle),
		ComboMastery = Util.DeepCopy(data.ComboMastery),
		Shop = PlayerDataService.SnapshotExtras and PlayerDataService.SnapshotExtras(player) or nil,
	}
end

-- Saves now and WAITS for the result (true = written, or nothing to write in a Studio
-- test session). Used before telling Roblox a purchase was granted.
function PlayerDataService:SaveAndWait(player: Player): boolean
	local session = sessions[player]
	if not session then
		return false
	end
	if not session.Persistent then
		return true
	end
	local deadline = os.clock() + 15
	while session.Saving and os.clock() < deadline do
		task.wait(0.1) -- an autosave is in flight: let it land, then write again
	end
	if session.Released then
		-- the final (release) save is already under way and includes this change
		while sessions[player] == session and os.clock() < deadline do
			task.wait(0.1)
		end
		return sessions[player] ~= session and session.ReleaseOk == true
	end
	return writeToStore(player, session, false)
end

PlayerDataService.PurchaseLogSize = PURCHASE_LOG_SIZE

return PlayerDataService
