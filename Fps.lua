-- FPS Counter + Lag Reducer v3 - LocalScript
-- Đặt vào: StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Stats = game:GetService("Stats")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then warn("[GUI] Không tìm thấy PlayerGui!") return end

local existing = playerGui:FindFirstChild("FPSLagGui")
if existing then existing:Destroy() end

-- ============================================================
-- BIẾN TRẠNG THÁI
-- ============================================================
local lagEnabled  = false
local nukeEnabled = false
local panelOpen   = true
local hiddenObjects = {}
local isAnimating = false

-- ============================================================
-- GUI SETUP
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "FPSLagGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 155, 0, 0)
frame.AutomaticSize = Enum.AutomaticSize.Y
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 14)
frame.BackgroundTransparency = 0.1
frame.BorderSizePixel = 0
frame.ClipsDescendants = true
frame.Parent = gui
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

-- stroke viền mỏng cho đẹp
local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 70)
stroke.Thickness = 1
stroke.Transparency = 0.5
stroke.Parent = frame

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 3)
layout.Parent = frame

local padding = Instance.new("UIPadding")
padding.PaddingTop    = UDim.new(0, 6)
padding.PaddingBottom = UDim.new(0, 6)
padding.PaddingLeft   = UDim.new(0, 7)
padding.PaddingRight  = UDim.new(0, 7)
padding.Parent = frame

-- ============================================================
-- HELPERS
-- ============================================================
local function makeLabel(text, color, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 18)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextScaled = false
	l.TextSize = 12
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Text = text
	l.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	l.LayoutOrder = order or 0
	l.Parent = frame
	return l
end

local function makeDivider(order)
	local d = Instance.new("Frame")
	d.Size = UDim2.new(1, 0, 0, 1)
	d.BackgroundColor3 = Color3.fromRGB(50, 50, 55)
	d.BorderSizePixel = 0
	d.LayoutOrder = order
	d.Parent = frame
	return d
end

local function makeSubButton(parent, text, color, order)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 24)
	b.BackgroundColor3 = color or Color3.fromRGB(45, 45, 50)
	b.BorderSizePixel = 0
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.Text = text
	b.TextColor3 = Color3.fromRGB(240, 240, 240)
	b.LayoutOrder = order or 0
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	return b
end

-- ============================================================
-- FPS / PING LABELS
-- ============================================================
local fpsLabel  = makeLabel("FPS: --",  Color3.fromRGB(0, 230, 0),   1)
local pingLabel = makeLabel("Ping: --", Color3.fromRGB(80, 185, 255), 2)

makeDivider(3)

-- ============================================================
-- HEADER ROW (Fix Lag + collapse btn)
-- ============================================================
local headerRow = Instance.new("Frame")
headerRow.Size = UDim2.new(1, 0, 0, 22)
headerRow.BackgroundTransparency = 1
headerRow.LayoutOrder = 4
headerRow.Parent = frame

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -28, 1, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Font = Enum.Font.GothamBold
headerTitle.TextSize = 11
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.Text = "⚙️ Fix Lag"
headerTitle.TextColor3 = Color3.fromRGB(170, 170, 180)
headerTitle.Parent = headerRow

local collapseBtn = Instance.new("TextButton")
collapseBtn.Size = UDim2.new(0, 22, 0, 20)
collapseBtn.Position = UDim2.new(1, -22, 0.5, -10)
collapseBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
collapseBtn.BorderSizePixel = 0
collapseBtn.Font = Enum.Font.GothamBold
collapseBtn.TextSize = 10
collapseBtn.Text = "▲"
collapseBtn.TextColor3 = Color3.fromRGB(180, 180, 190)
collapseBtn.Parent = headerRow
Instance.new("UICorner", collapseBtn).CornerRadius = UDim.new(0, 5)

-- ============================================================
-- LAG PANEL (có tween)
-- ============================================================
local lagPanel = Instance.new("Frame")
lagPanel.Size = UDim2.new(1, 0, 0, 0)   -- height sẽ tween
lagPanel.BackgroundTransparency = 1
lagPanel.ClipsDescendants = true
lagPanel.LayoutOrder = 5
lagPanel.Parent = frame

