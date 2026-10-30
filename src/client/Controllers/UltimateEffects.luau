--[[
	UltimateEffects  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/UltimateEffects

	The look of every Ultimate (client only; nothing here affects play), through the same three
	ways in as AbilityEffects, whose building blocks it uses:
	  * "FX_<Name>" markers on the clip (NightmarePoses "Ultimate_<Id>"), for what the body does
	  * WorldFX "AbilityFX" from the server, for what depends on the fight (where a wave started,
	    where a bomb is going, where the well opened)
	  * landed hits (CombatFeedback "Damage", Source "Ultimate:<name>")
	Respects the Impact effects setting through the same `amount`.
]]

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local AbilityEffects = require(script.Parent:WaitForChild("AbilityEffects"))

local UltimateEffects = {}

local controllers
local KIT = AbilityEffects.Kit
local EFFECTS = AbilityEffects.Effects
local KINDS = AbilityEffects.Kinds
local CONTACT = AbilityEffects.Contact
local TEX, COLORS = KIT.TEX, KIT.COLORS
local amount, newPart, particles, emitterOn, pieces, ring, flash = KIT.amount, KIT.newPart, KIT.particles, KIT.emitterOn, KIT.pieces, KIT.ring, KIT.flash
local bolt, rope, floorBelow, floorMark, rootOf, slotParts, limbTip = KIT.bolt, KIT.rope, KIT.floorBelow, KIT.floorMark, KIT.rootOf, KIT.slotParts, KIT.limbTip
local groundUnder, play, shake, isMine = KIT.groundUnder, KIT.play, KIT.shake, KIT.isMine

local WOOD = Color3.fromRGB(122, 88, 56)
local WOOD_DARK = Color3.fromRGB(78, 54, 34)
local GLARE = Color3.fromRGB(165, 60, 255)
local GLARE_CORE = Color3.fromRGB(240, 225, 255)
local SCRAP = Color3.fromRGB(70, 62, 58)
local SMOKE = Color3.fromRGB(60, 54, 52)
local SMOKE_FADE = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })

