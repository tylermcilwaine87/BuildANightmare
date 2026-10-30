--[[
	RewardController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/RewardController

	Post-victory reward screen (RewardNotification remote):
	  1. Victory title, fight time / best time
	  2. XP, coins, essence (+ level up)
	  3. Part reveal with rarity-specific drama. LEGENDARY: the screen darkens, gold
	     cracks spread, then the part emerges and its name is announced. SKIP at any time.
	  4. Part card: rarity, slot, stats, ability, NEW badge, pity guarantee note
	  5. EQUIP NOW (returns to the Forge and opens the Workshop on that part),
	     FIGHT AGAIN, RETURN TO FORGE
	The server already granted everything before this screen appears; it is display only.
	Audio: rarity sound hooks are marked PLACEHOLDER below (add rbxassetid values).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PartMeshes = require(Shared:WaitForChild("PartMeshes"))
local Net = require(Shared:WaitForChild("Net"))
local Config = require(Shared:WaitForChild("Config"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local RewardController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local controllers
local ui = {}
local isOpen = false
local revealToken = 0
local currentReward = nil

-- Reveal sounds: AudioDefinitions RevealUncommon / RevealRare / RevealEpic / RevealLegendary.
local REVEAL_TIME = { Uncommon = 0.4, Rare = 0.8, Epic = 1.2, Legendary = 2.4 }

function RewardController:Init(registry)
	controllers = registry
end

function RewardController:IsOpen(): boolean
	return isOpen
end

local function playSound(rarity: string)
	controllers.AudioController:Play("Reveal" .. rarity)
end

local function statText(stats): string
	local parts = {}
	for _, row in StatCalculator.DisplayOrder do
		local v = stats[row.Key]
		if v and v ~= 0 then
			table.insert(parts, ("%s%d %s"):format(v > 0 and "+" or "", v, row.Label))
		end
	end
	return table.concat(parts, "  ·  ")
end

function RewardController:BuildGui()
	local screen = UIKit.New("ScreenGui", {
		Name = "RewardGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 30,
		Enabled = false,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	ui.Screen = screen
	ui.Dim = UIKit.New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, Parent = screen })

	local body = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 0.85),
		BackgroundTransparency = 1,
		Parent = screen,
	})
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(820, 700), Parent = body })

	ui.Title = UIKit.Label({ Text = "VICTORY!", Size = UDim2.fromScale(1, 0.12), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, TextColor3 = C.Good, TextStrokeTransparency = 0.3, MaxTextSize = 54, Parent = body })
	ui.Time = UIKit.Label({ Position = UDim2.fromScale(0, 0.12), Size = UDim2.fromScale(1, 0.05), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 18, Parent = body })
	ui.Progress = UIKit.Label({ Position = UDim2.fromScale(0, 0.18), Size = UDim2.fromScale(1, 0.06), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Warn, MaxTextSize = 20, Parent = body })

	-- Legendary cracks (thin gold lines radiating from the card centre).
	ui.Cracks = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromScale(1, 0.6), BackgroundTransparency = 1, Parent = body })
	ui.CrackLines = {}
	for i = 1, 10 do
		local line = UIKit.New("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, 0, 0, 3),
			Rotation = (i - 1) * 36 + math.random(-12, 12),
			BackgroundColor3 = Color3.fromRGB(255, 205, 80),
			BorderSizePixel = 0,
			Visible = false,
			Parent = ui.Cracks,
		})
		table.insert(ui.CrackLines, line)
	end

	-- Part card
	local card = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromScale(0.62, 0.42),
		BackgroundColor3 = C.Panel,
		Parent = body,
	}, { UIKit.Corner(14), UIKit.Padding(14) })
	ui.Card = card
	ui.CardStroke = UIKit.Stroke(C.SubText, 4, 0)
	ui.CardStroke.Parent = card
	ui.CardScale = UIKit.New("UIScale", { Scale = 1, Parent = card })
	ui.CardRarity = UIKit.Label({ Size = UDim2.fromScale(0.7, 0.12), Font = UIKit.FontHeavy, MaxTextSize = 18, Parent = card })
	ui.CardNew = UIKit.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.3, 0.12), TextXAlignment = Enum.TextXAlignment.Right, Font = UIKit.FontHeavy, TextColor3 = C.Warn, MaxTextSize = 18, Parent = card })
	ui.CardName = UIKit.Label({ Position = UDim2.fromScale(0, 0.13), Size = UDim2.fromScale(0.62, 0.2), Font = UIKit.FontHeavy, MaxTextSize = 34, Parent = card })
	ui.CardMeta = UIKit.Label({ Position = UDim2.fromScale(0, 0.34), Size = UDim2.fromScale(0.62, 0.1), TextColor3 = C.SubText, MaxTextSize = 15, Parent = card })
	ui.CardDesc = UIKit.Label({ Position = UDim2.fromScale(0, 0.46), Size = UDim2.fromScale(0.62, 0.18), Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 15, Parent = card })
	ui.CardStats = UIKit.Label({ Position = UDim2.fromScale(0, 0.66), Size = UDim2.fromScale(1, 0.14), TextColor3 = C.Accent2, MaxTextSize = 15, Parent = card })
	ui.CardAbility = UIKit.Label({ Position = UDim2.fromScale(0, 0.82), Size = UDim2.fromScale(1, 0.18), TextColor3 = C.Accent, MaxTextSize = 15, Parent = card })
	-- what you won, in 3D, turning slowly on the right of the card
	ui.CardPart = UIKit.New("ViewportFrame", { Position = UDim2.fromScale(0.62, 0.12), Size = UDim2.fromScale(0.38, 0.54), BackgroundTransparency = 1, Parent = card })
	RunService.RenderStepped:Connect(function(dt)
		local camera = ui.CardCamera
		if camera and ui.Screen and ui.Screen.Enabled and ui.Card.Visible then
			camera.CFrame = CFrame.new(ui.CardFocus) * CFrame.Angles(0, dt * 0.9, 0) * CFrame.new(-ui.CardFocus) * camera.CFrame
		end
	end)

	ui.Pity = UIKit.Label({ Position = UDim2.fromScale(0, 0.76), Size = UDim2.fromScale(1, 0.05), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.SubText, MaxTextSize = 15, Parent = body })

	local buttons = UIKit.New("Frame", { Position = UDim2.fromScale(0, 0.84), Size = UDim2.fromScale(1, 0.1), BackgroundTransparency = 1, Parent = body }, { UIKit.List(10, Enum.FillDirection.Horizontal) })
	buttons:FindFirstChildOfClass("UIListLayout").HorizontalAlignment = Enum.HorizontalAlignment.Center
	ui.EquipButton = UIKit.Button({ Text = "EQUIP NOW", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = C.Good, TextColor3 = C.Background, LayoutOrder = 1, Parent = buttons }, function()
		self:Equip()
	end)
	UIKit.Button({ Text = "FIGHT AGAIN", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = Color3.fromRGB(220, 90, 40), LayoutOrder = 2, Parent = buttons }, function()
		self:Replay()
	end)
	UIKit.Button({ Text = "RETURN TO FORGE", Size = UDim2.fromScale(0.3, 1), BackgroundColor3 = C.PanelLighter, LayoutOrder = 3, Parent = buttons }, function()
		self:Return()
	end)
	ui.Buttons = buttons

	ui.Skip = UIKit.Button({ Text = "SKIP ▶", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -20, 1, -20), Size = UDim2.fromOffset(120, 44), BackgroundColor3 = C.PanelLighter, Parent = screen }, function()
		self:FinishReveal()
	end)
