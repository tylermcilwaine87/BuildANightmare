--[[
	AbilityLab  (ModuleScript, DEV TOOL)
	Location: ServerStorage/DevTools/AbilityLab   (Rojo: tools/, never shipped to players)

	Fires Nightmare abilities for real in a Studio playtest and measures what they did. From
	the command bar in the SERVER view:

	  local Lab = require(game.ServerStorage.DevTools.AbilityLab:Clone())
	  Lab.Run("FrostRam")              -- one ability, on a toughened Scrapling
	  Lab.Run("FrostRam", { Legs = "MangyHoundLegs" })   -- on a different body
	  task.spawn(Lab.RunAll)           -- all of them, one line each
	  Lab.Loop("FrostRam")             -- keep casting it, to watch from the game view

	Each run spawns a Studio-only test body (NightmareSpawnService:DevSpawn: it earns no
	mastery, your saved builds aren't touched), holds its combat brain off it, stages it in
	range of the Scrapling and casts the ability on it (AbilityService:DevCast), so the
	numbers are that ability's alone. Printed:
	  acted   seconds from the request until its action started (nil: it never fired)
	  moved   studs the body travelled; gap = closest it got to the victim
	  vy      the victim's highest point above where it stood
	  held    when the victim was gripped (from - to)
	  dmg     each hit: time:amount
	Requires the Training Arena's Scraplings (they stay put while the player is inside it).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Lab = {}

local ARENA = Vector3.new(88, 0, -70)

-- id -> { parts that give it, slot it lands in, studs from the victim to cast from }
-- (the Peeper Orb: a core with no ability of its own and no thorns to muddy the damage)
local BASE = { Core = "PeeperOrb", Head = "CrackedSkull", Legs = "ScrapLegs" }
Lab.Tests = {
	{ "Bite", {}, 1, 6 },
	{ "ChargedBite", { Head = "ElectricJaw" }, 1, 6 },
	{ "FrostRam", { Head = "FrostHorns" }, 1, 8 },
	{ "ScrapVisorBeam", { Head = "ScrapVisor" }, 1, 9 },
	{ "DragonBreath", { Head = "DragonSkull" }, 1, 9 },
	{ "RustySlash", { RightArm = "RustyClaw" }, 2, 5 },
	{ "TentacleLash", { RightArm = "ShadowTentacle" }, 2, 10 },
	{ "DemonRend", { RightArm = "DemonicClaws" }, 2, 6 },
	{ "MagnetPull", { RightArm = "MagneticClaw" }, 2, 16 },
	{ "HammerSlam", { RightArm = "TitanHammerArm" }, 2, 7 },
	{ "MeteorFist", { RightArm = "InfernoGauntlet" }, 2, 12 },
	{ "BatDive", { Back = "TinyBatWings" }, 2, 8 },
	{ "BlinkDash", { Back = "VoidWings" }, 2, 10 },
	{ "PhoenixDive", { Back = "PhoenixWings" }, 2, 8 },
	{ "TailSweep", { Tail = "BentMetalTail" }, 2, 5 },
	{ "VenomSting", { Tail = "ScorpionTail" }, 2, 5 },
	{ "ReinforcedGuard", { Core = "ReinforcedCore" }, 2, 6 },
	{ "CrystalBarrier", { Core = "CrystalShell" }, 2, 6 },
	{ "EnergyOverload", { Core = "ReactorHeart" }, 2, 6 },
	{ "MagmaShell", { Core = "ObsidianHeart" }, 2, 6 },
}

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

local function scrapling(): Model?
	local best, bestDistance
	for _, enemy in Workspace.Enemies:GetChildren() do
		local humanoid = enemy:FindFirstChildOfClass("Humanoid")
		if enemy.Name == "Scrapling" and enemy:FindFirstChild("HumanoidRootPart") and humanoid and humanoid.Health > 0 then
			local distance = (enemy:GetPivot().Position * Vector3.new(1, 0, 1) - ARENA).Magnitude
			if not bestDistance or distance < bestDistance then
				best, bestDistance = enemy, distance
			end
		end
	end
	return best
end

-- Runs one test; returns its report line (and prints it). `extra` overrides body parts.
function Lab.Run(id: string, extra, seconds: number?)
	local test
	for _, t in Lab.Tests do
		if t[1] == id then
			test = t
		end
	end
	assert(test, "no test for " .. tostring(id))
	local player = Players:GetPlayers()[1]
	local parts = table.clone(BASE)
	for slot, part in test[2] do
		parts[slot] = part
	end
	for slot, part in extra or {} do
		parts[slot] = part or nil -- (false removes a part: e.g. RightArm = false, LeftArm = "RustyClaw")
	end
	-- (the handler is standing among Scraplings: keep them alive, or no body can spawn)
	local handler = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if handler then
		handler.MaxHealth, handler.Health = 100000, 100000
	end
	invoke("NightmareSpawnService", "DevSpawn", player, { Parts = parts })
	invoke("AbilityService", "DevHoldBrain", player, true)
	task.wait(0.8)
	local model, victim = myNightmare(player), scrapling()
	if not model or not victim then
		warn("[Lab] " .. id .. ": no body or no Scrapling")
		return
	end
	-- wait for the Scrapling to be back on its feet from the last test
	local waited = os.clock()
	while victim:GetAttribute("Ragdolled") and os.clock() - waited < 6 do
		task.wait(0.1)
	end
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	humanoid.MaxHealth, humanoid.Health = 20000, 20000
	local victimRoot, root = victim.HumanoidRootPart, model.HumanoidRootPart
	victimRoot.AssemblyLinearVelocity = Vector3.zero
	local spot = Vector3.new(ARENA.X, victimRoot.Position.Y, ARENA.Z)
	victim:PivotTo(CFrame.lookAt(spot, spot - Vector3.xAxis))
	if player.Character then
		player.Character:PivotTo(CFrame.lookAt(spot + Vector3.new(-4, 1, -14), spot + Vector3.new(-4, 0, 0)))
	end
	local stage = spot - Vector3.xAxis * test[4]
	model:PivotTo(CFrame.lookAt(Vector3.new(stage.X, root.Position.Y, stage.Z), Vector3.new(spot.X, root.Position.Y, spot.Z)))
	task.wait(0.15)
	invoke("AbilityService", "DevCast", player, test[3], victim)

	local start, standY = root.Position, victimRoot.Position.Y
	local began = os.clock()
	local acted, moved, gap, top = nil, 0, math.huge, 0
	local heldFrom, heldTo = nil, nil
	local hits, health = {}, humanoid.Health
	local action = "Ability_" .. id
	local c1 = humanoid.HealthChanged:Connect(function(now)
		if now < health and (acted or false) then
			table.insert(hits, ("%.2f:%d"):format(os.clock() - began, health - now + 0.5))
		end
		health = now
	end)
	local c2 = RunService.Heartbeat:Connect(function()
		local t = os.clock() - began
		local current = model:GetAttribute("ActionName")
		if not acted and type(current) == "string" and current:find(action, 1, true) then
			acted = t
		end
		if root.Parent then
			moved = math.max(moved, ((root.Position - start) * Vector3.new(1, 0, 1)).Magnitude)
			gap = math.min(gap, ((victimRoot.Position - root.Position) * Vector3.new(1, 0, 1)).Magnitude)
		end
		top = math.max(top, victimRoot.Position.Y - standY)
		if victim:GetAttribute("Gripped") then
			heldFrom = heldFrom or t
			heldTo = t
		end
	end)
	task.wait(seconds or 3.4)
	c1:Disconnect()
	c2:Disconnect()
	local line = ("[Lab] %-15s acted=%s moved=%.1f gap=%.1f vy=%.1f held=%s dmg=%s"):format(
		id,
		acted and ("%.2f"):format(acted) or "NEVER",
		moved,
		gap,
		top,
		heldFrom and ("%.2f-%.2f"):format(heldFrom, heldTo) or "-",
		#hits > 0 and table.concat(hits, " ") or "-"
	)
	print(line)
	return line
end

-- Keeps casting one ability, for watching it from the game view (the effects are too fast to
-- catch in one go). Lab.Loop("FrostRam") switches to that ability; Lab.Loop(nil) stops.
function Lab.Loop(id: string?, extra)
	local running = Lab.LoopId ~= nil
	Lab.LoopId, Lab.LoopExtra = id, extra
	if running or not id then
		return
	end
	task.spawn(function()
		while Lab.LoopId do
			local ok, err = pcall(Lab.Run, Lab.LoopId, Lab.LoopExtra, 3)
			if not ok then
				warn("[Lab] " .. tostring(Lab.LoopId) .. " FAILED: " .. tostring(err))
				task.wait(1)
			end
			task.wait(0.6)
		end
	end)
end

function Lab.RunAll()
	for _, test in Lab.Tests do
		local ok, err = pcall(Lab.Run, test[1])
		if not ok then
			warn("[Lab] " .. test[1] .. " FAILED: " .. tostring(err))
		end
	end
	print("[Lab] done")
end

return Lab
