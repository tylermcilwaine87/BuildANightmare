--[[
	MonetizationService  (ModuleScript)
	Location: ServerScriptService/Server/Services/MonetizationService

	THE SHOP, server side (catalog: Shared/MonetizationDefinitions). The only code that
	grants anything bought with Robux.

	DEVELOPER PRODUCTS (MarketplaceService.ProcessReceipt), safe against every failure:
	  1. no profile yet (still loading / left)          -> NotProcessedYet (Roblox retries)
	  2. receipt already in profile.Purchases.Log        -> PurchaseGranted (never twice)
	  3. grant it, log the receipt, then SAVE AND WAIT    -> PurchaseGranted only once the
	     save is written; if it fails, NotProcessedYet: Roblox re-sends the receipt and
	     step 2 stops a double grant (the grant is still in memory and saves later).
	GAME PASSES: ownership is checked when you join (UserOwnsGamePassAsync) and the moment
	you buy one (PromptGamePassPurchaseFinished). Owning one:
	  * switches on its perks (HasPerk), for as long as you own it
	  * gives its one-time Grants once (recorded in profile.Owned["Pass:<key>"])
	  * tops its exclusive Parts back up to their count on every join
	  * unlocks its exclusive Weapons (profile.Owned["Weapon:<id>"], MeleeDefinitions)
	  Bundles count as every pass they include.

	STUDIO: entries with Id = 0 (not created on the dashboard yet) are sold as free TEST
	purchases through "DevBuy", so the whole shop can be tried; test passes are kept in
	profile.Owned["StudioPass:<key>"] (Studio saves are separate from the live game).
	Nothing here works for Id = 0 on a live server.

	Perks read by other services:
	  CoinMultiplier(player), XPMultiplier(player)   ProgressionService (coins / XP earned)
	  GymExtras(player)                              GymService (luck / speed on top of boosts)
	  HasPerk(player, "NightShift" | ...)            GymService, the Workshop's build slots
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local Monetization = require(Shared:WaitForChild("MonetizationDefinitions"))
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))

local MonetizationService = {}

local IS_STUDIO = RunService:IsStudio()
local PERK = Monetization.PerkValues

local passes = {} -- [Player] = { [passKey] = true } (bundles expanded)
local restricted = {} -- [Player] = true when paid random items are restricted for them
local serverLuck = { Until = 0, By = "" } -- os.time it ends, who bought the last one

function MonetizationService:Init(services)
	self.Services = services
	self.Event = Net.Get("ShopEvent")
	self.UIState = Net.Get("UIStateUpdate")
	services.PlayerDataService.SnapshotExtras = function(player)
		return self:Summary(player)
	end
end

------------------------------------------------------------------------------------------
-- Ownership & perks
------------------------------------------------------------------------------------------
function MonetizationService:OwnsPass(player: Player, key: string): boolean
	return passes[player] ~= nil and passes[player][key] == true
end

function MonetizationService:HasPerk(player: Player, perk: string): boolean
	for key in passes[player] or {} do
		local def = Monetization.Passes[key]
		if def and def.Perks and table.find(def.Perks, perk) then
			return true
		end
	end
	return false
end

function MonetizationService:IsPremium(player: Player): boolean
	return player.MembershipType == Enum.MembershipType.Premium
end

-- x coins EARNED (never applied to bought coins).
function MonetizationService:CoinMultiplier(player: Player): number
	local m = 1
	if self:HasPerk(player, "DoubleCoins") then
		m *= PERK.DoubleCoins
	end
	if self:HasPerk(player, "VIP") then
		m *= PERK.VIPCoins
	end
	if self:IsPremium(player) then
		m *= PERK.PremiumCoins
	end
	return m
end

function MonetizationService:XPMultiplier(player: Player): number
	return self:HasPerk(player, "VIP") and PERK.VIPCoins or 1
end

function MonetizationService:ServerLuckActive(): boolean
	return serverLuck.Until > os.time()
end

-- What the gym multiplies on top of your boosts (GymDefinitions.Multipliers `extra`).
-- `offline` (Night Shift): only your own passes; a Server Luck is for whoever is here.
function MonetizationService:GymExtras(player: Player, offline: boolean?)
	local luck, speed = 1, 1
	if self:HasPerk(player, "LuckyTrainer") then
		luck *= PERK.LuckyTrainer
	end
	if self:ServerLuckActive() and not offline then
		luck *= PERK.ServerLuck
	end
	if self:HasPerk(player, "FastTrainer") then
		speed *= PERK.FastTrainer
	end
	return { Luck = luck, Speed = speed, MaxLuck = Monetization.MaxLuck, MaxSpeed = Monetization.MaxSpeed }
