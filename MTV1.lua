-- X-Ploitgaa v1 (AutoTP Delay & WalkSpeed use number boxes; small theme change)
-- Fly bug fix: startFly no longer returns early when state.flyEnabled was pre-set by toggle.
-- Only fly start/stop logic changed; everything else kept identical to original.

-- ======= Cleanup previous GUIs & globals =======
pcall(function()
    local CoreGui = game:GetService("CoreGui")
    for _, gui in pairs(CoreGui:GetChildren()) do
        local n = tostring(gui.Name):lower()
        if n:find("orion") or n:find("orionlib") or n:find("arrayfield") then
            pcall(function() gui:Destroy() end)
        end
    end

    local Players = game:GetService("Players")
    local lp = Players.LocalPlayer
    if lp then
        local pg = lp:FindFirstChildOfClass("PlayerGui")
        if pg then
            for _, child in pairs(pg:GetChildren()) do
                if child:IsA("ScreenGui") then
                    local name = tostring(child.Name):lower()
                    if name:find("orion") or name:find("arrayfield") or name:find("af_") then
                        pcall(function() child:Destroy() end)
                    end
                end
            end
        end
    end

    if _G then
        pcall(function() _G.OrionLib = nil end)
        pcall(function() _G.Orion = nil end)
        pcall(function() _G.ArrayField = nil end)
        pcall(function() _G.ArrayFieldExample = nil end)
    end
end)

task.wait(0.06)

-- ======= Load library (runtime) =======
local function load_orion()
    local success, lib = pcall(function()
        local url = "https://raw.githubusercontent.com/jensonhirst/Orion/main/source"
        local src = game:HttpGet(url)
        local fn = loadstring(src)
        if not fn then error("Failed compile source") end
        local ok, result = pcall(fn)
        if not ok then error("init failed: "..tostring(result)) end
        if type(result) == "table" then return result end
        if _G and _G.OrionLib then return _G.OrionLib end
        if _G and _G.Orion then return _G.Orion end
        return nil
    end)
    if success and type(lib) == "table" then return lib end
    return nil, lib
end

local OrionLib, err = load_orion()
if not OrionLib then
    pcall(function() OrionLib = (loadstring(game:HttpGet("https://raw.githubusercontent.com/jensonhirst/Orion/main/source"))()) end)
end
if not OrionLib then error("Could not load library. Ensure HttpGet allowed.") end

-- ======= Services & state =======
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local BOOKMARK_SAVE_FILE = "ArrayField_bookmarks.json"
local bookmarks = {}

local state = {
    selectedPlayerName = nil,
    selectedBookmarkIndex = nil,
    espEnabled = false,
    espColor = Color3.fromRGB(255,0,0),
    autoTPEnabled = false,
    autoTPMode = "Players",
    autoTPDelay = 3,
    walkEnabled = false,
    walkSpeedValue = 16,
    flyEnabled = false,
    flySpeed = 50,
    antiAfk = false
}

local function notify(text, time)
    pcall(function()
        if OrionLib and type(OrionLib.MakeNotification) == "function" then
            OrionLib:MakeNotification({Name="Theme: Midnight", Content = tostring(text), Time = time or 3})
        else print("[Notify] "..tostring(text)) end
    end)
end

local function safeReadFile(path)
    local ok, content = pcall(function()
        if isfile and isfile(path) and readfile then return readfile(path)
        elseif readfile then return readfile(path)
        elseif syn and syn.read_file then return syn.read_file(path) end
    end)
    if ok then return content end
    return nil
end
local function safeWriteFile(path, data)
    pcall(function()
        if writefile then writefile(path, data)
        elseif syn and syn.write_file then syn.write_file(path, data)
        else error("No writefile available") end
    end)
end

-- Bookmarks
local function saveBookmarks()
    pcall(function()
        local serial = {}
        for _, b in ipairs(bookmarks) do
            if b and b.CFrame then
                local p = b.CFrame.Position
                local l = b.CFrame.LookVector
                table.insert(serial, { Name = b.Name, Pos = {p.X,p.Y,p.Z}, Look = {l.X,l.Y,l.Z} })
            else table.insert(serial, { Name = b.Name, Pos = nil }) end
        end
        local json = HttpService:JSONEncode(serial)
        safeWriteFile(BOOKMARK_SAVE_FILE, json)
    end)
