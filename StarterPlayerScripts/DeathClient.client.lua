-- DeathClient.client.lua
-- StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local PlayerDied = ReplicatedStorage:WaitForChild("PlayerDied")
local TakeDamage = ReplicatedStorage:WaitForChild("TakeDamage")

local function setupDebugKillButton()
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("DeathDebugGui")
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathDebugGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = pg

	local button = Instance.new("TextButton")
	button.Name = "KillMeButton"
	button.Size = UDim2.fromOffset(140, 42)
	button.Position = UDim2.new(1, -160, 0, 20)
	button.BackgroundColor3 = Color3.fromRGB(155, 35, 35)
	button.BorderSizePixel = 0
	button.Text = "Test Death"
	button.TextColor3 = Color3.new(1, 1, 1)
	button.TextScaled = true
	button.Font = Enum.Font.GothamBold
	button.Parent = gui

	button.MouseButton1Click:Connect(function()
		if player:GetAttribute("IsDead") then return end
		TakeDamage:FireServer(player, 999, "DebugKillButton")
	end)
end

local function makeDeathGui()
	local pg = player:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild("DeathGui")
	if old then old:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathGui"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Parent = pg

	local fade = Instance.new("Frame")
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundColor3 = Color3.new(0, 0, 0)
	fade.BackgroundTransparency = 1
	fade.Parent = gui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 0.2)
	label.Position = UDim2.fromScale(0, 0.4)
	label.BackgroundTransparency = 1
	label.Text = "YOU DIED"
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(220, 40, 40)
	label.TextStrokeTransparency = 0.4
	label.Font = Enum.Font.GothamBlack
	label.TextTransparency = 1
	label.Parent = gui

	return gui, fade, label
end

local function playDeathCinematic(payload)
	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.AutoRotate = false
			hum.WalkSpeed = 0
			hum.JumpPower = 0
		end
	end

	if camera then
		camera.CameraType = Enum.CameraType.Scriptable
		local basePos = camera.CFrame.Position
		local look = camera.CFrame.LookVector
		local target = CFrame.new(basePos - look * 8 + Vector3.new(0, 4, 0), basePos)
		TweenService:Create(camera, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { CFrame = target }):Play()
	end

	local gui, fade, label = makeDeathGui()
	TweenService:Create(fade, TweenInfo.new(1.2), { BackgroundTransparency = 0.1 }):Play()
	TweenService:Create(label, TweenInfo.new(1.0), { TextTransparency = 0 }):Play()

	task.delay(2.5, function()
		player:SetAttribute("Spectating", true)
	end)

	-- optional payload debug
	if payload and payload.source then
		print(string.format("[DeathClient] Died to %s", tostring(payload.source)))
	end
end

PlayerDied.OnClientEvent:Connect(function(payload)
	playDeathCinematic(payload)
end)

setupDebugKillButton()
