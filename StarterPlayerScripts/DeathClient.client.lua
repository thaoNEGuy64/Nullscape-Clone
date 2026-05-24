-- DeathClient.client.lua
-- StarterPlayerScripts

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local PlayerDied = ReplicatedStorage:WaitForChild("PlayerDied")
local TakeDamage = ReplicatedStorage:WaitForChild("TakeDamage")
local RequestRespawn = ReplicatedStorage:WaitForChild("RequestRespawn")
local StateChanged = ReplicatedStorage:FindFirstChild("StateChanged")

local mainState = "InGame"
if StateChanged and StateChanged:IsA("RemoteEvent") then
	StateChanged.OnClientEvent:Connect(function(newState)
		if type(newState) == "string" then
			mainState = newState
		end
	end)
end

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
	label.Size = UDim2.fromOffset(500, 80)
	label.AnchorPoint = Vector2.new(0, 1)
	label.Position = UDim2.new(0, 22, 1, -20)
	label.BackgroundTransparency = 1
	label.Text = "You died."
	label.TextScaled = false
	label.TextSize = 44
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Bottom
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Font = Enum.Font.Garamond
	label.TextTransparency = 1
	label.Parent = gui

	return gui, fade, label
end

local function fadeOutGameplayGui()
	local pg = player:WaitForChild("PlayerGui")
	for _, obj in ipairs(pg:GetDescendants()) do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			TweenService:Create(obj, TweenInfo.new(0.35), {
				TextTransparency = 1,
				BackgroundTransparency = math.clamp(obj.BackgroundTransparency + 0.35, 0, 1),
			}):Play()
		elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
			TweenService:Create(obj, TweenInfo.new(0.35), {
				ImageTransparency = 1,
				BackgroundTransparency = math.clamp(obj.BackgroundTransparency + 0.35, 0, 1),
			}):Play()
		elseif obj:IsA("Frame") then
			TweenService:Create(obj, TweenInfo.new(0.35), {
				BackgroundTransparency = math.clamp(obj.BackgroundTransparency + 0.35, 0, 1),
			}):Play()
		end
	end
end

local function setGameplayScreenGuisEnabled(enabled)
	local pg = player:WaitForChild("PlayerGui")
	for _, child in ipairs(pg:GetChildren()) do
		if child:IsA("ScreenGui") and child.Name ~= "DeathGui" and child.Name ~= "DeathDebugGui" then
			child.Enabled = enabled
		end
	end
end

local function freezeCurrentPose(char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		pcall(function()
			track:AdjustSpeed(0)
		end)
	end
end

local function hideLocalBody(char)
	for _, obj in ipairs(char:GetDescendants()) do
		if obj:IsA("BasePart") then
			obj.LocalTransparencyModifier = 1
		elseif obj:IsA("Accessory") then
			local handle = obj:FindFirstChild("Handle")
			if handle then
				handle.LocalTransparencyModifier = 1
			end
		end
	end
end

local function playExplosionOverlayPlaceholder()
	-- TODO: hook real explosion frame sequence here when art is ready.
	-- Keep this function call in place so the cinematic timing path is already wired.
end

local function shakeAndPullCamera(duration)
	local char = player.Character
	local head = char and char:FindFirstChild("Head")
	if not camera or not head then return end

	camera.CameraType = Enum.CameraType.Scriptable
	local t = 0
	local lookYaw = 0
	local lookPitch = 0
	while t < duration do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		local delta = UserInputService:GetMouseDelta()
		lookYaw = lookYaw - delta.X * 0.12
		lookPitch = math.clamp(lookPitch - delta.Y * 0.08, -30, 30)
		local alpha = math.clamp(t / duration, 0, 1)
		local back = 1 + alpha * 12
		local up = 0.75 + alpha * 3
		local shake = Vector3.new(
			math.sin(t * 5.2) * 0.08,
			math.cos(t * 4.7) * 0.07,
			math.sin(t * 6.3) * 0.05
		)
		local focus = head.Position
		local orbitCF = CFrame.new(focus) * CFrame.Angles(math.rad(lookPitch), math.rad(lookYaw), 0)
		local camPos = focus + (orbitCF.LookVector * -back) + Vector3.new(0, up, 0) + shake
		camera.CFrame = CFrame.new(camPos, focus)
	end
end

local function isIntermissionState()
	return mainState == "Start" or mainState == "Voting"
end

local function playDeathCinematic(payload)
	player:SetAttribute("DisableFirstPersonCamera", true)

	local char = player.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.AutoRotate = false
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.JumpHeight = 0
		end
		freezeCurrentPose(char)
		hideLocalBody(char)
	end

	fadeOutGameplayGui()
	local gui, fade, label = makeDeathGui()
	setGameplayScreenGuisEnabled(false)

	if isIntermissionState() then
		TweenService:Create(fade, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()
		task.wait(0.3)
		RequestRespawn:FireServer()
		return
	end

	-- Full cinematic pacing:
	-- 5s camera pull/shake, explode, black fade, "You died." for 4s, then fade out to spectate.
	local hideConn
	hideConn = RunService.RenderStepped:Connect(function()
		setGameplayScreenGuisEnabled(false)
		if char then
			hideLocalBody(char)
		end
	end)

	shakeAndPullCamera(5.0)
	playExplosionOverlayPlaceholder()

	TweenService:Create(fade, TweenInfo.new(0.8), { BackgroundTransparency = 0 }):Play()
	task.wait(0.7)
	TweenService:Create(label, TweenInfo.new(0.9), { TextTransparency = 0 }):Play()
	task.wait(4.0)

	if hideConn then hideConn:Disconnect() end
	-- Intentionally stop here for now so post-death menu flow can be added later.

	if payload and payload.source then
		print(string.format("[DeathClient] Died to %s", tostring(payload.source)))
	end
end

PlayerDied.OnClientEvent:Connect(function(payload)
	playDeathCinematic(payload)
end)

player.CharacterAdded:Connect(function()
	player:SetAttribute("DisableFirstPersonCamera", false)
	setGameplayScreenGuisEnabled(true)
end)

setupDebugKillButton()