end
local function loadBookmarks()
    local content = safeReadFile(BOOKMARK_SAVE_FILE)
    if not content or content == "" then bookmarks = {}; return end
    local ok, data = pcall(function() return HttpService:JSONDecode(content) end)
    if not ok or type(data) ~= "table" then bookmarks = {}; return end
    bookmarks = {}
    for _, entry in ipairs(data) do
        if entry.Pos and entry.Look then
            local pos = Vector3.new(entry.Pos[1], entry.Pos[2], entry.Pos[3])
            local look = Vector3.new(entry.Look[1], entry.Look[2], entry.Look[3])
            table.insert(bookmarks, { Name = entry.Name, CFrame = CFrame.new(pos, pos + look) })
        else table.insert(bookmarks, { Name = entry.Name, CFrame = nil }) end
    end
end

-- Players helper
local function getPlayerOptions()
    local seen = {}
    local out = {}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= Players.LocalPlayer then
            local n = tostring(p.Name)
            if not seen[n] then seen[n]=true; table.insert(out,n) end
        end
    end
    if #out == 0 then table.insert(out,"No players") end
    return out
end

local function teleportToPlayer(name)
    local target = Players:FindFirstChild(name)
    local lp = Players.LocalPlayer
    if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then return false end
    if lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") then
        pcall(function() lp.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame end)
        return true
    end
    return false
end

-- ESP
local highlights = {}
local function createHighlight(plr)
    if not plr or not plr.Character then return end
    if highlights[plr] then return end
    pcall(function()
        local h = Instance.new("Highlight")
        h.Adornee = plr.Character
        h.FillColor = state.espColor
        h.FillTransparency = 0.7
        h.OutlineTransparency = 0.4
        h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        h.Parent = workspace
        highlights[plr] = h
    end)
end
local function removeHighlights() for p,h in pairs(highlights) do pcall(function() h:Destroy() end) end highlights = {} end

-- WalkSpeed helpers
local originalWalkSpeed = nil
local function applyWalkSpeed(speed)
    local lp = Players.LocalPlayer
    if not lp or not lp.Character then return end
    local hum = lp.Character:FindFirstChildOfClass("Humanoid")
    if hum then if not originalWalkSpeed then originalWalkSpeed = hum.WalkSpeed end pcall(function() hum.WalkSpeed = speed end) end
end
local function restoreWalkSpeed()
    if not originalWalkSpeed then return end
    local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.WalkSpeed = originalWalkSpeed end) end
    originalWalkSpeed = nil
end
local function clampSpeed(n) n = tonumber(n) or state.walkSpeedValue if n < 16 then n = 16 end if n > 250 then n = 250 end return math.floor(n) end

-- Fly implementation (BUG FIXED: guard uses mover existence, not state flag set by toggle)
local flyBV, flyBG, flyHB, flyInB, flyInE = nil,nil,nil,nil,nil
-- Mobile thumbstick support (dynamic / classic) and on-screen up/down buttons for fly control
local touchJoystickMode = "dynamic" -- "dynamic" or "classic"
local joystickGui = nil
local touchStartedConn, touchMovedConn, touchEndedConn = nil, nil, nil
local upBtnConnDown, upBtnConnUp, downBtnConnDown, downBtnConnUp = nil, nil, nil, nil

local joystickTouchId = nil
local joystickCenter = Vector2.new(100, workspace.CurrentCamera.ViewportSize.Y - 100) -- default for classic
local joystickRadius = 60
local touchMoveVector = Vector3.new(0,0,0) -- X,Z plane movement from joystick
local touchVertical = 0 -- -1 down, 0 none, 1 up

