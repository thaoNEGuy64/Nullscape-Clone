-- ShadeServer.server.lua
-- ServerScriptService

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local RunService        = game:GetService("RunService")

local TakeDamageServer = ReplicatedStorage:WaitForChild("TakeDamageServer")

-- ── Config ────────────────────────────────────────────────────
local MAX_HEALTH       = 50
local MAX_SPEED        = 9
local ACCEL            = 3.5
local FRICTION         = 2.5
local CIRCLE_SPEED     = 5
local STOP_DISTANCE    = 5.0
local PUNCH_DISTANCE   = 3.5
local PUNCH_PULL_TIME  = 0.7
local PUNCH_HIT_HOLD   = 0.9
local PUNCH_DAMAGE     = 20
local PUNCH_COOLDOWN   = 0.8
local BACKPEDAL_SPEED  = 4
local BACKPEDAL_TIME   = 0.6
local CIRCLE_TIME_MIN  = 1.2
local CIRCLE_TIME_MAX  = 2.5
local FAKE_CHANCE      = 0.2
local FAKE_DURATION    = 0.3
local DETECTION_RADIUS = 50
local PROXIMITY_RADIUS = 10
local UPDATE_RATE      = 1/60

-- ── Setup ─────────────────────────────────────────────────────
local enemyTemplate = ReplicatedStorage:WaitForChild("EnemySimple"):WaitForChild("Shade")
local spawnPart     = Workspace:WaitForChild("SpawnShade")

local enemy = enemyTemplate:Clone()
enemy.Anchored   = true
enemy.CanCollide = false
enemy.CanQuery   = true
enemy.CFrame     = spawnPart.CFrame + Vector3.new(0, enemy.Size.Y * 0.5, 0)
enemy.Parent     = Workspace
enemy.Name       = "Shade_1"

local pos = enemy.Position

local posValue      = Instance.new("Vector3Value")
posValue.Name       = "WorldPos"
posValue.Value      = pos
posValue.Parent     = enemy

enemy:SetAttribute("State",    "Idle")
enemy:SetAttribute("Agitated", false)
enemy:SetAttribute("FacingX",  0)
enemy:SetAttribute("FacingZ",  1)
enemy:SetAttribute("Health",   MAX_HEALTH)

local alive = true
enemy:GetAttributeChangedSignal("Health"):Connect(function()
	local hp = enemy:GetAttribute("Health")
	if hp and hp <= 0 and alive then
		alive = false
		enemy:SetAttribute("State", "Dead")
	end
end)

local function getClosestPlayer()
	if not alive then return nil end
	local closest = nil; local closestDist = math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("IsDead") then continue end
		local char = p.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - pos).Magnitude
			if d < closestDist then closestDist = d; closest = {player=p, hrp=hrp, dist=d} end
		end
	end
	return closest
end

local function hasLOS(targetPos)
	local origin = pos + Vector3.new(0, enemy.Size.Y * 0.4, 0)
	local dir    = targetPos - origin
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { enemy }
	local result = Workspace:Raycast(origin, dir, params)
	if not result then return true end
	return (result.Position - origin).Magnitude >= dir.Magnitude * 0.9
end

local function isAgitated(target)
	if not target then return false end
	if target.dist <= PROXIMITY_RADIUS then return true end
	if target.dist <= DETECTION_RADIUS then return hasLOS(target.hrp.Position) end
	return false
end

local function setState(s) enemy:SetAttribute("State", s) end

local vel = Vector3.new(0, 0, 0)
local noiseT = 0

local function applyVelocity(desiredDir, speed, dt)
	local desired = desiredDir.Magnitude > 0.01 and desiredDir.Unit * speed or Vector3.new(0, 0, 0)
	vel = vel:Lerp(desired, math.clamp(ACCEL * dt, 0, 1))
	if desiredDir.Magnitude < 0.01 then
		vel = vel:Lerp(Vector3.new(0,0,0), math.clamp(FRICTION * dt, 0, 1))
	end
	local newPos = pos + vel * dt
	pos = Vector3.new(newPos.X, pos.Y, newPos.Z)
	posValue.Value = pos
	if vel.Magnitude > 0.5 then
		enemy:SetAttribute("FacingX", vel.Unit.X)
		enemy:SetAttribute("FacingZ", vel.Unit.Z)
	end
