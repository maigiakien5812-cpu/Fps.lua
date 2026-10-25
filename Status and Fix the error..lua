-- Server Stats HUD v4.9 - visible 15-stud ring only
-- Removed all abnormal-movement detection. Reset is based only on the fixed horizontal ring.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer

local CONFIG = {
    OffsetX = 172, OffsetY = 23, Height = 22, TextSize = 11,
    StartOpen = true, UpdateRate = 0.5,

    ConflictReset = true,
    GraceSeconds = 15,
    ResetCooldown = 25,

    IgnoreAfterSeatSeconds = 3,
    IgnoreAfterSpawnSeconds = 5,
    StuckSeconds = 100,
    MinMoveStuds = 70,
    RingSegments = 72,
    RingDotSize = 0.7,
    RingRefreshDelay = 3,
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
        Good = Color3.fromRGB(80,255,120),
        Mid = Color3.fromRGB(255,205,60),
        Bad = Color3.fromRGB(255,70,70),
        Text = Color3.fromRGB(255,255,255),
        Back = Color3.fromRGB(20,20,25),
    }

    local function make(class, props, parent)
        local obj = Instance.new(class)
        for k,v in pairs(props) do obj[k] = v end
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
        s = math.max(0, math.floor(s))
        local hours = math.floor(s / 3600)
        local minutes = math.floor((s % 3600) / 60)
        local seconds = s % 60
        if hours > 0 then
            return string.format("%02d:%02d:%02d", hours, minutes, seconds)
        end
        return string.format("%02d:%02d", minutes, seconds)
    end

    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild(GUI_NAME)
    if old then old:Destroy() end

    local H = CONFIG.Height
    local holderWidth = 232

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
        AutoButtonColor = false, Size = UDim2.fromOffset(H,H),
        BackgroundColor3 = COLORS.Back, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 14,
        TextColor3 = COLORS.Text, Text = "<", ZIndex = 3,
    }, root)
    make("UICorner", {CornerRadius = UDim.new(0,6)}, toggle)
    local holder = make("Frame", {
        BackgroundTransparency = 1, ClipsDescendants = true,
        Position = UDim2.fromOffset(H+3,0), Size = UDim2.fromOffset(holderWidth,H),
    }, root)
    local content = make("Frame", {
        BackgroundColor3 = COLORS.Back, BackgroundTransparency = 0.3,
        BorderSizePixel = 0, Size = UDim2.fromScale(1,1),
    }, holder)
    make("UICorner", {CornerRadius = UDim.new(0,6)}, content)
    make("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Left,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0,2),
    }, content)
    make("UIPadding", {
        PaddingLeft = UDim.new(0,6), PaddingRight = UDim.new(0,6),
    }, content)

    local function makeLabel(order, width)
        return make("TextLabel", {
            LayoutOrder = order, BackgroundTransparency = 1,
            Size = UDim2.new(0,width,1,0), Font = Enum.Font.GothamBold,
            TextSize = CONFIG.TextSize, TextColor3 = COLORS.Text,
            TextXAlignment = Enum.TextXAlignment.Center, Text = "...",
        }, content)
    end
    local playersLabel = makeLabel(1,54)
    local fpsLabel = makeLabel(2,48)
    local pingLabel = makeLabel(3,42)
    local elapsedLabel = makeLabel(4,66)
    elapsedLabel.Text = "00:00"

    local isOpen = CONFIG.StartOpen
    local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local function applyState(animate)
        local target = isOpen and UDim2.new(0,0,0,0) or UDim2.new(-1,-8,0,0)
        toggle.Text = isOpen and "<" or ">"
        if animate then
            TweenService:Create(content,tweenInfo,{Position=target}):Play()
        else
            content.Position = target
        end
    end
    applyState(false)
    table.insert(connections,toggle.Activated:Connect(function()
        isOpen = not isOpen
        applyState(true)
    end))

    -- Elapsed timer starts when the HUD is initialized and counts up indefinitely.
    local timerStartedAt = os.clock()

    -- Reset logic uses only the visible fixed ring; no abnormal-movement detector.
    local startTime = os.clock()
    local lastReset = -math.huge
    local lastSeatState = nil
    local characterReadyAt = startTime + CONFIG.IgnoreAfterSpawnSeconds
    local stuckAnchorPos = nil
    local stuckSince = startTime
    local ringFolder = nil
    local ringDots = {}
    local outsideSince = nil

    local function destroyRing()
        if ringFolder then
            pcall(function() ringFolder:Destroy() end)
        end
        ringFolder = nil
        ringDots = {}
    end

    local function createRing(center)
        destroyRing()
        local folder = Instance.new("Folder")
        folder.Name = "ServerStatsHUD_StuckRing"
        folder.Parent = workspace
        ringFolder = folder
        local radius = CONFIG.MinMoveStuds
        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.FilterDescendantsInstances = {folder, LocalPlayer.Character}
        rayParams.IgnoreWater = false

        for i = 1, CONFIG.RingSegments do
            local angle = (i / CONFIG.RingSegments) * math.pi * 2
            local x = center.X + math.cos(angle) * radius
            local z = center.Z + math.sin(angle) * radius
            -- Raycast downward so the ring sits visibly above uneven terrain.
            local origin = Vector3.new(x, center.Y + 80, z)
            local hit = workspace:Raycast(origin, Vector3.new(0, -300, 0), rayParams)
            local y = hit and (hit.Position.Y + 0.8) or (center.Y - 2.5)

            local dot = Instance.new("Part")
            dot.Name = "RingDot"
            dot.Shape = Enum.PartType.Ball
            dot.Size = Vector3.new(CONFIG.RingDotSize, CONFIG.RingDotSize, CONFIG.RingDotSize)
            dot.Anchored = true
            dot.CanCollide = false
            dot.CanTouch = false
            dot.CanQuery = false
            dot.CastShadow = false
            dot.Material = Enum.Material.Neon
            dot.Color = Color3.fromRGB(0, 255, 255)
            dot.Transparency = 0
            dot.Position = Vector3.new(x, y, z)
            dot.Parent = folder
            table.insert(ringDots, dot)
        end

        local marker = Instance.new("Part")
        marker.Name = "RingCenterMarker"
        marker.Size = Vector3.new(0.25, 0.25, 0.25)
        marker.Shape = Enum.PartType.Ball
        marker.Anchored = true
        marker.CanCollide = false
        marker.CanTouch = false
        marker.CanQuery = false
        marker.CastShadow = false
        marker.Material = Enum.Material.Neon
        marker.Color = Color3.fromRGB(255, 190, 45)
        marker.Position = center
        marker.Parent = folder

        local billboard = Instance.new("BillboardGui")
        billboard.Name = "RingLabel"
        billboard.Size = UDim2.fromOffset(120, 30)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = marker
        local label = Instance.new("TextLabel")
        label.Size = UDim2.fromScale(1, 1)
        label.BackgroundTransparency = 1
        label.Text = "70 STUDS"
        label.TextColor3 = Color3.fromRGB(0, 255, 255)
        label.TextStrokeTransparency = 0
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
    end

    local function clearMovementState()
    end

    local function resetCharacter(reason)
        local now = os.clock()
        if not CONFIG.ConflictReset or now-lastReset < CONFIG.ResetCooldown then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        lastReset = now
        clearMovementState()
        stuckAnchorPos = nil
        stuckSince = now
        outsideSince = nil
        destroyRing()
        notify("Reset nhan vat: "..reason)
        -- Keep the existing reset behavior; server/executor may disallow client-side health changes.
        local ok = pcall(function() hum.Health = 0 end)
        if not ok then warn("[ServerStatsHUD] Client khong the reset Humanoid") end
    end

    table.insert(connections,LocalPlayer.CharacterAdded:Connect(function()
        characterReadyAt = os.clock()+CONFIG.IgnoreAfterSpawnSeconds
        lastSeatState = nil
        clearMovementState()
        stuckAnchorPos = nil
        stuckSince = os.clock()
        outsideSince = nil
        destroyRing()
    end))

    table.insert(connections,RunService.Heartbeat:Connect(function()
        if not CONFIG.ConflictReset then return end
        local now = os.clock()
        if now < characterReadyAt or now-startTime < CONFIG.GraceSeconds then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        -- Seat state transitions can produce legitimate position/velocity changes.
        local seatState = hum.SeatPart ~= nil
        if seatState ~= lastSeatState then
            lastSeatState = seatState
            return
        end
        if seatState then
            stuckAnchorPos = nil
            stuckSince = now
            outsideSince = nil
            destroyRing()
            return
        end

        -- The visible ring stays fixed at its anchor. If the player remains
        -- inside it for 60s, reset. After leaving it, wait 10s, then place a new
        -- ring at the player's current position and restart the 60s timer.
        if not stuckAnchorPos then
            stuckAnchorPos = hrp.Position
            stuckSince = now
            outsideSince = nil
            createRing(stuckAnchorPos)
        end

        local horizontalDistance = Vector3.new(
            hrp.Position.X - stuckAnchorPos.X,
            0,
            hrp.Position.Z - stuckAnchorPos.Z
        ).Magnitude

        if horizontalDistance >= CONFIG.MinMoveStuds then
            if not outsideSince then outsideSince = now end
            if now - outsideSince >= CONFIG.RingRefreshDelay then
                stuckAnchorPos = hrp.Position
                stuckSince = now
                outsideSince = nil
                createRing(stuckAnchorPos)
            end
        else
            outsideSince = nil
        end

        if now - stuckSince >= CONFIG.StuckSeconds and horizontalDistance < CONFIG.MinMoveStuds then
            resetCharacter("inside-70-stud-ring-100s")
            return
        end

    end))

    local function updatePlayers()
        playersLabel.Text = string.format("SV %d/%d",#Players:GetPlayers(),Players.MaxPlayers)
    end
    local function updatePing()
        local ms = getPing()
        pingLabel.Text = ms.."ms"
        pingLabel.TextColor3 = pingColor(ms)
    end
    local function updateFps(fps)
        fps = math.floor(fps+0.5)
        fpsLabel.Text = "FPS "..fps
        fpsLabel.TextColor3 = fpsColor(fps)
    end
    local function updateElapsed()
        elapsedLabel.Text = formatTime(os.clock() - timerStartedAt)
        elapsedLabel.TextColor3 = COLORS.Text
    end

    updatePlayers(); updatePing(); updateFps(60); updateElapsed()
    local frames,last = 0,os.clock()
    table.insert(connections,RunService.RenderStepped:Connect(function()
        frames = frames+1
        local now = os.clock()
        local dt = now-last
        if dt >= CONFIG.UpdateRate then
            updateFps(frames/dt); updatePing(); updatePlayers(); updateElapsed()
            frames,last = 0,now
        end
    end))
    table.insert(connections,Players.PlayerAdded:Connect(updatePlayers))
    table.insert(connections,Players.PlayerRemoving:Connect(function() task.defer(updatePlayers) end))

    gui.Destroying:Connect(function()
        for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    end)
    notify("HUD v4.8 da chay - chi reset theo vong 8 studs")
end

local ok,err = xpcall(run,function(e)
    return tostring(e).."\n"..tostring(debug.traceback())
end)
if not ok then
    warn("[ServerStatsHUD] LOI: "..tostring(err))
    notify("Loi: "..string.sub(tostring(err),1,150))
end