------------------------------------------------------------------------------------------
-- Shared pieces
------------------------------------------------------------------------------------------
local function tween(part: Instance, time: number, props, style, direction)
	local t = TweenService:Create(part, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

-- Runs `step(t)` every frame until it returns true (or the model it's tied to has gone).
local function everyFrame(step, model: Instance?)
	local start = os.clock()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local ok, finished = pcall(step, os.clock() - start)
		if not ok or finished or (model and not model.Parent) then
			connection:Disconnect()
			if not ok then
				warn("[UltimateEffects] " .. tostring(finished))
			elseif not finished then
				pcall(step, math.huge)
			end
		end
	end)
end

local function coreCentre(model: Model): (Vector3?, number)
	local list = slotParts(model, "Core")
	local sum, biggest = Vector3.zero, 0
	for _, part in list do
		sum += part.Position
		biggest = math.max(biggest, part.Size.X, part.Size.Y, part.Size.Z)
	end
	if #list == 0 then
		local root = rootOf(model)
		return root and root.Position, root and root.Size.Y or 2
	end
	return sum / #list, biggest
end

-- Cracks running out over the floor from `at`, glowing if `color` is given.
local function cracks(at: Vector3, count: number, length: number, color: Color3?, time: number?)
	time = time or 2.2
	for i = 1, amount(count) do
		local angle = (i / count) * math.pi * 2 + math.random() * 0.5
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from = at
		local reach = length * (0.7 + math.random() * 0.5)
		for step = 1, 3 do
			local to = from + (direction + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.7).Unit * (reach / 3)
			local width = 0.22 - step * 0.04
			local crack = newPart({ Size = Vector3.new(width, 0.05, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to) + Vector3.new(0, 0.05, 0), Color = Color3.fromRGB(20, 16, 14), Material = Enum.Material.SmoothPlastic })
			task.delay(time * 0.7, function()
				if crack.Parent then
					tween(crack, time * 0.3, { Transparency = 1 })
				end
			end)
			Debris:AddItem(crack, time + 0.05)
			if color then
				local glow = newPart({ Size = Vector3.new(width * 0.5, 0.06, (to - from).Magnitude), CFrame = crack.CFrame + Vector3.new(0, 0.02, 0), Color = color, Material = Enum.Material.Neon, Transparency = 0.1 })
				tween(glow, time * 0.6, { Transparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
				Debris:AddItem(glow, time * 0.6 + 0.05)
			end
			from = to
		end
	end
end

-- One crystal on the floor: a shaft with a point on it, rising out of the ground in `rise`
-- seconds. Returns its parts.
local function crystal(base: Vector3, height: number, width: number, lean: Vector3, color: Color3, rise: number)
	local tipHeight = width * 1.3
	local up = (Vector3.yAxis + lean).Unit
	local frame = CFrame.fromRotationBetweenVectors(Vector3.yAxis, up) * CFrame.Angles(0, math.random() * 6, 0) + base
	local list = {}
	local function place(part: BasePart, final: CFrame)
		part.CFrame = final - up * (height + tipHeight + 0.5)
		tween(part, rise, { CFrame = final }, Enum.EasingStyle.Back)
		table.insert(list, part)
	end
	place(newPart({ Size = Vector3.new(width, height, width), Color = color, Material = Enum.Material.Glass, Transparency = 0.2 }), frame * CFrame.new(0, height / 2, 0))
	local tip = frame * CFrame.new(0, height + tipHeight / 2, 0)
	for side = 1, 2 do
		local wedge = newPart({ Size = Vector3.new(width, tipHeight, width / 2), Color = color, Material = Enum.Material.Glass, Transparency = 0.2 }, "WedgePart")
		place(wedge, side == 1 and tip * CFrame.new(0, 0, -width / 4) or tip * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0))
	end
	-- (light caught inside it)
	place(newPart({ Size = Vector3.new(width * 0.22, height * 0.85, width * 0.22), Color = Color3.fromRGB(225, 240, 255), Material = Enum.Material.Neon, Transparency = 0.25 }), frame * CFrame.new(0, height * 0.45, 0))
	return list
end

local function shatterCrystal(list, big: boolean)
	for i, part in list do
		if part.Parent then
			if i == 1 then
				pieces(part.Position, Vector3.yAxis, { Count = big and 16 or 8, Colors = { COLORS.Crystal, COLORS.CrystalBlue, COLORS.Frost }, Material = Enum.Material.Glass, Size = big and 0.5 or 0.3, Speed = big and 26 or 18, Spread = 2.6, Life = 0.8, Gravity = 45 })
			end
			part:Destroy()
		end
	end
end

-- A blast on the floor: the shared base of everything that goes off when it lands.
local function blast(at: Vector3, radius: number, big: boolean?)
	flash(at + Vector3.new(0, 1, 0), radius * (big and 2.2 or 1.6), COLORS.FireCore, 0.28)
	ring(at + Vector3.new(0, 0.25, 0), radius * 1.15, COLORS.Fire, { Time = 0.35, Thickness = 0.4 })
	particles(at + Vector3.new(0, 1, 0), { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 2.4, Size2 = 0.6, Speed = radius * 3, Life = 0.5, Count = big and 34 or 20, Light = 1, Drag = 4 })
	particles(at + Vector3.new(0, 1.5, 0), { Color = SMOKE, Size = 2.5, Size2 = 6, Speed = radius * 1.6, Life = 1.1, Count = big and 16 or 9, Drag = 3, Accel = Vector3.new(0, 5, 0), Transparency = SMOKE_FADE })
end

------------------------------------------------------------------------------------------
-- SPLINTER STORM
------------------------------------------------------------------------------------------
local crates = setmetatable({}, { __mode = "k" })

local function showCore(model: Model, visible: boolean)
	for _, part in slotParts(model, "Core") do
		part.LocalTransparencyModifier = visible and 0 or 1
	end
end

function EFFECTS.CrateStrain(model)
	local at = coreCentre(model)
	if at then
		pieces(at, Vector3.yAxis, { Count = 5, Colors = { WOOD, WOOD_DARK }, Material = Enum.Material.Wood, Size = 0.12, Stretch = 4, Speed = 9, Spread = 3, Life = 0.5 })
		particles(at, { Color = Color3.fromRGB(150, 125, 95), Size = 0.7, Size2 = 2, Speed = 4, Life = 0.7, Count = 6, Drag = 2 })
	end
end

-- The crate comes apart: the planks of its own body fly out and hang round it, turning, with
-- only dark showing where it was, until FX_CrateGather (or a moment later, whatever happens).
function EFFECTS.CrateBurst(model)
	local at, size = coreCentre(model)
	if not at then
		return
	end
	local old = crates[model]
	if old then
		old.Finish()
	end
	local list = slotParts(model, "Core")
	local color = list[1] and list[1].Color or WOOD
	local radius = math.clamp(size * 1.6, 3, 7)
	local planks = {}
	local count = amount(14)
	for i = 1, count do
		local y = 1 - (i - 0.5) / count * 2
		local a = i * 2.39996
		local flat = math.sqrt(1 - y * y)
		local direction = Vector3.new(math.cos(a) * flat, y * 0.8, math.sin(a) * flat)
		local scale = math.clamp(size / 2.5, 0.7, 1.8)
		table.insert(planks, {
			Part = newPart({ Size = Vector3.new(0.9, 0.16, 1.5 + math.random() * 1.1) * scale, CFrame = CFrame.new(at), Color = i % 3 == 0 and WOOD_DARK or color, Material = Enum.Material.WoodPlanks }),
			Direction = direction,
			Spin = Vector3.new(math.random() * 6 - 3, math.random() * 6 - 3, math.random() * 6 - 3),
			Reach = radius * (0.7 + math.random() * 0.5),
		})
	end
	if count > 0 then
		showCore(model, false)
	end
	-- (what's inside it)
	local inside = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.7, CFrame = CFrame.new(at), Color = Color3.fromRGB(14, 8, 10), Material = Enum.Material.SmoothPlastic, Transparency = count > 0 and 0.05 or 1 })
	local state = { Gather = nil }
	local closed = false
	function state.Finish()
		if closed then
			return
		end
		closed = true
		for _, plank in planks do
			plank.Part:Destroy()
		end
		inside:Destroy()
		if model.Parent then
			showCore(model, true)
		end
		if crates[model] == state then
			crates[model] = nil
		end
	end
	crates[model] = state
	everyFrame(function(t)
		if closed then
			return true
		end
		local centre = coreCentre(model)
		if t == math.huge or not centre then
			state.Finish()
			return true
		end
		if not state.Gather and (state.GatherNow or t > 0.75) then
			state.Gather = t
		end
		local out = 1 - (1 - math.min(t / 0.16, 1)) ^ 3
		local back = state.Gather and math.min((t - state.Gather) / 0.26, 1) or 0
		local reach = out * (1 - back * back)
		local turn = CFrame.Angles(0, t * 3.2, 0)
		for _, plank in planks do
			local p = centre + turn:VectorToWorldSpace(plank.Direction) * plank.Reach * reach
			plank.Part.CFrame = CFrame.new(p) * CFrame.Angles(plank.Spin.X * t, plank.Spin.Y * t, plank.Spin.Z * t)
		end
		inside.CFrame = CFrame.new(centre)
		if back >= 1 then
			state.Finish()
			return true
		end
		return false
	end, model)
	particles(at, { Color = Color3.fromRGB(150, 125, 95), Size = 1.5, Size2 = 4, Speed = 16, Life = 0.7, Count = 14, Drag = 4 })
	shake(model, 0.25, 0.25, 22)
	if isMine(model) then
		controllers.EffectsController:ImpactPunch(0.6)
	end
end

function EFFECTS.CrateGather(model)
	local state = crates[model]
	if state then
		state.GatherNow = true
		play("WoodCreak", rootOf(model) and rootOf(model).Position)
	end
end

-- The stakes: driven flat out from the body across the floor, sticking where they land.
function KINDS.SplinterBurst(data)
	local center, radius = data.Position, math.clamp(tonumber(data.Radius) or 10, 2, 30)
	if typeof(center) ~= "Vector3" then
		return
	end
	local size = tonumber(data.Size) or 1
	play("WoodBreak", center)
	local count = amount(18 + size * 4)
	for i = 1, count do
		local angle = i / count * math.pi * 2 + math.random() * 0.2
		local direction = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local from = center + Vector3.new(0, 2.2 + math.random() * 1.5, 0) + direction * 1.2
		local land = center + direction * radius * (0.55 + math.random() * 0.55) + Vector3.new(0, 0.3, 0)
		local stake = newPart({ Size = Vector3.new(0.22, 0.22, 1.8 + math.random()), CFrame = CFrame.lookAt(from, land), Color = i % 2 == 0 and WOOD or WOOD_DARK, Material = Enum.Material.Wood })
		local time = 0.13 + math.random() * 0.09
		-- (driven in at the end of its flight, tail up)
		tween(stake, time, { CFrame = CFrame.lookAt(land, land + (land - from).Unit) }, Enum.EasingStyle.Linear)
		task.delay(time + 0.9 + math.random() * 0.4, function()
			if stake.Parent then
				tween(stake, 0.3, { Transparency = 1 })
			end
		end)
		Debris:AddItem(stake, time + 1.7)
	end
	local wood = floorBelow(center + Vector3.new(0, 1, 0))
	if wood then
		ring(wood.Position + Vector3.new(0, 0.2, 0), radius * 0.9, Color3.fromRGB(150, 125, 95), { Time = 0.35, Material = Enum.Material.SmoothPlastic, Transparency = 0.45, Thickness = 0.15 })
	end
	particles(center + Vector3.new(0, 1, 0), { Color = Color3.fromRGB(150, 125, 95), Size = 1.5, Size2 = 3.5, Speed = radius * 1.6, Life = 0.6, Count = 12, Drag = 4 })
end

CONTACT["Ultimate:SPLINTER STORM"] = function(at, dir)
	pieces(at, dir or Vector3.yAxis, { Count = 9, Colors = { WOOD, WOOD_DARK }, Material = Enum.Material.Wood, Size = 0.14, Stretch = 6, Speed = 16, Life = 0.5 })
	play("Stab", at)
end

------------------------------------------------------------------------------------------
-- THOUSAND-EYE GLARE
------------------------------------------------------------------------------------------
local glares = setmetatable({}, { __mode = "k" })

local WORLD_PARAMS = RaycastParams.new()
WORLD_PARAMS.FilterType = Enum.RaycastFilterType.Exclude
local function worldIgnore()
	local ignore = { Workspace:FindFirstChild("AbilityEffects") }
	for _, tag in { "Nightmare", "Enemy" } do
		for _, model in CollectionService:GetTagged(tag) do
			table.insert(ignore, model)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	WORLD_PARAMS.FilterDescendantsInstances = ignore
end

-- The eyes open: they swell out of nothing and hang around the body, all of them turning to
-- stare down the line it's aiming; FX_GlareFire sets the beam off.
function EFFECTS.EyesOpen(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local count = math.max(amount(9), 3)
	local eyes = {}
	for i = 1, count do
		local a = i / count * math.pi * 2
		local size = 0.6 + (i % 3) * 0.22
		local ball = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.05, CFrame = root.CFrame, Color = Color3.fromRGB(232, 226, 214), Material = Enum.Material.SmoothPlastic })
		local iris = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.05, CFrame = root.CFrame, Color = GLARE, Material = Enum.Material.Neon })
		local pupil = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.05, CFrame = root.CFrame, Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
		local spread = 3 + (i % 2) * 1.1
		table.insert(eyes, {
			Ball = ball, Iris = iris, Pupil = pupil, Size = size, Phase = i * 1.9,
			Offset = Vector3.new(math.cos(a) * spread, 1.2 + math.sin(a * 2.5 + 1) * 1.6, math.sin(a) * spread * 0.6 + 0.8),
			Born = 0.03 * i,
		})
	end
	local state = { Began = os.clock(), FireAt = nil, CloseAt = nil, Parts = {} }
	glares[model] = state
	local function beamPart(color: Color3, transparency: number)
		local part = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.one * 0.1, Color = color, Material = Enum.Material.Neon, Transparency = transparency })
		table.insert(state.Parts, part)
		return part
	end
	local nextScorch, nextSpark = 0, 0
	local core, shell, tip
	local threads = {}
	local function finish()
		for _, eye in eyes do
			eye.Ball:Destroy()
			eye.Iris:Destroy()
			eye.Pupil:Destroy()
		end
		for _, part in state.Parts do
			part:Destroy()
		end
		if glares[model] == state then
			glares[model] = nil
		end
	end
	everyFrame(function(t)
		local body = rootOf(model)
		if t == math.huge or not body or t > 3 then
			finish()
			return true
		end
		local direction = model:GetAttribute("GlareDir")
		if typeof(direction) ~= "Vector3" then
			direction = body.CFrame.LookVector
		end
		local closing = state.CloseAt and math.clamp((t - state.CloseAt) / 0.2, 0, 1) or 0
		if closing >= 1 then
			finish()
			return true
		end
		local firing = state.FireAt ~= nil and not state.CloseAt
		local chest = coreCentre(model) or body.Position
		local converge = chest + direction * 2.2
		for _, eye in eyes do
			local open = math.clamp((t - eye.Born) / 0.22, 0, 1)
			open = (1 - (1 - open) ^ 3) * (1 - closing)
			local size = eye.Size * open
			local p = body.CFrame:PointToWorldSpace(eye.Offset) + Vector3.new(0, math.sin(t * 2.4 + eye.Phase) * 0.18, 0)
			local look = (firing and (converge - p).Unit) or direction
			local frame = CFrame.lookAt(p, p + look)
			eye.Ball.Size = Vector3.one * math.max(size, 0.02)
			eye.Ball.CFrame = frame
			eye.Iris.Size = Vector3.one * math.max(size * 0.56, 0.02)
			eye.Iris.CFrame = frame * CFrame.new(0, 0, -size * 0.26)
			eye.Pupil.Size = Vector3.one * math.max(size * 0.28, 0.02)
			eye.Pupil.CFrame = frame * CFrame.new(0, 0, -size * 0.42)
			if firing and not threads[eye] then
				threads[eye] = beamPart(GLARE, 0.2)
			end
			local thread = threads[eye]
			if thread then
				local from = p + look * size * 0.45
				local length = (converge - from).Magnitude
				thread.Size = firing and Vector3.new(length, 0.09, 0.09) or Vector3.one * 0.01
				thread.CFrame = CFrame.lookAt((from + converge) / 2, converge) * CFrame.Angles(0, math.pi / 2, 0)
			end
		end
		if firing then
			local age = t - state.FireAt
			if not core then
				core = beamPart(GLARE_CORE, 0)
				shell = beamPart(GLARE, 0.45)
				tip = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one, Color = GLARE_CORE, Material = Enum.Material.Neon, Transparency = 0.1 })
				table.insert(state.Parts, tip)
				local light = Instance.new("PointLight")
				light.Color = GLARE
				light.Range = 26
				light.Brightness = 6
				light.Parent = tip
				worldIgnore()
			end
			local hit = Workspace:Raycast(chest, direction * 46, WORLD_PARAMS)
			local stop = hit and hit.Position or chest + direction * 46
			local length = (stop - chest).Magnitude
			local grow = math.min(age / 0.07, 1)
			local shown = length * grow
			local middle = chest + direction * (shown / 2)
			local pulse = 1 + math.sin(t * 34) * 0.14
			local frame = CFrame.lookAt(middle, chest + direction * shown) * CFrame.Angles(0, math.pi / 2, 0)
			core.Size = Vector3.new(shown, 1.1 * pulse, 1.1 * pulse)
			core.CFrame = frame
			shell.Size = Vector3.new(shown, 2.6 / pulse, 2.6 / pulse)
			shell.CFrame = frame
			tip.CFrame = CFrame.new(chest + direction * shown)
			tip.Size = Vector3.one * (2.2 + math.sin(t * 40) * 0.5)
			if t >= nextSpark then
				nextSpark = t + 0.09
				particles(stop, { Texture = TEX.Sparkle, Color = GLARE_CORE, Color2 = GLARE, Size = 0.9, Size2 = 0, Speed = 16, Life = 0.35, Count = 7, Light = 1 })
				-- light crawling down the beam
				local at = chest + direction * (math.random() * shown)
				bolt(at, at + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 4, GLARE, 0.07, 0.1)
			end
			if t >= nextScorch and hit then
				nextScorch = t + 0.1
				floorMark(stop, 2.2 + math.random(), Color3.fromRGB(26, 12, 30), Enum.Material.Slate, 3, 0.2)
			end
		elseif core then
			core.Size = Vector3.one * 0.01
			shell.Size = Vector3.one * 0.01
			tip.Size = Vector3.one * 0.01
		end
		return false
	end, model)