local function createJoystickGui()
    if joystickGui then return end
    local player = Players.LocalPlayer
    if not player then return end
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then pg = Instance.new("ScreenGui") pg.Name = "AF_TempPG" pg.Parent = player end
    joystickGui = Instance.new("ScreenGui")
    joystickGui.Name = "AF_TouchJoystickGui"
    joystickGui.ResetOnSpawn = false
    joystickGui.Parent = pg
    joystickGui.IgnoreGuiInset = true
    joystickGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling


    -- outer circle
    local outer = Instance.new("ImageLabel")
    outer.Name = "Outer"
    outer.Size = UDim2.new(0, joystickRadius*2, 0, joystickRadius*2)
    outer.Position = UDim2.new(0, joystickCenter.X - joystickRadius, 0, joystickCenter.Y - joystickRadius)
    outer.BackgroundTransparency = 1
    outer.Image = "rbxassetid://3926307971" -- circular texture (Roblox default)
    outer.ImageColor3 = Color3.fromRGB(40,40,40)
    outer.ImageTransparency = 0.3
    outer.Parent = joystickGui

    -- inner stick
    local inner = Instance.new("ImageLabel")
    inner.Name = "Inner"
    inner.Size = UDim2.new(0, joystickRadius, 0, joystickRadius)
    inner.Position = UDim2.new(0, joystickCenter.X - joystickRadius/2, 0, joystickCenter.Y - joystickRadius/2)
    inner.BackgroundTransparency = 1
    inner.Image = "rbxassetid://3926305904"
    inner.ImageColor3 = Color3.fromRGB(180,180,180)
    inner.ImageTransparency = 0.2
    inner.Parent = joystickGui

    -- up and down buttons (right bottom)
    local upBtn = Instance.new("ImageButton")
    upBtn.Name = "UpBtn"
    upBtn.Size = UDim2.new(0, 60, 0, 60)
    upBtn.Position = UDim2.new(1, -80, 1, -160)
    upBtn.AnchorPoint = Vector2.new(1,1)
    upBtn.Image = "rbxassetid://3926307971"
    upBtn.ImageColor3 = Color3.fromRGB(80,80,80)
    upBtn.BackgroundTransparency = 0.5
    upBtn.Parent = joystickGui

    local downBtn = Instance.new("ImageButton")
    downBtn.Name = "DownBtn"
    downBtn.Size = UDim2.new(0, 60, 0, 60)
    downBtn.Position = UDim2.new(1, -10, 1, -160)
    downBtn.AnchorPoint = Vector2.new(1,1)
    downBtn.Image = "rbxassetid://3926307971"
    downBtn.ImageColor3 = Color3.fromRGB(80,80,80)
    downBtn.BackgroundTransparency = 0.5
    downBtn.Parent = joystickGui

    -- labels
    local uLbl = Instance.new("TextLabel", upBtn)
    uLbl.Size = UDim2.new(1,0,1,0); uLbl.BackgroundTransparency = 1; uLbl.Text = "↑"; uLbl.TextScaled = true; uLbl.TextColor3 = Color3.new(1,1,1)
    local dLbl = Instance.new("TextLabel", downBtn)
    dLbl.Size = UDim2.new(1,0,1,0); dLbl.BackgroundTransparency = 1; dLbl.Text = "↓"; dLbl.TextScaled = true; dLbl.TextColor3 = Color3.new(1,1,1)

    -- touch handling for up/down buttons (use MouseButton1Down/MouseButton1Up which fire for touch and mouse)
    upBtnConnDown = upBtn.MouseButton1Down:Connect(function()
        touchVertical = 1
    end)
    upBtnConnUp = upBtn.MouseButton1Up:Connect(function()
        touchVertical = 0
    end)
    downBtnConnDown = downBtn.MouseButton1Down:Connect(function()
        touchVertical = -1
    end)
    downBtnConnUp = downBtn.MouseButton1Up:Connect(function()
        touchVertical = 0
    end)
    -- Also support InputBegan/Ended for touch inputs (some environments)
    upBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then touchVertical = 1 end
    end)
    upBtn.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then touchVertical = 0 end
    end)
    downBtn.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then touchVertical = -1 end
    end)
    downBtn.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.Touch then touchVertical = 0 end
    end)
end

local function destroyJoystickGui()
    if joystickGui then pcall(function() joystickGui:Destroy() end); joystickGui = nil end
    joystickTouchId = nil
    touchMoveVector = Vector3.new(0,0,0)
    touchVertical = 0
    -- disconnect touch connections
    if touchStartedConn then touchStartedConn:Disconnect(); touchStartedConn = nil end
    if touchMovedConn then touchMovedConn:Disconnect(); touchMovedConn = nil end
    if touchEndedConn then touchEndedConn:Disconnect(); touchEndedConn = nil end
    -- disconnect button connections
    if upBtnConnDown then upBtnConnDown:Disconnect(); upBtnConnDown = nil end
    if upBtnConnUp then upBtnConnUp:Disconnect(); upBtnConnUp = nil end
    if downBtnConnDown then downBtnConnDown:Disconnect(); downBtnConnDown = nil end
    if downBtnConnUp then downBtnConnUp:Disconnect(); downBtnConnUp = nil end
