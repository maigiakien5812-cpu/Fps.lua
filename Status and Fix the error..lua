-- Server Stats HUD v3: SV | FPS | Ping | Hop
-- Tu hop server moi 20 phut + phat hien xung dot bay -> hop ngay.
-- Chay xong se hien thong bao "HUD da chay". Neu loi se hien thong bao loi.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
	OffsetX = 172,       -- cach mep trai (px), chinh cho sat nut chat
	OffsetY = 23,        -- cach mep tren (px)
	Height = 22,
	TextSize = 11,
	StartOpen = true,    -- mac dinh mo
	UpdateRate = 0.5,
	UseHiddenUI = false, -- true = dung gethui() (neu HUD khong hien thi thi de false)

	AutoHop = true,
	HopMinutes = 20,
	RetrySeconds = 10,   -- hop loi thi thu lai sau X giay (loi nhieu lan thi cho lau hon)
	MinPlayers = 2,      -- uu tien server tu X nguoi tro len

	ConflictHop = true,  -- phat hien xung dot bay -> hop ngay
	GraceSeconds = 15,   -- bo qua X giay dau
	CheckMovers = true,  -- co >= 2 BodyVelocity/BodyPosition... cung loai
	MoverSeconds = 3,
	CheckJitter = true,  -- nhan vat giat qua lai lien tuc
	JitterStuds = 3,
	JitterCount = 20,
	JitterWindow = 2,
	CheckSnap = true,    -- bi keo toi roi giat nguoc ve cho cu, lap lai (kieu giat thuong gap)
	SnapStuds = 3,       -- giat nguoc >= X studs trong 1 khung hinh thi tinh la 1 lan
	SnapCount = 3,       -- du X lan trong SnapWindow giay thi hop
	SnapWindow = 8,
	SnapLookback = 1.5,  -- so sanh voi vi tri cach day X giay
	DebugSnap = false,   -- true = hien thong bao moi lan bat duoc 1 cu giat (de chinh SnapStuds)

	ScriptURL = "",      -- link RAW cua script nay (de tu chay lai sau khi hop)
}

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Server HUD", Text = text, Duration = 5 })
	end)
end