end

function EFFECTS.GlareFire(model)
	local state = glares[model]
	if state then
		state.FireAt = os.clock() - state.Began
	end
	shake(model, 1.1, 0.14, 30)
	if isMine(model) then
		controllers.EffectsController:ImpactPunch(0.5)
	end
end

function EFFECTS.EyesClose(model)
	local state = glares[model]
	if state then
		state.CloseAt = os.clock() - state.Began
	end
end

CONTACT["Ultimate:THOUSAND-EYE GLARE"] = function(at)
	pieces(at, Vector3.yAxis, { Count = 7, Colors = { GLARE, GLARE_CORE }, Size = 0.1, Stretch = 5, Speed = 18, Life = 0.35 })
	play("Sizzle", at)
end

------------------------------------------------------------------------------------------
-- BASTION QUAKE
------------------------------------------------------------------------------------------
local bastions = setmetatable({}, { __mode = "k" })

-- Its armour plates come off the body and hang round it, moving with it as it jumps.
function EFFECTS.PlatesRise(model)
	local root = rootOf(model)
	if not root then
		return
	end
	local state = bastions[model]
	if not state then
		local plates = {}
		local list = slotParts(model, "Core")
		local color = list[1] and list[1].Color or COLORS.Steel
		local count = 6
		for i = 1, count do
			local a = i / count * math.pi * 2
			table.insert(plates, {
				Angle = a,
				Part = newPart({ Size = Vector3.new(2.3, 3, 0.4), CFrame = root.CFrame, Color = i % 2 == 0 and color or COLORS.Steel, Material = Enum.Material.DiamondPlate }),
			})
		end
		state = { Plates = plates, Rose = os.clock(), Mode = "Rise", Generation = 0 }
		bastions[model] = state
		everyFrame(function(t)
			local body = rootOf(model)
			if t == math.huge or not body or bastions[model] ~= state then
				for _, plate in plates do
					plate.Part:Destroy()
				end
				return true
			end
			if state.Mode == "Rise" then
				local k = math.min((os.clock() - state.Rose) / 0.26, 1)
				k = 1 - (1 - k) ^ 2
				for _, plate in plates do
					local out = Vector3.new(math.cos(plate.Angle), 0, math.sin(plate.Angle))
					local target = CFrame.lookAt(body.Position + out * 3.8 + Vector3.new(0, 1 + math.sin(t * 7 + plate.Angle) * 0.14, 0), body.Position + out * 8)
					plate.Part.CFrame = plate.Part.CFrame:Lerp(target, math.max(k, 0.25))
				end
			end
			return false
		end, model)
	else
		state.Mode = "Rise"
		state.Rose = os.clock()
		state.Generation += 1
	end
	pieces(root.Position, Vector3.yAxis, { Count = 8, Colors = { COLORS.Steel }, Size = 0.1, Stretch = 3, Speed = 12, Spread = 3, Life = 0.4 })
end

-- ...and come down with it, driven edge-first into the floor round where it lands.
function EFFECTS.PlatesSlam(model)
	local state = bastions[model]
	local root = rootOf(model)
	local ground = groundUnder(model)
	if not root or not ground then
		return
	end
	if state then
		state.Mode = "Slam"
		state.Generation += 1
		local generation = state.Generation
		for _, plate in state.Plates do
			local out = Vector3.new(math.cos(plate.Angle), 0, math.sin(plate.Angle))
			local at = ground + out * 4.6 + Vector3.new(0, 0.7, 0)
			local final = CFrame.lookAt(at, at + out + Vector3.new(0, -0.45, 0))
			tween(plate.Part, 0.07, { CFrame = final }, Enum.EasingStyle.Linear)
			particles(at, { Color = Color3.fromRGB(130, 120, 110), Size = 1, Size2 = 3, Speed = 10, Life = 0.6, Count = 5, Drag = 3 })
			pieces(at, Vector3.yAxis, { Count = 3, Colors = { Color3.fromRGB(255, 220, 140) }, Size = 0.08, Stretch = 4, Speed = 16, Life = 0.3 })
		end
		task.delay(0.55, function()
			if bastions[model] == state and state.Generation == generation then
				for _, plate in state.Plates do
					tween(plate.Part, 0.25, { Transparency = 1 })
				end
				task.delay(0.26, function()
					if bastions[model] == state and state.Generation == generation then
						bastions[model] = nil
					end
				end)
			end
		end)
	end
	shake(model, 0.45, 0.5, 40)
	if isMine(model) then
		controllers.EffectsController:ImpactPunch(1)
	end
