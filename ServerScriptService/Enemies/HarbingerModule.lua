local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local TakeDamageServer = ReplicatedStorage:WaitForChild("TakeDamageServer")

local SEGMENT_SPACING = 5
local HISTORY_STEP = 0.035
local BODY_HIT_DAMAGE = 24
local HEAD_HIT_DAMAGE = 100
local HIT_COOLDOWN = 0.8
local BASE_SPEED = 24
local HUNT_SPEED_BONUS = 22
local STALK_DISTANCE = 45
local SWIPE_DISTANCE = 55
local SWEEP_REACH = 70
local TOP_RAISE = 8
local TOP_EXTRA_RAISE = 12
local FACE_HEIGHT_OFFSET = -10
local MAX_TURN_RATE = math.rad(140)
local MIN_TURN_RATE = math.rad(45)
local AGGRO_GAIN_PER_SEC = 5
local HUNT_AGGRO_GAIN_PER_SEC = 50
local HUNT_AGGRO_DECAY_PER_SEC = 25
local PROXIMITY_RANGE = 32
local ACTIVATE_DELAY_AFTER_ENTRY = 5

local ENTRANCE_FLASH_COUNT = 4
local ENTRANCE_FLASH_INTERVAL = 0.18
local ENTRANCE_SPAWN_DISTANCE = 100
local SEGMENT_FADE_DELAY = 0.25
local SEGMENT_FADE_TIME = 0.6
local ENTRANCE_RUMBLE_TIME = 2
local FAR_DISTANCE_BOOST_START = 500
local FAR_DISTANCE_SPEED_MULT = 2.8

local HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(220, 60, 60)
local HIGHLIGHT_ENTRANCE_COLOR = Color3.fromRGB(255, 0, 0)
local HIGHLIGHT_FILL_COLOR = Color3.fromRGB(0, 0, 0)

local function clamp01(v)
	return math.clamp(v, 0, 1)
end

local function anyPlayerEnteredLevel()
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("EnteredLevel") == true and p:GetAttribute("IsDead") ~= true then
			return true
		end
	end
	return false
end

local function findNearestPlayer(origin)
	local nearestPlayer, nearestRoot
	local best = math.huge
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("IsDead") then continue end
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local d = (hrp.Position - origin).Magnitude
			if d < best then
				best = d
				nearestPlayer = p
				nearestRoot = hrp
			end
		end
	end
	return nearestPlayer, nearestRoot, best
end

local function horizontalUnit(v)
	local flat = Vector3.new(v.X, 0, v.Z)
	if flat.Magnitude < 1e-4 then return nil end
	return flat.Unit
end

local function getTemplate(enemiesFolder)
	return enemiesFolder:FindFirstChild("harbringer") or enemiesFolder:FindFirstChild("Harbringer") or enemiesFolder:FindFirstChild("Harbinger")
end

local function gatherSegments(model)
	local segments = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			local idx = tonumber(string.lower(inst.Name):match("seg(%d+)"))
			if idx then
				table.insert(segments, { part = inst, idx = idx })
			end
		end
	end
	table.sort(segments, function(a, b) return a.idx < b.idx end)
	return segments
end

local function setFaceBeamState(faceModel, active)
	for _, inst in ipairs(faceModel:GetDescendants()) do
		if inst:IsA("Beam") and string.lower(inst.Name) == "harbringer" then
			inst.Enabled = active
		end
	end
end

local function createHighlight(adornee, parent)
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.25
	h.FillColor = HIGHLIGHT_FILL_COLOR
	h.OutlineTransparency = 0
	h.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
	h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	h.Adornee = adornee
	h.Parent = parent
	return h
end

local Harbinger = {}

