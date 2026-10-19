--[[
	RarityDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/RarityDefinitions

	Four rarities, Uncommon -> Legendary. There is intentionally no "Common" rarity.
]]

local RarityDefinitions = {}

RarityDefinitions.Order = { "Uncommon", "Rare", "Epic", "Legendary" }

RarityDefinitions.Info = {
	Uncommon = { Rank = 1, DisplayName = "UNCOMMON", Color = Color3.fromRGB(80, 205, 100) },
	Rare = { Rank = 2, DisplayName = "RARE", Color = Color3.fromRGB(70, 140, 255) },
	Epic = { Rank = 3, DisplayName = "EPIC", Color = Color3.fromRGB(170, 90, 255) },
	Legendary = { Rank = 4, DisplayName = "LEGENDARY", Color = Color3.fromRGB(255, 195, 50) },
}

return RarityDefinitions