end

-- The wave: the floor itself heaving up in slabs, ring after ring, racing outward, and a
-- line of cracks left behind it.
function KINDS.QuakeWave(data)
	local center = data.Position
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = math.clamp(tonumber(data.Radius) or 12, 2, 40)
	local time = math.clamp(tonumber(data.Time) or 0.3, 0.05, 1)
	local big = (tonumber(data.Size) or 1) >= 2
	local floor = floorBelow(center + Vector3.new(0, 2, 0), 10)
	local at = floor and floor.Position or center
	-- (broken rock, a dark cut of whatever the floor is)
	local color = (floor and floor.Instance.Color or Color3.fromRGB(110, 100, 92)):Lerp(Color3.fromRGB(38, 34, 36), 0.65)
	local material = Enum.Material.Slate
	play("Shockwave", at)
	if big then
		play("Explosion", at)
	end
	cracks(at, big and 16 or 12, radius * (big and 0.95 or 0.75), big and COLORS.FireCore or nil, 2.4)
	local steps = math.max(3, math.floor(radius / 1.8))
	for step = 1, steps do
		task.delay(time * (step - 1) / steps, function()
			local r = radius * step / steps
			local count = amount(math.clamp(math.floor(r * 1.25), 5, 15))
			local offset = math.random() * 6
			for i = 1, count do
				local a = i / count * math.pi * 2 + offset
				local out = Vector3.new(math.cos(a), 0, math.sin(a))
				local p = at + out * (r + (math.random() - 0.5))
				local high = (0.8 + math.random() * 1) * (big and 1.5 or 1) * (1 - step / steps * 0.4)
				local slab = newPart({ Size = Vector3.new(1 + math.random() * 1.1, high * 1.4, 0.8 + math.random()), Color = color, Material = material })
				local tilted = CFrame.lookAt(p, p + out) * CFrame.Angles(math.rad(-35 - math.random() * 30), 0, math.rad((math.random() - 0.5) * 30))
				slab.CFrame = tilted - Vector3.new(0, high * 1.1, 0)
				tween(slab, 0.07, { CFrame = tilted + Vector3.new(0, high * 0.2, 0) })
				task.delay(0.16 + math.random() * 0.14, function()
					if slab.Parent then
						tween(slab, 0.4, { CFrame = tilted - Vector3.new(0, high * 1.3, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					end
				end)
				Debris:AddItem(slab, 0.75)
			end
			particles(at + Vector3.new(0, 0.6, 0), { Color = Color3.fromRGB(135, 125, 115), Size = 1.5, Size2 = 4, Speed = r * 2.2, Life = 0.55, Count = 7, Drag = 5 })
			if step % 2 == 0 then
				pieces(at + Vector3.new(0, 0.5, 0), Vector3.yAxis, { Count = 6, Colors = { color }, Material = material, Size = 0.4, Speed = 18, Spread = 3.2, Life = 0.6, Gravity = 45 })
			end
		end)
	end
	ring(at + Vector3.new(0, 0.3, 0), radius * 1.1, Color3.fromRGB(190, 180, 165), { Time = time * 1.25, Material = Enum.Material.SmoothPlastic, Thickness = big and 1.2 or 0.7, Transparency = 0.4 })
end

CONTACT["Ultimate:BASTION QUAKE"] = function(at)
	pieces(at, Vector3.yAxis, { Count = 8, Colors = { Color3.fromRGB(120, 110, 100) }, Material = Enum.Material.Slate, Size = 0.3, Speed = 14, Life = 0.5 })
end

------------------------------------------------------------------------------------------
-- CRYSTAL CATACLYSM
------------------------------------------------------------------------------------------
local gathers = setmetatable({}, { __mode = "k" })

-- Shards grow out of the floor round it and lift, circling, as the arms draw them up.
function EFFECTS.CrystalGather(model)
	local root = rootOf(model)
	local ground = groundUnder(model)
	if not root or not ground then
		return
	end
	local shards = {}
	for i = 1, amount(10) do
		table.insert(shards, {
			Part = newPart({ Size = Vector3.new(0.5, 1.8 + math.random() * 1.2, 0.5), CFrame = CFrame.new(ground), Color = i % 2 == 0 and COLORS.Crystal or COLORS.CrystalBlue, Material = Enum.Material.Glass, Transparency = 0.2 }),
			Angle = i * 0.63 + math.random() * 0.2,
			Radius = 3.2 + math.random() * 1.4,
			Top = 1 + math.random() * 4.5,
			Lag = math.random() * 0.25,
		})
	end
	cracks(ground, 7, 5, COLORS.CrystalBlue, 1.5)
	local state = { Drive = nil }
	gathers[model] = state
	everyFrame(function(t)
		local body = rootOf(model)
		local under = body and ground + Vector3.new(body.Position.X - ground.X, 0, body.Position.Z - ground.Z)
		if t == math.huge or not body or t > 1.3 or state.Drive then
			for _, shard in shards do
				if shard.Part.Parent then
					local out = shard.Part.Position
					local down = Vector3.new(out.X, ground.Y - 3, out.Z)
					tween(shard.Part, 0.09, { CFrame = CFrame.lookAt(out, down) * CFrame.Angles(math.pi / 2, 0, 0) + (down - out) }, Enum.EasingStyle.Linear)
					Debris:AddItem(shard.Part, 0.12)
				end
			end
			return true
		end
		for _, shard in shards do
			local k = math.clamp((t - shard.Lag) / 0.9, 0, 1)
			k = k * k * (3 - 2 * k)
			local a = shard.Angle + t * 2.2
			local p = under + Vector3.new(math.cos(a) * shard.Radius, -1.5 + (shard.Top + 1.5) * k, math.sin(a) * shard.Radius)
			shard.Part.CFrame = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))) * CFrame.Angles(0.3, t * 1.4, 0)
		end
		return false
	end, model)
end

function EFFECTS.CrystalDrive(model)
	local state = gathers[model]
	if state then
		state.Drive = true
	end
	local ground = groundUnder(model)
	if ground then
		cracks(ground, 12, 8, COLORS.CrystalBlue, 2.2)
		ring(ground + Vector3.new(0, 0.2, 0), 8, COLORS.CrystalBlue, { Time = 0.3, Thickness = 0.3 })
		pieces(ground + Vector3.new(0, 0.3, 0), Vector3.yAxis, { Count = 10, Colors = { COLORS.Crystal, COLORS.CrystalBlue }, Material = Enum.Material.Glass, Size = 0.25, Speed = 16, Spread = 2.6, Life = 0.6 })
	end
	shake(model, 0.3, 0.3, 30)
	if isMine(model) then
		controllers.EffectsController:ImpactPunch(0.7)
	end
end

function EFFECTS.CrystalRelease(model)
	local root = rootOf(model)
	if root then
		flash(root.Position, 7, COLORS.CrystalBlue, 0.3)
	end
	shake(model, 0.35, 0.35, 34)
end

