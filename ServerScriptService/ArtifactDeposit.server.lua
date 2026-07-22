-- ArtifactDeposit.server.lua
-- ServerScriptService
-- Connects deposit Room clones through FrontDoor -> target BackDoor/Connect
-- and handles generic artifact deposits on each room's Pedastal/Part.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local function getOrCreateRemote(name)
	local ev = ReplicatedStorage:FindFirstChild(name)
	if ev and ev:IsA("RemoteEvent") then return ev end
	if ev then ev:Destroy() end
	ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = ReplicatedStorage
	return ev
end

local ItemDepositRE = getOrCreateRemote("ItemDeposit")
local SetHeldItemRE = getOrCreateRemote("SetHeldItem")

local ArtifactDepositedEvent = ReplicatedStorage:FindFirstChild("ArtifactDeposited")
if not ArtifactDepositedEvent or not ArtifactDepositedEvent:IsA("BindableEvent") then
	ArtifactDepositedEvent = Instance.new("BindableEvent")
	ArtifactDepositedEvent.Name = "ArtifactDeposited"
	ArtifactDepositedEvent.Parent = ReplicatedStorage
end

local GenComplete = ReplicatedStorage:FindFirstChild("GenComplete")
if not GenComplete or not GenComplete:IsA("BindableEvent") then
	GenComplete = Instance.new("BindableEvent")
	GenComplete.Name = "GenComplete"
	GenComplete.Parent = ReplicatedStorage
end

local roomTemplate = nil
local latestBackDoor = nil
local connectPart = nil
local depositRooms = {}
local wiredParts = {}

SetHeldItemRE.OnServerEvent:Connect(function(player, itemName)
	if not player then return end
	if type(itemName) == "string" and itemName ~= "" then
		player:SetAttribute("HeldItem", itemName)
	else
		player:SetAttribute("HeldItem", nil)
	end
end)

local function rememberOriginalRoom()
	if roomTemplate then return true end
	local room = Workspace:FindFirstChild("Room")
	if not room then
		room = Workspace:WaitForChild("Room", 30)
	end
	if not room or not room:IsA("Model") then
		warn("[ArtifactDeposit] Workspace.Room template was not found or is not a Model")
		return false
	end
	roomTemplate = room:Clone()
	roomTemplate.Name = "RoomTemplateRuntime"
	roomTemplate.Parent = ReplicatedStorage
	room:Destroy()
	print("[ArtifactDeposit] Cached Workspace.Room as RoomTemplateRuntime")
	return true
end

local function clearDepositRooms()
	for _, room in ipairs(depositRooms) do
		if room and room.Parent then room:Destroy() end
	end
	table.clear(depositRooms)
	table.clear(wiredParts)
	latestBackDoor = nil
end

local function getConnectPart()
	if connectPart and connectPart.Parent then return connectPart end
	local connect = Workspace:FindFirstChild("Connect")
	if not connect then
		connect = Workspace:WaitForChild("Connect", 30)
	end
	if connect and connect:IsA("BasePart") then
		connectPart = connect
		return connectPart
	end
	warn("[ArtifactDeposit] Workspace.Connect was not found or is not a BasePart")
	return nil
end

local function hideTargetDoor(targetDoorPart)
	if not targetDoorPart or not targetDoorPart:IsA("BasePart") then return end
	targetDoorPart.Transparency = 1
	targetDoorPart.CanCollide = false
	targetDoorPart.CanTouch = false
	targetDoorPart.CanQuery = false
end

local function sealBackDoor(room)
	local backDoor = room:FindFirstChild("BackDoor", true)
	if not backDoor or not backDoor:IsA("BasePart") then return nil end
	local replacement = Instance.new("Part")
	replacement.Name = backDoor.Name
	replacement.Size = backDoor.Size
	replacement.CFrame = backDoor.CFrame
	replacement.Color = backDoor.Color
	replacement.Material = backDoor.Material
	replacement.Transparency = backDoor.Transparency
	replacement.Reflectance = backDoor.Reflectance
	replacement.Anchored = true
	replacement.CanCollide = true
	replacement.Parent = backDoor.Parent
	backDoor:Destroy()
	return replacement
end

