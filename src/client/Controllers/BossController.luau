--[[
	BossController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/BossController

	  * Boss Portal panel (opens from the portal's ProximityPrompt): name, area,
	    difficulty, recommended power, tips, possible rewards with drop odds, Legendary
	    pity progress, wins and best time, FIGHT button.
	  * In-fight HUD: big boss health bar + phase, LEAVE button.
	  * Banners: boss intro, OVERDRIVE, victory / defeat.
	The server decides everything; this only requests and displays.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local TutorialDefinitions = require(Shared:WaitForChild("TutorialDefinitions"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local BossController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local controllers
local ui = {}
local bossRequest: RemoteFunction
local inFight = false
local currentBossId: string? = nil
local selectedMode = "Normal" -- difficulty chosen in the portal

function BossController:Init(registry)
	controllers = registry
	bossRequest = Net.Get("BossRequest")
end

function BossController:IsInFight(): boolean
	return inFight
end

function BossController:GetBossId(): string?
	return inFight and currentBossId or nil
end

-- The entrance moment: the camera sweeps across the arena to the boss as it wakes.
function BossController:IntroCamera(data)
	local camera = workspace.CurrentCamera
	local center, bossAt = data.ArenaCenter, data.BossPosition
	if typeof(center) ~= "Vector3" or typeof(bossAt) ~= "Vector3" then
		return
	end
	if controllers.WorldController and controllers.WorldController:IsCameraBusy() then
		return
	end
	local toBoss = Vector3.new(bossAt.X - center.X, 0, bossAt.Z - center.Z)
	toBoss = toBoss.Magnitude > 0.1 and toBoss.Unit or Vector3.zAxis
	local focus = bossAt + Vector3.new(0, 9, 0)
	local wide = CFrame.lookAt(center - toBoss * 70 + Vector3.new(0, 34, 0), focus)
	local close = CFrame.lookAt(bossAt - toBoss * 26 + Vector3.new(0, 11, 0), focus)
	local duration = math.max(1.5, (data.IntroDelay or 3) * 0.9)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = wide
	local tween = TweenService:Create(camera, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = close })
	tween:Play()
	tween.Completed:Wait()
	camera.CameraType = Enum.CameraType.Custom
end

function BossController:Request(action: string, arg, arg2)
	local ok, result = pcall(bossRequest.InvokeServer, bossRequest, action, arg, arg2)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Error = "Could not reach the server." }
	end
	return result
end

local function formatTime(seconds: number?): string
	if not seconds then
		return "—"
	end
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

------------------------------------------------------------------------------------------
-- Banner
------------------------------------------------------------------------------------------
function BossController:Banner(title: string, subtitle: string?, color: Color3?, duration: number?)
	ui.BannerTitle.Text = title
	ui.BannerTitle.TextColor3 = color or C.Warn
	ui.BannerSub.Text = subtitle or ""
	ui.Banner.Visible = true
	ui.BannerTitle.TextTransparency = 0
	ui.BannerSub.TextTransparency = 0
	local token = (ui.BannerToken or 0) + 1
	ui.BannerToken = token
	task.delay(duration or 3, function()
		if ui.BannerToken ~= token then
			return
		end
		local info = TweenInfo.new(0.6)
		TweenService:Create(ui.BannerTitle, info, { TextTransparency = 1 }):Play()
		TweenService:Create(ui.BannerSub, info, { TextTransparency = 1 }):Play()
		task.wait(0.6)
		if ui.BannerToken == token then
			ui.Banner.Visible = false
		end
	end)
end

------------------------------------------------------------------------------------------
-- Portal panel
------------------------------------------------------------------------------------------
function BossController:OpenPortal(bossId: string)
	local boss = BossDefinitions.Get(bossId)
	local profile = controllers.ClientState.Profile
	if not boss or not profile or inFight then
		return
	end
	if currentBossId ~= bossId then
		selectedMode = "Normal"
	end
	currentBossId = bossId
	-- A previously chosen difficulty may no longer be available (e.g. a new profile).
	if not BossDefinitions.IsModeUnlocked(profile.Bosses, bossId, selectedMode) then
		selectedMode = "Normal"
	end
	self:RefreshPortal()
	ui.Portal.Visible = true
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.FightButton
	end
end

function BossController:RefreshPortal()
	local bossId = currentBossId
	local boss = BossDefinitions.Get(bossId)
	local profile = controllers.ClientState.Profile
	if not boss or not profile then
		return
	end
	local difficulty = Config.Difficulties[selectedMode]

	-- Is the player still in the tutorial? Then only the training version is offered.
	local tutorial = profile.Tutorial
	local stepInfo = tutorial and not tutorial.Done and TutorialDefinitions.Steps[tutorial.Step]
	local stepId = stepInfo and stepInfo.Id or nil -- `or nil`: a finished tutorial gives false, not nil
	local inTutorial = stepId ~= nil and stepId ~= "Equip"

	ui.PortalName.Text = boss.DisplayName
	ui.PortalArea.Text = ("%s  ·  Difficulty %s  ·  Recommended Power %d"):format(boss.Area, string.rep("☠", boss.Difficulty + difficulty.ExtraSkulls), boss.RecommendedPower)
	local tips = table.clone(boss.Tips)
	if boss.ModeTips and boss.ModeTips[selectedMode] then
		table.insert(tips, 1, boss.ModeTips[selectedMode])
	end
	ui.PortalCodex.Text = boss.Codex .. "\n\n• " .. table.concat(tips, "\n• ")

	-- Difficulty buttons
	for mode, button in ui.ModeButtons do
		local info = Config.Difficulties[mode]
		local unlocked = BossDefinitions.IsModeUnlocked(profile.Bosses, bossId, mode)
		button.Visible = not inTutorial
		button.Text = unlocked and info.DisplayName or ("🔒 " .. info.DisplayName)
		button.BackgroundColor3 = mode == selectedMode and info.Color or C.PanelLighter
		button.TextColor3 = unlocked and C.Text or C.SubText
	end

	-- Rewards with odds
	ui.RewardsHeader.Text = ("POSSIBLE REWARDS (%s odds) · ✓ = owned"):format(inTutorial and "Training" or difficulty.DisplayName)
	local lines = {}
	local odds = Config.Loot.Odds[selectedMode] or Config.Loot.Odds.Normal
	for _, rarity in RarityDefinitions.Order do
		local ids = boss.LootPool[rarity]
		if ids and #ids > 0 then
			local names = {}
			for _, id in ids do
				local def = PartDefinitions.Get(id)
				local owned = (profile.Inventory[id] or 0) > 0
				table.insert(names, (def and def.DisplayName or id) .. (owned and " ✓" or ""))
			end
			table.insert(lines, ('<font color="#%s"><b>%s %d%%</b></font>  %s'):format(RarityDefinitions.Info[rarity].Color:ToHex(), RarityDefinitions.Info[rarity].DisplayName, odds[rarity], table.concat(names, ", ")))
		end
	end
	ui.PortalRewards.Text = table.concat(lines, "\n")

	local record = profile.Bosses and profile.Bosses[bossId]
	local modeRecord = BossDefinitions.ModeRecord(record, selectedMode)
	local pity = profile.Pity and profile.Pity.Legendary or 0
	local partySize = controllers.PartyController:GetSize()
	local revives = Config.Party.Revives[selectedMode]
	revives = revives == "PartySize" and partySize or (revives or 0)
	local partyText = partySize > 1
		and ("Party of %d (boss health ×%.2f, %d shared revive%s)"):format(partySize, Config.Bosses.HealthScaling[math.clamp(partySize, 1, #Config.Bosses.HealthScaling)], revives, revives == 1 and "" or "s")
		or "Solo (press L to form a party)"
	ui.PortalStats.Text = ("%s wins: %d   ·   Best time: %s   ·   Legendary pity: %d / %d   ·   %s"):format(difficulty.DisplayName, modeRecord.Wins or 0, formatTime(modeRecord.BestTime), pity, Config.Loot.LegendaryPity, partyText)
	local waitingForLeader = partySize > 1 and not controllers.PartyController:IsLeader()

	-- Fight button: training / locked tutorial / chosen difficulty
	local unlocked, reason = BossDefinitions.IsModeUnlocked(profile.Bosses, bossId, selectedMode)
	local bossUnlocked, bossReason = BossDefinitions.IsBossUnlocked(profile.Bosses, bossId)
	ui.PortalMessage.TextColor3 = C.SubText
	if not bossUnlocked then
		ui.FightButton.Text = "LOCKED"
		ui.FightButton.AutoButtonColor = false
		ui.FightButton.BackgroundColor3 = C.PanelLighter
		ui.PortalMessage.Text = bossReason or ""
	elseif waitingForLeader then
		ui.FightButton.Text = "LOCKED"
		ui.FightButton.AutoButtonColor = false
		ui.FightButton.BackgroundColor3 = C.PanelLighter
		ui.PortalMessage.Text = "You're in a party: the leader starts the fight and brings everyone."
	elseif stepId == "Boss" and boss.Modes.Tutorial then
		ui.FightButton.Text = "FIGHT (TRAINING VERSION)"
		ui.FightButton.AutoButtonColor = true
		ui.FightButton.BackgroundColor3 = Config.Difficulties.Normal.Color
		ui.PortalMessage.Text = "A weakened Scrap Titan for your first fight. Guaranteed Rare reward!"
	elseif inTutorial then
		ui.FightButton.Text = "LOCKED"
		ui.FightButton.AutoButtonColor = false
		ui.FightButton.BackgroundColor3 = C.PanelLighter
		ui.PortalMessage.Text = "Finish your training first (or skip the tutorial)."
	elseif not unlocked then
		ui.FightButton.Text = "LOCKED"
		ui.FightButton.AutoButtonColor = false
		ui.FightButton.BackgroundColor3 = C.PanelLighter
		ui.PortalMessage.Text = reason or ""
	else
		ui.FightButton.Text = ("FIGHT (%s)"):format(difficulty.DisplayName)
		ui.FightButton.AutoButtonColor = true
		ui.FightButton.BackgroundColor3 = difficulty.Color
		ui.PortalMessage.Text = difficulty.RewardMultiplier ~= 1 and ("x%s XP, coins and Essence on this difficulty."):format(tostring(difficulty.RewardMultiplier)) or ""
	end
end

function BossController:IsPortalOpen(): boolean
	return ui.Portal ~= nil and ui.Portal.Visible
end

function BossController:ClosePortal()
	ui.Portal.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Portal) then
		GuiService.SelectedObject = nil
	end
end

function BossController:Fight()
	if not currentBossId or ui.FightButton.Text == "LOCKED" then
		return
	end
	ui.PortalMessage.Text = "Entering..."
	local result = self:Request("Start", currentBossId, selectedMode)
	if result.Ok then
		self:ClosePortal()
	else
		ui.PortalMessage.Text = result.Error or "Could not start."
		ui.PortalMessage.TextColor3 = C.Bad
	end
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
function BossController:BuildGui()
	local gui = UIKit.New("ScreenGui", {
		Name = "BossGui",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 15,
		Parent = localPlayer:WaitForChild("PlayerGui"),
	})
	ui.Gui = gui

	-- Portal panel
	local portal = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.62, 0.78),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(Color3.fromRGB(255, 140, 50), 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(900, 640), Parent = portal })
	UIKit.Responsive(portal) -- near full screen on phones
	ui.Portal = portal
	ui.PortalName = UIKit.Label({ Size = UDim2.fromScale(0.8, 0.09), Font = UIKit.FontHeavy, TextColor3 = Color3.fromRGB(255, 170, 80), MaxTextSize = 34, Parent = portal })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.08, 0.08), BackgroundColor3 = C.PanelLighter, Parent = portal }, function()
		self:ClosePortal()
	end)
	ui.PortalArea = UIKit.Label({ Position = UDim2.fromScale(0, 0.09), Size = UDim2.fromScale(1, 0.05), TextColor3 = C.SubText, MaxTextSize = 15, Parent = portal })
	ui.PortalCodex = UIKit.Label({ Position = UDim2.fromScale(0, 0.15), Size = UDim2.fromScale(1, 0.21), Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 15, Parent = portal })

	-- Difficulty selector
	ui.ModeButtons = {}
	for index, mode in Config.Difficulties.Order do
		ui.ModeButtons[mode] = UIKit.Button({
			Position = UDim2.fromScale((index - 1) * 0.34, 0.37),
			Size = UDim2.fromScale(0.32, 0.065),
			BackgroundColor3 = C.PanelLighter,
			MaxTextSize = 16,
			Parent = portal,
		}, function()
			selectedMode = mode
			self:RefreshPortal()
		end)
	end

	ui.RewardsHeader = UIKit.Label({ Position = UDim2.fromScale(0, 0.45), Size = UDim2.fromScale(1, 0.045), TextColor3 = C.SubText, MaxTextSize = 13, Parent = portal })
	ui.PortalRewards = UIKit.Label({ Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(1, 0.24), RichText = true, Font = UIKit.FontBody, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 15, Parent = portal })
	ui.PortalStats = UIKit.Label({ Position = UDim2.fromScale(0, 0.75), Size = UDim2.fromScale(1, 0.06), TextColor3 = C.Accent2, MaxTextSize = 14, Parent = portal })
	ui.PortalMessage = UIKit.Label({ Position = UDim2.fromScale(0, 0.82), Size = UDim2.fromScale(1, 0.05), Font = UIKit.FontBody, MaxTextSize = 14, Parent = portal })
	ui.FightButton = UIKit.Button({ Text = "FIGHT", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromScale(0.5, 0.1), BackgroundColor3 = Color3.fromRGB(220, 90, 40), MaxTextSize = 22, Parent = portal }, function()
		self:Fight()
	end)

	-- Boss health bar (top centre during fights), below the top-right menu buttons so its
	-- LEAVE button never sits on top of them.
	local bossBar = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(620, 58),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	UIKit.AutoScale(bossBar)
	ui.BossBar = bossBar
	ui.BossName = UIKit.Label({ Size = UDim2.new(1, -120, 0, 24), Font = UIKit.FontHeavy, TextColor3 = Color3.fromRGB(255, 170, 80), TextStrokeTransparency = 0.4, MaxTextSize = 22, Parent = bossBar })
	ui.BossPhase = UIKit.Label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -120, 0, 0), Size = UDim2.fromOffset(200, 24), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.Bad, TextStrokeTransparency = 0.4, MaxTextSize = 16, Parent = bossBar })
	ui.BossHealth = UIKit.Bar({ Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, -120, 0, 22), Color = Color3.fromRGB(230, 80, 50), MaxTextSize = 15, Parent = bossBar })
	ui.BossStagger = UIKit.Bar({ Position = UDim2.fromOffset(0, 53), Size = UDim2.new(1, -120, 0, 5), Color = Color3.fromRGB(255, 220, 90), Parent = bossBar })
	ui.BossStagger.Label.Visible = false
	-- Party comebacks left (hidden when solo).
	ui.Revives = UIKit.Label({ Position = UDim2.fromOffset(0, 61), Size = UDim2.new(1, -120, 0, 16), TextColor3 = Color3.fromRGB(120, 200, 255), TextStrokeTransparency = 0.4, MaxTextSize = 14, Text = "", Parent = bossBar })
	UIKit.Button({ Text = "LEAVE", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 14), Size = UDim2.fromOffset(105, 36), BackgroundColor3 = C.PanelLighter, MaxTextSize = 15, Parent = bossBar }, function()
		self:Request("Leave")
	end)

	-- Banner
	ui.Banner = UIKit.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.32), Size = UDim2.fromScale(0.9, 0.18), BackgroundTransparency = 1, Visible = false, Parent = gui })
	ui.BannerTitle = UIKit.Label({ Size = UDim2.fromScale(1, 0.62), TextXAlignment = Enum.TextXAlignment.Center, Font = UIKit.FontHeavy, TextStrokeTransparency = 0.2, MaxTextSize = 60, Parent = ui.Banner })
	ui.BannerSub = UIKit.Label({ Position = UDim2.fromScale(0, 0.62), Size = UDim2.fromScale(1, 0.38), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, MaxTextSize = 26, Parent = ui.Banner })
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
-- Our boss = the closest living boss (each encounter has its own arena far apart).
local function findMyBoss(): Model?
	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return nil
	end
	local best, bestDistance = nil, 250
	for _, model in CollectionService:GetTagged("Boss") do
		local bossRoot = model:FindFirstChild("HumanoidRootPart")
		if bossRoot and not model:GetAttribute("Defeated") then
			local distance = (bossRoot.Position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = model, distance
			end
		end
	end
	return best
end

function BossController:Start()
	self:BuildGui()

	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name == "BossPortal" then
			self:OpenPortal(prompt:GetAttribute("BossId") or "ScrapTitan")
		end
	end)

	Net.Get("BossEvent").OnClientEvent:Connect(function(kind, data)
		if type(data) ~= "table" then
			return
		end
		if kind == "Start" then
			inFight = true
			currentBossId = data.BossId
			ui.BossBar.Visible = true
			local difficulty = Config.Difficulties[data.Mode]
			local suffix = data.Mode == "Tutorial" and " (TRAINING)" or (difficulty and data.Mode ~= "Normal" and (" · " .. difficulty.DisplayName) or "")
			ui.BossName.Text = data.Name .. suffix
			ui.BossName.TextColor3 = difficulty and data.Mode ~= "Normal" and difficulty.Color or Color3.fromRGB(255, 170, 80)
			ui.BossPhase.Text = ""
			ui.PhaseTitle = ""
			ui.Revives.Text = data.Revives and ("PARTY REVIVES: %d"):format(data.Revives) or ""
			UIKit.SetBar(ui.BossHealth, 1, 1)
			local subtitle = difficulty and data.Mode ~= "Normal" and (data.Title .. "  ·  " .. difficulty.DisplayName .. " DIFFICULTY") or data.Title
			if (data.PartySize or 1) > 1 then
				subtitle ..= ("  ·  PARTY OF %d"):format(data.PartySize)
			end
			self:Banner(data.Name, subtitle, difficulty and data.Mode ~= "Normal" and difficulty.Color or Color3.fromRGB(255, 170, 80), data.IntroDelay or 3)
			task.spawn(self.IntroCamera, self, data)
		elseif kind == "Revives" then
			ui.Revives.Text = ("PARTY REVIVES: %d"):format(data.Left or 0)
			if data.Text then
				controllers.HUDController:Toast(data.Text, Color3.fromRGB(120, 200, 255), 3)
			end
		elseif kind == "Down" then
			if data.RejoinIn then
				self:Banner("KNOCKED OUT", ("Your party is still fighting. Back in the arena in %ds."):format(data.RejoinIn), C.Warn, 4)
			else
				self:Banner("OUT OF THE FIGHT", "No revives left. Your party fights on, and you're still rewarded if they win.", C.Bad, 5)
			end
		elseif kind == "Phase" then
			ui.BossPhase.Text = data.Title or ""
			ui.PhaseTitle = data.Title or "" -- restored after a stagger
			self:Banner(data.Title or "", data.Subtitle, C.Bad, 2.5)
		elseif kind == "End" then
			inFight = false
			ui.BossBar.Visible = false
			if data.Result == "Victory" then
				self:Banner("VICTORY!", ("Defeated in %s"):format(formatTime(data.Time)), C.Good, 2.5)
			elseif data.Reason == "Left" then
				self:Banner("RETREATED", "Back at the gate. The waystone will take you home.", C.SubText, 2.5)
			else
				self:Banner("DEFEATED...", "Your Handler was knocked out. Returning to the Forge.", C.Bad, 3)
			end
		end
	end)

	-- Live boss health.
	local elapsed = 0
	RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.1 or not inFight then
			return
		end
		elapsed = 0
		local boss = findMyBoss()
		local humanoid = boss and boss:FindFirstChildOfClass("Humanoid")
		if humanoid then
			UIKit.SetBar(ui.BossHealth, humanoid.Health, humanoid.MaxHealth)
			local staggeredUntil = boss:GetAttribute("StaggeredUntil") or 0
			if staggeredUntil > workspace:GetServerTimeNow() then
				UIKit.SetBar(ui.BossStagger, 1, 1)
				ui.BossPhase.Text = "STAGGERED!"
			else
				UIKit.SetBar(ui.BossStagger, boss:GetAttribute("Stagger") or 0, boss:GetAttribute("StaggerMax") or 300)
				if ui.BossPhase.Text == "STAGGERED!" then
					ui.BossPhase.Text = (boss:GetAttribute("Phase") or 1) > 1 and (ui.PhaseTitle or "") or ""
				end
			end
		end
	end)
end

return BossController
