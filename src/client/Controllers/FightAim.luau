--[[
	FightAim  (ModuleScript, client)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/FightAim

	EVERY BLOW CONNECTS. A clip's strikes are keyed on the guard's centre line, but every body and
	every opponent is a different size. So around each contact frame (a clip's Aim list:
	{ T, Arm = limb, At = "Head" | "Body" | "Legs" }) the striking limb is laid over the clip:
	  * it straightens fully (the elbow / knee opens right out)
	  * the whole limb points at the enemy's body, wherever that is
	  * if it would still fall short, the body drives forward the rest of the way
	Used for Nightmares and bosses (NightmareAnimator) and Handlers (HandlerAnimator). Nothing
	here affects play: hits are still the server's.

	Limbs: Left, Right (arms), LeftLeg, RightLeg, FrontLeft, FrontRight (a four-legged body's).

	Studio: workspace attribute FightAimLog = true prints how far each limb was from the body it
	hit, on its contact frame (negative: sunk in).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FightAim = {}

local RANGE = 11 -- studs round the striker to look for what it's hitting
local LEAD = 0.1 -- seconds before contact the limb starts straightening
local HOLD = 0.05 -- stays out this long after contact
local RELEASE = 0.1 -- then comes back to the clip over this long
local MAX_DRIVE = 2.4 -- studs the body may drive forward to close the last of the gap
local HANG = Vector3.new(0, -1, 0) -- which way a limb lies at rest in its joint's frame

-- which joints a limb is, on each kind of body: { limb joint, bend joint }
local CREATURE = {
	Left = { "Joint_LeftArm", "Sub_LeftArm_Fore" },
	Right = { "Joint_RightArm", "Sub_RightArm_Fore" },
	LeftLeg = { "Sub_Legs_L", "Knee_L" },
	RightLeg = { "Sub_Legs_R", "Knee_R" },
	FrontLeft = { "Sub_Legs_FL" },
	FrontRight = { "Sub_Legs_FR" },
}
local HANDLER = {
	Left = { "LeftShoulder", "LeftElbow", Sizes = { "LeftUpperArm", "LeftLowerArm", "LeftHand" } },
	Right = { "RightShoulder", "RightElbow", Sizes = { "RightUpperArm", "RightLowerArm", "RightHand" } },
	LeftLeg = { "LeftHip", "LeftKnee", Sizes = { "LeftUpperLeg", "LeftLowerLeg", "LeftFoot" } },
	RightLeg = { "RightHip", "RightKnee", Sizes = { "RightUpperLeg", "RightLowerLeg", "RightFoot" } },
}

-- A joint's two ends (avatars with Roblox's joint upgrade have AnimationConstraints, not Motor6Ds).
local function upper(joint): CFrame
	return joint:IsA("Motor6D") and joint.C0 or joint.Attachment0.CFrame
end
local function lower(joint): CFrame
	return joint:IsA("Motor6D") and joint.C1 or joint.Attachment1.CFrame
end
local function parentPart(joint): BasePart?
	return joint:IsA("Motor6D") and joint.Part0 or (joint.Attachment0 and joint.Attachment0.Parent)
end
local function childPart(joint): BasePart?
	return joint:IsA("Motor6D") and joint.Part1 or (joint.Attachment1 and joint.Attachment1.Parent)
end

-- How far through the strike's window we are: 0 (the clip alone) .. 1 (fully out, on target)
local function weightAt(strike, t: number): number
	local lead = strike.Lead or LEAD
	local from = t - (strike.T - lead)
	if from <= 0 then
		return 0
	elseif from < lead then
		local k = from / lead
		return k * k * (3 - 2 * k)
	end
	local after = t - (strike.T + HOLD)
	if after <= 0 then
		return 1
	elseif after < RELEASE then
		local k = 1 - after / RELEASE
		return k * k * (3 - 2 * k)
	end
	return 0
end

local function ownerOf(model: Model): Player?
	local id = model:GetAttribute("OwnerUserId")
	if id then
		return Players:GetPlayerByUserId(id)
	end
	return Players:GetPlayerFromCharacter(model)
end

-- What it's hitting: the nearest fighter in front of it that isn't on its own side.
local function targetFor(model: Model, root: BasePart): (Model?, BasePart?)
	local owner = ownerOf(model)
	local monster = owner == nil and CollectionService:HasTag(model, "Enemy")
	local reachBonus = math.max(root.Size.X, root.Size.Z) / 2 + (monster and 10 or 0)
	local best, bestRoot, bestScore = nil, nil, math.huge
	local seen = {}
	local function consider(other: Model)
		if other == model or seen[other] then
			return
		end
		seen[other] = true
		local otherOwner = ownerOf(other)
		if owner and otherOwner == owner then
			return
		end
		local otherIsMonster = CollectionService:HasTag(other, "Enemy")
		if monster and otherIsMonster then
			return
		end
		local otherRoot = other:FindFirstChild("HumanoidRootPart")
		local humanoid = other:FindFirstChildOfClass("Humanoid")
		if not otherRoot or not humanoid or humanoid.Health <= 0 then
			return
		end
		local offset = otherRoot.Position - root.Position
		local reach = RANGE + reachBonus + math.max(otherRoot.Size.X, otherRoot.Size.Z) / 2
		if math.abs(offset.Y) > reach or Vector3.new(offset.X, 0, offset.Z).Magnitude > reach then
			return
		end
		local facing = offset.Magnitude > 0.01 and offset.Unit:Dot(root.CFrame.LookVector) or 1
		if facing < 0.05 then
			return
		end
		-- (a player's side goes for monsters first, other players only if nothing else is there)
		local score = offset.Magnitude * (2 - facing) + ((otherIsMonster or monster) and 0 or 6)
		if score < bestScore then
			best, bestRoot, bestScore = other, otherRoot, score
		end
	end
	for _, tag in { "Enemy", "Nightmare" } do
		for _, other in CollectionService:GetTagged(tag) do
			consider(other)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			consider(player.Character)
		end
	end
	return best, bestRoot
end

-- The point on them the blow is going for, at a height the limb can get to (a boss's head is out
-- of reach: it hits what it can reach).
local function pointOn(target: Model, targetRoot: BasePart, at: string?, joint: Vector3, length: number): Vector3
	local point = targetRoot.Position
	if at == "Legs" then
		point -= Vector3.new(0, targetRoot.Size.Y * 0.5 + 0.5, 0)
	elseif at ~= "Body" then
		local head = target:FindFirstChild("Head") or target:FindFirstChild("Head_Root")
		point = head and head:IsA("BasePart") and head.Position or (targetRoot.Position + Vector3.new(0, targetRoot.Size.Y * 0.3, 0))
	end
	return Vector3.new(point.X, math.clamp(point.Y, joint.Y - length * 0.95, joint.Y + length * 0.8), point.Z)
end

-- Everything hanging off a limb, followed through its welds and joints from the end away from
-- the body (measured at rest: the parts of a body the server moves).
local function measure(model: Model, joint): number
	local neighbours = {}
	local function link(a, b)
		if a and b then
			neighbours[a] = neighbours[a] or {}
			neighbours[b] = neighbours[b] or {}
			table.insert(neighbours[a], b)
			table.insert(neighbours[b], a)
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			link(d.Part0, d.Part1)
		end
	end
	local start, base = childPart(joint), parentPart(joint)
	if not start or not base then
		return 0
	end
	local pivot = (base.CFrame * upper(joint)).Position
	local seen, stack, longest = { [base] = true, [start] = true }, { start }, 0
	while #stack > 0 do
		local part = table.remove(stack)
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					longest = math.max(longest, (part.CFrame:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz)) - pivot).Magnitude)
				end
			end
		end
		for _, other in neighbours[part] or {} do
			if not seen[other] then
				seen[other] = true
				table.insert(stack, other)
			end
		end
	end
	return longest
end

-- The rig, built once per body: `motors` is its joints by name.
function FightAim.Rig(model: Model, motors, isHandler: boolean?)
	return { Model = model, Motors = motors, Root = model:FindFirstChild("HumanoidRootPart"), Names = isHandler and HANDLER or CREATURE, Limbs = {}, Found = {} }
end

local function limbOf(rig, name: string)
	if rig.Limbs[name] ~= nil then
		return rig.Limbs[name]
	end
	local names = rig.Names[name]
	local joint = names and rig.Motors[names[1]]
	if not joint or not rig.Root then
		rig.Limbs[name] = false
		return false
	end
	-- the chain of joints from the root out to where this limb hangs
	local chain, part, guard = {}, parentPart(joint), 0
	while part and part ~= rig.Root and guard < 8 do
		guard += 1
		local up
		for _, other in rig.Motors do
			if childPart(other) == part then
				up = other
				break
			end
		end
		if not up then
			break
		end
		table.insert(chain, 1, up)
		part = parentPart(up)
	end
	local length = 0
	if names.Sizes then
		for _, partName in names.Sizes do
			local piece = rig.Model:FindFirstChild(partName)
			length += piece and piece.Size.Y or 0
		end
	else
		length = measure(rig.Model, joint)
	end
	local limb = { Joint = joint, Bend = names[2] and rig.Motors[names[2]] or nil, Chain = chain, Length = length }
	rig.Limbs[name] = limb
	return limb
end

-- Lays the clip's strikes over the joints it has just set.
function FightAim.Apply(def, t: number, rig)
	for index, strike in def.Aim do
		local weight = weightAt(strike, t)
		local limb = weight > 0 and limbOf(rig, strike.Arm)
		if limb then
			-- find who it's hitting once per strike, as it starts
			local found = rig.Found[index]
			if not found or found.Def ~= def then
				local target, targetRoot = targetFor(rig.Model, rig.Root)
				found = { Def = def, Target = target, Root = targetRoot }
				rig.Found[index] = found
			end
			if limb.Bend then
				limb.Bend.Transform = limb.Bend.Transform:Lerp(CFrame.identity, weight)
			end
			if found.Root and found.Root.Parent then
				local frame = rig.Root.CFrame
				for _, joint in limb.Chain do
					frame = frame * upper(joint) * joint.Transform * lower(joint):Inverse()
				end
				local pivot = frame * upper(limb.Joint)
				local point = pointOn(found.Target, found.Root, strike.At, pivot.Position, limb.Length)
				local along = point - pivot.Position
				local radius = math.max(found.Root.Size.X, found.Root.Size.Z) / 2
				local gap = along.Magnitude - limb.Length - radius * 0.6
				-- (nowhere near it: the blow isn't for them; the clip's own swing stands)
				if along.Magnitude > 0.1 and gap <= MAX_DRIVE + 3 then
					local direction = pivot:VectorToObjectSpace(along.Unit)
					if direction.Y < 0.999 then
						limb.Joint.Transform = limb.Joint.Transform:Lerp(CFrame.fromRotationBetweenVectors(HANG, direction), weight)
					end
					-- still short of the body? Everything drives forward the rest of the way.
					local drive = 0
					local base = limb.Chain[1]
					if gap > 0 and base then
						drive = math.min(gap, MAX_DRIVE) * weight
						local flat = Vector3.new(along.X, 0, along.Z)
						if flat.Magnitude > 0.01 then
							base.Transform = CFrame.new((rig.Root.CFrame * upper(base)):VectorToObjectSpace(flat.Unit * drive)) * base.Transform
						end
					end
					if RunService:IsStudio() and Workspace:GetAttribute("FightAimLog") and t >= strike.T and not found.Logged then
						found.Logged = true
						print(("[FightAim] %s %s -> %s: %.2f studs from the body (drove %.2f, limb %.1f)"):format(rig.Model.Name, strike.Arm, tostring(found.Target), gap - drive, drive, limb.Length))
					end
				end
			end
		elseif t > strike.T + HOLD + RELEASE then
			rig.Found[index] = nil
		end
	end
end

return FightAim
