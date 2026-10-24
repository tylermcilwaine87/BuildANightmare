--[[
	MonetizationDefinitions  (ModuleScript, data only)
	Location: ReplicatedStorage/Shared/MonetizationDefinitions

	EVERYTHING THE SHOP SELLS. MonetizationService (server) is the only thing that grants
	any of it; the SHOP (ShopController) just shows these entries and opens Roblox's own
	purchase prompt.

	HOW TO GO LIVE: create each entry on the Creator Dashboard (game passes under
	Monetization > Passes, developer products under Monetization > Developer Products),
	set its price to Price, then paste its id into Id below. Id = 0 means "not created
	yet": in Studio the SHOP sells it as a free TEST purchase so everything can be tried;
	on a live server it's hidden. Roblox shows the real price from the dashboard; Price
	here is only the fallback label.

	FAIR PLAY (why the exclusives aren't pay-to-win): every exclusive part has a normal
	PowerCost for what it does, so it fits the same power budget as anything you can
	earn (ranked PvP is always capped at 100). They're DIFFERENT, not stronger: their
	own looks, their own special attack and animation. Exclusive weapons follow the same
	charge / recharge rules as the free ones. Paid boosts only touch the AFK gym.

	PAID RANDOM ITEMS: luck boosts make the gym's (free) reward rolls luckier. Where
	Roblox restricts paid random items (PolicyService ArePaidRandomItemsRestricted), the
	Luck entries (Luck = true) are hidden and can't be bought; the gym's odds are always
	shown in full.

	Passes (one purchase, forever):
	  Perks       what it switches on (MonetizationService:HasPerk)
	  Grants      given once when first owned: Coins / Essence / Title / Boosts { [id] = s }
	  Parts       exclusive parts { [partId] = count }, topped back up on every join
	  Weapons     exclusive weapons it unlocks (MeleeDefinitions Unlock.Pass)
	  Includes    other passes it counts as (bundles)
	Products (buy as often as you like):
	  Coins / Essence, Boosts { [GymDefinitions boost id] = seconds }, ServerLuck = seconds
]]

local Monetization = {}

-- What a perk does (numbers the services read).
Monetization.PerkValues = {
	DoubleCoins = 2, -- x coins earned (fights, gym, challenges); not bought coins
	VIPCoins = 1.1, -- VIP: +10% coins and XP earned
	PremiumCoins = 1.1, -- Roblox Premium members: +10% coins earned
	LuckyTrainer = 2, -- the gym's luck, always (multiplies with boosts)
	FastTrainer = 1.5, -- the gym's training speed, always (multiplies with boosts)
	ServerLuck = 2, -- everyone in the server, while a Server Luck is running
	ExtraBuildSlots = 3, -- saved Nightmares: 3 -> 6 (Config.Builds.MaxSlotCount)
	NightShift = { MaxHours = 8, Rate = 0.5 }, -- offline training: up to 8 h at half speed
}
Monetization.MaxLuck = 20 -- the gym's total luck never goes past this
Monetization.MaxSpeed = 4

Monetization.Passes = {
	VIP = {
		Id = 0, Price = 299, Name = "VIP", Icon = "👑", Color = Color3.fromRGB(255, 200, 60), Category = "Perks",
		Text = "[VIP] chat tag and a gold name, +10% coins and XP from everything, and the VIP title.",
		Perks = { "VIP" }, Grants = { Title = "VIP" },
	},
	DoubleCoins = {
		Id = 0, Price = 399, Name = "2x Coins", Icon = "💰", Color = Color3.fromRGB(255, 210, 80), Category = "Perks",
		Text = "Double the coins from boss wins, duels, the gym and challenges. Forever.",
		Perks = { "DoubleCoins" },
	},
	LuckyTrainer = {
		Id = 0, Price = 449, Name = "Lucky Trainer", Icon = "🍀", Color = Color3.fromRGB(90, 220, 120), Category = "Gym", Luck = true,
		Text = "Permanent 2x luck in the Nightmare Gym. Stacks with every luck boost.",
		Perks = { "LuckyTrainer" },
	},
	FastTrainer = {
		Id = 0, Price = 299, Name = "Fast Trainer", Icon = "⏱", Color = Color3.fromRGB(80, 190, 255), Category = "Gym",
		Text = "Your Nightmare trains 1.5x faster in the gym, always. Stacks with Fast Training.",
		Perks = { "FastTrainer" },
	},
	NightShift = {
		Id = 0, Price = 349, Name = "Night Shift", Icon = "🌙", Color = Color3.fromRGB(120, 110, 230), Category = "Gym",
		Text = "Log off while training and your Nightmare keeps going: up to 8 hours at half speed, collected when you're back.",
		Perks = { "NightShift" },
	},
	ExtraBuildSlots = {
		Id = 0, Price = 199, Name = "+3 Build Slots", Icon = "🧩", Color = Color3.fromRGB(150, 90, 255), Category = "Perks",
		Text = "Save 6 Nightmares instead of 3 in the Workshop.",
		Perks = { "ExtraBuildSlots" },
	},
	StarterPack = {
		Id = 0, Price = 99, Name = "Starter Pack", Icon = "🎁", Color = Color3.fromRGB(255, 120, 70), Category = "Featured", Badge = "BEST VALUE",
		Text = "3,000 coins, 200 Essence, 1 hour of Fast Training and the Founder title. One per account.",
		Grants = { Coins = 3000, Essence = 200, Title = "Founder", Boosts = { Haste = 3600 } },
	},

	-- EXCLUSIVE NIGHTMARE PARTS (each its own special attack + animation)
	InfernoGauntlets = {
		Id = 0, Price = 349, Name = "Inferno Gauntlets", Icon = "🔥", Color = Color3.fromRGB(255, 110, 40), Category = "Exclusive",
		Text = "A PAIR of molten-iron arms. Special: METEOR FIST: leaps high and smashes down fist-first in a burning crater.",
		Parts = { InfernoGauntlet = 2 },
	},
	DragonSkull = {
		Id = 0, Price = 249, Name = "Dragon Skull", Icon = "🐉", Color = Color3.fromRGB(230, 70, 50), Category = "Exclusive",
		Text = "A horned dragon skull. Special: DRAGON BREATH: rears back and pours a cone of fire over everything ahead.",
		Parts = { DragonSkull = 1 },
	},
	PhoenixWings = {
		Id = 0, Price = 299, Name = "Phoenix Wings", Icon = "🪽", Color = Color3.fromRGB(255, 160, 40), Category = "Exclusive",
		Text = "Blazing feathered wings. Special: PHOENIX DIVE. Ultimate: SUPERNOVA, three waves of fire.",
		Parts = { PhoenixWings = 1 },
	},
	ObsidianHeart = {
		Id = 0, Price = 299, Name = "Obsidian Heart", Icon = "🌋", Color = Color3.fromRGB(150, 60, 40), Category = "Exclusive",
		Text = "A volcanic glass core. Special: MAGMA SHELL (a barrier that burns attackers). Ultimate: ERUPTION, lava rains down.",
		Parts = { ObsidianHeart = 1 },
	},
	ScorpionTail = {
		Id = 0, Price = 199, Name = "Scorpion Tail", Icon = "🦂", Color = Color3.fromRGB(120, 210, 80), Category = "Exclusive",
		Text = "A segmented stinger tail. Special: VENOM STING: lunges in as the tail arcs over its head and stabs down, poisoning.",
		Parts = { ScorpionTail = 1 },
	},
	InfernoBundle = {
		Id = 0, Price = 899, Name = "Inferno Bundle", Icon = "☄", Color = Color3.fromRGB(255, 90, 30), Category = "Featured", Badge = "SAVE 30%",
		Text = "Inferno Gauntlets, Dragon Skull, Phoenix Wings and Obsidian Heart: a whole fire Nightmare. All of it together fits your power budget from level 10.",
		Includes = { "InfernoGauntlets", "DragonSkull", "PhoenixWings", "ObsidianHeart" },
	},

	-- EXCLUSIVE WEAPONS (Handler)
	ThunderHammer = {
		Id = 0, Price = 349, Name = "Thunder Hammer", Icon = "🔨", Color = Color3.fromRGB(120, 200, 255), Category = "Exclusive",
		Text = "A two-handed war hammer. Heavy swings, an overhead SMASH that knocks down, and P P K EARTHSHAKER: leap and crack the ground.",
		Weapons = { "ThunderHammer" },
	},
	ShadowKunai = {
		Id = 0, Price = 249, Name = "Shadow Kunai", Icon = "🗡", Color = Color3.fromRGB(150, 110, 220), Category = "Exclusive",
		Text = "Throwing knives: flick a fan of three kunai at your target. Fast, ranged, and they pin enemies in place for a moment.",
		Weapons = { "ShadowKunai" },
	},
}

Monetization.Products = {
	Coins500 = { Id = 0, Price = 25, Name = "500 Coins", Icon = "🪙", Category = "Currency", Coins = 500 },
	Coins2500 = { Id = 0, Price = 99, Name = "2,500 Coins", Icon = "💰", Category = "Currency", Coins = 2500, Badge = "+25%" },
	Coins7500 = { Id = 0, Price = 249, Name = "7,500 Coins", Icon = "💰", Category = "Currency", Coins = 7500, Badge = "+50%" },
	Coins20000 = { Id = 0, Price = 599, Name = "20,000 Coins", Icon = "🏦", Category = "Currency", Coins = 20000, Badge = "+65%" },
	Essence150 = { Id = 0, Price = 49, Name = "150 Essence", Icon = "🔮", Category = "Currency", Essence = 150 },
	Essence800 = { Id = 0, Price = 199, Name = "800 Essence", Icon = "🔮", Category = "Currency", Essence = 800, Badge = "+30%" },

	-- gym boosts for Robux (they run on real time and stack time, like the coin boosts)
	MegaLuck = {
		Id = 0, Price = 79, Name = "Mega Luck (30 min)", Icon = "🍀", Category = "Gym", Luck = true,
		Text = "5x luck in the gym for 30 minutes.", Boosts = { Luck5 = 1800 },
	},
	TurboTraining = {
		Id = 0, Price = 49, Name = "Turbo Training (30 min)", Icon = "⚡", Category = "Gym",
		Text = "Rewards arrive twice as often for 30 minutes.", Boosts = { Turbo = 1800 },
	},
	PowerHour = {
		Id = 0, Price = 199, Name = "Power Hour", Icon = "🔥", Category = "Gym", Luck = true, Badge = "POPULAR",
		Text = "1 hour of Mega Luck AND Turbo Training together.", Boosts = { Luck5 = 3600, Turbo = 3600 },
	},
	ServerLuck = {
		Id = 0, Price = 99, Name = "Server Luck (15 min)", Icon = "🌟", Category = "Gym", Luck = true,
		Text = "EVERYONE in this server gets 2x gym luck for 15 minutes, and they'll know it was you.", ServerLuck = 900,
	},
}

-- Shop tabs, in order.
Monetization.Categories = { "Featured", "Exclusive", "Gym", "Perks", "Currency" }

-- Titles the shop can give (shown on the profile like the gym's titles).
Monetization.Titles = {
	VIP = "VIP",
	Founder = "Founder",
}

for key, def in Monetization.Passes do
	def.Key = key
	def.Kind = "Pass"
end
for key, def in Monetization.Products do
	def.Key = key
	def.Kind = "Product"
end

-- The pass / product with this Roblox id, if any.
function Monetization.ById(kind: string, id: number)
	local list = kind == "Pass" and Monetization.Passes or Monetization.Products
	for _, def in list do
		if def.Id ~= 0 and def.Id == id then
			return def
		end
	end
	return nil
end

-- Every pass `key` counts as (itself + whatever a bundle includes).
function Monetization.Expand(key: string): { string }
	local out, seen = {}, {}
	local function add(k)
		if seen[k] or not Monetization.Passes[k] then
			return
		end
		seen[k] = true
		table.insert(out, k)
		for _, inner in Monetization.Passes[k].Includes or {} do
			add(inner)
		end
	end
	add(key)
	return out
end

-- The pass that unlocks an exclusive weapon / part, if any.
function Monetization.PassForWeapon(weaponId: string): string?
	for key, def in Monetization.Passes do
		if def.Weapons and table.find(def.Weapons, weaponId) then
			return key
		end
	end
	return nil
end
function Monetization.PassForPart(partId: string): string?
	for key, def in Monetization.Passes do
		if def.Parts and def.Parts[partId] then
			return key
		end
	end
	return nil
end

return Monetization
