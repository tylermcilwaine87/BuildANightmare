--[[
	BuildValidator  (ModuleScript)
	Location: ReplicatedStorage/Shared/BuildValidator

	Build data shape:
	  {
	    Name = "The Tank",
	    Parts = { Core = "WoodenBody", Head = "CrackedSkull", RightArm = "RustyClaw", ... },
	    Adjust = { [slot] = { Scale = 1, Yaw = 0, Pitch = 0 } },
	    Mutations = { [slot] = "Venomous", ... },   -- optional (Phase 5)
	  }

	Sanitize(): turns UNTRUSTED client data into a clean build (or rejects it).
	Validate(): checks game rules (required slots, slot fit, ownership counts, Legendary
	            limit, Power Cost budget).

	The client runs Validate() only to show helpful messages; the server ALWAYS runs
	Sanitize() + Validate() itself with the authoritative inventory.
]]

local Shared = script.Parent
local Config = require(Shared.Config)
local SlotDefinitions = require(Shared.SlotDefinitions)
local PartDefinitions = require(Shared.PartDefinitions)
local StatCalculator = require(Shared.StatCalculator)
local Util = require(Shared.Util)
local MutationDefinitions = require(Shared.MutationDefinitions)

local BuildValidator = {}

function BuildValidator.DefaultAdjust()
	return { Scale = 1, Yaw = 0, Pitch = 0 }
end

function BuildValidator.ClampAdjust(raw)
	local cfg = Config.Builds
	local adjust = BuildValidator.DefaultAdjust()
	if type(raw) ~= "table" then
		return adjust
	end
	if Util.IsFiniteNumber(raw.Scale) then
		adjust.Scale = Util.RoundTo(math.clamp(raw.Scale, cfg.ScaleMin, cfg.ScaleMax), 0.01)
	end
	if Util.IsFiniteNumber(raw.Yaw) then
		adjust.Yaw = Util.RoundTo(math.clamp(raw.Yaw, -cfg.RotateLimit, cfg.RotateLimit), 1)
	end
	if Util.IsFiniteNumber(raw.Pitch) then
		adjust.Pitch = Util.RoundTo(math.clamp(raw.Pitch, -cfg.RotateLimit, cfg.RotateLimit), 1)
	end
	return adjust
end

function BuildValidator.Sanitize(raw)
	if type(raw) ~= "table" or type(raw.Parts) ~= "table" then
		return nil, "Malformed build."
	end

	local name = ""
	if type(raw.Name) == "string" then
		name = Util.TruncateUtf8(Util.Trim(raw.Name), Config.Builds.MaxNameLength)
	end

	local rawAdjust = type(raw.Adjust) == "table" and raw.Adjust or {}
	local rawMutations = type(raw.Mutations) == "table" and raw.Mutations or {}
	local build = { Name = name, Parts = {}, Adjust = {}, Mutations = {} }

	for _, slot in SlotDefinitions.Order do
		local id = raw.Parts[slot]
		if id ~= nil then
			if type(id) ~= "string" or PartDefinitions.Get(id) == nil then
				return nil, ("Unknown part in %s."):format(SlotDefinitions.Info[slot].DisplayName)
			end
			build.Parts[slot] = id
			-- Unknown mutation ids are dropped (the plain part stays).
			if MutationDefinitions.Get(rawMutations[slot]) then
				build.Mutations[slot] = rawMutations[slot]
			end
		end
		build.Adjust[slot] = BuildValidator.ClampAdjust(rawAdjust[slot])
	end

	return build, nil
end

-- inventory: { [partId] = count } or nil to skip ownership checks.
-- powerBudget: number or nil to skip the budget check.
-- mutations: profile.Mutations ({ [partId] = { [mutationId] = count } }). When
--   ownership is checked, mutated parts need that many mutated copies (nil = none owned).
function BuildValidator.Validate(build, inventory, powerBudget, mutations): (boolean, string?)
	for _, slot in SlotDefinitions.Order do
		local info = SlotDefinitions.Info[slot]
		local id = build.Parts[slot]
		if id == nil then
			if info.Required then
				return false, ("%s is required."):format(info.DisplayName)
			end
		else
			local def = PartDefinitions.Get(id)
			if not def or not def.Equippable then
				return false, "That part cannot be equipped."
			end
			if def.Slot ~= info.PartSlot then
				return false, ("%s does not fit the %s slot."):format(def.DisplayName, info.DisplayName)
			end
		end
	end

	local core = PartDefinitions.Get(build.Parts.Core)
	local archetype = StatCalculator.GetArchetype(build)
	if core.Compat and not table.find(core.Compat, archetype) then
		return false, ("%s does not support %s movement."):format(core.DisplayName, archetype)
	end

	-- Ownership: a build may use a part as many times as you own copies of it.
	-- (Saved builds do not lock parts away from each other; only one is active at once.)
	local used = {}
	for _, slot in SlotDefinitions.Order do
		local id = build.Parts[slot]
		if id then
			used[id] = (used[id] or 0) + 1
		end
	end

	local legendaryCount = 0
	for id, count in used do
		local def = PartDefinitions.Get(id)
		if def.Rarity == "Legendary" then
			legendaryCount += count
		end
		if inventory then
			local owned = inventory[id] or 0
			if owned == 0 then
				return false, ("You don't own %s."):format(def.DisplayName)
			elseif owned < count then
				return false, ("You need %d× %s (you own %d)."):format(count, def.DisplayName, owned)
			end
		end
	end

	-- Mutated copies: a "Venomous Rusty Claw" in two arms needs two Venomous copies.
	if inventory then
		local usedMutated = {}
		for _, slot in SlotDefinitions.Order do
			local id = build.Parts[slot]
			local mutation = id and MutationDefinitions.ForSlot(build, slot)
			if mutation then
				local key = id .. "/" .. mutation
				usedMutated[key] = (usedMutated[key] or 0) + 1
				local owned = mutations and mutations[id] and mutations[id][mutation] or 0
				if owned < usedMutated[key] then
					local def = PartDefinitions.Get(id)
					return false, ("You don't own %s %s."):format(usedMutated[key] > 1 and ("%d×"):format(usedMutated[key]) or "a", MutationDefinitions.FullName(def.DisplayName, mutation))
				end
			end
		end
	end

	if legendaryCount > Config.Builds.MaxLegendaryParts then
		return false, "Only one Legendary part per Nightmare."
	end

	if powerBudget then
		local stats = StatCalculator.Compute(build)
		if stats.PowerCost > powerBudget then
			return false, ("Power Cost %d exceeds the budget of %d."):format(stats.PowerCost, powerBudget)
		end
	end

	return true, nil
end

return BuildValidator
