--[[
	UIKit  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/UIKit

	Construction helpers, the palette and THE GAME'S LOOK: everything is forged. Panels are dark
	iron plates with brackets and rivets on their corners, buttons are stamped metal in their
	colour, bars are troughs with a hot fill and a chip of the last hit draining behind it, and
	the type is scratched horror lettering over bone white. Every screen gets it from here: a Frame with a stroke
	is a plate (New), a Frame with a corner is a card, UIKit.Button and UIKit.Bar are the rest.
]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local UIKit = {}

local RGB = Color3.fromRGB

UIKit.Colors = {
	Background = RGB(12, 9, 11),
	Panel = RGB(24, 18, 20),
	PanelLight = RGB(46, 34, 34),
	PanelLighter = RGB(72, 54, 50),
	Accent = RGB(232, 72, 38), -- ember
	Accent2 = RGB(155, 95, 255), -- the Nightmare's own violet
	Text = RGB(240, 230, 212), -- bone
	SubText = RGB(176, 158, 142), -- ash
	Good = RGB(120, 225, 110),
	Bad = RGB(245, 70, 60),
	Warn = RGB(255, 186, 60),
	HandlerHP = RGB(120, 215, 105),
	NightmareHP = RGB(170, 90, 255),
	EnemyHP = RGB(235, 60, 50),
	Iron = RGB(120, 100, 88),
	IronDark = RGB(38, 30, 30),
}

UIKit.FontDisplay = Enum.Font.Creepster -- (names, titles, banners)
UIKit.FontPunch = Enum.Font.Bangers -- (the numbers that fly off a hit)
UIKit.Font = Enum.Font.Oswald
UIKit.FontHeavy = Enum.Font.Oswald
UIKit.FontBody = Enum.Font.RobotoCondensed

local SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- A skin's pieces go in a Folder: a parent's UIListLayout doesn't lay them out.
local function skinFolder(inst: Instance): Folder
	local folder = inst:FindFirstChild("Skin")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Skin"
		folder.Parent = inst
	end
	return folder
end

local function piece(folder: Instance, props)
	local frame = Instance.new("Frame")
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = UIKit.Colors.Iron
	for k, v in props do
		frame[k] = v
	end
	frame.Parent = folder
	return frame
end

-- The plate's corners: an iron bracket and a rivet on each.
local function brackets(inst: GuiObject, color: Color3, arm: number, zIndex: number)
	local padding = inst:FindFirstChildOfClass("UIPadding")
	local padX, padY = padding and padding.PaddingLeft.Offset or 0, padding and padding.PaddingTop.Offset or 0
	local folder = skinFolder(inst)
	for _, corner in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local x, y = corner[1], corner[2]
		local offsetX, offsetY = x == 0 and -padX or padX, y == 0 and -padY or padY
		local anchor = Vector2.new(x, y)
		local position = UDim2.new(x, offsetX, y, offsetY)
		piece(folder, { AnchorPoint = anchor, Position = position, Size = UDim2.fromOffset(arm, 3), BackgroundColor3 = color, ZIndex = zIndex })
		piece(folder, { AnchorPoint = anchor, Position = position, Size = UDim2.fromOffset(3, arm), BackgroundColor3 = color, ZIndex = zIndex })
		local rivet = piece(folder, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, offsetX + (x == 0 and 7 or -7), y, offsetY + (y == 0 and 7 or -7)),
			Size = UDim2.fromOffset(5, 5),
			BackgroundColor3 = UIKit.Colors.SubText,
			ZIndex = zIndex,
		})
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = rivet
	end
end

-- A dark iron plate: lit from above, soot in it, brackets on the corners, and a pop when it opens.
local function dressPlate(frame: Frame)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, RGB(255, 245, 235)),
		ColorSequenceKeypoint.new(0.12, RGB(190, 175, 170)),
		ColorSequenceKeypoint.new(1, RGB(125, 112, 112)),
	})
	gradient.Rotation = 90
	gradient.Parent = frame
	local folder = skinFolder(frame)
	local padding = frame:FindFirstChildOfClass("UIPadding")
	local padX, padY = padding and padding.PaddingLeft.Offset or 0, padding and padding.PaddingTop.Offset or 0
	local soot = Instance.new("ImageLabel")
	soot.Name = "Soot"
	soot.BackgroundTransparency = 1
	soot.Image = SMOKE
	soot.ImageColor3 = RGB(0, 0, 0)
	soot.ImageTransparency = 0.55
	soot.ScaleType = Enum.ScaleType.Stretch
	soot.Position = UDim2.fromOffset(-padX, -padY)
	soot.Size = UDim2.new(1, padX * 2, 1, padY * 2)
	soot.ZIndex = 0
	soot.Parent = folder
	piece(folder, { Position = UDim2.fromOffset(-padX, -padY), Size = UDim2.new(1, padX * 2, 0, 1), BackgroundColor3 = RGB(255, 225, 190), BackgroundTransparency = 0.72, ZIndex = 0 })
	brackets(frame, UIKit.Colors.Iron, 18, 8)
	-- opening: settles down onto the screen
	frame:GetPropertyChangedSignal("Visible"):Connect(function()
		local scale = frame:FindFirstChildOfClass("UIScale")
		if frame.Visible and scale then
			local final = scale.Scale
			scale.Scale = final * 1.06
			TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = final }):Play()
		end
	end)