-- One eruption: crystal runs out through the floor from the body to the point, and the spire
-- goes up there, staying till the field shatters (data.Until seconds from now).
function KINDS.CrystalSpire(data)
	local from, at = data.From, data.Position
	if typeof(from) ~= "Vector3" or typeof(at) ~= "Vector3" then
		return
	end
	local travel = math.clamp(tonumber(data.Travel) or 0.16, 0, 0.6)
	local path = (at - from) * Vector3.new(1, 0, 1)
	local length = path.Magnitude
	local side = length > 0.01 and path.Unit:Cross(Vector3.yAxis) or Vector3.xAxis
	local steps = math.clamp(math.floor(length / 2), 2, 12)
	for i = 1, steps do
		task.delay(travel * (i - 1) / steps, function()
			local p = from:Lerp(Vector3.new(at.X, from.Y, at.Z), i / steps) + side * (math.random() - 0.5) * 1.2
			local run = crystal(p, 0.7 + math.random() * 0.9, 0.42, side * (math.random() - 0.5) * 0.6, i % 2 == 0 and COLORS.Crystal or COLORS.CrystalBlue, 0.05)
			task.delay(0.3 + math.random() * 0.2, function()
				for _, part in run do
					if part.Parent then
						tween(part, 0.18, { Transparency = 1, CFrame = part.CFrame - Vector3.new(0, 1.5, 0) })
						Debris:AddItem(part, 0.2)
					end
				end
			end)
		end)
	end
	task.delay(travel, function()
		local size = tonumber(data.Size) or 1
		local floor = floorBelow(at + Vector3.new(0, 2, 0), 10)
		local base = floor and floor.Position or at
		local height = 6.5 * size
		local cluster = { crystal(base, height, 1.5 * size, Vector3.zero, COLORS.Crystal, 0.13) }
		local satellites = amount(4)
		for i = 1, satellites do
			local a = i / satellites * math.pi * 2 + math.random()
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			table.insert(cluster, crystal(base + out * 1.1 * size, height * (0.42 + math.random() * 0.3), 0.8 * size, out * 0.5, i % 2 == 0 and COLORS.CrystalBlue or COLORS.Crystal, 0.1 + math.random() * 0.05))
		end
		flash(base + Vector3.new(0, 2, 0), 4 * size, COLORS.CrystalBlue, 0.22)
		pieces(base + Vector3.new(0, 0.3, 0), Vector3.yAxis, { Count = 10, Colors = { COLORS.Crystal, COLORS.CrystalBlue, COLORS.Frost }, Material = Enum.Material.Ice, Size = 0.3, Speed = 20, Spread = 2.4, Life = 0.6, Gravity = 45 })
		cracks(base, 6, 4, COLORS.CrystalBlue, 2)
		floorMark(base, 6, COLORS.Ice, Enum.Material.Ice, 3, 0.35)
		play("IceCrack", base)
		play("CrystalChime", base)
		task.delay(math.clamp(tonumber(data.Until) or 1, 0.05, 3), function()
			for i, list in cluster do
				shatterCrystal(list, i == 1)
			end
		end)
	end)
end

function KINDS.CrystalShatter(data)
	if type(data.Points) ~= "table" then
		return
	end
	for _, point in data.Points do
		if typeof(point) == "Vector3" then
			flash(point + Vector3.new(0, 3, 0), 8, COLORS.Frost, 0.25)
			ring(point + Vector3.new(0, 0.3, 0), 6, COLORS.CrystalBlue, { Time = 0.3, Thickness = 0.25 })
			particles(point + Vector3.new(0, 2, 0), { Color = COLORS.Frost, Size = 1.5, Size2 = 4, Speed = 12, Life = 0.7, Count = 8 })
		end
	end
	if typeof(data.Points[1]) == "Vector3" then
		play("Shockwave", data.Points[1])
	end
end

CONTACT["Ultimate:CRYSTAL CATACLYSM"] = function(at, dir)
	pieces(at, dir or Vector3.yAxis, { Count = 8, Colors = { COLORS.Ice, COLORS.Frost, COLORS.Crystal }, Material = Enum.Material.Ice, Size = 0.26, Speed = 14, Life = 0.5 })
end

------------------------------------------------------------------------------------------
-- SCRAP APOCALYPSE
------------------------------------------------------------------------------------------
local orbits = setmetatable({}, { __mode = "k" })

local function scrapPiece(scale: number): BasePart
	local kind = math.random(1, 4)
	if kind == 1 then
		return newPart({ Size = Vector3.new(0.7, 0.7, 2.6) * scale, Color = SCRAP, Material = Enum.Material.CorrodedMetal })
	elseif kind == 2 then
		return newPart({ Size = Vector3.new(2.2, 0.3, 1.6) * scale, Color = Color3.fromRGB(96, 72, 56), Material = Enum.Material.CorrodedMetal })
	elseif kind == 3 then
		return newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.7, 1.2, 1.2) * scale, Color = SCRAP, Material = Enum.Material.DiamondPlate })
	end
	return newPart({ Size = Vector3.new(1.5, 1.2, 1.9) * scale, Color = Color3.fromRGB(80, 66, 60), Material = Enum.Material.CorrodedMetal }, "WedgePart")
end

function EFFECTS.ReactorVent(model)
	local at = coreCentre(model)
	local root = rootOf(model)
	if not at or not root then
		return
	end
	for side = -1, 1, 2 do
		local direction = (root.CFrame.RightVector * side + Vector3.new(0, 0.7, 0) - root.CFrame.LookVector * 0.4).Unit
		particles(at + direction, { Color = COLORS.Steam, Size = 0.9, Size2 = 3.2, Speed = 26, Spread = 10, Life = 0.6, Count = 14, Drag = 4, Direction = direction, Transparency = SMOKE_FADE })
	end
	flash(at, 4.5, COLORS.Ember, 0.35)
	pieces(at, Vector3.yAxis, { Count = 8, Colors = { COLORS.Volt, COLORS.Fire }, Size = 0.08, Stretch = 4, Speed = 20, Spread = 3, Life = 0.4 })
	shake(model, 0.2, 0.14, 24)
end

-- Scrap ripped up out of the floor, circling the body and heating up, until it's thrown.
function EFFECTS.ScrapRise(model)
	local root = rootOf(model)
	local ground = groundUnder(model)
	if not root or not ground then
		return
	end
	local list = {}
	local count = math.max(amount(10), 2)
	for i = 1, count do
		local part = scrapPiece(0.7 + math.random() * 0.35)
		local a = i / count * math.pi * 2
		local radius = 3.4 + (i % 3) * 0.9
		part.CFrame = CFrame.new(ground + Vector3.new(math.cos(a) * radius, -1.5, math.sin(a) * radius))
		local cold = part.Color
		table.insert(list, { Part = part, Cold = cold, Angle = a, Radius = radius, Top = 0.8 + (i % 4) * 1.3, Lag = i * 0.05, Spin = Vector3.new(math.random() * 3, math.random() * 3, math.random() * 3) })
		task.delay(i * 0.05, function()
			if part.Parent then
				local p = ground + Vector3.new(math.cos(a) * radius, 0.3, math.sin(a) * radius)
				pieces(p, Vector3.yAxis, { Count = 3, Colors = { Color3.fromRGB(110, 100, 90) }, Material = Enum.Material.Slate, Size = 0.22, Speed = 12, Life = 0.4 })
				particles(p, { Color = Color3.fromRGB(120, 110, 100), Size = 0.8, Size2 = 2, Speed = 5, Life = 0.5, Count = 4 })
				emitterOn(part, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 0.9, Size2 = 0.1, Life = 0.3, Speed = 1, Spread = 60, Rate = 14, Light = 1 }, 3)
			end
		end)
	end
	local state = { List = list }
	orbits[model] = state
	everyFrame(function(t)
		local body = rootOf(model)
		if t == math.huge or not body or t > 3.1 then
			for _, chunk in list do
				chunk.Part:Destroy()
			end
			if orbits[model] == state then
				orbits[model] = nil
			end
			return true
		end
		local heat = math.clamp(t / 0.9, 0, 1)
		for _, chunk in list do
			if chunk.Part.Parent then
				local k = math.clamp((t - chunk.Lag) / 0.45, 0, 1)
				k = 1 - (1 - k) ^ 3
				local a = chunk.Angle + t * 1.8
				local p = Vector3.new(body.Position.X, ground.Y, body.Position.Z) + Vector3.new(math.cos(a) * chunk.Radius, -1.5 + (chunk.Top + 1.5) * k, math.sin(a) * chunk.Radius)
				chunk.Part.CFrame = CFrame.new(p) * CFrame.Angles(chunk.Spin.X * t, chunk.Spin.Y * t, chunk.Spin.Z * t)
				chunk.Part.Color = chunk.Cold:Lerp(Color3.fromRGB(200, 60, 18), heat)
			end
		end
		return false
	end, model)
end

