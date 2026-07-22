-- LevelController.server.lua
-- ServerScriptService
-- Main game orchestrator - voting system + player management + level flow
-- Stripped: No FirstBlock, Elevator, LobbySpawn, pedestal fling
-- Stubs: Cinematics, Extraction, Collapse, Enemies

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Workspace           = game:GetService("Workspace")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService        = game:GetService("TweenService")
local RunService          = game:GetService("RunService")

-- ========================================
-- UTILITIES
-- ========================================
local function getOrCreate(className, name, parent)
	parent = parent or ReplicatedStorage
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local obj = Instance.new(className)
	obj.Name   = name
	obj.Parent = parent
	return obj
end

local function ensureBindable(name)
	return getOrCreate("BindableEvent", name)
end

-- ========================================
-- REMOTES / BINDABLES
-- ========================================
local UpdateGameStateEvent   = getOrCreate("RemoteEvent",  "UpdateGameState")
local FreezePlayerEvent      = getOrCreate("RemoteEvent",  "FreezePlayer")
local NotifyGenCompleteEvent = getOrCreate("RemoteEvent",  "NotifyGenComplete")
local StartLevelEvent        = getOrCreate("RemoteEvent",  "StartLevelEvent")
local RoundCinematicEvent    = getOrCreate("RemoteEvent",  "RoundCinematicEvent")
local StateChangedEvent      = getOrCreate("RemoteEvent",  "StateChanged")
local SubstateChangedEvent   = getOrCreate("RemoteEvent",  "SubstateChanged")
local ResetPlayerHealthEvent = getOrCreate("BindableEvent", "ResetPlayerHealth")
local ResetScoreEvent = getOrCreate("BindableEvent", "ResetScore")

local QuotaMetEventObj = ReplicatedStorage:FindFirstChild("QuotaMetEvent")
if not QuotaMetEventObj then
	QuotaMetEventObj        = Instance.new("BindableEvent")
	QuotaMetEventObj.Name   = "QuotaMetEvent"
	QuotaMetEventObj.Parent = ReplicatedStorage
end

local PlayerEscapedEventObj = ReplicatedStorage:FindFirstChild("PlayerEscaped")
if not PlayerEscapedEventObj then
	PlayerEscapedEventObj        = Instance.new("RemoteEvent")
	PlayerEscapedEventObj.Name   = "PlayerEscaped"
	PlayerEscapedEventObj.Parent = ReplicatedStorage
end

-- ========================================
-- MODULES
-- ========================================
local ModulesFolder = ServerScriptService:FindFirstChild("GameModules")
if not ModulesFolder then
	ModulesFolder        = Instance.new("Folder")
	ModulesFolder.Name   = "GameModules"
	ModulesFolder.Parent = ServerScriptService
end

local VotingManager, MoneyManager, ActiveEffectsManager
local EnemyRegistry, CurseManager, UpgradeManager

task.spawn(function()
	local waited = 0
	while waited < 10 do
		VotingManager        = ModulesFolder:FindFirstChild("VotingManager")
		MoneyManager         = ModulesFolder:FindFirstChild("MoneyManager")
		ActiveEffectsManager = ModulesFolder:FindFirstChild("ActiveEffectsManager")
		EnemyRegistry        = ModulesFolder:FindFirstChild("EnemyRegistry")
		CurseManager         = ModulesFolder:FindFirstChild("CurseManager")
		UpgradeManager       = ModulesFolder:FindFirstChild("UpgradeManager")
		if VotingManager and EnemyRegistry and CurseManager and UpgradeManager then break end
		task.wait(0.5); waited += 0.5
	end

	if VotingManager        then VotingManager        = require(VotingManager)        end
	if MoneyManager         then MoneyManager         = require(MoneyManager)         end
	if ActiveEffectsManager then ActiveEffectsManager = require(ActiveEffectsManager) end
	if EnemyRegistry        then EnemyRegistry        = require(EnemyRegistry)        end
	if CurseManager         then CurseManager         = require(CurseManager)         end
	if UpgradeManager       then UpgradeManager       = require(UpgradeManager)       end

	print("[LEVEL CONTROLLER] Modules loaded.")
end)

-- ========================================
-- STUB FLAGS
-- Flip to true as you add each real system
-- ========================================
local HAS_CINEMATICS = false
local HAS_EXTRACTION = false
local HAS_ENEMIES    = true
local HAS_COLLAPSE   = false