local function cloneAndAttachRoom(targetDoorPart)
	if not roomTemplate or not targetDoorPart or not targetDoorPart:IsA("BasePart") then return nil end
	local room = roomTemplate:Clone()
	room.Name = "Room"
	room:SetAttribute("DepositRoomClone", true)
	room.Parent = Workspace

	local frontDoor = room:FindFirstChild("FrontDoor", true)
	if not frontDoor or not frontDoor:IsA("BasePart") then
		room:Destroy()
		return nil
	end

	local pivot = room:GetPivot()
	local delta = targetDoorPart.CFrame * frontDoor.CFrame:Inverse()
	room:PivotTo(delta * pivot)

	local frontAfter = room:FindFirstChild("FrontDoor", true)
	if frontAfter and frontAfter:IsA("BasePart") then
		frontAfter:Destroy()
	end

	hideTargetDoor(targetDoorPart)
	latestBackDoor = sealBackDoor(room)
	table.insert(depositRooms, room)
	print(string.format("[ArtifactDeposit] Attached deposit room #%d to %s", #depositRooms, targetDoorPart:GetFullName()))
	return room
end

local function buildDepositRoomChain(artifactCount)
	if not rememberOriginalRoom() then
		warn("[ArtifactDeposit] Missing Workspace.Room template")
		return
	end
	clearDepositRooms()

	local target = getConnectPart()
	if not target then
		warn("[ArtifactDeposit] Missing Workspace.Connect")
		return
	end

	artifactCount = math.max(1, math.floor(artifactCount or 1))
	for i = 1, artifactCount do
		local room = cloneAndAttachRoom(target)
		if not room then
			warn("[ArtifactDeposit] Failed to attach deposit room #" .. tostring(i))
			break
		end
		-- The previous back door becomes the next target. If this is the last
		-- room, it remains as a normal sealed Part so players don't see void.
		target = latestBackDoor
	end

	print(string.format("[ArtifactDeposit] Connected %d deposit room(s)", #depositRooms))
end

local function findPedestalDepositParts()
	local parts = {}
	for _, room in ipairs(depositRooms) do
		if room and room.Parent then
			local pedestal = room:FindFirstChild("Pedastal", true) or room:FindFirstChild("Pedestal", true)
			local depositPart = pedestal and pedestal:FindFirstChild("Part", true)
			if depositPart and depositPart:IsA("BasePart") and depositPart.Transparency < 0.99 and not depositPart:GetAttribute("DepositedPedestal") then
				table.insert(parts, depositPart)
			end
		end
	end
	return parts
end

local function startBob(part)
	task.spawn(function()
		local base = part.CFrame
		while part.Parent and part:GetAttribute("DepositedArtifact") == true do
			local up = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = base * CFrame.new(0, 0.45, 0) })
			up:Play(); up.Completed:Wait()
			local down = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = base * CFrame.new(0, -0.45, 0) })
			down:Play(); down.Completed:Wait()
		end
	end)
end

local function getArtifactTemplate(held)
	local templateFolder = ReplicatedStorage:FindFirstChild("Items")
	local template = templateFolder and templateFolder:FindFirstChild(held)
	if not (template and template:IsA("BasePart")) and templateFolder then
		for _, obj in ipairs(templateFolder:GetChildren()) do
			if obj:IsA("BasePart") then
				template = obj
				break
			end
		end
	end
	return template
end

local function depositOnPart(player, clickPart)
	if not clickPart or clickPart:GetAttribute("DepositedPedestal") then return end
	if not player or not player.Parent then return end
	local held = player:GetAttribute("HeldItem")
	if type(held) ~= "string" or held == "" then
		warn("[ArtifactDeposit] Click ignored: no HeldItem on", player.Name)
		return
	end

	local template = getArtifactTemplate(held)
	if not template or not template:IsA("BasePart") then
		warn("[ArtifactDeposit] No artifact template available in ReplicatedStorage.Items")
		return
	end

	local artifact = template:Clone()
	artifact.Anchored = true
	artifact.CanCollide = false
	clickPart:SetAttribute("DepositedPedestal", true)
	clickPart.Transparency = 1
	clickPart.CanCollide = false
	clickPart.CanTouch = false
	clickPart.CanQuery = false
	artifact.CFrame = clickPart.CFrame * CFrame.new(0, clickPart.Size.Y * 0.5 + artifact.Size.Y * 0.5 + 0.15, 0)
	artifact.Parent = clickPart.Parent

	artifact:SetAttribute("DepositedArtifact", true)
	player:SetAttribute("HeldItem", nil)
	ItemDepositRE:FireClient(player, held)
	ArtifactDepositedEvent:Fire(player, held)
	startBob(artifact)
	print("[ArtifactDeposit] Deposited", held)
end

local function wirePedestals()
	local count = 0
	for _, clickPart in ipairs(findPedestalDepositParts()) do
		if not wiredParts[clickPart] then
			local cd = clickPart:FindFirstChildOfClass("ClickDetector")
			if not cd then
				cd = Instance.new("ClickDetector")
				cd.Parent = clickPart
			end
			cd.MaxActivationDistance = 20
			cd.MouseClick:Connect(function(player)
				depositOnPart(player, clickPart)
			end)
			wiredParts[clickPart] = true
			count += 1
		end
	end
	print(string.format("[ArtifactDeposit] Pedestal deposit part(s) wired: %d", count))
end

GenComplete.Event:Connect(function(level)
	local artifactCount = math.max(1, math.floor(tonumber(level) or 1))
	buildDepositRoomChain(artifactCount)
	wirePedestals()
end)

task.defer(function()
	for attempt = 1, 6 do
		buildDepositRoomChain(1)
		wirePedestals()
		if #depositRooms > 0 then return end
		task.wait(1)
	end
end)

print("[ArtifactDeposit] Ready")