end

-- handle touch input events to drive flyKeys via joystick
local function onTouchBegan(touch, processed)
    if processed then return end
    -- when dynamic mode, spawn joystick at touch position and capture that touch id
    if touchJoystickMode == "dynamic" then
        joystickTouchId = touch.UserInputId or touch.TouchId or touch.Position and touch
        joystickCenter = touch.Position
        if joystickGui then
            local outer = joystickGui:FindFirstChild("Outer")
            local inner = joystickGui:FindFirstChild("Inner")
            if outer and inner then
                outer.Position = UDim2.new(0, joystickCenter.X - joystickRadius, 0, joystickCenter.Y - joystickRadius)
                inner.Position = UDim2.new(0, joystickCenter.X - joystickRadius/2, 0, joystickCenter.Y - joystickRadius/2)
                outer.Visible = true; inner.Visible = true
            end
        end
    elseif touchJoystickMode == "classic" then
        -- classic uses fixed joystickCenter already set
    end
end

local function onTouchMoved(touch, processed)
    if not joystickGui then return end
    local id = touch.UserInputId or touch.TouchId or touch.Position and touch
    -- if a joystick touch is active (dynamic), only track that one; or always track if classic
    if touchJoystickMode == "dynamic" and joystickTouchId and id ~= joystickTouchId then return end
    local pos = touch.Position
    local delta = Vector2.new(pos.X, pos.Y) - joystickCenter
    local dist = math.min(delta.Magnitude, joystickRadius)
    local dir = (dist > 0) and (delta.Unit) or Vector2.new(0,0)
    local inner = joystickGui:FindFirstChild("Inner")
    if inner then inner.Position = UDim2.new(0, joystickCenter.X - joystickRadius/2 + dir.X * dist, 0, joystickCenter.Y - joystickRadius/2 + dir.Y * dist) end
    -- convert to world XZ movement relative to camera forward/right
    local cam = workspace.CurrentCamera
    if cam then
        local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z).Unit
        local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z).Unit
        local mag = dist / joystickRadius
        local moveWorld = (look * (-dir.Y) + right * dir.X) * (mag * state.flySpeed)
        touchMoveVector = Vector3.new(moveWorld.X, 0, moveWorld.Z)
    end
end

local function onTouchEnded(touch, processed)
    local id = touch.UserInputId or touch.TouchId or touch.Position and touch
    if touchJoystickMode == "dynamic" and joystickTouchId and id == joystickTouchId then
        -- reset inner
        if joystickGui then local inner = joystickGui:FindFirstChild("Inner") if inner then inner.Position = UDim2.new(0, joystickCenter.X - joystickRadius/2, 0, joystickCenter.Y - joystickRadius/2) end end
        joystickTouchId = nil
        touchMoveVector = Vector3.new(0,0,0)
    end
end

