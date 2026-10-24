--[[
	GymController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/GymController

	THE NIGHTMARE GYM on the client (GymService decides everything; this shows it):

	  ENTER   press E at the lift in the Forge: the camera glides to the freight doors,
	          they grind open, the camera pushes into the dark shaft (the server moves you
	          and your Nightmare down while it's black), comes out of the gym's own lift and
	          sweeps over the hall, then settles on your bay as your Nightmare walks to its
	          bag and starts training. The reward panel slides in.
	  TRAIN   a camera director cuts between angles (side, three-quarter, over the
	          shoulder, low hero, wide) when your Nightmare changes exercise; every heavy
	          bag in the hall swings from the strike markers of the animation that hit it
	          (strength per strike: GymDefinitions.Strikes), with dust, thumps and chains.
	  REWARD  each roll shows on the panel and your bay's screen; Rare and better glow the
	          crate open with the camera easing in (Space / Skip to skip).
	  LEAVE   the reverse: back into the gym's lift, out of the Forge's doors, which close
	          behind you, and the camera returns to you.
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local GymDefinitions = require(Shared:WaitForChild("GymDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local NightmarePoses = require(script.Parent:WaitForChild("NightmarePoses"))

local GymController = {}

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local C = UIKit.Colors
local TIERS = GymDefinitions.Tiers
local BAG = GymDefinitions.Bag

local controllers
local request, event
local ui = {}
local state = {
	phase = nil, -- nil | "Entering" | "Training" | "Leaving"
	bay = nil,
	summary = nil,
	summaryAt = 0,
	hiddenGuis = {},
	reveal = nil,
	panelHidden = false,
}

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local function ease(style: string, t: number): number
	t = math.clamp(t, 0, 1)
	if style == "In" then
		return t * t
	elseif style == "Out" then
		return 1 - (1 - t) * (1 - t)
	end
	return 0.5 - 0.5 * math.cos(math.pi * t) -- InOut (sine)
end

local function clock(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	if seconds >= 3600 then
		return ("%dh %02dm"):format(seconds // 3600, (seconds % 3600) // 60)
	end
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function pct(p: number): string
	local v = p * 100
	if v >= 1 then
		return ("%.1f%%"):format(v)
	elseif v >= 0.1 then
		return ("%.2f%%"):format(v)
	end
	return ("%.3f%%"):format(v)
end

local function tierName(rank: number?): string
	return rank and GymDefinitions.TierOrder[rank] or "—"
end

local function forgeFolder()
	return Workspace:FindFirstChild("NightmareForgeHub")
end

local function hall(): Model?
	local root = forgeFolder()
	return root and root:FindFirstChild("NightmareGym")
end

local function myNightmare(): Model?
	return controllers.ClientState:GetMyNightmare()
end

local function rewardText(r): string
	local parts = {}
	if r.PartId then
		local def = PartDefinitions.Get(r.PartId)
		local name = def and def.DisplayName or r.PartId
		if r.Mutation then
			local m = MutationDefinitions.Get(r.Mutation)
			name = (m and m.DisplayName or r.Mutation) .. " " .. name
		end
		table.insert(parts, name .. (r.IsNew and " (NEW)" or ""))
	end
	if (r.Coins or 0) > 0 then
		table.insert(parts, ("+%d coins"):format(r.Coins))
	end
	if (r.Essence or 0) > 0 then
		table.insert(parts, ("+%d essence"):format(r.Essence))
	end
	if r.Title then
		local title = GymDefinitions.Titles[r.Title]
		table.insert(parts, ('title "%s"'):format(title and title.Name or r.Title))
	end
	return table.concat(parts, " · ")
end

------------------------------------------------------------------------------------------
-- Camera: a cinematic move (from -> to over time) or the training director's shot
------------------------------------------------------------------------------------------
local cine = nil -- { From, To, Start, Duration, Style }
local director = { shot = 1, changedAt = 0, from = nil, blendStart = 0, override = nil }

local function moveCamera(to: CFrame, duration: number, style: string?)
	cine = { From = camera.CFrame, To = to, Start = os.clock(), Duration = duration, Style = style or "InOut" }
	task.wait(duration)
end

-- Shots around the bay, built every frame from where the Nightmare and its bag are.
local SHOTS = {
	function(n: Vector3, b: Vector3, bay: CFrame) -- side on, at chest height
		local mid = (n + b) / 2
		return CFrame.lookAt(mid + bay.RightVector * 13 + Vector3.new(0, 2.5, 0), mid + Vector3.new(0, 1, 0))
	end,
	function(n: Vector3, _b: Vector3, bay: CFrame) -- over the shoulder, the bag beyond
		return CFrame.lookAt(n - bay.LookVector * 8 + bay.RightVector * 3.5 + Vector3.new(0, 4.5, 0), n + bay.LookVector * 6 + Vector3.new(0, 1, 0))
	end,
	function(n: Vector3, b: Vector3, bay: CFrame) -- three-quarter front: from the mirror side, past the bag's edge (clear of the gantry)
		return CFrame.lookAt(b + bay.LookVector * 7 - bay.RightVector * 5.5 + Vector3.new(0, 1.5, 0), n + Vector3.new(0, 2, 0))
	end,
	function(n: Vector3, _b: Vector3, bay: CFrame) -- low hero angle, looking up at it
		return CFrame.lookAt(n + bay.RightVector * -7 + bay.LookVector * 1.5 + Vector3.new(0, -1.6, 0), n + Vector3.new(0, 2.5, 0))
	end,
	function(n: Vector3, b: Vector3, bay: CFrame) -- wide from the aisle, high
		local mid = (n + b) / 2
		return CFrame.lookAt(mid - bay.LookVector * 20 + bay.RightVector * 8 + Vector3.new(0, 10, 0), mid)
	end,
}

local function shotFrame(index: number): CFrame?
	local bayCF = state.bay and GymDefinitions.BayCF(state.bay)
	local model = myNightmare()
	local root = model and model:FindFirstChild("HumanoidRootPart")
	local bag = hall() and hall():FindFirstChild("Bags") and hall().Bags:FindFirstChild("Bag" .. (state.bay or 0))
	if not bayCF or not root or not bag or not bag.PrimaryPart then
		return nil
	end
	local n = root.Position
	local pivot = bag:GetAttribute("Pivot")
	local b = pivot and Vector3.new(pivot.X, n.Y, pivot.Z) or bag.PrimaryPart.Position
	-- a slow drift so even a held shot breathes
	local t = os.clock()
	local drift = Vector3.new(math.sin(t * 0.21) * 0.8, math.sin(t * 0.17) * 0.4, math.cos(t * 0.19) * 0.8)
	local shot = SHOTS[index](n, b, bayCF)
	return shot + drift
end

local function nextShot()
	local old = director.shot
	local pick = math.random(1, #SHOTS - 1)
	director.shot = pick >= old and pick + 1 or pick
	director.from = camera.CFrame
	director.blendStart = os.clock()
	director.changedAt = os.clock()
end

local function renderCamera()
	if not state.phase then
		return
	end
	camera.CameraType = Enum.CameraType.Scriptable
	if cine then
		local t = (os.clock() - cine.Start) / cine.Duration
		camera.CFrame = cine.From:Lerp(cine.To, ease(cine.Style, t))
		if t >= 1 and state.phase == "Training" then
			cine = nil
			director.from = camera.CFrame
			director.blendStart = os.clock()
		end
		return
	end
	if state.phase ~= "Training" then
		return
	end
	local target = director.override and director.override() or shotFrame(director.shot)
	if not target then
		return
	end
	if os.clock() - director.changedAt > 14 then
		nextShot()
	end
	local blend = ease("InOut", (os.clock() - director.blendStart) / 1.4)
	camera.CFrame = director.from and blend < 1 and director.from:Lerp(target, blend) or target
end

------------------------------------------------------------------------------------------
-- Doors
------------------------------------------------------------------------------------------
local function slideDoor(door: Instance?, open: boolean, duration: number)
	if not door then
		return
	end
	for _, leaf in door:GetChildren() do
		if leaf:IsA("Model") then
			local closed = leaf:GetAttribute("ClosedCF")
			local slide = leaf:GetAttribute("Slide") or 0
			if typeof(closed) == "CFrame" then
				local from = leaf:GetPivot()
				local to = open and closed * CFrame.new(slide, 0, 0) or closed
				task.spawn(function()
					local start = os.clock()
					while true do
						local t = (os.clock() - start) / duration
						leaf:PivotTo(from:Lerp(to, ease(open and "InOut" or "Out", t)))
						if t >= 1 then
							break
						end
						RunService.RenderStepped:Wait()
					end
				end)
			end
		end
	end
end

local function liftDoor()
	local root = forgeFolder()
	local lift = root and root:FindFirstChild("GymLift")
	return lift and lift:FindFirstChild("Door")
end

-- The lift's "Enter the Gym" prompt is off while you're in (or on your way in / out).
local function setPromptEnabled(enabled: boolean)
	local root = forgeFolder()
	local lift = root and root:FindFirstChild("GymLift")
	local part = lift and lift:FindFirstChild("PromptPart")
	local prompt = part and part:FindFirstChild("EnterGym")
	if prompt then
		prompt.Enabled = enabled
	end
end

------------------------------------------------------------------------------------------
-- Heavy bags: a damped pendulum per bag, pushed by strike markers
------------------------------------------------------------------------------------------
local bags = {} -- [Model] = sim

local function trackBag(model: Model)
	local pivot = model:GetAttribute("Pivot")
	local length = model:GetAttribute("Length")
	if typeof(pivot) ~= "Vector3" or type(length) ~= "number" then
		return
	end
	if bags[model] then
		return
	end
	local origin = CFrame.new(pivot)
	local parts = {}
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			parts[part] = origin:ToObjectSpace(part.CFrame)
		end
	end
	-- with streaming, parts can arrive after the model: they come in at rest, so their
	-- offset is taken from the rest frame
	model.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") and not parts[part] then
			parts[part] = origin:ToObjectSpace(part.CFrame)
		end
	end)
	bags[model] = {
		model = model,
		pivot = pivot,
		length = length,
		parts = parts,
		d = Vector2.zero, -- bag centre's horizontal offset from rest (studs)
		v = Vector2.zero,
		twist = 0,
		twistV = 0,
		moving = false,
	}
end

local function stepBags(dt: number)
	dt = math.min(dt, 1 / 20)
	local camPos = camera.CFrame.Position
	for model, sim in bags do
		if not model.Parent then
			bags[model] = nil
			continue
		end
		local hold = sim.hold
		if hold and os.clock() > hold.Until then
			sim.hold, hold = nil, nil -- (a Rip normally lets go first, with a yank)
		end
		if not sim.moving and not hold then
			continue
		end
		if hold then
			-- in the jaws: pulled in toward the biter and thrashed with its head
			local t = os.clock() - hold.Start
			local bump = math.exp(-(os.clock() - hold.BumpAt) * 9) * 0.45 -- a knee driving it away a touch
			local want = hold.Pull + hold.Across * math.sin(t * math.pi * 2 * hold.Shake) * 0.5 + hold.Look * bump
			sim.d = sim.d:Lerp(want, math.min(dt * 18, 1))
			sim.v = Vector2.zero
			sim.moving = true
		else
			local omega2 = BAG.Gravity / sim.length
			local a = -sim.d * omega2 - sim.v * BAG.Damping
			sim.v += a * dt
			sim.d += sim.v * dt
		end
		if sim.d.Magnitude > BAG.MaxSwing then
			sim.d = sim.d.Unit * BAG.MaxSwing
			sim.v *= 0.5
		end
		sim.twistV += (-sim.twist * 6 - sim.twistV * 1.5) * dt
		sim.twist += sim.twistV * dt
		if sim.d.Magnitude < 0.003 and sim.v.Magnitude < 0.01 and math.abs(sim.twist) < 0.002 and math.abs(sim.twistV) < 0.01 then
			sim.d, sim.v, sim.twist, sim.twistV, sim.moving = Vector2.zero, Vector2.zero, 0, 0, false
		end
		if (sim.pivot - camPos).Magnitude > 260 then
			continue
		end
		local down = Vector3.new(sim.d.X, -math.sqrt(math.max(sim.length ^ 2 - sim.d.Magnitude ^ 2, 0.01)), sim.d.Y).Unit
		local swing = CFrame.fromRotationBetweenVectors(Vector3.new(0, -1, 0), down)
		local frame = CFrame.new(sim.pivot) * swing * CFrame.Angles(0, sim.twist, 0)
		for part, relative in sim.parts do
			part.CFrame = frame * relative
		end
	end
end

local function strikeBag(model: Model, markerName: string, action: string?)
	local bay = model:GetAttribute("GymBay")
	-- a bite's contact frame clamps the bag instead of punching it
	local ability = type(action) == "string" and action:sub(1, 8) == "Ability_" and AbilityDefinitions.Get(action:sub(9):gsub("_Left$", "")) or nil
	if markerName == "Hit" and ability and ability.Clamp then
		markerName = "BiteClamp"
	end
	local strike = bay and GymDefinitions.Strikes[markerName]
	if not strike then
		return
	end
	local h = hall()
	local bagModel = h and h:FindFirstChild("Bags") and h.Bags:FindFirstChild("Bag" .. bay)
	local sim = bagModel and bags[bagModel]
	local root = model:FindFirstChild("HumanoidRootPart")
	if not sim or not root then
		return
	end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z).Unit
	local body = bagModel:FindFirstChild("Bag")
	local at = body and body.Position or sim.pivot
	local audio = controllers.AudioController
	if strike.Hold then
		-- a bite's clamp (thrashed with the head) or a clinch (held still, close)
		local clamp = ability and ability.Clamp
		local pull = -look * (strike.Pull or 0.5)
		sim.hold = {
			Start = os.clock(),
			Until = os.clock() + (clamp and clamp.Hold + 0.3 or strike.Duration or 1.4),
			Shake = clamp and clamp.Shake or 0,
			Pull = Vector2.new(pull.X, pull.Z),
			Across = clamp and Vector2.new(-right.X, -right.Z) or Vector2.zero, -- +sin swings it to the biter's left, with the head
			Look = Vector2.new(look.X, look.Z),
			BumpAt = -math.huge,
		}
		audio:Play(strike.Sound, at)
		local dust = body and body:FindFirstChild("Dust")
		if dust then
			dust:Emit(10)
		end
		return
	end
	-- a knee while it's clinched: it jolts in the hands instead of swinging away
	if sim.hold and markerName == "BagKnee" then
		sim.hold.BumpAt = os.clock()
		audio:Play(strike.Sound, at)
		local dust = body and body:FindFirstChild("Dust")
		if dust then
			dust:Emit(8)
		end
		return
	end
	sim.hold = nil -- a rip (or any blow) tears it out of the jaws
	local push = look * strike.Forward + right * strike.Side
	sim.v += Vector2.new(push.X, push.Z)
	sim.twistV += strike.Twist
	sim.moving = true

	local strength = push.Magnitude
	audio:Play(strike.Sound, at)
	-- practising an ability: its contact sparks off the leather
	if ability and markerName ~= "Rip" then
		controllers.EffectsController:HitBurst(at - look * BAG.Radius, -look, "Slash", false)
	end
	if strength > 4 then
		audio:Play("ChainRattle", sim.pivot)
	end
	local dust = body and body:FindFirstChild("Dust")
	if dust then
		dust:Emit(math.floor(4 + strength * 1.5))
	end
	if bay == state.bay and state.phase == "Training" then
		controllers.EffectsController:Shake(0.08, 0.02 + strength * 0.01)
	end
end

------------------------------------------------------------------------------------------
-- UI
------------------------------------------------------------------------------------------
local function buildUI()
	local gui = UIKit.New("ScreenGui", {
		Name = "GymUI",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 20,
		Enabled = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	ui.Gui = gui

	-- the black dip for the cut inside the lift shaft
	ui.Dip = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(), BackgroundTransparency = 1, ZIndex = 50, Parent = gui })

	local panel = UIKit.New("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -16, 0.5, 0),
		Size = UDim2.fromOffset(330, 684),
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.12,
		Parent = gui,
	}, { UIKit.Corner(12), UIKit.Stroke(Color3.fromRGB(255, 70, 110), 1.5, 0.4), UIKit.Padding(12) })
	UIKit.AutoScale(panel)
	ui.Panel = panel
	local y = 0
	local function row(height: number)
		local r = UIKit.New("Frame", { Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Parent = panel })
		y += height + 6
		return r
	end

	local head = row(40)
	UIKit.Label({ Text = "THE NIGHTMARE GYM", Font = UIKit.FontHeavy, TextColor3 = Color3.fromRGB(255, 80, 120), Size = UDim2.new(1, -70, 0, 24), MaxTextSize = 22, Parent = head })
	ui.BayLabel = UIKit.Label({ Text = "Bay", Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, -70, 0, 16), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 14, Parent = head })
	UIKit.Button({ Text = "Hide", Position = UDim2.new(1, -64, 0, 4), Size = UDim2.fromOffset(64, 28), MaxTextSize = 14, Parent = head }, function()
		GymController:SetPanelHidden(true)
	end)

	local next = row(46)
	ui.NextLabel = UIKit.Label({ Text = "Next reward in —", Size = UDim2.new(1, 0, 0, 20), MaxTextSize = 17, Parent = next })
	local bar = UIKit.New("Frame", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = Color3.fromRGB(18, 16, 26), Parent = next }, { UIKit.Corner(7) })
	ui.NextFill = UIKit.New("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 80, 120), Parent = bar }, { UIKit.Corner(7) })

	local multipliers = row(22)
	ui.LuckLabel = UIKit.Label({ Text = "Luck x1 · Speed x1", Size = UDim2.fromScale(1, 1), TextColor3 = C.Warn, MaxTextSize = 15, Parent = multipliers })

	local session = row(40)
	ui.SessionLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, 0, 0, 18), MaxTextSize = 14, Parent = session })
	ui.LifetimeLabel = UIKit.Label({ Text = "", Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 13, Parent = session })

	UIKit.Label({ Text = "RECENT REWARDS", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	y += 18
	local recent = row(118)
	UIKit.List(2).Parent = recent
	ui.Recent = recent

	UIKit.Label({ Text = "REAL ODDS (each reward)", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	y += 18
	local odds = row(84)
	UIKit.New("UIGridLayout", { CellSize = UDim2.new(0.5, -3, 0, 18), CellPadding = UDim2.fromOffset(6, 3), SortOrder = Enum.SortOrder.LayoutOrder, Parent = odds })
	ui.Odds = {}
	for i, id in GymDefinitions.TierOrder do
		ui.Odds[id] = UIKit.Label({ Text = id, LayoutOrder = i, TextColor3 = TIERS[id].Color, MaxTextSize = 13, Parent = odds })
	end

	UIKit.Label({ Text = "BOOSTS (coins)", Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 16), TextColor3 = C.SubText, MaxTextSize = 13, Parent = panel })
	y += 18
	ui.BoostButtons = {}
	for _, id in GymDefinitions.BoostOrder do
		local def = GymDefinitions.Boosts[id]
		local r = row(34)
		local button = UIKit.Button({ Text = ("%s · %d"):format(def.Name, def.Cost), Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = Color3.fromRGB(70, 40, 90), MaxTextSize = 14, Parent = r }, function()
			GymController:Buy(id)
		end)
		local info = UIKit.Label({ Text = def.Text .. (" (%d min)"):format(def.Duration // 60), Position = UDim2.new(0.5, 4, 0, 0), Size = UDim2.new(0.5, -4, 1, 0), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 11, Parent = r })
		ui.BoostButtons[id] = { Button = button, Info = info }
	end
	-- the SHOP's gym boosts and passes (Mega Luck, Lucky Trainer, Night Shift...)
	local shopRow = row(32)
	UIKit.Button({ Text = "🍀 MORE LUCK & SPEED · SHOP", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(190, 140, 30), MaxTextSize = 15, Parent = shopRow }, function()
		controllers.ShopController:Open("Gym")
	end)

	local leave = UIKit.Button({ Text = "LEAVE THE GYM", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Color3.fromRGB(150, 30, 52), MaxTextSize = 18, Parent = panel }, function()
		GymController:Leave()
	end)
	ui.Leave = leave

	-- collapsed bar (when the panel is hidden): the countdown + show button
	ui.Mini = UIKit.New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(250, 40), BackgroundColor3 = C.Panel, BackgroundTransparency = 0.15, Visible = false, Parent = gui }, { UIKit.Corner(10), UIKit.Padding(6) })
	ui.MiniLabel = UIKit.Label({ Text = "", Size = UDim2.new(1, -66, 1, 0), MaxTextSize = 15, Parent = ui.Mini })
	UIKit.Button({ Text = "Show", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.new(0, 60, 1, 0), MaxTextSize = 14, Parent = ui.Mini }, function()
		GymController:SetPanelHidden(false)
	end)

	-- reward popups (small) and the big reveal title
	ui.Popup = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(520, 36), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 24, TextStrokeTransparency = 0.4, Visible = false, Parent = gui })
	ui.RevealTier = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(700, 70), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, MaxTextSize = 64, TextStrokeTransparency = 0.2, Visible = false, Parent = gui })
	ui.RevealItem = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.39), Size = UDim2.fromOffset(700, 40), TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 30, TextStrokeTransparency = 0.3, Visible = false, Parent = gui })
	ui.Skip = UIKit.Button({ Text = "Skip (Space)", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.fromOffset(150, 34), Visible = false, MaxTextSize = 14, Parent = gui }, function()
		GymController:SkipReveal()
	end)
	ui.Flash = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 40, Parent = gui })
