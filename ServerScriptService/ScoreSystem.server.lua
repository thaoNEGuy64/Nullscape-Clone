-- ScoreSystem.server.lua
-- ServerScriptService
-- Team scoring: Artifacts (base) × Multi with momentum streak timer.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MOMENTUM_TIMEOUT = 20
local ARTIFACT_VALUE = 10

local function getOrCreateRemote(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then return ev end
	if ev then ev:Destroy() end
	ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local function getOrCreateBindable(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then return ev end
	if ev then ev:Destroy() end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local ItemPickupRE = getOrCreateRemote("ItemPickup")
local UpdateScoreHudRE = getOrCreateRemote("UpdateScoreHud")
local QuotaSetEvent = getOrCreateBindable("QuotaSet")
local ResetScoreEvent = getOrCreateBindable("ResetScore")
local QuotaMetEvent = getOrCreateBindable("QuotaMetEvent")
local ArtifactDepositedEvent = getOrCreateBindable("ArtifactDeposited")

local state = {
	artifacts = 0,
	multi = 1,
	teamScore = 0,
	quota = 1,
	streakCount = 0,
	lastCollectTime = 0,
	active = false,
	triggeredQuota = false,
}

local function broadcast()
	UpdateScoreHudRE:FireAllClients({
		artifacts = state.artifacts,
		multi = state.multi,
		teamScore = state.teamScore,
		quota = state.quota,
		active = state.active,
		momentumTimeout = MOMENTUM_TIMEOUT,
		lastCollectTime = state.lastCollectTime,
	})
end

local function resetRound(activate)
	state.artifacts = 0
	state.multi = 1
	state.teamScore = 0
	state.streakCount = 0
	state.lastCollectTime = 0
	state.triggeredQuota = false
	state.active = activate == true
	broadcast()
end

local function maybeTriggerQuota()
	if state.triggeredQuota then return end
	if state.teamScore >= state.quota then
		state.triggeredQuota = true
		QuotaMetEvent:Fire()
	end
end

local function applyMomentumOnCollect(now)
	if state.lastCollectTime > 0 and (now - state.lastCollectTime) <= MOMENTUM_TIMEOUT then
		state.streakCount += 1
	else
		state.streakCount = 1
		state.multi = 1
	end

	state.multi *= 1.5
	if state.streakCount == 2 then
		state.multi *= 2
	elseif state.streakCount == 5 then
		state.multi *= 2.5
	end
	state.lastCollectTime = now
end

local function registerCollect(player)
	if not state.active then return end
	if player and player:GetAttribute("IsDead") then return end

	local now = os.clock()
	applyMomentumOnCollect(now)

	state.artifacts += ARTIFACT_VALUE
	state.teamScore = math.floor(state.artifacts * state.multi)
	broadcast()
	maybeTriggerQuota()
end

ItemPickupRE.OnServerEvent:Connect(function(player, itemName)
	registerCollect(player)
end)

ArtifactDepositedEvent.Event:Connect(function(player, itemName)
	registerCollect(player)
end)

QuotaSetEvent.Event:Connect(function(quota)
	state.quota = math.max(1, tonumber(quota) or 1)
	resetRound(true)
end)

ResetScoreEvent.Event:Connect(function(activate)
	resetRound(activate)
end)

Players.PlayerAdded:Connect(function(player)
	task.defer(function()
		if player.Parent then
			UpdateScoreHudRE:FireClient(player, {
				artifacts = state.artifacts,
				multi = state.multi,
				teamScore = state.teamScore,
				quota = state.quota,
				active = state.active,
				momentumTimeout = MOMENTUM_TIMEOUT,
				lastCollectTime = state.lastCollectTime,
			})
		end
	end)
end)

print("[ScoreSystem] Ready")