local flyKeys = {w=false,a=false,s=false,d=false,space=false,shift=false}
local function startFly()
    -- don't return early just because state.flyEnabled was set by the UI toggle;
    -- instead check if movers / heartbeat already exist to avoid double-init.
    if flyBV or flyHB then
        return
    end
    local lp = Players.LocalPlayer
    local hrp = lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local hum = lp and lp.Character and lp.Character:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then notify("Cannot start fly: HRP or Humanoid missing",3); return end

    -- mark enabled and create movers
    state.flyEnabled = true
    flyBV = Instance.new("BodyVelocity"); flyBV.MaxForce = Vector3.new(1e5,1e5,1e5); flyBV.Parent = hrp
    flyBG = Instance.new("BodyGyro"); flyBG.MaxTorque = Vector3.new(1e5,1e5,1e5); flyBG.CFrame = hrp.CFrame; flyBG.Parent = hrp
    pcall(function() hum.PlatformStand = true end)
    flyInB = UserInputService.InputBegan:Connect(function(inp, gp) if gp then return end local kc = inp.KeyCode if kc==Enum.KeyCode.W then flyKeys.w=true elseif kc==Enum.KeyCode.S then flyKeys.s=true elseif kc==Enum.KeyCode.A then flyKeys.a=true elseif kc==Enum.KeyCode.D then flyKeys.d=true elseif kc==Enum.KeyCode.Space then flyKeys.space=true elseif kc==Enum.KeyCode.LeftShift or kc==Enum.KeyCode.RightShift then flyKeys.shift=true end end)
    flyInE = UserInputService.InputEnded:Connect(function(inp) local kc = inp.KeyCode if kc==Enum.KeyCode.W then flyKeys.w=false elseif kc==Enum.KeyCode.S then flyKeys.s=false elseif kc==Enum.KeyCode.A then flyKeys.a=false elseif kc==Enum.KeyCode.D then flyKeys.d=false elseif kc==Enum.KeyCode.Space then flyKeys.space=false elseif kc==Enum.KeyCode.LeftShift or kc==Enum.KeyCode.RightShift then flyKeys.shift=false end end)
    -- create mobile joystick GUI if device supports touch
    if UserInputService.TouchEnabled then
        createJoystickGui()
        joystickTouchId = nil
        -- connect touch input handlers (store connections so we can disconnect on stop)
        if not touchStartedConn then touchStartedConn = UserInputService.TouchStarted:Connect(function(inp) onTouchBegan(inp, false) end) end
        if not touchMovedConn then touchMovedConn = UserInputService.TouchMoved:Connect(function(inp) onTouchMoved(inp, false) end) end
        if not touchEndedConn then touchEndedConn = UserInputService.TouchEnded:Connect(function(inp) onTouchEnded(inp, false) end) end
    end
    flyHB = RunService.Heartbeat:Connect(function()
        local cam = workspace.CurrentCamera
        if not cam or not hrp then return end
        local look = cam.CFrame.LookVector; local right = cam.CFrame.RightVector
        local move = Vector3.new(0,0,0)
        if flyKeys.w then move = move + Vector3.new(look.X,0,look.Z) end
        if flyKeys.s then move = move - Vector3.new(look.X,0,look.Z) end
        if flyKeys.a then move = move - Vector3.new(right.X,0,right.Z) end
        if flyKeys.d then move = move + Vector3.new(right.X,0,right.Z) end
        local vertical = 0
        if flyKeys.space then vertical = vertical + 1 end
        if flyKeys.shift then vertical = vertical - 1 end
        local vel = Vector3.new(0, vertical * state.flySpeed, 0)
        -- combine keyboard (move) and touch joystick (touchMoveVector). touchMoveVector is already scaled by speed.
        if move.Magnitude>0 then
            local dir = move.Unit
            vel = Vector3.new(dir.X*state.flySpeed, vertical*state.flySpeed, dir.Z*state.flySpeed)
        end
        -- If touch joystick present, prefer its horizontal movement (additive)
        if touchMoveVector and (math.abs(touchMoveVector.X) > 0 or math.abs(touchMoveVector.Z) > 0) then
            vel = Vector3.new(touchMoveVector.X, vel.Y, touchMoveVector.Z)
        end
        if flyBV then flyBV.Velocity = vel end
        if flyBG then flyBG.CFrame = CFrame.new(hrp.Position, hrp.Position + cam.CFrame.LookVector) end
    end)
end
local function stopFly()
    -- clear state and cleanup movers/listeners
    state.flyEnabled = false
    if flyHB then flyHB:Disconnect(); flyHB=nil end
    if flyInB then flyInB:Disconnect(); flyInB=nil end
    if flyInE then flyInE:Disconnect(); flyInE=nil end
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV=nil end
    if flyBG then pcall(function() flyBG:Destroy() end); flyBG=nil end
    local hum = Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.PlatformStand=false end) end
    -- destroy joystick GUI if any
    destroyJoystickGui()
    flyKeys = {w=false,a=false,s=false,d=false,space=false,shift=false}
end