end

------------------------------------------------------------------------------------------
-- Reveal
------------------------------------------------------------------------------------------
function RewardController:FillCard(entry)
	local def = PartDefinitions.Get(entry.Id)
	local rarity = RarityDefinitions.Info[entry.Rarity]
	ui.CardStroke.Color = rarity.Color
	ui.CardRarity.Text = rarity.DisplayName
	ui.CardRarity.TextColor3 = rarity.Color
	ui.CardNew.Text = entry.IsNew and "NEW!" or "DUPLICATE"
	ui.CardNew.TextColor3 = entry.IsNew and C.Warn or C.SubText
	ui.CardName.Text = def and def.DisplayName or entry.Id
	ui.CardName.TextColor3 = rarity.Color
	local slotName = def and def.Slot or "?"
	ui.CardMeta.Text = ("%s part  ·  Power Cost %d%s"):format(slotName, def and def.PowerCost or 0, def and def.Movement and ("  ·  " .. def.Movement .. " movement") or "")
	ui.CardDesc.Text = def and def.Description or ""
	ui.CardStats.Text = def and statText(def.Stats) or ""
	-- the part itself: its own sculpted meshes (the templates are imported turned about Y)
	local templates = Shared:FindFirstChild("Meshes") and Shared.Meshes:FindFirstChild("PartMeshes")
	local parts = {}
	for _, mesh in (templates and PartMeshes[entry.Id]) or {} do
		local template = templates:FindFirstChild(mesh.Mesh)
		if template then
			local part = template:Clone()
			part.Size, part.Color, part.Material = mesh.Size, mesh.Color, mesh.Material
			part.CFrame = CFrame.new(mesh.Pos) * CFrame.Angles(0, math.pi, 0)
			table.insert(parts, part)
		end
	end
	ui.CardCamera = UIKit.ShowParts(ui.CardPart, parts, 30)
	if ui.CardCamera then
		local low, high = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, part in parts do
			low = low:Min(part.Position - part.Size / 2)
			high = high:Max(part.Position + part.Size / 2)
		end
		ui.CardFocus = (low + high) / 2
	end
	local ability = def and AbilityDefinitions.Get(def.AbilityId)
	ui.CardAbility.Text = ability and ("Ability: %s (%s) — %s"):format(ability.DisplayName, ability.Type, ability.Description) or ("Passive: " .. (def and def.PlannedAbility or "—"))
	if entry.Pity then
		ui.CardAbility.Text ..= "\nPITY GUARANTEE!"
	end

	-- Mutated drop: mutation colour frame, full name, combined stats, its effect.
	local mutation = MutationDefinitions.Get(entry.Mutation)
	if mutation then
		ui.CardStroke.Color = mutation.Color
		ui.CardRarity.Text = ("%s  ·  ★ %s MUTATION"):format(rarity.DisplayName, string.upper(mutation.DisplayName))
		ui.CardNew.Text = entry.MutationNew and "NEW MUTATION!" or (entry.IsNew and "NEW!" or "MUTATED")
		ui.CardNew.TextColor3 = mutation.Color
		ui.CardName.Text = MutationDefinitions.FullName(def and def.DisplayName or entry.Id, entry.Mutation)
		local combined = table.clone(def and def.Stats or {})
		for key, value in mutation.Stats do
			combined[key] = (combined[key] or 0) + value
		end
		ui.CardStats.Text = statText(combined)
		ui.CardMeta.Text ..= ("  (+%d mutation)"):format(mutation.PowerCost)
		ui.CardAbility.Text ..= ("\n★ %s"):format(mutation.Description)
	end