end

-- A smaller card inside a screen: the same light, no hardware.
local function dressCard(frame: Frame)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(RGB(255, 245, 235), RGB(165, 150, 150))
	gradient.Rotation = 90
	gradient.Parent = frame
end

local function isPanelSize(size: UDim2): boolean
	return size.X.Offset >= 200 or size.X.Scale >= 0.3
end

function UIKit.New(className: string, props, children)
	local inst = Instance.new(className)
	local parent
	for k, v in props or {} do
		if k == "Parent" then
			parent = v
		else
			inst[k] = v
		end
	end
	local stroked, cornered = false, false
	for _, child in children or {} do
		child.Parent = inst
		stroked = stroked or child:IsA("UIStroke")
		cornered = cornered or child:IsA("UICorner")
	end
	-- (the look: a stroked frame is a plate, a rounded one a card)
	if className == "Frame" and inst.BackgroundTransparency < 0.6 then
		if stroked and isPanelSize(inst.Size) then
			dressPlate(inst)
		elseif cornered then
			dressCard(inst)
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

-- Plates are cut square: a corner's just the edge taken off.
function UIKit.Corner(px: number?)
	return UIKit.New("UICorner", { CornerRadius = UDim.new(0, math.min(px or 8, 4)) })
end

function UIKit.Stroke(color: Color3, thickness: number?, transparency: number?)
	return UIKit.New("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UIKit.Padding(px: number)
	local u = UDim.new(0, px)
	return UIKit.New("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function UIKit.List(paddingPx: number?, direction)
	return UIKit.New("UIListLayout", {
		Padding = UDim.new(0, paddingPx or 6),
		FillDirection = direction or Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

local function applyDefaults(props, defaults)
	for k, v in defaults do
		if props[k] == nil then
			props[k] = v
		end
	end
end

-- props.MaxTextSize (custom) caps TextScaled text so it stays readable on big screens.
function UIKit.Label(props)
	local maxSize = props.MaxTextSize or 20
	props.MaxTextSize = nil
	-- (anything set big is a title: titles get the horror lettering)
	if maxSize >= 20 and (props.Font == nil or props.Font == UIKit.FontHeavy) then
		props.Font = UIKit.FontDisplay
	end
	applyDefaults(props, {
		BackgroundTransparency = 1,
		Font = UIKit.Font,
		TextColor3 = UIKit.Colors.Text,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextStrokeColor3 = RGB(8, 4, 4),
		TextStrokeTransparency = 0.55,
		Text = "",
	})
	local label = UIKit.New("TextLabel", props)
	UIKit.New("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = label })
	return label
end

function UIKit.Button(props, onActivated)
	local maxSize = props.MaxTextSize or 18
	props.MaxTextSize = nil
	applyDefaults(props, {
		BackgroundColor3 = UIKit.Colors.PanelLight,
		Font = UIKit.FontHeavy,
		TextColor3 = UIKit.Colors.Text,
		TextScaled = true,
		TextStrokeColor3 = RGB(8, 4, 4),
		TextStrokeTransparency = 0.25,
		AutoButtonColor = false,
		Text = "",
	})
	local button = UIKit.New("TextButton", props)
	if button.Font == UIKit.FontHeavy then
		button.FontFace = Font.new("rbxasset://fonts/families/Oswald.json", Enum.FontWeight.Bold)
	end
	-- (a hard outline on light lettering, none on dark: a selected tab's dark text stays crisp)
	local function outline()
		local c = button.TextColor3
		button.TextStrokeTransparency = (c.R + c.G + c.B) / 3 > 0.45 and 0 or 1
	end
	outline()
	button:GetPropertyChangedSignal("TextColor3"):Connect(outline)
	UIKit.Corner(8).Parent = button
	UIKit.New("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = button })
	UIKit.New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = button })
	-- stamped metal in its colour: lit along the top, dark along the bottom (strips, not a gradient
	-- on the button: that would dim its text too); it lifts under the pointer and sinks when pressed
	local skin = skinFolder(button)
	local lit = piece(skin, { Name = "Lit", Position = UDim2.new(0, -6, 0, -3), Size = UDim2.new(1, 12, 0.4, 0), BackgroundColor3 = RGB(255, 240, 220), BackgroundTransparency = 0, ZIndex = button.ZIndex })
	local litFade = UIKit.New("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.72, 1), Parent = lit })
	local dark = piece(skin, { Name = "Dark", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, -6, 1, 3), Size = UDim2.new(1, 12, 0.45, 0), BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 0, ZIndex = button.ZIndex })
	UIKit.New("UIGradient", { Rotation = 270, Transparency = NumberSequence.new(0.3, 1), Parent = dark })
	piece(skin, { Position = UDim2.new(0, -6, 0, -3), Size = UDim2.new(1, 12, 0, 1), BackgroundColor3 = RGB(255, 235, 205), BackgroundTransparency = 0.45, ZIndex = button.ZIndex })
	local grow = UIKit.New("UIScale", { Parent = button })
	local function push(scale: number, shine: number)
		TweenService:Create(grow, TweenInfo.new(0.09, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = scale }):Play()
		litFade.Transparency = NumberSequence.new(shine, 1)
	end
	button.MouseEnter:Connect(function()
		push(1.05, 0.45)
	end)
	button.MouseLeave:Connect(function()
		push(1, 0.72)
	end)
	button.MouseButton1Down:Connect(function()
		push(0.96, 0.9)
	end)
	button.MouseButton1Up:Connect(function()
		push(1.05, 0.45)
	end)
	if onActivated then
		button.Activated:Connect(function(...)
			if UIKit.OnClick then
				UIKit.OnClick() -- AudioController: click sound
			end
			onActivated(...)
		end)
	end
	return button
end

-- Set by AudioController; called on every UIKit button press.
UIKit.OnClick = nil

-- A trough in the iron: a hot fill, lit from above with a white-hot leading edge, notched every
-- quarter, and when it drops a chip of what was lost stays behind and drains after it.
function UIKit.Bar(props)
	local height = props.Size and props.Size.Y.Offset or 12
	local frame = UIKit.New("Frame", {
		Name = props.Name or "Bar",
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = RGB(9, 6, 7),
		BorderSizePixel = 0,
		Parent = props.Parent,
	})
	UIKit.New("UIStroke", { Color = height >= 10 and UIKit.Colors.IronDark or RGB(0, 0, 0), Thickness = height >= 10 and 2 or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = frame })
	local chip = UIKit.New("Frame", {
		Name = "Chip",
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = RGB(255, 235, 215),
		BorderSizePixel = 0,
		Parent = frame,
	})
	local fill = UIKit.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = props.Color,
		BorderSizePixel = 0,
		Parent = frame,
	})
	UIKit.New("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, RGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.3, RGB(235, 225, 225)),
			ColorSequenceKeypoint.new(1, RGB(120, 100, 105)),
		}),
		Rotation = 90,
		Parent = fill,
	})
	if height >= 6 then
		-- the leading edge, burning
		UIKit.New("Frame", { Name = "Edge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = RGB(255, 250, 235), BackgroundTransparency = 0.15, BorderSizePixel = 0, Parent = fill })
	end
	if height >= 12 then
		for i = 1, 3 do
			UIKit.New("Frame", { Name = "Notch", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(i / 4, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = RGB(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, ZIndex = 2, Parent = frame })
		end
	end
	local label = UIKit.Label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeTransparency = 0.15,
		MaxTextSize = props.MaxTextSize or 13,
		ZIndex = 3,
		Parent = frame,
	})
	return { Frame = frame, Fill = fill, Chip = chip, Label = label, Ratio = 1 }
end

function UIKit.SetBar(bar, current: number, max: number)
	local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0
	local last = bar.Ratio or ratio
	if math.abs(ratio - last) > 0.0005 then
		bar.Ratio = ratio
		local chip = bar.Chip
		if chip then
			if ratio < last - 0.002 then
				-- a hit: the chip holds where it was, then drains down to the new value
				chip.Size = UDim2.fromScale(math.max(chip.Size.X.Scale, last), 1)
				if bar.ChipTween then
					bar.ChipTween:Cancel()
				end
				bar.ChipTween = TweenService:Create(chip, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.28), { Size = UDim2.fromScale(ratio, 1) })
				bar.ChipTween:Play()
			else
				chip.Size = UDim2.fromScale(ratio, 1)
			end
		end
	end
	bar.Fill.Size = UDim2.fromScale(ratio, 1)
	bar.Fill.Visible = ratio > 0
	bar.Label.Text = ("%d / %d"):format(math.ceil(current), math.ceil(max))
end

-- A 3D picture of real parts of a body (a Nightmare's sculpted head, the part behind an ability):
-- clones `parts` into a ViewportFrame and frames them. Returns the camera, to turn it.
function UIKit.ShowParts(viewport: ViewportFrame, parts: { BasePart }, turn: number?, from: Vector3?)
	for _, child in viewport:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	if #parts == 0 then
		return nil
	end
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in parts do
		local copy = part:Clone()
		for _, child in copy:GetChildren() do
			if not child:IsA("SpecialMesh") and not child:IsA("SurfaceAppearance") then
				child:Destroy()
			end
		end
		copy.Anchored = true
		copy.CanCollide = false
		copy.Parent = world
		local half = part.Size / 2
		low = low:Min(part.Position - half)
		high = high:Max(part.Position + half)
	end
	local centre = (low + high) / 2
	local radius = math.max((high - low).Magnitude / 2, 0.5)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local look = (parts[1].Parent and parts[1].Parent:IsA("Model") and parts[1].Parent:FindFirstChild("HumanoidRootPart")) and parts[1].Parent.HumanoidRootPart.CFrame.LookVector or Vector3.new(0, 0, -1)
	local side = CFrame.Angles(0, math.rad(turn or 28), 0):VectorToWorldSpace(look)
	camera.CFrame = CFrame.lookAt(centre + (side + (from or Vector3.new(0, 0.12, 0))).Unit * radius / math.sin(math.rad(15)) * 0.92, centre)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.Ambient = RGB(150, 135, 130)
	viewport.LightColor = RGB(255, 225, 190)
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.5)
	return camera
end

-- Scales an offset-sized panel with the screen (phones -> smaller, 4K -> capped).
function UIKit.AutoScale(guiObject: GuiObject)
	local scale = UIKit.New("UIScale", { Parent = guiObject })
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		scale.Scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.25)
	end
	update()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

