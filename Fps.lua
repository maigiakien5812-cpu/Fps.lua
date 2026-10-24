--[[
	Server Stats HUD v2
	Hiện: số người (SV) | FPS | Ping | đếm ngược hop server
	Tự hop server mới mỗi 20 phút. Có nút thu gọn trượt ngang (mặc định mở).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- ================= CẤU HÌNH =================
local CONFIG = {
	OffsetX = 172,     -- cách mép trái (px), chỉnh cho nằm sát nút chat
	OffsetY = 23,      -- cách mép trên (px)
	Height = 22,       -- chiều cao thanh
	TextSize = 11,
	StartOpen = true,  -- mặc định mở
	UpdateRate = 0.5,  -- giây giữa mỗi lần cập nhật

	AutoHop = true,    -- bật/tắt tự hop
	HopMinutes = 20,   -- hop mỗi bao nhiêu phút
	RetrySeconds = 10, -- hop lỗi thì thử lại sau bao nhiêu giây

	-- (Tuỳ chọn) link RAW của script này. Điền vào thì sau khi hop script sẽ tự chạy lại
	-- (cần executor có queue_on_teleport). Để trống nếu executor của bạn có autoexec.
	ScriptURL = "",
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

local function formatTime(s)
	return ("%02d:%02d"):format(math.floor(s / 60), s % 60)
end

-- ================= TẠO GIAO DIỆN =================
local GUI_NAME = "ServerStatsHUD"
local connections = {}

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
local HOLDER_WIDTH = 224

local root = Instance.new("Frame")
root.Name = "Root"
root.BackgroundTransparency = 1
root.Position = UDim2.fromOffset(CONFIG.OffsetX, CONFIG.OffsetY)
root.Size = UDim2.fromOffset(H + 3 + HOLDER_WIDTH, H)
root.Parent = gui

-- Nút thu gọn / mở ra
local toggle = Instance.new("TextButton")
toggle.Name = "Toggle"
toggle.AutoButtonColor = false
toggle.Size = UDim2.fromOffset(H, H)
toggle.BackgroundColor3 = COLORS.Back
toggle.BackgroundTransparency = 0.3
toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 14
toggle.TextColor3 = COLORS.Text
toggle.Text = "<"
toggle.ZIndex = 3
toggle.Parent = root

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggle

-- Khung cắt: phần nội dung trượt vào/ra trong khung này
local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.BackgroundTransparency = 1
holder.ClipsDescendants = true
holder.Position = UDim2.fromOffset(H + 3, 0)
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
contentCorner.CornerRadius = UDim.new(0, 6)
contentCorner.Parent = content

local layout = Instance.new("UIListLayout")
layout.FillDirection = Enum.FillDirection.Horizontal
layout.VerticalAlignment = Enum.VerticalAlignment.Center
layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 2)
layout.Parent = content

local pad = Instance.new("UIPadding")
pad.PaddingLeft = UDim.new(0, 6)
pad.PaddingRight = UDim.new(0, 6)
pad.Parent = content

local function makeLabel(order, width)
	local l = Instance.new("TextLabel")
	l.LayoutOrder = order
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(0, width, 1, 0)
	l.Font = Enum.Font.GothamBold
	l.TextSize = CONFIG.TextSize
	l.TextColor3 = COLORS.Text
	l.TextXAlignment = Enum.TextXAlignment.Center
	l.Text = "..."
	l.Parent = content
	return l
end

local playersLabel = makeLabel(1, 54)
local fpsLabel = makeLabel(2, 48)
local pingLabel = makeLabel(3, 42)
local hopLabel = makeLabel(4, 62)

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

table.insert(connections, toggle.Activated:Connect(function()
	isOpen = not isOpen
	applyState(true)
end))

-- ================= HOP SERVER =================
local INTERVAL = math.max(1, CONFIG.HopMinutes) * 60
local nextHop = os.clock() + INTERVAL
local hopping = false

local function queueScript()
	if CONFIG.ScriptURL == "" then
		return
	end
	pcall(function()
		local queue = queue_on_teleport
			or (syn and syn.queue_on_teleport)
			or (fluxus and fluxus.queue_on_teleport)
		if queue then
			queue(('loadstring(game:HttpGet("%s"))()'):format(CONFIG.ScriptURL))
		end
	end)
end

local function pickServer()
	local target
	pcall(function()
		local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true")
			:format(game.PlaceId)
		local data = HttpService:JSONDecode(game:HttpGet(url))
		local candidates = {}
		for _, s in ipairs(data.data or {}) do
			if s.id ~= game.JobId and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
				table.insert(candidates, s.id)
			end
		end
		if #candidates > 0 then
			target = candidates[math.random(#candidates)]
		end
	end)
	return target
end

local function serverHop()
	if hopping then
		return
	end
	hopping = true
	hopLabel.Text = "Hop..."
	hopLabel.TextColor3 = COLORS.Mid

	task.spawn(function()
		local target = pickServer()
		queueScript()
		if target then
			pcall(function()
				TeleportService:TeleportToPlaceInstance(game.PlaceId, target, LocalPlayer)
			end)
		else
			-- không lấy được danh sách server -> teleport thường
			pcall(function()
				TeleportService:Teleport(game.PlaceId, LocalPlayer)
			end)
		end

		-- nếu 20s sau vẫn chưa đi được thì thử lại
		task.delay(20, function()
			if hopping then
				hopping = false
				nextHop = os.clock() + CONFIG.RetrySeconds
			end
		end)
	end)
end

table.insert(connections, TeleportService.TeleportInitFailed:Connect(function()
	hopping = false
	nextHop = os.clock() + CONFIG.RetrySeconds
end))

-- ================= CẬP NHẬT SỐ LIỆU =================
local function updatePlayers()
	playersLabel.Text = ("SV %d/%d"):format(#Players:GetPlayers(), Players.MaxPlayers)
end

local function updatePing()
	local ms = getPing()
	pingLabel.Text = ("%dms"):format(ms)
	pingLabel.TextColor3 = pingColor(ms)
end

local function updateFps(fps)
	fps = math.floor(fps + 0.5)
	fpsLabel.Text = ("FPS %d"):format(fps)
	fpsLabel.TextColor3 = fpsColor(fps)
end

local function updateHop()
	if not CONFIG.AutoHop then
		hopLabel.Text = "Hop: tắt"
		hopLabel.TextColor3 = COLORS.Text
		return
	end
	if hopping then
		return
	end
	local remaining = math.max(0, math.ceil(nextHop - os.clock()))
	hopLabel.Text = "Hop " .. formatTime(remaining)
	if remaining <= 10 then
		hopLabel.TextColor3 = COLORS.Bad
	elseif remaining <= 60 then
		hopLabel.TextColor3 = COLORS.Mid
	else
		hopLabel.TextColor3 = COLORS.Text
	end
	if remaining <= 0 then
		serverHop()
	end
end

updatePlayers()
updatePing()
updateFps(60)
updateHop()

local frames = 0
local last = os.clock()

table.insert(connections, RunService.RenderStepped:Connect(function()
	frames += 1
	local now = os.clock()
	local dt = now - last
	if dt >= CONFIG.UpdateRate then
		updateFps(frames / dt)
		updatePing()
		updatePlayers()
		updateHop()
		frames = 0
		last = now
	end
end))

table.insert(connections, Players.PlayerAdded:Connect(updatePlayers))
table.insert(connections, Players.PlayerRemoving:Connect(function()
	task.defer(updatePlayers)
end))

gui.Destroying:Connect(function()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
end)
