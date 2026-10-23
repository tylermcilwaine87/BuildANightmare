--[[
	UIKit  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/UIKit

	Tiny UI construction helpers + the game's colour palette, so every screen shares one
	visual style (dark charcoal surfaces, purple/blue energy accents, rarity colours).
]]

local Workspace = game:GetService("Workspace")

local UIKit = {}

local RGB = Color3.fromRGB

UIKit.Colors = {
	Background = RGB(14, 12, 20),
	Panel = RGB(26, 23, 36),
	PanelLight = RGB(40, 36, 56),
	PanelLighter = RGB(56, 50, 78),
	Accent = RGB(150, 90, 255),
	Accent2 = RGB(70, 140, 255),
	Text = RGB(236, 232, 248),
	SubText = RGB(165, 158, 188),
	Good = RGB(90, 220, 120),
	Bad = RGB(240, 85, 85),
	Warn = RGB(255, 190, 60),
	HandlerHP = RGB(90, 200, 120),
	NightmareHP = RGB(170, 100, 255),
	EnemyHP = RGB(235, 70, 70),
}

UIKit.Font = Enum.Font.GothamBold
UIKit.FontHeavy = Enum.Font.GothamBlack
UIKit.FontBody = Enum.Font.Gotham

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
	for _, child in children or {} do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.Corner(px: number?)
	return UIKit.New("UICorner", { CornerRadius = UDim.new(0, px or 8) })
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
	applyDefaults(props, {
		BackgroundTransparency = 1,
		Font = UIKit.Font,
		TextColor3 = UIKit.Colors.Text,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
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
		AutoButtonColor = true,
		Text = "",
	})
	local button = UIKit.New("TextButton", props)
	UIKit.Corner(8).Parent = button
	UIKit.New("UITextSizeConstraint", { MaxTextSize = maxSize, MinTextSize = 8, Parent = button })
	UIKit.New("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 3), Parent = button })
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

function UIKit.Bar(props)
	local frame = UIKit.New("Frame", {
		Name = props.Name or "Bar",
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = RGB(18, 16, 26),
		BorderSizePixel = 0,
		Parent = props.Parent,
	}, { UIKit.Corner(6) })
	local fill = UIKit.New("Frame", {
		Name = "Fill",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = props.Color,
		BorderSizePixel = 0,
		Parent = frame,
	}, { UIKit.Corner(6) })
	local label = UIKit.Label({
		Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
		MaxTextSize = props.MaxTextSize or 13,
		Parent = frame,
	})
	return { Frame = frame, Fill = fill, Label = label }
end

function UIKit.SetBar(bar, current: number, max: number)
	local ratio = max > 0 and math.clamp(current / max, 0, 1) or 0
	bar.Fill.Size = UDim2.fromScale(ratio, 1)
	bar.Fill.Visible = ratio > 0
	bar.Label.Text = ("%d / %d"):format(math.ceil(current), math.ceil(max))
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