-- AutoTP
local autoTPThread = nil
local function startAutoTP()
    if state.autoTPEnabled then return end
    state.autoTPEnabled = true
    autoTPThread = spawn(function()
        while state.autoTPEnabled do
            if state.autoTPMode == "Players" then
                local players = {}
                for _,p in pairs(Players:GetPlayers()) do if p~=Players.LocalPlayer and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then table.insert(players,p) end end
                if #players==0 then task.wait(state.autoTPDelay) else for _,p in ipairs(players) do if not state.autoTPEnabled then break end pcall(function() local lp=Players.LocalPlayer if lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then lp.Character.HumanoidRootPart.CFrame = p.Character.HumanoidRootPart.CFrame end end) task.wait(state.autoTPDelay) end end
            else
                if #bookmarks==0 then task.wait(state.autoTPDelay) else for _,bm in ipairs(bookmarks) do if not state.autoTPEnabled then break end pcall(function() local lp=Players.LocalPlayer if lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") and bm.CFrame then lp.Character.HumanoidRootPart.CFrame = bm.CFrame end end) task.wait(state.autoTPDelay) end end
            end
            task.wait(0.1)
        end
    end)
end
local function stopAutoTP() state.autoTPEnabled=false end

-- Anti-AFK
local antiAfkConn = nil
local function setAntiAfk(enabled)
    if enabled then antiAfkConn = Players.LocalPlayer.Idled:Connect(function() pcall(function() local vu = game:GetService("VirtualUser") vu:CaptureController(); vu:ClickButton2(Vector2.new(0,0)) end) end) else if antiAfkConn then antiAfkConn:Disconnect(); antiAfkConn=nil end end
end

-- Cleanup export
local function cleanupAll()
    state.autoTPEnabled = false
    stopAutoTP()
    pcall(saveBookmarks)
    stopFly()
    removeHighlights()
    setAntiAfk(false)
    restoreWalkSpeed()
end
_G.OrionFull_OrionStyle_Cleanup = cleanupAll

-- ======= Orion UI (theme: Midnight) =======
local Window = OrionLib:MakeWindow({ Name = "X-PloitGaa — Menu V.1 (VVIP)", HidePremium = false, IntroText = "Welcome To — X-PloitGaa", SaveConfig = true, ConfigFolder = "OrionFull_OrionStyle_Midnight" })

local InfoTab = Window:MakeTab({ Name = "Info", Icon = "rbxassetid://4483362458" })
InfoTab:AddSection({ Name = "About" })
InfoTab:AddParagraph("Info", "Developed by: Rangga?\nVersi: 1.0\nTheme: Midnight")
InfoTab:AddButton({ Name = "Copy Discord Invite", Callback = function() pcall(function() if setclipboard then setclipboard("https://discord.gg/swg7FjZFR") end end); notify("Discord invite copied",2) end })

local MainTab = Window:MakeTab({ Name = "Main", Icon = "rbxassetid://4483362458" })
MainTab:AddSection({ Name = "Teleport & Bookmarks" })

-- Player dropdown (single instance)
local playerDropdownRef = MainTab:AddDropdown({ Name = "Select Player (Teleport)", Default = nil, Options = getPlayerOptions(), Callback = function(opt) if opt and opt ~= "No players" then state.selectedPlayerName = opt else state.selectedPlayerName = nil end end })
Players.PlayerAdded:Connect(function() pcall(function() if playerDropdownRef and playerDropdownRef.SetOptions then playerDropdownRef:SetOptions(getPlayerOptions()) end end) end)
Players.PlayerRemoving:Connect(function() pcall(function() if playerDropdownRef and playerDropdownRef.SetOptions then playerDropdownRef:SetOptions(getPlayerOptions()) end end) end)
MainTab:AddButton({ Name = "Refresh Player List", Callback = function() if playerDropdownRef and playerDropdownRef.SetOptions then playerDropdownRef:SetOptions(getPlayerOptions()) end; notify("Player list refreshed",2) end })

MainTab:AddButton({ Name = "Respawn", Callback = function()
    local lp = Players.LocalPlayer
    if not lp then notify("LocalPlayer not found",2); return end
    local attempted = false
    pcall(function() if typeof(lp.LoadCharacter)=="function" then lp:LoadCharacter(); attempted=true end end)
    if attempted then notify("Respawn attempted",2); return end
    task.wait(0.1)
    pcall(function() local char = lp.Character if char then local hum = char:FindFirstChildOfClass("Humanoid") if hum then hum.Health = 0; attempted=true end end end)
    if attempted then notify("Respawn attempted",2); return end
    task.wait(0.1)
    pcall(function() local char = lp.Character if char then for _,obj in ipairs(char:GetDescendants()) do if obj:IsA("BasePart") then pcall(function() obj:BreakJoints() end) end end attempted=true end end)
    if attempted then notify("Respawn attempted",2); return end
    pcall(function() lp.Character = nil; attempted=true end)
    if attempted then notify("Respawn fallback attempted",2) else notify("Respawn failed",3) end
end })

