--[[
	PoseTools  (ModuleScript, data helpers)
	Location: ReplicatedStorage/Shared/PoseTools

	Finishing passes on pose library clips (NightmarePoses, BossPoses), so they read the same
	way however they were keyed. Shared rather than beside the pose files because the exporter
	requires clones of those, which have no parent to look next to.
]]

local PoseTools = {}

local IMPACT = { Hit = true, Strike = true, Land = true, JawSnap = true }

-- Gives a clip weight: it flows through its keys (Spline) and every blow lands: fast into the
-- contact key, dead stop on it. `overshoot` (0..1): the body then carries on past the contact
-- pose by that share of the move that brought it there, and comes back: mass, not a stop-frame.
-- (Contact times don't move, so the server's hits stay on their frames.)
function PoseTools.Punch(def, overshoot: number?)
	if def.Punched then
		return def
	end
	def.Punched = true
	def.Curve = "Spline"
	local impacts = {}
	for _, marker in def.Markers or {} do
		if IMPACT[marker[2]] then
			table.insert(impacts, marker[1])
		end
	end
	local added = {}
	for index, key in def.Keys do
		for _, t in impacts do
			if math.abs(key.T - t) < 0.005 and index > 1 then
				key.Ease = key.Ease or "Snap"
				key.Stop = true
				local before, after = def.Keys[index - 1], def.Keys[index + 1]
				if overshoot and after and after.T - key.T >= 0.14 then
					local extra = { T = key.T + 0.055, Ease = "Out" }
					for joint, value in key do
						if type(value) == "table" then
							local from = before[joint] or { 0, 0, 0 }
							local isPos = joint:match("Pos$") ~= nil
							local scale = isPos and overshoot * 0.6 or overshoot
							extra[joint] = { value[1] + (value[1] - from[1]) * scale, value[2] + (value[2] - from[2]) * scale, value[3] + (value[3] - from[3]) * scale }
						end
					end
					table.insert(added, extra)
				end
				break
			end
		end
	end
	for _, key in added do
		table.insert(def.Keys, key)
	end
	table.sort(def.Keys, function(a, b)
		return a.T < b.T
	end)
	return def
end

return PoseTools
