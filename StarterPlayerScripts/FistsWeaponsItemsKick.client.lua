-- Fists + Weapons + Items + Kick
-- LocalScript in StarterPlayerScripts

local RunService        = game:GetService("RunService")
local Input             = game:GetService("UserInputService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")

local player = Players.LocalPlayer

-- ── Silent wait helpers ────────────────────────────────────────
local function waitFor(parent, name)
	local c = parent:FindFirstChild(name)
	while not c do parent.ChildAdded:Wait(); c = parent:FindFirstChild(name) end
	return c
end
local function waitForDesc(parent, name)
	local c = parent:FindFirstChild(name, true)
	while not c do parent.DescendantAdded:Wait(); c = parent:FindFirstChild(name, true) end
	return c
end
local function getChar()
	local c = player.Character
	while not c do player.CharacterAdded:Wait(); c = player.Character end
	return c
end

-- ── Folder refs ────────────────────────────────────────────────
local skinsFolder = waitFor(ReplicatedStorage, "Skins")
local fistsFolder = waitFor(skinsFolder,       "Fists")
local itemsFolder = waitFor(skinsFolder,       "Items")
local weaponModulesFolder = ReplicatedStorage:FindFirstChild("WeaponModules")

-- ── Remotes ────────────────────────────────────────────────────
local pickupRemote   = waitFor(ReplicatedStorage, "ItemPickup")
local depositRemote  = waitFor(ReplicatedStorage, "ItemDeposit")
local enemyDamageRE  = waitFor(ReplicatedStorage, "EnemyDamage")  -- (enemyPart, damage)

-- ── Settings ───────────────────────────────────────────────────
local BOB_SPEED     = 7
local BOB_X         = 0.012
local BOB_Y         = 0.018
local MAX_MOVE      = 26

-- Sway
local SWAY_SPEED      = 1
local SWAY_MAX_PX     = 80

-- Attack settings
local QUICK_DURATION  = 0.35
local HOLD_DURATION   = 0.4
local QUICK_DAMAGE    = 10
local HOLD_DAMAGE     = 35
local HIT_RANGE       = 5
local ENTER_RECOVERY  = 0.12  -- seconds per enter frame — tune this
local TAP_THRESHOLD   = 0.12
local COMBO_WINDOW    = 0.55  -- time window to speed up chained attacks
local MIN_SPEED_MULT  = 0.5   -- fastest allowed chained speed

-- Shake settings (RightPullBack2 during hold)
local SHAKE_BASE      = 1.5   -- starting shake amplitude in px
local SHAKE_GROW      = 4.0   -- extra px added per second of holding
local SHAKE_FREQ      = 22    -- shakes per second

-- Kick
local KickKey          = Enum.KeyCode.Q
local KICK_DURATION    = 0.3
local KICK_HOLD_WEIGHT = 3

-- Throw
local ThrowKey         = Enum.KeyCode.E

-- Slot keys
local SLOT_KEYS = {
	[Enum.KeyCode.One]   = 1,
	[Enum.KeyCode.Two]   = 2,
	[Enum.KeyCode.Three] = 3,
}

-- ── State ──────────────────────────────────────────────────────
local character   = getChar()
local rootPart    = waitFor(character, "HumanoidRootPart")

local bobT        = 0
local swayOffsetX = 0   -- current sway offset in pixels
local swayOffsetY = 0
local lastCamCF   = Workspace.CurrentCamera.CFrame

local attacking      = false
local holding        = false
local holdStart      = 0
local kickPlaying    = false
local transitioning  = false
local attackQueued   = false
local attackPressId  = 0
local queuedAttackType = nil
local lastAttackTime = 0
local comboCount = 0

-- Weapon slots 1-3, item slot (separate)
local weaponSlots    = { nil, nil, nil }  -- each = { name, gui } or nil
local activeSlot     = nil               -- 1/2/3 or nil (nil = fists)
local currentItem    = nil
local activeWeaponDef = nil
local weaponDefsById = {}

-- GUI handles (set in setupFists)
local fistsGui, leftFist, rightFist
local baseLeftPos, baseRightPos
local leftPB1, leftPB2, rightPB1, rightPB2
local leftEnter, rightEnter   -- arrays of ImageLabels {1,2,3}
local quickFolder, holdFolder
local activeItemGui, activeRight, baseActivePos
local kickGui, kickFrames
local baseFrame3Size, baseFrame3Pos

