-- DreamPodController.server.lua
-- ServerScriptService

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local CART_NAME = "car1"
local STOP_HERE_NAME = "StopHere"

local OCCUPANT_HOLD_TIME = 0.45
local CART_ROOM_PADDING = Vector3.new(4, 6, 4)
local CART_PLAYER_OFFSET = Vector3.new(0, 0, 0)

local LANDING_CLEARANCE = 0.25
local LIFT_HEIGHT = 46
local DROP_HEIGHT = 105
local LIFT_TIME = 1.45
local RETURN_RISE_TIME = 2.0
local FADE_IN_TIME = 0.7
local FADE_OUT_TIME = 1.05

local PART_FADE_TIME  = 1.5
local POST_IMPACT_WAIT = 10

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

local PodFade          = getOrCreateRemote("PodFade")
local PodImpact        = getOrCreateRemote("PodImpact")
local DreamPodReady    = getOrCreateBindable("DreamPodReady")
local DreamPodArrived  = getOrCreateBindable("DreamPodArrived")
local DreamPodReturned = getOrCreateBindable("DreamPodReturned")

local cart = Workspace:WaitForChild(CART_NAME, 20)
if not cart then
	warn("[DreamPod] Missing Workspace." .. CART_NAME .. "; pod travel disabled")
	return
end

local stopHerePart = Workspace:WaitForChild(STOP_HERE_NAME, 20)
if not stopHerePart then
	warn("[DreamPod] Missing Workspace." .. STOP_HERE_NAME .. "; pod travel disabled")
	return
end

local cartTemplate = cart:Clone()
cartTemplate.Name   = CART_NAME .. "_Template"
cartTemplate.Parent = ReplicatedStorage
for _, d in ipairs(cartTemplate:GetDescendants()) do
	if d:IsA("BasePart") then
		d.Anchored     = true
		d.CanCollide   = false
		d.Transparency = 1
	end
end

local function getCartParts()
	local parts = {}
	for _, d in ipairs(cart:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	return parts
end

local function getCartBottomY()
	local lowest = math.huge
	for _, part in ipairs(getCartParts()) do
		local bottom = part.Position.Y - part.Size.Y * 0.5
		if bottom < lowest then lowest = bottom end
	end
	return lowest == math.huge and 0 or lowest
end

local function getCartCenter()
	local parts = getCartParts()
	if #parts == 0 then return Vector3.zero end
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, part in ipairs(parts) do
		local p, s = part.Position, part.Size * 0.5
		if p.X-s.X<minX then minX=p.X-s.X end; if p.X+s.X>maxX then maxX=p.X+s.X end
		if p.Y-s.Y<minY then minY=p.Y-s.Y end; if p.Y+s.Y>maxY then maxY=p.Y+s.Y end
		if p.Z-s.Z<minZ then minZ=p.Z-s.Z end; if p.Z+s.Z>maxZ then maxZ=p.Z+s.Z end
	end
	return Vector3.new((minX+maxX)*0.5, (minY+maxY)*0.5, (minZ+maxZ)*0.5)
end

local function moveCartByDeltaY(deltaY)
	if math.abs(deltaY) < 0.0001 then return end
	for _, part in ipairs(getCartParts()) do
		part.CFrame = part.CFrame + Vector3.new(0, deltaY, 0)
	end
end

local function teleportCart(targetBottomY, targetX, targetZ)
	local parts = getCartParts()
	if #parts == 0 then return end
	local minX, maxX = math.huge, -math.huge
	local minY       = math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, part in ipairs(parts) do
		local p, s = part.Position, part.Size * 0.5
		if p.X-s.X<minX then minX=p.X-s.X end; if p.X+s.X>maxX then maxX=p.X+s.X end
		if p.Y-s.Y<minY then minY=p.Y-s.Y end
		if p.Z-s.Z<minZ then minZ=p.Z-s.Z end; if p.Z+s.Z>maxZ then maxZ=p.Z+s.Z end
	end
	local delta = Vector3.new(
		targetX - (minX+maxX)*0.5,
		targetBottomY - minY,
		targetZ - (minZ+maxZ)*0.5
	)
	for _, part in ipairs(parts) do
		part.CFrame = part.CFrame + delta
	end
end

local function snapPlayerToCart(player)
	local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local center = getCartCenter()
	hrp.CFrame = CFrame.new(center + CART_PLAYER_OFFSET)
end

local function tweenCartY(targetBottomY, duration, easingStyle, easingDirection)
	local startY = getCartBottomY()
	if math.abs(targetBottomY - startY) < 0.001 then return end

	local value = Instance.new("NumberValue")
	value.Value = startY

	local lastY = startY
	local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
		local delta = value.Value - lastY
		lastY = value.Value
		moveCartByDeltaY(delta)
	end)

	local tween = TweenService:Create(
		value,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Sine, easingDirection or Enum.EasingDirection.InOut),
		{ Value = targetBottomY }
	)
	tween:Play()
	tween.Completed:Wait()

	conn:Disconnect()
	value:Destroy()

	local snap = targetBottomY - getCartBottomY()
	if math.abs(snap) > 0.001 then moveCartByDeltaY(snap) end
