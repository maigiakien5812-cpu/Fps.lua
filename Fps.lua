--[[
	Server Stats HUD
	Hiện: số người trong server | FPS (xanh/vàng/đỏ) | Ping (xanh/vàng/đỏ)
	Nằm ngay cạnh nút chat, có nút thu gọn trượt ngang (mặc định mở).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer

-- ================= CẤU HÌNH =================
local CONFIG = {
	OffsetX = 172,     -- cách mép trái màn hình (px). Tăng lên nếu bị đè nút chat, giảm nếu cách xa
	OffsetY = 18,      -- cách mép trên (px). Chỉnh cho thẳng hàng với nút chat
	Height = 32,       -- chiều cao thanh
	StartOpen = true,  -- mặc định mở
	UpdateRate = 0.5,  -- giây giữa mỗi lần cập nhật số
}

local COLORS = {
	Good = Color3.fromRGB(80, 255, 120),   -- mạnh
	Mid  = Color3.fromRGB(255, 205, 60),   -- trung bình
	Bad  = Color3.fromRGB(255, 70, 70),    -- yếu
	Text = Color3.fromRGB(255, 255, 255),
	Back = Color3.fromRGB(20, 20, 25),
}

-- FPS: >=50 mạnh | 30-49 trung bình | <30 yếu
local function fpsColor(fps)
	if fps >= 50 then
		return COLORS.Good
	elseif fps >= 30 then
		return COLORS.Mid
	end
	return COLORS.Bad
end

-- Ping: <=100 tốt | 101-200 trung bình | >200 yếu
local function pingColor(ms)
	if ms <= 100 then
		return COLORS.Good
	elseif ms <= 200 then
		return COLORS.Mid
	end
	return COLORS.Bad
end

local function getPing()
	local ok, value = pcall(function()
		return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
	end)
	if ok and value then
		return math.floor(value + 0.5)
	end
	return 0
end

-- ================= TẠO GIAO DIỆN =================
local GUI_NAME = "ServerStatsHUD"

local function getParent()
	local ok, ui = pcall(function()
		return gethui and gethui()
	end)
	if ok and ui then
		return ui
	end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local parent = getParent()
local old = parent:FindFirstChild(GUI_NAME)
if old then
	old:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = parent

local H = CONFIG.Height
local HOLDER_WIDTH = 280

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Position = UDim2.fromOffset(CONFIG.OffsetX, CONFIG.OffsetY)
root.Size = UDim2.fromOffset(H + 4 + HOLDER_WIDTH, H)
root.Parent = gui

-- Nút thu gọn / mở ra
local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.AutoButtonColor = false
toggle.Size = UDim2.fromOffset(H, H)
toggle.Position = UDim2.fromOffset(0, 0)
toggle.BackgroundColor3 = COLORS.Back
toggle.BackgroundTransparency = 0.3
toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 18
toggle.TextColor3 = COLORS.Text
toggle.Text = "<"
toggle.ZIndex = 3
toggle.Parent = root

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggle

-- Khung cắt: phần nội dung trượt vào/ra trong khung này
local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.ClipsDescendants = true
holder.Position = UDim2.fromOffset(H + 4, 0)
holder.Size = UDim2.fromOffset(HOLDER_WIDTH, H)
holder.Parent = root

local content = Instance.new("Frame")
content.Name = "Content"
content.BackgroundColor3 = COLORS.Back
content.BackgroundTransparency = 0.3
content.BorderSizePixel = 0
content.Size = UDim2.fromScale(1, 1)
content.Parent = holder

local contentCorner = Instance.new("UICorner")
contentCorner.CornerRadius = UDim.new(0, 8)
contentCorner.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 4)
layout.Parent = content

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 8)
pad.PaddingRight = UDim.new(0, 8)
pad.Parent = content

local function makeLabel(order, width)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(0, width, 1, 0)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 14
	l.TextColor3 = COLORS.Text
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Text = "..."
	l.Parent = content
	return l
end

local playersLabel = makeLabel(1, 108)
local fpsLabel = makeLabel(2, 64)
local pingLabel = makeLabel(3, 88)

-- ================= THU GỌN / MỞ RA =================
local isOpen = CONFIG.StartOpen
local OPEN_POS = UDim2.new(0, 0, 0, 0)
local CLOSED_POS = UDim2.new(-1, -8, 0, 0)
local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function applyState(animate)
	local target = isOpen and OPEN_POS or CLOSED_POS
	toggle.Text = isOpen and "<" or ">"
	if animate then
		TweenService:Create(content, tweenInfo, { Position = target }):Play()
	else
		content.Position = target
	end
end

applyState(false)

toggle.Activated:Connect(function()
	isOpen = not isOpen
	applyState(true)
end)

-- ================= CẬP NHẬT SỐ LIỆU =================
local function updatePlayers()
	playersLabel.Text = ("Players %d/%d"):format(#Players:GetPlayers(), Players.MaxPlayers)
end

local function updatePing()
	local ms = getPing()
	pingLabel.Text = ("Ping %dms"):format(ms)
	pingLabel.TextColor3 = pingColor(ms)
end

local function updateFps(fps)
	fps = math.floor(fps + 0.5)
	fpsLabel.Text = ("FPS %d"):format(fps)
	fpsLabel.TextColor3 = fpsColor(fps)
end

updatePlayers()
updatePing()
updateFps(60)

local frames = 0
local last = os.clock()

local conn
conn = RunService.RenderStepped:Connect(function()
	frames += 1
	local now = os.clock()
	local dt = now - last
	if dt >= CONFIG.UpdateRate then
		updateFps(frames / dt)
		updatePing()
		updatePlayers()
		frames = 0
		last = now
	end
end)

Players.PlayerAdded:Connect(updatePlayers)
Players.PlayerRemoving:Connect(function()
	task.defer(updatePlayers)
end)

gui.Destroying:Connect(function()
	if conn then
		conn:Disconnect()
	end
end)
