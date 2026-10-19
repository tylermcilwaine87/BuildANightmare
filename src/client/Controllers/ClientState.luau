--[[
	ClientState  (ModuleScript)
	Location: StarterPlayer/StarterPlayerScripts/Client/Controllers/ClientState

	Holds the latest server-provided profile SNAPSHOT (read-only display copy) and wraps
	the BuildRequest RemoteFunction. Fires:
	  ClientState.Changed(profile)          whenever a new snapshot arrives
	  ClientState.ServerEvent(kind, data)   for other UIStateUpdate messages
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local ClientState = {}
ClientState.Profile = nil

local changedEvent = Instance.new("BindableEvent")
local serverEvent = Instance.new("BindableEvent")
ClientState.Changed = changedEvent.Event
ClientState.ServerEvent = serverEvent.Event

local localPlayer = Players.LocalPlayer

function ClientState:Init()
	self.BuildRequest = Net.Get("BuildRequest")
	self.UIStateUpdate = Net.Get("UIStateUpdate")
end

function ClientState:Start()
	self.UIStateUpdate.OnClientEvent:Connect(function(kind, data)
		if kind == "Profile" then
			self:SetProfile(data)
		else
			serverEvent:Fire(kind, data)
		end
	end)
	task.spawn(function()
		self:Refresh()
	end)
end

function ClientState:SetProfile(profile)
	self.Profile = profile
	changedEvent:Fire(profile)
end

function ClientState:Refresh(): boolean
	for _ = 1, 10 do
		local result = self:Request("GetState")
		if result.Ok then
			return true
		end
		task.wait(1)
	end
	return false
end

-- Invokes BuildRequest safely and applies any returned snapshot.
function ClientState:Request(action: string, ...)
	local ok, result = pcall(self.BuildRequest.InvokeServer, self.BuildRequest, action, ...)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Error = "Could not reach the server." }
	end
	if result.Ok and result.State then
		self:SetProfile(result.State)
	end
	return result
end

function ClientState:GetMyNightmare(): Model?
	for _, model in CollectionService:GetTagged("Nightmare") do
		if model:GetAttribute("OwnerUserId") == localPlayer.UserId and not model:GetAttribute("Defeated") then
			return model
		end
	end
	return nil
end

return ClientState