end

local function driftNoise()
	noiseT += 0.016
	return math.sin(noiseT * 1.3)  * 0.15 + math.sin(noiseT * 2.9)  * 0.08 + math.sin(noiseT * 0.55) * 0.07
end

local behaviourState = "Idle"
local circleDir = 1
local circleTimer = 0
local isPunching = false

local function doPunch(targetPlayer)
	if not alive then return end
	isPunching = true
	behaviourState = "Punching"
	vel = Vector3.new(0, 0, 0)

	setState("PunchPull")
	task.wait(PUNCH_PULL_TIME)
	if not alive then isPunching = false; return end

	setState("Punch")
	if targetPlayer then
		TakeDamageServer:Fire(targetPlayer, PUNCH_DAMAGE, "Shade")
	end

	task.wait(PUNCH_HIT_HOLD)
	if not alive then isPunching = false; return end

	setState("Walk")
	local backDir = Vector3.new(-enemy:GetAttribute("FacingX"), 0, -enemy:GetAttribute("FacingZ"))
	if backDir.Magnitude < 0.01 then backDir = Vector3.new(0,0,1) end
	backDir = backDir.Unit

	local elapsed = 0
	while elapsed < BACKPEDAL_TIME do
		local dt = task.wait(); elapsed += dt
		applyVelocity(backDir, BACKPEDAL_SPEED, dt)
	end

	setState("Idle")
	task.wait(PUNCH_COOLDOWN)
	isPunching = false
	behaviourState = "Sprint"
end

local accumulator = 0
RunService.Heartbeat:Connect(function(dt)
	if not alive or isPunching then return end
	accumulator += dt
	if accumulator < UPDATE_RATE then return end
	local stepDt = accumulator; accumulator = 0

	local target = getClosestPlayer()
	local agitated = isAgitated(target)
	enemy:SetAttribute("Agitated", agitated)

	if not agitated or not target then
		behaviourState = "Idle"
		setState("Idle")
		applyVelocity(Vector3.new(0,0,0), 0, stepDt)
		return
	end

	local hrp = target.hrp
	local toTarget = hrp.Position - pos
	toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
	local dist = toTarget.Magnitude
	local forward = dist > 0.01 and toTarget.Unit or Vector3.new(0,0,1)

	if behaviourState == "Idle" then behaviourState = "Sprint" end
	if behaviourState == "Sprint" then
		if dist <= STOP_DISTANCE then
			circleDir = math.random(2) == 1 and 1 or -1
			circleTimer = CIRCLE_TIME_MIN + math.random()*(CIRCLE_TIME_MAX-CIRCLE_TIME_MIN)
			behaviourState = "Circle"
		else
			local right = Vector3.new(-forward.Z, 0, forward.X)
			local dir = forward + right * driftNoise()
			setState("Walk")
			applyVelocity(dir, MAX_SPEED, stepDt)
		end
	elseif behaviourState == "Circle" then
		circleTimer -= stepDt
		local right = Vector3.new(-forward.Z, 0, forward.X) * circleDir
		local inward = forward * 0.4
		local dir = right + inward

		if math.random() < FAKE_CHANCE * stepDt then
			task.spawn(function()
				local e = 0
				while e < FAKE_DURATION do
					local d = task.wait(); e += d
					if not alive then return end
					local tp = getClosestPlayer(); if not tp then break end
					local tf = tp.hrp.Position - pos
					tf = Vector3.new(tf.X, 0, tf.Z)
					applyVelocity(tf, MAX_SPEED * 1.4, d)
				end
			end)
		else
			setState("Walk")
			applyVelocity(dir, CIRCLE_SPEED, stepDt)
		end

		if dist > STOP_DISTANCE * 1.8 then behaviourState = "Sprint" end
		if dist <= PUNCH_DISTANCE or circleTimer <= 0 then
			task.spawn(doPunch, target.player)
		end
	end
end)
