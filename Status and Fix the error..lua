-- Server Stats HUD v4 - Blox Fruits / Delta (Android)
-- HUD SV/FPS/Ping/Hop; auto-hop theo chu ky; retry sau 20s neu that bai.
-- Phat hien giat qua lai thi thu reset nhan vat, khong hop server vi ly do nay.
-- Luu y: giao thuc Server Browser noi bo co the thay doi; khong dam bao hop thanh cong.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    OffsetX = 172,
    OffsetY = 23,
    Height = 22,
    TextSize = 11,
    StartOpen = true,
    UpdateRate = 0.5,

    AutoHop = true,
    HopMinutes = 20,
    RetrySeconds = 20,
    MinPlayers = 2,
    UseGameBrowser = true,

    ConflictReset = true,
    GraceSeconds = 15,
    ResetCooldown = 25,
    CheckJitter = true,
    JitterStuds = 3,
    JitterCount = 8,
    JitterWindow = 2,
    CheckSnap = true,
    SnapStuds = 3,
    SnapCount = 3,
    SnapWindow = 8,
    SnapLookback = 1.5,
    CheckMovers = false, -- tat mac dinh de tranh reset nham do ky nang/vat ly game
    MoverSeconds = 3,

    -- Neu co URL RAW, co the thu queue script chay lai sau khi teleport.
    -- De trong neu chua host script tren raw URL.
    ScriptURL = "",
}

