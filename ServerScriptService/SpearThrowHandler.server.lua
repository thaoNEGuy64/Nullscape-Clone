-- SpearThrowHandler.server.lua
-- Server-authoritative spear throw/return behavior for the Spear weapon module.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local DAMAGE = 100
local THROW_SPEED = 165
local MIN_KNOCKBACK_SPEED = 550
local MAX_KNOCKBACK_SPEED = 2400
local KNOCKBACK_UP_BONUS = 120
local MAX_OUT_TIME = 10
local SLOWDOWN_TIME = 1.0
local RETURN_TIME = 0.85
local RETURN_ARC_HEIGHT = 22

local activeThrows = {}

local function getOrCreate(className, name, parent)
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA(className) then return existing end
	if existing then existing:Destroy() end
	local obj = Instance.new(className)
	obj.Name = name
	obj.Parent = parent
	return obj
end

local weaponRemotes = getOrCreate("Folder", "Weapon Remotes", ReplicatedStorage)
local spearRemotes = getOrCreate("Folder", "Spear", weaponRemotes)
local SpearAction = getOrCreate("RemoteEvent", "SpearAction", spearRemotes)

local function getSpearTemplate()
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local weapons = assets and assets:FindFirstChild("Weapons")
	local spearFolder = weapons and weapons:FindFirstChild("Spear")
	local spear = spearFolder and spearFolder:FindFirstChild("Spear")
	if spear and spear:IsA("BasePart") then return spear end
	return nil
end

local function cleanProjectileClone(projectile)
	for _, child in ipairs(projectile:GetDescendants()) do
		if child.Name == "Trigger" or child:IsA("ScreenGui") or child:IsA("BillboardGui") or child:IsA("SurfaceGui") then
			child:Destroy()
		end
	end
	projectile.Anchored = true
	projectile.CanCollide = false
	projectile.CanTouch = false
	projectile.CanQuery = false
end

local function addThrowTrail(projectile)
	local halfZ = math.max(projectile.Size.Z * 0.5, 0.5)
	local a0 = Instance.new("Attachment")
	a0.Name = "SpearTrailFront"
	a0.Position = Vector3.new(0, 0, -halfZ)
	a0.Parent = projectile

	local a1 = Instance.new("Attachment")
	a1.Name = "SpearTrailBack"
	a1.Position = Vector3.new(0, 0, halfZ)
	a1.Parent = projectile

	local trail = Instance.new("Trail")
	trail.Name = "SpearRedTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 30, 30), Color3.fromRGB(255, 130, 60))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.85
	trail.MinLength = 0.1
	trail.LightEmission = 1
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3.0),
		NumberSequenceKeypoint.new(1, 0),
	})
	trail.Parent = projectile
end

local function findHealthTarget(inst)
	local current = inst
	while current and current ~= Workspace do
		if current:GetAttribute("Health") ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function damageTarget(target)
	local hp = target and target:GetAttribute("Health")
	if type(hp) ~= "number" then return end
	target:SetAttribute("Health", math.max(0, hp - DAMAGE))
end

local function lookCFrame(pos, dir)
	if dir.Magnitude < 0.001 then dir = Vector3.new(0, 0, -1) end
	return CFrame.lookAt(pos, pos + dir.Unit)
end

local function spearCFrame(pos, dir, spinTime)
	return lookCFrame(pos, dir) * CFrame.Angles(0, 0, (spinTime or 0) * 28)
end

local function quadraticBezier(a, b, c, t)
	local ab = a:Lerp(b, t)
	local bc = b:Lerp(c, t)
	return ab:Lerp(bc, t)
end

local function returnSpear(player, projectile, fromPos)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		if projectile then projectile:Destroy() end
		activeThrows[player] = nil
		return
	end

	local startPos = fromPos
	local elapsed = 0
	local lastPos = startPos
	while elapsed < RETURN_TIME and projectile.Parent and player.Parent do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		local t = math.clamp(elapsed / RETURN_TIME, 0, 1)
		local endPos = hrp.Position + Vector3.new(0, 1.2, 0)
		local control = (startPos + endPos) * 0.5 + Vector3.new(0, RETURN_ARC_HEIGHT, 0)
		local pos = quadraticBezier(startPos, control, endPos, t)
		local dir = pos - lastPos
		projectile.CFrame = lookCFrame(pos, dir.Magnitude > 0.001 and dir or hrp.CFrame.LookVector)
		lastPos = pos
	end

	if projectile then projectile:Destroy() end
	activeThrows[player] = nil
	if player.Parent then
		SpearAction:FireClient(player, "Returned")
	end