-- Where the bottom-centre HUD stack (abilities, meters, weapon hotbar, combo trail) is
-- centred: on touch screens left of the middle, far enough to clear the touch-button
-- cluster in the bottom-right (HUDController: 280 wide, 140 from the right edge; the stack
-- is 330 wide; both AutoScale), measured on an iPhone XR and an iPhone 7.
function UIKit.HudCenterX(): number
	local input = game:GetService("UserInputService")
	local camera = Workspace.CurrentCamera
	if not (input.TouchEnabled and not input.KeyboardEnabled) or not camera then
		return 0.5
	end
	local viewport = camera.ViewportSize
	if viewport.X < 200 then
		return 0.44 -- (the viewport isn't known yet)
	end
	local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.25)
	local fits = (viewport.X - 140 - 280 * scale - 165 * scale - 16) / viewport.X
	return math.clamp(fits, 0.36, 0.5)
end

-- Places a bottom-centre HUD piece (AnchorPoint 0.5, 1) `fromBottom` px up, at
-- HudCenterX, and keeps it there when the screen size changes (on phones the size isn't
-- known yet when the HUD is first built).
-- (`fromBottom` may be a function of the current AutoScale, for a piece stacked on top of
-- a scaled one)
-- (`touchNudge`: extra X, as a fraction of the screen, on touch screens only)
function UIKit.PlaceHudCenter(guiObject: GuiObject, fromBottom: number | (number) -> number, touchNudge: number?)
	local function place()
		local camera = Workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local scale = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.25)
		local offset = type(fromBottom) == "function" and fromBottom(scale) or fromBottom
		local x = UIKit.HudCenterX()
		if x < 0.5 then
			x += touchNudge or 0
		end
		guiObject.Position = UDim2.new(x, 0, 1, -offset)
	end
	place()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(place)
	end
end

-- Small screens (phones): a centred menu panel grows to almost full screen so its text
-- and buttons stay readable and tappable. Desktop keeps the panel's own size.
UIKit.SmallScreenHeight = 560
function UIKit.IsSmallScreen(): boolean
	local camera = Workspace.CurrentCamera
	return camera ~= nil and camera.ViewportSize.Y < UIKit.SmallScreenHeight
end

function UIKit.Responsive(panel: GuiObject)
	local desktopSize = panel.Size
	local function update()
		panel.Size = UIKit.IsSmallScreen() and UDim2.fromScale(0.95, 0.9) or desktopSize
	end
	update()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
end

-- True on phones / tablets (touch, no keyboard).
function UIKit.IsTouchOnly(): boolean
	local UserInputService = game:GetService("UserInputService")
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

function UIKit.ToHex(color: Color3): string
	return color:ToHex()
end

return UIKit
