-- Server Stats HUD v4.6 - elapsed timer + movement watchdog
-- No server-hop controls; reset after prolonged insufficient movement.

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

    -- Conservative detector: count only large reversals while moving,
    -- require repeated events over a window, then confirm after 2 seconds.
    JitterStuds = 3,
    JitterCount = 3,
    JitterWindow = 5,
    ConfirmSeconds = 2,
    SnapStuds = 5,
    SnapCount = 3,
    SnapWindow = 8,
    IgnoreAfterSeatSeconds = 3,
    IgnoreAfterSpawnSeconds = 5,
    StuckSeconds = 60,
    MinMoveStuds = 8,
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

    -- Conservative conflict reset: one detector only. Ignore seat transitions,
    -- respawns, and small movement. Require 3 large direction reversals in 5s,
    -- then verify instability continues for 2s before resetting.
    local startTime = os.clock()
    local lastHrp, lastPos, lastDelta = nil,nil,nil
    local reversals = {}
    local lastReset = -math.huge
    local pendingSince = nil
    local lastSeatState = nil
    local characterReadyAt = startTime + CONFIG.IgnoreAfterSpawnSeconds
    local stuckAnchorPos = nil
    local stuckSince = startTime

    local function clearMovementState()
        lastHrp, lastPos, lastDelta = nil,nil,nil
        reversals = {}
        pendingSince = nil
    end

    local function resetCharacter(reason)
        local now = os.clock()
        if not CONFIG.ConflictReset or now-lastReset < CONFIG.ResetCooldown then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then return end
        lastReset = now
        pendingSince = nil
        clearMovementState()
        stuckAnchorPos = nil
        stuckSince = now
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
    end))

    table.insert(connections,RunService.Heartbeat:Connect(function()
        if not CONFIG.ConflictReset then return end
        local now = os.clock()
        if now < characterReadyAt or now-startTime < CONFIG.GraceSeconds then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then clearMovementState(); return end

        -- Seat state transitions can produce legitimate position/velocity changes.
        local seatState = hum.SeatPart ~= nil
        if seatState ~= lastSeatState then
            lastSeatState = seatState
            clearMovementState()
            return
        end
        if seatState then
            clearMovementState()
            stuckAnchorPos = nil
            stuckSince = now
            return
        end

        -- Reset if the character has not moved at least MinMoveStuds from
        -- the current anchor for StuckSeconds. Re-anchor after sufficient travel.
        if not stuckAnchorPos then
            stuckAnchorPos = hrp.Position
            stuckSince = now
        elseif Vector3.new(
            hrp.Position.X - stuckAnchorPos.X,
            0,
            hrp.Position.Z - stuckAnchorPos.Z
        ).Magnitude >= CONFIG.MinMoveStuds then
            stuckAnchorPos = hrp.Position
            stuckSince = now
        elseif now - stuckSince >= CONFIG.StuckSeconds then
            resetCharacter("stuck-or-insufficient-movement-60s")
            return
        end

        if hrp ~= lastHrp then
            lastHrp, lastPos, lastDelta = hrp, hrp.Position, nil
            reversals = {}
            pendingSince = nil
            return
        end

        local pos = hrp.Position
        local rawDelta = pos-lastPos
        lastPos = pos
        -- Ignore vertical movement; only measure horizontal X/Z displacement.
        local delta = Vector3.new(rawDelta.X, 0, rawDelta.Z)

        -- Only consider meaningful horizontal movement; ignore tiny physics jitter.
        if delta.Magnitude >= CONFIG.JitterStuds then
            if lastDelta and lastDelta.Magnitude >= CONFIG.JitterStuds
                and delta:Dot(lastDelta) < 0 then
                table.insert(reversals,now)
            end
            lastDelta = delta
        elseif delta.Magnitude < 0.5 then
            lastDelta = nil
        end

        while reversals[1] and now-reversals[1] > CONFIG.JitterWindow do
            table.remove(reversals,1)
        end

        if #reversals >= CONFIG.JitterCount then
            if not pendingSince then
                pendingSince = now
            elseif now-pendingSince >= CONFIG.ConfirmSeconds then
                -- Reconfirm: must still be moving and show a fresh reversal.
                if lastDelta and lastDelta.Magnitude >= CONFIG.JitterStuds
                    and reversals[#reversals] and now-reversals[#reversals] <= 1 then
                    resetCharacter("jitter-confirmed")
                else
                    pendingSince = nil
                    reversals = {}
                end
            end
        else
            pendingSince = nil
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
    notify("HUD v4.6 da chay")
end

local ok,err = xpcall(run,function(e)
    return tostring(e).."\n"..tostring(debug.traceback())
end)
if not ok then
    warn("[ServerStatsHUD] LOI: "..tostring(err))
    notify("Loi: "..string.sub(tostring(err),1,150))
end