end

local landingCFrame = nil
local dreamReady    = false
local traveling     = false
local available     = false
local cartLocation  = "Pit"

local occupantCandidate = nil
local occupantSince     = 0

local pitBottomY   = getCartBottomY()
local lobbyBottomY = nil

local wreckageParts = {}

local function smashCart()
	local parts = getCartParts()
	local center = getCartCenter()
	wreckageParts = {}

	local explosion = Instance.new("Explosion")
	explosion.Position      = center
	explosion.BlastRadius   = 14
	explosion.BlastPressure = 0
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = Workspace
	Debris:AddItem(explosion, 3)

	for _, part in ipairs(parts) do
		part.Parent = Workspace

		part.Anchored   = false
		part.CanCollide = true

		local dir = (part.Position - center)
		if dir.Magnitude < 0.1 then
			dir = Vector3.new(math.random() - 0.5, 0.5, math.random() - 0.5)
		end
		dir = dir.Unit

		local lateralSpeed = math.random(120, 220)
		local upSpeed      = math.random(80, 160)
		local impulse = Vector3.new(
			dir.X * lateralSpeed,
			upSpeed,
			dir.Z * lateralSpeed
		)
		part:ApplyImpulse(impulse * part:GetMass())

		table.insert(wreckageParts, part)
	end
end

local function fadeWreckage()
	for _, part in ipairs(wreckageParts) do
		if not part or not part.Parent then continue end
		part.Anchored   = true
		part.CanCollide = false
		TweenService:Create(
			part,
			TweenInfo.new(PART_FADE_TIME, Enum.EasingStyle.Linear),
			{ Transparency = 1 }
		):Play()
		Debris:AddItem(part, PART_FADE_TIME + 0.1)
	end
	wreckageParts = {}
end