function KINDS.ScrapThrow(data)
	local model, to = data.Model, data.To
	if typeof(to) ~= "Vector3" then
		return
	end
	local root = typeof(model) == "Instance" and rootOf(model)
	local from = root and (limbTip(model, data.Arm) or root.Position + Vector3.new(0, 3, 0)) or to + Vector3.new(0, 20, 0)
	-- it's one of the pieces that was circling, gone from the ring
	local state = root and orbits[model]
	if state then
		for _, chunk in state.List do
			if chunk.Part.Parent then
				chunk.Part:Destroy()
				break
			end
		end
	end
	local big = data.Big == true
	local part = scrapPiece(big and 1.5 or 1)
	part.Color = Color3.fromRGB(200, 60, 18)
	part.CFrame = CFrame.new(from)
	emitterOn(part, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = big and 2.2 or 1.4, Size2 = 0.2, Life = 0.4, Speed = 1, Spread = 40, Rate = 40, Light = 1, Glow = COLORS.Fire, GlowRange = 12 }, 2)
	emitterOn(part, CFrame.identity, { Texture = TEX.Smoke, Color = SMOKE, Size = 1.2, Size2 = 3, Life = 0.7, Speed = 1, Spread = 30, Rate = 22, Light = 0, Transparency = SMOKE_FADE }, 2)
	local time = math.clamp(tonumber(data.Time) or 0.45, 0.1, 2)
	local apex = 3.5 + (to - from).Magnitude * 0.16
	local spin = Vector3.new(math.random() * 12 - 6, math.random() * 12 - 6, math.random() * 12 - 6)
	everyFrame(function(t)
		local k = math.min(t / time, 1)
		if t == math.huge then
			part:Destroy()
			return true
		end
		part.CFrame = CFrame.new(from:Lerp(to, k) + Vector3.new(0, 4 * k * (1 - k) * apex, 0)) * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
		if k >= 1 then
			part:Destroy()
			blast(to, 6, big)
			pieces(to + Vector3.new(0, 0.6, 0), Vector3.yAxis, { Count = big and 18 or 10, Colors = { SCRAP, Color3.fromRGB(150, 70, 30), COLORS.Fire }, Material = Enum.Material.CorrodedMetal, Size = 0.18, Stretch = 4, Speed = 30, Spread = 3.4, Life = 0.7, Gravity = 45 })
			floorMark(to, big and 11 or 7, Color3.fromRGB(32, 22, 16), Enum.Material.Slate, 3.5, 0.2)
			cracks(to, big and 9 or 5, big and 7 or 4, COLORS.Ember, 1.6)
			play("Explosion", to)
			play("MetalClang", to)
			local holder = root and model
			if holder then
				shake(holder, big and 0.4 or 0.18, big and 0.42 or 0.18, 40)
			end
			return true
		end
		return false
	end)
end

CONTACT["Ultimate:SCRAP APOCALYPSE"] = function(at, dir)
	pieces(at, dir or Vector3.yAxis, { Count = 6, Colors = { SCRAP, COLORS.Fire }, Material = Enum.Material.CorrodedMetal, Size = 0.2, Stretch = 3, Speed = 16, Life = 0.4 })
end

------------------------------------------------------------------------------------------
-- VOID COLLAPSE
------------------------------------------------------------------------------------------
function KINDS.VoidWell(data)
	local at = data.Position
	if typeof(at) ~= "Vector3" then
		return
	end
	local radius = math.clamp(tonumber(data.Radius) or 20, 4, 40)
	local blastRadius = math.clamp(tonumber(data.Blast) or 10, 2, 30)
	local collapse = math.clamp(tonumber(data.Collapse) or 1.2, 0.1, 3)
	local detonate = math.clamp(tonumber(data.Detonate) or 1.4, 0.1, 3)
	local model = typeof(data.Model) == "Instance" and data.Model or nil

	local hole = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, CFrame = CFrame.new(at), Color = Color3.fromRGB(3, 0, 6), Material = Enum.Material.SmoothPlastic })
	local disc = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 0.5, 0.5), CFrame = CFrame.new(at), Color = COLORS.Void, Material = Enum.Material.Neon, Transparency = 0.25 })
	local outer = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 0.5, 0.5), CFrame = CFrame.new(at), Color = COLORS.Shadow, Material = Enum.Material.Neon, Transparency = 0.5 })
	local glow = Instance.new("PointLight")
	glow.Color = COLORS.Void
	glow.Range = radius * 1.4
	glow.Brightness = 5
	glow.Parent = hole
	local shadow = floorMark(at - Vector3.new(0, 1, 0), radius * 1.3, Color3.fromRGB(10, 2, 18), Enum.Material.SmoothPlastic, detonate + 1, 0.45)
	play("VoidWhoosh", at)
	cracks((floorBelow(at) and floorBelow(at).Position) or at, 10, radius * 0.5, COLORS.Void, detonate + 0.6)
	if model then
		-- it's hauling on it: a line of void from each claw to the well
		for _, arm in { "RightArm", "LeftArm" } do
			if model:FindFirstChild(arm .. "_Root") then
				rope(function()
					return limbTip(model, arm)
				end, function()
					return at
				end, collapse, { Color = COLORS.Void, Material = Enum.Material.Neon, Wave = 0.28, Width = 0.22 })
			end
		end
	end
	if shadow then
		shadow.Size = Vector3.new(0.06, 1, 1)
		tween(shadow, collapse * 0.6, { Size = Vector3.new(0.06, radius * 2, radius * 2) })
	end

	local nextStreak, nextDebris = 0, 0
	everyFrame(function(t)
		if t == math.huge then
			hole:Destroy()
			disc:Destroy()
			outer:Destroy()
			return true
		end
		if t < collapse then
			local k = math.min(t / (collapse * 0.45), 1)
			local size = (1 - (1 - k) ^ 2) * (5.2 + t * 0.9) + math.sin(t * 22) * 0.12
			hole.Size = Vector3.one * math.max(size, 0.2)
			disc.Size = Vector3.new(0.08, size * 2.2, size * 2.2)
			outer.Size = Vector3.new(0.06, size * 3.4, size * 3.4)
			disc.CFrame = CFrame.new(at) * CFrame.Angles(0.5, t * 2.4, math.pi / 2 + 0.35) * CFrame.Angles(t * 7, 0, 0)
			outer.CFrame = CFrame.new(at) * CFrame.Angles(-0.4, -t * 1.7, math.pi / 2 - 0.5) * CFrame.Angles(t * 4, 0, 0)
			if t >= nextStreak then
				nextStreak = t + 0.045
				-- light falling in from all round
				for _ = 1, amount(2) do
					local direction = Vector3.new(math.random() - 0.5, (math.random() - 0.35) * 0.6, math.random() - 0.5).Unit
					local from = at + direction * radius * (0.45 + math.random() * 0.5)
					local streak = newPart({ Size = Vector3.new(0.09, 0.09, 2.4), CFrame = CFrame.lookAt(from, at), Color = math.random() < 0.5 and COLORS.Void or Color3.fromRGB(220, 190, 255), Material = Enum.Material.Neon, Transparency = 0.15 })
					tween(streak, 0.3, { CFrame = CFrame.lookAt(at, at + (at - from)), Size = Vector3.new(0.03, 0.03, 0.8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					Debris:AddItem(streak, 0.31)
				end
			end
			if t >= nextDebris then
				nextDebris = t + 0.11
				-- bits of the floor torn loose and dragged in
				local a = math.random() * math.pi * 2
				local start = Vector3.new(at.X + math.cos(a) * radius * 0.7, at.Y - 2.8, at.Z + math.sin(a) * radius * 0.7)
				local bit = newPart({ Size = Vector3.one * (0.25 + math.random() * 0.4), CFrame = CFrame.new(start) * CFrame.Angles(a, a, a), Color = Color3.fromRGB(70, 60, 70), Material = Enum.Material.Slate })
				tween(bit, 0.5, { CFrame = CFrame.new(at) * CFrame.Angles(a * 3, a, 0), Size = Vector3.one * 0.06 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(bit, 0.52)
			end
			return false
		end
		-- the collapse: everything crushed to a point, and the light goes out
		local k = math.min((t - collapse) / 0.11, 1)
		hole.Size = hole.Size:Lerp(Vector3.one * 0.25, k)
		disc.Size = disc.Size:Lerp(Vector3.new(0.02, 0.1, 0.1), k)
		outer.Size = outer.Size:Lerp(Vector3.new(0.02, 0.1, 0.1), k)
		glow.Brightness = 5 * (1 - k)
		return k >= 1 and t >= detonate
	end)

	task.delay(collapse, function()
		play("VoidWhoosh", at)
		if model and isMine(model) then
			controllers.EffectsController:Shake(0.2, 0.08)
		end
	end)
	task.delay(detonate, function()
		hole:Destroy()
		disc:Destroy()
		outer:Destroy()
		play("Explosion", at)
		play("Shockwave", at)
		flash(at, blastRadius * 2.8, Color3.fromRGB(245, 230, 255), 0.25)
		local shell = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(at), Color = COLORS.VoidDark, Material = Enum.Material.Neon, Transparency = 0.2 })
		tween(shell, 0.4, { Size = Vector3.one * blastRadius * 2.4, Transparency = 1 }, Enum.EasingStyle.Quart)
		Debris:AddItem(shell, 0.42)
		local below = floorBelow(at)
		local floorAt = below and below.Position or at - Vector3.new(0, 3, 0)
		ring(floorAt + Vector3.new(0, 0.3, 0), blastRadius * 1.5, COLORS.Void, { Time = 0.45, Thickness = 0.6 })
		ring(at, blastRadius * 1.2, Color3.fromRGB(220, 190, 255), { Time = 0.35, Normal = Vector3.new(0.3, 0.3, 1).Unit, Thickness = 0.2 })
		ring(at, blastRadius * 1.2, COLORS.Void, { Time = 0.4, Normal = Vector3.new(1, 0.2, -0.3).Unit, Thickness = 0.2 })
		for i = 1, amount(12) do
			local a = i / 12 * math.pi * 2
			local out = Vector3.new(math.cos(a), (math.random() - 0.3) * 0.5, math.sin(a)).Unit
			bolt(at, at + out * blastRadius * (0.7 + math.random() * 0.6), i % 2 == 0 and COLORS.Void or Color3.fromRGB(235, 215, 255), 0.16, 0.25)
		end
		cracks(floorAt, 14, blastRadius, COLORS.Void, 2.4)
		floorMark(floorAt, blastRadius * 2, Color3.fromRGB(14, 6, 22), Enum.Material.Slate, 3.5, 0.2)
		particles(at, { Color = COLORS.Shadow, Color2 = COLORS.VoidDark, Size = 2.5, Size2 = 6, Speed = blastRadius * 3.2, Life = 0.8, Count = 22, Drag = 5, Transparency = SMOKE_FADE })
		if model then
			shake(model, 0.5, 0.6, 50)
			if isMine(model) then
				controllers.EffectsController:ImpactPunch(1)
			end
		end
	end)
end

CONTACT["Ultimate:VOID COLLAPSE"] = function(at)
	pieces(at, Vector3.yAxis, { Count = 10, Colors = { COLORS.Void, Color3.fromRGB(230, 200, 255) }, Size = 0.12, Stretch = 5, Speed = 22, Life = 0.4 })
end

------------------------------------------------------------------------------------------
-- SUPERNOVA
------------------------------------------------------------------------------------------
local cocoons = setmetatable({}, { __mode = "k" })

-- The wings catch and it burns inside them, a light growing at its heart until the first flare.
function EFFECTS.WingsCocoon(model)
	local root = rootOf(model)
	if not root then
		return
	end
	for _, part in slotParts(model, "Back") do
		if part.Size.Magnitude > 1 then
			emitterOn(part, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.4, Size2 = 0.2, Life = 0.4, Speed = 1.5, Spread = 60, Rate = 45, Light = 1, Accel = Vector3.new(0, 6, 0) }, 2.8)
		end
	end
	emitterOn(root, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 2.2, Size2 = 0.2, Life = 0.5, Speed = 3, Spread = 180, Rate = 40, Light = 1, Glow = COLORS.Fire, GlowRange = 22, GlowBrightness = 4 }, 2.8)
	local heart = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = root.CFrame, Color = COLORS.FireCore, Material = Enum.Material.Neon, Transparency = 0.15 })
	cocoons[model] = heart
	everyFrame(function(t)
		local body = rootOf(model)
		if t == math.huge or not body or not heart.Parent or t > 1.2 then
			heart:Destroy()
			return true
		end
		heart.CFrame = CFrame.new(body.Position)
		heart.Size = Vector3.one * (0.5 + t * 3 + math.sin(t * 30) * 0.2)
		return false
	end, model)
	-- embers drawn up off the floor beneath it
	local ground = groundUnder(model)
	if ground then
		particles(ground + Vector3.new(0, 0.3, 0), { Texture = TEX.Sparkle, Color = COLORS.Fire, Size = 0.5, Size2 = 0, Speed = 12, Spread = 25, Life = 0.9, Count = 18, Light = 1, Direction = Vector3.yAxis })
	end
