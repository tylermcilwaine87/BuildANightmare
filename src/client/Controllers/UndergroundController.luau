--[[
	UndergroundController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/UndergroundController

	Client side of NIGHTMARE UNDERGROUND (server: UndergroundService + DuelService Mode
	"Underground"). PvPController hands it every duel "State"; in an Underground match it
	replaces the duel scoreboard with the fight HUD:
	  TOP LEFT     you: name, your Nightmare's name, health, guard, rounds won
	  TOP RIGHT    the opponent, the same
	  TOP CENTRE   ROUND n / 3, the round clock, the score
	  BOTTOM LEFT  your stance and the controls
	  CALLOUTS     what your blows just did: HEAVY IMPACT, GUARD BREAK, KNOCKDOWN, n HIT COMBO,
	               and the fight's own (UndergroundFightService "UGCallout": PARRY!, SLIPPED,
	               COUNTER!, GASSED, FEINT, the combo's name) under the plate of who it's about
	Also the "searching for an opponent" pill while you're in the queue (DuelEvent "UGQueue").
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local UndergroundController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local RGB = Color3.fromRGB
local RED, BLUE = RGB(255, 60, 70), RGB(80, 150, 255)
local STEEL = RGB(18, 16, 20)

local controllers
local ui = {}
local state = nil -- the latest Underground "State" (nil = not in an Underground match)
local chain = { Count = 0, At = 0 }

function UndergroundController:Init(registry)
	controllers = registry
end

function UndergroundController:IsInMatch(): boolean
	return state ~= nil
end

local fighters -- (defined below)

-- The other fighter's Nightmare (nil outside an Underground match).
function UndergroundController:GetOpponent(): Model?
	if not state then
		return nil
	end
	local _, theirs = fighters()
	return theirs
end

------------------------------------------------------------------------------------------
-- Who's who
------------------------------------------------------------------------------------------
function fighters(): (Model?, Model?)
	local character = localPlayer.Character
	local duelId = character and character:GetAttribute("DuelId")
	local mySide = character and character:GetAttribute("DuelSide")
	if not duelId then
		return nil, nil
	end
	local mine, theirs
	for _, model in CollectionService:GetTagged("Nightmare") do
		if model:GetAttribute("DuelId") == duelId then
			if model:GetAttribute("OwnerUserId") == localPlayer.UserId then
				mine = model
			elseif model:GetAttribute("DuelSide") ~= mySide then
				theirs = model
			end
		end
	end
	return mine, theirs
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
-- One fighter's plate (a corner of the screen): name, Nightmare, health, guard, round pips.
local function plate(parent: Instance, right: boolean, color: Color3)
	local frame = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(right and 1 or 0, 0),
		Position = right and UDim2.new(1, -16, 0, 60) or UDim2.new(0, 16, 0, 60), -- (below Roblox's top bar)
		Size = UDim2.fromOffset(380, 98),
		BackgroundColor3 = STEEL,
		BackgroundTransparency = 0.15,
		Parent = parent,
	}, { UIKit.Corner(6), UIKit.Stroke(color, 2, 0.15) })
	UIKit.AutoScale(frame)
	local align = right and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	-- a slab of the corner's colour along the outside edge
	UIKit.New("Frame", { AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = UDim2.fromScale(right and 1 or 0, 0), Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0, Parent = frame })
	local p = {}
	p.Name = UIKit.Label({ Position = UDim2.fromOffset(14, 4), Size = UDim2.new(1, -28, 0, 26), TextXAlignment = align, Font = UIKit.FontDisplay, TextColor3 = C.Text, MaxTextSize = 24, Parent = frame })
	p.Sub = UIKit.Label({ Position = UDim2.fromOffset(14, 30), Size = UDim2.new(1, -28, 0, 16), TextXAlignment = align, TextColor3 = C.SubText, MaxTextSize = 12, Parent = frame })
	p.Health = UIKit.Bar({ Position = UDim2.fromOffset(14, 50), Size = UDim2.new(1, -28, 0, 18), Color = color, MaxTextSize = 12, Parent = frame })
	p.Guard = UIKit.Bar({ Position = UDim2.fromOffset(14, 72), Size = UDim2.new(0.62, -14, 0, 8), Color = RGB(235, 225, 200), Parent = frame })
	if right then
		p.Guard.Frame.AnchorPoint = Vector2.new(1, 0)
		p.Guard.Frame.Position = UDim2.new(1, -14, 0, 72)
	end
	p.Guard.Label.Visible = false
	-- stamina (UndergroundFightService): under the guard, gold, red when gassed
	p.Stamina = UIKit.Bar({ Position = UDim2.fromOffset(14, 84), Size = UDim2.new(0.62, -14, 0, 6), Color = RGB(255, 200, 60), Parent = frame })
	if right then
		p.Stamina.Frame.AnchorPoint = Vector2.new(1, 0)
		p.Stamina.Frame.Position = UDim2.new(1, -14, 0, 84)
	end
	p.Stamina.Label.Visible = false
	-- what just happened to this fighter (PARRY!, SLIPPED, GASSED, a combo's name), under the plate
	p.Flash = UIKit.Label({ AnchorPoint = Vector2.new(right and 1 or 0, 0), Position = right and UDim2.new(1, -4, 1, 6) or UDim2.new(0, 4, 1, 6), Size = UDim2.fromOffset(372, 26), TextXAlignment = align, Font = UIKit.FontPunch, TextColor3 = C.Warn, TextStrokeTransparency = 0.2, MaxTextSize = 24, Visible = false, Parent = frame })
	p.Pips =UIKit.Label({ AnchorPoint = Vector2.new(right and 0 or 1, 0), Position = right and UDim2.fromOffset(14, 68) or UDim2.new(1, -14, 0, 68), Size = UDim2.fromOffset(110, 18), TextXAlignment = right and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right, TextColor3 = C.Warn, MaxTextSize = 14, Parent = frame })
	p.Frame = frame
	return p
end

function UndergroundController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "UndergroundGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 17, Enabled = false, Parent = localPlayer:WaitForChild("PlayerGui") })
	ui.Gui = gui
	ui.Me = plate(gui, false, RED)
	ui.Them = plate(gui, true, BLUE)

	-- the clock in the middle
	local clock = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 56), Size = UDim2.fromOffset(190, 100), BackgroundColor3 = STEEL, BackgroundTransparency = 0.1, Parent = gui }, { UIKit.Corner(6), UIKit.Stroke(RGB(120, 110, 120), 1, 0.3) })
	UIKit.AutoScale(clock)
	ui.Round = UIKit.Label({ Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 13, Parent = clock })
	ui.Timer = UIKit.Label({ Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 46), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontPunch, TextColor3 = C.Text, MaxTextSize = 44, Parent = clock })
	ui.Score = UIKit.Label({ Position = UDim2.fromOffset(0, 68), Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontDisplay, TextColor3 = C.Warn, MaxTextSize = 24, Parent = clock })

	-- your stance and the controls, bottom left
	local hints = UIKit.New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -16), Size = UDim2.fromOffset(470, 88), BackgroundColor3 = STEEL, BackgroundTransparency = 0.25, Parent = gui }, { UIKit.Corner(6), UIKit.Padding(8) })
	UIKit.AutoScale(hints)
	ui.Stance = UIKit.Label({ Size = UDim2.new(1, 0, 0, 20), TextColor3 = C.Warn, MaxTextSize = 15, Parent = hints })
	ui.Controls = UIKit.Label({ Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 1, -22), TextColor3 = C.SubText, Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 12, Parent = hints })

	-- the callout: what your last blows did
	ui.Callout = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 168), Size = UDim2.fromOffset(520, 44), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontPunch, TextColor3 = C.Warn, TextStrokeTransparency = 0.1, MaxTextSize = 40, Visible = false, Parent = gui })
	ui.CalloutSub = UIKit.Label({ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 210), Size = UDim2.fromOffset(520, 22), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Text, MaxTextSize = 16, Visible = false, Parent = gui })

	-- the queue pill (outside a match)
	local queueGui = UIKit.New("ScreenGui", { Name = "UndergroundQueueGui", ResetOnSpawn = false, DisplayOrder = 16, Enabled = false, Parent = localPlayer.PlayerGui })
	ui.QueueGui = queueGui
	local pill = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 60), Size = UDim2.fromOffset(420, 40), BackgroundColor3 = STEEL, BackgroundTransparency = 0.1, Parent = queueGui }, { UIKit.Corner(20), UIKit.Stroke(RED, 2, 0.2) })
	UIKit.AutoScale(pill)
	ui.QueueText = UIKit.Label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Text, MaxTextSize = 15, Parent = pill })
