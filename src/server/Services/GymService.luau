--[[
	GymService  (ModuleScript)
	Location: ServerScriptService/Server/Services/GymService

	THE NIGHTMARE GYM: AFK training. Server-authoritative from start to finish; the
	client only plays the cinematics and shows what this service sends it.

	  "Enter"   at the lift in the Forge (EnterRadius), not mid-fight / duel / possession.
	            Summons your Nightmare if it isn't out, reserves a free training bay.
	  "Arrive"  (the client's camera is inside the dark lift shaft): you and your Nightmare
	            are moved into the gym, the bay's bag is re-hung at your Nightmare's shoulder
	            height, it walks in from the lift and starts training (routine below), and
	            the reward clock starts.
	  "Leave"   back out through the lift (also on death / disconnect / Nightmare loss).
	  "Buy"     a boost (GymDefinitions.Boosts) for coins.

	Training: the Nightmare's AI is suspended (brain.scripted) and this service plays
	GymDefinitions.Routines one after another (combos on the bag, footwork, jaw work for
	armless Nightmares, a rest every few routines). The bag swings on each client from the
	strike markers of those animations.

	Rewards: every RewardInterval / Haste seconds of training, roll a tier with the real
	odds (GymDefinitions.Odds at your luck), grant it (coins / essence via
	ProgressionService, parts via InventoryService), record it in profile.Gym, and save at
	once for anything Rare or better. Nothing a client sends affects a roll.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))

local GymWorld = require(script.Parent:WaitForChild("World"):WaitForChild("Gym"))

local GymService = {}

local random = Random.new()
local sessions = {} -- [Player] = session
local bayOwner = {} -- [bayIndex] = Player
local stats = { Training = 0, Rewards = 0, LastDrop = "—" }

-- Equippable parts by rarity, for part rewards.
local partsByRarity = {}
for id, def in PartDefinitions.ById do
	if def.Equippable then
		partsByRarity[def.Rarity] = partsByRarity[def.Rarity] or {}
		table.insert(partsByRarity[def.Rarity], id)
	end
end
for _, list in partsByRarity do
	table.sort(list) -- deterministic order (the pick itself is random)
end
local PART_FALLBACK = { Legendary = "Epic", Epic = "Rare", Rare = "Uncommon" }

function GymService:Init(services)
	self.Services = services
	self.Event = Net.Get("GymEvent")
end

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local function rootOf(player: Player): BasePart?
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function rollRange(range): number
	if not range then
		return 0
	end
	return random:NextInteger(range[1], range[2])
end

local function rollTier(luck: number): string
	local odds = GymDefinitions.Odds(luck)
	local roll = random:NextNumber()
	for _, id in GymDefinitions.TierOrder do
		roll -= odds[id]
		if roll <= 0 then
			return id
		end
	end
	return "Common"
end

local function hasArms(model: Model): boolean
	return model:FindFirstChild("RightArm_Root", true) ~= nil or model:FindFirstChild("LeftArm_Root", true) ~= nil
end

-- How far in front of the root a punch reaches when the arm is straight out (shoulder
-- position + arm length) and the shoulder's height: measured off the rest pose.
local function punchReach(model: Model, root: BasePart): (number?, number?)
	for _, side in { "Right", "Left" } do
		local joint = model:FindFirstChild("Joint_" .. side .. "Arm", true)
		if joint and joint:IsA("Motor6D") and joint.Part0 then
			local shoulder = (joint.Part0.CFrame * joint.C0).Position
			local length = 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") and part.Name:sub(1, #side + 4) == side .. "Arm_" then
					local half = part.Size.Magnitude / 2
					length = math.max(length, (part.Position - shoulder).Magnitude + half * 0.7)
				end
			end
			local forward = -root.CFrame:PointToObjectSpace(shoulder).Z
			return forward + length, shoulder.Y
		end
	end
	return nil, nil
end

-- A two-legged body's kicking leg: its length (hip pivot to the far corner of the leg, the
-- same measure GymDefinitions' Reach fractions were taken with) and how far forward of the
-- root the hip sits. nil for bodies that can't kick (four legs, floating...).
local function kickingLeg(model: Model, root: BasePart): (number?, number?)
	if model:GetAttribute("Archetype") ~= "Biped" then
		return nil, nil
	end
	local joint = model:FindFirstChild("Sub_Legs_R", true)
	if not (joint and joint:IsA("Motor6D") and joint.Part0 and joint.Part1) then
		return nil, nil
	end
	local pivot = (joint.Part0.CFrame * joint.C0).Position
	local length = 0
	for _, weld in model:GetDescendants() do
		if weld:IsA("Weld") and weld.Part0 == joint.Part1 and weld.Part1 then
			local part = weld.Part1
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local corner = (part.CFrame * CFrame.new(part.Size.X / 2 * sx, part.Size.Y / 2 * sy, part.Size.Z / 2 * sz)).Position
						length = math.max(length, (corner - pivot).Magnitude)
					end
				end
			end
		end
	end
	if length < 0.5 then
		return nil, nil
	end
	return length, -root.CFrame:PointToObjectSpace(pivot).Z
end

-- The mouth's reach (head front + the bite's thrust) and its height, for jaw work.
local function biteReach(model: Model, root: BasePart): (number, number)
	local front, height = 0, root.Position.Y
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and part.Name:sub(1, 5) == "Head_" then
			local relative = root.CFrame:ToObjectSpace(part.CFrame)
			local depth = math.abs(relative.XVector.Z) * part.Size.X + math.abs(relative.YVector.Z) * part.Size.Y + math.abs(relative.ZVector.Z) * part.Size.Z
			local f = -relative.Position.Z + depth / 2
			if f > front then
				front, height = f, part.Position.Y
			end
		end
	end
	return front + 1, height