end

function KINDS.SupernovaFlare(data)
	local center = data.Position
	local model = typeof(data.Model) == "Instance" and data.Model or nil
	local root = model and rootOf(model)
	if typeof(center) ~= "Vector3" then
		return
	end
	local radius = math.clamp(tonumber(data.Radius) or 12, 2, 40)
	local size = tonumber(data.Size) or 1
	local at = root and root.Position or center + Vector3.new(0, 6, 0)
	if model and cocoons[model] then
		cocoons[model]:Destroy()
		cocoons[model] = nil
	end
	local sun = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = CFrame.new(at), Color = Color3.fromRGB(255, 244, 205), Material = Enum.Material.Neon, Transparency = 0.02 })
	tween(sun, 0.4, { Size = Vector3.one * radius * 1.5, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(sun, 0.42)
	local halo = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = CFrame.new(at), Color = COLORS.Fire, Material = Enum.Material.Neon, Transparency = 0.25 })
	tween(halo, 0.55, { Size = Vector3.one * radius * 2.2, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(halo, 0.57)
	local light = Instance.new("PointLight")
	light.Color = COLORS.Fire
	light.Range = radius * 3.2
	light.Brightness = 10
	light.Parent = sun
	-- the wave of fire across the floor: flames standing up along it as it goes
	ring(center + Vector3.new(0, 0.3, 0), radius, COLORS.Fire, { Time = 0.4, Thickness = 0.8 })
	local rings = 4
	for step = 1, rings do
		task.delay(0.08 * (step - 1), function()
			local r = radius * step / rings
			local count = amount(6 + step * 3)
			for i = 1, count do
				local a = i / count * math.pi * 2 + step
				local p = center + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r)
				particles(p, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 2.4, Size2 = 0.4, Speed = 7, Spread = 18, Life = 0.42, Count = 3, Light = 1, Direction = Vector3.yAxis })
			end
		end)
	end
	-- burning feathers thrown off it
	pieces(at, Vector3.yAxis, { Count = 10 + size * 6, Colors = { COLORS.FireCore, COLORS.Fire, COLORS.Ember }, Size = 0.13, Stretch = 5, Speed = 32, Spread = 4, Up = 2, Life = 0.9, Gravity = 12 })
	floorMark(center, radius * 1.5, Color3.fromRGB(30, 20, 14), Enum.Material.Slate, 3.5, 0.3)
	play(size >= 3 and "Explosion" or "FireIgnite", at)
	play("Shockwave", at)
	if model then
		shake(model, 0.3 + size * 0.07, 0.2 + size * 0.1, 50)
		if isMine(model) and size >= 3 then
			controllers.EffectsController:ImpactPunch(1)
		end
	end
end

function EFFECTS.PhoenixLand(model)
	local ground = groundUnder(model)
	if ground then
		cracks(ground, 10, 6, COLORS.FireCore, 2.2)
		ring(ground + Vector3.new(0, 0.3, 0), 7, COLORS.Fire, { Time = 0.3, Thickness = 0.4 })
		particles(ground + Vector3.new(0, 1, 0), { Color = SMOKE, Size = 2, Size2 = 5, Speed = 12, Life = 0.9, Count = 12, Drag = 4, Transparency = SMOKE_FADE })
		pieces(ground + Vector3.new(0, 0.4, 0), Vector3.yAxis, { Count = 10, Colors = { COLORS.Fire, COLORS.Ember }, Size = 0.1, Stretch = 3, Speed = 16, Spread = 3, Life = 0.5 })
	end
	shake(model, 0.25, 0.3, 28)
end

CONTACT["Ultimate:SUPERNOVA"] = function(at)
	particles(at, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.4, Size2 = 0.2, Speed = 10, Life = 0.4, Count = 12, Light = 1 })
end

