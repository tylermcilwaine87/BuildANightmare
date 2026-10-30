--[[
	FightLab  (ModuleScript, DEV TOOL)
	Location: ServerStorage/DevTools/FightLab   (Rojo: tools/, never shipped to players)

	A Nightmare vs Nightmare ring in a Studio playtest, with one player. From the command bar in
	the SERVER view:

	  local Lab = require(game.ServerStorage.DevTools.FightLab:Clone())
	  Lab.Start()                         -- your Nightmare (its real combat brain) vs a sparring body
	  Lab.Force("Gym_ComboB")             -- keep throwing this string (nil: back to its own choice)
	  Lab.Spar(true)                      -- the sparring body throws strings back (no damage)
	  print(Lab.Report())                 -- per string: blows thrown, landed, missed
	  Lab.Stop()

	The sparring body is a real assembled Nightmare with no brain, toughened so it can't die: a
	Studio-only DevSpawn body attacks it, so nothing here touches saved builds or mastery.
	Reads the [Combo] log, so it needs Config.Dev.LogNightmareCombos.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local CollectionService = game:GetService("CollectionService")
local LogService = game:GetService("LogService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Lab = {}

Lab.Spot = Vector3.new(88, 0, -70)
Lab.Fighter = { Core = "PeeperOrb", Head = "CrackedSkull", Legs = "ScrapLegs", RightArm = "DemonicClaws", LeftArm = "DemonicClaws" }
Lab.Opponent = { Core = "ReinforcedCore", Head = "ScrapVisor", Legs = "ScrapLegs", RightArm = "RustyClaw", LeftArm = "RustyClaw" }

local STRINGS = { "Gym_ComboA", "Gym_ComboB", "Gym_ComboC", "Gym_BodyRip", "Gym_OneTwoLow", "Gym_LiverHead", "Gym_Teep", "Gym_Roundhouse", "Gym_Power", "Combo_BrutalBoxer" }

local function invoke(service: string, method: string, ...)
	return ServerStorage.DevBridge:Invoke(service, method, ...)
end

local function myNightmare(player: Player): Model?
	for _, model in Workspace.Nightmares:GetChildren() do
		if model:GetAttribute("OwnerUserId") == player.UserId then
			return model
		end
	end
	return nil
end

function Lab.SpawnOpponent(parts)
	local assembler = require(Shared:WaitForChild("NightmareAssembler"))
	local model, info = assembler.Build({ Name = "Sparring", Parts = parts or Lab.Opponent }, { Name = "Sparring" })
	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = info.HipHeight
	humanoid.MaxHealth, humanoid.Health = 1000000, 1000000
	humanoid.WalkSpeed = 0
	humanoid.BreakJointsOnDeath = false
	humanoid.RequiresNeck = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.Parent = model
	model:SetAttribute("Archetype", info.Archetype)
	model:SetAttribute("ActionSeq", 0)
	model:SetAttribute("FightStance", true)
	model:SetAttribute("Defence", 0)
	model.Parent = Workspace.Enemies
	CollectionService:AddTag(model, "Enemy")
	CollectionService:AddTag(model, "Nightmare")
	return model
end

function Lab.Start(fighter, opponent)
	Lab.Stop()
	local player = Players:GetPlayers()[1]
	local handler = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if handler then
		handler.MaxHealth, handler.Health = 100000, 100000
	end
	-- (only the sparring body in the ring)
	for _, enemy in Workspace.Enemies:GetChildren() do
		if enemy.Name == "Scrapling" then
			enemy:Destroy()
		end
	end
	local model = Lab.SpawnOpponent(opponent)
	local y = 8
	local ray = Workspace:Raycast(Lab.Spot + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0))
	if ray then
		y = ray.Position.Y + model:GetExtentsSize().Y / 2 + 1
	end
	model:PivotTo(CFrame.new(Lab.Spot.X, y, Lab.Spot.Z))
	Lab.Model = model
	if player.Character then
		player.Character:PivotTo(CFrame.lookAt(Lab.Spot + Vector3.new(-6, y, -16), Lab.Spot + Vector3.new(0, y, 0)))
	end
	invoke("NightmareSpawnService", "DevSpawn", player, { Parts = fighter or Lab.Fighter })
	task.wait(0.8)
	local mine = myNightmare(player)
	if mine then
		mine:PivotTo(CFrame.lookAt(Lab.Spot + Vector3.new(-12, y, 0), Lab.Spot + Vector3.new(0, y, 0)))
	end
	-- the sparring body keeps squared up on it, and never dies
	Lab.Connection = RunService.Heartbeat:Connect(function()
		local them = myNightmare(player)
		local root = model:FindFirstChild("HumanoidRootPart")
		if them and root and not model:GetAttribute("Ragdolled") then
			local p = root.Position
			local q = them:GetPivot().Position
			if (Vector3.new(q.X, p.Y, q.Z) - p).Magnitude > 0.1 then
				root.CFrame = CFrame.lookAt(p, Vector3.new(q.X, p.Y, q.Z))
			end
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid and humanoid.Health < 500000 then
			humanoid.Health = humanoid.MaxHealth
		end
	end)
	Lab.Since = os.clock()
	print("[FightLab] ready")
	return model
end

function Lab.Force(action: string?)
	return invoke("NightmareAIService", "DevForceString", Players:GetPlayers()[1], action, action ~= nil)
end

-- The sparring body throws strings back (the animation only, in its own time), so you can see
-- how both bodies read when they're both working.
function Lab.Spar(on: boolean)
	Lab.Sparring = on or nil
	if not on or Lab.SparThread then
		return
	end
	Lab.SparThread = task.spawn(function()
		while Lab.Sparring and Lab.Model and Lab.Model.Parent do
			local action = STRINGS[math.random(1, #STRINGS)]
			local duration = 0
			for _, def in require(Shared:WaitForChild("Config")).Nightmare.Moveset do
				if def.Action == action then
					duration = def.Duration
				end
			end
			if duration > 0 and not Lab.Model:GetAttribute("Ragdolled") then
				Lab.Model:SetAttribute("ActionName", action)
				Lab.Model:SetAttribute("ActionWindup", duration * 0.45)
				Lab.Model:SetAttribute("ActionDuration", duration)
				Lab.Model:SetAttribute("ActionSeq", (Lab.Model:GetAttribute("ActionSeq") or 0) + 1)
			end
			task.wait(duration + 0.6 + math.random() * 0.8)
		end
		Lab.SparThread = nil
	end)
end

-- Every standard string in turn, `seconds` each, then the report.
function Lab.Sweep(seconds: number?, list)
	for _, action in list or STRINGS do
		Lab.Force(action)
		task.wait(seconds or 5)
	end
	Lab.Force(nil)
	print(Lab.Report())
end

-- From the [Combo] log since Start: each string's blows, how many landed, how many went nowhere.
function Lab.Report(): string
	local rows, order = {}, {}
	for _, entry in LogService:GetLogHistory() do
		local action, gap, result = entry.message:match("^%[Combo%] ([%w_]+) hit %d+ @[%d%.]+ gap ([%d%.%-]+) %-> (.+)$")
		if action then
			local row = rows[action]
			if not row then
				row = { Thrown = 0, Landed = 0, Gap = 0 }
				rows[action] = row
				table.insert(order, action)
			end
			row.Thrown += 1
			row.Gap += tonumber(gap) or 0
			if result ~= "MISS" then
				row.Landed += 1
			end
		end
	end
	local lines, thrown, landed = {}, 0, 0
	for _, action in order do
		local row = rows[action]
		thrown += row.Thrown
		landed += row.Landed
		table.insert(lines, ("%s %d/%d gap %.1f"):format(action, row.Landed, row.Thrown, row.Gap / row.Thrown))
	end
	table.insert(lines, ("TOTAL %d/%d"):format(landed, thrown))
	return "[FightLab] " .. table.concat(lines, " | ")
end

function Lab.Stop()
	Lab.Sparring = nil
	if Lab.Connection then
		Lab.Connection:Disconnect()
		Lab.Connection = nil
	end
	if Lab.Model then
		Lab.Model:Destroy()
		Lab.Model = nil
	end
end

return Lab