end

function GymService:IsTraining(player: Player): boolean
	local session = sessions[player]
	return session ~= nil and session.state == "Training"
end

function GymService:InGym(player: Player): boolean
	return sessions[player] ~= nil
end

-- The bay's screen as everyone else sees it (its owner's client shows their live timer).
local function labelBay(bay: number, ownerName: string?)
	local hall = GymWorld.Hall()
	local model = hall and hall:FindFirstChild("Bay" .. bay)
	local screen = model and model:FindFirstChild("BayScreen")
	local gui = screen and screen:FindFirstChild("Screen")
	if gui then
		gui.Title.Text = ownerName and ("BAY %d · %s"):format(bay, ownerName:upper()) or ("BAY %d"):format(bay)
		gui.Next.Text = ownerName and "TRAINING" or "FREE"
		gui.Last.Text = ""
	end
end

function GymService:UpdateStatsWall()
	local hall = GymWorld.Hall()
	local screen = hall and hall:FindFirstChild("StatsScreen")
	local gui = screen and screen:FindFirstChild("Stats")
	if not gui then
		return
	end
	gui.Training.Text = ("NIGHTMARES IN TRAINING: %d"):format(stats.Training)
	gui.Rewards.Text = ("REWARDS EARNED HERE: %d"):format(stats.Rewards)
	gui.LastDrop.Text = "LAST BIG DROP: " .. stats.LastDrop
end

local function countTraining()
	local n = 0
	for _, session in sessions do
		if session.state == "Training" then
			n += 1
		end
	end
	stats.Training = n
end

-- What the client's panel shows (timers in seconds from now).
function GymService:Summary(player: Player)
	local session = sessions[player]
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return nil
	end
	local now = os.time()
	local luck, speed = GymDefinitions.Multipliers(profile.Gym.Boosts, now)
	local boosts = {}
	for id, expires in profile.Gym.Boosts do
		if expires > now then
			boosts[id] = expires - now
		end
	end
	return {
		Bay = session and session.bay,
		State = session and session.state,
		NextIn = session and session.nextRewardAt and math.max(0, session.nextRewardAt - os.clock()) or nil,
		Interval = GymDefinitions.RewardInterval / speed,
		SessionTime = session and session.trained or 0,
		SessionRewards = session and session.count or 0,
		SessionBest = session and session.best or nil,
		Recent = session and session.recent or {},
		Luck = luck,
		Speed = speed,
		Boosts = boosts,
		TotalTime = profile.Gym.TotalTime,
		TotalRewards = profile.Gym.Rewards,
		Best = profile.Gym.Best,
		Titles = Util.DeepCopy(profile.Gym.Titles),
		Coins = profile.Coins,
	}
