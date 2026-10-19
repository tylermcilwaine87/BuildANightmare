--[[
	CodexController  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/CodexController

	THE CODEX (Phase 5): the in-game encyclopedia. Open with M or the CODEX button.
	  BOSSES          lore, recommended power, tips, your wins / best time per
	                  difficulty, loot (✓ = owned)
	  PARTS           every part; discovered ones show stats, ability and source,
	                  undiscovered ones are "???" with a hint of where to find them
	  STATUS EFFECTS  what each status does and how to counter it
	  MUTATIONS       the Mutation Book (found mutations, effects, parts). In Studio it
	                  also has a DEV: GRANT MUTATION button for testing.
	Read-only: everything comes from shared definitions + the profile snapshot.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PartDefinitions = require(Shared:WaitForChild("PartDefinitions"))
local RarityDefinitions = require(Shared:WaitForChild("RarityDefinitions"))
local BossDefinitions = require(Shared:WaitForChild("BossDefinitions"))
local StatusDefinitions = require(Shared:WaitForChild("StatusDefinitions"))
local AbilityDefinitions = require(Shared:WaitForChild("AbilityDefinitions"))
local MutationDefinitions = require(Shared:WaitForChild("MutationDefinitions"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))

local CodexController = {}

local localPlayer = Players.LocalPlayer
local C = UIKit.Colors
local CODEX_COLOR = Color3.fromRGB(255, 140, 230)
local TABS = {
	{ Id = "Bosses", Label = "BOSSES" },
	{ Id = "Parts", Label = "PARTS" },
	{ Id = "Statuses", Label = "STATUS EFFECTS" },
	{ Id = "Mutations", Label = "MUTATIONS" },
}
local PART_SLOT_ORDER = { "Core", "Head", "Arm", "Legs", "Back", "Tail" }

local controllers
local ui = {}
local tab = "Bosses"

function CodexController:Init(registry)
	controllers = registry
end

function CodexController:IsOpen(): boolean
	return ui.Panel ~= nil and ui.Panel.Visible
end

function CodexController:Toggle()
	if self:IsOpen() then
		self:Close()
	else
		self:Open()
	end
end

function CodexController:Open(startTab: string?)
	if not controllers.ClientState.Profile then
		return
	end
	if startTab then
		tab = startTab
	end
	ui.Panel.Visible = true
	self:Refresh()
	if UserInputService.GamepadEnabled then
		GuiService.SelectedObject = ui.TabButtons[tab]
	end
end

function CodexController:Close()
	ui.Panel.Visible = false
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(ui.Panel) then
		GuiService.SelectedObject = nil
	end
end

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------
local function hex(color: Color3): string
	return color:ToHex()
end

local function statLine(stats): string
	local parts = {}
	for _, row in StatCalculator.DisplayOrder do
		local value = stats[row.Key]
		if value and value ~= 0 then
			table.insert(parts, ("%s%d %s"):format(value > 0 and "+" or "", value, row.Label))
		end
	end
	return table.concat(parts, ", ")
end

local function formatTime(seconds: number?): string
	if not seconds then
		return "—"
	end
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

local function percent(chance: number): number
	return math.floor(chance * 100 + 0.5) -- %d needs a whole number
end

-- A card in the list: coloured side bar + text lines (rich text allowed).
local function card(order: number, accent: Color3, lines: { { Text: string, Size: number?, Color: Color3?, Body: boolean? } })
	local height = 8
	for _, line in lines do
		height += (line.Size or 16) + 4
	end
	local row = UIKit.New("Frame", { Size = UDim2.new(1, -8, 0, height + 6), BackgroundColor3 = C.PanelLight, LayoutOrder = order, Parent = ui.List }, { UIKit.Corner(8), UIKit.Padding(8) })
	UIKit.New("Frame", { Size = UDim2.new(0, 6, 1, 0), BackgroundColor3 = accent, BorderSizePixel = 0, Parent = row }, { UIKit.Corner(3) })
	local y = 0
	for _, line in lines do
		local size = line.Size or 16
		UIKit.Label({
			Text = line.Text,
			RichText = true,
			Position = UDim2.fromOffset(14, y),
			Size = UDim2.new(1, -14, 0, size),
			Font = line.Body and UIKit.FontBody or UIKit.Font,
			TextColor3 = line.Color or C.Text,
			MaxTextSize = math.min(size - 2, 18), -- tall multi-line boxes keep normal-sized text
			Parent = row,
		})
		y += size + 4
	end
	return row
end

local function header(order: number, text: string)
	UIKit.Label({ Text = text, Size = UDim2.new(1, -8, 0, 24), TextColor3 = C.SubText, MaxTextSize = 15, LayoutOrder = order, Parent = ui.List })
end

------------------------------------------------------------------------------------------
-- Tabs
------------------------------------------------------------------------------------------
function CodexController:ShowBosses(profile)
	local order = 0
	for _, bossId in BossDefinitions.Order do
		local boss = BossDefinitions.Get(bossId)
		local record = profile.Bosses and profile.Bosses[bossId]
		local unlocked, reason = BossDefinitions.IsBossUnlocked(profile.Bosses, bossId)

		local results = {}
		for _, mode in Config.Difficulties.Order do
			local modeRecord = BossDefinitions.ModeRecord(record, mode)
			table.insert(results, ("%s: %d win%s, best %s"):format(Config.Difficulties[mode].DisplayName, modeRecord.Wins or 0, (modeRecord.Wins or 0) == 1 and "" or "s", formatTime(modeRecord.BestTime)))
		end

		local loot = {}
		for _, rarity in RarityDefinitions.Order do
			for _, partId in boss.LootPool[rarity] or {} do
				local def = PartDefinitions.Get(partId)
				local owned = (profile.Inventory[partId] or 0) > 0
				table.insert(loot, ('<font color="#%s">%s</font>%s'):format(hex(RarityDefinitions.Info[rarity].Color), def and def.DisplayName or partId, owned and " ✓" or ""))
			end
		end

		order += 1
		card(order, Color3.fromRGB(255, 170, 80), {
			{ Text = ('<font color="#FFAA50">%s</font>   <font color="#%s">%s</font>'):format(boss.DisplayName, hex(C.SubText), boss.Title), Size = 20 },
			{ Text = ("%s  ·  Difficulty %s  ·  Recommended Power %d%s"):format(boss.Area, string.rep("☠", boss.Difficulty), boss.RecommendedPower, unlocked and "" or ("  ·  🔒 " .. (reason or "Locked"))), Color = C.SubText, Size = 15 },
			{ Text = boss.Codex, Body = true, Size = 32 },
			{ Text = "• " .. table.concat(boss.Tips, "\n• "), Body = true, Size = 16 * #boss.Tips, Color = C.SubText },
			{ Text = "Your record: " .. table.concat(results, "   ·   "), Color = C.Accent2, Size = 15 },
			{ Text = "Loot: " .. table.concat(loot, ", "), Body = true, Size = 32 },
		})
	end
	ui.Summary.Text = ("%d bosses. Follow the four paths out of the Forge and challenge each one at its gate."):format(#BossDefinitions.Order)
end

function CodexController:ShowParts(profile)
	local discoveredCount, total = 0, 0
	local order = 0
	for _, partSlot in PART_SLOT_ORDER do
		local list = PartDefinitions.ForPartSlot(partSlot)
		table.sort(list, function(a, b)
			local ra, rb = RarityDefinitions.Info[a.Rarity].Rank, RarityDefinitions.Info[b.Rarity].Rank
			if ra ~= rb then
				return ra < rb
			end
			return a.DisplayName < b.DisplayName
		end)
		order += 1
		header(order, string.upper(partSlot) .. " PARTS")
		for _, def in list do
			total += 1
			local rarity = RarityDefinitions.Info[def.Rarity]
			local discovered = profile.Discovered and profile.Discovered[def.Id]
			order += 1
			if discovered then
				discoveredCount += 1
				local ability = AbilityDefinitions.Get(def.AbilityId)
				local ultimate = AbilityDefinitions.GetUltimate(def.UltimateId)
				local extras = {}
				if ability then
					table.insert(extras, ("Ability: %s (%ds)"):format(ability.DisplayName, ability.Cooldown))
				end
				if ultimate then
					table.insert(extras, "Ultimate: " .. ultimate.DisplayName)
				end
				if def.OnHit then
					table.insert(extras, ("On hit: %s%s"):format(def.OnHit.Status, def.OnHit.ComboHit and " (finisher)" or ""))
				end
				if def.Movement then
					table.insert(extras, def.Movement .. " movement")
				end
				card(order, rarity.Color, {
					{ Text = ('<font color="#%s">%s</font>   <font color="#%s">%s · Power %d · Owned ×%d</font>'):format(hex(rarity.Color), def.DisplayName, hex(C.SubText), rarity.DisplayName, def.PowerCost, profile.Inventory[def.Id] or 0), Size = 17 },
					{ Text = def.Description, Body = true, Size = 15 },
					{ Text = statLine(def.Stats) .. (#extras > 0 and ("  ·  " .. table.concat(extras, "  ·  ")) or ""), Color = C.Accent2, Size = 15 },
					{ Text = "Source: " .. def.Source, Color = C.SubText, Body = true, Size = 14 },
				})
			else
				card(order, C.PanelLighter, {
					{ Text = ("??? <font color=\"#%s\">(%s %s)</font>"):format(hex(rarity.Color), rarity.DisplayName, def.Slot), Color = C.SubText, Size = 17 },
					{ Text = "Undiscovered. Found at: " .. def.Source, Color = C.SubText, Body = true, Size = 14 },
				})
			end
		end
	end
	ui.Summary.Text = ("Parts discovered: %d / %d. Bosses, crafting and the Forge are how you find new ones."):format(discoveredCount, total)
end

function CodexController:ShowStatuses()
	for order, id in StatusDefinitions.Order do
		local status = StatusDefinitions.ById[id]
		local effect
		if status.TickDamage then
			effect = ("%d damage every %ss for %ss%s"):format(status.TickDamage, tostring(status.TickInterval), tostring(status.Duration), status.MaxStacks > 1 and (" (per stack, up to %d stacks)"):format(status.MaxStacks) or "")
		elseif status.BurstDamage then
			effect = ("%d burst damage, then jumps to one enemy within %d studs for %d%%"):format(status.BurstDamage, status.ChainRadius, percent(status.ChainFraction))
		elseif status.Slow then
			effect = ("%d%% slower for %ss (never a full freeze)"):format(percent(status.Slow), tostring(status.Duration))
		elseif status.OutgoingMultiplier then
			effect = ("deals %d%% less damage for %ss"):format(percent(1 - status.OutgoingMultiplier), tostring(status.Duration))
		else
			effect = ("lasts %ss"):format(tostring(status.Duration))
		end
		card(order, status.Color, {
			{ Text = ('<font color="#%s">%s</font>   <font color="#%s">[%s]</font>'):format(hex(status.Color), string.upper(status.DisplayName), hex(C.SubText), status.Icon), Size = 18 },
			{ Text = "Effect: " .. effect .. ".", Body = true, Size = 15 },
			{ Text = "Counterplay: " .. status.Counterplay, Color = C.SubText, Body = true, Size = 15 },
		})
	end
	ui.Summary.Text = "Status effects come from abilities, some parts (e.g. Venomous Spider Legs) and mutations. They show as coloured tags over health bars."
end

function CodexController:ShowMutations(profile)
	local book = profile.MutationBook or {}
	local discovered = 0
	for order, id in MutationDefinitions.Order do
		local mutation = MutationDefinitions.ById[id]
		local entry = book[id]
		if entry then
			discovered += 1
			local partNames = {}
			for partId in entry.Parts or {} do
				local def = PartDefinitions.Get(partId)
				table.insert(partNames, def and def.DisplayName or partId)
			end
			table.sort(partNames)
			local stats = statLine(mutation.Stats)
			card(order, mutation.Color, {
				{ Text = ('<font color="#%s">✦ %s</font>   <font color="#%s">Found ×%d · +%d Power</font>'):format(hex(mutation.Color), string.upper(mutation.DisplayName), hex(C.SubText), entry.Found or 0, mutation.PowerCost), Size = 17 },
				{ Text = mutation.Description .. (stats ~= "" and ("  (" .. stats .. ")") or ""), Body = true, Size = 15 },
				{ Text = "Found on: " .. table.concat(partNames, ", "), Color = C.SubText, Body = true, Size = 14 },
			})
		else
			card(order, C.PanelLighter, {
				{ Text = mutation.Weight <= 3 and "✦ ??? (very rare)" or "✦ ???", Color = C.SubText, Size = 17 },
				{ Text = "Undiscovered. Boss drops can mutate, more often on Hard and Nightmare.", Color = C.SubText, Body = true, Size = 14 },
			})
		end
	end
	local chances = Config.Mutations.Chance
	ui.Summary.Text = ("Mutations discovered: %d / %d   ·   Chance per boss drop: Normal %d%% · Hard %d%% · Nightmare %d%%. Mutated parts are the same part with a bonus and a new look; they cost a little extra Power and are never used up by crafting or dismantling."):format(discovered, #MutationDefinitions.Order, percent(chances.Normal), percent(chances.Hard), percent(chances.Nightmare))
end

------------------------------------------------------------------------------------------
-- Refresh
------------------------------------------------------------------------------------------
function CodexController:Refresh()
	local profile = controllers.ClientState.Profile
	if not profile or not self:IsOpen() then
		return
	end
	for id, button in ui.TabButtons do
		button.BackgroundColor3 = id == tab and CODEX_COLOR or C.PanelLighter
		button.TextColor3 = id == tab and C.Background or C.Text
	end
	for _, child in ui.List:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	if ui.DevRow then
		ui.DevRow.Visible = tab == "Mutations"
	end
	if tab == "Bosses" then
		self:ShowBosses(profile)
	elseif tab == "Parts" then
		self:ShowParts(profile)
	elseif tab == "Statuses" then
		self:ShowStatuses()
	else
		self:ShowMutations(profile)
	end
end

------------------------------------------------------------------------------------------
-- DEV (Studio only)
------------------------------------------------------------------------------------------
function CodexController:DevGrant()
	local request = Net.Get("CraftRequest")
	local ok, result = pcall(request.InvokeServer, request, "DevGrantMutation")
	if not ok or type(result) ~= "table" then
		result = { Ok = false, Error = "Could not reach the server." }
	end
	if result.Ok and result.State then
		controllers.ClientState:SetProfile(result.State) -- refreshes the Codex
	end
	local granted = result.Granted
	if result.Ok and granted then
		local def = PartDefinitions.Get(granted.Id)
		local mutation = MutationDefinitions.Get(granted.Mutation)
		ui.DevMessage.Text = ("Granted %s%s  Equip it in the Workshop (B)."):format(MutationDefinitions.FullName(def and def.DisplayName or granted.Id, granted.Mutation), granted.MutationNew and " (NEW!)" or "")
		ui.DevMessage.TextColor3 = mutation and mutation.Color or C.Good
	else
		ui.DevMessage.Text = result.Error or "Couldn't grant."
		ui.DevMessage.TextColor3 = C.Bad
	end
end

------------------------------------------------------------------------------------------
-- GUI
------------------------------------------------------------------------------------------
function CodexController:BuildGui()
	-- DisplayOrder 22: above the Workshop (20) so M works from inside it; below rewards (30).
	local gui = UIKit.New("ScreenGui", { Name = "CodexGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 22, Parent = localPlayer:WaitForChild("PlayerGui") })
	local panel = UIKit.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.66, 0.86),
		BackgroundColor3 = C.Panel,
		Visible = false,
		Parent = gui,
	}, { UIKit.Corner(14), UIKit.Stroke(CODEX_COLOR, 2, 0.1), UIKit.Padding(14) })
	UIKit.New("UISizeConstraint", { MaxSize = Vector2.new(940, 720), Parent = panel })
	UIKit.Responsive(panel) -- near full screen on phones
	ui.Panel = panel

	UIKit.Label({ Text = "✦ THE CODEX", Size = UDim2.fromScale(0.85, 0.07), Font = UIKit.FontHeavy, TextColor3 = CODEX_COLOR, MaxTextSize = 30, Parent = panel })
	UIKit.Button({ Text = "X", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromScale(0.07, 0.07), BackgroundColor3 = C.PanelLighter, Parent = panel }, function()
		self:Close()
	end)

	ui.TabButtons = {}
	for index, info in TABS do
		ui.TabButtons[info.Id] = UIKit.Button({
			Text = info.Label,
			Position = UDim2.new((index - 1) * 0.25, index > 1 and 4 or 0, 0.085, 0),
			Size = UDim2.new(0.25, -4, 0.06, 0),
			MaxTextSize = 15,
			Parent = panel,
		}, function()
			tab = info.Id
			self:Refresh()
		end)
	end

	ui.Summary = UIKit.Label({ Position = UDim2.fromScale(0, 0.155), Size = UDim2.fromScale(1, 0.06), Font = UIKit.FontBody, TextColor3 = C.Warn, TextYAlignment = Enum.TextYAlignment.Top, MaxTextSize = 13, Parent = panel })

	local isStudio = RunService:IsStudio()
	ui.List = UIKit.New("ScrollingFrame", {
		Position = UDim2.fromScale(0, 0.225),
		Size = UDim2.fromScale(1, isStudio and 0.69 or 0.775),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Parent = panel,
	}, { UIKit.List(6) })

	-- DEV ONLY (Studio): instant random mutated part for testing. The server refuses it
	-- on live servers too, so this can't be abused even if someone forces it visible.
	if isStudio then
		local row = UIKit.New("Frame", { Position = UDim2.fromScale(0, 0.93), Size = UDim2.fromScale(1, 0.07), BackgroundTransparency = 1, Visible = false, Parent = panel })
		ui.DevRow = row
		UIKit.Button({ Text = "DEV: GRANT MUTATION", Size = UDim2.fromScale(0.34, 1), BackgroundColor3 = Color3.fromRGB(120, 60, 110), MaxTextSize = 15, Parent = row }, function()
			self:DevGrant()
		end)
		ui.DevMessage = UIKit.Label({ Position = UDim2.new(0.34, 10, 0, 0), Size = UDim2.new(0.66, -10, 1, 0), Font = UIKit.FontBody, TextColor3 = C.SubText, MaxTextSize = 14, Text = "Studio only: gives a random mutated copy of one of your parts.", Parent = row })
	end
end

function CodexController:Start()
	self:BuildGui()
	controllers.ClientState.Changed:Connect(function()
		self:Refresh()
	end)
end

return CodexController
