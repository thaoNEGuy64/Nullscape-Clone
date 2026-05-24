-- ArtifactDeposit.server.lua
-- ServerScriptService
-- Places the Room.FrontDoor onto Connect, converts BackDoor to a normal part,
-- and handles pedestal deposit using held artifacts.

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

local rigged = false
local isPlaced = false

local function convertBackDoor(room)
	local backDoor = room:FindFirstChild("BackDoor", true)
	if not backDoor or not backDoor:IsA("BasePart") then return end
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
end

local function setupConnectionRoom()
	if rigged then return end
	local connect = Workspace:FindFirstChild("Connect")
	local room = Workspace:FindFirstChild("Room")
	if not connect or not connect:IsA("BasePart") or not room or not room:IsA("Model") then return end

	local frontDoor = room:FindFirstChild("FrontDoor", true)
	if frontDoor and frontDoor:IsA("BasePart") then
		frontDoor.CFrame = connect.CFrame
		frontDoor.Anchored = true
		frontDoor.Parent = Workspace
		connect:Destroy()
	end

	convertBackDoor(room)
	rigged = true
	print("[ArtifactDeposit] Room connected")
end

local function findPedestalClickPart()
	local room = Workspace:FindFirstChild("Room")
	if not room then return nil end
	local pedestal = room:FindFirstChild("Pedastal", true) or room:FindFirstChild("Pedestal", true)
	if not pedestal then return nil end
	for _, inst in ipairs(pedestal:GetDescendants()) do
		if inst:IsA("BasePart") and inst:FindFirstChildOfClass("ClickDetector") then
			return inst
		end
	end
	return nil
end

local function startBob(part)
	task.spawn(function()
		local base = part.CFrame
		while part.Parent and isPlaced do
			local up = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = base * CFrame.new(0, 0.45, 0) })
			up:Play(); up.Completed:Wait()
			local down = TweenService:Create(part, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = base * CFrame.new(0, -0.45, 0) })
			down:Play(); down.Completed:Wait()
		end
	end)
end

local function onPedestalClicked(player)
	if isPlaced then return end
	if not player or not player.Parent then return end
	local held = player:GetAttribute("HeldItem")
	if type(held) ~= "string" or held == "" then return end

	local templateFolder = ReplicatedStorage:FindFirstChild("Items")
	local template = templateFolder and templateFolder:FindFirstChild(held)
	if not template or not template:IsA("BasePart") then
		warn("[ArtifactDeposit] Missing item template for", held)
		return
	end

	local clickPart = findPedestalClickPart()
	if not clickPart then return end

	local artifact = template:Clone()
	artifact.Anchored = true
	artifact.CanCollide = false
	artifact.CFrame = clickPart.CFrame * CFrame.new(0, clickPart.Size.Y * 0.5 + artifact.Size.Y * 0.5 + 0.15, 0)
	artifact.Parent = clickPart.Parent

	isPlaced = true
	player:SetAttribute("HeldItem", nil)
	ItemDepositRE:FireClient(player, held)
	ArtifactDepositedEvent:Fire(player, held)
	startBob(artifact)
	print("[ArtifactDeposit] Deposited", held)
end

local function wirePedestal()
	local clickPart = findPedestalClickPart()
	if not clickPart then return end
	local cd = clickPart:FindFirstChildOfClass("ClickDetector")
	if not cd then
		cd = Instance.new("ClickDetector")
		cd.Parent = clickPart
	end
	cd.MaxActivationDistance = 20
	cd.MouseClick:Connect(onPedestalClicked)
	print("[ArtifactDeposit] Pedestal wired")
end

GenComplete.Event:Connect(function()
	setupConnectionRoom()
	wirePedestal()
end)

task.defer(function()
	setupConnectionRoom()
	wirePedestal()
end)

print("[ArtifactDeposit] Ready")