------------------------------------------------------------------------------------------
-- ERUPTION
------------------------------------------------------------------------------------------
local hearts = setmetatable({}, { __mode = "k" })

function EFFECTS.HeartCrack(model)
	local at, size = coreCentre(model)
	local ground = groundUnder(model)
	if not at or not ground then
		return
	end
	cracks(ground, 8, 5.5, COLORS.Lava, 3.2)
	flash(at, size * 1.4, COLORS.Lava, 0.28)
	particles(ground + Vector3.new(0, 0.2, 0), { Color = SMOKE, Size = 1, Size2 = 3.2, Speed = 5, Life = 1, Count = 8, Accel = Vector3.new(0, 4, 0), Transparency = SMOKE_FADE })
	pieces(at, Vector3.yAxis, { Count = 5, Colors = { COLORS.Basalt, COLORS.Lava }, Material = Enum.Material.Basalt, Size = 0.18, Speed = 10, Spread = 3, Life = 0.5 })
	shake(model, 0.16, 0.1, 24)
end

-- The heart opens: rock thrown off the chest, and a column of lava going up out of it into the
-- sky, standing there until FX_HeartSeal.
function EFFECTS.HeartSplit(model)
	local at, size = coreCentre(model)
	local root = rootOf(model)
	if not at or not root then
		return
	end
	pieces(at, Vector3.yAxis, { Count = 20, Colors = { COLORS.Basalt, Color3.fromRGB(30, 22, 26), COLORS.Lava }, Material = Enum.Material.Basalt, Size = 0.5, Speed = 34, Spread = 3.6, Life = 1, Gravity = 50 })
	flash(at, size * 5, COLORS.FireCore, 0.35)
	local ground = groundUnder(model)
	if ground then
		ring(ground + Vector3.new(0, 0.3, 0), 11, COLORS.Lava, { Time = 0.4, Thickness = 0.7 })
		cracks(ground, 14, 10, COLORS.Lava, 3.6)
		floorMark(ground, 9, COLORS.Lava, Enum.Material.Neon, 2.6, 0.1)
	end
	local core = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1, 1), Color = Color3.fromRGB(255, 225, 160), Material = Enum.Material.Neon })
	local column = newPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 3, 3), Color = COLORS.Lava, Material = Enum.Material.Neon, Transparency = 0.2 })
	local light = Instance.new("PointLight")
	light.Color = COLORS.Lava
	light.Range = 34
	light.Brightness = 7
	light.Parent = column
	local state = { Began = os.clock(), SealedAt = nil }
	hearts[model] = state
	local nextBurst = 0
	emitterOn(root, CFrame.new(0, 1, 0), { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.8, Size2 = 0.2, Life = 0.5, Speed = 14, Spread = 30, Rate = 34, Light = 1, Accel = Vector3.new(0, 10, 0) }, 1.5)
	everyFrame(function(t)
		local centre = coreCentre(model)
		if t == math.huge or not centre or t > 2 then
			core:Destroy()
			column:Destroy()
			return true
		end
		local age = state.SealedAt and t - state.SealedAt or 0
		if age > 0.28 then
			core:Destroy()
			column:Destroy()
			if hearts[model] == state then
				hearts[model] = nil
			end
			return true
		end
		local height = 60 * math.min(t / 0.14, 1)
		local closing = 1 - age / 0.28
		local pulse = (1 + math.sin(t * 26) * 0.12) * closing
		local up = CFrame.new(centre + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		core.Size = Vector3.new(height, 1.5 * pulse, 1.5 * pulse)
		core.CFrame = up
		column.Size = Vector3.new(height, 3.4 / math.max(pulse, 0.3) * closing, 3.4 / math.max(pulse, 0.3) * closing)
		column.CFrame = up
		if t >= nextBurst and not state.SealedAt then
			nextBurst = t + 0.12
			particles(centre + Vector3.new(0, 3 + math.random() * 12, 0), { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.8, Size2 = 0.2, Speed = 8, Life = 0.4, Count = 5, Light = 1 })
		end
		return false
	end, model)
	shake(model, 1.4, 0.16, 40)
	if isMine(model) then
		controllers.EffectsController:ImpactPunch(1)
	end
end

function EFFECTS.HeartSeal(model)
	local state = hearts[model]
	if state then
		state.SealedAt = os.clock() - state.Began
	end
	local at = coreCentre(model)
	if at then
		particles(at, { Color = COLORS.Steam, Size = 1.4, Size2 = 4.5, Speed = 7, Life = 1.2, Count = 16, Accel = Vector3.new(0, 6, 0), Transparency = SMOKE_FADE })
	end
end

function KINDS.LavaBomb(data)
	local from, to = data.From, data.To
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local big = data.Big == true
	local time = math.clamp(tonumber(data.Time) or 0.7, 0.1, 2)
	local size = big and 3.6 or 2.2
	local rock = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(from), Color = COLORS.Basalt, Material = Enum.Material.Basalt })
	local molten = newPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 1.12, CFrame = CFrame.new(from), Color = COLORS.Lava, Material = Enum.Material.Neon, Transparency = 0.45 })
	emitterOn(molten, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = size * 0.9, Size2 = 0.2, Life = 0.4, Speed = 1, Spread = 180, Rate = 46, Light = 1, Glow = COLORS.Lava, GlowRange = 14 }, 2)
	emitterOn(molten, CFrame.identity, { Texture = TEX.Smoke, Color = SMOKE, Size = size * 0.7, Size2 = size * 1.8, Life = 0.8, Speed = 1, Spread = 40, Rate = 18, Light = 0, Transparency = SMOKE_FADE }, 2)
	local apex = 16 + (to - from).Magnitude * 0.3
	everyFrame(function(t)
		local k = math.min(t / time, 1)
		if t == math.huge then
			rock:Destroy()
			molten:Destroy()
			return true
		end
		local p = from:Lerp(to, k) + Vector3.new(0, 4 * k * (1 - k) * apex, 0)
		rock.CFrame = CFrame.new(p) * CFrame.Angles(t * 5, t * 3, 0)
		molten.CFrame = CFrame.new(p)
		if k >= 1 then
			rock:Destroy()
			molten:Destroy()
			blast(to, 6, big)
			pieces(to + Vector3.new(0, 0.6, 0), Vector3.yAxis, { Count = big and 20 or 12, Colors = { COLORS.Lava, COLORS.FireCore, COLORS.Basalt }, Shape = Enum.PartType.Ball, Size = 0.42, Speed = 26, Spread = 3.4, Life = 0.8, Gravity = 42 })
			-- a pool of lava left burning where it landed, crusting over
			local floor = floorBelow(to + Vector3.new(0, 2, 0), 10)
			local base = floor and floor.Position or to
			floorMark(base, big and 12 or 8, Color3.fromRGB(28, 18, 16), Enum.Material.Basalt, 4.5, 0.15)
			local pool = floorMark(base + Vector3.new(0, 0.03, 0), big and 8.5 or 5.5, COLORS.Lava, Enum.Material.Neon, 3.6, 0.1)
			if pool then
				pool.CFrame += Vector3.new(0, 0.03, 0)
				local vent = newPart({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(base) })
				Debris:AddItem(vent, 3)
				emitterOn(vent, CFrame.identity, { Texture = TEX.Fire, Color = COLORS.FireCore, Color2 = COLORS.Ember, Size = 1.4, Size2 = 0.2, Life = 0.5, Speed = 3, Spread = 25, Rate = 16, Light = 1, Accel = Vector3.new(0, 6, 0), Glow = COLORS.Lava, GlowRange = 10 }, 2.4)
			end
			cracks(base, big and 10 or 6, big and 8 or 5, COLORS.Lava, 3)
			play("Explosion", to)
			play("Sizzle", to)
			play("RockDebris", to)
			return true
		end
		return false
	end)
end

CONTACT["Ultimate:ERUPTION"] = function(at, dir)
	pieces(at, dir or Vector3.yAxis, { Count = 7, Colors = { COLORS.Lava, COLORS.FireCore }, Shape = Enum.PartType.Ball, Size = 0.22, Speed = 14, Life = 0.5 })
	play("Sizzle", at)
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function UltimateEffects:Init(registry)
	controllers = registry
end

-- (nothing to start: AbilityEffects' listeners read the tables filled in above)
function UltimateEffects:Start() end

return UltimateEffects
