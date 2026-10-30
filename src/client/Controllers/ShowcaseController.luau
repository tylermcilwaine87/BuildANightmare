--[[
	ShowcaseController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/ShowcaseController

	THE NIGHTMARE SHOWCASE (Phase 6), client side: pressing E ("Inspect") at a pedestal
	next to the Workshop opens a card with that player's active build (every part and
	mutation, stats, Q / E / G abilities), its likes and a LIKE ♥ button. The server
	(ShowcaseService) decides whether you can like it (once per player per day).
]]

local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local SlotDefinitions = require(Shared:WaitForChild("SlotDefinitions"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local ShowcaseController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local SHOW_COLOR = Color3.fromRGB(210, 40, 30) -- blood red
local GOLD = Color3.fromRGB(255, 195, 50)
local controllers
local ui = {}
local request: RemoteFunction
local current = nil -- the build being inspected (server reply)

function ShowcaseController:Init(registry)
	controllers = registry
	request = Net.Get("ShowcaseRequest")
end

function ShowcaseController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function ShowcaseController:Request(action: string, userId: number)
	local ok, result = pcall(request.InvokeServer, request, action, userId)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Error = "Could not reach the server." }
	end
	return result
end

function ShowcaseController:Close()
	ui.Panel.Visible = false
	current = nil
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

local function statLine(stats): string
	local parts = {}
	for _, row in StatCalculator.DisplayOrder do
		local value = stats[row.Key]
		if value then
			table.insert(parts, ("%s %d"):format(row.Label, math.floor(value + 0.5)))
		end
	end
	return table.concat(parts, "  ·  ")
end

function ShowcaseController:Show(data)
	current = data
	local build = data.Build
	local stats, archetype = StatCalculator.Compute(build)
	ui.Title.Text = ("%s's  %s"):format(data.OwnerName, build.Name)
	ui.Meta.Text = ("★ %d RESPECT  ·  %s  ·  Power %d"):format(data.Likes or 0, string.upper(archetype), stats.PowerCost)
	ui.Stats.Text = statLine(stats)

	local abilities = AbilityDefinitions.ForBuild(build, PartDefinitions)
	local function abilityName(id)
		local def = AbilityDefinitions.Get(id)
		return def and def.DisplayName or "—"
	end
	local ultimate = AbilityDefinitions.GetUltimate(AbilityDefinitions.UltimateForBuild(build, PartDefinitions))
	ui.Abilities.Text = ("Q: %s   ·   E: %s   ·   G: %s"):format(abilityName(abilities[1]), abilityName(abilities[2]), ultimate and ultimate.DisplayName or "—")

	for _, child in ui.Parts:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	for order, slot in SlotDefinitions.Order do
		local def = PartDefinitions.Get(build.Parts[slot])
		local mutation = MutationDefinitions.Get(MutationDefinitions.ForSlot(build, slot))
		local text
		if def then
			local rarity = RarityDefinitions.Info[def.Rarity]
			local prefix = mutation and ('<font color="#%s">★ %s </font>'):format(mutation.Color:ToHex(), mutation.DisplayName) or ""
			text = ('%s:  %s<font color="#%s">%s</font>'):format(SlotDefinitions.Info[slot].DisplayName, prefix, rarity.Color:ToHex(), def.DisplayName)
		else
			text = ('%s:  <font color="#%s">empty</font>'):format(SlotDefinitions.Info[slot].DisplayName, C.SubText:ToHex())
		end
		UIKit.Label({ Text = text, RichText = true, Size = UDim2.new(1, -8, 0, 22), Font = UIKit.FontBody, MaxTextSize = 15, LayoutOrder = order, Parent = ui.Parts })
	end

	ui.LikeButton.Text = data.CanLike and "GIVE RESPECT ★" or "★"
	ui.LikeButton.BackgroundColor3 = data.CanLike and SHOW_COLOR or C.PanelLighter
	ui.LikeButton.AutoButtonColor = data.CanLike == true
	ui.Message.Text = data.CanLike and "" or (data.LikeNote or "")
	ui.Message.TextColor3 = C.SubText
	ui.Panel.Visible = true
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.LikeButton
	end
end

function ShowcaseController:Like()
	if not current or not current.CanLike then
		return
	end
	local result = self:Request("Like", current.OwnerUserId)
	if result.Ok then
		current.CanLike = false
		current.Likes = result.Likes or current.Likes
		ui.Meta.Text = ui.Meta.Text:gsub("^★ %d+", "★ " .. tostring(current.Likes))
		ui.LikeButton.Text = "★ RESPECT GIVEN"
		ui.LikeButton.BackgroundColor3 = C.PanelLighter
		ui.LikeButton.AutoButtonColor = false
		ui.Message.Text = ("You gave %s's Nightmare respect!"):format(current.OwnerName)
		ui.Message.TextColor3 = C.Good
	else
		ui.Message.Text = result.Error or "Couldn't like."
		ui.Message.TextColor3 = C.Bad
	end
end

function ShowcaseController:BuildGui()
	local gui = UIKit.New("ScreenGui", { Name = "ShowcaseGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 21, Parent = localPlayer:WaitForChild("PlayerGui") })
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.42, 0.66),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(SHOW_COLOR, 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(600, 560), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel

	ui.Title = UIKit.Label({ Size = UDim2.fromScale(0.86, 0.09), Font = UIKit.FontHeavy, TextColor3 = GOLD, MaxTextSize = 24, Parent = panel })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.1, 0.09), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)
	ui.Meta = UIKit.Label({ Position = UDim2.fromScale(0, 0.1), Size = UDim2.fromScale(1, 0.06), TextColor3 = C.Warn, MaxTextSize = 16, Parent = panel })
	ui.Abilities = UIKit.Label({ Position = UDim2.fromScale(0, 0.17), Size = UDim2.fromScale(1, 0.06), TextColor3 = C.Accent, MaxTextSize = 15, Parent = panel })
	ui.Parts = UIKit.New("Frame", { Position = UDim2.fromScale(0, 0.25), Size = UDim2.fromScale(1, 0.45), BackgroundTransparency = 1, Parent = panel }, { UIKit.List(2) })
	ui.Stats = UIKit.Label({ Position = UDim2.fromScale(0, 0.71), Size = UDim2.fromScale(1, 0.1), Font = UIKit.FontBody, TextColor3 = C.Accent2, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 13, Parent = panel })
	ui.LikeButton = UIKit.Button({ Text = "GIVE RESPECT ★", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromScale(0.45, 0.1), BackgroundColor3 = SHOW_COLOR, MaxTextSize = 20, Parent = panel }, function()
		self:Like()
	end)
	ui.Message = UIKit.Label({ Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.07), Font = UIKit.FontBody, TextXAlignment = Enum.TextXAlignment.Center, MaxTextSize = 14, Parent = panel })
end

function ShowcaseController:Start()
	self:BuildGui()
	ProximityPromptService.PromptTriggered:Connect(function(prompt)
		if prompt.Name ~= "InspectShowcase" then
			return
		end
		local userId = prompt:GetAttribute("OwnerUserId")
		if type(userId) ~= "number" then
			return
		end
		local result = self:Request("Inspect", userId)
		if result.Ok then
			self:Show(result)
		else
			controllers.HUDController:Toast(result.Error or "Couldn't inspect.", C.Bad, 2)
		end
	end)
end

return ShowcaseController
