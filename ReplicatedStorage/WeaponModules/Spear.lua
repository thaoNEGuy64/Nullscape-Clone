-- Spear weapon module: hold M1 to charge, release to force-throw, then return to inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WEAPON_ID = "Spear"
local GUI_NAME = "SpearWeaponGuiLocal"
local MAX_CHARGE_TIME = 1.25
local MAX_SHAKE_PX = 14
local BASE_SHAKE_SPEED = 10
local MAX_SHAKE_SPEED = 34

local returnConnection = nil
local lastRestore = nil
local consumedSlot = nil
local throwing = false
local charging = false
local chargeStart = 0
local guiAnimConn = nil
local guiBasePosition = nil
local guiBaseRotation = 0
local guiImage = nil

local function findPath(root, path)
	local current = root
	for _, name in ipairs(path) do
		current = current and current:WaitForChild(name, 10)
		if not current then return nil end
	end
	return current
end

local function getActionRemote()
	return findPath(ReplicatedStorage, {"Weapon Remotes", "Spear", "SpearAction"})
end

local function stopGuiAnim()
	if guiAnimConn then
		guiAnimConn:Disconnect()
		guiAnimConn = nil
	end
	if guiImage and guiImage.Parent and guiBasePosition then
		guiImage.Position = guiBasePosition
		guiImage.Rotation = guiBaseRotation
	end
	guiBasePosition = nil
	guiBaseRotation = 0
	guiImage = nil
end

local function clearGui(player)
	stopGuiAnim()
	local pg = player and player:FindFirstChild("PlayerGui")
	local old = pg and pg:FindFirstChild(GUI_NAME)
	if old then old:Destroy() end
end

local function startGuiAnim(gui)
	stopGuiAnim()
	local image = gui:FindFirstChildWhichIsA("ImageLabel", true)
	if not image then return end
	guiImage = image
	guiBasePosition = image.Position
	guiBaseRotation = image.Rotation
	local t = 0
	guiAnimConn = RunService.RenderStepped:Connect(function(dt)
		if not image.Parent then stopGuiAnim(); return end
		t += dt
		local chargeAlpha = 0
		if charging then
			chargeAlpha = math.clamp((os.clock() - chargeStart) / MAX_CHARGE_TIME, 0, 1)
		end
		local idleX = math.sin(t * 3.6) * 8
		local idleY = math.sin(t * 7.2) * 5
		local shakeSpeed = BASE_SHAKE_SPEED + (MAX_SHAKE_SPEED - BASE_SHAKE_SPEED) * chargeAlpha
		local shakeAmp = MAX_SHAKE_PX * chargeAlpha
		local shakeX = math.sin(t * shakeSpeed) * shakeAmp
		local shakeY = math.cos(t * shakeSpeed * 1.37) * shakeAmp * 0.65
		image.Position = UDim2.new(
			guiBasePosition.X.Scale, guiBasePosition.X.Offset + idleX + shakeX,
			guiBasePosition.Y.Scale, guiBasePosition.Y.Offset + idleY + shakeY
		)
		image.Rotation = guiBaseRotation + (charging and -90 or 0) + math.sin(t * shakeSpeed * 0.8) * chargeAlpha * 7
	end)
end

local function applyClientImpulse(impulse)
	local player = Players.LocalPlayer
	local char = player and player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and typeof(impulse) == "Vector3" then
		hrp.AssemblyLinearVelocity += impulse
	end
end

local function ensureReturnListener(remote)
	if returnConnection then return end
	returnConnection = remote.OnClientEvent:Connect(function(action, payload)
		if action == "Returned" then
			throwing = false
			if lastRestore then
				lastRestore(WEAPON_ID, consumedSlot)
			end
			consumedSlot = nil
		elseif action == "Impulse" then
			applyClientImpulse(payload)
		end
	end)
end

local function releaseThrow(ctx)
	if throwing then return end
	local remote = getActionRemote()
	if not remote then
		warn("[SPEAR] Missing ReplicatedStorage/Weapon Remotes/Spear/SpearAction")
		charging = false
		return
	end
	local chargeAlpha = charging and math.clamp((os.clock() - chargeStart) / MAX_CHARGE_TIME, 0, 1) or 0
	charging = false
	local consumedWeapon, slot = nil, nil
	if ctx.consumeActiveWeapon then
		consumedWeapon, slot = ctx.consumeActiveWeapon()
	end
	if not consumedWeapon then return end
	throwing = true
	consumedSlot = slot
	lastRestore = ctx.restoreWeapon
	ensureReturnListener(remote)
	local camera = workspace.CurrentCamera
	local look = camera and camera.CFrame.LookVector or (ctx.rootPart and ctx.rootPart.CFrame.LookVector) or Vector3.new(0, 0, -1)
	remote:FireServer("Throw", look, chargeAlpha)
end

return {
	id = WEAPON_ID,
	displayName = "Spear",
	pickupModelName = "Spear",

	onEquip = function(ctx)
		local player = ctx.player or Players.LocalPlayer
		clearGui(player)
		local template = findPath(ReplicatedStorage, {"Assets", "Weapons", "Spear", "SpearGui"})
		local pg = player and player:FindFirstChild("PlayerGui")
		if template and template:IsA("ScreenGui") and pg then
			local gui = template:Clone()
			gui.Name = GUI_NAME
			gui.ResetOnSpawn = false
			gui.Parent = pg
			startGuiAnim(gui)
		end
	end,

	onUnequip = function(ctx)
		charging = false
		clearGui(ctx.player or Players.LocalPlayer)
	end,

	onPrimaryDown = function(ctx)
		if throwing or charging then return end
		charging = true
		chargeStart = os.clock()
	end,

	onPrimaryUp = function(ctx)
		releaseThrow(ctx)
	end,
}