end

function GymController:SetPanelHidden(hidden: boolean)
	state.panelHidden = hidden
	ui.Panel.Visible = not hidden and state.phase == "Training"
	ui.Mini.Visible = hidden and state.phase == "Training"
end

local function refreshPanel()
	local s = state.summary
	if not s then
		return
	end
	ui.BayLabel.Text = ("Bay %d · your Nightmare is training"):format(state.bay or 0)
	ui.LuckLabel.Text = ("Luck x%s · Speed x%s"):format(tostring(s.Luck), tostring(s.Speed))
	local boostsLeft = {}
	for id, left in s.Boosts or {} do
		local def = GymDefinitions.Boosts[id]
		local remaining = left - (os.clock() - state.summaryAt)
		if def and remaining > 0 then
			table.insert(boostsLeft, ("%s %s"):format(def.Name, clock(remaining)))
		end
	end
	if #boostsLeft > 0 then
		ui.LuckLabel.Text ..= "  ·  " .. table.concat(boostsLeft, ", ")
	end
	local trained = (s.SessionTime or 0) + (state.phase == "Training" and (os.clock() - state.summaryAt) or 0)
	ui.SessionLabel.Text = ("This session: %s · %d rewards · best %s"):format(clock(trained), s.SessionRewards or 0, s.SessionBest and tierName(s.SessionBest):upper() or "—")
	local titles = {}
	for id in s.Titles or {} do
		local def = GymDefinitions.Titles[id]
		table.insert(titles, def and def.Name or id)
	end
	ui.LifetimeLabel.Text = ("All time: %s · %d rewards · best %s%s"):format(clock(s.TotalTime or 0), s.TotalRewards or 0, s.Best and s.Best > 0 and tierName(s.Best):upper() or "—", #titles > 0 and (" · " .. table.concat(titles, ", ")) or "")
	local odds = GymDefinitions.Odds(s.Luck or 1)
	for id, label in ui.Odds do
		label.Text = ("%s  %s"):format(id, pct(odds[id]))
	end
	for _, child in ui.Recent:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	for i, r in s.Recent or {} do
		UIKit.Label({ Text = ("%s · %s"):format(r.Tier:upper(), rewardText(r)), LayoutOrder = i, Size = UDim2.new(1, 0, 0, 18), TextColor3 = TIERS[r.Tier].Color, MaxTextSize = 13, Parent = ui.Recent })
	end
	if #(s.Recent or {}) == 0 then
		UIKit.Label({ Text = "Your first reward is on its way.", Size = UDim2.new(1, 0, 0, 18), TextColor3 = C.SubText, Font = UIKit.FontBody, MaxTextSize = 13, Parent = ui.Recent })
	end
	for id, entry in ui.BoostButtons do
		local def = GymDefinitions.Boosts[id]
		local affordable = (s.Coins or 0) >= def.Cost
		entry.Button.BackgroundColor3 = affordable and Color3.fromRGB(70, 40, 90) or C.PanelLight
		entry.Button.TextTransparency = affordable and 0 or 0.45
	end
end

local function setSummary(summary)
	if summary then
		state.summary = summary
		state.summaryAt = os.clock()
		refreshPanel()
	end
end

-- The countdown on the panel, the mini bar and your bay's screen (twice a second).
local function tickTimers()
	local s = state.summary
	if state.phase ~= "Training" or not s or not s.NextIn then
		return
	end
	local left = math.max(0, s.NextIn - (os.clock() - state.summaryAt))
	local interval = s.Interval or GymDefinitions.RewardInterval
	ui.NextLabel.Text = ("Next reward in %s"):format(clock(left))
	ui.NextFill.Size = UDim2.fromScale(math.clamp(1 - left / interval, 0, 1), 1)
	ui.MiniLabel.Text = ("Next reward %s · luck x%s"):format(clock(left), tostring(s.Luck))
	refreshPanel()
	local h = hall()
	local bayModel = h and h:FindFirstChild("Bay" .. (state.bay or 0))
	local screen = bayModel and bayModel:FindFirstChild("BayScreen")
	local gui = screen and screen:FindFirstChild("Screen")
	if gui then
		gui.Title.Text = ("BAY %d · %s"):format(state.bay, localPlayer.DisplayName:upper())
		gui.Next.Text = ("NEXT REWARD %s"):format(clock(left))
		local last = s.Recent and s.Recent[1]
		gui.Last.Text = last and ("%s · %s"):format(last.Tier:upper(), rewardText(last)) or ("LUCK x%s"):format(tostring(s.Luck))
		gui.Last.TextColor3 = last and TIERS[last.Tier].Color or Color3.fromRGB(255, 200, 90)
	end
end

------------------------------------------------------------------------------------------
-- Rewards
------------------------------------------------------------------------------------------
local function popup(text: string, color: Color3)
	ui.Popup.Text = text
	ui.Popup.TextColor3 = color
	ui.Popup.Visible = true
	ui.Popup.TextTransparency = 0
	local token = os.clock()
	ui.Popup:SetAttribute("Token", token)
	task.delay(2.6, function()
		if ui.Popup:GetAttribute("Token") == token then
			TweenService:Create(ui.Popup, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
		end
	end)
end

local function crateParts()
	local h = hall()
	local bayModel = h and h:FindFirstChild("Bay" .. (state.bay or 0))
	local crate = bayModel and bayModel:FindFirstChild("Crate")
	return crate, crate and crate:FindFirstChild("Glow"), crate and crate:FindFirstChild("Lid")
end

function GymController:SkipReveal()
	local reveal = state.reveal
	if not reveal then
		return
	end
	state.reveal = nil
	director.override = nil
	director.from = camera.CFrame
	director.blendStart = os.clock()
	ui.RevealTier.Visible = false
	ui.RevealItem.Visible = false
	ui.Skip.Visible = false
	local _, glowPart, lid = crateParts()
	if glowPart then
		glowPart.Transparency = 1
		local light = glowPart:FindFirstChild("GlowLight")
		if light then
			light.Brightness = 0
		end
	end
	if lid and reveal.lidCF then
		lid.CFrame = reveal.lidCF
	end
	if not state.panelHidden and state.phase == "Training" then
		ui.Panel.Visible = true
	end
end

local function reveal(r)
	local tier = TIERS[r.Tier]
	local big = r.Rank >= TIERS.Mythic.Rank
	controllers.AudioController:Play(big and "GymRevealMythic" or "GymRevealRare")
	local crate, glowPart, lid = crateParts()
	if state.reveal then
		GymController:SkipReveal()
	end
	local token = {}
	state.reveal = token
	token.lidCF = lid and lid.CFrame
	ui.Panel.Visible = false
	ui.Skip.Visible = true

	-- the camera eases in on the crate
	if crate and crate.PrimaryPart then
		local at = crate.PrimaryPart.Position
		local bayCF = GymDefinitions.BayCF(state.bay)
		director.override = function()
			return CFrame.lookAt(at + bayCF.RightVector * 6 - bayCF.LookVector * 4 + Vector3.new(0, 3.2, 0), at + Vector3.new(0, 1, 0))
		end
		director.from = camera.CFrame
		director.blendStart = os.clock()
	end
	-- the crate glows in the tier's colour, the lid lifts, sparks burst out
	if glowPart then
		glowPart.Color = tier.Color
		TweenService:Create(glowPart, TweenInfo.new(0.6), { Transparency = 0.15 }):Play()
		local light = glowPart:FindFirstChild("GlowLight")
		if light then
			light.Color = tier.Color
			TweenService:Create(light, TweenInfo.new(0.6), { Brightness = big and 6 or 4 }):Play()
		end
	end
	task.delay(0.9, function()
		if state.reveal ~= token then
			return
		end
		if lid then
			TweenService:Create(lid, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = lid.CFrame * CFrame.new(0, 1.4, 0.8) * CFrame.Angles(math.rad(-60), 0, 0) }):Play()
		end
		if glowPart then
			local sparks = glowPart:FindFirstChild("RevealSparks") or Instance.new("ParticleEmitter")
			sparks.Name = "RevealSparks"
			sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color = ColorSequence.new(tier.Color)
			sparks.LightEmission = 1
			sparks.Size = NumberSequence.new(big and 0.8 or 0.5, 0)
			sparks.Lifetime = NumberRange.new(0.8, 1.6)
			sparks.Speed = NumberRange.new(8, big and 22 or 14)
			sparks.SpreadAngle = Vector2.new(40, 40)
			sparks.Acceleration = Vector3.new(0, -12, 0)
			sparks.EmissionDirection = Enum.NormalId.Top
			sparks.Enabled = false
			sparks.Parent = glowPart
			sparks:Emit(big and 120 or 50)
		end
		if big then
			ui.Flash.BackgroundTransparency = 0.2
			TweenService:Create(ui.Flash, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		end
		-- the silhouette first, then the colour
		ui.RevealTier.Text = r.Tier:upper() .. "!"
		ui.RevealTier.TextColor3 = Color3.new()
		ui.RevealItem.Text = rewardText(r)
		ui.RevealItem.TextColor3 = Color3.new()
		ui.RevealTier.Visible = true
		ui.RevealItem.Visible = true
		task.delay(0.45, function()
			if state.reveal == token then
				TweenService:Create(ui.RevealTier, TweenInfo.new(0.3), { TextColor3 = tier.Color }):Play()
				TweenService:Create(ui.RevealItem, TweenInfo.new(0.3), { TextColor3 = Color3.new(1, 1, 1) }):Play()
			end
		end)
	end)
	task.delay(big and 5 or 3.6, function()
		if state.reveal == token then
			GymController:SkipReveal()
		end
	end)
end

local function onReward(r)
	setSummary(r.Summary)
	if r.Rank >= TIERS.Rare.Rank and state.phase == "Training" then
		reveal(r)
	else
		controllers.AudioController:Play("GymReward")
		popup(("%s · %s"):format(r.Tier:upper(), rewardText(r)), TIERS[r.Tier].Color)
	end
end

------------------------------------------------------------------------------------------
-- Enter / leave
------------------------------------------------------------------------------------------
-- Your Handler stays put while you watch: the default controls if this place has them,
-- and the Humanoid's own speed / jump (restored on the way out) either way.
local savedMovement = nil
local function setControls(enabled: boolean)
	local scripts = localPlayer:FindFirstChild("PlayerScripts")
	local playerModule = scripts and scripts:FindFirstChild("PlayerModule")
	if playerModule then
		local ok, module = pcall(require, playerModule)
		if ok and module and module.GetControls then
			local controls = module:GetControls()
			if enabled then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if not enabled then
		savedMovement = { WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, JumpHeight = humanoid.JumpHeight }
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 0, 0, 0
		humanoid:Move(Vector3.zero)
	elseif savedMovement then
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = savedMovement.WalkSpeed, savedMovement.JumpPower, savedMovement.JumpHeight
		savedMovement = nil
	end
end

-- Every other screen GUI hides while you're in here (restored on the way out).
local function hideOtherGuis(hide: boolean)
	local playerGui = localPlayer:FindFirstChild("PlayerGui")
	if hide then
		state.hiddenGuis = {}
		for _, gui in playerGui:GetChildren() do
			if gui:IsA("ScreenGui") and gui ~= ui.Gui and gui.Enabled then
				gui.Enabled = false
				table.insert(state.hiddenGuis, gui)
			end
		end
	else
		for _, gui in state.hiddenGuis do
			if gui.Parent then
				gui.Enabled = true
			end
		end
		state.hiddenGuis = {}
	end
end

local function dip(to: number, duration: number)
	TweenService:Create(ui.Dip, TweenInfo.new(duration), { BackgroundTransparency = to }):Play()
	task.wait(duration)
end

function GymController:IsActive(): boolean
	return state.phase ~= nil
end

function GymController:Enter()
	if state.phase then
		return
	end
	local result = request:InvokeServer("Enter")
	if not result or not result.Ok then
		controllers.HUDController:Toast(result and result.Error or "The gym is closed right now.", C.Bad)
		return
	end
	state.phase = "Entering"
	state.bay = result.Bay
	state.summary = nil
	setPromptEnabled(false)
	setControls(false)
	hideOtherGuis(true)
	ui.Gui.Enabled = true
	ui.Panel.Visible = false
	ui.Mini.Visible = false
	ui.Dip.BackgroundTransparency = 1

	local entrance = GymDefinitions.EntranceCF()
	local door = liftDoor()
	-- 1. glide to the doors
	moveCamera(CFrame.lookAt((entrance * CFrame.new(0, 7, -21)).Position, (entrance * CFrame.new(0, 5.5, 0)).Position), 1.3, "InOut")
	-- 2. they grind open
	controllers.AudioController:Play("GymDoor")
	slideDoor(door, true, 1.2)
	task.wait(0.9)
	-- 3. push into the dark shaft; the server moves us while it's black
	local arrived
	task.spawn(function()
		task.wait(0.75)
		arrived = request:InvokeServer("Arrive")
	end)
	moveCamera(CFrame.lookAt((entrance * CFrame.new(0, 6, 9)).Position, (entrance * CFrame.new(0, 6, 20)).Position), 1.1, "In")
	dip(0, 0.2)
	local waited = os.clock()
	while arrived == nil and os.clock() - waited < 6 do
		task.wait(0.05)
	end
	slideDoor(door, false, 0.01)
	if not arrived or not arrived.Ok then
		self:Cleanup()
		controllers.HUDController:Toast(arrived and arrived.Error or "Couldn't reach the gym.", C.Bad)
		return
	end
	setSummary(arrived.Summary)
	-- 4. out of the gym's own lift, sweeping up over the hall
	local arrival = GymDefinitions.ArrivalCF()
	cine = nil
	camera.CFrame = CFrame.lookAt((arrival * CFrame.new(0, 7, 9)).Position, (arrival * CFrame.new(0, 7, -10)).Position)
	task.wait(0.15)
	dip(1, 0.35)
	state.phase = "Training"
	cine = nil
	local origin = GymDefinitions.Origin
	moveCamera(CFrame.lookAt((origin * CFrame.new(0, 24, 46)).Position, (origin * CFrame.new(0, 4, -24)).Position), 2.4, "InOut")
	-- 5. down onto our bay as the Nightmare arrives
	director.shot = 5
	local wide = shotFrame(5)
	if wide then
		moveCamera(wide, 2, "InOut")
	end
	cine = nil
	director.from = camera.CFrame
	director.blendStart = os.clock()
	director.changedAt = os.clock()
	self:SetPanelHidden(state.panelHidden)
end

-- (returns at once; the way out plays in its own thread)
function GymController:Leave()
	if state.phase ~= "Training" then
		return
	end
	state.phase = "Leaving"
	task.spawn(self.LeaveSequence, self)
end

function GymController:LeaveSequence()
	self:SkipReveal()
	ui.Panel.Visible = false
	ui.Mini.Visible = false
	local arrival = GymDefinitions.ArrivalCF()
	-- 1. back to the gym's lift (high, clear of the bench press) and into it
	moveCamera(CFrame.lookAt((arrival * CFrame.new(0, 12, -15)).Position, (arrival * CFrame.new(0, 7, 0)).Position), 1.6, "InOut")
	moveCamera(CFrame.lookAt((arrival * CFrame.new(0, 7, 9)).Position, (arrival * CFrame.new(0, 7, 20)).Position), 0.9, "In")
	dip(0, 0.2)
	local result = request:InvokeServer("Leave")
	-- 2. out of the Forge's doors, which close behind us
	local entrance = GymDefinitions.EntranceCF()
	local door = liftDoor()
	slideDoor(door, true, 0.01)
	cine = nil
	camera.CFrame = CFrame.lookAt((entrance * CFrame.new(0, 6, 10)).Position, (entrance * CFrame.new(0, 5, -20)).Position)
	task.wait(0.2)
	dip(1, 0.3)
	moveCamera(CFrame.lookAt((entrance * CFrame.new(7, 7, -18)).Position, (entrance * CFrame.new(0, 5, 0)).Position), 1.5, "Out")
	controllers.AudioController:Play("GymDoor")
	slideDoor(door, false, 1.1)
	task.wait(1.1)
	-- 3. back behind you
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		moveCamera(CFrame.lookAt((root.CFrame * CFrame.new(0, 4, 12)).Position, (root.CFrame * CFrame.new(0, 2, -10)).Position), 0.8, "InOut")
	end
	self:Cleanup()
	if result and result.Ok then
		local count = result.Rewards or 0
		controllers.HUDController:Toast(("Trained %s · %d reward%s · best %s"):format(clock(result.Time or 0), count, count == 1 and "" or "s", result.Best and tierName(result.Best):upper() or "—"), Color3.fromRGB(255, 120, 150), 4)
	end
end

-- Restore everything (also used when you die / respawn in there).
function GymController:Cleanup()
	state.phase = nil
	state.bay = nil
	state.reveal = nil
	cine = nil
	director.override = nil
	ui.Gui.Enabled = false
	ui.Dip.BackgroundTransparency = 1
	camera.CameraType = Enum.CameraType.Custom
	hideOtherGuis(false)
	setControls(true)
	setPromptEnabled(true)
end

function GymController:Buy(boostId: string)
	local def = GymDefinitions.Boosts[boostId]
	local result = request:InvokeServer("Buy", boostId)
	if result and result.Ok then
		setSummary(result.Summary)
		popup(("%s active!"):format(def.Name), C.Warn)
	else
		popup(result and result.Error or "Couldn't buy that.", C.Bad)
	end
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function GymController:Init(registry)
	controllers = registry
end

function GymController:Start()
	request = Net.Get("GymRequest")
	event = Net.Get("GymEvent")
	buildUI()

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "EnterGym" then
			task.spawn(self.Enter, self)
		end
	end)
	event.OnClientEvent:Connect(function(kind, data)
		if kind == "Reward" and type(data) == "table" then
			onReward(data)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not state.phase then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			self:SkipReveal()
		elseif input.KeyCode == Enum.KeyCode.H and state.phase == "Training" then
			self:SetPanelHidden(not state.panelHidden)
		end
	end)

	-- the camera changes angle when the Nightmare moves on to another exercise
	controllers.NightmareAnimator.MarkerReached:Connect(function(model, action, name)
		strikeBag(model, name, action)
	end)
	-- an ability with no keyframed animation yet (no markers): it still lands on the bag at
	-- its windup, the moment the server would land it
	local watchedModels = {}
	local function watchForAbilities(model: Model)
		if watchedModels[model] then
			return
		end
		watchedModels[model] = true
		model:GetAttributeChangedSignal("ActionSeq"):Connect(function()
			local action = model:GetAttribute("ActionName")
			if not model:GetAttribute("GymBay") or type(action) ~= "string" or action:sub(1, 8) ~= "Ability_" then
				return
			end
			if NightmarePoses.Common[action] then
				return -- keyframed: its own Hit marker strikes the bag
			end
			task.delay(model:GetAttribute("ActionWindup") or 0.3, strikeBag, model, "Hit", action)
		end)
	end
	for _, model in CollectionService:GetTagged("Nightmare") do
		watchForAbilities(model)
	end
	CollectionService:GetInstanceAddedSignal("Nightmare"):Connect(watchForAbilities)
	task.spawn(function()
		local watched
		while true do
			task.wait(0.5)
			if state.phase == "Training" then
				local model = myNightmare()
				if model ~= watched then
					watched = model
					if model then
						model:GetAttributeChangedSignal("ActionSeq"):Connect(function()
							if state.phase == "Training" and not state.reveal and os.clock() - director.changedAt > 6 and math.random() < 0.6 then
								nextShot()
							end
						end)
					end
				end
				tickTimers()
			end
		end
	end)

	-- heavy bags (they're re-hung whenever a Nightmare starts or stops training)
	task.spawn(function()
		local root = Workspace:WaitForChild("NightmareForgeHub", 60)
		local h = root and root:WaitForChild("NightmareGym", 60)
		local folder = h and h:WaitForChild("Bags", 60)
		if not folder then
			return
		end
		for _, model in folder:GetChildren() do
			task.defer(trackBag, model)
		end
		folder.ChildAdded:Connect(function(model)
			task.defer(trackBag, model)
		end)
	end)
	RunService:BindToRenderStep("GymCamera", Enum.RenderPriority.Camera.Value + 1, renderCamera)
	RunService.Heartbeat:Connect(stepBags)

	localPlayer.CharacterAdded:Connect(function()
		if state.phase then
			self:Cleanup()
		end
	end)
end

return GymController