-- ── Tween helper ───────────────────────────────────────────────
local function tw(obj, goal, time)
	local t = TweenService:Create(obj,
		TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
	t:Play(); return t
end

-- ── GUI setup ──────────────────────────────────────────────────
local function findScreenGui(folder, name)
	for _, g in ipairs(folder:GetChildren()) do
		if g:IsA("ScreenGui") and g.Name == name then return g end
	end
end

local function getAllFrames(folder)
	local frames = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("ImageLabel") then
			local n = tonumber(c.Name)
			if n then frames[n] = c end
		end
	end
	return frames
end

-- ── Weapon module registry ─────────────────────────────────────
local function buildWeaponContext()
	return {
		player = player,
		character = character,
		rootPart = rootPart,
		workspace = Workspace,
		remotes = {
			enemyDamage = enemyDamageRE,
		},
	}
end

local function loadWeaponModules()
	weaponDefsById = {}
	if not weaponModulesFolder then
		warn("[WEAPON] ReplicatedStorage.WeaponModules folder not found; weapon modules disabled")
		return
	end

	for _, child in ipairs(weaponModulesFolder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, def = pcall(require, child)
			if ok and type(def) == "table" and def.id then
				def.moduleScriptName = child.Name
				def.displayName = def.displayName or def.id
				weaponDefsById[def.id] = def
				print(string.format("[WEAPON] Module loaded: %s (%s)", def.id, child.Name))
			else
				warn(string.format("[WEAPON] Failed to load module %s", child.Name))
			end
		end
	end
end

local function setupFists()
	local pg = waitFor(player, "PlayerGui")

	-- Clean up old
	for _, name in ipairs({"FistsGuiLocal","KickGuiLocal"}) do
		local old = pg:FindFirstChild(name)
		if old then old:Destroy() end
	end

	local handsTemplate = findScreenGui(fistsFolder, "Hands")
	local kickTemplate  = findScreenGui(fistsFolder, "Kick")
	if not handsTemplate or not kickTemplate then
		warn("[FISTS] Missing Hands or Kick template"); return
	end

	fistsGui = handsTemplate:Clone()
	fistsGui.Name         = "FistsGuiLocal"
	fistsGui.ResetOnSpawn = false

	-- Hide EVERYTHING except Left and Right before parenting
	-- so no attack frames are ever visible at start
	for _, obj in ipairs(fistsGui:GetDescendants()) do
		if obj:IsA("ImageLabel") or obj:IsA("Frame") then
			local n = obj.Name
			if n ~= "Left" and n ~= "Right" then
				obj.Visible = false
			end
		end
	end

	fistsGui.Parent = pg

	leftFist  = waitFor(fistsGui, "Left")
	rightFist = waitFor(fistsGui, "Right")

	-- Search direct children first, then recurse — prevents finding
	-- a nested 'Left' inside a Frame before the top-level Left hand
	local function findInGui(name)
		local found = fistsGui:FindFirstChild(name)  -- direct child first
		if not found then
			found = fistsGui:FindFirstChild(name, true)  -- then recursive
		end
		if not found then warn("[FISTS] Could not find:", name) end
		return found
	end

	leftPB1     = findInGui("LeftPullBack1")
	leftPB2     = findInGui("LeftPullBack2")
	rightPB1    = findInGui("RightPullBack1")
	rightPB2    = findInGui("RightPullBack2")
	quickFolder = findInGui("Quick")
	holdFolder  = findInGui("Hold")

	-- Enter frames — played after attack completes
	leftEnter  = {}
	rightEnter = {}
	for i = 1, 3 do
		leftEnter[i]  = findInGui("LeftEnter"  .. i)
		rightEnter[i] = findInGui("RightEnter" .. i)
	end

	baseLeftPos  = leftFist.Position
	baseRightPos = rightFist.Position

	-- Kick
	kickGui = kickTemplate:Clone()
	kickGui.Name         = "KickGuiLocal"
	kickGui.ResetOnSpawn = false
	kickGui.Enabled      = false
	kickGui.Parent       = pg

	local f3 = kickGui:FindFirstChild("3")
	baseFrame3Size = f3 and f3.Size     or UDim2.new(1,0,1,0)
	baseFrame3Pos  = f3 and f3.Position or UDim2.new(0,0,0,0)

	kickFrames = {
		waitFor(kickGui, "1"),
		waitFor(kickGui, "2"),
		waitFor(kickGui, "3"),
	}
end

-- ── Attack raycast ─────────────────────────────────────────────
local function doAttackRaycast(damage)
	local camera = Workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local dir    = camera.CFrame.LookVector * HIT_RANGE

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	print(string.format("[FISTS] Raycast from %s dir %s range %d",
		tostring(origin), tostring(dir), HIT_RANGE))

	local result = Workspace:Raycast(origin, dir, params)

	if not result then
		-- Raycast missed everything — check if enemy is just non-queryable
		-- by doing a proximity sphere check as fallback
		print("[FISTS] Raycast missed — checking proximity fallback")
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp then
			for _, obj in ipairs(Workspace:GetChildren()) do
				if obj:IsA("BasePart") and obj:GetAttribute("Health") ~= nil then
					local dist = (obj.Position - hrp.Position).Magnitude
					if dist <= HIT_RANGE * 1.5 then
						-- Also check it's roughly in front of us
						local toEnemy = (obj.Position - camera.CFrame.Position).Unit
						local dot = toEnemy:Dot(camera.CFrame.LookVector)
						if dot > 0.5 then
							print(string.format("[FISTS] Proximity hit %s (dist %.1f dot %.2f) for %d",
								obj.Name, dist, dot, damage))
							enemyDamageRE:FireServer(obj, damage)
							return
						end
					end
				end
			end
		end
		print("[FISTS] No hit found")
		return
	end

	local hit = result.Instance
	print(string.format("[FISTS] Raycast hit: %s (parent: %s)", hit.Name,
		hit.Parent and hit.Parent.Name or "nil"))

	-- Walk up to find Health attribute
	local target = hit
	while target and target:GetAttribute("Health") == nil do
		target = target.Parent
		if not target or target == Workspace then target = nil; break end
	end

	if target then
		print(string.format("[FISTS] Dealing %d damage to %s", damage, target.Name))
		enemyDamageRE:FireServer(target, damage)
	else
		print("[FISTS] Hit something but no Health attribute found on: " .. hit.Name)
	end
end

-- ── Hide/show helpers ──────────────────────────────────────────
local function showDefault()
	if leftFist  then leftFist.Visible  = true end
	if rightFist then rightFist.Visible = true end
	if leftPB1   then leftPB1.Visible   = false end
	if leftPB2   then leftPB2.Visible   = false end
	if rightPB1  then rightPB1.Visible  = false end
	if rightPB2  then rightPB2.Visible  = false end
	if leftEnter  then for _, f in ipairs(leftEnter)  do if f then f.Visible = false end end end
	if rightEnter then for _, f in ipairs(rightEnter) do if f then f.Visible = false end end end
	if quickFolder then for _, f in pairs(getAllFrames(quickFolder)) do f.Visible = false end end
	if holdFolder  then for _, f in pairs(getAllFrames(holdFolder))  do f.Visible = false end end
end

-- ── Attack sequences ───────────────────────────────────────────
local shakeConn = nil

local function stopShake()
	if shakeConn then shakeConn:Disconnect(); shakeConn = nil end
end

local function startShake(basePosRPB2)
	stopShake()
	if not rightPB2 then return end
	local t2 = 0
	shakeConn = RunService.RenderStepped:Connect(function(dt)
		if not rightPB2 or not rightPB2.Visible then stopShake(); return end
		t2 += dt
		local held = tick() - holdStart
		local amp  = SHAKE_BASE + held * SHAKE_GROW
		local ox   = math.sin(t2 * SHAKE_FREQ * 1.3) * amp
		local oy   = math.cos(t2 * SHAKE_FREQ * 0.9) * amp
		rightPB2.Position = UDim2.new(
			basePosRPB2.X.Scale, basePosRPB2.X.Offset + ox,
			basePosRPB2.Y.Scale, basePosRPB2.Y.Offset + oy
		)
	end)
end

-- For quick: only RightEnter2, single frame
-- For hold:  LeftEnter1-3 and RightEnter1-3 simultaneously
local function playEnterFrames(isHold)
	if isHold then
		for i = 1, 3 do
			if not attacking then break end
			local lf = leftEnter  and leftEnter[i]
			local rf = rightEnter and rightEnter[i]
			if lf then lf.Visible = true end
			if rf then rf.Visible = true end
			task.wait(ENTER_RECOVERY)
			if lf then lf.Visible = false end
			if rf then rf.Visible = false end
		end
	else
		-- Quick: give a short 2-frame recovery so it reads clearly
		local sequence = {
			{ li = nil, ri = 2 },
			{ li = 1,   ri = 1 },
		}
		for _, step in ipairs(sequence) do
			if not attacking then break end
			local lf = step.li and leftEnter and leftEnter[step.li] or nil
			local rf = step.ri and rightEnter and rightEnter[step.ri] or nil
			if lf then lf.Visible = true end
			if rf then rf.Visible = true end
			task.wait(ENTER_RECOVERY * 0.75)
			if lf then lf.Visible = false end
			if rf then rf.Visible = false end
		end
	end
end

local function markAttackFinished()
	lastAttackTime = tick()
end

local doQuickAttack
local doHoldAttack

local function getAttackSpeedMult()
	if tick() - lastAttackTime <= COMBO_WINDOW then
		comboCount = math.clamp(comboCount + 1, 0, 4)
	else
		comboCount = 0
	end
	local speedMult = 1 - (comboCount * 0.15)
	return math.max(MIN_SPEED_MULT, speedMult)
end

local function queueOrRunAttack(requestedType)
	if attacking then
		attackQueued = true
		queuedAttackType = requestedType
		return
	end

	local speedMult = getAttackSpeedMult()
	if requestedType == "hold" then
		task.spawn(function() doHoldAttack(speedMult) end)
	else
		task.spawn(function() doQuickAttack(speedMult) end)
	end
end

local function runQueuedAttackIfAny()
	if not attackQueued then return end
	local nextType = queuedAttackType or "quick"
	attackQueued = false
	queuedAttackType = nil
	queueOrRunAttack(nextType)
end

doQuickAttack = function(speedMult)
	attacking = true
	if leftFist  then leftFist.Visible  = false end
	if rightFist then rightFist.Visible = false end
	speedMult = speedMult or 1

	-- Pullbacks together
	if leftPB1  then leftPB1.Visible  = true end
	if rightPB1 then rightPB1.Visible = true end
	task.wait(0.06 * speedMult)
	if leftPB1  then leftPB1.Visible  = false end
	if rightPB1 then rightPB1.Visible = false end

	if leftPB2  then leftPB2.Visible  = true end
	if rightPB2 then rightPB2.Visible = true end
	task.wait(0.06 * speedMult)
	-- Both disappear — right does NOT stay during quick
	if leftPB2  then leftPB2.Visible  = false end
	if rightPB2 then rightPB2.Visible = false end

	-- Keep a fallback left-arm image only between quick frames
	if leftFist then leftFist.Visible = true end

	-- Quick frames play, but hide fallback while frame is visible to avoid double-image overlap
	local quickFrames = getAllFrames(quickFolder)
	local sortedQ = {}
	for idx, f in pairs(quickFrames) do sortedQ[#sortedQ+1] = {idx=idx, f=f} end
	table.sort(sortedQ, function(a,b) return a.idx < b.idx end)

	-- Fire raycast immediately when punch commits, not after animation
	doAttackRaycast(QUICK_DAMAGE)

	local timePerFrame = (QUICK_DURATION * speedMult) / math.max(1, #sortedQ)
	for _, entry in ipairs(sortedQ) do
		if not attacking then break end
		if leftFist then leftFist.Visible = false end
		entry.f.Visible = true
		task.wait(timePerFrame)
		entry.f.Visible = false
		if leftFist then leftFist.Visible = true end
	end

	-- Enter: quick recovery
	playEnterFrames(false)

	showDefault()
	attacking = false
	markAttackFinished()
	runQueuedAttackIfAny()
end

doHoldAttack = function(speedMult)
	attacking = true
	if leftFist  then leftFist.Visible  = false end
	if rightFist then rightFist.Visible = false end
	speedMult = speedMult or 1

	-- Pullbacks
	if leftPB1  then leftPB1.Visible  = true end
	if rightPB1 then rightPB1.Visible = true end
	task.wait(0.06 * speedMult)
	if leftPB1  then leftPB1.Visible  = false end
	if rightPB1 then rightPB1.Visible = false end

	if leftPB2  then leftPB2.Visible  = true end
	if rightPB2 then rightPB2.Visible = true end
	task.wait(0.06 * speedMult)
	if leftPB2  then leftPB2.Visible  = false end

	-- Right shakes while held, left already hidden
	local basePB2pos = rightPB2 and rightPB2.Position
	startShake(basePB2pos)

	-- Wait for M1 release
	while holding and attacking do task.wait(0.05) end

	stopShake()
	if rightPB2 and basePB2pos then
		rightPB2.Position = basePB2pos
		rightPB2.Visible  = false
	end

	-- Hold frames
	local holdFrames = getAllFrames(holdFolder)
	local sortedH = {}
	for idx, f in pairs(holdFrames) do sortedH[#sortedH+1] = {idx=idx, f=f} end
	table.sort(sortedH, function(a,b) return a.idx < b.idx end)

	-- Fire raycast immediately when hold commits
	doAttackRaycast(HOLD_DAMAGE)

	local timePerFrame = (HOLD_DURATION * speedMult) / math.max(1, #sortedH)
	for _, entry in ipairs(sortedH) do
		if not attacking then break end
		entry.f.Visible = true
		task.wait(timePerFrame)
		entry.f.Visible = false
	end

	-- Enter: all 3 frames both sides for hold
	playEnterFrames(true)

	showDefault()
	attacking = false
	markAttackFinished()
	runQueuedAttackIfAny()
end

-- ── Kick ───────────────────────────────────────────────────────
local function setKickFrame(name)
	for _, f in ipairs(kickFrames) do
		if f and f:IsA("GuiObject") then
			f.Visible = (f.Name == name)
			if f.Name == "3" then
				f.Size     = baseFrame3Size
				f.Position = baseFrame3Pos
				f.ImageTransparency = 0
			end
		end
	end
	if name == "3" then
		local f3 = kickGui:FindFirstChild("3")
		if f3 then
			f3.Size = UDim2.new(
				baseFrame3Size.X.Scale * 1.1, baseFrame3Size.X.Offset,
				baseFrame3Size.Y.Scale * 1.1, baseFrame3Size.Y.Offset)
			f3.Position = UDim2.new(
				baseFrame3Pos.X.Scale, baseFrame3Pos.X.Offset,
				baseFrame3Pos.Y.Scale - 0.01, baseFrame3Pos.Y.Offset)
			f3.ImageTransparency = 0.2
		end
	end
end

local function playKick()
	if kickPlaying then return end
	kickPlaying = true
	kickGui.Enabled = true

	local seq     = {"1","2","3","2","1"}
	local weights = {1, 1, KICK_HOLD_WEIGHT, 1, 1}
	local total   = 0; for _, w in ipairs(weights) do total += w end

	for i, name in ipairs(seq) do
		setKickFrame(name)
		local elapsed = 0
		local step    = KICK_DURATION * (weights[i]/total)
		while elapsed < step do elapsed += RunService.RenderStepped:Wait() end
	end

	kickGui.Enabled = false
	kickPlaying = false
end

-- ── Item equip/unequip ─────────────────────────────────────────
local function equipItem(itemName)
	if transitioning or currentItem then return end
	transitioning = true

	local template = itemsFolder:FindFirstChild(itemName)
	if not template then transitioning = false; return end

	local pg      = waitFor(player, "PlayerGui")
	local itemGui = template:Clone()
	itemGui.Name         = "ItemGuiLocal"
	itemGui.ResetOnSpawn = false
	itemGui.Parent       = pg

	local rightLabel = waitFor(itemGui, "Right")
	local basePos    = rightLabel.Position

	rightLabel.Position = UDim2.new(
		basePos.X.Scale, basePos.X.Offset,
		basePos.Y.Scale + 0.5, basePos.Y.Offset)

	tw(leftFist,  { Position = UDim2.new(baseLeftPos.X.Scale,  baseLeftPos.X.Offset,  baseLeftPos.Y.Scale  + 0.5, baseLeftPos.Y.Offset) }, 0.25)
	tw(rightFist, { Position = UDim2.new(baseRightPos.X.Scale, baseRightPos.X.Offset, baseRightPos.Y.Scale + 0.5, baseRightPos.Y.Offset) }, 0.25)
	task.wait(0.3)

	fistsGui.Enabled = false
	tw(rightLabel, { Position = basePos }, 0.25)
	task.wait(0.3)

	activeItemGui = itemGui
	activeRight   = rightLabel
	baseActivePos = basePos
	currentItem   = itemName

	pickupRemote:FireServer(itemName)
	transitioning = false
end

local function unequipItem()
	if transitioning or not currentItem then return end
	transitioning = true

	tw(activeRight, { Position = UDim2.new(
		baseActivePos.X.Scale, baseActivePos.X.Offset,
		baseActivePos.Y.Scale + 0.5, baseActivePos.Y.Offset) }, 0.25)
	task.wait(0.3)

	if activeItemGui then activeItemGui:Destroy() end
	activeItemGui = nil; activeRight = nil; baseActivePos = nil
	currentItem   = nil
	player:SetAttribute("HeldItem", nil)

	fistsGui.Enabled   = true
	leftFist.Position  = UDim2.new(baseLeftPos.X.Scale,  baseLeftPos.X.Offset,  baseLeftPos.Y.Scale  + 0.5, baseLeftPos.Y.Offset)
	rightFist.Position = UDim2.new(baseRightPos.X.Scale, baseRightPos.X.Offset, baseRightPos.Y.Scale + 0.5, baseRightPos.Y.Offset)
	tw(leftFist,  { Position = baseLeftPos  }, 0.25)
	tw(rightFist, { Position = baseRightPos }, 0.25)
	task.wait(0.3)

	transitioning = false
end

-- ── Weapon slots ───────────────────────────────────────────────
local function printSlots()
	local parts = {}
	for i = 1, 3 do
		parts[i] = weaponSlots[i] and weaponSlots[i].displayName or "empty"
	end
	print(string.format("[SLOTS] 1:%s  2:%s  3:%s  | Active:%s",
		parts[1], parts[2], parts[3],
		activeSlot and tostring(activeSlot) or "fists"))
end

local function unequipActiveWeapon()
	if not activeWeaponDef then return end
	if type(activeWeaponDef.onUnequip) == "function" then
		pcall(activeWeaponDef.onUnequip, buildWeaponContext())
	end
	activeWeaponDef = nil
	if fistsGui then fistsGui.Enabled = true end
	showDefault()
end

local function equipActiveWeapon(slotData)
	unequipActiveWeapon()
	if not slotData then return end
	activeWeaponDef = slotData.def
	if fistsGui then fistsGui.Enabled = false end
	if type(activeWeaponDef.onEquip) == "function" then
		pcall(activeWeaponDef.onEquip, buildWeaponContext())
	end
end

local function switchToSlot(slot)
	if activeSlot == slot then return end
	-- Cancel any ongoing fist attack if switching away
	if attacking then attacking = false; holding = false; stopShake(); showDefault(); markAttackFinished() end

	activeSlot = slot
	local weapon = weaponSlots[slot]
	if weapon then
		equipActiveWeapon(weapon)
		print(string.format("[WEAPON] Switched to slot %d: %s", slot, weapon.displayName))
	else
		unequipActiveWeapon()
		print(string.format("[WEAPON] Slot %d is empty — fists active", slot))
	end
	printSlots()
end

local function pickupWeapon(weaponId, pickupModelName)
	local def = weaponDefsById[weaponId]
	if not def then
		warn(string.format("[WEAPON] No module for weapon id '%s'", tostring(weaponId)))
		return false
	end

	-- Find first empty slot
	for i = 1, 3 do
		if not weaponSlots[i] then
			weaponSlots[i] = {
				id = def.id,
				def = def,
				displayName = def.displayName,
				pickupModelName = pickupModelName or def.pickupModelName or def.id,
			}
			print(string.format("[WEAPON] Picked up %s → slot %d", def.displayName, i))
			switchToSlot(i)
			printSlots()
			return true
		end
	end
	print("[WEAPON] All slots full — throw one first (E)")
	return false
end

local function throwWeapon()
	if not activeSlot then
		print("[WEAPON] No weapon to throw — using fists")
		return
	end
	local weapon = weaponSlots[activeSlot]
	if not weapon then
		print(string.format("[WEAPON] Slot %d already empty", activeSlot))
		return
	end

	print(string.format("[WEAPON] Threw %s from slot %d", weapon.displayName, activeSlot))
	-- TODO: spawn thrown weapon/item world pickup; keeping module integration as current priority
	unequipActiveWeapon()
	weaponSlots[activeSlot] = nil
	activeSlot = nil
	if fistsGui then fistsGui.Enabled = true end
	showDefault()
	printSlots()
end

local function isFistsActive()
	-- Fists are active when no slot is selected OR active slot is empty
	return activeSlot == nil or weaponSlots[activeSlot] == nil
end

-- ── Input ──────────────────────────────────────────────────────
Input.InputBegan:Connect(function(io, processed)
	if processed then return end

	-- Slot switching
	local slot = SLOT_KEYS[io.KeyCode]
	if slot then switchToSlot(slot); return end

	-- Kick
	if io.KeyCode == KickKey then task.spawn(playKick); return end

	-- Throw
	if io.KeyCode == ThrowKey then throwWeapon(); return end

	-- M1 — only fists for now (weapons handled when they exist)
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		if not isFistsActive() then
			if activeWeaponDef and type(activeWeaponDef.onPrimaryDown) == "function" then
				pcall(activeWeaponDef.onPrimaryDown, buildWeaponContext())
			end
			return
		end

		holding   = true
		holdStart = tick()
		attackPressId += 1
		local thisPressId = attackPressId

		-- Small delay to distinguish tap from hold
		task.delay(TAP_THRESHOLD, function()
			if thisPressId ~= attackPressId then return end
			if holding then
				queueOrRunAttack("hold")
			else
				queueOrRunAttack("quick")
			end
		end)
	end

	if io.UserInputType == Enum.UserInputType.MouseButton2 then
		if activeWeaponDef and type(activeWeaponDef.onSecondaryDown) == "function" then
			pcall(activeWeaponDef.onSecondaryDown, buildWeaponContext())
		end
	end
end)

Input.InputEnded:Connect(function(io, processed)
	if io.UserInputType == Enum.UserInputType.MouseButton1 then
		if not isFistsActive() then
			if activeWeaponDef and type(activeWeaponDef.onPrimaryUp) == "function" then
				pcall(activeWeaponDef.onPrimaryUp, buildWeaponContext())
			end
		else
			holding = false
		end
	end

	if io.UserInputType == Enum.UserInputType.MouseButton2 then
		if activeWeaponDef and type(activeWeaponDef.onSecondaryUp) == "function" then
			pcall(activeWeaponDef.onSecondaryUp, buildWeaponContext())
		end
	end
end)

-- ── Touch item pickup ──────────────────────────────────────────
local connectedTriggers = {}
local connectedWeaponTriggers = {}

local function connectTouch(itemName)
	task.spawn(function()
		local function tryConnect(obj)
			if not obj:IsA("BasePart") or obj.Name ~= "Trigger" then return end
			local parent = obj.Parent
			if not parent or parent.Name ~= itemName then return end
			if connectedTriggers[obj] then return end
			connectedTriggers[obj] = true
			obj.Touched:Connect(function(hit)
				if currentItem then return end
				local char = player.Character
				if not char then return end
				if hit:IsDescendantOf(char) then
					equipItem(itemName)
					if parent and parent.Parent then parent:Destroy() end
				end
			end)
		end
		for _, obj in ipairs(Workspace:GetDescendants()) do tryConnect(obj) end
		Workspace.DescendantAdded:Connect(tryConnect)
	end)
end

local ITEM_NAMES = { "Paper", "Echo", "Seal", "Core" }

local function connectWeaponTouches()
	task.spawn(function()
		local function tryConnect(obj)
			if not obj:IsA("BasePart") or obj.Name ~= "Trigger" then return end
			local parent = obj.Parent
			if not parent then return end
			if connectedWeaponTriggers[obj] then return end

			local weaponId = parent:GetAttribute("WeaponId") or parent.Name
			if not weaponDefsById[weaponId] then return end
			connectedWeaponTriggers[obj] = true

			obj.Touched:Connect(function(hit)
				local char = player.Character
				if not char then return end
				if not hit:IsDescendantOf(char) then return end
				if pickupWeapon(weaponId, parent.Name) then
					if parent and parent.Parent then
						parent:Destroy()
					end
				end
			end)
		end

		for _, obj in ipairs(Workspace:GetDescendants()) do tryConnect(obj) end
		Workspace.DescendantAdded:Connect(tryConnect)
	end)
end

-- ── Deposit listener ───────────────────────────────────────────
depositRemote.OnClientEvent:Connect(function(itemName)
	if currentItem == itemName then unequipItem() end
end)

-- ── Sway ───────────────────────────────────────────────────────
-- Tracks camera delta each frame to produce lag-behind sway on hands
local function applySwayOffset(basePos, swayX, swayY)
	return UDim2.new(
		basePos.X.Scale,
		math.clamp(basePos.X.Offset + swayX, basePos.X.Offset - SWAY_MAX_PX, basePos.X.Offset + SWAY_MAX_PX),
		basePos.Y.Scale,
		math.clamp(basePos.Y.Offset + swayY, basePos.Y.Offset - SWAY_MAX_PX, basePos.Y.Offset + SWAY_MAX_PX)
	)
end

-- ── Respawn ────────────────────────────────────────────────────
local function bindCharacter(newChar)
	character = newChar
	rootPart  = waitFor(newChar, "HumanoidRootPart")

	currentItem   = nil
	transitioning = false
	attacking     = false
	holding       = false
	kickPlaying   = false
	activeSlot    = nil
	weaponSlots   = { nil, nil, nil }
	activeItemGui = nil
	activeRight   = nil
	baseActivePos = nil
	activeWeaponDef = nil
	swayOffsetX   = 0
	swayOffsetY   = 0
	attackQueued  = false
	attackPressId = 0
	queuedAttackType = nil
	lastAttackTime = 0
	comboCount = 0

	setupFists()
	loadWeaponModules()
	for _, name in ipairs(ITEM_NAMES) do connectTouch(name) end
	connectWeaponTouches()
end

player.CharacterAdded:Connect(bindCharacter)

-- ── Init ───────────────────────────────────────────────────────
setupFists()
loadWeaponModules()
for _, name in ipairs(ITEM_NAMES) do connectTouch(name) end
connectWeaponTouches()

-- ── RenderStepped: sway + bob ──────────────────────────────────
RunService.RenderStepped:Connect(function(dt)
	if not rootPart or not rootPart.Parent then return end

	-- ── Sway: measure camera rotation delta ───────────────────
	local cam       = Workspace.CurrentCamera
	local camCF     = cam.CFrame
	local deltaCF   = lastCamCF:Inverse() * camCF
	local _, dY, _  = deltaCF:ToEulerAnglesYXZ()   -- yaw delta
	local dX, _, _  = deltaCF:ToEulerAnglesYXZ()   -- pitch delta
	lastCamCF       = camCF

	-- Convert rotation delta to pixels (scale factor feels best around 800-1200)
	local swayTargetX = -math.deg(dY) * 30   -- look right → hands lag left (negative)
	local swayTargetY =  math.deg(dX) * 20

	-- Lerp sway offset toward target, then decay back to zero
	swayOffsetX = swayOffsetX + (swayTargetX - swayOffsetX) * math.clamp(SWAY_SPEED * dt, 0, 1)
	swayOffsetY = swayOffsetY + (swayTargetY - swayOffsetY) * math.clamp(SWAY_SPEED * dt, 0, 1)

	-- Decay back to 0 when no input
	swayOffsetX = swayOffsetX * (1 - math.clamp(SWAY_SPEED * 0.5 * dt, 0, 1))
	swayOffsetY = swayOffsetY * (1 - math.clamp(SWAY_SPEED * 0.5 * dt, 0, 1))

	-- ── Bob: speed-based vertical/horizontal oscillation ──────
	local vel       = rootPart.AssemblyLinearVelocity
	local speed     = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local intensity = math.clamp(speed / MAX_MOVE, 0, 1)
	bobT += dt * BOB_SPEED * (0.25 + intensity)

	local bobX = math.sin(bobT)     * BOB_X * intensity
	local bobY = math.sin(2 * bobT) * BOB_Y * intensity

	-- ── Apply to hands ─────────────────────────────────────────
	if not attacking then
		if isFistsActive() and fistsGui and fistsGui.Enabled then
			if leftFist and leftFist.Visible then
				leftFist.Position = applySwayOffset(
					UDim2.new(baseLeftPos.X.Scale + bobX, baseLeftPos.X.Offset,
						baseLeftPos.Y.Scale + bobY, baseLeftPos.Y.Offset),
					swayOffsetX, swayOffsetY)
			end
			if rightFist and rightFist.Visible then
				rightFist.Position = applySwayOffset(
					UDim2.new(baseRightPos.X.Scale + bobX, baseRightPos.X.Offset,
						baseRightPos.Y.Scale + bobY, baseRightPos.Y.Offset),
					swayOffsetX, swayOffsetY)
			end
		end
	end

	if currentItem and activeRight and baseActivePos then
		activeRight.Position = applySwayOffset(
			UDim2.new(baseActivePos.X.Scale + bobX, baseActivePos.X.Offset,
				baseActivePos.Y.Scale + bobY, baseActivePos.Y.Offset),
			swayOffsetX, swayOffsetY)
	end
end)