local function run()
	local GUI_NAME = "ServerStatsHUD"
	local connections = {}

	local COLORS = {
		Good = Color3.fromRGB(80, 255, 120),
		Mid = Color3.fromRGB(255, 205, 60),
		Bad = Color3.fromRGB(255, 70, 70),
		Text = Color3.fromRGB(255, 255, 255),
		Back = Color3.fromRGB(20, 20, 25),
	}

	local function fpsColor(fps)
		if fps >= 50 then
			return COLORS.Good
		elseif fps >= 30 then
			return COLORS.Mid
		end
		return COLORS.Bad
	end

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
		return string.format("%02d:%02d", math.floor(s / 60), s % 60)
	end

	-- ============ GIAO DIEN ============
	local function make(class, props, parent)
		local inst = Instance.new(class)
		for k, v in pairs(props) do
			inst[k] = v
		end
		inst.Parent = parent
		return inst
	end

	local playerGui = LocalPlayer:WaitForChild("PlayerGui")
	local parent = playerGui
	if CONFIG.UseHiddenUI then
		local ok, ui = pcall(function()
			return gethui and gethui()
		end)
		if ok and ui then
			parent = ui
		end
	end
	for _, p in ipairs({ playerGui, parent }) do
		local old = p:FindFirstChild(GUI_NAME)
		if old then
			old:Destroy()
		end
	end

	local H = CONFIG.Height
	local WIDTH_ON = 248   -- do rong khung khi hop BAT (co o vuong + dong ho)
	local WIDTH_OFF = 184  -- do rong khung khi hop TAT (chi con o vuong)
	local hopEnabled = CONFIG.AutoHop
	local HOLDER_WIDTH = hopEnabled and WIDTH_ON or WIDTH_OFF

	local gui = make("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 999,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, parent)

	local root = make("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(CONFIG.OffsetX, CONFIG.OffsetY),
		Size = UDim2.fromOffset(H + 3 + HOLDER_WIDTH, H),
	}, gui)

	local toggle = make("TextButton", {
		AutoButtonColor = false,
		Size = UDim2.fromOffset(H, H),
		BackgroundColor3 = COLORS.Back,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextColor3 = COLORS.Text,
		Text = "<",
		ZIndex = 3,
	}, root)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, toggle)

	local holder = make("Frame", {
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Position = UDim2.fromOffset(H + 3, 0),
		Size = UDim2.fromOffset(HOLDER_WIDTH, H),
	}, root)

	local content = make("Frame", {
		BackgroundColor3 = COLORS.Back,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, holder)
	make("UICorner", { CornerRadius = UDim.new(0, 6) }, content)
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 2),
	}, content)
	make("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, content)

	local function makeLabel(order, width)
		return make("TextLabel", {
			LayoutOrder = order,
			BackgroundTransparency = 1,
			Size = UDim2.new(0, width, 1, 0),
			Font = Enum.Font.GothamBold,
			TextSize = CONFIG.TextSize,
			TextColor3 = COLORS.Text,
			TextXAlignment = Enum.TextXAlignment.Center,
			Text = "...",
		}, content)
	end

	local playersLabel = makeLabel(1, 54)
	local fpsLabel = makeLabel(2, 48)
	local pingLabel = makeLabel(3, 42)

	-- O vuong nho bat/tat hop: bat = to day mau, tat = chi con khung vien
	local switchBtn = make("TextButton", {
		LayoutOrder = 4,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.new(0, 22, 1, 0),
	}, content)
	local switchBox = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(12, 12),
		BorderSizePixel = 0,
		BackgroundColor3 = COLORS.Good,
	}, switchBtn)
	make("UICorner", { CornerRadius = UDim.new(0, 3) }, switchBox)
	local switchStroke = make("UIStroke", { Color = COLORS.Good, Thickness = 1.5 }, switchBox)

	local hopLabel = makeLabel(5, 62)

	-- ============ THU GON / MO RA ============
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

	-- Ve lai o vuong + dong ho theo trang thai bat/tat hop
	local function applySwitch(animate)
		if hopEnabled then
			switchBox.BackgroundTransparency = 0
			switchBox.BackgroundColor3 = COLORS.Good
			switchStroke.Color = COLORS.Good
			hopLabel.Visible = true
		else
			switchBox.BackgroundTransparency = 1
			switchStroke.Color = COLORS.Text
			hopLabel.Visible = false
		end
		local size = UDim2.fromOffset(hopEnabled and WIDTH_ON or WIDTH_OFF, H)
		if animate then
			TweenService:Create(holder, tweenInfo, { Size = size }):Play()
		else
			holder.Size = size
		end
	end
	applySwitch(false)

	table.insert(connections, toggle.Activated:Connect(function()
		isOpen = not isOpen
		applyState(true)
	end))

	-- ============ HOP SERVER ============
	local INTERVAL = math.max(1, CONFIG.HopMinutes) * 60
	local nextHop = os.clock() + INTERVAL
	local hopping = false
	local hopId = 0
	local failedIds = {}
	local attempts = 0
	local lastTarget = nil
	local retryAt = 0

	local function queueScript()
		if CONFIG.ScriptURL == "" then
			return
		end
		pcall(function()
			local queue = queue_on_teleport
				or (syn and syn.queue_on_teleport)
				or (fluxus and fluxus.queue_on_teleport)
			if queue then
				queue('loadstring(game:HttpGet("' .. CONFIG.ScriptURL .. '"))()')
			end
		end)
	end

	local function pickServer()
		local target = nil
		local ok, err = pcall(function()
			local url = string.format(
				"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true",
				game.PlaceId
			)
			local data = HttpService:JSONDecode(game:HttpGet(url))
			local strict, loose = {}, {}
			for _, s in ipairs(data.data or {}) do
				if s.id ~= game.JobId
					and not failedIds[s.id]
					and s.playing and s.maxPlayers
					and s.playing < s.maxPlayers then
					table.insert(loose, s.id)
					if s.playing >= CONFIG.MinPlayers and s.playing <= s.maxPlayers - 2 then
						table.insert(strict, s.id)
					end
				end
			end
			local pool = #strict > 0 and strict or loose
			if #pool > 0 then
				target = pool[math.random(#pool)]
			end
		end)
		if not ok then
			warn("[ServerStatsHUD] Lay danh sach server loi: " .. tostring(err))
		end
		return target
	end

	local function onHopFailed(reason)
		attempts = attempts + 1
		if lastTarget then
			failedIds[lastTarget] = true
		end
		warn("[ServerStatsHUD] Hop loi lan " .. attempts .. ": " .. tostring(reason))
		local delayTime = math.min(CONFIG.RetrySeconds * attempts, 60)
		hopping = false
		nextHop = os.clock() + delayTime
		retryAt = nextHop
	end

	local function serverHop(conflict)
		if hopping then
			return
		end
		hopping = true
		hopId = hopId + 1
		local myId = hopId
		hopLabel.Text = conflict and "Conflict!" or "Hop..."
		hopLabel.TextColor3 = conflict and COLORS.Bad or COLORS.Mid

		task.spawn(function()
			local target = nil
			if attempts < 3 then
				target = pickServer()
			end
			lastTarget = target
			queueScript()
			pcall(function()
				if target then
					TeleportService:TeleportToPlaceInstance(game.PlaceId, target, LocalPlayer)
				else
					TeleportService:Teleport(game.PlaceId, LocalPlayer)
				end
			end)
			task.delay(20, function()
				if hopping and hopId == myId then
					onHopFailed("qua 20s chua di duoc")
				end
			end)
		end)
	end

	table.insert(connections, TeleportService.TeleportInitFailed:Connect(function(_, result, message)
		onHopFailed(tostring(result) .. " | " .. tostring(message))
	end))

	-- ============ PHAT HIEN XUNG DOT BAY ============
	local MOVER_CLASSES = {
		BodyVelocity = true,
		BodyPosition = true,
		BodyGyro = true,
		LinearVelocity = true,
		AlignPosition = true,
	}
	local startTime = os.clock()
	local blockedUntil = 0
	local lastHrp, lastPos, lastDelta = nil, nil, nil
	local reversals = {}
	local moverSince = nil
	local nextMoverCheck = 0
	local snapHrp = nil
	local history = {}
	local snaps = {}

	local function triggerConflict(reason)
		local now = os.clock()
		if hopping or not hopEnabled or now < blockedUntil or now < retryAt then
			return
		end
		blockedUntil = now + CONFIG.RetrySeconds
		reversals = {}
		snaps = {}
		moverSince = nil
		warn("[ServerStatsHUD] Xung dot bay (" .. reason .. ") -> doi server ngay")
		serverHop(true)
	end

	local function checkMovers(char, now)
		local counts = {}
		local dupClass = nil
		for _, d in ipairs(char:GetDescendants()) do
			if MOVER_CLASSES[d.ClassName] then
				counts[d.ClassName] = (counts[d.ClassName] or 0) + 1
				if counts[d.ClassName] >= 2 then
					dupClass = d.ClassName
					break
				end
			end
		end
		if dupClass then
			moverSince = moverSince or now
			if now - moverSince >= CONFIG.MoverSeconds then
				triggerConflict("2x " .. dupClass)
			end
		else
			moverSince = nil
		end
	end

	local function checkJitter(hrp, now)
		local pos = hrp.Position
		if hrp ~= lastHrp then
			lastHrp, lastPos, lastDelta = hrp, pos, nil
			reversals = {}
			return
		end
		local delta = pos - lastPos
		lastPos = pos
		if delta.Magnitude >= CONFIG.JitterStuds then
			if lastDelta and delta:Dot(lastDelta) < 0 then
				table.insert(reversals, now)
			end
			lastDelta = delta
		else
			lastDelta = nil
		end
		while reversals[1] and now - reversals[1] > CONFIG.JitterWindow do
			table.remove(reversals, 1)
		end
		if #reversals >= CONFIG.JitterCount then
			triggerConflict("jitter")
		end
	end

	-- Kieu giat "keo toi roi giat nguoc ve": vi tri troi dan theo 1 huong vai khung hinh
	-- roi bi giat nguoc ve gan cho cu trong 1 khung hinh, lap lai nhieu lan.
	local function checkSnap(hrp, now)
		if hrp ~= snapHrp then
			snapHrp = hrp
			history = {}
			snaps = {}
		end
		local pos = hrp.Position
		table.insert(history, { now, pos })
		while history[1] and now - history[1][1] > CONFIG.SnapLookback do
			table.remove(history, 1)
		end
		local n = #history
		if n < 3 then
			return
		end
		local prev = history[n - 1][2]
		local delta = pos - prev
		local drift = prev - history[1][2]
		local opposing = delta:Dot(drift) < 0
		if CONFIG.DebugSnap and opposing and delta.Magnitude >= 1 and drift.Magnitude >= 0.5 then
			notify(string.format("snap %.1f studs (troi %.1f)", delta.Magnitude, drift.Magnitude))
		end
		if opposing and delta.Magnitude >= CONFIG.SnapStuds and drift.Magnitude >= CONFIG.SnapStuds * 0.5 then
			table.insert(snaps, now)
		end
		while snaps[1] and now - snaps[1] > CONFIG.SnapWindow do
			table.remove(snaps, 1)
		end
		if #snaps >= CONFIG.SnapCount then
			triggerConflict("snap-back")
		end
	end

	table.insert(connections, RunService.Heartbeat:Connect(function()
		if not CONFIG.ConflictHop or not hopEnabled then
			return
		end
		local now = os.clock()
		if now - startTime < CONFIG.GraceSeconds then
			return
		end
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (hrp and hum) or hum.Health <= 0 then
			lastHrp = nil
			return
		end
		if CONFIG.CheckJitter then
			checkJitter(hrp, now)
		end
		if CONFIG.CheckSnap then
			checkSnap(hrp, now)
		end
		if CONFIG.CheckMovers and now >= nextMoverCheck then
			nextMoverCheck = now + 0.5
			checkMovers(char, now)
		end
	end))

	-- ============ NUT BAT/TAT HOP ============
	table.insert(connections, switchBtn.Activated:Connect(function()
		hopEnabled = not hopEnabled
		if hopEnabled then
			-- bat lai: dem nguoc lai tu dau, xoa trang thai cu
			attempts = 0
			retryAt = 0
			nextHop = os.clock() + INTERVAL
			reversals = {}
			snaps = {}
			history = {}
			moverSince = nil
			lastHrp = nil
			hopLabel.Text = "Hop " .. formatTime(INTERVAL)
			hopLabel.TextColor3 = COLORS.Text
		end
		applySwitch(true)
	end))

	-- ============ CAP NHAT SO LIEU ============
	local function updatePlayers()
		playersLabel.Text = string.format("SV %d/%d", #Players:GetPlayers(), Players.MaxPlayers)
	end

	local function updatePing()
		local ms = getPing()
		pingLabel.Text = ms .. "ms"
		pingLabel.TextColor3 = pingColor(ms)
	end

	local function updateFps(fps)
		fps = math.floor(fps + 0.5)
		fpsLabel.Text = "FPS " .. fps
		fpsLabel.TextColor3 = fpsColor(fps)
	end

	local function updateHop()
		if not hopEnabled then
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
		if remaining <= 0 and os.clock() >= retryAt then
			serverHop(false)
		end
	end

	updatePlayers()
	updatePing()
	updateFps(60)
	updateHop()

	local frames = 0
	local last = os.clock()
	table.insert(connections, RunService.RenderStepped:Connect(function()
		frames = frames + 1
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

	notify("HUD da chay")
end

local ok, err = xpcall(run, function(e)
	return tostring(e) .. "\n" .. tostring(debug.traceback())
end)
if not ok then
	warn("[ServerStatsHUD] LOI: " .. tostring(err))
	notify("Loi: " .. string.sub(tostring(err), 1, 150))
end