MainTab:AddButton({ Name = "Teleport to Selected Player", Callback = function() if not state.selectedPlayerName then notify("Please select player",2); return end; if teleportToPlayer(state.selectedPlayerName) then notify("Teleported to "..state.selectedPlayerName,2) else notify("Teleport failed",2) end end })

-- Bookmarks (unchanged creation logic)
MainTab:AddButton({ Name = "Add Bookmark (current pos)", Callback = function()
    local lp = Players.LocalPlayer
    if not lp or not lp.Character or not lp.Character:FindFirstChild("HumanoidRootPart") then notify("HRP not found",2); return end
    local name = "BM"..tostring(os.time())
    table.insert(bookmarks, { Name = name, CFrame = lp.Character.HumanoidRootPart.CFrame })
    saveBookmarks()
    if bookmarkDropdownRef and bookmarkDropdownRef.SetOptions then bookmarkDropdownRef:SetOptions((function() local t={} for _,b in ipairs(bookmarks) do table.insert(t,b.Name) end if #t==0 then table.insert(t,"No bookmarks") end return t end)()) end
    notify("Bookmark added",2)
end })

local function getBookmarkOptions()
    local t = {}
    for _,b in ipairs(bookmarks) do table.insert(t, b.Name or "Unnamed") end
    if #t==0 then table.insert(t,"No bookmarks") end
    return t
end

local bookmarkDropdownRef = MainTab:AddDropdown({ Name = "Bookmarks", Default = nil, Options = getBookmarkOptions(), Callback = function(sel)
    state.selectedBookmarkIndex = nil
    if not sel or sel == "No bookmarks" then return end
    for i,b in ipairs(bookmarks) do if b.Name == sel then state.selectedBookmarkIndex = i; break end end
end })

MainTab:AddButton({ Name = "Delete Selected Bookmark", Callback = function() if not state.selectedBookmarkIndex or #bookmarks==0 then notify("No bookmark selected",2); return end; table.remove(bookmarks, state.selectedBookmarkIndex); state.selectedBookmarkIndex = nil; saveBookmarks(); if bookmarkDropdownRef and bookmarkDropdownRef.SetOptions then bookmarkDropdownRef:SetOptions(getBookmarkOptions()) end; notify("Bookmark deleted",2) end })

MainTab:AddButton({ Name = "Rename Selected Bookmark", Callback = function()
    if not state.selectedBookmarkIndex or #bookmarks==0 then notify("No bookmark selected",2); return end
    local cur = bookmarks[state.selectedBookmarkIndex].Name or ""
    if OrionLib and OrionLib.Prompt then
        OrionLib:Prompt({ Title = "Rename Bookmark", Desc = "Current: "..cur, Default = cur, Callback = function(newName) if not newName or newName:match("^%s*$") then notify("Invalid name",2); return end bookmarks[state.selectedBookmarkIndex].Name = newName; saveBookmarks(); if bookmarkDropdownRef and bookmarkDropdownRef.SetOptions then bookmarkDropdownRef:SetOptions(getBookmarkOptions()) end; notify("Renamed",2) end })
    else notify("Prompt not available, cannot rename via UI",3) end
end })

MainTab:AddButton({ Name = "Delete All Bookmarks", Callback = function()
    if #bookmarks==0 then notify("No bookmarks",2); return end
    bookmarks = {}; state.selectedBookmarkIndex = nil; saveBookmarks(); if bookmarkDropdownRef and bookmarkDropdownRef.SetOptions then bookmarkDropdownRef:SetOptions(getBookmarkOptions()) end; notify("All bookmarks deleted",2)
end })

MainTab:AddButton({ Name = "Teleport to First Bookmark", Callback = function() if #bookmarks==0 then notify("No bookmarks",2); return end local lp=Players.LocalPlayer if lp and lp.Character and lp.Character:FindFirstChild("HumanoidRootPart") and bookmarks[1].CFrame then pcall(function() lp.Character.HumanoidRootPart.CFrame = bookmarks[1].CFrame end); notify("Teleported to first bookmark",2) end end })

-- Auto TP: REPLACE slider with number textbox
MainTab:AddSection({ Name = "Auto TP" })
local autoTPModeRef = MainTab:AddDropdown({ Name = "AutoTP Mode", Default = state.autoTPMode, Options = {"Players","Bookmarks"}, Callback = function(opt) if opt then state.autoTPMode = opt end end })

-- number input for delay
local autoTPDelayBox = MainTab:AddTextbox({ Name = "AutoTP Delay (s)", Text = tostring(state.autoTPDelay), PlaceholderText = "Seconds (1-300)", Callback = function(txt)
    local n = tonumber(txt)
    if not n then notify("Masukkan angka valid",2); return end
    if n < 1 then n = 1 end
    if n > 300 then n = 300 end
    state.autoTPDelay = math.floor(n)
    notify("AutoTP delay set to "..tostring(state.autoTPDelay).."s",2)
end })

MainTab:AddToggle({ Name = "Auto TP (sequential)", Default = state.autoTPEnabled, Callback = function(s) if s then startAutoTP() else stopAutoTP() end end })

-- Player Tab
local PlayerTab = Window:MakeTab({ Name = "Player", Icon = "rbxassetid://4483362458" })
PlayerTab:AddSection({ Name = "Player Tools" })
PlayerTab:AddToggle({ Name = "ESP", Default = state.espEnabled, Callback = function(s) state.espEnabled = s if s then for _,p in pairs(Players:GetPlayers()) do if p~=Players.LocalPlayer then if p.Character then createHighlight(p) end end end else removeHighlights() end end })
PlayerTab:AddColorpicker({ Name = "ESP Color", Default = state.espColor, Callback = function(c) state.espColor = c for _,h in pairs(highlights) do pcall(function() h.FillColor = c end) end end })

PlayerTab:AddSection({ Name = "WalkSpeed" })
PlayerTab:AddToggle({ Name = "WalkSpeed (Enabled)", Default = state.walkEnabled, Callback = function(s) state.walkEnabled = s if s then applyWalkSpeed(state.walkSpeedValue) else restoreWalkSpeed() end end })

-- replace slider with numeric textbox
local walkSpeedBox = PlayerTab:AddTextbox({ Name = "WalkSpeed Value", Text = tostring(state.walkSpeedValue), PlaceholderText = "16-250", Callback = function(txt)
    local n = tonumber(txt)
    if not n then notify("Masukkan angka valid",2); return end
    n = clampSpeed(n)
    state.walkSpeedValue = n
    if state.walkEnabled then applyWalkSpeed(state.walkSpeedValue) end
    notify("WalkSpeed set to "..tostring(state.walkSpeedValue),2)
end })

PlayerTab:AddToggle({ Name = "Anti-AFK", Default = state.antiAfk, Callback = function(s) state.antiAfk = s; setAntiAfk(s) end })

PlayerTab:AddSection({ Name = "Fly" })
PlayerTab:AddToggle({ Name = "FLY", Default = state.flyEnabled, Callback = function(s) state.flyEnabled = s if s then startFly() else stopFly() end end })
PlayerTab:AddTextbox({ Name = "Fly Speed", Text = tostring(state.flySpeed), PlaceholderText = "1-200", Callback = function(txt) local n=tonumber(txt) if not n then notify("Invalid",2); return end if n<1 then n=1 end if n>200 then n=200 end state.flySpeed = math.floor(n) notify("Fly speed set to "..tostring(state.flySpeed),2) end })
PlayerTab:AddButton({ Name = "Reset Fly Speed", Callback = function() state.flySpeed = 50; notify("Fly reset",2) end })

-- Initialize dropdowns & load bookmarks
pcall(function() loadBookmarks() end)
if playerDropdownRef and playerDropdownRef.SetOptions then pcall(function() playerDropdownRef:SetOptions(getPlayerOptions()) end) end
if bookmarkDropdownRef and bookmarkDropdownRef.SetOptions then pcall(function() bookmarkDropdownRef:SetOptions(getBookmarkOptions()) end) end

pcall(function() if OrionLib and OrionLib.Init then OrionLib:Init() end end)
notify("X-PloitGaa v1 (VVIP) (num boxes for delay & walk)",2)
print("X-PloitGaa v1 (VVIP) loaded.")