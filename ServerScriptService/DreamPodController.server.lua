-- DreamPodController.server.lua
-- ServerScriptService
-- Handles the mining-cage pod (Workspace.car1) that carries players between
-- the voting area and the currently generated dream map.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local CART_NAME = "car1"
local OCCUPANT_HOLD_TIME = 0.45
local CART_ROOM_PADDING = Vector3.new(4, 6, 4)
local CART_PLAYER_OFFSET = Vector3.new(0, 4, 0)
local LANDING_CLEARANCE = 0.25
local LIFT_HEIGHT = 46
local DROP_HEIGHT = 105
local LIFT_TIME = 1.45
local DROP_TIME = 2.65
local RETURN_DROP_TIME = 2.0
local FADE_IN_TIME = 0.7
local FADE_OUT_TIME = 1.05

local function getOrCreateRemote(name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then return remote end
	if remote then remote:Destroy() end
	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = ReplicatedStorage
	return remote
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

local PodFade = getOrCreateRemote("PodFade")
local DreamPodReady = getOrCreateBindable("DreamPodReady")
local DreamPodArrived = getOrCreateBindable("DreamPodArrived")
local DreamPodReturned = getOrCreateBindable("DreamPodReturned")
local QuotaMetEvent = getOrCreateBindable("QuotaMetEvent")

local cart = Workspace:WaitForChild(CART_NAME, 20)
if not cart then
	warn("[DreamPod] Missing Workspace." .. CART_NAME .. "; pod travel disabled")
	return
end

local lobbyCFrame = cart:GetPivot()
local landingCFrame = nil
local dreamReady = false
local traveling = false
local available = false
local cartLocation = "Lobby" -- Lobby/Dream
local occupantCandidate = nil
local occupantSince = 0

local highlight = Instance.new("Highlight")
highlight.Name = "DreamPodReadyHighlight"
highlight.Adornee = cart
highlight.FillTransparency = 0.75
highlight.OutlineTransparency = 0
highlight.FillColor = Color3.fromRGB(255, 230, 130)
highlight.OutlineColor = Color3.fromRGB(255, 245, 180)
highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
highlight.Enabled = false
highlight.Parent = cart

local function setHighlighted(enabled)
	highlight.Enabled = enabled and available and not traveling
end

local function setAvailable(enabled)
	available = enabled
	setHighlighted(enabled)
end

local function getCartBounds()
	local cf, size
	if cart:IsA("Model") then
		cf, size = cart:GetBoundingBox()
	elseif cart:IsA("BasePart") then
		cf, size = cart.CFrame, cart.Size
	else
		cf, size = cart:GetPivot(), Vector3.new(12, 12, 12)
	end
	return cf, size + CART_ROOM_PADDING
end

local function pointInsideCart(point)
	local cf, size = getCartBounds()
	local lp = cf:PointToObjectSpace(point)
	return math.abs(lp.X) <= size.X * 0.5
		and math.abs(lp.Y) <= size.Y * 0.5
		and math.abs(lp.Z) <= size.Z * 0.5
end

local function getPlayerRoot(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getFirstOccupant()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("IsDead") then continue end
		local hrp = getPlayerRoot(player)
		if hrp and pointInsideCart(hrp.Position) then
			return player
		end
	end
	return nil
end

local function putPlayerInCart(player)
	local hrp = getPlayerRoot(player)
	if not hrp then return end
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = cart:GetPivot() * CFrame.new(CART_PLAYER_OFFSET)
end

local function getCartBottomOffset()
	local pivot = cart:GetPivot()
	local cf, size
	if cart:IsA("Model") then
		cf, size = cart:GetBoundingBox()
	elseif cart:IsA("BasePart") then
		cf, size = cart.CFrame, cart.Size
	else
		return CART_PLAYER_OFFSET.Y
	end
	local bottomY = cf.Position.Y - size.Y * 0.5
	return math.max(0, pivot.Position.Y - bottomY) + LANDING_CLEARANCE
end

local function getCartOnTopOf(topCFrame)
	local targetPosition = topCFrame.Position + Vector3.new(0, getCartBottomOffset(), 0)
	return CFrame.new(targetPosition) * (topCFrame - topCFrame.Position)
end

local function lockPassenger(player)
	local hrp = getPlayerRoot(player)
	if not hrp then return nil end
	local state = {
		player = player,
		hrp = hrp,
		anchored = hrp.Anchored,
	}
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = true
	putPlayerInCart(player)
	return state
end

local function updatePassengerRide(state)
	if not state or not state.player.Parent then return end
	local hrp = getPlayerRoot(state.player)
	if not hrp then return end
	state.hrp = hrp
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.CFrame = cart:GetPivot() * CFrame.new(CART_PLAYER_OFFSET)
end

local function unlockPassenger(state)
	if not state then return end
	updatePassengerRide(state)
	if state.hrp and state.hrp.Parent then
		state.hrp.AssemblyLinearVelocity = Vector3.zero
		state.hrp.Anchored = state.anchored
	end
end

local function waitUntilPlayerLeaves(player)
	local clearTime = 0
	while player.Parent and not traveling do
		local dt = task.wait(0.2)
		local hrp = getPlayerRoot(player)
		if not hrp or not pointInsideCart(hrp.Position) then
			clearTime += dt
			if clearTime >= 0.8 then return end
		else
			clearTime = 0
		end
	end
end

local function pivotCartTo(cf)
	cart:PivotTo(cf)
end

local function tweenCartPivot(targetCFrame, duration, easingStyle, easingDirection, passengerState)
	local value = Instance.new("CFrameValue")
	value.Value = cart:GetPivot()
	local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		if cart and cart.Parent then
			pivotCartTo(value.Value)
			updatePassengerRide(passengerState)
		end
	end)
	local tween = TweenService:Create(value, TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Sine, easingDirection or Enum.EasingDirection.InOut), {
		Value = targetCFrame,
	})
	tween:Play()
	tween.Completed:Wait()
	conn:Disconnect()
	value:Destroy()
	pivotCartTo(targetCFrame)
	updatePassengerRide(passengerState)
