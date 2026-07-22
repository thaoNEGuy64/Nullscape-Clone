-- Spear weapon module: click to force-throw, then return to inventory.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local WEAPON_ID = "Spear"
local GUI_NAME = "SpearWeaponGuiLocal"

local returnConnection = nil
local lastRestore = nil
local consumedSlot = nil
local throwing = false
local guiAnimConn = nil
local guiBasePosition = nil

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
	guiBasePosition = nil
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
	guiBasePosition = image.Position
	local t = 0
	guiAnimConn = RunService.RenderStepped:Connect(function(dt)
		if not image.Parent then stopGuiAnim(); return end
		t += dt
		local x = math.sin(t * 3.6) * 8
		local y = math.sin(t * 7.2) * 5
		image.Position = UDim2.new(
			guiBasePosition.X.Scale, guiBasePosition.X.Offset + x,
			guiBasePosition.Y.Scale, guiBasePosition.Y.Offset + y
		)
	end)
end

local function ensureReturnListener(remote)
	if returnConnection then return end
	returnConnection = remote.OnClientEvent:Connect(function(action)
		if action ~= "Returned" then return end
		throwing = false
		if lastRestore then
			lastRestore(WEAPON_ID, consumedSlot)
		end
		consumedSlot = nil
	end)
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
		clearGui(ctx.player or Players.LocalPlayer)
	end,

	onPrimaryDown = function(ctx)
		if throwing then return end
		local remote = getActionRemote()
		if not remote then
			warn("[SPEAR] Missing ReplicatedStorage/Weapon Remotes/Spear/SpearAction")
			return
		end
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
		remote:FireServer("Throw", look)
	end,
}
