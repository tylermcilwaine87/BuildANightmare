--[[
	StatusDefinitions  (ModuleScript)
	Location: ReplicatedStorage/Shared/StatusDefinitions

	Elemental status effects. Every effect has a clear icon/colour, a fixed duration, a
	stack cap and counterplay. StatusService applies them on the server; clients show
	them from the model attribute "Statuses" (e.g. "Burn,Poison:3,Chill").

	Element -> status:
	  Fire -> Burn      Poison -> Poison     Electric -> Shock
	  Ice  -> Chill     Shadow -> Weaken     Void -> (knockback/displacement in the ability)
	  Mechanical -> (shields/stagger resist via parts, no debuff)
]]

local StatusDefinitions = {}

StatusDefinitions.ById = {
	Burn = {
		DisplayName = "Burn",
		Icon = "BURN",
		Color = Color3.fromRGB(255, 130, 40),
		Duration = 3,
		MaxStacks = 1, -- re-applying refreshes the timer
		TickInterval = 0.5,
		TickDamage = 4,
		Counterplay = "Short. Disengage until it ends.",
	},
	Poison = {
		DisplayName = "Poison",
		Icon = "PSN",
		Color = Color3.fromRGB(120, 220, 70),
		Duration = 6,
		MaxStacks = 5,
		TickInterval = 1,
		TickDamage = 2, -- per stack
		Counterplay = "Stacks drop off if you avoid repeated hits.",
	},
	Shock = {
		DisplayName = "Shock",
		Icon = "SHK",
		Color = Color3.fromRGB(255, 235, 80),
		Duration = 0.6,
		MaxStacks = 1,
		BurstDamage = 8,
		ChainRadius = 12,
		ChainFraction = 0.5, -- one nearby enemy takes half
		Counterplay = "Spread out so it can't chain.",
	},
	Chill = {
		DisplayName = "Chill",
		Icon = "ICE",
		Color = Color3.fromRGB(120, 220, 255),
		Duration = 2.5,
		MaxStacks = 1,
		Slow = 0.35, -- 35% slower; never a full freeze
		Counterplay = "Slow only, never frozen. Dodge still works.",
	},
	Weaken = {
		DisplayName = "Weaken",
		Icon = "WKN",
		Color = Color3.fromRGB(170, 100, 255),
		Duration = 3,
		MaxStacks = 1,
		OutgoingMultiplier = 0.85, -- deals 15% less damage
		Counterplay = "Play defensively for 3 seconds.",
	},
}

-- Element (ability/part flavour) -> status applied.
StatusDefinitions.ByElement = {
	Fire = "Burn",
	Poison = "Poison",
	Electric = "Shock",
	Ice = "Chill",
	Shadow = "Weaken",
}

StatusDefinitions.Order = { "Burn", "Poison", "Shock", "Chill", "Weaken" }

function StatusDefinitions.Get(id: string?)
	if type(id) ~= "string" then
		return nil
	end
	return StatusDefinitions.ById[id]
end

-- "Burn,Poison:3" -> { Burn = 1, Poison = 3 }
function StatusDefinitions.Parse(text: string?)
	local result = {}
	if type(text) ~= "string" or text == "" then
		return result
	end
	for entry in string.gmatch(text, "[^,]+") do
		local id, stacks = string.match(entry, "^(%a+):?(%d*)$")
		if id then
			result[id] = tonumber(stacks) or 1
		end
	end
	return result
end

return StatusDefinitions
