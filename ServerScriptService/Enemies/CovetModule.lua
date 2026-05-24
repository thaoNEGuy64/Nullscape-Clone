local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TakeDamageServer = ReplicatedStorage:WaitForChild("TakeDamageServer")

local DASH_DURATION = 1.2
local DASH_BREAK = 3
local HIT_COOLDOWN = 1.5
local HIT_DAMAGE = 50
local TOP_RAISE = 8
local DORMANT_POLL = 0.2
local WARNING_TIME = 0.45

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
			if activeName == "Dormant" then
				d.Enabled = false
				continue
			end
			local beamName = string.lower(d.Name)
			local parentName = d.Parent and string.lower(d.Parent.Name) or ""
			local isIdle = beamName == "idle" or parentName == "idle"
			local isAttack = beamName == "attack" or parentName == "attack"
			local isDash = beamName == "dash" or parentName == "dash"
			if isIdle then
				d.Enabled = true
			elseif isAttack then
				d.Enabled = (activeName == "Attack" or activeName == "AttackDash")
			elseif isDash then
				d.Enabled = (activeName == "Dash" or activeName == "AttackDash")
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

local function findDashAttachments(model)
	local atts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Attachment") and string.lower(d.Name) == "dash" then
			table.insert(atts, d)
		end
	end
	if #atts >= 2 then
		return atts[1], atts[2]
	end
	return nil, nil
end

local function setDashEndpoints(attA, attB, startPos, endPos)
	if not attA or not attB then return end
	attA.WorldPosition = startPos
	attB.WorldPosition = endPos
end

local function createEnemySound(root, soundTemplate)
	if not root or not soundTemplate or not soundTemplate:IsA("Sound") then return nil end
	local s = soundTemplate:Clone()
	s.Parent = root
	return s
end

local CovetServer = {}

local function anyPlayerEnteredLevel()
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("EnteredLevel") == true and p:GetAttribute("IsDead") ~= true then
			return true
		end
	end
	return false
end

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

	if root:IsA("BasePart") then root.Transparency = 0 end
	if top:IsA("BasePart") then top.Transparency = 0 end
	if hitbox:IsA("BasePart") then hitbox.Transparency = 1 end

	local dashA, dashB = findDashAttachments(model)
	local maxTelegraphLen = 120
	if dashA and dashB then
		maxTelegraphLen = math.max(6, (dashB.WorldPosition - dashA.WorldPosition).Magnitude)
	end

	local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
	local warningSound = soundsFolder and createEnemySound(root, soundsFolder:FindFirstChild("Covet Warning"))
	local dashSound = soundsFolder and createEnemySound(root, soundsFolder:FindFirstChild("Covet Dash"))

	local alive = true
	local dashing = false
	local lastHitAt = {}
	model:SetAttribute("Dormant", true)
	setBeamState(model, "Dormant")

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
		while alive and model.Parent and not anyPlayerEnteredLevel() do
			task.wait(DORMANT_POLL)
		end
		model:SetAttribute("Dormant", false)

		while alive and model.Parent do
			setBeamState(model, "Idle")
			top.CFrame = root.CFrame * CFrame.new(0, TOP_RAISE, 0)
			hitbox.CFrame = root.CFrame
			task.wait(0.2)

			local warningStart = os.clock()
			if warningSound then warningSound:Play() end
			local dashStartPos = root.Position
			local lockedDashDir = root.CFrame.LookVector
			local lockedDashLen = maxTelegraphLen
			local dashEndPos = dashStartPos + lockedDashDir * lockedDashLen
			while model.Parent and (os.clock() - warningStart) < WARNING_TIME do
				local dt = RunService.Heartbeat:Wait()
				dashStartPos = root.Position
				local targetPos = nearestPlayerPosition(dashStartPos) or (dashStartPos + root.CFrame.LookVector * maxTelegraphLen)
				local toTarget = targetPos - dashStartPos
				local targetLen = math.min(maxTelegraphLen, toTarget.Magnitude)
				if toTarget.Magnitude > 0.01 then
					lockedDashDir = toTarget.Unit
					lockedDashLen = targetLen
				end
				dashEndPos = dashStartPos + lockedDashDir * lockedDashLen
				model:PivotTo(CFrame.lookAt(root.Position, root.Position + lockedDashDir))
				local alphaWarn = math.clamp((os.clock() - warningStart) / WARNING_TIME, 0, 1)
				setBeamState(model, "Dash")
				setDashStretch(model, alphaWarn)
				local warningEnd = dashStartPos + lockedDashDir * (lockedDashLen * alphaWarn)
				setDashEndpoints(dashA, dashB, dashStartPos, warningEnd)
				if dt <= 0 then break end
			end

			dashing = true
			setBeamState(model, "AttackDash")
			if dashSound then dashSound:Play() end
			local startT = os.clock()
			local dashOrigin = root.Position
			local dashGoal = dashOrigin + lockedDashDir * lockedDashLen
			while model.Parent and (os.clock() - startT) < DASH_DURATION do
				RunService.Heartbeat:Wait()
				local elapsed = os.clock() - startT
				local alpha = math.clamp(elapsed / DASH_DURATION, 0, 1)
				local smoothAlpha = 0.5 - 0.5 * math.cos(math.pi * alpha)
				local distance = math.min(lockedDashLen, lockedDashLen * smoothAlpha)
				local nextPos = dashOrigin + lockedDashDir * distance
				local lookCF = CFrame.lookAt(nextPos, nextPos + lockedDashDir)
				model:PivotTo(lookCF)

				top.CFrame = root.CFrame * CFrame.new(0, TOP_RAISE, 0)
				hitbox.CFrame = root.CFrame
				setBeamState(model, "AttackDash")
				setDashStretch(model, alpha)
				setDashEndpoints(dashA, dashB, root.Position, dashGoal)
				if distance >= lockedDashLen then
					break
				end
			end
			dashing = false

			setBeamState(model, "Idle")
			setDashEndpoints(dashA, dashB, root.Position, root.Position)
			top.CFrame = root.CFrame * CFrame.new(0, TOP_RAISE, 0)
			hitbox.CFrame = root.CFrame
			task.wait(DASH_BREAK)
		end
	end)

	return model
end

return CovetServer