-- ========================================
-- GAME STATE
-- ========================================
local GameState = {
	currentLevel     = 0,
	state            = "Waiting",
	quota            = 1,
	deposited        = 0,
	escapedPlayers   = {},
	deadPlayers      = {},

	MAIN_STATE       = "Start",
	SUBSTATE         = "WaitingForStart",

	selectedEnemy    = nil,
	permanentEnemies = {},
	selectedCurses   = {},
	selectedUpgrades = {},
	levelStartTime   = 0,
}

local generationAckByUserId     = {}
local generationSyncToken       = 0
local generationFinalizeStarted = false
local generationSyncDeadline    = 0
local generationSyncLevel       = 0
local generationSyncQuota       = 1
local roundTransitionInProgress = false

-- ========================================
-- STUBS
-- ========================================
local function fireCinematic(action, payload)
	if not HAS_CINEMATICS then return end
	payload = payload or {}; payload.action = action
	pcall(function() RoundCinematicEvent:FireAllClients(payload) end)
end

local function startMapBreakdown()
	if not HAS_COLLAPSE then
		print("[LEVEL CONTROLLER] (stub) Collapse skipped — no collapse system yet")
		return
	end
	if type(_G.StartMapBreakdown) == "function" then pcall(_G.StartMapBreakdown); return end
	local be = ReplicatedStorage:FindFirstChild("StartMapBreakdown")
	if be and be:IsA("BindableEvent") then pcall(function() be:Fire() end) end
end

local function spawnEnemies()
	if not HAS_ENEMIES then
		print("[LEVEL CONTROLLER] (stub) Enemy spawn skipped — no enemies yet")
		return
	end
	local SpawnEnemy = ensureBindable("SpawnEnemy")
	for enemyName, enemyCount in pairs(GameState.permanentEnemies) do
		if enemyCount and enemyCount > 0 then
			pcall(function() SpawnEnemy:Fire(enemyName, enemyCount) end)
		end
	end
end

local function resetAllPlayerHealth(reason)
	if ResetPlayerHealthEvent and ResetPlayerHealthEvent:IsA("BindableEvent") then
		ResetPlayerHealthEvent:Fire()
		print(string.format("[LEVEL CONTROLLER] ResetPlayerHealth fired (%s)", reason or "no_reason"))
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("Health", 100)
		player:SetAttribute("IsDead", false)
		player:SetAttribute("Spectating", false)
	end
end

-- ========================================
-- PLAYER HELPERS
-- ========================================
local function freezeAllPlayers(freeze)
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local hum = char:FindFirstChild("Humanoid")
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hum and hrp then
				if freeze then
					hum.WalkSpeed = 0; hum.JumpPower = 0; hum.JumpHeight = 0; hrp.Anchored = true
				else
					hum.WalkSpeed = 16; hum.JumpPower = 50; hum.JumpHeight = 7.2; hrp.Anchored = false
				end
			end
		end
		pcall(function() FreezePlayerEvent:FireClient(player, freeze) end)
	end
	print("[LEVEL CONTROLLER]", freeze and "Frozen" or "Unfrozen", "all players")
end

-- Teleport everyone to the generated map's Spawn room.
-- Falls back to 0,100,0 if the room isn't found yet.
-- ── Door transition remote ────────────────────────────────────
-- Tells a specific client to flash white (entering the door)
local DoorFlashEvent        = getOrCreate("RemoteEvent", "DoorFlash")
local EnterSpectatorEvent   = getOrCreate("RemoteEvent", "EnterSpectator")   -- others still alive
local ReturnToVoteEvent     = getOrCreate("RemoteEvent", "ReturnToVote")      -- everyone done

-- ── Door helpers ──────────────────────────────────────────────
local DOOR_OPEN_ANGLE    = math.rad(90)   -- real doors open ~90 degrees
local DOOR_OPEN_TIME     = 1.2
local DOOR_ENTRY_TIMEOUT = 20

local function getLevelDoor()
	return Workspace:FindFirstChild("LevelDoor")
end

local function getMapSpawnCFrame()
	local genFolder  = Workspace:FindFirstChild("GeneratedRooms")
	local spawnModel = genFolder and genFolder:FindFirstChild("Spawn")
	if spawnModel then
		return CFrame.new(spawnModel:GetPivot().Position + Vector3.new(0, 5, 0))
	end
	return CFrame.new(0, 100, 0)