local lagPanelLayout = Instance.new("UIListLayout")
lagPanelLayout.SortOrder = Enum.SortOrder.LayoutOrder
lagPanelLayout.Padding = UDim.new(0, 3)
lagPanelLayout.Parent = lagPanel

local lagBtn   = makeSubButton(lagPanel, "⚡ Bật Giảm Lag",       Color3.fromRGB(35, 90, 35),  1)
local nukeBtn  = makeSubButton(lagPanel, "💣 Xoá Vật Thể (Mạnh)", Color3.fromRGB(110, 35, 35), 2)
local resetBtn = makeSubButton(lagPanel, "↺ Reset Tất Cả",        Color3.fromRGB(50, 50, 55),  3)

-- Tính chiều cao thật của panel khi mở
-- 3 buttons x 24 + 2 gaps x 3 + padding top 3 = ~81
local PANEL_OPEN_H  = 24*3 + 3*2 + 3  -- 81
local PANEL_CLOSE_H = 0

local tweenInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function setPanelOpen(open, instant)
	if isAnimating and not instant then return end
	isAnimating = true
	panelOpen = open
	collapseBtn.Text = open and "▲" or "▼"

	local targetH = open and PANEL_OPEN_H or PANEL_CLOSE_H
	if instant then
		lagPanel.Size = UDim2.new(1, 0, 0, targetH)
		isAnimating = false
	else
		local tween = TweenService:Create(lagPanel, tweenInfo, {
			Size = UDim2.new(1, 0, 0, targetH)
		})
		tween.Completed:Connect(function()
			isAnimating = false
		end)
		tween:Play()
	end
end

-- Init: mở ngay không tween
task.defer(function()
	setPanelOpen(true, true)
end)

collapseBtn.MouseButton1Click:Connect(function()
	setPanelOpen(not panelOpen)
end)

-- ============================================================
-- DRAG
-- ============================================================
local dragging, dragStart, startPos = false, nil, nil

frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging  = true
		dragStart = input.Position
		startPos  = frame.Position
	end
end)

frame.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
		dragging = false
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if not dragging then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end
end)

-- ============================================================
-- FPS + PING
-- ============================================================
local frameCount = 0
local lastTime   = tick()

RunService.RenderStepped:Connect(function()
	frameCount += 1
	local now     = tick()
	local elapsed = now - lastTime
	if elapsed < 1 then return end

	local fps = math.round(frameCount / elapsed)
	fpsLabel.Text = "FPS: " .. fps
	fpsLabel.TextColor3 =
		fps >= 60 and Color3.fromRGB(0, 230, 0)   or
		fps >= 30 and Color3.fromRGB(255, 195, 0) or
		Color3.fromRGB(255, 50, 50)

	local ok, ping = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok then
		pingLabel.Text = "Ping: " .. math.round(ping) .. "ms"
		pingLabel.TextColor3 =
			ping < 80  and Color3.fromRGB(0, 230, 0)   or
			ping < 150 and Color3.fromRGB(255, 195, 0) or
			Color3.fromRGB(255, 50, 50)
	end

	frameCount = 0
	lastTime   = now
end)

-- ============================================================
-- LAG REDUCER NHẸ
-- ============================================================
local function applyLagReduction()
	settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
	Lighting.GlobalShadows = false
	Lighting.FogEnd = 9e9
	for _, e in ipairs(Lighting:GetChildren()) do
		if e:IsA("BloomEffect") or e:IsA("BlurEffect") or e:IsA("SunRaysEffect")
			or e:IsA("ColorCorrectionEffect") or e:IsA("DepthOfFieldEffect") then
			e.Enabled = false
		end
	end
	workspace.StreamingEnabled = true
	local n = 0
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and n < 500 then
			obj.CastShadow = false
			n += 1
		end
	end
end