end

function UndergroundController:Callout(title: string, subtitle: string?, color: Color3?)
	ui.Callout.Text = title
	ui.Callout.TextColor3 = color or C.Warn
	ui.Callout.Visible = true
	ui.Callout.TextTransparency = 0
	ui.CalloutSub.Text = subtitle or ""
	ui.CalloutSub.Visible = subtitle ~= nil
	ui.CalloutSub.TextTransparency = 0
	local token = (ui.CalloutToken or 0) + 1
	ui.CalloutToken = token
	local grow = ui.Callout:FindFirstChildOfClass("UIScale") or UIKit.New("UIScale", { Parent = ui.Callout })
	grow.Scale = 1.35
	TweenService:Create(grow, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(1.3, function()
		if ui.CalloutToken == token then
			TweenService:Create(ui.Callout, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
			TweenService:Create(ui.CalloutSub, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
		end
	end)
end

------------------------------------------------------------------------------------------
-- State
------------------------------------------------------------------------------------------
local function pips(won: number, needed: number): string
	return string.rep("◆", won) .. string.rep("◇", math.max(0, needed - won))
end

function UndergroundController:ApplyState(data)
	if not ui.Gui then
		return
	end
	if data.State == "None" or data.Mode ~= "Underground" then
		if state then
			controllers.HUDController:SetUndergroundMode(false)
		end
		state = nil
		ui.Gui.Enabled = false
		return
	end
	controllers.HUDController:SetUndergroundMode(true)
	if not state or state.Round ~= data.Round then
		ui.RoundStartedAt = os.clock()
	end
	state = data
	ui.Gui.Enabled = true
	ui.QueueGui.Enabled = false
	local needed = math.ceil((data.BestOf or 3) / 2)
	ui.Me.Name.Text = string.upper(data.MyName or localPlayer.DisplayName)
	ui.Them.Name.Text = string.upper(data.OpponentName or "?")
	ui.Me.Pips.Text = pips(data.MyScore or 0, needed)
	ui.Them.Pips.Text = pips(data.OpponentScore or 0, needed)
	ui.Round.Text = ("ROUND %d / %d"):format(math.max(data.Round or 1, 1), data.BestOf or 3)
	ui.Score.Text = ("%d — %d"):format(data.MyScore or 0, data.OpponentScore or 0)
end

function UndergroundController:SetQueue(data)
	if not ui.QueueGui then
		return
	end
	local searching = data.Searching == true and not state
	ui.QueueGui.Enabled = searching
	if searching then
		ui.QueueText.Text = ("NIGHTMARE UNDERGROUND  ·  searching for an opponent  ·  %d in the queue"):format(data.Waiting or 1)
	end
end

local function updatePlate(p, model: Model?)
	local humanoid = model and model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		UIKit.SetBar(p.Health, 0, 1)
		p.Sub.Text = "—"
		return
	end
	UIKit.SetBar(p.Health, math.max(humanoid.Health, 0), humanoid.MaxHealth)
	local guard = model:GetAttribute("GuardLevel") or Config.Block.Max
	UIKit.SetBar(p.Guard, guard, Config.Block.Max)
	p.Guard.Fill.BackgroundColor3 = model:GetAttribute("GuardBroken") and C.Bad or (guard < Config.Block.CrackAt and C.Warn or RGB(235, 225, 200))
	local stamina = Config.Underground.Fight.Stamina
	UIKit.SetBar(p.Stamina, model:GetAttribute("UGStamina") or stamina.Max, stamina.Max)
	p.Stamina.Fill.BackgroundColor3 = model:GetAttribute("UGGassed") and C.Bad or RGB(255, 200, 60)
	local name = model:GetAttribute("NightmareName") or "Nightmare"
	local archetype = model:GetAttribute("Archetype") or ""
	p.Sub.Text = ("%s  ·  %s"):format(string.upper(name), string.upper(archetype))
end

function UndergroundController:UpdateFrame()
	if not state then
		return
	end
	local mine, theirs = fighters()
	updatePlate(ui.Me, mine)
	updatePlate(ui.Them, theirs)

	-- a fighting game's camera: locked on to the other fighter from the corner onwards (Z lets
	-- go; it locks again next round)
	local lock = controllers.LockOnController
	local theirHumanoid = theirs and theirs:FindFirstChildOfClass("Humanoid")
	if (state.State == "Live" or state.State == "Countdown") and controllers.PossessionController:IsBound()
		and theirHumanoid and theirHumanoid.Health > 0 and not lock:IsLocked()
		and lock:ReleasedByPlayerAt() < (ui.RoundStartedAt or 0) then
		lock:Lock(theirs)
	end

	-- the clock
	local left = math.max(0, (state.PhaseEndsAt or 0) - Workspace:GetServerTimeNow())
	local phase = state.State
	if phase == "Live" then
		ui.Timer.Text = ("%d:%02d"):format(math.floor(left / 60), math.floor(left % 60))
		ui.Timer.TextColor3 = left <= 10 and C.Bad or C.Text
	elseif phase == "Countdown" then
		ui.Timer.Text = tostring(math.max(1, math.ceil(left)))
		ui.Timer.TextColor3 = C.Warn
	elseif phase == "Prep" then
		ui.Timer.Text = ("PICK %d"):format(math.ceil(left))
		ui.Timer.TextColor3 = C.SubText
	else
		ui.Timer.Text = "—"
		ui.Timer.TextColor3 = C.SubText
	end

	-- your stance
	local status
	if mine and mine:GetAttribute("GuardBroken") then
		status = "GUARD BROKEN"
	elseif mine and mine:GetAttribute("Ragdolled") then
		status = "DOWN!"
	elseif mine and mine:GetAttribute("Guarding") then
		status = mine:GetAttribute("GuardLow") and "LOW GUARD (body)" or "HIGH GUARD (head)"
	else
		status = phase == "Live" and "FIGHTING" or (phase == "Countdown" and "IN YOUR CORNER" or "BETWEEN ROUNDS")
	end
	if mine and mine:GetAttribute("UGGassed") then
		status ..= "  ·  GASSED"
	end
	ui.Stance.Text = ("STANCE  ·  %s"):format(status)
	local touch = UIKit.IsTouchOnly()
	local pad = not touch and UserInputService:GetLastInputType().Name:sub(1, 7) == "Gamepad"
	local L, H = touch and "ATK" or pad and "R2" or "LMB", touch and "KICK" or pad and "X" or "RMB"
	local G, D = touch and "GUARD" or pad and "L2" or "Ctrl", touch and "DIVE" or pad and "B" or "Shift"
	-- (the strings, Config.Underground.Fight Strings: presses of one button chain, the power
	-- button finishes)
	ui.Controls.Text = ("%s ×1-4: jab, cross, hook, uppercut  ·  %s: overhand\n%s then %s: liver  ·  ×2 then %s: overhand  ·  ×3 then %s: LAUNCHER\n%s: guard (+back: low)  ·  just as they swing: PARRY  ·  %s+dir: slip")
		:format(L, H, L, H, H, H, G, D)
end

-- A callout from the server (UndergroundFightService): under the plate of the fighter it's
-- about; your own combos also big in the middle.
local CALLOUT_COLORS = { Good = RGB(120, 255, 150), Bad = RGB(255, 90, 90), Combo = RGB(255, 210, 90), Info = RGB(220, 220, 230) }
function UndergroundController:Flash(p, text: string, color: Color3)
	p.Flash.Text = text
	p.Flash.TextColor3 = color
	p.Flash.TextTransparency = 0
	p.Flash.Visible = true
	local token = (p.FlashToken or 0) + 1
	p.FlashToken = token
	task.delay(1.2, function()
		if p.FlashToken == token then
			TweenService:Create(p.Flash, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		end
	end)
end

local function onCallout(data)
	if not state or typeof(data.Target) ~= "Instance" or type(data.Text) ~= "string" then
		return
	end
	local mine, theirs = fighters()
	local color = CALLOUT_COLORS[data.Kind] or C.Warn
	if data.Target == mine then
		UndergroundController:Flash(ui.Me, data.Text, color)
		if data.Kind == "Combo" or data.Text == "COUNTER!" or data.Text == "PARRY!" then
			UndergroundController:Callout(data.Text, chain.Count >= 2 and ("%d HIT COMBO"):format(chain.Count) or nil, color)
		end
	elseif data.Target == theirs then
		UndergroundController:Flash(ui.Them, data.Text, color)
	end
end

-- A blow you landed on the other fighter: the callout says what it did.
local function onFeedback(kind: string, data)
	if kind == "UGCallout" and type(data) == "table" then
		onCallout(data)
		return
	end
	if not state or kind ~= "Damage" or type(data) ~= "table" then
		return
	end
	local mine, theirs = fighters()
	if not mine or data.Attacker ~= mine or data.Target ~= theirs then
		return
	end
	local now = os.clock()
	chain.Count = (now - chain.At <= 1.4) and chain.Count + 1 or 1
	chain.At = now
	if data.KnockedDown then
		UndergroundController:Callout("KNOCKDOWN!", nil, C.Bad)
	elseif data.GuardBroken then
		UndergroundController:Callout("GUARD BREAK", nil, C.Warn)
	elseif data.Heavy and not data.Guarded then
		UndergroundController:Callout("HEAVY IMPACT", chain.Count >= 3 and ("%d HIT COMBO"):format(chain.Count) or nil, C.Warn)
	elseif chain.Count >= 3 then
		UndergroundController:Callout(("%d HIT COMBO"):format(chain.Count), nil, C.Text)
	end
end

function UndergroundController:Start()
	self:BuildGui()
	Net.Get("CombatFeedback").OnClientEvent:Connect(onFeedback)
	RunService.RenderStepped:Connect(function()
		self:UpdateFrame()
	end)
end

return UndergroundController
