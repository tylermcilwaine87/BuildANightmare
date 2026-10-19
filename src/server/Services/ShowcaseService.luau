--[[
	ShowcaseService  (ModuleScript)
	Location: ServerScriptService/Server/Services/ShowcaseService

	THE NIGHTMARE SHOWCASE (Phase 6): a row of pedestals next to the Workshop. Every
	player in the server gets one showing their ACTIVE Nightmare (a frozen copy built
	with the same NightmareAssembler, mutation looks included), a label with their name,
	build name and likes, and an "Inspect" prompt.

	  Pedestals refresh every RefreshInterval when a player's active build changes.
	  Inspect -> the build (parts, mutations), likes, and whether you can like it.
	  Like    -> +1 to the owner's profile.Showcase.Likes; one like per player per day,
	             never your own. Saved on both sides right away.
	  The "Most Liked Nightmares" leaderboard reads profile.Showcase.Likes.

	Remote ShowcaseRequest (RemoteFunction): "Inspect", userId | "Like", userId
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Util = require(Shared:WaitForChild("Util"))
local NightmareAssembler = require(Shared:WaitForChild("NightmareAssembler"))
local StatCalculator = require(Shared:WaitForChild("StatCalculator"))

local ShowcaseService = {}
local SHOW = Config.Showcase

local pedestals = {} -- [index] = { Base, Label, Prompt, Owner, Model, Signature }
local slotOf: { [Player]: number } = {}

local function today(): string
	return os.date("!%Y-%m-%d")
end

function ShowcaseService:Init(services)
	self.Services = services
end

------------------------------------------------------------------------------------------
-- Pedestals
------------------------------------------------------------------------------------------
function ShowcaseService:BuildPedestals()
	local parent = Workspace:FindFirstChild("NightmareForgeHub") or Workspace
	local folder = Instance.new("Folder")
	folder.Name = "NightmareShowcase"
	folder.Parent = parent

	for index = 1, SHOW.Slots do
		local position = SHOW.FirstPedestal + Vector3.new((index - 1) * SHOW.Spacing, 0, 0)
		local base = Instance.new("Part")
		base.Name = "Pedestal"
		base.Anchored = true
		base.Shape = Enum.PartType.Cylinder
		base.Size = Vector3.new(1.2, 7, 7)
		base.CFrame = CFrame.new(position + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
		base.Color = Color3.fromRGB(42, 42, 48)
		base.Material = Enum.Material.DiamondPlate
		base.Parent = folder
		local rim = Instance.new("Part")
		rim.Name = "Rim"
		rim.Anchored = true
		rim.CanCollide = false
		rim.Shape = Enum.PartType.Cylinder
		rim.Size = Vector3.new(0.2, 7.4, 7.4)
		rim.CFrame = CFrame.new(position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		rim.Color = Color3.fromRGB(210, 30, 25) -- blood-red arena glow
		rim.Material = Enum.Material.Neon
		rim.Parent = folder

		-- Sized in studs (scales with distance) with one label per line, so neither line
		-- can be squeezed or cut off.
		local billboard = Instance.new("BillboardGui")
		billboard.Size = UDim2.fromScale(10, 2.6)
		billboard.StudsOffsetWorldSpace = Vector3.new(0, 11, 0)
		billboard.MaxDistance = 70
		billboard.AlwaysOnTop = false
		billboard.Parent = base
		local function line(y: number, height: number, font)
			local l = Instance.new("TextLabel")
			l.Position = UDim2.fromScale(0, y)
			l.Size = UDim2.fromScale(1, height)
			l.BackgroundTransparency = 1
			l.TextScaled = true
			l.RichText = true
			l.Font = font
			l.TextColor3 = Color3.fromRGB(236, 232, 248)
			l.TextStrokeTransparency = 0.3
			l.Text = ""
			l.Parent = billboard
			return l
		end
		local label = { Name = line(0, 0.55, Enum.Font.GothamBlack), Info = line(0.58, 0.42, Enum.Font.GothamBold) }

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "InspectShowcase"
		prompt.ActionText = "Inspect"
		prompt.ObjectText = "Empty pedestal"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Enabled = false
		prompt.Parent = base

		pedestals[index] = { Base = base, Position = position, Label = label, Prompt = prompt }
	end

	-- Sign over the row.
	local middle = SHOW.FirstPedestal + Vector3.new((SHOW.Slots - 1) * SHOW.Spacing / 2, 0, 0)
	local sign = Instance.new("Part")
	sign.Name = "ShowcaseSign"
	sign.Anchored = true
	sign.Size = Vector3.new(26, 4, 0.5)
	sign.CFrame = CFrame.lookAt(middle + Vector3.new(0, 16, 6), middle + Vector3.new(0, 16, -10))
	sign.Color = Color3.fromRGB(25, 25, 28)
	sign.Material = Enum.Material.Metal
	sign.Parent = folder
	local gui = Instance.new("SurfaceGui")
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = sign
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.TextScaled = true
	text.Font = Enum.Font.GothamBlack
	text.TextColor3 = Color3.fromRGB(255, 195, 50) -- gold
	text.TextStrokeColor3 = Color3.fromRGB(170, 20, 15) -- red outline
	text.TextStrokeTransparency = 0
	text.Text = "NIGHTMARE SHOWCASE"
	text.Parent = gui
end

-- Player-typed text inside a RichText label: escape the markup characters.
local function escape(text: string): string
	return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function activeBuild(profile)
	return profile and profile.Builds[profile.ActiveBuild]
end

function ShowcaseService:RenderLabel(index: number)
	local pedestal = pedestals[index]
	local owner = pedestal.Owner
	local profile = owner and self.Services.PlayerDataService:Get(owner)
	local build = activeBuild(profile)
	if not owner or not build then
		pedestal.Label.Name.Text = ""
		pedestal.Label.Info.Text = ""
		pedestal.Prompt.Enabled = false
		pedestal.Prompt.ObjectText = "Empty pedestal"
		return
	end
	local stats, archetype = StatCalculator.Compute(build)
	pedestal.Label.Name.Text = ('<font color="#FFC332">%s\'s</font> %s'):format(escape(owner.DisplayName), escape(build.Name))
	pedestal.Label.Info.Text = ('<font color="#E6372D">★ %d RESPECT</font>  ·  %s  ·  Power %d'):format(profile.Showcase.Likes or 0, archetype, stats.PowerCost)
	pedestal.Prompt.Enabled = true
	pedestal.Prompt.ObjectText = owner.DisplayName .. "'s Nightmare"
	pedestal.Prompt:SetAttribute("OwnerUserId", owner.UserId)
end

-- Rebuilds the statue if the owner's active build changed (or the pedestal is new).
function ShowcaseService:RefreshPedestal(index: number)
	local pedestal = pedestals[index]
	local owner = pedestal.Owner
	local build = owner and activeBuild(self.Services.PlayerDataService:Get(owner))
	local signature = build and HttpService:JSONEncode(build) or nil
	if signature == pedestal.Signature then
		return
	end
	pedestal.Signature = signature
	if pedestal.Model then
		pedestal.Model:Destroy()
		pedestal.Model = nil
	end
	if build then
		local ok, model, info = pcall(NightmareAssembler.Build, build, { Name = "Showcase_" .. owner.UserId })
		if ok then
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanCollide = false
					d.CanQuery = false
					d.CanTouch = false
				end
			end
			local top = pedestal.Position.Y + 1.2
			-- Nightmares face -Z, toward the Workshop; that's the side visitors come from.
			model:PivotTo(CFrame.new(pedestal.Position.X, top + info.HipHeight + info.HitboxSize.Y / 2, pedestal.Position.Z))
			model.Parent = pedestal.Base.Parent
			pedestal.Model = model
		else
			warn("[Showcase] couldn't build a statue:", model)
		end
	end
	self:RenderLabel(index)
end

function ShowcaseService:Assign(player: Player)
	if slotOf[player] then
		return
	end
	for index, pedestal in pedestals do
		if not pedestal.Owner then
			pedestal.Owner = player
			slotOf[player] = index
			self:RefreshPedestal(index)
			return
		end
	end
end

function ShowcaseService:Release(player: Player)
	local index = slotOf[player]
	if not index then
		return
	end
	slotOf[player] = nil
	local pedestal = pedestals[index]
	pedestal.Owner = nil
	self:RefreshPedestal(index)
end

------------------------------------------------------------------------------------------
-- Inspect / Like
------------------------------------------------------------------------------------------
-- Can `viewer` like `owner` right now? ok, reason
function ShowcaseService:CanLike(viewer: Player, owner: Player): (boolean, string?)
	if viewer == owner then
		return false, "That's your own Nightmare. Earn respect from others!"
	end
	local profile = self.Services.PlayerDataService:Get(viewer)
	if not profile then
		return false, "Your profile is still loading."
	end
	local given = profile.LikesGiven
	if given.Day == today() and given.To[tostring(owner.UserId)] then
		return false, "You already gave this Nightmare respect today. Come back tomorrow!"
	end
	return true, nil
end

function ShowcaseService:Inspect(viewer: Player, userId)
	local owner = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	local profile = owner and self.Services.PlayerDataService:Get(owner)
	local build = activeBuild(profile)
	if not build then
		return { Ok = false, Error = "That Nightmare isn't on display any more." }
	end
	local canLike, reason = self:CanLike(viewer, owner)
	return {
		Ok = true,
		OwnerName = owner.DisplayName,
		OwnerUserId = owner.UserId,
		Build = Util.DeepCopy(build),
		Likes = profile.Showcase.Likes or 0,
		CanLike = canLike,
		LikeNote = reason,
	}
end

function ShowcaseService:Like(viewer: Player, userId)
	local owner = type(userId) == "number" and Players:GetPlayerByUserId(userId)
	local ownerProfile = owner and self.Services.PlayerDataService:Get(owner)
	local viewerProfile = self.Services.PlayerDataService:Get(viewer)
	if not ownerProfile or not viewerProfile then
		return { Ok = false, Error = "That Nightmare isn't on display any more." }
	end
	local ok, reason = self:CanLike(viewer, owner)
	if not ok then
		return { Ok = false, Error = reason }
	end
	local given = viewerProfile.LikesGiven
	if given.Day ~= today() then
		viewerProfile.LikesGiven = { Day = today(), To = {} } -- new day: start a fresh list
		given = viewerProfile.LikesGiven
	end
	given.To[tostring(owner.UserId)] = true
	ownerProfile.Showcase.Likes = (ownerProfile.Showcase.Likes or 0) + 1
	self.Services.PlayerDataService:SaveNow(owner)
	self.Services.PlayerDataService:SaveNow(viewer)
	self.Services.NightmareBuildService:PushState(owner)
	if slotOf[owner] then
		self:RenderLabel(slotOf[owner])
	end
	Net.Get("UIStateUpdate"):FireClient(owner, "Toast", { Text = ("★ %s gave your Nightmare RESPECT! (%d total)"):format(viewer.DisplayName, ownerProfile.Showcase.Likes) })
	return { Ok = true, Likes = ownerProfile.Showcase.Likes }
end

------------------------------------------------------------------------------------------
-- Lifecycle
------------------------------------------------------------------------------------------
function ShowcaseService:Start()
	self:BuildPedestals()

	Net.Get("ShowcaseRequest").OnServerInvoke = function(player, action, userId)
		if not self.Services.AntiExploitService:Allow(player, "ShowcaseRequest") then
			return { Ok = false, Error = "Slow down a little!" }
		end
		if action == "Inspect" then
			return self:Inspect(player, userId)
		elseif action == "Like" then
			return self:Like(player, userId)
		end
		return { Ok = false, Error = "Unknown request." }
	end

	local function onPlayer(player: Player)
		task.spawn(function()
			if self.Services.PlayerDataService:WaitFor(player, 30) and player.Parent then
				self:Assign(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		self:Release(player)
	end)

	-- Statues follow build changes (cheap: compares a JSON signature per pedestal).
	task.spawn(function()
		while true do
			task.wait(SHOW.RefreshInterval)
			for index, pedestal in pedestals do
				if pedestal.Owner then
					self:RefreshPedestal(index)
					self:RenderLabel(index)
				end
			end
		end
	end)
end

return ShowcaseService
