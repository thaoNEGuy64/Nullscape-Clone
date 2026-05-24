-- ShadeClient.client.lua
-- StarterPlayerScripts
-- Reads Shade state/facing from server attributes and updates sprite display locally.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local SPRITE_UPDATE = 1 / 24
local SCAN_INTERVAL = 1.0
local FRONT_THRESHOLD = 45
local BACK_THRESHOLD = 135
local WALK_FRAME_DURATION = 0.2
local walkFrames = { "WalkFront1", "WalkFront2", "WalkFront3" }
local trackedEnemies = {}

local function isShadePart(obj)
	return obj:IsA("BasePart") and obj.Name:sub(1, 6) == "Shade_"
end

local function getViewDirection(enemyPart)
	local camera = Workspace.CurrentCamera
	if not camera then return "Front", false end
	local toCamera = camera.CFrame.Position - enemyPart.Position
	toCamera = Vector3.new(toCamera.X, 0, toCamera.Z)
	if toCamera.Magnitude < 0.01 then return "Front", false end
	toCamera = toCamera.Unit

	local facing = Vector3.new(enemyPart:GetAttribute("FacingX") or 0, 0, enemyPart:GetAttribute("FacingZ") or 1)
	if facing.Magnitude < 0.01 then facing = Vector3.new(0, 0, 1) end
	facing = facing.Unit

	local angleDeg = math.deg(math.acos(math.clamp(facing:Dot(toCamera), -1, 1)))
	if angleDeg < FRONT_THRESHOLD then
		return "Front", false
	elseif angleDeg > BACK_THRESHOLD then
		return "Back", false
	end
	return "Side", facing:Cross(toCamera).Y <= 0
end

local function applySprite(data, spriteName, mirror)
	local gui = data.gui
	if not gui then return end
	for _, child in ipairs(gui:GetChildren()) do
		if child:IsA("ImageLabel") then
			local active = child.Name == spriteName
			child.Visible = active
			if active then
				local rs = child.ImageRectSize
				local ro = child.ImageRectOffset
				if mirror and rs.X > 0 then
					child.ImageRectSize = Vector2.new(-rs.X, rs.Y)
					child.ImageRectOffset = Vector2.new(rs.X + ro.X, ro.Y)
				elseif not mirror and rs.X < 0 then
					child.ImageRectSize = Vector2.new(-rs.X, rs.Y)
					child.ImageRectOffset = Vector2.new(ro.X - (-rs.X), ro.Y)
				end
				data.activeSprite = child
			end
		end
	end
end

local function getSpriteName(state, direction, walkFrame, mirror)
	if state == "PunchPull" then return "PunchPull", false end
	if state == "Punch" then return "Punch", false end
	if state == "Walk" then return walkFrames[walkFrame] or walkFrames[1], mirror end
	if direction == "Back" then return "IdleBack", false end
	if direction == "Side" then return "IdleSide", mirror end
	return "IdleFront", false
end

local function startTrackingEnemy(part)
	if trackedEnemies[part] then return end
	local gui = part:FindFirstChild("GUI")
	local sprites = part:FindFirstChild("Sprites")
	if not gui or not sprites then
		warn("[SHADE CLIENT] Enemy missing GUI or Sprites:", part:GetFullName())
		return
	end
	for _, sprite in ipairs(sprites:GetChildren()) do
		if sprite:IsA("ImageLabel") then
			sprite.Parent = gui
			sprite.Visible = false
			sprite.Size = UDim2.new(1, 0, 1, 0)
			sprite.Position = UDim2.new(0, 0, 0, 0)
			sprite.BackgroundTransparency = 1
		end
	end
	trackedEnemies[part] = { gui = gui, walkFrame = 1, frameDir = 1, frameTimer = 0, state = "Idle", activeSprite = nil }
	print("[SHADE CLIENT] Tracking enemy:", part.Name)
end

local function stopTrackingEnemy(part)
	trackedEnemies[part] = nil
end

local function scanForEnemies()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if isShadePart(obj) then startTrackingEnemy(obj) end
	end
	for part in pairs(trackedEnemies) do
		if not part or not part.Parent then stopTrackingEnemy(part) end
	end
end

local lastSpriteUpdate = 0
local lastScan = 0

RunService.RenderStepped:Connect(function(dt)
	local now = tick()
	if now - lastScan >= SCAN_INTERVAL then
		lastScan = now
		scanForEnemies()
	end
	if now - lastSpriteUpdate < SPRITE_UPDATE then return end
	lastSpriteUpdate = now

	for part, data in pairs(trackedEnemies) do
		if not part or not part.Parent then
			trackedEnemies[part] = nil
			continue
		end
		local state = part:GetAttribute("State") or "Idle"
		data.state = state
		if state == "Walk" then
			data.frameTimer += SPRITE_UPDATE
			if data.frameTimer >= WALK_FRAME_DURATION then
				data.frameTimer -= WALK_FRAME_DURATION
				data.walkFrame += data.frameDir
				if data.walkFrame > #walkFrames then
					data.walkFrame = #walkFrames - 1
					data.frameDir = -1
				elseif data.walkFrame < 1 then
					data.walkFrame = 2
					data.frameDir = 1
				end
			end
		else
			data.walkFrame = 1
			data.frameDir = 1
			data.frameTimer = 0
		end

		local direction, mirror = getViewDirection(part)
		local spriteName, shouldMirror = getSpriteName(state, direction, data.walkFrame, mirror)
		applySprite(data, spriteName, shouldMirror)

		local camera = Workspace.CurrentCamera
		local posVal = part:FindFirstChild("WorldPos")
		if camera and posVal then
			local pos = posVal.Value
			local toCamera = camera.CFrame.Position - pos
			toCamera = Vector3.new(toCamera.X, 0, toCamera.Z)
			part.CFrame = toCamera.Magnitude > 0.01 and CFrame.new(pos, pos + toCamera) or CFrame.new(pos)
		end
	end
end)

Workspace.DescendantAdded:Connect(function(child)
	if isShadePart(child) then
		task.wait(0.1)
		startTrackingEnemy(child)
	end
end)

Workspace.DescendantRemoving:Connect(function(child)
	stopTrackingEnemy(child)
end)

print("[SHADE CLIENT] Loaded")