end

function RewardController:FinishReveal()
	revealToken += 1
	ui.Skip.Visible = false
	ui.Card.Visible = true
	ui.CardScale.Scale = 1
	ui.Cracks.Visible = false
	ui.Buttons.Visible = true
	ui.Dim.BackgroundTransparency = 0.35
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.EquipButton
	end
end

function RewardController:Reveal(entry)
	revealToken += 1
	local token = revealToken
	local rarity = entry.Rarity
	local duration = REVEAL_TIME[rarity] or 0.5
	self:FillCard(entry)
	ui.Card.Visible = false
	ui.Buttons.Visible = false
	ui.Skip.Visible = true
	ui.Cracks.Visible = false

	task.spawn(function()
		if rarity == "Legendary" then
			-- Darken, crack, emerge.
			TweenService:Create(ui.Dim, TweenInfo.new(0.5), { BackgroundTransparency = 0.05 }):Play()
			task.wait(0.5)
			ui.Cracks.Visible = true
			for _, line in ui.CrackLines do
				if revealToken ~= token then
					return
				end
				line.Visible = true
				line.Size = UDim2.new(0, 0, 0, 3)
				TweenService:Create(line, TweenInfo.new(0.25), { Size = UDim2.new(0.5, 0, 0, 3) }):Play()
				task.wait(0.09)
			end
			task.wait(0.5)
		else
			task.wait(duration * 0.5)
		end
		if revealToken ~= token then
			return
		end
		playSound(rarity)
		ui.Card.Visible = true
		ui.CardScale.Scale = 0.2
		TweenService:Create(ui.CardScale, TweenInfo.new(rarity == "Legendary" and 0.8 or 0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.wait(rarity == "Legendary" and 1.2 or 0.5)
		if revealToken == token then
			self:FinishReveal()
		end
	end)
end

------------------------------------------------------------------------------------------
-- Show / buttons
------------------------------------------------------------------------------------------
function RewardController:Show(summary)
	currentReward = summary
	isOpen = true
	ui.Screen.Enabled = true
	controllers.CombatController:SetGuard(false)

	if summary.Mode == "Tutorial" then
		ui.Title.Text = "TRAINING VICTORY!"
	elseif summary.Mode == "Normal" or not Config.Difficulties[summary.Mode] then
		ui.Title.Text = "VICTORY!"
	else
		ui.Title.Text = Config.Difficulties[summary.Mode].DisplayName .. " VICTORY!"
	end
	local best = summary.BestTime and ("  ·  Best %d:%02d"):format(summary.BestTime // 60, summary.BestTime % 60) or ""
	ui.Time.Text = ("%s defeated in %d:%02d%s"):format(summary.BossName, summary.Time // 60, summary.Time % 60, best)
	local p = summary.Progress or {}
	local levelText = (p.LevelAfter and p.LevelBefore and p.LevelAfter > p.LevelBefore) and ("   ·   LEVEL UP → %d!"):format(p.LevelAfter) or ""
	ui.Progress.Text = ("+%d XP   ·   +%d Coins   ·   +%d Essence%s"):format(p.XP or 0, p.Coins or 0, p.Essence or 0, levelText)
	if summary.Mode == "Tutorial" then
		ui.Pity.Text = "Training reward: guaranteed Rare part."
	else
		ui.Pity.Text = ("Legendary pity: %d / %d (a Legendary is guaranteed when this fills)"):format(summary.Pity.Count, summary.Pity.Threshold)
	end

	local entry = summary.Parts and summary.Parts[1]
	if entry then
		self:Reveal(entry)
	else
		self:FinishReveal()
	end
end

function RewardController:Close()
	isOpen = false
	ui.Screen.Enabled = false
	revealToken += 1
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Screen) then
		GuiService.SelectedObject = nil
	end
end

function RewardController:Return()
	self:Close()
	controllers.BossController:Request("Return")
end

function RewardController:Replay()
	self:Close()
	local result = controllers.BossController:Request("Replay")
	if not result.Ok then
		controllers.HUDController:Toast(result.Error or "Could not replay.", C.Bad)
		controllers.BossController:Request("Return")
	end
end

function RewardController:Equip()
	local entry = currentReward and currentReward.Parts and currentReward.Parts[1]
	self:Return()
	if entry then
		task.delay(0.4, function()
			controllers.WorkshopController:OpenToPart(entry.Id, entry.Mutation)
		end)
	end
end

function RewardController:Start()
	self:BuildGui()
	Net.Get("RewardNotification").OnClientEvent:Connect(function(summary)
		if type(summary) == "table" then
			-- Give the VICTORY banner a moment first.
			task.delay(1.5, function()
				self:Show(summary)
			end)
		end
	end)
end

return RewardController
