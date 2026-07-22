-- DreamPortalController.server.lua
-- Places floating picture-frame portals on PortalHere markers and supports
-- simple paired teleporting between portals in the active dream.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FRAME_MODEL_PATH = {"Assets", "Picture Frame"}
local DREAM_PICS_PATH = {"Assets", "DreamPics"}
local MARKER_NAME = "PortalHere"
local FRAME_HEIGHT = 9
local FRAME_FORWARD_OFFSET = 0
local FLOAT_AMPLITUDE = 0.55
local TOUCH_COOLDOWN = 1.0
local rng = Random.new()

local function shuffle(list)
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function popRandom(list)
	if #list == 0 then return nil end
	return table.remove(list, rng:NextInteger(1, #list))
end

local function findPath(root, path)
	local cur = root
	for _, name in ipairs(path) do
		cur = cur and cur:FindFirstChild(name)
	end
	return cur
end

local function getBasePart(model)
	if model:IsA("BasePart") then return model end
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function cframeFromPart(part)
	local pos = part.Position
		+ Vector3.new(0, part.Size.Y * 0.5 + FRAME_HEIGHT, 0)
		+ part.CFrame.LookVector * FRAME_FORWARD_OFFSET
	return CFrame.new(pos, pos + part.CFrame.LookVector)
end

local activeFrames = {}
local playerCooldown = {}

local function clearFrames()
	for _, entry in ipairs(activeFrames) do
		if entry and entry.model then entry.model:Destroy() end
	end
	table.clear(activeFrames)
end

local function getDreams()
	local folder = Workspace:FindFirstChild("GeneratedDreams")
	if not folder then return {} end
	local dreams = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then table.insert(dreams, child) end
	end
	table.sort(dreams, function(a, b)
		return (a:GetAttribute("DreamIndex") or 0) < (b:GetAttribute("DreamIndex") or 0)
	end)
	return dreams
end

local function applyDreamPicture(frameModel, dreamName)
	local pics = findPath(ReplicatedStorage, DREAM_PICS_PATH)
	if not pics then return end
	local pic = pics:FindFirstChild(dreamName)
	if not pic then return end
	local tex = nil
	if pic:IsA("Decal") then tex = pic.Texture end
	if pic:IsA("Texture") then tex = pic.Texture end
	if not tex or tex == "" then return end
	for _, d in ipairs(frameModel:GetDescendants()) do
		if d:IsA("Decal") and d.Name == "Picture" then
			d.Texture = tex
		end
	end
end

local function teleportPlayer(player, destinationCF)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	hrp.CFrame = destinationCF + destinationCF.LookVector * 5 + Vector3.new(0, 2, 0)
end

local function canTeleport(player)
	local now = os.clock()
	local last = playerCooldown[player.UserId] or 0
	if now - last < TOUCH_COOLDOWN then return false end
	playerCooldown[player.UserId] = now
	return true
end

local function wirePortalTouch(entry)
	local trigger = Instance.new("Part")
	trigger.Name = "PortalTrigger"
	trigger.Size = Vector3.new(8, 10, 2)
	trigger.Transparency = 1
	trigger.CanCollide = false
	trigger.Anchored = true
	trigger.CFrame = entry.model:GetPivot()
	trigger.Parent = entry.model
	entry.trigger = trigger

	trigger.Touched:Connect(function(hit)
		if not entry.paired or not entry.paired.marker then return end
		local plr = Players:GetPlayerFromCharacter(hit.Parent)
		if not plr or not canTeleport(plr) then return end
		teleportPlayer(plr, entry.paired.marker.CFrame)
	end)
end

local floatTime = 0
local function updateFloat(dt)
	floatTime += dt
	for _, entry in ipairs(activeFrames) do
		if entry.model and entry.marker and entry.model.Parent then
			local base = cframeFromPart(entry.marker)
			local y = math.sin(floatTime * 1.4 + entry.phase) * FLOAT_AMPLITUDE
			local yaw = math.sin(floatTime * 0.8 + entry.phase) * math.rad(6)
			entry.model:PivotTo(base * CFrame.new(0, y, 0) * CFrame.Angles(0, yaw, 0))
			if entry.trigger then
				entry.trigger.CFrame = entry.model:GetPivot()
			end
		end
	end
end

local function rebuildPortals()
	clearFrames()
	local dreams = getDreams()
	if #dreams < 2 then
		print("[DreamPortal] Skipping portal spawn (need 2+ dreams)")
		return
	end
	local frameTemplate = findPath(ReplicatedStorage, FRAME_MODEL_PATH)
	if not frameTemplate or not frameTemplate:IsA("Model") then
		warn("[DreamPortal] Missing ReplicatedStorage/Assets/Picture Frame model")
		return
	end

	local byDream = {}
	for _, dream in ipairs(dreams) do
		byDream[dream] = {}
		for _, d in ipairs(dream:GetDescendants()) do
			if d:IsA("BasePart") and d.Name == MARKER_NAME and d:GetAttribute("ReservedForPod") ~= true then
				table.insert(byDream[dream], d)
			end
		end
	end

	for _, markers in pairs(byDream) do
		shuffle(markers)
	end

	local pairsToBuild = {}
	local unconnected = table.clone(dreams)
	shuffle(unconnected)
	local connected = { popRandom(unconnected) }

	-- First make a randomized spanning tree so every dream can be reached,
	-- instead of always wiring dream 1 -> 2 -> 3 in list order.
	while #unconnected > 0 do
		local b = popRandom(unconnected)
		local a = connected[rng:NextInteger(1, #connected)]
		if #byDream[a] > 0 and #byDream[b] > 0 then
			table.insert(pairsToBuild, { a = a, b = b, ma = popRandom(byDream[a]), mb = popRandom(byDream[b]) })
		end
		table.insert(connected, b)
	end

	-- Use extra PortalHere markers as optional branches between random different
	-- dreams, so maps with 3+ markers can create more than one route.
	local safety = 0
	while safety < 100 do
		safety += 1
		local candidates = {}
		for _, dream in ipairs(dreams) do
			if #byDream[dream] > 0 then table.insert(candidates, dream) end
		end
		if #candidates < 2 then break end
		local a = popRandom(candidates)
		local b = popRandom(candidates)
		if a and b and a ~= b then
			table.insert(pairsToBuild, { a = a, b = b, ma = popRandom(byDream[a]), mb = popRandom(byDream[b]) })
		end
	end

	local id = 0
	for _, pair in ipairs(pairsToBuild) do
		local a, b, ma, mb = pair.a, pair.b, pair.ma, pair.mb
		if ma and mb then
			id += 1
			local fa = frameTemplate:Clone()
			fa.Name = "DreamPortalFrame_" .. id .. "A"
			fa.Parent = a
			fa:PivotTo(cframeFromPart(ma))
			applyDreamPicture(fa, b:GetAttribute("DreamName") or b.Name)
			local ea = {model = fa, marker = ma, phase = rng:NextNumber(0, math.pi * 2)}
			table.insert(activeFrames, ea)

			local fb = frameTemplate:Clone()
			fb.Name = "DreamPortalFrame_" .. id .. "B"
			fb.Parent = b
			fb:PivotTo(cframeFromPart(mb))
			applyDreamPicture(fb, a:GetAttribute("DreamName") or a.Name)
			local eb = {model = fb, marker = mb, phase = rng:NextNumber(0, math.pi * 2)}
			table.insert(activeFrames, eb)

			ea.paired = eb
			eb.paired = ea
			wirePortalTouch(ea)
			wirePortalTouch(eb)
		end
	end

	print(string.format("[DreamPortal] Spawned %d portal frame(s) across %d portal pair(s)", #activeFrames, id))
end

local DreamPodReady = ReplicatedStorage:FindFirstChild("DreamPodReady")
if DreamPodReady and DreamPodReady:IsA("BindableEvent") then
	DreamPodReady.Event:Connect(function()
		task.defer(rebuildPortals)
	end)
end

Workspace.ChildAdded:Connect(function(c)
	if c.Name == "GeneratedDreams" then task.defer(rebuildPortals) end
end)

RunService.Heartbeat:Connect(updateFloat)
task.defer(rebuildPortals)

print("[DreamPortal] Controller ready")
