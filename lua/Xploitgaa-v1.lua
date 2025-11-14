--[[ 
====================================================
      WARP SYSTEM MOBILE EDITION (AUTO UI)
   Add Warp • Delete Warp • AutoTP • DataStore
   Mobile UI Scaling • Scroll List • Touch Friendly
====================================================
]]

--------------------------
--  SERVICES
--------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local UserInputService = game:GetService("UserInputService")

--------------------------
--  DATASTORE
--------------------------
local warpStore = DataStoreService:GetDataStore("WarpDataStore_MOBILE_v1")

--------------------------
-- RemoteEvent Setup
--------------------------
local event = ReplicatedStorage:FindFirstChild("WarpTeleportEvent")
if not event then
    event = Instance.new("RemoteEvent")
    event.Name = "WarpTeleportEvent"
    event.Parent = ReplicatedStorage
end

--------------------------
-- PLAYER VARS
--------------------------
local player = Players.LocalPlayer
local warps = {}
local autoTP = false
local autoRespawn = true
local autoTPDelay = 0.7
local currentIndex = 1

--------------------------
-- MOBILE UI SCALING
--------------------------
local UIScale = 1
local screen = workspace.CurrentCamera.ViewportSize

if screen.X < 1200 then
    UIScale = 1.6   -- Tampilan dibuat 60% lebih besar di HP
else
    UIScale = 1
end

--------------------------
--  UI CREATION
--------------------------
local gui = Instance.new("ScreenGui", player:WaitForChild("PlayerGui"))
gui.Name = "WarpSystemGUI"
gui.IgnoreGuiInset = false
gui.ResetOnSpawn = false

-- Main window
local main = Instance.new("Frame", gui)
main.Size = UDim2.new(0, 260 * UIScale, 0, 480 * UIScale)
main.Position = UDim2.new(1, -(280 * UIScale), 0.5, -220 * UIScale)
main.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
main.BorderSizePixel = 0

local corner = Instance.new("UICorner", main)
corner.CornerRadius = UDim.new(0, 10)

local title = Instance.new("TextLabel", main)
title.Text = "Warp System (Mobile)"
title.Font = Enum.Font.GothamBold
title.TextSize = 18 * UIScale
title.Size = UDim2.new(1, 0, 0, 35 * UIScale)
title.BackgroundColor3 = Color3.fromRGB(25, 25, 25)

local scroll = Instance.new("ScrollingFrame", main)
scroll.Size = UDim2.new(1, -10, 0, 200 * UIScale)
scroll.Position = UDim2.new(0, 5, 0, 40 * UIScale)
scroll.BackgroundTransparency = 1
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.ScrollBarThickness = 6 * UIScale

local UIList = Instance.new("UIListLayout", scroll)
UIList.Padding = UDim.new(0, 6 * UIScale)
UIList.SortOrder = Enum.SortOrder.LayoutOrder

function refreshWarpList()
    for _, v in ipairs(scroll:GetChildren()) do
        if v:IsA("Frame") then v:Destroy() end
    end

    for i, cf in ipairs(warps) do
        local item = Instance.new("Frame", scroll)
        item.Size = UDim2.new(1, -8, 0, 40 * UIScale)
        item.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
        local ic = Instance.new("UICorner", item)

        local label = Instance.new("TextLabel", item)
        label.Text = "Warp " .. i
        label.Size = UDim2.new(0.4, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextScaled = true

        local TP = Instance.new("TextButton", item)
        TP.Text = "TP"
        TP.Size = UDim2.new(0.25, -4, 1, 0)
        TP.Position = UDim2.new(0.4, 4, 0, 0)
        TP.TextScaled = true
        TP.BackgroundColor3 = Color3.fromRGB(70, 180, 90)

        TP.MouseButton1Click:Connect(function()
            event:FireServer(cf)
        end)

        local DEL = Instance.new("TextButton", item)
        DEL.Text = "DEL"
        DEL.Size = UDim2.new(0.25, -4, 1, 0)
        DEL.Position = UDim2.new(0.65, 4, 0, 0)
        DEL.TextScaled = true
        DEL.BackgroundColor3 = Color3.fromRGB(200, 80, 80)

        DEL.MouseButton1Click:Connect(function()
            table.remove(warps, i)
            refreshWarpList()
        end)
    end

    scroll.CanvasSize = UDim2.new(0, 0, 0, UIList.AbsoluteContentSize.Y)
end

--------------------------
-- AUTO TP LOOP
--------------------------
task.spawn(function()
    while true do
        task.wait(autoTPDelay)
        if autoTP and #warps > 0 then
            currentIndex = currentIndex + 1
            if currentIndex > #warps then currentIndex = 1 end
            event:FireServer(warps[currentIndex])
        end
    end
end)

--------------------------
-- AUTO RESPAWN
--------------------------
player.CharacterAdded:Connect(function(char)
    if autoRespawn then
        char:WaitForChild("Humanoid").Died:Connect(function()
            task.wait(1)
            player:LoadCharacter()
        end)
    end
end)

--------------------------
-- BUTTON SECTION
--------------------------
local function createButton(text, y)
    local btn = Instance.new("TextButton", main)
    btn.Text = text
    btn.Size = UDim2.new(1, -10, 0, 40 * UIScale)
    btn.Position = UDim2.new(0, 5, 0, y * UIScale)
    btn.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
    btn.TextScaled = true
    btn.AutoButtonColor = true
    local ic = Instance.new("UICorner", btn)
    return btn
end

local autoB = createButton("AutoTP: OFF", 250)
local delayLabel = createButton("Delay: 0.7", 300)
delayLabel.Active = false

local addBtn = createButton("Add Warp", 350)
addBtn.BackgroundColor3 = Color3.fromRGB(80, 80, 200)

local saveBtn = createButton("Save Config", 400)
local loadBtn = createButton("Load Config", 450)

autoB.MouseButton1Click:Connect(function()
    autoTP = not autoTP
    autoB.Text = "AutoTP: " .. (autoTP and "ON" or "OFF")
end)

addBtn.MouseButton1Click:Connect(function()
    local char = player.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        table.insert(warps, hrp.CFrame)
        refreshWarpList()
    end
end)

saveBtn.MouseButton1Click:Connect(function()
    warpStore:SetAsync(player.UserId .. "_warps", warps)
end)

loadBtn.MouseButton1Click:Connect(function()
    local data = warpStore:GetAsync(player.UserId .. "_warps")
    if data then
        warps = data
        refreshWarpList()
    end
end)

--------------------------
-- SERVER HANDLER
--------------------------
event.OnServerEvent:Connect(function(plr, cf)
    if typeof(cf) == "CFrame" and plr.Character then
        local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = cf + Vector3.new(0, 3, 0) end
    end
end)

print("Mobile Warp System Loaded!")