local function resetQuality()
	settings().Rendering.QualityLevel = Enum.QualityLevel.Automatic
	Lighting.GlobalShadows = true
	for _, e in ipairs(Lighting:GetChildren()) do
		if e:IsA("BloomEffect") or e:IsA("BlurEffect") or e:IsA("SunRaysEffect")
			or e:IsA("ColorCorrectionEffect") or e:IsA("DepthOfFieldEffect") then
			e.Enabled = true
		end
	end
end

-- ============================================================
-- NUKE (batch để không treo)
-- ============================================================
local BATCH = 80  -- xử lý bao nhiêu obj mỗi frame

local function isCharPart(obj)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and obj:IsDescendantOf(p.Character) then return true end
	end
	return false
end

local function applyNuke()
	hiddenObjects = {}
	local all = workspace:GetDescendants()
	local i   = 1
	task.spawn(function()
		while i <= #all do
			local batch_end = math.min(i + BATCH - 1, #all)
			for j = i, batch_end do
				local obj = all[j]
				if not obj or not obj.Parent then continue end
				if isCharPart(obj) then continue end

				if obj:IsA("Decal") or obj:IsA("Texture") then
					if obj.Transparency < 1 then
						table.insert(hiddenObjects, {obj=obj, prop="Transparency", val=obj.Transparency})
						obj.Transparency = 1
					end
				elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
					or obj:IsA("SelectionBox") or obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
					if obj.Enabled then
						table.insert(hiddenObjects, {obj=obj, prop="Enabled"})
						obj.Enabled = false
					end
				elseif obj:IsA("BasePart") then
					local n = obj.Name:lower()
					if n == "baseplate" or n == "spawnlocation" then continue end
					if obj.Transparency < 1 then
						table.insert(hiddenObjects, {obj=obj, prop="Transparency", val=obj.Transparency})
						obj.Transparency = 1
						obj.CastShadow   = false
					end
				elseif obj:IsA("Sound") and obj.Playing then
					obj:Stop()
					table.insert(hiddenObjects, {obj=obj, prop="Sound"})
				end
			end
			i = batch_end + 1
			task.wait()  -- nhường frame, không treo
		end
	end)
end

local function restoreNuke()
	for _, entry in ipairs(hiddenObjects) do
		local obj = entry.obj
		if not obj or not obj.Parent then continue end
		if entry.prop == "Enabled" then
			obj.Enabled = true
		elseif entry.prop == "Transparency" then
			obj.Transparency = entry.val or 0
		end
	end
	hiddenObjects = {}
end

-- ============================================================
-- BUTTON EVENTS
-- ============================================================
lagBtn.MouseButton1Click:Connect(function()
	lagEnabled = not lagEnabled
	if lagEnabled then
		applyLagReduction()
		lagBtn.Text = "✅ Đang Giảm Lag"
		lagBtn.BackgroundColor3 = Color3.fromRGB(25, 110, 25)
	else
		resetQuality()
		lagBtn.Text = "⚡ Bật Giảm Lag"
		lagBtn.BackgroundColor3 = Color3.fromRGB(35, 90, 35)
	end
end)

nukeBtn.MouseButton1Click:Connect(function()
	nukeEnabled = not nukeEnabled
	if nukeEnabled then
		applyNuke()
		nukeBtn.Text = "✅ Đã Xoá Vật Thể"
		nukeBtn.BackgroundColor3 = Color3.fromRGB(150, 25, 25)
	else
		restoreNuke()
		nukeBtn.Text = "💣 Xoá Vật Thể (Mạnh)"
		nukeBtn.BackgroundColor3 = Color3.fromRGB(110, 35, 35)
	end
end)

resetBtn.MouseButton1Click:Connect(function()
	lagEnabled  = false
	nukeEnabled = false
	resetQuality()
	restoreNuke()
	lagBtn.Text  = "⚡ Bật Giảm Lag"
	lagBtn.BackgroundColor3  = Color3.fromRGB(35, 90, 35)
	nukeBtn.Text = "💣 Xoá Vật Thể (Mạnh)"
	nukeBtn.BackgroundColor3 = Color3.fromRGB(110, 35, 35)
end)