end

function MonetizationService:IsRestricted(player: Player): boolean
	return restricted[player] == true
end

-- Sent with the profile snapshot (the SHOP and Workshop read it).
function MonetizationService:Summary(player: Player)
	local perks = {}
	for key in passes[player] or {} do
		for _, perk in Monetization.Passes[key].Perks or {} do
			perks[perk] = true
		end
	end
	return {
		Passes = Util.DeepCopy(passes[player] or {}),
		Perks = perks,
		Premium = self:IsPremium(player),
		Restricted = self:IsRestricted(player),
		ServerLuckUntil = serverLuck.Until,
		ServerLuckBy = serverLuck.By,
	}
end

------------------------------------------------------------------------------------------
-- Granting
------------------------------------------------------------------------------------------
local function addBoosts(profile, boosts)
	local now = os.time()
	for boostId, seconds in boosts or {} do
		if GymDefinitions.Boosts[boostId] then
			profile.Gym.Boosts[boostId] = math.max(now, profile.Gym.Boosts[boostId] or 0) + seconds
		end
	end
end

-- Lines for the "you got" popup.
local function grantLines(def): { string }
	local lines = {}
	if def.Coins then
		table.insert(lines, ("+%s coins"):format(Util.FormatNumber(def.Coins)))
	end
	if def.Essence then
		table.insert(lines, ("+%d Essence"):format(def.Essence))
	end
	return lines
end

