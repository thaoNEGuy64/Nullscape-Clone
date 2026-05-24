-- FirstPersonIfHeWasCool.client.lua
-- LocalScript for StarterPlayerScripts

local AngleX, TargetAngleX = 0, 0
local AngleY, TargetAngleY = 0, 0

local function normalizeDegrees(v)
	v = v % 360
	if v < 0 then v += 360 end
	return v
end

_G.SetFirstPersonYaw = function(yawDeg)
	yawDeg = normalizeDegrees(yawDeg)
	AngleY = yawDeg
	TargetAngleY = yawDeg
end

_G.SetFirstPersonPitch = function(pitchDeg)
	AngleX = pitchDeg
	TargetAngleX = pitchDeg
end

_G.GetFirstPersonYaw = function()
	return AngleY, TargetAngleY
end

_G.RotateFirstPersonYaw = function(deltaDeg)
	deltaDeg = deltaDeg or 0
	AngleY = normalizeDegrees(AngleY + deltaDeg)
	TargetAngleY = normalizeDegrees(TargetAngleY + deltaDeg)
end

repeat task.wait() until game:GetService("Players").LocalPlayer.Character ~= nil

local runService = game:GetService("RunService")
local input = game:GetService("UserInputService")
local players = game:GetService("Players")

CanToggleMouse = {allowed = true; activationkey = Enum.KeyCode.N;}
CanViewBody = false
Sensitivity = 0.2
Smoothness = 0.05
FieldOfView = 95

local MaxTiltDegrees = 1.25
local JumpBobAmount = 0.1
local LandBobAmount = -2.5
local BobReturnSpeed = 3
local BobDamping = 35
local JumpTriggerY = 2.0
local LandTriggerY = -8.0
local WalkBobX = 1
local WalkBobY = 1
local WalkBobSpeed = 1.5
local WalkBobEaseSpeed = 7 -- smooth in/out for movement bob
local KickKey = Enum.KeyCode.Q
local KickFovPunch = 2
local KickTiltPunch = 2
local KickPunchDecay = 14

local cam = workspace.CurrentCamera
local player = players.LocalPlayer
local m = player:GetMouse()
m.Icon = "http://www.roblox.com/asset/?id=569021388"

local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local humanoidpart = character:WaitForChild("HumanoidRootPart")
local head = character:WaitForChild("Head")

local CamPos, TargetCamPos = cam.CFrame.Position, cam.CFrame.Position

local freemouse = false
local currentTilt = 0
local bobOffset = 0
local bobVelocity = 0
local wasGrounded = true
local jumpBobArmed = true
local previousYVel = 0
local walkT = 0
local kickFovOffset = 0
local kickTiltOffset = 0
local walkAlphaSmoothed = 0

local function applyExternalYawIfAny()
	local attrYaw = player:GetAttribute("FP_AngleY")
	local attrTarget = player:GetAttribute("FP_TargetAngleY")
	if typeof(attrYaw) == "number" then
		AngleY = normalizeDegrees(attrYaw)
		player:SetAttribute("FP_AngleY", nil)
	end
	if typeof(attrTarget) == "number" then
		TargetAngleY = normalizeDegrees(attrTarget)
		player:SetAttribute("FP_TargetAngleY", nil)
	end
end

local function updatechar()
	for _, v in pairs(character:GetDescendants()) do
		if v:IsA("BasePart") then
			if CanViewBody then
				if v.Name == "Head" then
					v.LocalTransparencyModifier = 1
				else
					v.LocalTransparencyModifier = 0
				end
			else
				v.LocalTransparencyModifier = 1
			end
		end
		if v:IsA("Accessory") then
			local handle = v:FindFirstChild("Handle")
			if handle then
				handle.LocalTransparencyModifier = 1
			end
		end
	end
end

input.InputChanged:Connect(function(inputObject)
	if inputObject.UserInputType == Enum.UserInputType.MouseMovement then
		local delta = Vector2.new(
			inputObject.Delta.x / Sensitivity,
			inputObject.Delta.y / Sensitivity
		) * Smoothness

		local X = TargetAngleX - delta.y
		TargetAngleX = math.clamp(X, -80, 80)
		TargetAngleY = (TargetAngleY - delta.x) % 360
	end
end)

