local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TakeDamageServer = ReplicatedStorage:WaitForChild("TakeDamageServer")

local DASH_DURATION = 3
local DASH_BREAK = 3
local HIT_COOLDOWN = 1.5
local HIT_DAMAGE = 50
local DASH_SPEED = 70
local TOP_RAISE = 8

local function nearestPlayerPosition(origin)
	local bestDist = math.huge
	local bestPos = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("IsDead") then continue end
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - origin).Magnitude
			if d < bestDist then
				bestDist = d
				bestPos = hrp.Position
			end
		end
	end
	return bestPos
end

local function setBeamState(model, activeName)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Beam") then
			if d.Name == "Idle" then
				d.Enabled = (activeName == "Idle")
			elseif d.Name == "Attack" then
				d.Enabled = (activeName == "Attack")
			elseif string.lower(d.Name) == "dash" then
				d.Enabled = (activeName == "Dash")
			end
		end
	end
end

local function setDashStretch(model, alpha)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Beam") and string.lower(d.Name) == "dash" then
			d.Width0 = 0.15 + alpha * 1.3
			d.Width1 = 0.15 + alpha * 1.3
		end
	end
end

local CovetServer = {}

function CovetServer.Spawn(position)
	local enemiesFolder = ReplicatedStorage:WaitForChild("Enemies")
	local covetTemplate = enemiesFolder:WaitForChild("Covet")
	local model = covetTemplate:Clone()
	model.Name = string.format("Covet_%d", math.random(1000, 9999))
	model.Parent = workspace

	local root = model:FindFirstChild("Part") or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local top = model:FindFirstChild("Top")
	local hitbox = model:FindFirstChild("Hitbox")
	if not root or not top or not hitbox then
		warn("[Covet] Missing Part/Top/Hitbox")
		model:Destroy()
		return nil
	end

	if model:IsA("Model") then
		model.PrimaryPart = root
		model:PivotTo(CFrame.new(position))
	else
		root.CFrame = CFrame.new(position)
	end

	local alive = true
	local dashing = false
	local lastHitAt = {}

	hitbox.Touched:Connect(function(other)
		if not alive or not dashing then return end
		local char = other and other.Parent
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		local t = os.clock()
		local last = lastHitAt[player.UserId] or 0
		if t - last < HIT_COOLDOWN then return end
		lastHitAt[player.UserId] = t
		TakeDamageServer:Fire(player, HIT_DAMAGE, "Covet")
	end)

	task.spawn(function()
		while alive and model.Parent do
			setBeamState(model, "Idle")
			top.CFrame = root.CFrame * CFrame.new(0, 0, 0)
			hitbox.CFrame = root.CFrame
			task.wait(0.2)

			dashing = true
			setBeamState(model, "Attack")
			local startT = os.clock()
			while model.Parent and (os.clock() - startT) < DASH_DURATION do
				local dt = RunService.Heartbeat:Wait()
				local targetPos = nearestPlayerPosition(root.Position) or (root.Position + root.CFrame.LookVector * 20)
				local moveDir = targetPos - root.Position
				moveDir = Vector3.new(moveDir.X, 0, moveDir.Z)
				if moveDir.Magnitude > 0.01 then
					moveDir = moveDir.Unit
					local nextPos = root.Position + moveDir * DASH_SPEED * dt
					local lookCF = CFrame.lookAt(nextPos, nextPos + moveDir)
					model:PivotTo(lookCF)
				end
				top.CFrame = root.CFrame * CFrame.new(0, TOP_RAISE, 0)
				hitbox.CFrame = root.CFrame * CFrame.new(0, TOP_RAISE * 0.5, 0)
				setBeamState(model, "Dash")
				setDashStretch(model, (os.clock() - startT) / DASH_DURATION)
			end
			dashing = false

			setBeamState(model, "Idle")
			top.CFrame = root.CFrame
			hitbox.CFrame = root.CFrame
			task.wait(DASH_BREAK)
		end
	end)

	return model
end

return CovetServer
