--[[
	BlockLab  (ModuleScript, DEV TOOL)
	Location: ServerStorage/DevTools/BlockLab   (Rojo: tools/, never shipped to players)

	Measures blocking through the real damage pipeline (CombatService:ApplyDamage), with a
	Training Dummy as the attacker so nothing else interferes, and prints what each case did.
	Your health is put back after each one; nothing here is saved.

	  require(game.ServerStorage.DevTools.BlockLab:Clone()).Run()         -- SERVER view, your Handler
	  require(game.ServerStorage.DevTools.BlockLab:Clone()).Run("Nightmare")  -- your Nightmare
	  require(game.ServerStorage.DevTools.BlockLab:Clone()).Show("Handler", 15) -- hold the stance at a level
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Lab = {}

-- (the command bar has its own copies of every module: the running game's services are reached
-- through the DevBridge)
local function service(name: string)
	return setmetatable({}, {
		__index = function(_, method: string)
			return function(_, ...)
				return ServerStorage.DevBridge:Invoke(name, method, ...)
			end
		end,
	})
end
local Combat = service("CombatService")
local Block = service("BlockService")

local function bodyOf(kind: string?): Model
	local player = Players:GetPlayers()[1]
	if kind == "Nightmare" then
		return Workspace:FindFirstChild("Nightmare_" .. player.UserId, true)
	end
	return player.Character
end

local function dummy(): Model
	for _, enemy in CollectionService:GetTagged("Enemy") do
		if enemy.Name:find("Dummy") then
			return enemy
		end
	end
	error("no Training Dummy")
end

local function heal(body: Model)
	local humanoid = body:FindFirstChildOfClass("Humanoid")
	humanoid.Health = humanoid.MaxHealth
end

local function hit(body: Model, attacker: Model, damage: number, extra): number
	local params = { Attacker = attacker, Target = body, BaseDamage = damage, AttackPower = 100, Source = "BlockLab", IgnoreDefence = true }
	for key, value in extra or {} do
		params[key] = value
	end
	return Combat:ApplyDamage(params)
end

local function level(body: Model): number
	return body:GetAttribute("GuardLevel") or 100
end

-- A clean guard: full meter, up and past its startup (and past a parry window, on a Handler).
local function raise(body: Model)
	Block:Release(body)
	Block:DevSetLevel(body, 100)
	task.wait(1.5)
	Block:Press(body)
	task.wait(0.32)
end

function Lab.Run(kind: string?)
	task.spawn(function()
		local body, attacker = bodyOf(kind), dummy()
		local root = body:FindFirstChild("HumanoidRootPart")
		-- (out on the open floor, away from the arena's Scraplings)
		local away = attacker:GetPivot().Position
		attacker:PivotTo(CFrame.new(40, away.Y, 120))
		local spot = attacker:GetPivot().Position + attacker:GetPivot().LookVector * 7
		root.Anchored = true
		local function face(towardAttacker: boolean)
			local at = attacker:GetPivot().Position
			local flat = Vector3.new(at.X, spot.Y, at.Z)
			body:PivotTo(towardAttacker and CFrame.lookAt(spot, flat) or CFrame.lookAt(spot, spot + (spot - flat)))
		end
		local out = {}
		local function note(text: string, ...)
			local line = text:format(...)
			table.insert(out, line)
			print("[BlockLab] " .. line)
		end
		local big = kind == "Nightmare" and 18 or 7 -- a typical blow on this body

		face(true)
		Block:Release(body)
		task.wait(1.5)
		heal(body)
		note("no guard: %d damage from a %d blow", hit(body, attacker, big), big)

		face(true)
		raise(body)
		heal(body)
		note("fresh guard: %d from a %d blow, meter %d", hit(body, attacker, big), big, level(body))

		raise(body)
		heal(body)
		note("heavy on a fresh guard: %d from %d, meter %d", hit(body, attacker, big * 2, { Heavy = true }), big * 2, level(body))

		face(false)
		raise(body)
		heal(body)
		note("from BEHIND a raised guard: %d from %d", hit(body, attacker, big), big)
		face(true)

		raise(body)
		heal(body)
		note("unblockable: %d from %d", hit(body, attacker, big, { Unblockable = true }), big)

		-- standing under a steady stream of blows until it goes
		raise(body)
		heal(body)
		local dealt, started, count = {}, os.clock(), 0
		while Block:IsHolding(body) and os.clock() - started < 15 do
			table.insert(dealt, hit(body, attacker, big))
			count += 1
			task.wait(0.35)
		end
		note("under fire: broke after %d blows, %.1f s; damage per blow %s", count, os.clock() - started, table.concat(dealt, " "))
		heal(body)
		note("while broken: %d from %d (guard pressed: %s)", hit(body, attacker, big), big, tostring(Block:Press(body)))

		-- nothing hitting it: how long until it fails, and goes
		task.wait(1.5)
		raise(body)
		started = os.clock()
		local crackedAt
		while Block:IsHolding(body) and os.clock() - started < 15 do
			if not crackedAt and level(body) <= 40 then
				crackedAt = os.clock() - started
			end
			task.wait(0.05)
		end
		note("held untouched: failing at %.1f s, broke at %.1f s", crackedAt or -1, os.clock() - started)

		-- recovery, sampled from the moment it broke
		local samples = {}
		for _ = 1, 8 do
			table.insert(samples, level(body))
			task.wait(0.5)
		end
		note("after a break, every 0.5 s: %s", table.concat(samples, " "))
		root.Anchored = false
		heal(body)
		print("[BlockLab] done")
	end)
end

-- Holds the stance at a meter level, to look at (nil level: lets go).
function Lab.Show(kind: string?, at: number?)
	local body = bodyOf(kind)
	if at then
		Block:DevSetLevel(body, at)
		Block:Press(body)
		Block:DevSetLevel(body, at)
	else
		Block:Release(body)
		Block:DevSetLevel(body, 100)
	end
end

-- Breaks the guard right now, to watch it crumble.
function Lab.Break(kind: string?)
	Block:Break(bodyOf(kind), nil)
end

return Lab
