--[[
	Util  (ModuleScript)
	Location: ReplicatedStorage/Shared/Util

	Small, pure helper functions shared by server and client.
]]

local Util = {}

function Util.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[Util.DeepCopy(k)] = Util.DeepCopy(v)
	end
	return copy
end

function Util.DeepEqual(a, b): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for k, v in a do
		if not Util.DeepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Rejects NaN and infinities, which exploiters love to send through remotes.
function Util.IsFiniteNumber(x): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function Util.RoundTo(x: number, step: number): number
	return math.floor(x / step + 0.5) * step
end

function Util.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function Util.FlatDistance(a: Vector3, b: Vector3): number
	return Util.Flat(a - b).Magnitude
end

function Util.FlatUnit(v: Vector3): Vector3?
	local flat = Util.Flat(v)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

function Util.Trim(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

-- Truncates by characters (not bytes) so emoji/accents never get cut in half.
function Util.TruncateUtf8(text: string, maxChars: number): string
	local length = utf8.len(text)
	if not length then
		return ""
	end
	if length <= maxChars then
		return text
	end
	local cut = utf8.offset(text, maxChars + 1)
	return string.sub(text, 1, cut - 1)
end

-- 12500 -> "12,500"
function Util.FormatNumber(n: number): string
	local text = tostring(math.floor(n))
	local sign, digits = text:match("^(-?)(%d+)$")
	if not digits then
		return text
	end
	return sign .. digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

return Util
