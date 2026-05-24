-- ArenaClient.client.lua
-- StarterPlayerScripts
-- Creates local-only arena door blockers so the triggered player is trapped
-- without blocking other players from entering to help.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ArenaDoorState = ReplicatedStorage:WaitForChild("ArenaDoorState")
local blockersByArena = {}

local function getFolder(arenaId)
	local folder = blockersByArena[arenaId]
	if folder and folder.Parent then return folder end
	folder = Instance.new("Folder")
	folder.Name = "LocalArenaDoorBlockers_" .. tostring(arenaId)
	folder.Parent = Workspace
	blockersByArena[arenaId] = folder
	return folder
end

local function unlock(arenaId)
	local folder = blockersByArena[arenaId]
	if folder then
		folder:Destroy()
		blockersByArena[arenaId] = nil
	end
end

local function lock(arenaId, doors)
	unlock(arenaId)
	local folder = getFolder(arenaId)
	for _, door in ipairs(doors or {}) do
		local wall = Instance.new("Part")
		wall.Name = "LocalArenaSeal"
		wall.Anchored = true
		wall.CanCollide = true
		wall.CanTouch = false
		wall.CanQuery = false
		wall.Transparency = 0.35
		wall.Material = Enum.Material.SmoothPlastic
		wall.Color = Color3.fromRGB(25, 25, 25)
		wall.Size = door.Size
		wall.CFrame = door.CFrame
		wall.Parent = folder
	end
end

ArenaDoorState.OnClientEvent:Connect(function(action, arenaId, doors)
	if action == "Lock" then
		lock(tostring(arenaId), doors)
	elseif action == "Unlock" then
		unlock(tostring(arenaId))
	end
end)

print("[ArenaClient] Loaded")