function Harbinger.Spawn(position)
	local enemiesFolder = ReplicatedStorage:WaitForChild("Enemies")
	local template = getTemplate(enemiesFolder)
	if not template then
		warn("[Harbinger] Missing model.")
		return nil
	end

	local model = template:Clone()
	model.Name = string.format("Harbinger_%d", math.random(1000, 9999))
	model.Parent = workspace

	local face = model:FindFirstChild("face") or model:FindFirstChild("Face")
	if not face or not face:IsA("Model") then
		warn("[Harbinger] Missing face model")
		model:Destroy()
		return nil
	end

	local root = face:FindFirstChild("Part") or face.PrimaryPart or face:FindFirstChildWhichIsA("BasePart")
	local top = face:FindFirstChild("Top")
	local headHitbox = face:FindFirstChild("Hitbox")
	if not root or not top or not headHitbox then
		warn("[Harbinger] face needs Part/Top/Hitbox")
		model:Destroy()
		return nil
	end

	face.PrimaryPart = root
	face:PivotTo(CFrame.new(position))

	root.Transparency = 1
	top.Transparency = 1
	headHitbox.Transparency = 0.99
	headHitbox.Color = Color3.fromRGB(0, 0, 0)
	headHitbox.Material = Enum.Material.SmoothPlastic

	local excludeParts = { [root] = true, [top] = true, [headHitbox] = true }
	local faceVisuals = {}
	for _, inst in ipairs(face:GetDescendants()) do
		if inst:IsA("BasePart") and not excludeParts[inst] then
			table.insert(faceVisuals, { part = inst, origColor = inst.Color, origTransparency = inst.Transparency })
		end
	end

	setFaceBeamState(face, false)

	local segments = gatherSegments(model)
	local segOrigTransparency = {}
	for _, seg in ipairs(segments) do
		seg.part.Anchored = true
		seg.part.CanCollide = false
		segOrigTransparency[seg.part] = seg.part.Transparency
		seg.part.Transparency = 1
	end

	local highlight = createHighlight(headHitbox, model)
	highlight.Enabled = true

	local alive = true
	local entranceDone = false
	local aggression = 0
	local huntAggro = 0
	local mode = "Stalk"
	local modeTimer = 4
	local heading = horizontalUnit(root.CFrame.LookVector) or Vector3.new(0, 0, -1)
	local histTimer = 0
	local history = {}
	local maxHistory = math.max(80, (#segments + 4) * 8)
	local playerHitCd = {}
	local sweepAnchor = nil
	local headAnchor = position

	model:SetAttribute("Dormant", true)
	model:SetAttribute("Aggression", aggression)
	model:SetAttribute("HuntAggro", huntAggro)
	model:SetAttribute("Mode", mode)

	local function dealDamage(player, amount, source)
		local now = os.clock()
		local last = playerHitCd[player.UserId] or 0
		if now - last < HIT_COOLDOWN then return end
		playerHitCd[player.UserId] = now
		TakeDamageServer:Fire(player, amount, source)
	end

	headHitbox.Touched:Connect(function(other)
		if not alive or not entranceDone then return end
		local char = other and other.Parent
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local player = Players:GetPlayerFromCharacter(char)
		if not player then return end
		dealDamage(player, HEAD_HIT_DAMAGE, "Harbinger Head")
	end)

	for _, seg in ipairs(segments) do
		seg.part.Touched:Connect(function(other)
			if not alive or not entranceDone then return end
			local char = other and other.Parent
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if not hum or not hrp then return end
			local player = Players:GetPlayerFromCharacter(char)
			if not player then return end
			dealDamage(player, BODY_HIT_DAMAGE, "Harbinger Body")
			local away = horizontalUnit(hrp.Position - seg.part.Position) or heading
			hrp.AssemblyLinearVelocity = away * 55 + Vector3.new(0, 30, 0)
		end)
	end

	task.spawn(function()
		while alive and model.Parent and not anyPlayerEnteredLevel() do
			task.wait(0.2)
		end
		task.wait(ACTIVATE_DELAY_AFTER_ENTRY)
		if not alive or not model.Parent then return end

		local _, nearestRoot = findNearestPlayer(position)
			local spawnPos = position
			if nearestRoot then
				local look = horizontalUnit(nearestRoot.CFrame.LookVector) or Vector3.new(0, 0, -1)
				spawnPos = nearestRoot.Position + look * ENTRANCE_SPAWN_DISTANCE
			end
		headAnchor = spawnPos
		face:PivotTo(CFrame.new(spawnPos))
		model:SetAttribute("Dormant", false)

		local ok = pcall(function()
			for _ = 1, ENTRANCE_FLASH_COUNT do
				for _, v in ipairs(faceVisuals) do
					v.part.Color = Color3.fromRGB(200, 0, 0)
				end
				highlight.OutlineColor = HIGHLIGHT_ENTRANCE_COLOR
				task.wait(ENTRANCE_FLASH_INTERVAL)
				for _, v in ipairs(faceVisuals) do
					v.part.Color = v.origColor
				end
				highlight.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
				task.wait(ENTRANCE_FLASH_INTERVAL)
			end
		end)
		if not ok then
			warn("[Harbinger] Entrance flash error")
		end

			root.Transparency = 0
			top.Transparency = 1
			setFaceBeamState(face, true)
			entranceDone = true
			local rumbleStart = os.clock()
			while alive and model.Parent and (os.clock() - rumbleStart) < ENTRANCE_RUMBLE_TIME do
				local shake = Vector3.new((math.random() - 0.5) * 2, 0, (math.random() - 0.5) * 2)
				local p = face:GetPivot().Position + shake
				face:PivotTo(CFrame.lookAt(p, p + heading))
				task.wait(0.04)
			end

			for i, seg in ipairs(segments) do
			task.delay(i * SEGMENT_FADE_DELAY, function()
				if not alive then return end
				local original = segOrigTransparency[seg.part] or 0
				local elapsed = 0
				while elapsed < SEGMENT_FADE_TIME and alive do
					elapsed += RunService.Heartbeat:Wait()
					seg.part.Transparency = 1 - clamp01(elapsed / SEGMENT_FADE_TIME) * (1 - original)
				end
				seg.part.Transparency = original
			end)
		end
	end)

	task.spawn(function()
		while alive and model.Parent do
			local dt = RunService.Heartbeat:Wait()
			if not entranceDone then
				continue
			end

			local _, playerRoot, playerDist = findNearestPlayer(headAnchor)
			if not playerRoot then
				mode = "Stalk"
				model:SetAttribute("Mode", mode)
				continue
			end

			aggression = math.min(100, aggression + AGGRO_GAIN_PER_SEC * dt)
			model:SetAttribute("Aggression", aggression)
			if playerDist <= PROXIMITY_RANGE then
				huntAggro = math.min(100, huntAggro + HUNT_AGGRO_GAIN_PER_SEC * dt)
			else
				huntAggro = math.max(0, huntAggro - HUNT_AGGRO_DECAY_PER_SEC * dt)
			end
			model:SetAttribute("HuntAggro", huntAggro)

			modeTimer -= dt
			if mode == "Hunt" and huntAggro >= 100 then
				mode = "Stalk"
				modeTimer = 4
				huntAggro = 0
				sweepAnchor = nil
				model:SetAttribute("HuntAggro", huntAggro)
			elseif modeTimer <= 0 then
				local roll = math.random()
				local huntBias = clamp01(0.22 + aggression / 120)
				if roll < huntBias then mode = "Hunt"; modeTimer = 3.6
				elseif roll < 0.70 then mode = "Block"; modeTimer = 2.2
				else mode = "Stalk"; modeTimer = 3.2 end
				sweepAnchor = nil
			end
			model:SetAttribute("Mode", mode)

			local playerPos = playerRoot.Position
			local myPos = headAnchor
			local toPlayerFlat = horizontalUnit(playerPos - myPos) or heading
			local sideDir = toPlayerFlat:Cross(Vector3.yAxis)
			local torsoAim = playerPos + Vector3.new(0, 1.8, 0)

			local desired3
			if mode == "Stalk" then
				local hoverY = playerPos.Y + 12 + 4 * math.sin(os.clock() * 1.6)
				local behindTarget = Vector3.new(playerPos.X, hoverY, playerPos.Z) - toPlayerFlat * STALK_DISTANCE
				desired3 = behindTarget - myPos
			elseif mode == "Block" then
				local swipeSign = (math.sin(os.clock() * 1.2) >= 0) and 1 or -1
				local swipeTarget = torsoAim + sideDir * SWIPE_DISTANCE * swipeSign + Vector3.new(0, 6, 0)
				desired3 = swipeTarget - myPos
			else
				if not sweepAnchor then
					local sign = math.random(0, 1) == 0 and -1 or 1
					sweepAnchor = torsoAim + sideDir * sign * SWEEP_REACH + Vector3.new(0, 4, 0)
				end
				local sweepDir = sweepAnchor - torsoAim
				if sweepDir.Magnitude < 0.01 then sweepDir = sideDir * SWEEP_REACH end
				local throughTarget = torsoAim - sweepDir.Unit * SWEEP_REACH * 0.75
				local target = ((sweepAnchor - myPos).Magnitude > 11) and sweepAnchor or throughTarget
				if (throughTarget - myPos).Magnitude < 10 then sweepAnchor = nil end
				desired3 = target - myPos
			end

				local desiredFlat = horizontalUnit(desired3) or heading
				local speed = BASE_SPEED + (aggression * 0.2) + (mode == "Hunt" and HUNT_SPEED_BONUS or 0)
				local farDistance = (playerPos - myPos).Magnitude
				if farDistance > FAR_DISTANCE_BOOST_START then
					speed *= FAR_DISTANCE_SPEED_MULT
				end
				local turnRate = MIN_TURN_RATE + (MAX_TURN_RATE - MIN_TURN_RATE) * clamp01(1 - speed / 80)
				local t = clamp01(turnRate * dt)
				heading = (heading:Lerp(desiredFlat, t)).Unit

				local verticalStep = math.clamp(desired3.Y, -16, 16) * dt * 0.8
				local slitherSide = heading:Cross(Vector3.yAxis)
				local slither = slitherSide * math.sin(os.clock() * 4 + aggression * 0.03) * 2.2
				local nextPos = myPos + heading * speed * dt + Vector3.new(0, verticalStep, 0) + slither * dt * 9
				headAnchor = nextPos

				local displayPos = Vector3.new(nextPos.X, nextPos.Y + FACE_HEIGHT_OFFSET, nextPos.Z)
				face:PivotTo(CFrame.lookAt(displayPos, displayPos + heading))
				local topPos = displayPos + Vector3.new(0, TOP_RAISE + TOP_EXTRA_RAISE, 0)
				top.CFrame = CFrame.new(topPos)
				local midPos = (topPos + displayPos) * 0.5
				headHitbox.CFrame = CFrame.new(midPos)
				headHitbox.Transparency = 0.99
				root.Transparency = 1
				top.Transparency = 1

					highlight.Enabled = true

			histTimer += dt
			if histTimer >= HISTORY_STEP then
				histTimer = 0
				table.insert(history, 1, headAnchor)
				if #history > maxHistory then table.remove(history) end
			end
			for i, seg in ipairs(segments) do
				local targetIndex = math.min(#history, math.max(1, math.floor(i * SEGMENT_SPACING)))
				local target = history[targetIndex] or headAnchor
				local newPos = seg.part.Position:Lerp(target, clamp01(dt * 11))
				local ahead = history[math.max(1, targetIndex - 2)] or headAnchor
				local look = horizontalUnit(ahead - newPos) or heading
				seg.part.CFrame = CFrame.lookAt(newPos, newPos + look)
			end
		end
	end)

	return model
end

return Harbinger