local function spawnReplacementCart(targetBottomY, targetX, targetZ)
	fadeWreckage()

	if cart and cart.Parent then
		cart:Destroy()
	end

	local newCart = cartTemplate:Clone()
	newCart.Name   = CART_NAME
	newCart.Parent = Workspace

	for _, d in ipairs(newCart:GetChildren()) do
		if d:IsA("BasePart") then
			d.Anchored     = true
			d.CanCollide   = true
			d.Transparency = 0
		end
	end
	for _, d in ipairs(newCart:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored     = true
			d.CanCollide   = true
			d.Transparency = 0
		end
	end

	cart = newCart

	local dropFromY = targetBottomY + 40
	teleportCart(dropFromY, targetX, targetZ)
	tweenCartY(targetBottomY, RETURN_RISE_TIME, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
end

local function setAvailable(enabled)
	available = enabled
end

local function getCartBoundsCenter()
	local parts = getCartParts()
	if #parts == 0 then return Vector3.zero, Vector3.new(12,12,12) end
	local minX, maxX = math.huge, -math.huge
	local minY, maxY = math.huge, -math.huge
	local minZ, maxZ = math.huge, -math.huge
	for _, part in ipairs(parts) do
		local p, s = part.Position, part.Size * 0.5
		if p.X-s.X<minX then minX=p.X-s.X end; if p.X+s.X>maxX then maxX=p.X+s.X end
		if p.Y-s.Y<minY then minY=p.Y-s.Y end; if p.Y+s.Y>maxY then maxY=p.Y+s.Y end
		if p.Z-s.Z<minZ then minZ=p.Z-s.Z end; if p.Z+s.Z>maxZ then maxZ=p.Z+s.Z end
	end
	local center = Vector3.new((minX+maxX)*0.5,(minY+maxY)*0.5,(minZ+maxZ)*0.5)
	local size   = Vector3.new(maxX-minX,maxY-minY,maxZ-minZ) + CART_ROOM_PADDING
	return center, size
end

local function pointInsideCart(point)
	local center, size = getCartBoundsCenter()
	local d = point - center
	return math.abs(d.X) <= size.X*0.5
		and math.abs(d.Y) <= size.Y*0.5
		and math.abs(d.Z) <= size.Z*0.5
end

local function getPlayerRoot(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function getFirstOccupant()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("IsDead") then continue end
		local hrp = getPlayerRoot(player)
		if hrp and pointInsideCart(hrp.Position) then return player end
	end
	return nil
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

local function fade(player, mode, duration)
	PodFade:FireClient(player, mode, duration)
end

local function raiseCartToStopHere()
	local targetBottomY = stopHerePart.Position.Y + LANDING_CLEARANCE
	tweenCartY(targetBottomY, LIFT_TIME, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)
	lobbyBottomY = getCartBottomY()
end

local function travelToDream(player)
	if traveling or not dreamReady or not landingCFrame then return end
	traveling = true
	setAvailable(false)
	print("[DreamPod] Taking", player.Name, "to dream")

	fade(player, "In", FADE_IN_TIME)
	local downTargetY = getCartBottomY() - LIFT_HEIGHT
	tweenCartY(downTargetY, LIFT_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

	local remaining = FADE_IN_TIME - LIFT_TIME
	if remaining > 0 then task.wait(remaining) end

	local dreamBottomY = landingCFrame.Position.Y + LANDING_CLEARANCE
	local dropStartY   = dreamBottomY + DROP_HEIGHT
	teleportCart(dropStartY, landingCFrame.Position.X, landingCFrame.Position.Z)
	snapPlayerToCart(player)

	player:SetAttribute("EnteredLevel", true)
	player:SetAttribute("Spectating", false)

	fade(player, "Out", FADE_OUT_TIME)

	tweenCartY(dreamBottomY, 2.2, Enum.EasingStyle.Linear, Enum.EasingDirection.In)

	smashCart()
	PodImpact:FireClient(player)
	print("[DreamPod] Cart smashed at dream floor")

	cartLocation = "Dream"
	traveling    = false
	DreamPodArrived:Fire(player, landingCFrame)

	local dreamX          = landingCFrame.Position.X
	local dreamZ          = landingCFrame.Position.Z
	local dreamFloorY     = landingCFrame.Position.Y + LANDING_CLEARANCE

	task.delay(POST_IMPACT_WAIT, function()
		print("[DreamPod] Spawning replacement cart at dream landing")
		traveling = true
		setAvailable(false)

		spawnReplacementCart(dreamFloorY, dreamX, dreamZ)

		cartLocation = "Dream"
		traveling    = false
		setAvailable(true)
		print("[DreamPod] Replacement cart ready in dream — awaiting passenger")
	end)

	waitUntilPlayerLeaves(player)
end

local function travelToLobby(player)
	if traveling then return end
	traveling = true
	setAvailable(false)
	print("[DreamPod] Returning", player.Name, "to vote area")

	fade(player, "In", FADE_IN_TIME)
	task.wait(FADE_IN_TIME)

	local lobbyY = lobbyBottomY or (stopHerePart.Position.Y + LANDING_CLEARANCE)
	local COSMETIC_DIP = 8
	teleportCart(lobbyY - COSMETIC_DIP, stopHerePart.Position.X, stopHerePart.Position.Z)
	snapPlayerToCart(player)

	player:SetAttribute("EnteredLevel", false)

	fade(player, "Out", FADE_OUT_TIME)
	tweenCartY(lobbyY, RETURN_RISE_TIME, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

	cartLocation = "StopHere"
	traveling    = false
	DreamPodReturned:Fire(player)

	waitUntilPlayerLeaves(player)
	setAvailable(dreamReady)
	print("[DreamPod] Pod available in lobby")
end

DreamPodReady.Event:Connect(function(payload)
	landingCFrame = payload and payload.LandingCFrame
		or ReplicatedStorage:GetAttribute("DreamPodLandingCFrame")

	if typeof(landingCFrame) ~= "CFrame" then
		warn("[DreamPod] DreamPodReady fired without a landing CFrame")
		dreamReady = false
		setAvailable(false)
		return
	end

	dreamReady = true
	moveCartByDeltaY(pitBottomY - getCartBottomY())
	raiseCartToStopHere()
	cartLocation = "StopHere"
	setAvailable(true)

	print(string.format("[DreamPod] Ready for dream '%s'",
		tostring(payload and payload.DreamName or ReplicatedStorage:GetAttribute("ActiveDreamName"))))
end)

task.defer(function()
	local existingLanding = ReplicatedStorage:GetAttribute("DreamPodLandingCFrame")
	if ReplicatedStorage:GetAttribute("GenDone") == true and typeof(existingLanding) == "CFrame" then
		landingCFrame = existingLanding
		dreamReady    = true
		moveCartByDeltaY(pitBottomY - getCartBottomY())
		raiseCartToStopHere()
		cartLocation = "StopHere"
		setAvailable(true)
		print("[DreamPod] Recovered existing generated dream state")
	end
end)

RunService.Heartbeat:Connect(function()
	if traveling or not available then
		occupantCandidate = nil
		occupantSince     = 0
		return
	end

	local occupant = getFirstOccupant()
	if not occupant then
		occupantCandidate = nil
		occupantSince     = 0
		return
	end

	if occupant ~= occupantCandidate then
		occupantCandidate = occupant
		occupantSince     = os.clock()
		return
	end

	if os.clock() - occupantSince < OCCUPANT_HOLD_TIME then return end
	occupantCandidate = nil
	occupantSince     = 0

	if cartLocation == "StopHere" then
		travelToDream(occupant)
	else
		travelToLobby(occupant)
	end
end)

print("[DreamPod] Controller ready")