-- A pass you own: perks are live already; give its one-time grants once, top its parts
-- up, and record its weapons. Returns true if anything in the profile changed.
function MonetizationService:ApplyPass(player: Player, key: string): boolean
	local def = Monetization.Passes[key]
	local profile = self.Services.PlayerDataService:Get(player)
	if not def or not profile then
		return false
	end
	local changed = false
	local mark = "Pass:" .. key
	if not profile.Owned[mark] then
		profile.Owned[mark] = true
		changed = true
		local grants = def.Grants
		if grants then
			profile.Coins += grants.Coins or 0
			profile.Essence += grants.Essence or 0
			if grants.Title and Monetization.Titles[grants.Title] then
				profile.Titles[grants.Title] = true
			end
			addBoosts(profile, grants.Boosts)
		end
	end
	for partId, count in def.Parts or {} do
		local have = profile.Inventory[partId] or 0
		if have < count then
			self.Services.InventoryService:Grant(player, partId, count - have)
			changed = true
		end
	end
	for _, weaponId in def.Weapons or {} do
		if not profile.Owned["Weapon:" .. weaponId] then
			profile.Owned["Weapon:" .. weaponId] = true
			changed = true
		end
	end
	for _, perk in def.Perks or {} do
		if perk == "ExtraBuildSlots" then
			local target = Config.Builds.SlotCount + PERK.ExtraBuildSlots
			while #profile.Builds < math.min(target, Config.Builds.MaxSlotCount) do
				table.insert(profile.Builds, self.Services.PlayerDataService.DefaultBuild(#profile.Builds + 1))
				changed = true
			end
		elseif perk == "VIP" then
			player:SetAttribute("VIP", true) -- (chat tag / gold name on every client)
		end
	end
	return changed
end

-- Marks a pass (and everything a bundle includes) owned and applies it.
function MonetizationService:GivePass(player: Player, key: string)
	passes[player] = passes[player] or {}
	local changed = false
	for _, k in Monetization.Expand(key) do
		passes[player][k] = true
		if self:ApplyPass(player, k) then
			changed = true
		end
	end
	return changed
end

-- Applies a developer product to the profile. Returns the popup lines.
function MonetizationService:ApplyProduct(player: Player, def)
	local profile = self.Services.PlayerDataService:Get(player)
	profile.Coins += def.Coins or 0
	profile.Essence += def.Essence or 0
	addBoosts(profile, def.Boosts)
	local lines = grantLines(def)
	if def.ServerLuck then
		local now = os.time()
		serverLuck.Until = math.max(now, serverLuck.Until) + def.ServerLuck
		serverLuck.By = player.DisplayName
		Workspace:SetAttribute("ServerLuckUntil", serverLuck.Until)
		Workspace:SetAttribute("ServerLuckBy", serverLuck.By)
		for _, other in Players:GetPlayers() do
			self.UIState:FireClient(other, "Toast", { Text = ("🌟 %s started SERVER LUCK: 2x gym luck for everyone (%d min left)!"):format(player.DisplayName, math.ceil((serverLuck.Until - now) / 60)) })
			self.Services.NightmareBuildService:PushState(other)
		end
		table.insert(lines, "2x gym luck for the whole server")
	end
	if def.Boosts then
		for boostId, seconds in def.Boosts do
			local boost = GymDefinitions.Boosts[boostId]
			if boost then
				table.insert(lines, ("%s: +%d min"):format(boost.Name, seconds // 60))
			end
		end
	end
	return lines
end

function MonetizationService:Celebrate(player: Player, def, lines)
	self.Event:FireClient(player, "Granted", {
		Key = def.Key,
		Name = def.Name,
		Icon = def.Icon,
		Lines = lines,
	})
	self.Services.NightmareBuildService:PushState(player)
end

------------------------------------------------------------------------------------------
-- Roblox purchase flows
------------------------------------------------------------------------------------------
function MonetizationService:ProcessReceipt(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- they left: granted on their next join
	end
	local profile = self.Services.PlayerDataService:WaitFor(player, 20)
	if not profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local def = Monetization.ById("Product", receipt.ProductId)
	if not def then
		warn(("[Shop] receipt for unknown product %s"):format(tostring(receipt.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return self:GrantReceipt(player, profile, def, tostring(receipt.PurchaseId), receipt.CurrencySpent or def.Price)
end

-- Steps 2-3 of ProcessReceipt (see the header).
function MonetizationService:GrantReceipt(player: Player, profile, def, purchaseId: string, spent: number)
	if profile.Purchases.Log[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted -- already granted: never twice
	end
	local lines = self:ApplyProduct(player, def)
	profile.Purchases.Log[purchaseId] = os.time()
	profile.Purchases.Robux += spent
	profile.Purchases.Count += 1
	self:TrimLog(profile)
	if not self.Services.PlayerDataService:SaveAndWait(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	self.Services.GameAnalyticsService:Event(player, "Purchase", spent, { def.Key })
	self:Celebrate(player, def, lines)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- STUDIO ONLY (DevBridge): run a product through the real receipt path with a made-up
-- purchase id (send the same id twice: the second must grant nothing).
function MonetizationService:DevReceipt(player: Player, key: string, purchaseId: string)
	local def = IS_STUDIO and Monetization.Products[key]
	local profile = def and self.Services.PlayerDataService:Get(player)
	if not profile then
		return nil
	end
	return self:GrantReceipt(player, profile, def, purchaseId, def.Price).Name
end

-- Keeps the newest PurchaseLogSize receipts.
function MonetizationService:TrimLog(profile)
	local entries = {}
	for id, at in profile.Purchases.Log do
		table.insert(entries, { id, at })
	end
	local keep = self.Services.PlayerDataService.PurchaseLogSize
	if #entries <= keep then
		return
	end
	table.sort(entries, function(a, b)
		return a[2] > b[2]
	end)
	for i = keep + 1, #entries do
		profile.Purchases.Log[entries[i][1]] = nil
	end
end

function MonetizationService:OnPassBought(player: Player, def)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return
	end
	self:GivePass(player, def.Key)
	if profile.Purchases then
		profile.Purchases.Count += 1
		profile.Purchases.Robux += def.Price
	end
	self.Services.PlayerDataService:SaveNow(player)
	self.Services.GameAnalyticsService:Event(player, "Purchase", def.Price, { def.Key })
	local lines = {}
	for _, k in Monetization.Expand(def.Key) do
		local inner = Monetization.Passes[k]
		if k ~= def.Key then
			table.insert(lines, inner.Name)
		end
	end
	local grants = def.Grants
	if grants then
		if grants.Coins then
			table.insert(lines, ("+%d coins"):format(grants.Coins))
		end
		if grants.Essence then
			table.insert(lines, ("+%d Essence"):format(grants.Essence))
		end
		if grants.Title then
			table.insert(lines, ("Title: %s"):format(Monetization.Titles[grants.Title] or grants.Title))
		end
		for boostId, seconds in grants.Boosts or {} do
			local boost = GymDefinitions.Boosts[boostId]
			if boost then
				table.insert(lines, ("%s: %d min"):format(boost.Name, seconds // 60))
			end
		end
	end
	for partId, count in def.Parts or {} do
		local part = PartDefinitions.Get(partId)
		local name = part and part.DisplayName or partId
		if count > 1 or name ~= def.Name then -- (not "Scorpion Tail" twice)
			table.insert(lines, ("%s%s"):format(count > 1 and ("%d x "):format(count) or "", name))
		end
	end
	for _, perk in def.Perks or {} do
		if perk == "ExtraBuildSlots" then
			table.insert(lines, "3 new build slots in the Workshop")
		end
	end
	self:Celebrate(player, def, lines)
end

-- On join: which passes do they own? (live: Roblox; Studio: also the test purchases)
function MonetizationService:LoadPasses(player: Player)
	local profile = self.Services.PlayerDataService:WaitFor(player, 60)
	if not profile or not player.Parent then
		return
	end
	passes[player] = passes[player] or {}
	local owned = {}
	for key, def in Monetization.Passes do
		if def.Id ~= 0 then
			for _ = 1, 3 do
				local ok, has = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, def.Id)
				if ok then
					if has then
						table.insert(owned, key)
					end
					break
				end
				task.wait(1)
			end
		end
		if IS_STUDIO and profile.Owned["StudioPass:" .. key] then
			table.insert(owned, key)
		end
	end
	local changed = false
	for _, key in owned do
		if self:GivePass(player, key) then
			changed = true
		end
	end
	if changed then
		self.Services.PlayerDataService:SaveNow(player)
	end
	self.Services.NightmareBuildService:PushState(player)
	self.Services.GymService:CollectNightShift(player) -- (needs the passes known)
end

function MonetizationService:LoadPolicy(player: Player)
	if IS_STUDIO then
		restricted[player] = Config.Dev.ShopRestrictedInStudio == true
		return
	end
	local ok, info = pcall(PolicyService.GetPolicyInfoForPlayerAsync, PolicyService, player)
	-- (if Roblox can't say, stay on the safe side: treat paid random items as restricted)
	restricted[player] = not ok or info == nil or info.ArePaidRandomItemsRestricted == true
end

------------------------------------------------------------------------------------------
-- Studio test purchases
------------------------------------------------------------------------------------------
function MonetizationService:DevBuy(player: Player, key: string)
	if not IS_STUDIO then
		return { Ok = false, Error = "Not available." }
	end
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return { Ok = false, Error = "Still loading." }
	end
	local pass = Monetization.Passes[key]
	local product = Monetization.Products[key]
	if pass then
		if self:OwnsPass(player, key) then
			return { Ok = false, Error = "You already own " .. pass.Name .. "." }
		end
		profile.Owned["StudioPass:" .. key] = true
		self:OnPassBought(player, pass)
		return { Ok = true }
	elseif product then
		local lines = self:ApplyProduct(player, product)
		profile.Purchases.Count += 1
		self.Services.PlayerDataService:SaveNow(player)
		self:Celebrate(player, product, lines)
		return { Ok = true }
	end
	return { Ok = false, Error = "Unknown item." }
end

-- STUDIO ONLY (DevBridge): forget every test pass, so the shop can be tried again.
function MonetizationService:DevReset(player: Player)
	local profile = IS_STUDIO and self.Services.PlayerDataService:Get(player)
	if not profile then
		return false
	end
	for mark in profile.Owned do
		if mark:sub(1, 11) == "StudioPass:" or mark:sub(1, 5) == "Pass:" or mark:sub(1, 7) == "Weapon:" then
			profile.Owned[mark] = nil
		end
	end
	passes[player] = {}
	player:SetAttribute("VIP", nil)
	self.Services.NightmareBuildService:PushState(player)
	return true
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function MonetizationService:Start()
	MarketplaceService.ProcessReceipt = function(receipt)
		local ok, decision = pcall(self.ProcessReceipt, self, receipt)
		if not ok then
			warn("[Shop] ProcessReceipt failed:", decision)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local def = Monetization.ById("Pass", passId)
		if def and not self:OwnsPass(player, def.Key) then
			self:OnPassBought(player, def)
		end
	end)

	Net.Get("ShopRequest").OnServerInvoke = function(player: Player, action, key)
		if not self.Services.AntiExploitService:Allow(player, "ShopRequest") then
			return { Ok = false, Error = "Slow down." }
		end
		if action == "DevBuy" and type(key) == "string" then
			return self:DevBuy(player, key)
		elseif action == "State" then
			return { Ok = true, Summary = self:Summary(player) }
		end
		return { Ok = false }
	end

	local function onPlayer(player: Player)
		task.spawn(self.LoadPolicy, self, player)
		task.spawn(self.LoadPasses, self, player)
		self.Event:FireClient(player, "ServerLuck", { Until = serverLuck.Until, By = serverLuck.By })
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		passes[player] = nil
		restricted[player] = nil
	end)
	Players.PlayerMembershipChanged:Connect(function(player)
		self.Services.NightmareBuildService:PushState(player)
	end)
end

return MonetizationService
