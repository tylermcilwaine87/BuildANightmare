--[[
	NightmareAssembler  (ModuleScript)
	Location: ReplicatedStorage/Shared/NightmareAssembler

	Turns build DATA into a physical Model. Used by:
	  * the server (NightmareSpawnService) to create the real, fighting Nightmare
	  * the client (WorkshopController) to render the live preview — same code, so the
	    preview always matches what spawns.

	RIG LAYOUT
	  HumanoidRootPart   invisible, fixed-size hitbox from the archetype. The ONLY part that
	                     collides or can be hit.
	  Core_Root          helper part, Motor6D "Joint_Core" from the root
	  <Slot>_Root        helper part at each socket, Motor6D "Joint_<Slot>" from Core_Root
	  <Slot>_<Group>     sub-joint helpers (legs, wings), Motor6D "Sub_<Slot>_<Group>"
	  <Slot>_<n>         visual pieces, welded to their joint helper. Massless, no
	                     collision, no queries, no touch.

	Every joint pivots exactly at its socket, so the client-side procedural animator can
	swing arms from the shoulder, legs from the hip, etc., for ANY part combination.

	Build(build, opts) -> model, info
	  opts.Preview = true  -> all parts anchored (for ViewportFrames)
	  info = { HipHeight, Archetype, Stats, HitboxSize, SlotRoots, Lowest }
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = script.Parent
local SlotDefinitions = require(Shared.SlotDefinitions)
local PartDefinitions = require(Shared.PartDefinitions)
local PartMeshes = require(Shared.PartMeshes)
local ArchetypeDefinitions = require(Shared.ArchetypeDefinitions)
local StatCalculator = require(Shared.StatCalculator)
local MutationDefinitions = require(Shared.MutationDefinitions)

local NightmareAssembler = {}

-- Mutated parts: tint/material/transparency on every visual piece, plus a few sparkles
-- around the joint (not in previews: ViewportFrames don't render particles).
local function applyMutation(mutationId: string?, pieces, slotRoot: BasePart, preview: boolean)
	local mutation = MutationDefinitions.Get(mutationId)
	if not mutation then
		return
	end
	local visual = mutation.Visual or {}
	for _, part in pieces do
		if visual.Tint then
			part.Color = part.Color:Lerp(visual.Tint, visual.TintAlpha or 0.5)
		end
		if visual.Material and part.Material ~= Enum.Material.Neon then
			part.Material = visual.Material
		end
		if visual.Transparency then
			part.Transparency = math.max(part.Transparency, visual.Transparency)
		end
	end
	if not preview then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Name = "MutationSparkle"
		sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color = ColorSequence.new(mutation.Color)
		sparkle.LightEmission = 1
		sparkle.Rate = 3
		sparkle.Lifetime = NumberRange.new(0.6, 1.1)
		sparkle.Speed = NumberRange.new(0.5, 1.5)
		sparkle.SpreadAngle = Vector2.new(180, 180)
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Parent = slotRoot
	end
end

local function mutationScale(build, slot: string): number
	local mutation = MutationDefinitions.Get(MutationDefinitions.ForSlot(build, slot))
	return mutation and mutation.Visual and mutation.Visual.Scale or 1
end

local SHAPES = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function angles(rotDegrees: Vector3): CFrame
	return CFrame.Angles(math.rad(rotDegrees.X), math.rad(rotDegrees.Y), math.rad(rotDegrees.Z))
end

local function mirrorPos(v: Vector3): Vector3
	return Vector3.new(-v.X, v.Y, v.Z)
end

local function mirrorRot(v: Vector3): Vector3
	return Vector3.new(v.X, -v.Y, -v.Z)
end

local function styleVisual(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

local function newHelper(name: string, cframe: CFrame, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.CastShadow = false
	p.CFrame = cframe
	styleVisual(p)
	p.Parent = parent
	return p
end

local function weld(part0: BasePart, part1: BasePart)
	local w = Instance.new("Weld")
	w.Part0 = part0
	w.Part1 = part1
	w.C0 = part0.CFrame:ToObjectSpace(part1.CFrame)
	w.C1 = CFrame.identity
	w.Parent = part1
end

local function motor(name: string, part0: BasePart, part1: BasePart, jointWorld: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = part0.CFrame:ToObjectSpace(jointWorld)
	m.C1 = part1.CFrame:ToObjectSpace(jointWorld)
	m.Parent = part0
	return m
end

local function readAdjust(build, slot: string)
	local a = build.Adjust and build.Adjust[slot]
	return {
		Scale = (a and a.Scale) or 1,
		Yaw = (a and a.Yaw) or 0,
		Pitch = (a and a.Pitch) or 0,
	}
end

local function findAssetOverride(def, mirror: boolean): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("PartModels")
	if not folder then
		return nil
	end
	local name = def.ModelAsset
	if mirror and folder:FindFirstChild(name .. "_Left") then
		name = name .. "_Left"
	end
	local asset = folder:FindFirstChild(name)
	if asset and asset:IsA("Model") then
		return asset
	end
	return nil
end

-- Studio's 3D importer turns a mesh half round (it takes +Z as an OBJ's front; the forge
-- sculpts facing -Z, like every part here), so each mesh is turned back as it is placed.
local IMPORT_TURN = CFrame.Angles(0, math.pi, 0)

-- The sculpted mesh templates (Shared/Meshes/PartMeshes, made by tools/MeshForge), or nil.
local function meshTemplates(): Instance?
	local meshes = Shared:FindFirstChild("Meshes")
	return meshes and meshes:FindFirstChild("PartMeshes")
end

-- A part's sculpted meshes, if every template it needs is there (else nil: use the blocks).
-- A mirrored (left) arm uses each mesh's mirror image, <Mesh>_L.
local function sculptedMeshes(def, mirror: boolean)
	local entries = PartMeshes[def.Id]
	local templates = entries and meshTemplates()
	if not templates then
		return nil
	end
	local list = {}
	for _, entry in entries do
		local template = mirror and templates:FindFirstChild(entry.Mesh .. "_L") or templates:FindFirstChild(entry.Mesh)
		if not (template and template:IsA("MeshPart")) then
			return nil
		end
		table.insert(list, { Entry = entry, Template = template })
	end
	return list
end

-- Builds one part's geometry, attached to slotRoot whose world frame is frameCF.
local function buildSlotGeometry(model: Model, slot: string, def, slotRoot: BasePart, frameCF: CFrame, scale: number, mirror: boolean, visualParts)
	-- 1) Real art override from ReplicatedStorage/Assets/PartModels
	local asset = findAssetOverride(def, mirror)
	if asset then
		local clone = asset:Clone()
		clone.Name = slot .. "_Asset"
		if scale ~= 1 then
			clone:ScaleTo(clone:GetScale() * scale)
		end
		clone:PivotTo(frameCF)
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				styleVisual(d)
				weld(slotRoot, d)
				table.insert(visualParts, d)
			end
		end
		clone.Parent = model
		return
	end

	-- 2) The sculpted meshes, or the block pieces from the definition, on the same joints
	local groupRoots, groupFrames = {}, {}
	if def.Groups then
		for groupName, group in def.Groups do
			local pivot, rot = group.Pivot, group.Rot or Vector3.zero
			if mirror then
				pivot, rot = mirrorPos(pivot), mirrorRot(rot)
			end
			local groupCF = frameCF * CFrame.new(pivot * scale) * angles(rot)
			local groupRoot = newHelper(slot .. "_" .. groupName, groupCF, model)
			motor("Sub_" .. slot .. "_" .. groupName, slotRoot, groupRoot, groupCF)
			groupRoots[groupName] = groupRoot
			groupFrames[groupName] = groupCF
		end
	end

	local sculpted = sculptedMeshes(def, mirror)
	if sculpted then
		for index, item in sculpted do
			local entry = item.Entry
			local baseCF = (entry.Group and groupFrames[entry.Group]) or frameCF
			local attachTo = (entry.Group and groupRoots[entry.Group]) or slotRoot
			local part = item.Template:Clone()
			part.Name = slot .. "_" .. index
			part.Size = entry.Size * scale
			part.CFrame = baseCF * CFrame.new((mirror and mirrorPos(entry.Pos) or entry.Pos) * scale) * IMPORT_TURN
			part.Color = entry.Color
			part.Material = entry.Material
			part.Transparency = entry.Transparency or 0
			part.CastShadow = part.Transparency < 0.5
			styleVisual(part)
			part.Parent = model
			weld(attachTo, part)
			table.insert(visualParts, part)
		end
		return
	end

	for index, spec in def.Visual do
		local baseCF = (spec.Group and groupFrames[spec.Group]) or frameCF
		local attachTo = (spec.Group and groupRoots[spec.Group]) or slotRoot
		local pos, rot = spec.Pos, spec.Rot or Vector3.zero
		if mirror then
			pos, rot = mirrorPos(pos), mirrorRot(rot)
		end

		local part: BasePart
		if spec.Shape == "Wedge" then
			part = Instance.new("WedgePart")
		else
			local p = Instance.new("Part")
			p.Shape = SHAPES[spec.Shape] or Enum.PartType.Block
			part = p
		end
		part.Name = slot .. "_" .. index
		part.Size = spec.Size * scale
		part.CFrame = baseCF * CFrame.new(pos * scale) * angles(rot)
		part.Color = spec.Color
		part.Material = spec.Material
		part.Transparency = spec.Transparency or 0
		styleVisual(part)
		part.Parent = model
		weld(attachTo, part)
		table.insert(visualParts, part)
	end
end

function NightmareAssembler.Build(build, opts)
	opts = opts or {}
	local stats, archetypeName = StatCalculator.Compute(build)
	local archetype = ArchetypeDefinitions[archetypeName]

	local coreDef = PartDefinitions.Get(build.Parts.Core)
	assert(coreDef, "Cannot assemble a Nightmare without a Core")

	local model = Instance.new("Model")
	model.Name = opts.Name or "Nightmare"

	-- Fixed hitbox root, built at the origin.
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = archetype.HitboxSize
	root.Transparency = 1
	root.CanCollide = true
	root.CanQuery = true
	root.CanTouch = true
	root.CastShadow = false
	root.CFrame = CFrame.identity
	root.Parent = model
	model.PrimaryPart = root

	local visualParts = {}
	local slotRoots = {}

	-- Core
	local coreAdjust = readAdjust(build, "Core")
	local coreCF = CFrame.new(0, archetype.CoreHeight, 0) * CFrame.Angles(math.rad(coreAdjust.Pitch), math.rad(coreAdjust.Yaw), 0)
	local coreRoot = newHelper("Core_Root", coreCF, model)
	motor("Joint_Core", root, coreRoot, coreCF)
	slotRoots.Core = coreRoot
	local corePieces = {}
	buildSlotGeometry(model, "Core", coreDef, coreRoot, coreCF, coreAdjust.Scale * mutationScale(build, "Core"), false, corePieces)
	applyMutation(MutationDefinitions.ForSlot(build, "Core"), corePieces, coreRoot, opts.Preview == true)
	table.move(corePieces, 1, #corePieces, #visualParts + 1, visualParts)

	-- Every other slot plugs into a core socket.
	for _, slot in SlotDefinitions.Order do
		if slot == "Core" then
			continue
		end
		local def = PartDefinitions.Get(build.Parts[slot])
		local socket = coreDef.Sockets[slot]
		if not def or not socket then
			continue
		end
		local info = SlotDefinitions.Info[slot]
		local mirror = info.Mirror == true
		local adjust = readAdjust(build, slot)
		local yaw = mirror and -adjust.Yaw or adjust.Yaw
		local jointCF = coreCF * CFrame.new(socket * coreAdjust.Scale) * CFrame.Angles(math.rad(adjust.Pitch), math.rad(yaw), 0)

		local slotRoot = newHelper(slot .. "_Root", jointCF, model)
		motor("Joint_" .. slot, coreRoot, slotRoot, jointCF)
		slotRoots[slot] = slotRoot
		local pieces = {}
		buildSlotGeometry(model, slot, def, slotRoot, jointCF, adjust.Scale * mutationScale(build, slot), mirror, pieces)
		applyMutation(MutationDefinitions.ForSlot(build, slot), pieces, slotRoot, opts.Preview == true)
		table.move(pieces, 1, #pieces, #visualParts + 1, visualParts)
	end

	-- Hip height: lift the hitbox so the lowest visual part rests on the ground.
	local lowest = 0
	for _, part in visualParts do
		local cf, half = part.CFrame, part.Size / 2
		local extentY = math.abs(cf.RightVector.Y) * half.X + math.abs(cf.UpVector.Y) * half.Y + math.abs(cf.LookVector.Y) * half.Z
		lowest = math.min(lowest, cf.Position.Y - extentY)
	end
	local hipHeight = math.max(-lowest - archetype.HitboxSize.Y / 2, archetype.MinHipHeight) + archetype.HoverHeight

	if opts.Preview then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end

	return model, {
		HipHeight = hipHeight,
		Archetype = archetypeName,
		Stats = stats,
		HitboxSize = archetype.HitboxSize,
		SlotRoots = slotRoots,
		Lowest = lowest,
	}
end

return NightmareAssembler