end

local function fade(player, mode, duration)
	PodFade:FireClient(player, mode, duration)
end

local function travelToDream(player)
	if traveling or not dreamReady or not landingCFrame then return end
	traveling = true
	setAvailable(false)
	print("[DreamPod] Taking", player.Name, "to dream")

	local passengerState = lockPassenger(player)
	local liftTarget = cart:GetPivot() + Vector3.new(0, LIFT_HEIGHT, 0)
	task.delay(math.max(0.1, LIFT_TIME - FADE_IN_TIME * 0.85), function()
		if traveling then fade(player, "In", FADE_IN_TIME) end
	end)
	tweenCartPivot(liftTarget, LIFT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, passengerState)
	task.wait(0.08)

	local dreamCartCFrame = getCartOnTopOf(landingCFrame)
	local dropStart = dreamCartCFrame + Vector3.new(0, DROP_HEIGHT, 0)
	pivotCartTo(dropStart)
	updatePassengerRide(passengerState)
	player:SetAttribute("EnteredLevel", true)
	player:SetAttribute("Spectating", false)

	fade(player, "Out", FADE_OUT_TIME)
	tweenCartPivot(dreamCartCFrame, DROP_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, passengerState)
	unlockPassenger(passengerState)

	cartLocation = "Dream"
	traveling = false
	DreamPodArrived:Fire(player, dreamCartCFrame)

	waitUntilPlayerLeaves(player)
	setAvailable(true)
	print("[DreamPod] Pod available for return")
end

local function travelToLobby(player)
	if traveling then return end
	traveling = true
	setAvailable(false)
	print("[DreamPod] Returning", player.Name, "to vote area")

	local passengerState = lockPassenger(player)
	local liftTarget = cart:GetPivot() + Vector3.new(0, LIFT_HEIGHT, 0)
	task.delay(math.max(0.1, LIFT_TIME - FADE_IN_TIME * 0.85), function()
		if traveling then fade(player, "In", FADE_IN_TIME) end
	end)
	tweenCartPivot(liftTarget, LIFT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, passengerState)
	task.wait(0.08)

	local dropStart = lobbyCFrame + Vector3.new(0, DROP_HEIGHT * 0.6, 0)
	pivotCartTo(dropStart)
	updatePassengerRide(passengerState)
	player:SetAttribute("EnteredLevel", false)

	fade(player, "Out", FADE_OUT_TIME)
	tweenCartPivot(lobbyCFrame, RETURN_DROP_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, passengerState)
	unlockPassenger(passengerState)

	cartLocation = "Lobby"
	traveling = false
	DreamPodReturned:Fire(player)

	waitUntilPlayerLeaves(player)
	setAvailable(dreamReady)
	print("[DreamPod] Pod available in lobby")
end

local function pulseLiftDownForRoundEnd()
	if traveling or cartLocation ~= "Lobby" or not cart or not cart.Parent then return end
	local start = cart:GetPivot()
	local lowered = start + Vector3.new(0, -12, 0)
	tweenCartPivot(lowered, 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, nil)
	task.wait(0.2)
	tweenCartPivot(start, 0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, nil)
end

DreamPodReady.Event:Connect(function(payload)
	landingCFrame = payload and payload.LandingCFrame or ReplicatedStorage:GetAttribute("DreamPodLandingCFrame")
	if typeof(landingCFrame) ~= "CFrame" then
		warn("[DreamPod] DreamPodReady fired without a landing CFrame")
		dreamReady = false
		setAvailable(false)
		return
	end
	dreamReady = true
	cartLocation = "Lobby"
	pivotCartTo(lobbyCFrame)
	setAvailable(true)
	print(string.format("[DreamPod] Ready for dream '%s'", tostring(payload and payload.DreamName or ReplicatedStorage:GetAttribute("ActiveDreamName"))))
end)

QuotaMetEvent.Event:Connect(function()
	task.spawn(pulseLiftDownForRoundEnd)
end)


task.defer(function()
	local existingLanding = ReplicatedStorage:GetAttribute("DreamPodLandingCFrame")
	if ReplicatedStorage:GetAttribute("GenDone") == true and typeof(existingLanding) == "CFrame" then
		landingCFrame = existingLanding
		dreamReady = true
		cartLocation = "Lobby"
		pivotCartTo(lobbyCFrame)
		setAvailable(true)
		print("[DreamPod] Recovered existing generated dream state")
	end
end)

RunService.Heartbeat:Connect(function()
	if traveling or not available then
		occupantCandidate = nil
		occupantSince = 0
		return
	end

	local occupant = getFirstOccupant()
	if not occupant then
		occupantCandidate = nil
		occupantSince = 0
		return
	end

	if occupant ~= occupantCandidate then
		occupantCandidate = occupant
		occupantSince = os.clock()
		return
	end

	if os.clock() - occupantSince < OCCUPANT_HOLD_TIME then return end
	occupantCandidate = nil
	occupantSince = 0

	if cartLocation == "Lobby" then
		travelToDream(occupant)
	else
		travelToLobby(occupant)
	end
end)

print("[DreamPod] Controller ready")
