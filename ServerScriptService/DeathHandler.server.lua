-- DeathHandler.server.lua
-- ServerScriptService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MAX_HEALTH = 100

local function getOrCreate(className, name)
	local obj = ReplicatedStorage:FindFirstChild(name)
	if obj then return obj end
	obj = Instance.new(className)
	obj.Name = name
	obj.Parent = ReplicatedStorage
	return obj
end

local TakeDamageRemote = getOrCreate("RemoteEvent", "TakeDamage")
local TakeDamageServer = getOrCreate("BindableEvent", "TakeDamageServer") -- server->server damage channel
local PlayerDiedRemote = getOrCreate("RemoteEvent", "PlayerDied")
local ResetPlayerHealth = getOrCreate("BindableEvent", "ResetPlayerHealth")

local PlayerEscapedServer = ReplicatedStorage:FindFirstChild("PlayerEscapedServer")
if not PlayerEscapedServer then
	PlayerEscapedServer = Instance.new("BindableEvent")
	PlayerEscapedServer.Name = "PlayerEscapedServer"
	PlayerEscapedServer.Parent = ReplicatedStorage
end

local function setHealthState(player, hp)
	player:SetAttribute("Health", hp)
	player:SetAttribute("IsDead", hp <= 0)
end

local function teleportPlayerToVote(player)
	local votePart = Workspace:FindFirstChild("Vote")
	if not votePart or not votePart:IsA("BasePart") then return end
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = votePart.CFrame + Vector3.new(0, 5, 0)
end

local function applyDamage(player, amount, source)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	if type(amount) ~= "number" then return end
	if amount <= 0 then return end

	local current = player:GetAttribute("Health")
	if type(current) ~= "number" then current = MAX_HEALTH end
	if current <= 0 then return end

	local nextHealth = math.max(0, current - amount)
	setHealthState(player, nextHealth)

	if nextHealth <= 0 then
		player:SetAttribute("Spectating", true)
		PlayerDiedRemote:FireClient(player, {
			source = source or "Unknown",
			finalHealth = nextHealth,
			timestamp = os.clock(),
		})

		if PlayerEscapedServer:IsA("BindableEvent") then
			PlayerEscapedServer:Fire(player)
		end
	end
end

-- Server systems (enemy AI, hazards) should use this bindable.
TakeDamageServer.Event:Connect(function(player, amount, source)
	applyDamage(player, amount, source)
end)

-- Optional client requests (guarded): currently only accepts self-damage for test tooling.
TakeDamageRemote.OnServerEvent:Connect(function(sender, targetPlayer, amount, source)
	if targetPlayer ~= sender then
		warn("[DeathHandler] Rejected TakeDamage remote: target mismatch")
		return
	end
	applyDamage(targetPlayer, amount, source)
end)

Players.PlayerAdded:Connect(function(player)
	setHealthState(player, MAX_HEALTH)
	player:SetAttribute("Spectating", false)

	player.CharacterAdded:Connect(function()
		if player:GetAttribute("IsDead") then
			-- Keep dead state until intermission reset.
			return
		end
		setHealthState(player, MAX_HEALTH)
		player:SetAttribute("Spectating", false)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	-- no-op placeholder for persistence hooks
end)

ResetPlayerHealth.Event:Connect(function(optionalPlayer)
	if optionalPlayer and optionalPlayer:IsA("Player") then
		setHealthState(optionalPlayer, MAX_HEALTH)
		optionalPlayer:SetAttribute("Spectating", false)
		teleportPlayerToVote(optionalPlayer)
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		setHealthState(player, MAX_HEALTH)
		player:SetAttribute("Spectating", false)
		teleportPlayerToVote(player)
	end
end)

print("[DeathHandler] Ready. Health system + death flow active.")
