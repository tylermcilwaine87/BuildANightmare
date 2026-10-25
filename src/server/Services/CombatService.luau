--[[
	CombatService  (ModuleScript)
	Location: ServerScriptService/Server/Services/CombatService

	The ONE place damage is applied. Everything (Handler swings, Nightmare combos & heavies,
	abilities, ultimates, status ticks, enemies, bosses) calls :ApplyDamage(), which:
	  1. checks the target is alive and on the opposing side
	  2. applies AttackPower, the attacker's Weaken, the target's Defence and the SYNCED
	     bonus (SyncService)
	  3. Handlers: dodge i-frames, guard, possession damage reduction (HandlerService)
	     Nightmares: possession-dodge i-frames, ability shields
	  4. applies knockback to server-owned bodies (bosses are immune)
	  5. adds STAGGER and STATUS effects (StatusService)
	  6. broadcasts visual feedback (damage numbers / defeat) to clients
	  7. notifies listeners: OnDamaged (AI retaliation, boss threat, possession meter,
	     ultimate energy, tutorial) and OnDefeated (kill credit)

	Sides: models tagged "Enemy" vs everyone else (Handlers + Nightmares).
	Phase 4 adds a PvP match context so opposing players can damage each other.

	Remote: CombatAction
	  "Melee", seq, flag? | "Equip", weaponId   Handler fighting (MeleeService)
	  "Dodge", dir | "StepBack" | "Guard", bool | "Ability", 1|2 | "Ultimate"
	  "Possess"     toggle Nightmare Possession
	  "NM_Light" | "NM_Heavy" | "NM_Dodge"   actions while possessing
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local Util = require(Shared:WaitForChild("Util"))
local Passives = require(Shared:WaitForChild("PassiveDefinitions"))
local NightmareCombat = require(Shared:WaitForChild("NightmareCombatDefinitions"))

local CombatService = {}

local damageListeners = {}
local ultimateDamage = {} -- [castKey] = { [target] = damage so far } (PvP Ultimate cap)
local recentDamage = setmetatable({}, { __mode = "k" }) -- [Model] = { Amount, At } (ragdoll burst check)
local defeatListeners = {}
local bossDownAt = setmetatable({}, { __mode = "k" }) -- [Model] = os.clock() of its last knockdown
local random = Random.new()

------------------------------------------------------------------------------------------
-- Size & resistance (Config.Ragdoll): how hard a body is to hurt, throw and floor
------------------------------------------------------------------------------------------
local RAG = Config.Ragdoll

local function isBoss(model: Model): boolean
	return CollectionService:HasTag(model, "Boss")
end

-- Body size: the cube root of the hitbox volume (Handlers count as a person-sized box).
local function bodySize(model: Model?): number
	if not model then
		return 3.2
	end
	local box = Players:GetPlayerFromCharacter(model) and RAG.HandlerBody
	if not box then
		local root = model:FindFirstChild("HumanoidRootPart")
		box = root and root:IsA("BasePart") and root.Size or RAG.HandlerBody
	end
	return math.max(box.X * box.Y * box.Z, 0.1) ^ (1 / 3)
end

local function sizeFactor(curve, attacker: Model?, target: Model): number
	local ratio = bodySize(attacker) / bodySize(target)
	return math.clamp(ratio ^ curve.Exponent, curve.Min, curve.Max)
end

-- 0..1: how much this body shrugs off knockdowns.
local function knockdownResist(target: Model): number
	local resist = RAG.Resist
	if Players:GetPlayerFromCharacter(target) then
		return resist.Handler
	elseif CollectionService:HasTag(target, "Nightmare") then
		local armour = (target:GetAttribute("Defence") or 0) * resist.NightmarePerDefence
		local footing = (target:GetAttribute("StaggerResist") or 0) * resist.NightmarePerStaggerResist
		return math.min(resist.Nightmare + armour + footing, resist.NightmareMax)
	end
	return resist.Enemy
end

-- Body size of `model` (exposed for other services / debugging).
function CombatService:BodySize(model: Model): number
	return bodySize(model)
end

-- 0..1: the chance a knockdown-worthy hit from `attacker` floors `target` right now.
-- `big` = the hit took a big chunk of its health. Bosses: a flat odd-time chance, only
-- while their knockdown cooldown is over (the caller only asks for signature strikes).
function CombatService:KnockdownChance(attacker: Model?, target: Model, big: boolean?): number
	if isBoss(target) then
		local ready = os.clock() - (bossDownAt[target] or -math.huge) >= RAG.Boss.Cooldown
		return ready and RAG.Boss.Chance or 0
	end
	local sturdy = Passives.Has(target, "Sturdy") and Passives.ById.Sturdy.KnockdownMultiplier or 1
	return math.min(1, (1 - knockdownResist(target)) * sizeFactor(RAG.SizeChance, attacker, target) * (big and 1.25 or 1) * sturdy)
end

function CombatService:Init(services)
	self.Services = services
	self.Feedback = Net.Get("CombatFeedback")
end

function CombatService:Start()
	Net.Get("CombatAction").OnServerEvent:Connect(function(player, action, arg, arg2)
		if not self.Services.AntiExploitService:Allow(player, "CombatAction") then
			return
		end
		local possession = self.Services.PossessionService
		if action == "Melee" then
			self.Services.MeleeService:HandleMelee(player, arg, arg2)
		elseif action == "Equip" then
			self.Services.MeleeService:Equip(player, arg)
		elseif action == "Loadout" then
			self.Services.MeleeService:SetLoadout(player, arg)
		elseif action == "BuyRun" or action == "SetRun" then
			self.Services.MeleeService:HandleRun(player, action, arg)
		elseif action == "Dodge" then
			self.Services.HandlerService:TryDodge(player, type(arg2) == "string" and arg2 or nil)
		elseif action == "StepBack" then
			self.Services.HandlerService:TryStepBack(player)
		elseif action == "Guard" then
			self.Services.HandlerService:SetGuard(player, arg == true)
		elseif action == "Ability" then
			if arg == 1 or arg == 2 then
				if possession:IsPossessing(player) then
					possession:PossessedAbility(player, arg)
				else
					self.Services.AbilityService:Request(player, arg)
				end
			end
		elseif action == "Ultimate" then
			self.Services.UltimateService:Request(player)
		elseif action == "Possess" then
			possession:Toggle(player)
		elseif action == "NM_Light" or action == "NM_Heavy" or action == "NM_Dodge" then
			possession:PossessedAction(player, action)
		end
	end)
end

function CombatService:IsAlive(model: Model?): boolean
	if not model or not model.Parent then
		return false
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

function CombatService:IsEnemy(model: Model): boolean
	return CollectionService:HasTag(model, "Enemy")
end

function CombatService:CanDamage(attacker: Model?, target: Model): boolean
	if not attacker or attacker == target then
		return false
	end
	-- Player vs player (Handlers and Nightmares): ONLY between opponents in a live duel.
	local attackerOwner, targetOwner = self:GetOwnerPlayer(attacker), self:GetOwnerPlayer(target)
	if attackerOwner and targetOwner then
		return attackerOwner ~= targetOwner and self.Services.DuelService:AreOpponents(attackerOwner, targetOwner)
	end
	-- Otherwise: monsters (tagged "Enemy") vs players' side.
	return self:IsEnemy(attacker) ~= self:IsEnemy(target)
end

-- True when this hit is player-vs-player.
function CombatService:IsPvP(attacker: Model?, target: Model): boolean
	local attackerOwner = attacker and self:GetOwnerPlayer(attacker)
	local targetOwner = self:GetOwnerPlayer(target)
	return attackerOwner ~= nil and targetOwner ~= nil and attackerOwner ~= targetOwner
end

-- The Player responsible for a model (their character or their Nightmare), or nil.
function CombatService:GetOwnerPlayer(model: Model?): Player?
	if not model then
		return nil
	end
	local fromCharacter = Players:GetPlayerFromCharacter(model)
	if fromCharacter then
		return fromCharacter
	end
	local ownerId = model:GetAttribute("OwnerUserId")
	return ownerId and Players:GetPlayerByUserId(ownerId) or nil
end

-- fn(target: Model, attacker: Model?, amount: number, params)
function CombatService:OnDamaged(fn)
	table.insert(damageListeners, fn)
end

-- fn(target: Model, killer: Model?)
function CombatService:OnDefeated(fn)
	table.insert(defeatListeners, fn)
end

--[[
	params = {
	  Attacker: Model, Target: Model, BaseDamage: number,
	  AttackPower: number?   100 = x1.0
	  Knockback: number?     server-owned bodies only
	  Heavy: boolean?        only partly blockable; may interrupt possession
	  Unblockable: boolean?  guard has no effect (dodging still works)
	  IgnoreDefence: boolean?
	  Stagger: number?       added to the target's stagger meter
	  Status: string?        status effect to apply on hit (StatusDefinitions id)
	  NoStatus: boolean?     (status ticks) never re-apply statuses
	  AllowSourceless: boolean?  status ticks whose source is gone
	  HitDirection: Vector3? the way the blow's force travels (unit): the reaction and any
	                         knockdown follow it (default: straight away from the attacker)
	  Crumple: boolean?      a knockdown that buckles the legs and drops the target where it
	                         stands (an overhand) instead of launching it
	  Launch: table?         { Lift, Push, Spin }: the knockdown throws the target UP (studs/s),
	                         a little away, rotating heels over head (rad/s) - a leg sweep
	                         (Config.Ragdoll.Sweep), a scythe's harvest
	  Thrown: boolean?       a throw / a signature's last blow: always knocks down (not a boss)
	  NoKnockdown: boolean?  never knocks down (the blow holds or rocks them instead)
	  Ground: boolean?       comes up out of the floor (arena hazards): misses a hovering
	                         Nightmare (Hover passive)
	  Source: string         e.g. "Handler:Jab", "NightmareCombo", "Ability:Bite"
	}
	Returns the damage actually dealt.
]]
function CombatService:ApplyDamage(params): number
	local target = params.Target
	local attacker = params.Attacker
	if not self:IsAlive(target) then
		return 0
	end
	if params.AllowSourceless then
		attacker = nil
	elseif not self:CanDamage(attacker, target) then
		return 0
	end
	if params.Ground and Passives.Has(target, "Hover") then
		return 0 -- (passive) floor hazards pass underneath a hovering Nightmare
	end

	local humanoid = target:FindFirstChildOfClass("Humanoid")
	local status = self.Services.StatusService
	local amount = params.BaseDamage * ((params.AttackPower or 100) / 100) * status:OutgoingMultiplier(attacker)
	if not params.IgnoreDefence then
		amount *= StatCalculator.DefenceMultiplier(target:GetAttribute("Defence") or 0)
	end
	-- smaller than you: it hurts more; bigger: less (never vs bosses, their health is tuned)
	if attacker and not isBoss(target) then
		amount *= sizeFactor(RAG.SizeDamage, attacker, target)
	end
	-- SYNCED (you and your Nightmare fighting as one, SyncService): both hit harder
	local synced = self.Services.SyncService:DamageMultiplier(attacker)
	amount *= synced
	-- a boss caught EXPOSED (just after its attack) or BROKEN (stagger bar full, on its
	-- knees) takes more (Config.Bosses: the punish windows)
	local exposed, broken = false, false
	if attacker and isBoss(target) then
		if (target:GetAttribute("ExposedUntil") or 0) > Workspace:GetServerTimeNow() then
			exposed = true
			amount *= Config.Bosses.Exposed.DamageMultiplier
		end
		if status:IsStaggered(target) then
			broken = true
			amount *= Config.Bosses.BrokenDamageMultiplier
		end
	end

	local targetPlayer = Players:GetPlayerFromCharacter(target)

	-- PvP balance (spec section 13).
	if attacker and self:IsPvP(attacker, target) then
		if targetPlayer and CollectionService:HasTag(attacker, "Nightmare") then
			amount *= Config.PvP.NightmareToHandlerMultiplier
		end
		-- An Ultimate can never take more than 45% of a target's max HP in one cast.
		if params.CastKey then
			local perCast = ultimateDamage[params.CastKey]
			if not perCast then
				perCast = {}
				ultimateDamage[params.CastKey] = perCast
				task.delay(15, function()
					ultimateDamage[params.CastKey] = nil
				end)
			end
			local cap = humanoid.MaxHealth * Config.Ultimate.PvPDamageCapFraction
			amount = math.min(amount, math.max(0, cap - (perCast[target] or 0)))
			perCast[target] = (perCast[target] or 0) + amount
		end
	end

	if targetPlayer then
		amount = self.Services.HandlerService:ModifyIncomingDamage(targetPlayer, amount, params)
	elseif CollectionService:HasTag(target, "Nightmare") and self.Services.PossessionService:IsNightmareInvulnerable(target) then
		amount = 0
	elseif (target:GetAttribute("PhaseUntil") or 0) > Workspace:GetServerTimeNow() then
		amount = 0 -- (Afterimage passive) mid-step: the blow hits the afterimage
	end
	-- a Nightmare covering up (the combat brain's GUARD): light blows are mostly absorbed;
	-- a Heavy smashes the guard open and staggers it harder
	local guarded, guardBroken = false, false
	if (target:GetAttribute("NightmareGuard") or 0) > Workspace:GetServerTimeNow() and not params.Unblockable then
		if params.Heavy then
			guardBroken = true
			target:SetAttribute("NightmareGuard", nil)
		else
			guarded = true
			amount *= 1 - NightmareCombat.Guard.Absorb
		end
	end

	-- Shields (abilities) absorb damage before health.
	local shield = target:GetAttribute("Shield") or 0
	if shield > 0 and amount > 0 then
		local absorbed = math.min(shield, amount)
		target:SetAttribute("Shield", shield - absorbed)
		amount -= absorbed
		-- a shield that burns back (Magma Shell: AbilityDefinitions Retaliate)
		if (target:GetAttribute("RetaliateUntil") or 0) > Workspace:GetServerTimeNow() then
			self.Services.PassiveService:Retaliate(target, params.Attacker, params)
		end
	end

	if amount <= 0 then
		return 0
	end
	amount = math.max(1, math.floor(amount + 0.5))

	-- Duels: a Handler is KNOCKED OUT (never killed). DuelService decides what happens.
	local duelKO = false
	if targetPlayer and self.Services.DuelService:IsInMatch(targetPlayer) and amount >= humanoid.Health then
		amount = math.max(0, math.floor(humanoid.Health) - 1)
		duelKO = true
	end
	if duelKO and amount <= 0 then
		self.Services.DuelService:OnHandlerKO(targetPlayer)
		return 0
	end

	local before = humanoid.Health
	humanoid:TakeDamage(amount) -- respects ForceFields
	local dealt = before - humanoid.Health
	if dealt <= 0 then
		return 0
	end

	local root = target:FindFirstChild("HumanoidRootPart")
	local position = root and root.Position or target:GetPivot().Position

	-- a heavy blow on a Handler knocks them out of the strike they were throwing
	if targetPlayer and params.Heavy then
		self.Services.MeleeService:Interrupt(targetPlayer)
	end

	-- Knockback only for server-owned bodies (Nightmares/enemies). Player characters are
	-- client-owned, so impulses from the server would be ignored or fight the client.
	-- (a small body gets sent much further than a big one)
	local knockback = (params.Knockback or 0) * (attacker and sizeFactor(RAG.SizeThrow, attacker, target) or 1)
	if guarded then
		knockback *= 0.3 -- (braced behind the guard)
	end
	if Passives.Has(target, "Sturdy") then
		knockback *= Passives.ById.Sturdy.KnockbackMultiplier -- (passive) planted
	end
	if attacker and knockback > 0 and root and not root.Anchored and not target:GetAttribute("KnockbackImmune") and (self:IsEnemy(target) or CollectionService:HasTag(target, "Nightmare")) and root:GetNetworkOwner() == nil then
		local direction = Util.FlatUnit(position - attacker:GetPivot().Position)
		if direction then
			root:ApplyImpulse((direction * knockback + Vector3.new(0, knockback * 0.3, 0)) * root.AssemblyMass)
		end
	end

	-- Ragdoll knockdown (Config.Ragdoll): special moves, strong knockback and hits that take
	-- a big chunk of health can throw a body off its feet: a Scrapling every time, another
	-- player's Nightmare depending on its armour and size, a boss only the odd time and
	-- only to a signature strike.
	local knockedDown = false
	if humanoid.Health > 0 and attacker and (targetPlayer or CollectionService:HasTag(target, "Nightmare") or CollectionService:HasTag(target, "Enemy")) then
		local cfg = Config.Ragdoll
		local now = os.clock()
		-- recent damage, fading out over BurstWindow
		local burst = recentDamage[target]
		local total = dealt
		if burst then
			total += burst.Amount * math.max(0, 1 - (now - burst.At) / cfg.BurstWindow)
		end
		recentDamage[target] = { Amount = total, At = now }

		local source = params.Source or ""
		local special = params.Heavy or source:sub(1, 8) == "Ability:" or source:sub(1, 9) == "Ultimate:"
		local big = dealt >= humanoid.MaxHealth * cfg.DamageFraction or total >= humanoid.MaxHealth * cfg.BurstFraction
		local boss = isBoss(target)
		local worthy = if boss then special else (special or big or knockback >= cfg.MinKnockback)
		-- NoKnockdown: the blow holds them instead (a bite's clamp keeps them in its jaws)
		if worthy and not params.NoKnockdown and not guarded then
			local chance = self:KnockdownChance(attacker, target, big or params.Launch ~= nil)
			if params.Thrown and not boss then
				chance = 1 -- (a throw, a signature's last blow: they go down)
			end
			if chance > 0 and random:NextNumber() < chance then
				local direction = (params.HitDirection and Util.FlatUnit(params.HitDirection)) or Util.FlatUnit(position - attacker:GetPivot().Position) or Vector3.zAxis
				local force = math.max(knockback, cfg.MinThrow)
				local throw
				local options = boss and { AllowImmune = true, SpinScale = cfg.Boss.SpinScale } or {}
				local launch = params.Launch
				if launch then
					-- thrown UP and rotated heels over head (a small body flies higher, a big
					-- one barely leaves the floor)
					local scale = sizeFactor(RAG.SizeThrow, attacker, target)
					throw = direction * launch.Push * scale + Vector3.new(0, launch.Lift * scale, 0)
					options.Flip = launch.Spin
				elseif params.Crumple then
					-- the legs go: a short stagger the way the blow drove them, folding down
					throw = direction * force * cfg.Launch * 0.3 + Vector3.new(0, -force * 0.25, 0)
				else
					throw = direction * force * cfg.Launch + Vector3.new(0, force * 0.45, 0)
				end
				if boss then
					throw *= cfg.Boss.ThrowScale
				end
				if self.Services.RagdollService:Ragdoll(target, throw, direction, boss and cfg.Boss.Duration or nil, options) then
					recentDamage[target] = nil
					knockedDown = true
					if boss then
						bossDownAt[target] = now
						Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "KnockedDown", { Target = target, Position = position, Boss = true })
					end
				end
			end
		end
	end

	if humanoid.Health > 0 then
		if params.Stagger and params.Stagger > 0 then
			local stagger = params.Stagger * (exposed and Config.Bosses.Exposed.StaggerMultiplier or 1)
			if guarded then
				stagger *= 0.35
			elseif guardBroken then
				stagger *= 2
			end
			if synced > 1 then
				stagger *= Config.Sync.StaggerMultiplier
			end
			status:AddStagger(target, stagger, attacker)
		end
		if params.Status and not params.NoStatus then
			status:Apply(target, params.Status, attacker)
		end
	end

	-- Visual only: just the players close enough to see it (Config.Performance).
	-- (Attacker / Dir / Heavy / KnockedDown drive the hit reaction, the striker's hit-stop
	-- and camera punch, and the impact sound on every nearby client)
	Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "Damage", {
		Target = target,
		Amount = math.floor(dealt + 0.5),
		Position = position,
		Source = params.Source,
		Attacker = attacker,
		Dir = params.HitDirection or (attacker and Util.FlatUnit(position - attacker:GetPivot().Position)) or nil,
		Heavy = params.Heavy == true,
		KnockedDown = knockedDown,
		Exposed = exposed or nil, -- (punished an exposed boss)
		Broken = broken or nil, -- (hit a broken boss)
		Synced = synced > 1 or nil, -- (a synced hit)
		Guarded = guarded or nil, -- (blocked by a Nightmare's guard)
		GuardBroken = guardBroken or nil,
	})

	for _, listener in damageListeners do
		task.spawn(listener, target, attacker, dealt, params)
	end
	if duelKO then
		self.Services.DuelService:OnHandlerKO(targetPlayer)
	end

	if humanoid.Health <= 0 then
		Net.FireNearby(self.Feedback, position, Config.Performance.EffectRadius, "Defeated", { Target = target, Position = position })
		for _, listener in defeatListeners do
			task.spawn(listener, target, attacker)
		end
	end

	return dealt
end

return CombatService
