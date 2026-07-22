-- ============================================================
-- DREAM GENERATOR
-- Triggered by LevelController via TriggerGeneration:Fire(level)
-- New base: clones one large dream map instead of stitching rooms.
-- ============================================================

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DreamsFolder = ReplicatedStorage:WaitForChild("Dreams")
local ProgressEvent = ReplicatedStorage:FindFirstChild("UpdateGenerationProgress")

local ItemsFolder = ReplicatedStorage:FindFirstChild("Items")

local DREAM_ORIGIN = CFrame.new(0, 1500, 0)
local function calcQuota(level)
	level = math.max(1, math.floor(level or 1))
	local artifactCount = level
	return math.ceil(artifactCount * 10 * (0.8 + level * 0.05))
end

local generationId = 0
local rng = Random.new()

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function chooseRandom(list)
	if #list == 0 then return nil end
	return list[rng:NextInteger(1, #list)]
end

local function getOrCreateBindable(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if ev and ev:IsA("BindableEvent") then return ev end
	if ev then ev:Destroy() end
	ev = Instance.new("BindableEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local QuotaSetEvent = getOrCreateBindable("QuotaSet")
local GenCompleteEvent = getOrCreateBindable("GenComplete")
local DreamPodReadyEvent = getOrCreateBindable("DreamPodReady")

local function clearOldDream()
	for _, name in ipairs({ "GeneratedDreams", "GeneratedRooms", "GeneratedBridges", "SpawnedItems" }) do
		local old = Workspace:FindFirstChild(name)
		if old then old:Destroy() end
	end
end

local function getMarkerParts(model, markerName)
	local markers = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == markerName then
			markers[#markers + 1] = inst
		end
	end
	table.sort(markers, function(a, b) return a:GetFullName() < b:GetFullName() end)
	return markers
end

local function getDreamCandidates()
	local candidates = {}
	for _, dream in ipairs(DreamsFolder:GetChildren()) do
		if dream:IsA("Model") then
			local portalCount = #getMarkerParts(dream, "PortalHere")
			if portalCount >= 2 then
				candidates[#candidates + 1] = dream
			end
		end
	end
	return candidates
end

local function chooseDream()
	local candidates = getDreamCandidates()
	if #candidates == 0 then
		for _, dream in ipairs(DreamsFolder:GetChildren()) do
			if dream:IsA("Model") then
				candidates[#candidates + 1] = dream
			end
		end
	end
	if #candidates == 0 then return nil end
	return chooseRandom(candidates)
end

local function hideReservedPortalMarker(marker)
	-- The pod landing marker should not also get a visible rift frame later.
	marker:SetAttribute("ReservedForPod", true)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
end

local function runGeneration(level)
	level = math.max(1, math.floor(level or 1))
	generationId += 1
	local myGenerationId = generationId

	clearOldDream()

	local generatedDreams = Instance.new("Folder")
	generatedDreams.Name = "GeneratedDreams"
	generatedDreams.Parent = Workspace

	-- Compatibility folder for older systems that still scan GeneratedRooms.
	local generatedRooms = Instance.new("Folder")
	generatedRooms.Name = "GeneratedRooms"
	generatedRooms.Parent = Workspace

	local spawnedItems = Instance.new("Folder")
	spawnedItems.Name = "SpawnedItems"
	spawnedItems.Parent = Workspace

	local allDreamTemplates = {}
	for _, d in ipairs(DreamsFolder:GetChildren()) do
		if d:IsA("Model") then table.insert(allDreamTemplates, d) end
	end
	if #allDreamTemplates == 0 then
		warn("[DreamGen] No dream models found in ReplicatedStorage/Dreams")
		ReplicatedStorage:SetAttribute("GenDone", true)
		local q = calcQuota(level)
		GenCompleteEvent:Fire(level, q)
		return
	end

	local dreamCount = math.max(1, level)
	local templatePool = table.clone(allDreamTemplates)
	shuffle(templatePool)
	local dreams = {}
	for i = 1, dreamCount do
		if #templatePool == 0 then
			templatePool = table.clone(allDreamTemplates)
			shuffle(templatePool)
		end
		local template = table.remove(templatePool, 1)
		local dream = template:Clone()
		dream.Name = string.format("%s_%d", template.Name, i)
		dream:SetAttribute("DreamName", template.Name)
		dream:SetAttribute("DreamLevel", level)
		dream:SetAttribute("DreamIndex", i)
		dream.Parent = generatedDreams
		dream:PivotTo(DREAM_ORIGIN + Vector3.new((i - 1) * 1400, 0, 0))
		table.insert(dreams, dream)
	end
	local dream = chooseRandom(dreams) or dreams[1]

	-- Older arena/enemy code mostly scans GeneratedRooms children, so place a soft
	-- reference marker there and keep the real map under GeneratedDreams.
	local dreamMarker = Instance.new("Model")
	dreamMarker.Name = dream.Name
	dreamMarker:SetAttribute("DreamName", dream.Name)
	dreamMarker:SetAttribute("IsDreamReference", true)
	dreamMarker.Parent = generatedRooms

	local quota = calcQuota(level)
	local markersByDream = {}
	local dreamsWithMarkers = {}
	local extraMarkers = {}
	for _, d in ipairs(dreams) do
		local markers = getMarkerParts(d, "ItemHere")
		shuffle(markers)
		markersByDream[d] = markers
		if #markers > 0 then table.insert(dreamsWithMarkers, d) end
	end
	shuffle(dreamsWithMarkers)

	local artifactMarkers = {}
	local artifactCount = level
	for _, d in ipairs(dreamsWithMarkers) do
		if #artifactMarkers >= artifactCount then break end
		local marker = table.remove(markersByDream[d], 1)
		if marker then table.insert(artifactMarkers, marker) end
	end
	for _, d in ipairs(dreamsWithMarkers) do
		for _, marker in ipairs(markersByDream[d]) do table.insert(extraMarkers, marker) end
	end
	shuffle(extraMarkers)
	while #artifactMarkers < artifactCount and #extraMarkers > 0 do
		table.insert(artifactMarkers, table.remove(extraMarkers, 1))
	end

	if ItemsFolder and #artifactMarkers > 0 then
		local template = ItemsFolder:FindFirstChild("Paper") or ItemsFolder:FindFirstChildWhichIsA("BasePart")
		if template then
			local itemsFolder = Instance.new("Folder")
			itemsFolder.Name = "DreamArtifacts"
			itemsFolder.Parent = Workspace:FindFirstChild("SpawnedItems") or spawnedItems
			local toSpawn = #artifactMarkers
			for i = 1, toSpawn do
				local markerPart = artifactMarkers[i]
				local container = Instance.new("Model")
				container.Name = "Paper"
				container.Parent = itemsFolder
				local clone = template:Clone()
				clone.CFrame = markerPart.CFrame * CFrame.new(0, markerPart.Size.Y * 0.5 + clone.Size.Y * 0.5, 0)
				clone.Parent = container
				local trigger = Instance.new("Part")
				trigger.Name = "Trigger"
				trigger.Size = Vector3.new(4, 4, 4)
				trigger.CFrame = clone.CFrame
				trigger.Transparency = 1
				trigger.Anchored = true
				trigger.CanCollide = false
				trigger.Parent = container
			end
			print(string.format("[DreamGen] Spawned %d artifact pickup(s) from ItemHere", toSpawn))
		else
			warn("[DreamGen] Missing Items/Paper template for ItemHere spawn")
		end
	end

	local portalMarkers = getMarkerParts(dream, "PortalHere")
	shuffle(portalMarkers)
	if #portalMarkers == 0 then
		warn("[DreamGen] Dream '" .. dream.Name .. "' has no PortalHere parts; using dream pivot as pod landing")
	end

	local landingMarker = portalMarkers[1]
	local landingCFrame = landingMarker and (landingMarker.CFrame * CFrame.new(0, landingMarker.Size.Y * 0.5, 0)) or dream:GetPivot()
	if landingMarker then hideReservedPortalMarker(landingMarker) end

	ReplicatedStorage:SetAttribute("ActiveDreamName", dream:GetAttribute("DreamName") or dream.Name)
	ReplicatedStorage:SetAttribute("ActiveDreamLevel", level)
	ReplicatedStorage:SetAttribute("DreamPodLandingCFrame", landingCFrame)
	ReplicatedStorage:SetAttribute("DreamPodLobbyCFrame", nil)
	ReplicatedStorage:SetAttribute("GenDone", true)

	pcall(function() QuotaSetEvent:Fire(quota, level) end)
	if ProgressEvent then ProgressEvent:FireAllClients(1, 1) end

	print(string.format("[DreamGen] Loaded %d dream(s). Primary '%s' has %d PortalHere marker(s).", #dreams, dream.Name, #portalMarkers))

	if generationId ~= myGenerationId then return end
	DreamPodReadyEvent:Fire({
		Dream = dream,
		DreamName = dream.Name,
		Level = level,
		LandingCFrame = landingCFrame,
		Quota = quota,
	})
	GenCompleteEvent:Fire(level, quota)
end

local TriggerGeneration = ReplicatedStorage:FindFirstChild("TriggerGeneration")
if not TriggerGeneration then
	TriggerGeneration = Instance.new("BindableEvent")
	TriggerGeneration.Name = "TriggerGeneration"
	TriggerGeneration.Parent = ReplicatedStorage
end

TriggerGeneration.Event:Connect(function(level)
	task.spawn(function()
		runGeneration(level)
	end)
end)

print("[DreamGen] Ready — waiting for TriggerGeneration.")
