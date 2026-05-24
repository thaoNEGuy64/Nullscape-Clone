-- ArenaController.server.lua
-- ServerScriptService
-- Finds generated arena rooms, locks local doors for participating players,
-- spawns arena Shades, and unlocks after all arena enemies die.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ShadeModule = require(ServerScriptService:WaitForChild("Enemies"):WaitForChild("ShadeModule"))

local ARENA_ENEMY_COUNT = 5
local SPAWN_INTERVAL = 0.5
local CHECK_INTERVAL = 0.2
local DOOR_PAD = Vector3.new(0.5, 0.5, 1.0)
local SPAWN_SPACING_RADIUS = 7

local ArenaDoorState = ReplicatedStorage:FindFirstChild("ArenaDoorState")
if not ArenaDoorState then
	ArenaDoorState = Instance.new("RemoteEvent")
	ArenaDoorState.Name = "ArenaDoorState"
	ArenaDoorState.Parent = ReplicatedStorage
end

local arenas = {}
local nextArenaId = 0
local scanAccumulator = 0

local function isDoorPart(part)
	return part and (part:IsA("UnionOperation") or part:IsA("BasePart"))
		and (part.Name == "White door frame arch" or part.Name == "White door frame arch (ZiplineSide)")
end

local function getDoorPayload(room)
	local payload = {}
	for _, inst in ipairs(room:GetDescendants()) do
		if isDoorPart(inst) then
			payload[#payload + 1] = {
				CFrame = inst.CFrame,
				Size = inst.Size + DOOR_PAD,
			}
		end
	end
	return payload
end

local function getSpawnPoints(room)
	local points = {}
	for _, inst in ipairs(room:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == "SpawnArena" then
			points[#points + 1] = inst
		end
	end
	table.sort(points, function(a, b) return a:GetFullName() < b:GetFullName() end)
	return points
end

local function pointInsideRoom(room, point)
	local cf, size = room:GetBoundingBox()
	local lp = cf:PointToObjectSpace(point)
	return math.abs(lp.X) <= size.X * 0.5
		and math.abs(lp.Y) <= size.Y * 0.5
		and math.abs(lp.Z) <= size.Z * 0.5
end

local function playerInRoom(player, room)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	return hrp and pointInsideRoom(room, hrp.Position)
end

local function unlockArena(arena)
	arena.cleared = true
	for player in pairs(arena.lockedPlayers) do
		ArenaDoorState:FireClient(player, "Unlock", arena.id)
	end
	arena.lockedPlayers = {}
	print(string.format("[Arena] Cleared %s", arena.room.Name))
end

local function lockPlayer(arena, player)
	if arena.cleared or arena.lockedPlayers[player] then return end
	arena.lockedPlayers[player] = true
	ArenaDoorState:FireClient(player, "Lock", arena.id, arena.doors)
end

local function startArena(arena, starter)
	if arena.started or arena.cleared then return end
	arena.started = true
	lockPlayer(arena, starter)
	print(string.format("[Arena] Started %s by %s", arena.room.Name, starter.Name))

	task.spawn(function()
		local spawnPoints = arena.spawnPoints
		if #spawnPoints == 0 then
			warn("[Arena] " .. arena.room.Name .. " has no SpawnArena parts")
			unlockArena(arena)
			return
		end

		for i = 1, ARENA_ENEMY_COUNT do
			if arena.cleared then return end
			local spawnPart = spawnPoints[((i - 1) % #spawnPoints) + 1]
			local angle = ((i - 1) / ARENA_ENEMY_COUNT) * math.pi * 2
			local offset = Vector3.new(math.cos(angle), 0, math.sin(angle)) * SPAWN_SPACING_RADIUS
			local spawnCF = spawnPart.CFrame + offset
			arena.aliveEnemies += 1
			ShadeModule.Spawn(spawnCF, {
				Parent = arena.enemyFolder,
				ArenaId = arena.id,
				Name = string.format("Shade_%s_%d", arena.id, i),
				EntranceFromBelow = true,
				EntranceOffset = 10,
				EntranceDuration = 0.75,
				EntranceJumpHeight = 4,
				OnDied = function()
					arena.aliveEnemies -= 1
					if arena.started and not arena.cleared and arena.aliveEnemies <= 0 and arena.spawnedAll then
						unlockArena(arena)
					end
				end,
			})
			task.wait(SPAWN_INTERVAL)
		end
		arena.spawnedAll = true
		if arena.aliveEnemies <= 0 then unlockArena(arena) end
	end)
end

local function registerArena(room)
	if arenas[room] then return end
	nextArenaId += 1
	local enemyFolder = Instance.new("Folder")
	enemyFolder.Name = "ArenaEnemies_" .. nextArenaId
	enemyFolder.Parent = Workspace
	arenas[room] = {
		id = tostring(nextArenaId),
		room = room,
		doors = getDoorPayload(room),
		spawnPoints = getSpawnPoints(room),
		enemyFolder = enemyFolder,
		lockedPlayers = {},
		started = false,
		cleared = false,
		aliveEnemies = 0,
		spawnedAll = false,
	}
	print(string.format("[Arena] Registered %s with %d spawn point(s)", room.Name, #arenas[room].spawnPoints))
end

local function scanArenas()
	local genFolder = Workspace:FindFirstChild("GeneratedRooms")
	if not genFolder then return end
	for _, room in ipairs(genFolder:GetChildren()) do
		if room:IsA("Model") and room:GetAttribute("IsArena") then
			registerArena(room)
		end
	end
end

local function cleanupMissingArenas()
	for room, arena in pairs(arenas) do
		if not room.Parent then
			for player in pairs(arena.lockedPlayers) do
				ArenaDoorState:FireClient(player, "Unlock", arena.id)
			end
			if arena.enemyFolder then arena.enemyFolder:Destroy() end
			arenas[room] = nil
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	scanAccumulator += dt
	if scanAccumulator >= CHECK_INTERVAL then
		scanAccumulator = 0
		scanArenas()
		cleanupMissingArenas()
		for _, arena in pairs(arenas) do
			if not arena.cleared then
				for _, player in ipairs(Players:GetPlayers()) do
					if playerInRoom(player, arena.room) then
						if arena.started then lockPlayer(arena, player) else startArena(arena, player) end
					end
				end
			end
		end
	end
end)

local genComplete = ReplicatedStorage:FindFirstChild("GenComplete")
if not genComplete then
	genComplete = Instance.new("BindableEvent")
	genComplete.Name = "GenComplete"
	genComplete.Parent = ReplicatedStorage
end
if genComplete:IsA("BindableEvent") then
	genComplete.Event:Connect(function()
		task.defer(scanArenas)
	end)
end

print("[Arena] ArenaController ready")