input.InputBegan:Connect(function(inputObject, processed)
	if processed then return end
	if inputObject.UserInputType == Enum.UserInputType.Keyboard then
		if inputObject.KeyCode == CanToggleMouse.activationkey then
			if CanToggleMouse.allowed then
				freemouse = not freemouse
			end
		elseif inputObject.KeyCode == KickKey then
			kickFovOffset = KickFovPunch
			kickTiltOffset = math.rad(KickTiltPunch)
		end
	end
end)

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = character:WaitForChild("Humanoid")
	humanoidpart = character:WaitForChild("HumanoidRootPart")
	head = character:WaitForChild("Head")
end)

runService.RenderStepped:Connect(function(dt)
	if player:GetAttribute("DisableFirstPersonCamera") then
		input.MouseBehavior = Enum.MouseBehavior.Default
		return
	end

	updatechar()
	applyExternalYawIfAny()

	CamPos = CamPos + (TargetCamPos - CamPos) * 0.28
	AngleX = AngleX + (TargetAngleX - AngleX) * 0.35

	local dist = TargetAngleY - AngleY
	dist = math.abs(dist) > 180 and dist - (dist / math.abs(dist)) * 360 or dist
	AngleY = (AngleY + dist * 0.35) % 360

	local strafeAxis = 0
	if input:IsKeyDown(Enum.KeyCode.A) then strafeAxis -= 1 end
	if input:IsKeyDown(Enum.KeyCode.D) then strafeAxis += 1 end
	currentTilt = math.rad(-MaxTiltDegrees * strafeAxis)
	kickFovOffset = kickFovOffset * math.exp(-KickPunchDecay * dt)
	kickTiltOffset = kickTiltOffset * math.exp(-KickPunchDecay * dt)
	currentTilt += kickTiltOffset

	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local yVel = humanoidpart.AssemblyLinearVelocity.Y
	local planar = Vector3.new(humanoidpart.AssemblyLinearVelocity.X, 0, humanoidpart.AssemblyLinearVelocity.Z)
	local speed = planar.Magnitude

	if grounded then
		jumpBobArmed = true
		if (not wasGrounded) and previousYVel <= LandTriggerY then
			bobVelocity += LandBobAmount
		end
	else
		if jumpBobArmed and yVel >= JumpTriggerY then
			bobVelocity += JumpBobAmount
			jumpBobArmed = false
		end
	end

	wasGrounded = grounded
	previousYVel = yVel

	bobVelocity += (-bobOffset * BobReturnSpeed) * dt
	bobVelocity *= math.exp(-BobDamping * dt)
	bobOffset += bobVelocity

	local moveAlpha = math.clamp(speed / 55, 0, 1)
	walkAlphaSmoothed = walkAlphaSmoothed + (moveAlpha - walkAlphaSmoothed) * math.clamp(WalkBobEaseSpeed * dt, 0, 1)
	walkT += dt * WalkBobSpeed * (0.35 + walkAlphaSmoothed)
	local walkX = math.sin(walkT) * WalkBobX * walkAlphaSmoothed
	local walkY = math.abs(math.sin(walkT * 2)) * WalkBobY * walkAlphaSmoothed

	cam.CameraType = Enum.CameraType.Scriptable
	cam.CFrame =
		CFrame.new(head.Position)
		* CFrame.Angles(0, math.rad(AngleY), 0)
		* CFrame.Angles(math.rad(AngleX), 0, 0)
		* CFrame.Angles(0, 0, currentTilt)
		* CFrame.new(walkX, 0.8 + bobOffset + walkY, 0)

	humanoidpart.CFrame =
		CFrame.new(humanoidpart.Position)
		* CFrame.Angles(0, math.rad(AngleY), 0)

	humanoid.AutoRotate = false

	if freemouse then
		input.MouseBehavior = Enum.MouseBehavior.Default
	else
		input.MouseBehavior = Enum.MouseBehavior.LockCenter
	end

	cam.FieldOfView = FieldOfView + kickFovOffset
end)
