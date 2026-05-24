-- ShadeModule.lua
-- ServerScriptService/Enemies
-- Arena-friendly Shade enemy module. Does not auto-spawn; callers choose when
-- and where to spawn Shades (arena controller, debug tools, etc.).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local TakeDamageServer = ReplicatedStorage:WaitForChild("TakeDamageServer")

local MAX_HEALTH = 50
local MAX_SPEED = 9
local ACCEL = 3.5
local FRICTION = 2.5
local CIRCLE_SPEED = 5
local STOP_DISTANCE = 5.0
local PUNCH_DISTANCE = 3.5
local PUNCH_PULL_TIME = 0.7
local PUNCH_HIT_HOLD = 0.9
local PUNCH_DAMAGE = 20
local SHADE_GLOBAL_HIT_COOLDOWN = 0.2
local PUNCH_COOLDOWN = 0.8
local BACKPEDAL_SPEED = 4
local BACKPEDAL_TIME = 0.6
local CIRCLE_TIME_MIN = 1.2
local CIRCLE_TIME_MAX = 2.5
local FAKE_CHANCE = 0.2
local FAKE_DURATION = 0.3
local DETECTION_RADIUS = 50
local PROXIMITY_RADIUS = 10
local UPDATE_RATE = 1 / 60

local nextId = 0
local lastShadeHitByUserId = {}
local Shade = {}

local function getTemplate()
	local simple = ReplicatedStorage:FindFirstChild("EnemySimple")
	local template = simple and simple:FindFirstChild("Shade")
	if template then return template end

	local enemies = ReplicatedStorage:FindFirstChild("Enemies")
	local shadeFolder = enemies and enemies:FindFirstChild("Shade")
	return shadeFolder and (shadeFolder:FindFirstChild("Shade") or shadeFolder:FindFirstChildWhichIsA("BasePart"))
end

local function getSpawnCFrame(position)
	if typeof(position) == "CFrame" then return position end
	if typeof(position) == "Vector3" then return CFrame.new(position) end
	return CFrame.new(0, 8, 0)
end

local function getSpawnPart(template)
	if template:IsA("BasePart") then return template:Clone() end
	if template:IsA("Model") then
		local clone = template:Clone()
		local part = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
		if not part then clone:Destroy(); return nil end
		part.Parent = nil
		clone:Destroy()
		return part
	end
	return nil
end

