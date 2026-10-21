--[[
	FightRules  (ModuleScript)
	Location: ReplicatedStorage/Shared/FightRules

	The duel layer (UFC x For Honor): directional guards, blocks and parries. Shared by
	the server (which decides every outcome) and the client (which shows it).

	STANCE: locking on (Z) puts a fighter in their fighting stance (attribute InStance).
	In stance you ALWAYS guard one side: GuardDir = "High" | "Left" | "Right" (flick the
	mouse / right stick, or tap a guard button on phones). Your strikes come from that same
	side (Melee.ResolveStance): High = straight punches, Left = lead hook, Right = rear hook.

	SIDES are always from the DEFENDER's point of view: a lead (left-hand) hook lands on the
	defender's RIGHT, so they guard Right to stop it. Straight punches land High.

	A blow that lands on the side a fighter in stance is guarding:
	  PARRY  if they moved their guard there in the last ParryWindow seconds (they read it
	         and met it): no damage, the attacker's arm is knocked aside and they're off
	         balance for ParryStagger seconds (a counter window).
	  BLOCK  otherwise: chip damage only, a stamina cost, both bodies react.
	Any other side: a clean HIT, with a reaction by side and strength.
]]

local FightRules = {}

FightRules.Sides = { "High", "Left", "Right" }
FightRules.ParryWindow = 0.22 -- seconds before impact a guard change still counts as a parry
FightRules.BlockChip = 0.12 -- fraction of a blocked blow's damage that still gets through
FightRules.BlockStamina = 6 -- stamina per blocked blow (x2 for heavy blows)
FightRules.ParryStagger = 0.7 -- how long a parried attacker is off balance
FightRules.ParryStaminaDrain = 14 -- stamina knocked out of a parried attacker
-- Flicking into the side you're ALREADY guarding re-commits the guard (so a blow on that
-- side can be parried too), at most once per cooldown and for a little stamina.
FightRules.RecommitCooldown = 0.5
FightRules.RecommitStamina = 4

-- Where a move lands on the defender, from the move's own Dir (MeleeDefinitions):
--   "Straight" -> "High", "Lead" (attacker's left hand / leg) -> "Right",
--   "Rear" (attacker's right) -> "Left". Moves without a Dir land High.
local DIR_TO_SIDE = { Straight = "High", Lead = "Right", Rear = "Left" }
function FightRules.SideOf(move): string
	return DIR_TO_SIDE[move and move.Dir or "Straight"] or "High"
end

function FightRules.IsSide(side): boolean
	return side == "High" or side == "Left" or side == "Right"
end

-- How hard a blow is, for the hit reaction: "Light" | "Medium" | "Heavy".
function FightRules.Strength(params): string
	if params.Heavy then
		return "Heavy"
	end
	if (params.Knockback or 0) >= 12 or (params.Stagger or 0) >= 6 then
		return "Medium"
	end
	return "Light"
end

-- The defender's answer to a blow landing on `side` at server time `now`:
-- "Parry" | "Block" | "Hit". Reads the defender model's stance attributes.
function FightRules.Resolve(defender: Model, side: string, now: number): string
	if not defender:GetAttribute("InStance") or defender:GetAttribute("GuardBroken") or defender:GetAttribute("Ragdolled") then
		return "Hit"
	end
	if defender:GetAttribute("Striking") then
		return "Hit" -- caught mid-strike: hands aren't home
	end
	if defender:GetAttribute("GuardDir") ~= side then
		return "Hit"
	end
	local changedAt = defender:GetAttribute("GuardDirAt") or 0
	if now - changedAt <= FightRules.ParryWindow then
		return "Parry"
	end
	return "Block"
end

return FightRules
