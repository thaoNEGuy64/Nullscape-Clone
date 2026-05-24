local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function getOrCreateBindable(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then return ev end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local SpawnEnemyEvent = getOrCreateBindable("SpawnEnemy")

local enemyModulesFolder = ServerScriptService:WaitForChild("Enemies")
local loadedModules = {}

local function loadEnemyModule(enemyName)
	if loadedModules[enemyName] then return loadedModules[enemyName] end

	local candidateNames = {
		enemyName .. "Module",
		enemyName .. "Server",
		enemyName,
	}

	for _, name in ipairs(candidateNames) do
		local mod = enemyModulesFolder:FindFirstChild(name)
		if mod then
			if not mod:IsA("ModuleScript") then
				warn(string.format("[EnemySpawner] %s exists but is not a ModuleScript", name))
			else
				local ok, required = pcall(require, mod)
				if ok then
					loadedModules[enemyName] = required
					return required
				end
				warn(string.format("[EnemySpawner] Failed requiring %s: %s", mod.Name, tostring(required)))
			end
		end
	end

	warn(string.format("[EnemySpawner] Missing valid ModuleScript for %s. Expected one of: %s", enemyName, table.concat(candidateNames, ", ")))
	return nil
end

local function getActiveDreamCenter()
	local landing = ReplicatedStorage:GetAttribute("DreamPodLandingCFrame")
	if typeof(landing) == "CFrame" then
		return landing.Position
	end

	local dreamsFolder = workspace:FindFirstChild("GeneratedDreams")
	local dream = dreamsFolder and dreamsFolder:FindFirstChildWhichIsA("Model")
	if dream then
		return dream:GetPivot().Position
	end

	local genFolder = workspace:FindFirstChild("GeneratedRooms")
	local spawnModel = genFolder and genFolder:FindFirstChild("Spawn")
	return spawnModel and spawnModel:GetPivot().Position or Vector3.new(0, 8, 0)
end

local function getSpawnNearMap(offset)
	local center = getActiveDreamCenter()
	local ang = math.random() * math.pi * 2
	local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
	local rayOrigin = center + dir * offset + Vector3.new(0, 120, 0)
	local result = workspace:Raycast(rayOrigin, Vector3.new(0, -400, 0))
	if result then
		return result.Position + Vector3.new(0, 3, 0)
	end
	return center + dir * offset + Vector3.new(0, 3, 0)
end

SpawnEnemyEvent.Event:Connect(function(enemyName, enemyCount)
	enemyCount = math.max(1, tonumber(enemyCount) or 1)
	local module = loadEnemyModule(enemyName)
	if not module or type(module.Spawn) ~= "function" then
		warn(string.format("[EnemySpawner] Invalid module for %s", tostring(enemyName)))
		return
	end

	for _ = 1, enemyCount do
		local pos = getSpawnNearMap(200)
		module.Spawn(pos)
	end

	print(string.format("[EnemySpawner] Spawned %d x %s", enemyCount, tostring(enemyName)))
end)

print("[EnemySpawner] Ready")