end

local function teleportPlayerIntoMap(player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	-- Flash white on client then teleport
	pcall(function() DoorFlashEvent:FireClient(player) end)
	task.wait(0.15)  -- let flash start before the position snaps
	hrp.CFrame = getMapSpawnCFrame()
	player:SetAttribute("EnteredLevel", true)
end

local doorConnection = nil
local doorClosedCF   = nil

local function getDoorOpenCF(panel)
	local pivotCF     = panel:GetPivot()
	local localOffset = pivotCF:Inverse() * panel.CFrame
	return (pivotCF * CFrame.Angles(0, -DOOR_OPEN_ANGLE, 0)) * localOffset
end

local function openDoorAndSendPlayers(level, quota)
	local door = getLevelDoor()
	if not door then
		warn("[LEVEL CONTROLLER] LevelDoor not found — teleporting directly")
		for _, p in ipairs(Players:GetPlayers()) do teleportPlayerIntoMap(p) end
		return
	end

	local panel   = door:FindFirstChild("DoorPanel")
	local trigger = door:FindFirstChild("DoorTrigger")

	for _, p in ipairs(Players:GetPlayers()) do
		p:SetAttribute("EnteredLevel", false)
	end

	if panel then
		doorClosedCF = panel.CFrame
		TweenService:Create(panel,
			TweenInfo.new(DOOR_OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = getDoorOpenCF(panel) }
		):Play()
	end

	task.wait(DOOR_OPEN_TIME)

	if trigger then
		trigger.CanCollide = false
		if doorConnection then doorConnection:Disconnect() end
		local lastCheck = 0
		doorConnection = RunService.Heartbeat:Connect(function()
			local now = tick()
			if now - lastCheck < 0.1 then return end
			lastCheck = now
			if not trigger or not trigger.Parent then
				doorConnection:Disconnect(); return
			end
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("EnteredLevel") then continue end
				local char = p.Character
				local hrp  = char and char:FindFirstChild("HumanoidRootPart")
				if hrp and (hrp.Position - trigger.Position).Magnitude <= 5 then
					teleportPlayerIntoMap(p)
				end
			end
		end)
	end

	task.delay(DOOR_ENTRY_TIMEOUT, function()
		if GameState.state ~= "Playing" then return end
		local forcedCount = 0
		for _, p in ipairs(Players:GetPlayers()) do
			if not p:GetAttribute("EnteredLevel") then
				teleportPlayerIntoMap(p)
				forcedCount += 1
			end
		end
		if forcedCount > 0 then
			print(string.format("[LEVEL CONTROLLER] Force-teleported %d straggler(s)", forcedCount))
		end
		if doorConnection then doorConnection:Disconnect(); doorConnection = nil end
	end)
end

local function closeDoor()
	local door = getLevelDoor()
	if not door then return end
	local panel = door:FindFirstChild("DoorPanel")
	if panel and doorClosedCF then
		TweenService:Create(panel,
			TweenInfo.new(DOOR_OPEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ CFrame = doorClosedCF }
		):Play()
	end
	if doorConnection then doorConnection:Disconnect(); doorConnection = nil end
end

local function getVoteCFrame()
	local votePart = Workspace:FindFirstChild("Vote")
	if votePart and votePart:IsA("BasePart") then
		return votePart.CFrame + Vector3.new(0, 5, 0)
	end
	warn("[LEVEL CONTROLLER] 'Vote' part not found in Workspace!")
	return CFrame.new(0, 50, 0)
end

local function teleportPlayerToVote(player)
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = getVoteCFrame()
end

local function teleportToVote()
	local cf = getVoteCFrame()
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = cf end
		end
	end
	print("[LEVEL CONTROLLER] Teleported all players to Vote")
end

local function broadcastState()
	pcall(function() StateChangedEvent:FireAllClients(GameState.MAIN_STATE) end)
	pcall(function() SubstateChangedEvent:FireAllClients(GameState.SUBSTATE) end)
	print("[LEVEL CONTROLLER] State:", GameState.MAIN_STATE, "| Substate:", GameState.SUBSTATE)
end

local function changeMainState(s)  GameState.MAIN_STATE = s; broadcastState() end
local function changeSubstate(s)   GameState.SUBSTATE   = s; broadcastState() end

local function isEvenLevel() return GameState.currentLevel % 2 == 0 end

local startEnemyVoting, startCurseVoting, startUpgradeVoting, startLevelGeneration
local beginGenerationSync
local advanceRound

local function getOptionTier(voteType, optionName)
	if voteType == "Upgrade" and UpgradeManager and type(UpgradeManager.GetUpgradeData) == "function" then
		local d = UpgradeManager:GetUpgradeData(optionName); return d and tonumber(d.Tier)
	elseif voteType == "Curse" and CurseManager and type(CurseManager.GetCurseData) == "function" then
		local d = CurseManager:GetCurseData(optionName); return d and tonumber(d.Tier)
	elseif voteType == "Enemy" and EnemyRegistry then
		if type(EnemyRegistry.GetEnemyData) == "function" then
			local d = EnemyRegistry:GetEnemyData(optionName); return d and tonumber(d.Tier)
		end
		if type(EnemyRegistry.Enemies) == "table" and type(EnemyRegistry.Enemies[optionName]) == "table" then
			return tonumber(EnemyRegistry.Enemies[optionName].Tier)
		end
	end
	return nil
end

local function isEnemyOptionAvailable(optionName, level)
	if not EnemyRegistry then return true end
	local data = type(EnemyRegistry.GetEnemyData) == "function" and EnemyRegistry:GetEnemyData(optionName)
	if not data and type(EnemyRegistry.Enemies) == "table" then
		data = EnemyRegistry.Enemies[optionName]
	end
	if type(data) ~= "table" then return true end
	if data.Enabled == false then return false end
	local reqLevel = tonumber(data.LevelRequirement) or 1
	return (tonumber(level) or 1) >= reqLevel
end

local function alignOptionsForThreeSlots(opts)
	local input = opts or {}
	return input
end

local function getEnabledEnemyOptionsForLevel(level)
	local out = {}
	if not EnemyRegistry or type(EnemyRegistry.Enemies) ~= "table" then
		return out
	end
	for name, data in pairs(EnemyRegistry.Enemies) do
		if type(data) == "table" then
			local enabled = data.Enabled ~= false
			local tier = tonumber(data.Tier) or 1
			local reqLevel = tonumber(data.LevelRequirement) or 1
			if enabled and tier <= level and level >= reqLevel then
				table.insert(out, name)
			end
		end
	end
	table.sort(out)
	return out
end

local function filterOptionsByTier(voteType, level, options)
	local filtered = {}
	for _, opt in ipairs(options or {}) do
		if voteType == "Enemy" and not isEnemyOptionAvailable(opt, level) then
			continue
		end
		local tier = getOptionTier(voteType, opt)
		if not tier or tier <= level then table.insert(filtered, opt) end
	end
	if #filtered == 0 then
		if voteType == "Enemy" then
			local nonShade = {}
			for _, opt in ipairs(options or {}) do
				if isEnemyOptionAvailable(opt, level) then
					table.insert(nonShade, opt)
				end
			end
			if #nonShade > 0 then return nonShade end
			if EnemyRegistry and ((type(EnemyRegistry.GetEnemyData) == "function" and EnemyRegistry:GetEnemyData("Covet")) or (type(EnemyRegistry.Enemies) == "table" and EnemyRegistry.Enemies["Covet"])) then
				return { "Covet" }
			end
		end
		return options or {}
	end
	return filtered
end

startEnemyVoting = function()
	if not VotingManager then warn("[LEVEL CONTROLLER] VotingManager not loaded"); return end
	changeSubstate("EnemyVoting")
	local opts = getEnabledEnemyOptionsForLevel(GameState.currentLevel)
	if #opts == 0 then
		opts = filterOptionsByTier("Enemy", GameState.currentLevel,
			VotingManager:GetEnemyOptions(GameState.currentLevel, 3))
	end
	opts = alignOptionsForThreeSlots(opts)
	VotingManager:StartVote("Enemy", opts, function(winner)
		GameState.selectedEnemy = winner
		local enemyData = EnemyRegistry and type(EnemyRegistry.GetEnemyData) == "function" and EnemyRegistry:GetEnemyData(winner)
		if enemyData and enemyData.ArenaOnly then
			print("[LEVEL CONTROLLER] Arena enemy selected:", winner, "(not added to permanent spawns)")
		else
			GameState.permanentEnemies[winner] = (GameState.permanentEnemies[winner] or 0) + 1
			print("[LEVEL CONTROLLER] Enemy selected:", winner)
		end
		task.wait(1); startCurseVoting()
	end)
end

startCurseVoting = function()
	if not VotingManager then return end
	changeSubstate("CurseVoting")
	local opts = filterOptionsByTier("Curse", GameState.currentLevel,
		VotingManager:GetCurseOptions(GameState.currentLevel, 3))
	VotingManager:StartVote("Curse", opts, function(winner)
		table.insert(GameState.selectedCurses, winner)
		print("[LEVEL CONTROLLER] Curse selected:", winner)
		task.wait(1); startUpgradeVoting()
	end)
end

startUpgradeVoting = function()
	if not VotingManager then return end
	changeSubstate("UpgradeVoting")
	local opts = filterOptionsByTier("Upgrade", GameState.currentLevel,
		VotingManager:GetUpgradeOptions(GameState.currentLevel, 3))

	if _G.UpdateLeftPedestal then _G.UpdateLeftPedestal("SkipUpgrade", true) end

	VotingManager:StartVote("Upgrade", opts, function(winner)
		if winner == "SKIPPED" then
			print("[LEVEL CONTROLLER] Upgrade skipped")
			task.wait(1); startLevelGeneration(); return
		end
		table.insert(GameState.selectedUpgrades, winner)
		print("[LEVEL CONTROLLER] Upgrade selected:", winner)
		task.wait(0.35); startUpgradeVoting()
	end)
end

local function startVotingPhase()
	local clearEv = ReplicatedStorage:FindFirstChild("ClearEnemies")
	if not clearEv then clearEv = ensureBindable("ClearEnemies") end
	pcall(function() clearEv:Fire() end)

	changeMainState("Voting")
	GameState.selectedEnemy    = nil
	GameState.selectedCurses   = {}
	GameState.selectedUpgrades = {}

	resetAllPlayerHealth("startVotingPhase")
	if ResetScoreEvent and ResetScoreEvent:IsA("BindableEvent") then
		ResetScoreEvent:Fire(false)
	end
	-- Players should already be in the lobby/hub when voting restarts.
	freezeAllPlayers(false)

	if _G.UpdateLeftPedestal then _G.UpdateLeftPedestal("WaitingForStart", false) end

	if isEvenLevel() then
		print("[LEVEL CONTROLLER] Even level — skipping enemy vote")
		startCurseVoting()
	else
		print("[LEVEL CONTROLLER] Odd level — starting enemy vote")
		startEnemyVoting()
	end
end

startLevelGeneration = function()
	changeMainState("InGame")
	changeSubstate("Generating")
	GameState.state          = "Generating"
	GameState.deposited      = 0
	GameState.escapedPlayers = {}
	GameState.deadPlayers    = {}

	resetAllPlayerHealth("startLevelGeneration")
	if ResetScoreEvent and ResetScoreEvent:IsA("BindableEvent") then
		ResetScoreEvent:Fire(false)
	end

	print(string.format("[LEVEL CONTROLLER] Starting Level %d generation", GameState.currentLevel))

	if ActiveEffectsManager then
		for _, c in ipairs(GameState.selectedCurses)   do ActiveEffectsManager:ApplyCurse(c)   end
		for _, u in ipairs(GameState.selectedUpgrades) do ActiveEffectsManager:ApplyUpgrade(u) end
	end

	freezeAllPlayers(true)

	pcall(function() UpdateGameStateEvent:FireAllClients({
		state = "Generating", level = GameState.currentLevel
		}) end)

	task.wait(0.1)

	beginGenerationSync(GameState.currentLevel, GameState.quota)

	local trigEv = ReplicatedStorage:FindFirstChild("TriggerGeneration") or ensureBindable("TriggerGeneration")
	pcall(function() trigEv:Fire(GameState.currentLevel) end)
end

local function countGenerationReadyPlayers()
	local total, ready = 0, 0
	for _, pl in ipairs(Players:GetPlayers()) do
		total += 1
		if generationAckByUserId[pl.UserId] then ready += 1 end
	end
	return ready, total
end

local function finalizeGenerationIfNeeded(level, quota, reason)
	if generationFinalizeStarted or GameState.state ~= "Generating" then return end
	generationFinalizeStarted = true

	GameState.quota = quota or generationSyncQuota or 1
	GameState.state = "Playing"
	changeSubstate("Collecting")

	print(string.format("[LEVEL CONTROLLER] Finalize (%s) Level:%d Quota:%d", reason, level or 0, GameState.quota))

	-- New dream flow: generation prepares the mining pod/cart in the vote area.
	-- Players board the highlighted pod instead of walking through LevelDoor.
	freezeAllPlayers(false)

	pcall(function() UpdateGameStateEvent:FireAllClients({
		state     = "Playing",
		level     = level,
		quota     = GameState.quota,
		deposited = 0,
		}) end)

	local resetQuota = ReplicatedStorage:FindFirstChild("ResetQuota") or ensureBindable("ResetQuota")
	pcall(function() resetQuota:Fire(level, GameState.quota) end)

	task.wait(0.35)
	spawnEnemies()

	GameState.levelStartTime = tick()
	print("[LEVEL CONTROLLER] Game started! Level:", level)
end

beginGenerationSync = function(level, quota)
	generationSyncToken        += 1
	local myToken               = generationSyncToken
	generationFinalizeStarted   = false
	generationAckByUserId       = {}
	generationSyncLevel         = level or GameState.currentLevel
	generationSyncQuota         = quota or 1
	generationSyncDeadline      = tick() + 15

	task.spawn(function()
		while GameState.state == "Generating" and not generationFinalizeStarted and myToken == generationSyncToken do
			local ready, total = countGenerationReadyPlayers()
			if total > 0 and ready >= total then
				finalizeGenerationIfNeeded(generationSyncLevel, generationSyncQuota, "all_ready"); return
			end
			if tick() >= generationSyncDeadline then
				finalizeGenerationIfNeeded(generationSyncLevel, generationSyncQuota,
					string.format("timeout_%d_of_%d", ready, total)); return
			end
			task.wait(0.25)
		end
	end)
end

NotifyGenCompleteEvent.OnServerEvent:Connect(function(player, level, quota)
	if GameState.state ~= "Generating" or not player then return end
	if level then generationSyncLevel = level end
	if quota  then generationSyncQuota = quota  end
	generationAckByUserId[player.UserId] = true
	local ready, total = countGenerationReadyPlayers()
	print(string.format("[LEVEL CONTROLLER] GenComplete from %s (%d/%d)", player.Name, ready, total))
	if total > 0 and ready >= total then
		finalizeGenerationIfNeeded(generationSyncLevel, generationSyncQuota, "all_ready")
	end
end)

local GenCompleteEventObj = ReplicatedStorage:FindFirstChild("GenComplete") or ensureBindable("GenComplete")
if GenCompleteEventObj:IsA("BindableEvent") then
	GenCompleteEventObj.Event:Connect(function(level, quota)
		if GameState.state ~= "Generating" then return end
		if level then generationSyncLevel = level end
		if quota then generationSyncQuota = quota end
		finalizeGenerationIfNeeded(generationSyncLevel, generationSyncQuota, "server_gen_complete")
	end)
end

local function startCollapsePhase()
	changeSubstate("Collapse")
	GameState.state = "QuotaMet"
	print(string.format("[LEVEL CONTROLLER] Quota met! Level %d", GameState.currentLevel))

	if MoneyManager and type(MoneyManager.AddCoins) == "function" then
		MoneyManager:AddCoins(100 * GameState.currentLevel)
	end

	pcall(function() UpdateGameStateEvent:FireAllClients({
		state = "QuotaMet", level = GameState.currentLevel
		}) end)

	startMapBreakdown()
	local function everyoneBackAtLobby()
		for _, p in ipairs(Players:GetPlayers()) do
			if p:GetAttribute("IsDead") == true then
				continue
			end
			if p:GetAttribute("EnteredLevel") == true then
				return false
			end
		end
		return true
	end
	task.spawn(function()
		while GameState.state == "QuotaMet" and not roundTransitionInProgress do
			if everyoneBackAtLobby() then
				advanceRound()
				return
			end
			task.wait(0.4)
		end
	end)
end

if QuotaMetEventObj:IsA("BindableEvent") then
	QuotaMetEventObj.Event:Connect(function()
		if GameState.state == "Playing" then startCollapsePhase() end
	end)
elseif QuotaMetEventObj:IsA("RemoteEvent") then
	QuotaMetEventObj.OnServerEvent:Connect(function()
		if GameState.state == "Playing" then startCollapsePhase() end
	end)
end

advanceRound = function()
	if roundTransitionInProgress then return end
	roundTransitionInProgress = true

	GameState.state = "Transitioning"
	pcall(function() UpdateGameStateEvent:FireAllClients({state = "Transitioning"}) end)

	local clearEv = ReplicatedStorage:FindFirstChild("ClearEnemies")
	if clearEv and clearEv:IsA("BindableEvent") then pcall(function() clearEv:Fire() end) end

	fireCinematic("TransitionIn")

	task.spawn(function()
		task.wait(0.35)
		if _G.ResetExtraction then pcall(_G.ResetExtraction) end

		closeDoor()
		resetAllPlayerHealth("advanceRound")
		freezeAllPlayers(true)

		GameState.currentLevel += 1
		startVotingPhase()
		freezeAllPlayers(false)

		task.wait(1)
		fireCinematic("TransitionOut")
		roundTransitionInProgress = false
	end)
end

PlayerEscapedEventObj.OnServerEvent:Connect(function(player)
	if GameState.state ~= "QuotaMet" then return end
	GameState.escapedPlayers[player] = true
	print(string.format("[LEVEL CONTROLLER] %s escaped!", player.Name))

	local allDone = true
	for _, p in ipairs(Players:GetPlayers()) do
		local isDead = p:GetAttribute("IsDead") == true
		if not p:GetAttribute("Spectating") and not isDead
			and not GameState.escapedPlayers[p] and not GameState.deadPlayers[p] then
			allDone = false; break
		end
	end
	if allDone then advanceRound() end
end)

local function hookEscapeBindable(name)
	local ev = ReplicatedStorage:FindFirstChild(name) or ensureBindable(name)
	if ev:IsA("BindableEvent") then
		ev.Event:Connect(function()
			if GameState.state == "QuotaMet" then advanceRound() end
		end)
	end
	ReplicatedStorage.ChildAdded:Connect(function(child)
		if child.Name == name and child:IsA("BindableEvent") then
			child.Event:Connect(function()
				if GameState.state == "QuotaMet" then advanceRound() end
			end)
		end
	end)
end
hookEscapeBindable("PlayerEscapedServer")
hookEscapeBindable("PlayerEscapedServerBindable")

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(character)
		local hum = character:WaitForChild("Humanoid")
		local hrp = character:WaitForChild("HumanoidRootPart")

		task.wait(0.1)

		local state = GameState.MAIN_STATE
		if state == "Start" or state == "Voting" then
			hrp.CFrame = getVoteCFrame()
			print(string.format("[LEVEL CONTROLLER] New join: teleported %s to Vote", player.Name))
		else
			hrp.CFrame = getVoteCFrame()
			player:SetAttribute("Spectating", true)
			print(string.format("[LEVEL CONTROLLER] Mid-game join: %s set to spectating", player.Name))
		end

		local function onDeadChanged()
			if GameState.state == "QuotaMet" and player:GetAttribute("IsDead") == true then
				GameState.deadPlayers[player] = true
				print(string.format("[LEVEL CONTROLLER] %s died (custom health)", player.Name))
			end
		end
		player:GetAttributeChangedSignal("IsDead"):Connect(onDeadChanged)

		hum.Died:Connect(function()
			if GameState.state == "QuotaMet" then
				GameState.deadPlayers[player] = true
				print(string.format("[LEVEL CONTROLLER] %s died", player.Name))
			end
		end)
	end)
end)

local function startGame()
	print("[LEVEL CONTROLLER] Game starting!")
	GameState.currentLevel = 1
	if MoneyManager and type(MoneyManager.ResetCoins) == "function" then
		MoneyManager:ResetCoins()
	end
	startVotingPhase()
end

_G.StartGameFromPedestal = function(player)
	print("[LEVEL CONTROLLER] Start requested by", player.Name)
	if GameState.MAIN_STATE == "Start" and GameState.SUBSTATE == "WaitingForStart" then
		startGame()
	else
		warn("[LEVEL CONTROLLER] Cannot start — wrong state:", GameState.MAIN_STATE, GameState.SUBSTATE)
	end
end

StartLevelEvent.OnServerEvent:Connect(function(player, level)
	GameState.currentLevel = level or 1; startGame()
end)

_G.StartLevel = function(level)
	GameState.currentLevel = level or 1; startGame()
end

pcall(function() math.randomseed(tick()); math.random(); math.random(); math.random() end)
print("[LEVEL CONTROLLER] Initialized")
broadcastState()

task.defer(function()
	resetAllPlayerHealth("init")
	teleportToVote()
end)

return GameState
