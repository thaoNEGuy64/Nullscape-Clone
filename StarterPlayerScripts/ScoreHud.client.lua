-- ScoreHud.client.lua
-- StarterPlayerScripts

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local scoreGui = playerGui:WaitForChild("Score")

local artifactsLabel = scoreGui:WaitForChild("Artifacts")
local multiLabel = scoreGui:WaitForChild("Multi")
local teamScoreLabel = scoreGui:WaitForChild("Team Score")
local quotaLabel = scoreGui:WaitForChild("Quota")

local UpdateScoreHudRE = ReplicatedStorage:WaitForChild("UpdateScoreHud")
local StateChangedRE = ReplicatedStorage:WaitForChild("StateChanged")
local SubstateChangedRE = ReplicatedStorage:WaitForChild("SubstateChanged")

local labels = { artifactsLabel, multiLabel, teamScoreLabel, quotaLabel }
local basePos = {}
for _, label in ipairs(labels) do
	basePos[label] = label.Position
end

local shown = false
local mainState = "Start"
local substate = "WaitingForStart"

local function setVisible(visible)
	scoreGui.Enabled = true
	for _, label in ipairs(labels) do
		label.Visible = visible
	end
end

local function hideTopInstant()
	for _, label in ipairs(labels) do
		local p = basePos[label]
		label.Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale - 0.2, p.Y.Offset - 30)
	end
end

local function animateShow()
	if shown then return end
	shown = true
	setVisible(true)
	hideTopInstant()
	for i, label in ipairs(labels) do
		local p = basePos[label]
		task.delay((i - 1) * 0.06, function()
			if not shown then return end
			TweenService:Create(label, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				Position = p,
			}):Play()
		end)
	end
end

local function animateHide()
	if not shown then return end
	shown = false
	for _, label in ipairs(labels) do
		local p = basePos[label]
		TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(p.X.Scale, p.X.Offset, p.Y.Scale - 0.2, p.Y.Offset - 30),
		}):Play()
	end
	task.delay(0.27, function()
		if shown then return end
		setVisible(false)
	end)
end

local function shouldShowHud(payloadActive)
	if payloadActive == true then return true end
	if mainState == "InGame" and substate ~= "Generating" then
		return true
	end
	return false
end

UpdateScoreHudRE.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then return end
	artifactsLabel.Text = string.format("Artifacts: %d", math.floor(payload.artifacts or 0))
	multiLabel.Text = string.format("Multi: x%.2f", tonumber(payload.multi or 1))
	teamScoreLabel.Text = string.format("Team Score: %d", math.floor(payload.teamScore or 0))
	quotaLabel.Text = string.format("Quota: %d", math.floor(payload.quota or 0))

	if shouldShowHud(payload.active) then animateShow() else animateHide() end
end)

StateChangedRE.OnClientEvent:Connect(function(newMain)
	mainState = tostring(newMain)
	if shouldShowHud(false) then animateShow() else animateHide() end
end)

SubstateChangedRE.OnClientEvent:Connect(function(newSub)
	substate = tostring(newSub)
	if shouldShowHud(false) then animateShow() else animateHide() end
end)

RunService.RenderStepped:Connect(function()
	if not shown then return end
	local t = os.clock()
	for i, label in ipairs(labels) do
		local p = basePos[label]
		local ox = math.sin(t * 1.1 + i * 0.9) * 2
		local oy = math.cos(t * 0.9 + i * 1.3) * 1.5
		label.Position = UDim2.new(p.X.Scale, p.X.Offset + ox, p.Y.Scale, p.Y.Offset + oy)
	end
end)

setVisible(false)
print("[ScoreHud] Ready")
