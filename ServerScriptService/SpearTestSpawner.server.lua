-- SpearTestSpawner.server.lua
-- Dev/test helper: keeps one Spear pickup spawned at Workspace.PlaceSpearHere.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MARKER_NAME = "PlaceSpearHere"
local WEAPON_ID = "Spear"
local RESPAWN_DELAY = 1.0
local SPAWNED_NAME = "Spear_TestPickup"
local TRIGGER_SIZE = Vector3.new(5, 5, 5)

local spawnedPickup = nil
local respawnQueued = false

local function getSpearTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local weapons = assets and assets:FindFirstChild("Weapons")
	local spearFolder = weapons and weapons:FindFirstChild("Spear")
	local spear = spearFolder and spearFolder:FindFirstChild("Spear")
	if spear and spear:IsA("BasePart") then return spear end
	return nil
end

local function getMarker()
	local marker = Workspace:FindFirstChild(MARKER_NAME, true)
	if marker and marker:IsA("BasePart") then return marker end
	return nil
end

local function preparePickup(pickup, marker)
	pickup.Name = SPAWNED_NAME
	pickup:SetAttribute("WeaponId", WEAPON_ID)
	pickup.Anchored = true
	pickup.CanCollide = true
	pickup.CanTouch = false
	pickup.CanQuery = true
	pickup.CFrame = marker.CFrame * CFrame.new(0, marker.Size.Y * 0.5 + pickup.Size.Y * 0.5 + 0.25, 0)

	local trigger = pickup:FindFirstChild("Trigger")
	if not (trigger and trigger:IsA("BasePart")) then
		trigger = Instance.new("Part")
		trigger.Name = "Trigger"
		trigger.Parent = pickup
	end
	trigger.Size = TRIGGER_SIZE
	trigger.CFrame = pickup.CFrame
	trigger.Transparency = 1
	trigger.Anchored = true
	trigger.CanCollide = false
	trigger.CanTouch = true
	trigger.CanQuery = false
	trigger:SetAttribute("WeaponId", WEAPON_ID)
end

local function spawnSpear()
	if spawnedPickup and spawnedPickup.Parent then return end
	local marker = getMarker()
	if not marker then
		warn("[SpearTestSpawner] Missing Workspace." .. MARKER_NAME .. " BasePart")
		return
	end
	local template = getSpearTemplate()
	if not template then
		warn("[SpearTestSpawner] Missing ReplicatedStorage/Assets/Weapons/Spear/Spear BasePart")
		return
	end

	local pickup = template:Clone()
	preparePickup(pickup, marker)
	pickup.Parent = Workspace
	spawnedPickup = pickup
	print("[SpearTestSpawner] Spawned Spear test pickup at " .. MARKER_NAME)

	pickup.AncestryChanged:Connect(function(_, parent)
		if parent ~= nil or respawnQueued then return end
		respawnQueued = true
		task.delay(RESPAWN_DELAY, function()
			respawnQueued = false
			spawnSpear()
		end)
	end)
end

local marker = getMarker()
if marker then
	spawnSpear()
else
	Workspace.DescendantAdded:Connect(function(child)
		if child.Name == MARKER_NAME and child:IsA("BasePart") then
			task.defer(spawnSpear)
		end
	end)
	warn("[SpearTestSpawner] Waiting for Workspace." .. MARKER_NAME)
end

print("[SpearTestSpawner] Ready")