end

local function throwSpear(player, lookVector, chargeAlpha)
	if activeThrows[player] then return end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	if typeof(lookVector) ~= "Vector3" or lookVector.Magnitude < 0.1 then
		lookVector = hrp.CFrame.LookVector
	end
	local dir = lookVector.Unit
	chargeAlpha = math.clamp(tonumber(chargeAlpha) or 0, 0, 1)
	local template = getSpearTemplate()
	if not template then
		warn("[SPEAR] Missing ReplicatedStorage/Assets/Weapons/Spear/Spear BasePart")
		SpearAction:FireClient(player, "Returned")
		return
	end

	local projectile = template:Clone()
	projectile.Name = "ThrownSpear"
	cleanProjectileClone(projectile)
	projectile.Transparency = math.min(projectile.Transparency, 0)
	addThrowTrail(projectile)
	projectile.Parent = Workspace
	local pos = hrp.Position + Vector3.new(0, 1.5, 0) + dir * 4
	projectile.CFrame = spearCFrame(pos, dir, 0)
	Debris:AddItem(projectile, MAX_OUT_TIME + SLOWDOWN_TIME + RETURN_TIME + 5)
	activeThrows[player] = projectile

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local airborne = humanoid and humanoid.FloorMaterial == Enum.Material.Air
	if airborne then
		local knockbackSpeed = MIN_KNOCKBACK_SPEED + (MAX_KNOCKBACK_SPEED - MIN_KNOCKBACK_SPEED) * chargeAlpha
		local impulse = (-dir * knockbackSpeed) + Vector3.new(0, KNOCKBACK_UP_BONUS * (0.35 + chargeAlpha), 0)
		hrp.AssemblyLinearVelocity += impulse
		SpearAction:FireClient(player, "Impulse", impulse)
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local raycastFilter = { char, projectile }
	params.FilterDescendantsInstances = raycastFilter

	local elapsed = 0
	local speed = THROW_SPEED
	local hitEnemies = {}
	local returning = false
	while projectile.Parent and player.Parent and not returning do
		local dt = RunService.Heartbeat:Wait()
		elapsed += dt
		if elapsed > MAX_OUT_TIME then
			local slowElapsed = 0
			while slowElapsed < SLOWDOWN_TIME and projectile.Parent do
				local slowDt = RunService.Heartbeat:Wait()
				slowElapsed += slowDt
				local alpha = math.clamp(slowElapsed / SLOWDOWN_TIME, 0, 1)
				speed = THROW_SPEED * (1 - alpha)
				pos += dir * speed * slowDt
				projectile.CFrame = spearCFrame(pos, dir, elapsed)
			end
			returning = true
			break
		end

		local step = dir * speed * dt
		local result = Workspace:Raycast(pos, step, params)
		if result then
			local target = findHealthTarget(result.Instance)
			if target then
				if not hitEnemies[target] then
					hitEnemies[target] = true
					damageTarget(target)
				end
				table.insert(raycastFilter, target)
				params.FilterDescendantsInstances = raycastFilter
				pos = result.Position + dir * 0.25
				projectile.CFrame = spearCFrame(pos, dir, elapsed)
			elseif result.Instance.CanCollide then
				pos = result.Position
				projectile.CFrame = spearCFrame(pos, dir, elapsed)
				returning = true
			else
				pos += step
				projectile.CFrame = spearCFrame(pos, dir, elapsed)
			end
		else
			pos += step
			projectile.CFrame = spearCFrame(pos, dir, elapsed)
		end
	end

	if projectile.Parent then
		returnSpear(player, projectile, pos)
	else
		activeThrows[player] = nil
		SpearAction:FireClient(player, "Returned")
	end
end

SpearAction.OnServerEvent:Connect(function(player, action, lookVector, chargeAlpha)
	if action == "Throw" then
		throwSpear(player, lookVector, chargeAlpha)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local projectile = activeThrows[player]
	if projectile then projectile:Destroy() end
	activeThrows[player] = nil
end)

print("[SPEAR] Throw handler ready")
