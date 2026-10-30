--[[
	PoseCurve  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/PoseCurve

	How a keyframed pose library clip (NightmarePoses, BossPoses) moves between its keys:
	Sample(def, joint, t) -> x, y, z (degrees, or studs for a "...Pos" key). Used by
	NightmareAnimator to play clips and by tools/AnimationExporter to bake them.

	Keys are poses (a joint a key leaves out is at rest there).
	  * By default each segment eases in and out of its keys: the body stops on every key.
	  * Curve = "Spline" on a clip: it flows THROUGH its keys (a cubic through the
	    neighbouring keys, so momentum carries from one pose into the next: arcs instead of
	    corners). A key with Stop = true still comes to rest on its pose (an impact).
	  * Ease on a key: how the move arrives at it (the segment ending on that key):
	      Smooth  ease in and out (default)   Linear  constant speed
	      In      accelerating into it (a blow landing)   Out  decelerating into it
	      Snap    slow, then very fast (a whip, a jaw slamming shut)
	      Hold    stays on the previous key until this one, then jumps (a twitch)
]]

local PoseCurve = {}

local function smooth(p: number): number
	return p * p * (3 - 2 * p)
end

PoseCurve.Ease = {
	Smooth = smooth,
	Linear = function(p)
		return p
	end,
	In = function(p)
		return p * p
	end,
	Out = function(p)
		return 1 - (1 - p) * (1 - p)
	end,
	Snap = function(p)
		return p * p * p
	end,
	Hold = function(p)
		return p >= 1 and 1 or 0
	end,
}

local ZERO3 = { 0, 0, 0 }

-- Does this clip need more than plain eased keys (so an exporter has to bake it)?
function PoseCurve.IsCurved(def): boolean
	if def.Curve == "Spline" then
		return true
	end
	for _, key in def.Keys do
		if key.Ease and key.Ease ~= "Smooth" then
			return true
		end
	end
	return false
end

function PoseCurve.Sample(def, joint: string, t: number): (number, number, number)
	local keys = def.Keys
	local n = #keys
	local i = n - 1
	for j = 1, n - 1 do
		if t <= keys[j + 1].T then
			i = j
			break
		end
	end
	local k0, k1 = keys[i], keys[i + 1]
	local a, b = k0[joint] or ZERO3, k1[joint] or ZERO3
	local span = k1.T - k0.T
	local p = span > 0 and math.clamp((t - k0.T) / span, 0, 1) or 1
	local ease = PoseCurve.Ease[k1.Ease or "Smooth"] or smooth
	if def.Curve ~= "Spline" then
		local k = ease(p)
		return a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
	end
	-- the slope through a key (per second): from its neighbours; none at the ends of the
	-- clip (it starts and ends at rest) or on a Stop key
	local function slope(index: number)
		local key = keys[index]
		if index <= 1 or index >= n or key.Stop then
			return 0, 0, 0
		end
		local before, after = keys[index - 1], keys[index + 1]
		local dt = after.T - before.T
		if dt <= 0 then
			return 0, 0, 0
		end
		local u, v = before[joint] or ZERO3, after[joint] or ZERO3
		return (v[1] - u[1]) / dt, (v[2] - u[2]) / dt, (v[3] - u[3]) / dt
	end
	local u = (k1.Ease and k1.Ease ~= "Smooth") and ease(p) or p
	local u2, u3 = u * u, u * u * u
	local h00, h10, h01, h11 = 2 * u3 - 3 * u2 + 1, u3 - 2 * u2 + u, -2 * u3 + 3 * u2, u3 - u2
	local m0x, m0y, m0z = slope(i)
	local m1x, m1y, m1z = slope(i + 1)
	return h00 * a[1] + h10 * span * m0x + h01 * b[1] + h11 * span * m1x,
		h00 * a[2] + h10 * span * m0y + h01 * b[2] + h11 * span * m1y,
		h00 * a[3] + h10 * span * m0z + h01 * b[3] + h11 * span * m1z
end

return PoseCurve