end

------------------------------------------------------------------------------------------
-- Training routine
------------------------------------------------------------------------------------------
function GymService:PickRoutine(session)
	if session.sinceRest >= session.restDue then
		for _, routine in GymDefinitions.Routines do
			if routine.Rest then
				return routine
			end
		end
	end
	-- Arms = true needs arms, false is for armless bodies, nil suits any body; Legs needs
	-- a kicking leg; Abilities needs something in its loadout
	local armed = session.armed
	local pool, total = {}, 0
	for pass = 1, 2 do
		for _, routine in GymDefinitions.Routines do
			local fits = not routine.Rest
				and (routine.Arms == nil or routine.Arms == armed)
				and (not routine.Legs or session.legLength ~= nil)
				and (not routine.Abilities or #session.brain.abilities > 0)
			fits = fits and (routine.Abilities or routine.Action ~= nil)
			if fits and (pass == 2 or (routine.Action or "Abilities") ~= session.lastAction) then
				table.insert(pool, routine)
				total += routine.Weight
			end
		end
		if #pool > 0 then
			break -- pass 2 (repeats allowed) only if nothing else fits
		end
	end
	local roll = random:NextNumber(0, total)
	for _, routine in pool do
		roll -= routine.Weight
		if roll <= 0 then
			return routine
		end
	end
	return pool[1]
end

-- Walks the Nightmare in from the lift to its spot at the bag, then trains until the
-- session ends. Runs in its own thread; every wait re-checks the session is still live.
function GymService:RunTraining(player: Player, session)
	local ai = self.Services.NightmareAIService
	-- one routine thread per session: starting a new one (Nightmare rebuilt) retires this
	session.runToken = (session.runToken or 0) + 1
	local token = session.runToken
	local brain = session.brain
	local function live()
		return sessions[player] == session and session.state == "Training" and session.runToken == token and brain.model.Parent ~= nil
	end
	local humanoid = brain.humanoid
	brain.nav:Stop()
	ai:StopFacing(brain)
	ai:SetSpeed(brain, math.min(brain.stats.MoveSpeed, 16))

	-- along the aisle edge on the bay's side, then into the bay
	local bayCF = GymDefinitions.BayCF(session.bay)
	local laneX = session.bay <= 3 and -12 or 12
	local lane = (GymDefinitions.Origin * CFrame.new(laneX, 0, 0)).Position
	local entry = (bayCF * CFrame.new(0, 0, 8)).Position
	local waypoints = {
		(GymDefinitions.Origin * CFrame.new(laneX, 0, GymDefinitions.HallHalf.Z - 12)).Position,
		Vector3.new(lane.X, entry.Y, entry.Z),
		session.standAt,
	}
	for _, point in waypoints do
		if not live() then
			return
		end
		humanoid:MoveTo(point)
		local started = os.clock()
		while live() and Util.FlatDistance(brain.root.Position, point) > 1.5 and os.clock() - started < 6 do
			task.wait(0.1)
		end
	end
	if not live() then
		return
	end
	humanoid:MoveTo(brain.root.Position)
	ai:Face(brain, session.bagAt)
	task.wait(0.4)

	while live() do
		local routine = self:PickRoutine(session)
		session.lastAction = routine.Action or (routine.Abilities and "Abilities")
		if routine.Abilities then
			routine = self:AbilityRoutine(session) or routine
		end
		if not routine.Action then
			task.wait(0.5)
			continue
		end
		if routine.Rest then
			session.sinceRest = 0
			session.restDue = random:NextInteger(GymDefinitions.RestEvery[1], GymDefinitions.RestEvery[2])
		else
			session.sinceRest += 1
		end
		-- footwork: step to the range this move lands from (in for a bite or a knee, back
		-- out for a spinning kick, punching range for the hands)
		local spot = self:SpotFor(session, routine)
		if Util.FlatDistance(brain.root.Position, spot) > 0.5 then
			ai:StopFacing(brain)
			humanoid:MoveTo(spot)
			local started = os.clock()
			while live() and Util.FlatDistance(brain.root.Position, spot) > 0.5 and os.clock() - started < 1.5 do
				task.wait(0.05)
			end
			humanoid:MoveTo(brain.root.Position)
		end
		if not live() then
			return
		end
		ai:Face(brain, session.bagAt)
		task.wait(0.15)
		brain.model:SetAttribute("ActionSource", routine.Source or "")
		ai:PlayAction(brain, routine.Action, routine.Windup or 0, routine.Duration)
		task.wait(routine.Duration + random:NextNumber(GymDefinitions.RoutineGap[1], GymDefinitions.RoutineGap[2]))
	end
end

------------------------------------------------------------------------------------------
-- Rewards
------------------------------------------------------------------------------------------
function GymService:GrantReward(player: Player, session)
	local profile = self.Services.PlayerDataService:Get(player)
	if not profile then
		return
	end
	local luck = GymDefinitions.Multipliers(profile.Gym.Boosts, os.time())
	local tierId = rollTier(luck)
	if session.devTier and RunService:IsStudio() then
		tierId, session.devTier = session.devTier, nil
	end
	local tier = GymDefinitions.Tiers[tierId]
	local spec = GymDefinitions.Rewards[tierId]
	local result = { Tier = tierId, Rank = tier.Rank }

	local currency = { Coins = rollRange(spec.Coins), Essence = rollRange(spec.Essence) }
	if spec.Part then
		local rarity = spec.Part
		local list = partsByRarity[rarity]
		while (not list or #list == 0) and PART_FALLBACK[rarity] do
			rarity = PART_FALLBACK[rarity]
			list = partsByRarity[rarity]
		end
		if list and #list > 0 then
			local partId = list[random:NextInteger(1, #list)]
			local mutationId = spec.Mutated and MutationDefinitions.Roll(random) or nil
			local isNew
			if mutationId then
				local _, newPart = self.Services.InventoryService:GrantMutated(player, partId, mutationId)
				isNew = newPart
			else
				local _, newPart = self.Services.InventoryService:Grant(player, partId, 1)
				isNew = newPart
			end
			result.PartId, result.PartRarity, result.Mutation, result.IsNew = partId, rarity, mutationId, isNew
		elseif spec.Fallback then
			currency.Essence += rollRange(spec.Fallback.Essence)
		end
	end
	if currency.Coins > 0 or currency.Essence > 0 then
		self.Services.ProgressionService:Award(player, currency)
		self.Services.GameAnalyticsService:Rewards(player, currency, "Gym")
	end
	result.Coins, result.Essence = currency.Coins, currency.Essence
	if spec.Title and not profile.Gym.Titles[spec.Title] then
		profile.Gym.Titles[spec.Title] = true
		result.Title = spec.Title
	end

	profile.Gym.Rewards += 1
	profile.Gym.Best = math.max(profile.Gym.Best, tier.Rank)
	session.count += 1
	if not session.best or tier.Rank > session.best then
		session.best = tier.Rank
	end
	table.insert(session.recent, 1, table.clone(result)) -- a copy: `result` gets the summary (which lists `recent`) below
	if #session.recent > 6 then
		table.remove(session.recent)
	end

	stats.Rewards += 1
	if tier.Rank >= GymDefinitions.Tiers.Epic.Rank then
		local what = result.PartId and (PartDefinitions.Get(result.PartId).DisplayName) or tierId
		stats.LastDrop = ("%s — %s (%s)"):format(player.DisplayName, what, tierId:upper())
	end
	self:UpdateStatsWall()

	if tier.Rank >= GymDefinitions.Tiers.Rare.Rank then
		self.Services.PlayerDataService:SaveNow(player)
	end
	self.Services.NightmareBuildService:PushState(player)
	result.Summary = self:Summary(player)
	self.Event:FireClient(player, "Reward", result)
end

------------------------------------------------------------------------------------------
-- Session flow
------------------------------------------------------------------------------------------
function GymService:Enter(player: Player)
	if sessions[player] then
		return { Ok = false, Error = "You're already in the gym." }
	end
	local profile = self.Services.PlayerDataService:Get(player)
	local root = rootOf(player)
	if not profile or not root then
		return { Ok = false, Error = "Not ready yet." }
	end
	if Util.FlatDistance(root.Position, GymDefinitions.HubEntrance) > GymDefinitions.EnterRadius then
		return { Ok = false, Error = "Walk up to the gym's lift first." }
	end
	if self.Services.BossService:GetEncounter(player) then
		return { Ok = false, Error = "Finish your fight first." }
	end
	local busy, why = self.Services.DuelService:IsBusy(player)
	if busy then
		return { Ok = false, Error = why or "You're busy with a duel." }
	end
	if self.Services.PossessionService:IsPossessing(player) then
		return { Ok = false, Error = "Release your Nightmare first." }
	end
	local bay
	for i = 1, GymDefinitions.BayCount do
		if not bayOwner[i] then
			bay = i
			break
		end
	end
	if not bay then
		return { Ok = false, Error = "Every training bay is taken right now. Try again soon." }
	end
	local spawner = self.Services.NightmareSpawnService
	if not spawner:IsSummoned(player) or not spawner:GetNightmare(player) then
		spawner:SetSummoned(player, true)
	end
	bayOwner[bay] = player
	sessions[player] = {
		bay = bay,
		state = "Entering",
		enteredAt = os.clock(),
		trained = 0,
		count = 0,
		best = nil,
		recent = {},
		sinceRest = 0,
		restDue = random:NextInteger(GymDefinitions.RestEvery[1], GymDefinitions.RestEvery[2]),
	}
	return { Ok = true, Bay = bay }
end

-- Takes over the player's current Nightmare for the session's bay: suspends its AI,
-- places it at the lift and works out where it stands at the bag (and the bag's height).
function GymService:Possess(player: Player, session): boolean
	local brain = self.Services.NightmareAIService:GetBrain(player)
	if not brain or not brain.model.Parent then
		return false
	end
	if session.brain and session.brain ~= brain then
		session.brain.scripted = nil
	end
	session.brain = brain
	brain.scripted = true
	brain.queuedAbility = nil
	brain.nav:Stop()
	local model, root = brain.model, brain.root
	model:SetAttribute("GymBay", session.bay)

	-- step it out of the lift (the gym floor and the Forge are both at y = 1, so it keeps
	-- its standing height)
	local bayCF = GymDefinitions.BayCF(session.bay)
	local arrival = (GymDefinitions.ArrivalCF() * CFrame.new(session.bay <= 3 and -3 or 3, 0, -4)).Position
	local at = Vector3.new(arrival.X, root.Position.Y + 0.3, arrival.Z)
	local hallCenter = GymDefinitions.Origin.Position
	model:PivotTo(CFrame.lookAt(at, Vector3.new(hallCenter.X, at.Y, hallCenter.Z)))
	task.wait() -- let it settle onto the floor before measuring

	session.armed = hasArms(model)
	local reach, height
	if session.armed then
		reach, height = punchReach(model, root)
	end
	local mouth, mouthHeight = biteReach(model, root)
	if not reach then
		session.armed = false
		reach, height = mouth, mouthHeight
	end
	session.legLength, session.hipForward = kickingLeg(model, root)
	-- the bag hangs with its middle a touch below the strike height; the Nightmare stands
	-- so a straight strike sinks ~0.3 studs into the leather
	local bag = GymWorld.BuildBag(session.bay, height - 0.4)
	local bagPivot = bag and bag:GetAttribute("Pivot") or (bayCF * CFrame.new(GymDefinitions.BagOffset)).Position
	session.bagAt = Vector3.new(bagPivot.X, root.Position.Y, bagPivot.Z)
	-- measured in Studio: at this distance the cross / overhand sink ~0.6 into the leather,
	-- the jab and hook just meet it, the body shots land on its surface
	local stand = reach + GymDefinitions.Bag.Radius - 0.65
	session.standAt = session.bagAt + bayCF.LookVector * -stand
	session.biteAt = session.bagAt + bayCF.LookVector * -(mouth + GymDefinitions.Bag.Radius - 0.4)
	session.bayLook = bayCF.LookVector
	return true
end

-- Where the body has to stand for a routine to land: punching range, the mouth on the
-- leather for a bite, or each kick's own range (its Reach fraction of the leg).
function GymService:SpotFor(session, routine)
	if routine.Spot == "Bite" then
		return session.biteAt
	elseif routine.Legs and session.legLength then
		local distance = session.hipForward + session.legLength * (routine.Reach or 1) + GymDefinitions.Bag.Radius - 0.35
		return session.bagAt - session.bayLook * distance
	end
	return session.standAt
end

-- An ability from its own loadout, as a routine: its animation at its real timing (a
-- bite also holds for its clamp), from the range it lands at.
function GymService:AbilityRoutine(session)
	local brain = session.brain
	local options = {}
	for slot, id in brain.abilities do
		local def = AbilityDefinitions.Get(id)
		if def then
			table.insert(options, { Slot = slot, Def = def })
		end
	end
	if #options == 0 then
		return nil
	end
	local pick = options[random:NextInteger(1, #options)]
	local def = pick.Def
	return {
		Action = "Ability_" .. def.Id,
		Windup = def.Windup,
		Duration = def.Windup + def.Recovery + (def.Clamp and def.Clamp.Hold or 0) + 0.3,
		Spot = def.Motion == "Grip" and "Bite" or nil,
		Source = brain.model:GetAttribute(("Ability%dSource"):format(pick.Slot)) or "",
		Weight = 0,
	}
end

function GymService:Arrive(player: Player)
	local session = sessions[player]
	if not session or session.state ~= "Entering" then
		return { Ok = false }
	end
	local character = player.Character
	if not character or not character.Parent then
		return { Ok = false }
	end
	local bayCF = GymDefinitions.BayCF(session.bay)
	local handlerAt = bayCF * GymDefinitions.HandlerOffset
	-- the place streams: load the gym around the bay before moving them in
	pcall(player.RequestStreamAroundAsync, player, bayCF.Position, 3)
	character:PivotTo(CFrame.lookAt(handlerAt.Position, (bayCF * CFrame.new(GymDefinitions.BagOffset)).Position * Vector3.new(1, 0, 1) + Vector3.new(0, handlerAt.Position.Y, 0)))
	session.state = "Training"
	if not self:Possess(player, session) then
		self:Leave(player, true)
		return { Ok = false, Error = "Your Nightmare isn't here." }
	end
	session.startedAt = os.clock()
	session.lastTick = os.clock()
	session.carry = 0
	local profile = self.Services.PlayerDataService:Get(player)
	local _, speed = GymDefinitions.Multipliers(profile and profile.Gym.Boosts, os.time())
	session.nextRewardAt = os.clock() + GymDefinitions.RewardInterval / speed
	session.thread = task.spawn(self.RunTraining, self, player, session)
	labelBay(session.bay, player.DisplayName)
	countTraining()
	self:UpdateStatsWall()
	return { Ok = true, Summary = self:Summary(player) }
end

function GymService:Leave(player: Player, teleport: boolean)
	local session = sessions[player]
	if not session then
		return { Ok = false }
	end
	sessions[player] = nil
	if bayOwner[session.bay] == player then
		bayOwner[session.bay] = nil
	end
	local brain = session.brain
	if brain then
		brain.scripted = nil
		if brain.model.Parent then
			brain.model:SetAttribute("GymBay", nil)
			brain.humanoid:MoveTo(brain.root.Position)
			self.Services.NightmareAIService:StopFacing(brain)
		end
	end
	if session.thread and coroutine.status(session.thread) == "suspended" then
		pcall(task.cancel, session.thread)
	end
	GymWorld.BuildBag(session.bay) -- re-hang the bay's bag at its default height
	labelBay(session.bay, nil)
	local summary = {
		Ok = true,
		Time = math.floor(session.trained),
		Rewards = session.count,
		Best = session.best,
	}
	if teleport and session.state == "Training" then
		local character = player.Character
		if character and character.Parent then
			local exit = GymDefinitions.ExitCF()
			pcall(player.RequestStreamAroundAsync, player, exit.Position, 3)
			character:PivotTo(exit)
			self.Services.NightmareSpawnService:TeleportNightmare(player, exit * CFrame.new(5, -3, 3))
		end
	end
	countTraining()
	self:UpdateStatsWall()
	self.Services.PlayerDataService:SaveNow(player)
	return summary
end

function GymService:Buy(player: Player, boostId: string)
	local def = type(boostId) == "string" and GymDefinitions.Boosts[boostId]
	local profile = self.Services.PlayerDataService:Get(player)
	if not def or not profile then
		return { Ok = false, Error = "Unknown boost." }
	end
	if profile.Coins < def.Cost then
		return { Ok = false, Error = ("You need %d coins for %s."):format(def.Cost, def.Name) }
	end
	profile.Coins -= def.Cost
	local now = os.time()
	profile.Gym.Boosts[boostId] = math.max(now, profile.Gym.Boosts[boostId] or 0) + def.Duration
	-- a Haste boost bought mid-session brings the next reward forward too
	local session = sessions[player]
	if session and session.nextRewardAt and def.Speed then
		local remaining = session.nextRewardAt - os.clock()
		session.nextRewardAt = os.clock() + remaining / def.Speed
	end
	self.Services.GameAnalyticsService:Event(player, "GymBoost", boostId)
	self.Services.PlayerDataService:SaveNow(player)
	self.Services.NightmareBuildService:PushState(player)
	return { Ok = true, Summary = self:Summary(player) }
end

-- STUDIO ONLY (DevBridge): roll the next reward now, optionally forcing its tier, so the
-- reveals can be checked without waiting. Does nothing in a live game.
function GymService:DevRollNow(player: Player, tierId: string?)
	local session = sessions[player]
	if not RunService:IsStudio() or not session or session.state ~= "Training" then
		return false
	end
	session.devTier = tierId and GymDefinitions.Tiers[tierId] and tierId or nil
	session.nextRewardAt = os.clock()
	return true
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function GymService:Tick()
	local now = os.clock()
	for player, session in sessions do
		if session.state == "Entering" and now - session.enteredAt > 20 then
			self:Leave(player, false) -- the client never arrived
		elseif session.state == "Training" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid or humanoid.Health <= 0 then
				self:Leave(player, false)
			else
				-- the Nightmare was rebuilt (a save, a respawn): take the new one over too
				local brain = self.Services.NightmareAIService:GetBrain(player)
				if brain and brain ~= session.brain and not session.repossessing then
					session.repossessing = true
					task.spawn(function()
						if self:Possess(player, session) and sessions[player] == session then
							session.thread = task.spawn(self.RunTraining, self, player, session)
						end
						session.repossessing = nil
					end)
				end
				local dt = now - session.lastTick
				session.lastTick = now
				session.trained += dt
				session.carry += dt
				local profile = self.Services.PlayerDataService:Get(player)
				if profile and session.carry >= 1 then
					local whole = math.floor(session.carry)
					profile.Gym.TotalTime += whole
					session.carry -= whole
				end
				if now >= session.nextRewardAt then
					local _, speed = GymDefinitions.Multipliers(profile and profile.Gym.Boosts, os.time())
					session.nextRewardAt += GymDefinitions.RewardInterval / speed
					local ok, err = pcall(self.GrantReward, self, player, session)
					if not ok then
						warn("[GymService] reward failed:", err)
					end
				end
			end
		end
	end
end

function GymService:Start()
	local request = Net.Get("GymRequest")
	request.OnServerInvoke = function(player: Player, action, arg)
		if not self.Services.AntiExploitService:Allow(player, "GymRequest") then
			return { Ok = false, Error = "Slow down." }
		end
		if action == "Enter" then
			return self:Enter(player)
		elseif action == "Arrive" then
			return self:Arrive(player)
		elseif action == "Leave" then
			return self:Leave(player, true)
		elseif action == "Buy" then
			return self:Buy(player, arg)
		elseif action == "State" then
			return { Ok = true, Summary = self:Summary(player) }
		end
		return { Ok = false }
	end
	Players.PlayerRemoving:Connect(function(player)
		if sessions[player] then
			self:Leave(player, false)
		end
	end)
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated < 0.25 then
			return
		end
		accumulated = 0
		self:Tick()
	end)
	self:UpdateStatsWall()
end

return GymService
