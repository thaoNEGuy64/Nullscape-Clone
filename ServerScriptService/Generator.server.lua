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
	return math.max(1, math.floor(level or 1))
end

local generationId = 0

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
	return candidates[math.random(1, #candidates)]
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

	local dreamTemplate = chooseDream()
	if not dreamTemplate then
		warn("[DreamGen] No dream models found in ReplicatedStorage/Dreams")
		ReplicatedStorage:SetAttribute("GenDone", true)
		GenCompleteEvent:Fire(level, quota)
		return
	end

	local dream = dreamTemplate:Clone()
	dream.Name = dreamTemplate.Name
	dream:SetAttribute("DreamName", dreamTemplate.Name)
	dream:SetAttribute("DreamLevel", level)
	dream.Parent = generatedDreams
	dream:PivotTo(DREAM_ORIGIN)

	-- Older arena/enemy code mostly scans GeneratedRooms children, so place a soft
	-- reference marker there and keep the real map under GeneratedDreams.
	local dreamMarker = Instance.new("Model")
	dreamMarker.Name = dream.Name
	dreamMarker:SetAttribute("DreamName", dream.Name)
	dreamMarker:SetAttribute("IsDreamReference", true)
	dreamMarker.Parent = generatedRooms

	local itemMarkers = getMarkerParts(dream, "ItemHere")
	if ItemsFolder and #itemMarkers > 0 then
		local template = ItemsFolder:FindFirstChild("Paper") or ItemsFolder:FindFirstChildWhichIsA("BasePart")
		if template then
			local spawnedItems = Instance.new("Folder")
			spawnedItems.Name = "DreamArtifacts"
			spawnedItems.Parent = dream
			for i, markerPart in ipairs(itemMarkers) do
				local container = Instance.new("Model")
				container.Name = "Paper"
				container.Parent = spawnedItems
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
			print(string.format("[DreamGen] Spawned %d artifact pickup(s) from ItemHere", #itemMarkers))
		else
			warn("[DreamGen] Missing Items/Paper template for ItemHere spawn")
		end
	end

	local portalMarkers = getMarkerParts(dream, "PortalHere")
	if #portalMarkers == 0 then
		warn("[DreamGen] Dream '" .. dream.Name .. "' has no PortalHere parts; using dream pivot as pod landing")
	end

	local landingMarker = portalMarkers[1]
	local landingCFrame = landingMarker and (landingMarker.CFrame * CFrame.new(0, landingMarker.Size.Y * 0.5, 0)) or dream:GetPivot()
	if landingMarker then hideReservedPortalMarker(landingMarker) end

	ReplicatedStorage:SetAttribute("ActiveDreamName", dream.Name)
	ReplicatedStorage:SetAttribute("ActiveDreamLevel", level)
	ReplicatedStorage:SetAttribute("DreamPodLandingCFrame", landingCFrame)
	ReplicatedStorage:SetAttribute("DreamPodLobbyCFrame", nil)
	ReplicatedStorage:SetAttribute("GenDone", true)

	local quota = calcQuota(level)
	pcall(function() QuotaSetEvent:Fire(quota, level) end)
	if ProgressEvent then ProgressEvent:FireAllClients(1, 1) end

	print(string.format("[DreamGen] Loaded dream '%s' with %d PortalHere marker(s). Pod landing reserved at %s",
		dream.Name,
		#portalMarkers,
		tostring(landingCFrame.Position)
	))

	if generationId ~= myGenerationId then return end
	DreamPodReadyEvent:Fire({
		Dream = dream,
		DreamName = dream.Name,
		Level = level,
		LandingCFrame = landingCFrame,
		Quota = DEFAULT_QUOTA,
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

pcall(function() math.randomseed(tick()); math.random(); math.random(); math.random() end)
print("[DreamGen] Ready — waiting for TriggerGeneration.")