local function notify(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = "Server HUD", Text = tostring(msg), Duration = 5
        })
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

    local function make(class, props, parent)
        local obj = Instance.new(class)
        for k, v in pairs(props) do obj[k] = v end
        obj.Parent = parent
        return obj
    end

    local function getPing()
        local ok, value = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        return (ok and value) and math.floor(value + 0.5) or 0
    end

    local function fpsColor(n)
        if n >= 50 then return COLORS.Good end
        if n >= 30 then return COLORS.Mid end
        return COLORS.Bad
    end
    local function pingColor(n)
        if n <= 100 then return COLORS.Good end
        if n <= 200 then return COLORS.Mid end
        return COLORS.Bad
    end
    local function formatTime(s)
        return string.format("%02d:%02d", math.floor(s / 60), s % 60)
    end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end

    local H = CONFIG.Height
    local WIDTH_ON, WIDTH_OFF = 248, 184
    local hopEnabled = CONFIG.AutoHop
    local holderWidth = hopEnabled and WIDTH_ON or WIDTH_OFF
    local gui = make("ScreenGui", {
        Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
        DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, playerGui)

    local root = make("Frame", {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(CONFIG.OffsetX, CONFIG.OffsetY),
        Size = UDim2.fromOffset(H + 3 + holderWidth, H),
    }, gui)
    local toggle = make("TextButton", {
        AutoButtonColor = false, Size = UDim2.fromOffset(H, H),
        BackgroundColor3 = COLORS.Back, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = COLORS.Text, Text = "<", ZIndex = 3,
    }, root)
    make("UICorner", {CornerRadius = UDim.new(0, 6)}, toggle)

    local holder = make("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(H + 3, 0),
        Size = UDim2.fromOffset(holderWidth, H),
    }, root)
    local content = make("Frame", {
        BackgroundColor3 = COLORS.Back, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
    }, holder)
    make("UICorner", {CornerRadius = UDim.new(0, 6)}, content)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
    }, content)
    make("UIPadding", {PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6)}, content)

    local function makeLabel(order, width)
        return make("TextLabel", {
            LayoutOrder = order, BackgroundTransparency = 1,
            Size = UDim2.new(0, width, 1, 0), Font = Enum.Font.GothamBold,
            TextSize = CONFIG.TextSize, TextColor3 = COLORS.Text,
            TextXAlignment = Enum.TextXAlignment.Center, Text = "...",
        }, content)
    end
    local playersLabel = makeLabel(1, 54)
    local fpsLabel = makeLabel(2, 48)
    local pingLabel = makeLabel(3, 42)
    local switchBtn = make("TextButton", {
        LayoutOrder = 4, AutoButtonColor = false, BackgroundTransparency = 1,
        Text = "", Size = UDim2.new(0, 22, 1, 0),
    }, content)
    local switchBox = make("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(12, 12), BorderSizePixel = 0,
        BackgroundColor3 = COLORS.Good,
    }, switchBtn)
    make("UICorner", {CornerRadius = UDim.new(0, 3)}, switchBox)
    local switchStroke = make("UIStroke", {Color = COLORS.Good, Thickness = 1.5}, switchBox)
    local hopLabel = makeLabel(5, 62)

    local isOpen = CONFIG.StartOpen
    local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local function applyState(animate)
        local target = isOpen and UDim2.new(0, 0, 0, 0) or UDim2.new(-1, -8, 0, 0)
        toggle.Text = isOpen and "<" or ">"
        if animate then TweenService:Create(content, tweenInfo, {Position = target}):Play()
        else content.Position = target end
    end
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
        if animate then TweenService:Create(holder, tweenInfo, {Size = size}):Play()
        else holder.Size = size end
    end
    applyState(false)
    applySwitch(false)
    table.insert(connections, toggle.Activated:Connect(function()
        isOpen = not isOpen
        applyState(true)
    end))

    -- Auto-hop: dung Browser noi bo neu tim thay, neu khong thi fallback Public Servers API.
    local INTERVAL = math.max(1, CONFIG.HopMinutes) * 60
    local nextHop = os.clock() + INTERVAL
    local hopping = false
    local attempts = 0
    local failedIds = {}
    local lastTarget = nil
    local retryAt = 0
    local hopToken = 0

    local function queueScript()
        if CONFIG.ScriptURL == "" then return end
        pcall(function()
            local queue = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
            if queue then queue('loadstring(game:HttpGet("' .. CONFIG.ScriptURL .. '"))()') end
        end)
    end

    local function pickPublicServer()
        local target
        local ok, err = pcall(function()
            local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true", game.PlaceId)
            local data = HttpService:JSONDecode(game:HttpGet(url))
            local strict, loose = {}, {}
            for _, s in ipairs(data.data or {}) do
                if s.id ~= game.JobId and not failedIds[s.id] and s.playing and s.maxPlayers and s.playing < s.maxPlayers then
                    table.insert(loose, s.id)
                    if s.playing >= CONFIG.MinPlayers and s.playing <= s.maxPlayers - 2 then
                        table.insert(strict, s.id)
                    end
                end
            end
            local pool = #strict > 0 and strict or loose
            if #pool > 0 then target = pool[math.random(1, #pool)] end
        end)
        if not ok then warn("[ServerStatsHUD] Khong lay duoc server cong khai: " .. tostring(err)) end
        return target
    end

    local function tryGameBrowser()
        local browser = ReplicatedStorage:FindFirstChild("__ServerBrowser", true)
        if not browser or not browser:IsA("RemoteFunction") then return false, "Khong tim thay Server Browser RemoteFunction" end
        local strict, loose = {}, {}
        local maxP = Players.MaxPlayers
        for page = 1, 4 do
            local ok, servers = pcall(function() return browser:InvokeServer(page) end)
            if not ok or type(servers) ~= "table" then break end
            local any = false
            for id, info in pairs(servers) do
                any = true
                local count = type(info) == "table" and tonumber(info.Count) or nil
                if count and id ~= game.JobId and not failedIds[id] and count < maxP then
                    table.insert(loose, id)
                    if count >= CONFIG.MinPlayers and count <= maxP - 2 then table.insert(strict, id) end
                end
            end
            if not any or #strict >= 10 then break end
        end
        local pool = #strict > 0 and strict or loose
        if #pool == 0 then return false, "Browser khong tra ve server phu hop" end
        local target = pool[math.random(1, #pool)]
        lastTarget = target
        queueScript()
        local ok, result = pcall(function() return browser:InvokeServer("teleport", target) end)
        if not ok then return false, tostring(result) end
        return true
    end

    local function scheduleRetry(reason)
        attempts = attempts + 1
        if lastTarget then failedIds[lastTarget] = true end
        hopping = false
        retryAt = os.clock() + CONFIG.RetrySeconds
        nextHop = retryAt
        hopLabel.Text = "Retry 00:20"
        hopLabel.TextColor3 = COLORS.Bad
        warn("[ServerStatsHUD] Hop that bai lan " .. attempts .. ": " .. tostring(reason) .. "; thu lai sau 20s")
        notify("Hop that bai. Thu lai sau 20 giay")
    end

    local function serverHop()
        if hopping or not hopEnabled then return end
        hopping = true
        hopToken = hopToken + 1
        local myToken = hopToken
        hopLabel.Text = "Hop..."
        hopLabel.TextColor3 = COLORS.Mid
        task.spawn(function()
            local issued, reason = false, "Khong co phuong thuc hop thanh cong"
            if CONFIG.UseGameBrowser then
                local ok, result, detail = pcall(tryGameBrowser)
                if ok and result == true then issued = true
                else reason = ok and (detail or result or reason) or result end
            end
            if not issued then
                local target = pickPublicServer()
                lastTarget = target
                queueScript()
                if target then
                    local ok, err = pcall(function()
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, target, LocalPlayer)
                    end)
                    if ok then
                        -- Lenh duoc gui; cho su kien TeleportInitFailed hoac timeout.
                        issued = true
                    else
                        reason = tostring(err)
                    end
                else
                    reason = "Khong lay duoc server cong khai (HTTP/Get co the bi Delta chan)"
                end
            end
            if not issued then
                scheduleRetry(reason)
                return
            end
            task.delay(25, function()
                if hopping and hopToken == myToken then
                    scheduleRetry("Qua 25 giay chua chuyen server")
                end
            end)
        end)
    end

    table.insert(connections, TeleportService.TeleportInitFailed:Connect(function(_, result, message)
        if hopping then scheduleRetry(tostring(result) .. " | " .. tostring(message)) end
    end))

    -- Phat hien di chuyen giat qua lai: reset nhan vat thay vi hop server.
    local startTime = os.clock()
    local lastHrp, lastPos, lastDelta = nil, nil, nil
    local reversals, history, snaps = {}, {}, {}
    local lastReset = 0
    local resetting = false
    local function resetCharacter(reason)
        local now = os.clock()
        if not CONFIG.ConflictReset or resetting or now - lastReset < CONFIG.ResetCooldown then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        resetting = true
        lastReset = now
        notify("Phat hien giat bat thuong (" .. reason .. "). Dang reset nhan vat")
        -- Thu yeu cau reset nhan vat trong server hien tai.
        local ok = pcall(function() hum.Health = 0 end)
        if not ok then warn("[ServerStatsHUD] Khong the reset Humanoid tu client") end
        task.delay(8, function() resetting = false end)
        reversals, history, snaps = {}, {}, {}
        lastHrp, lastPos, lastDelta = nil, nil, nil
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
            if lastDelta and delta:Dot(lastDelta) < 0 then table.insert(reversals, now) end
            lastDelta = delta
        else
            lastDelta = nil
        end
        while reversals[1] and now - reversals[1] > CONFIG.JitterWindow do table.remove(reversals, 1) end
        if #reversals >= CONFIG.JitterCount then resetCharacter("jitter") end
    end

    local function checkSnap(hrp, now)
        local pos = hrp.Position
        table.insert(history, {now, pos})
        while history[1] and now - history[1][1] > CONFIG.SnapLookback do table.remove(history, 1) end
        if #history < 3 then return end
        local prev = history[#history - 1][2]
        local delta = pos - prev
        local drift = prev - history[1][2]
        if delta:Dot(drift) < 0 and delta.Magnitude >= CONFIG.SnapStuds and drift.Magnitude >= CONFIG.SnapStuds * 0.5 then
            table.insert(snaps, now)
        end
        while snaps[1] and now - snaps[1] > CONFIG.SnapWindow do table.remove(snaps, 1) end
        if #snaps >= CONFIG.SnapCount then resetCharacter("snap-back") end
    end

    table.insert(connections, RunService.Heartbeat:Connect(function()
        if not hopEnabled or not CONFIG.ConflictReset or os.clock() - startTime < CONFIG.GraceSeconds then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then
            lastHrp, lastPos, lastDelta = nil, nil, nil
            return
        end
        if CONFIG.CheckJitter then checkJitter(hrp, os.clock()) end
        if CONFIG.CheckSnap then checkSnap(hrp, os.clock()) end
    end))

    table.insert(connections, switchBtn.Activated:Connect(function()
        hopEnabled = not hopEnabled
        if hopEnabled then
            attempts = 0
            retryAt = 0
            nextHop = os.clock() + INTERVAL
            hopLabel.Text = "Hop " .. formatTime(INTERVAL)
            hopLabel.TextColor3 = COLORS.Text
        else
            hopping = false
        end
        applySwitch(true)
    end))

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
        if not hopEnabled then return end
        if hopping then return end
        local now = os.clock()
        local remaining = math.max(0, math.ceil(nextHop - now))
        hopLabel.Text = "Hop " .. formatTime(remaining)
        if remaining <= 10 then hopLabel.TextColor3 = COLORS.Bad
        elseif remaining <= 60 then hopLabel.TextColor3 = COLORS.Mid
        else hopLabel.TextColor3 = COLORS.Text end
        if remaining <= 0 and now >= retryAt then serverHop() end
    end

    updatePlayers(); updatePing(); updateFps(60); updateHop()
    local frames, last = 0, os.clock()
    table.insert(connections, RunService.RenderStepped:Connect(function()
        frames = frames + 1
        local now = os.clock()
        local dt = now - last
        if dt >= CONFIG.UpdateRate then
            updateFps(frames / dt)
            updatePing(); updatePlayers(); updateHop()
            frames, last = 0, now
        end
    end))
    table.insert(connections, Players.PlayerAdded:Connect(updatePlayers))
    table.insert(connections, Players.PlayerRemoving:Connect(function() task.defer(updatePlayers) end))
    gui.Destroying:Connect(function()
        for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    end)
    notify("HUD da chay - v4")
end

local ok, err = xpcall(run, function(e)
    return tostring(e) .. "\n" .. tostring(debug.traceback())
end)
if not ok then
    warn("[ServerStatsHUD] LOI: " .. tostring(err))
    notify("Loi: " .. string.sub(tostring(err), 1, 150))
end
