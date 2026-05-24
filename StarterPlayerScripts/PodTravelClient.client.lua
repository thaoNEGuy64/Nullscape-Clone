-- PodTravelClient.client.lua
-- StarterPlayerScripts
-- Small fade overlay used by DreamPodController during cart travel.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local PodFade = ReplicatedStorage:WaitForChild("PodFade")

local gui = Instance.new("ScreenGui")
gui.Name = "PodTravelFadeGui"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 10000
gui.Parent = player:WaitForChild("PlayerGui")

local blackout = Instance.new("Frame")
blackout.Name = "Blackout"
blackout.Size = UDim2.fromScale(1, 1)
blackout.Position = UDim2.fromScale(0, 0)
blackout.BackgroundColor3 = Color3.new(0, 0, 0)
blackout.BackgroundTransparency = 1
blackout.BorderSizePixel = 0
blackout.Parent = gui

local activeTween = nil

local function tweenTransparency(targetTransparency, duration)
	if activeTween then
		activeTween:Cancel()
		activeTween = nil
	end
	activeTween = TweenService:Create(
		blackout,
		TweenInfo.new(duration or 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ BackgroundTransparency = targetTransparency }
	)
	activeTween:Play()
end

PodFade.OnClientEvent:Connect(function(mode, duration)
	if mode == "In" then
		tweenTransparency(0, duration)
	elseif mode == "Out" then
		tweenTransparency(1, duration)
	elseif mode == "SetBlack" then
		if activeTween then activeTween:Cancel(); activeTween = nil end
		blackout.BackgroundTransparency = 0
	elseif mode == "Clear" then
		if activeTween then activeTween:Cancel(); activeTween = nil end
		blackout.BackgroundTransparency = 1
	end
end)
