-- ArtifactDeposit.server.lua
-- ServerScriptService
-- Connects Room models through FrontDoor->Connect/BackDoor and handles artifact pedestal deposits.

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
local usedConnectParts = {}
local wiredPedestal = nil
local wirePedestal

SetHeldItemRE.OnServerEvent:Connect(function(player, itemName)
	if not player then return end
	if type(itemName) == "string" and itemName ~= "" then
		player:SetAttribute("HeldItem", itemName)
	else
		player:SetAttribute("HeldItem", nil)
	end
end)

local function convertBackDoor(room)
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

	local newBack = convertBackDoor(room)
	latestBackDoor = newBack
	return room
end

local function getConnectPart()
	local connect = Workspace:FindFirstChild("Connect")
	if connect and connect:IsA("BasePart") and not usedConnectParts[connect] then
		usedConnectParts[connect] = true
		return connect
	end
	return nil
end

local function setupInitialConnection()
	if roomTemplate then return end
	local room = Workspace:FindFirstChild("Room")
	if not room or not room:IsA("Model") then return end
	roomTemplate = room:Clone()
	roomTemplate.Parent = ReplicatedStorage
	roomTemplate.Name = "RoomTemplateRuntime"
	room:Destroy()

	local connect = getConnectPart()
	if not connect then return end
	cloneAndAttachRoom(connect)
	connect:Destroy()
	print("[ArtifactDeposit] Initial room connected")
end

local function findPedestalClickPart()
	for _, model in ipairs(Workspace:GetChildren()) do
		if model:IsA("Model") then
			local pedestal = model:FindFirstChild("Pedastal", true) or model:FindFirstChild("Pedestal", true)
			if pedestal then
				local fallback = nil
				for _, inst in ipairs(pedestal:GetDescendants()) do
					if inst:IsA("BasePart") and inst.Transparency < 0.99 then
						fallback = fallback or inst
						if inst:FindFirstChildOfClass("ClickDetector") then
							return inst
						end
					end
				end
				if fallback then return fallback end
			end
		end
	end
	return nil
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

local function attachNextRoomFromBackDoor()
	if not latestBackDoor or not latestBackDoor.Parent then return end
	local nextRoom = cloneAndAttachRoom(latestBackDoor)
	if nextRoom then
		latestBackDoor:Destroy()
		print("[ArtifactDeposit] Extended dream by one room")
	end
end

local function onPedestalClicked(player)
		if not player or not player.Parent then return end
	local held = player:GetAttribute("HeldItem")
	if type(held) ~= "string" or held == "" then
		warn("[ArtifactDeposit] Click ignored: no HeldItem on", player.Name)
		return
	end

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
	if not template or not template:IsA("BasePart") then
		warn("[ArtifactDeposit] No artifact template available in ReplicatedStorage.Items")
		return
	end

	local clickPart = wiredPedestal and wiredPedestal.Parent and wiredPedestal or findPedestalClickPart()
	if not clickPart then
		warn("[ArtifactDeposit] No pedestal part found to wire")
		return
	end

	local artifact = template:Clone()
	artifact.Anchored = true
	artifact.CanCollide = false
	clickPart.Transparency = 1
	clickPart.CanCollide = false
	artifact.CFrame = clickPart.CFrame * CFrame.new(0, clickPart.Size.Y * 0.5 + artifact.Size.Y * 0.5 + 0.15, 0)
	artifact.Parent = clickPart.Parent

	artifact:SetAttribute("DepositedArtifact", true)
	player:SetAttribute("HeldItem", nil)
	ItemDepositRE:FireClient(player, held)
	ArtifactDepositedEvent:Fire(player, held)
	startBob(artifact)
	attachNextRoomFromBackDoor()
	wiredPedestal = nil
	wirePedestal()
	print("[ArtifactDeposit] Deposited", held)
end

wirePedestal = function()
	if wiredPedestal and wiredPedestal.Parent then return end
	local clickPart = findPedestalClickPart()
	if not clickPart then
		warn("[ArtifactDeposit] No pedestal part found to wire")
		return
	end
	local cd = clickPart:FindFirstChildOfClass("ClickDetector")
	if not cd then
		cd = Instance.new("ClickDetector")
		cd.Parent = clickPart
	end
	cd.MaxActivationDistance = 20
	cd.MouseClick:Connect(onPedestalClicked)
	wiredPedestal = clickPart
	print("[ArtifactDeposit] Pedestal wired")
end

GenComplete.Event:Connect(function()
	setupInitialConnection()
	wirePedestal()
end)

task.defer(function()
	setupInitialConnection()
	wirePedestal()
end)

print("[ArtifactDeposit] Ready")
