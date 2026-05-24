local players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local module = require(ReplicatedStorage:WaitForChild("2DPlayer"))

local LocalPlayer = players.LocalPlayer
local instances = {}

local function set2DTransparency(instance, alpha)
	-- best-effort compatibility with unknown 2DPlayer implementation
	pcall(function()
		if instance.SetTransparency then
			instance:SetTransparency(alpha)
		end
	end)
	pcall(function()
		if instance.Billboard and instance.Billboard:IsA("BillboardGui") then
			for _, d in ipairs(instance.Billboard:GetDescendants()) do
				if d:IsA("ImageLabel") or d:IsA("ImageButton") then
					d.ImageTransparency = alpha
				elseif d:IsA("TextLabel") or d:IsA("TextButton") then
					d.TextTransparency = alpha
				end
			end
		end
	end)
end

local function addForPlayer(player: Player)
	if instances[player] then return end
	local character = player.Character or player.CharacterAppearanceLoaded:Wait()
	local new2D = module.new(character, 10)
	instances[player] = {
		inst = new2D,
		fadeAlpha = (player == LocalPlayer) and 1 or 0,
	}

	if player == LocalPlayer then
		set2DTransparency(new2D, 1)
	end

	character.Destroying:Once(function()
		local entry = instances[player]
		if entry then
			instances[player] = nil
			entry.inst:Destroy()
		end
	end)
end

local function removeForPlayer(player: Player)
	local entry = instances[player]
	if not entry then return end
	instances[player] = nil
	entry.inst:Destroy()
end

local function shouldShowLocal2D()
	return LocalPlayer:GetAttribute("IsDead") == true or LocalPlayer:GetAttribute("DisableFirstPersonCamera") == true
end

players.PlayerAdded:Connect(function(player)
	if player ~= LocalPlayer then
		addForPlayer(player)
	end
end)

players.PlayerRemoving:Connect(function(player)
	removeForPlayer(player)
end)

LocalPlayer:GetAttributeChangedSignal("IsDead"):Connect(function()
	if shouldShowLocal2D() then
		addForPlayer(LocalPlayer)
	else
		removeForPlayer(LocalPlayer)
	end
end)

LocalPlayer:GetAttributeChangedSignal("DisableFirstPersonCamera"):Connect(function()
	if shouldShowLocal2D() then
		addForPlayer(LocalPlayer)
	else
		removeForPlayer(LocalPlayer)
	end
end)

RunService.RenderStepped:Connect(function(dT)
	for player, entry in pairs(instances) do
		local freezeLocalFrame = false
		if player == LocalPlayer then
			if shouldShowLocal2D() then
				entry.fadeAlpha = math.max(0, entry.fadeAlpha - dT * 0.9)
				set2DTransparency(entry.inst, entry.fadeAlpha)
				freezeLocalFrame = entry.fadeAlpha <= 0.02
			else
				entry.fadeAlpha = 1
			end
		end
		if not freezeLocalFrame then
			entry.inst:Update(dT)
		end
	end
end)

for _, v in pairs(players:GetPlayers()) do
	if v ~= LocalPlayer then
		addForPlayer(v)
	end
end
