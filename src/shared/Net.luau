--[[
	Net  (ModuleScript)
	Location: ReplicatedStorage/Shared/Net

	Single source of truth for every remote. The server calls Net.Setup() once at boot,
	which creates ReplicatedStorage/Remotes/<name>. Both sides fetch them with Net.Get().

	  BuildRequest       RemoteFunction  C->S  "GetState" | "SaveBuild" | "SetActive"
	  CombatAction       RemoteEvent     C->S  "Melee", seq, flag? | "Equip", id | "Dodge", dir | "Guard", bool | "Ability", 1|2
	  NightmareCommand   RemoteEvent     C->S  "Attack"(target) | "Follow" | "Retreat" | "ToggleSummon"
	  BossRequest        RemoteFunction  C->S  "Start", bossId, mode? | "Leave" | "Replay" | "Return"
	  TutorialAction     RemoteEvent     C->S  "Skip"
	  CombatFeedback     RemoteEvent     S->all "Damage" | "Defeated" | "Blocked" | "GuardBreak"
	  WorldFX            RemoteEvent     S->all "Telegraph" | "Impact" | "Projectile" | "Shield"
	  PlayerFX           RemoteEvent     S->one "Impulse", velocity (server can't push client-owned characters)
	  BossEvent          RemoteEvent     S->one "Start" | "Phase" | "End"
	  RewardNotification RemoteEvent     S->one reward summary after a victory
	  DuelRequest        RemoteFunction  C->S  "Challenge" | "Respond" | "SetAllow" | "SelectBuild" | "Forfeit"
	  DuelEvent          RemoteEvent     S->one "Incoming" | "RequestResult" | "State" | "Banner" | "MatchEnd"
	  UIStateUpdate      RemoteEvent     S->one "Profile" | "NightmareDefeated" | "Summon" | "Toast" | "LevelUp" | "Challenges"
	  CraftRequest       RemoteFunction  C->S  "Craft", partId | "Dismantle", partId, count
	  PartyRequest       RemoteFunction  C->S  "Invite", userId | "Respond", inviteId, bool | "Leave" | "Kick", userId
	  PartyEvent         RemoteEvent     S->one "Incoming" | "State" | "Result"
	  ShowcaseRequest    RemoteFunction  C->S  "Inspect", userId | "Like", userId
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.Definitions = {
	BuildRequest = "RemoteFunction",
	CombatAction = "RemoteEvent",
	NightmareCommand = "RemoteEvent",
	BossRequest = "RemoteFunction",
	TutorialAction = "RemoteEvent",
	CombatFeedback = "RemoteEvent",
	WorldFX = "RemoteEvent",
	PlayerFX = "RemoteEvent",
	BossEvent = "RemoteEvent",
	RewardNotification = "RemoteEvent",
	DuelRequest = "RemoteFunction",
	DuelEvent = "RemoteEvent",
	UIStateUpdate = "RemoteEvent",
	CraftRequest = "RemoteFunction",
	PartyRequest = "RemoteFunction",
	PartyEvent = "RemoteEvent",
	ShowcaseRequest = "RemoteFunction",
}

function Net.Setup()
	assert(RunService:IsServer(), "Net.Setup must run on the server")
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
	end
	for name, className in Net.Definitions do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new(className)
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

-- SERVER: fire a remote only to players whose character is within `radius` studs of
-- `position` (visual effects nobody far away can see: damage numbers, telegraphs,
-- impacts...). Saves bandwidth and client work in busy servers. No position = everyone.
function Net.FireNearby(remote: RemoteEvent, position: Vector3?, radius: number, ...)
	if typeof(position) ~= "Vector3" then
		remote:FireAllClients(...)
		return
	end
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and (root.Position - position).Magnitude <= radius then
			remote:FireClient(player, ...)
		end
	end
end

function Net.Get(name: string)
	assert(Net.Definitions[name], "Unknown remote: " .. tostring(name))
	local folder = ReplicatedStorage:WaitForChild("Remotes")
	return folder:WaitForChild(name)
end

return Net