function Shade.Spawn(position, options)
	options = options or {}
	local template = getTemplate()
	if not template then
		warn("[ShadeModule] Missing Shade template at ReplicatedStorage.EnemySimple.Shade or ReplicatedStorage.Enemies.Shade")
		return nil
	end

	local enemy = getSpawnPart(template)
	if not enemy then
		warn("[ShadeModule] Shade template needs a BasePart enemy root")
		return nil
	end
	enemy.Size = Vector3.new(4, 4, 0.001)

	nextId += 1
	enemy.Name = options.Name or string.format("Shade_%d", nextId)
	enemy.Anchored = true
	enemy.CanCollide = false
	enemy.CanQuery = true
	local finalCFrame = getSpawnCFrame(position) + Vector3.new(0, enemy.Size.Y * 0.5, 0)
	local entranceOffset = options.EntranceFromBelow and (options.EntranceOffset or 10) or 0
	enemy.CFrame = finalCFrame * CFrame.new(0, -entranceOffset, 0)
	enemy.Parent = options.Parent or Workspace

	local pos = enemy.Position
	local finalPos = finalCFrame.Position
	local entranceDone = entranceOffset <= 0
	local posValue = enemy:FindFirstChild("WorldPos") or Instance.new("Vector3Value")
	posValue.Name = "WorldPos"
	posValue.Value = pos
	posValue.Parent = enemy

	enemy:SetAttribute("State", entranceDone and "Idle" or "Spawn")
	enemy:SetAttribute("Agitated", false)
	enemy:SetAttribute("FacingX", 0)
	enemy:SetAttribute("FacingZ", 1)
	enemy:SetAttribute("Health", options.Health or MAX_HEALTH)
	enemy:SetAttribute("ArenaId", options.ArenaId)

	local alive = true
	local vel = Vector3.new(0, 0, 0)
	local noiseT = 0
	local behaviourState = "Idle"
	local circleDir = 1
	local circleTimer = 0
	local isPunching = false
	local accumulator = 0
	local hbConn
	local diedConn

	local function cleanup()
		if hbConn then hbConn:Disconnect(); hbConn = nil end
		if diedConn then diedConn:Disconnect(); diedConn = nil end
	end

	local function setState(s)
		if enemy and enemy.Parent then enemy:SetAttribute("State", s) end
	end

	local function getClosestPlayer()
		if not alive then return nil end
		local closest, closestDist = nil, math.huge
		for _, p in ipairs(options.TargetPlayers or Players:GetPlayers()) do
			if p:GetAttribute("IsDead") then continue end
			local char = p.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - pos).Magnitude
				if d < closestDist then closestDist = d; closest = { player = p, hrp = hrp, dist = d } end
			end
		end
		return closest
	end

	local function hasLOS(targetPos)
		local origin = pos + Vector3.new(0, enemy.Size.Y * 0.4, 0)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { enemy }
		local dir = targetPos - origin
		local result = Workspace:Raycast(origin, dir, params)
		return (not result) or (result.Position - origin).Magnitude >= dir.Magnitude * 0.9
	end

	local function isAgitated(target)
		if not target then return false end
		if target.dist <= PROXIMITY_RADIUS then return true end
		if target.dist <= DETECTION_RADIUS then return hasLOS(target.hrp.Position) end
		return false
	end

	local function applyVelocity(desiredDir, speed, dt)
		local desired = desiredDir.Magnitude > 0.01 and desiredDir.Unit * speed or Vector3.new(0, 0, 0)
		vel = vel:Lerp(desired, math.clamp(ACCEL * dt, 0, 1))
		if desiredDir.Magnitude < 0.01 then
			vel = vel:Lerp(Vector3.new(0, 0, 0), math.clamp(FRICTION * dt, 0, 1))
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
		return math.sin(noiseT * 1.3) * 0.15 + math.sin(noiseT * 2.9) * 0.08 + math.sin(noiseT * 0.55) * 0.07
	end

	local function die()
		if not alive then return end
		alive = false
		setState("Dead")
		cleanup()
		if type(options.OnDied) == "function" then task.spawn(options.OnDied, enemy) end
		if options.DestroyOnDeath ~= false then
			task.delay(options.DeathCleanupDelay or 1.5, function()
				if enemy and enemy.Parent then enemy:Destroy() end
			end)
		end
	end

	diedConn = enemy:GetAttributeChangedSignal("Health"):Connect(function()
		local hp = enemy:GetAttribute("Health")
		if hp and hp <= 0 then die() end
	end)
	enemy.Destroying:Once(cleanup)

	if not entranceDone then
		task.spawn(function()
			local duration = options.EntranceDuration or 0.55
			local startPos = pos
			local elapsed = 0
			local jumpHeight = options.EntranceJumpHeight or 4
			while alive and enemy.Parent and elapsed < duration do
				elapsed += RunService.Heartbeat:Wait()
				local alpha = math.clamp(elapsed / duration, 0, 1)
				local rise = 1 - (1 - alpha) * (1 - alpha)
				local arc = math.sin(alpha * math.pi) * jumpHeight
				pos = startPos:Lerp(finalPos, rise) + Vector3.new(0, arc, 0)
				posValue.Value = pos
				enemy.CFrame = CFrame.new(pos)
			end
			pos = finalPos
			posValue.Value = pos
			if enemy and enemy.Parent then
				enemy.CFrame = finalCFrame
				enemy:SetAttribute("State", "Idle")
			end
			entranceDone = true
		end)
	end

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
			local now = os.clock()
			local lastHit = lastShadeHitByUserId[targetPlayer.UserId] or 0
			if now - lastHit >= SHADE_GLOBAL_HIT_COOLDOWN then
				lastShadeHitByUserId[targetPlayer.UserId] = now
				TakeDamageServer:Fire(targetPlayer, PUNCH_DAMAGE, "Shade")
			end
		end
		task.wait(PUNCH_HIT_HOLD)
		if not alive then isPunching = false; return end
		setState("Walk")
		local backDir = Vector3.new(-(enemy:GetAttribute("FacingX") or 0), 0, -(enemy:GetAttribute("FacingZ") or 1))
		if backDir.Magnitude < 0.01 then backDir = Vector3.new(0, 0, 1) end
		local elapsed = 0
		while elapsed < BACKPEDAL_TIME do
			local dt = task.wait()
			elapsed += dt
			applyVelocity(backDir.Unit, BACKPEDAL_SPEED, dt)
		end
		setState("Idle")
		task.wait(PUNCH_COOLDOWN)
		isPunching = false
		behaviourState = "Sprint"
	end

	hbConn = RunService.Heartbeat:Connect(function(dt)
		if not alive or isPunching or not enemy.Parent or not entranceDone then return end
		accumulator += dt
		if accumulator < UPDATE_RATE then return end
		local stepDt = accumulator
		accumulator = 0

		local target = getClosestPlayer()
		local agitated = isAgitated(target)
		enemy:SetAttribute("Agitated", agitated)
		if not agitated or not target then
			behaviourState = "Idle"
			setState("Idle")
			applyVelocity(Vector3.new(0, 0, 0), 0, stepDt)
			return
		end

		local toTarget = target.hrp.Position - pos
		toTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
		local dist = toTarget.Magnitude
		local forward = dist > 0.01 and toTarget.Unit or Vector3.new(0, 0, 1)
		if behaviourState == "Idle" then behaviourState = "Sprint" end
		if behaviourState == "Sprint" then
			if dist <= STOP_DISTANCE then
				circleDir = math.random(2) == 1 and 1 or -1
				circleTimer = CIRCLE_TIME_MIN + math.random() * (CIRCLE_TIME_MAX - CIRCLE_TIME_MIN)
				behaviourState = "Circle"
			else
				local right = Vector3.new(-forward.Z, 0, forward.X)
				setState("Walk")
				applyVelocity(forward + right * driftNoise(), MAX_SPEED, stepDt)
			end
		elseif behaviourState == "Circle" then
			circleTimer -= stepDt
			local right = Vector3.new(-forward.Z, 0, forward.X) * circleDir
			if math.random() < FAKE_CHANCE * stepDt then
				task.spawn(function()
					local e = 0
					while e < FAKE_DURATION do
						local d = task.wait()
						e += d
						if not alive then return end
						local tp = getClosestPlayer(); if not tp then break end
						local tf = tp.hrp.Position - pos
						applyVelocity(Vector3.new(tf.X, 0, tf.Z), MAX_SPEED * 1.4, d)
					end
				end)
			else
				setState("Walk")
				applyVelocity(right + forward * 0.4, CIRCLE_SPEED, stepDt)
			end
			if dist > STOP_DISTANCE * 1.8 then behaviourState = "Sprint" end
			if dist <= PUNCH_DISTANCE or circleTimer <= 0 then task.spawn(doPunch, target.player) end
		end
	end)

	return {
		Part = enemy,
		Destroy = function()
			alive = false
			cleanup()
			if enemy and enemy.Parent then enemy:Destroy() end
		end,
		IsAlive = function()
			return alive and enemy.Parent ~= nil
		end,
	}
end

return Shade
