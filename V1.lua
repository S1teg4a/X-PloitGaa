-- MyUI.lua - Lightweight Rayfield-like UI library (single file)
-- Usage:
-- local MyUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/USERNAME/REPO/main/MyUI.lua"))()
-- local W = MyUI:CreateWindow({Name="Hub", ShowText="Menu", Theme="Blue", ToggleUIKeybind="K"})
-- local t = W:CreateTab("Main")
-- t:CreateToggle({Name="Auto", Default=false, Callback=function(v) print(v) end})

-- ========= Services & Safety =========
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MyUI = {}
MyUI.__index = MyUI

-- ========= Defaults / Theme =========
local THEMES = {
  Blue = {
    Accent = Color3.fromRGB(0,132,255),
    Background = Color3.fromRGB(24,25,32),
    Surface = Color3.fromRGB(34,34,44),
    Text = Color3.fromRGB(235,240,250),
    Subtext = Color3.fromRGB(170,185,205)
  },
  Dark = {
    Accent = Color3.fromRGB(120,120,120),
    Background = Color3.fromRGB(18,18,20),
    Surface = Color3.fromRGB(28,28,31),
    Text = Color3.fromRGB(230,230,230),
    Subtext = Color3.fromRGB(160,160,160)
  }
}

local DEFAULT = {
  WIDTH = 520, HEIGHT = 360, HEADER = 86, MINI = 72, TRANS = 0.20, THEME = "Blue"
}

-- ========= Utility constructors =========
local function new(class, props)
  local o = Instance.new(class)
  if props then for k,v in pairs(props) do o[k] = v end end
  return o
end

local function safeParent(obj, parent) obj.Parent = parent return obj end

local function tween(inst, props, time, style, dir)
  TweenService:Create(inst, TweenInfo.new(time or DEFAULT.TRANS, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props):Play()
end

-- ========= Internal helpers =========
local function getPlayer()
  return Players.LocalPlayer
end

-- ========= Library: CreateWindow =========
function MyUI:CreateWindow(opts)
  opts = opts or {}
  local player = getPlayer()
  if not player then error("LocalPlayer not found") end

  local themeName = opts.Theme or DEFAULT.THEME
  local theme = THEMES[themeName] or THEMES.Blue

  local sg = new("ScreenGui", {Name = "MyUI_" .. tostring(math.random(9999)), ResetOnSpawn = false, IgnoreGuiInset = true})
  sg.Parent = player:WaitForChild("PlayerGui")

  local uiScale = new("UIScale", {Scale = 1})
  uiScale.Parent = sg
  local function updateScale()
    local vp = (Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize) or Vector2.new(1280,720)
    uiScale.Scale = math.clamp(vp.X / 1280, 0.76, 1.18)
  end
  updateScale()
  if Workspace.CurrentCamera then Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale) end

  local Main = new("Frame", {
    Name = "Main",
    Size = UDim2.new(0, DEFAULT.WIDTH, 0, DEFAULT.HEIGHT),
    Position = UDim2.new(0.5, -DEFAULT.WIDTH/2, 0.5, -DEFAULT.HEIGHT/2),
    BackgroundColor3 = theme.Background,
    BorderSizePixel = 0,
    ClipsDescendants = false
  })
  Main.Parent = sg
  new("UICorner", {CornerRadius = UDim.new(0,14)}).Parent = Main
  local Outline = new("UIStroke", {Color = theme.Accent, Thickness = 1.1})
  Outline.Parent = Main

  -- header
  local Header = new("Frame", {Parent = Main, Name = "Header", Size = UDim2.new(1,0,0,DEFAULT.HEADER), BackgroundColor3 = Color3.fromRGB(22,23,30), BorderSizePixel = 0})
  new("UICorner", {CornerRadius = UDim.new(0,12)}).Parent = Header
  local Title = new("TextLabel", {Parent = Header, Text = opts.Name or "MyUI", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = theme.Text, BackgroundTransparency = 1, Position = UDim2.new(0,18,0,12), Size = UDim2.new(0.6,-18,0,28), TextXAlignment = Enum.TextXAlignment.Left})
  local Subtitle = new("TextLabel", {Parent = Header, Text = opts.Subtitle or "", Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = theme.Subtext, BackgroundTransparency = 1, Position = UDim2.new(0,18,0,44), Size = UDim2.new(0.6,-18,0,20), TextXAlignment = Enum.TextXAlignment.Left})

  -- top tabs container
  local TabBar = new("Frame", {Parent = Main, Name = "TabBar", Size = UDim2.new(1,0,0,44), Position = UDim2.new(0,0,0,DEFAULT.HEADER), BackgroundTransparency = 1})
  local TAB_W, TAB_GAP = 150, 18
  local startX = (DEFAULT.WIDTH - (3 * TAB_W + 2 * TAB_GAP)) / 2

  -- pages container
  local Pages = new("Frame", {Parent = Main, Name = "Pages", Size = UDim2.new(1,0,1, -(DEFAULT.HEADER + 44)), Position = UDim2.new(0,0,0, DEFAULT.HEADER + 44), BackgroundTransparency = 1})

  -- scrolling frames for pages
  local function makeScrolling(parent)
    local sf = new("ScrollingFrame", {Parent = parent, BackgroundTransparency = 1, Size = UDim2.new(1,0,1,0), ScrollBarThickness = 6, CanvasSize = UDim2.new(0,0,0,0)})
    new("UIListLayout", {Parent = sf}).Padding = UDim.new(0,12)
    new("UIPadding", {Parent = sf, PaddingLeft = UDim.new(0,16), PaddingTop = UDim.new(0,8), PaddingRight = UDim.new(0,16)})
    return sf
  end
  local PageMain = makeScrolling(Pages)
  PageMain.Name = "MainPage"
  local PageSettings = makeScrolling(Pages); PageSettings.Name = "SettingsPage"; PageSettings.Visible = false
  local PageAbout = makeScrolling(Pages); PageAbout.Name = "AboutPage"; PageAbout.Visible = false

  -- indicator
  local Indicator = new("Frame", {Parent = TabBar, Size = UDim2.new(0,TAB_W,0,3), Position = UDim2.new(0,startX,1,-3), BackgroundColor3 = theme.Accent, BorderSizePixel = 0})

  -- drag logic
  do
    local dragging, dragStart, startPos
    Header.InputBegan:Connect(function(i)
      if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = i.Position; startPos = Main.Position
        i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then dragging = false end end)
      end
    end)
    UserInputService.InputChanged:Connect(function(i)
      if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
        local delta = i.Position - dragStart
        Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
      end
    end)
  end

  -- close & minimize
  local CloseBtn = new("TextButton", {Parent = Header, Size = UDim2.new(0,48,0,48), Position = UDim2.new(1,-56,0,18), BackgroundTransparency = 1, Text = "✕", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = Color3.fromRGB(255,85,85)})
  new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = CloseBtn
  CloseBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

  local MinBtn = new("TextButton", {Parent = Header, Size = UDim2.new(0,48,0,48), Position = UDim2.new(1,-112,0,18), BackgroundTransparency = 1, Text = "—", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = theme.Subtext})
  new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = MinBtn

  -- minimize logic (height-only)
  local minimized = false
  MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
      tween(Main, {Size = UDim2.new(0, DEFAULT.WIDTH, 0, DEFAULT.MINI)}, DEFAULT.TRANS)
      TabBar.Visible = false
      Pages.Visible = false
      MinBtn.Text = "▢"
    else
      tween(Main, {Size = UDim2.new(0, DEFAULT.WIDTH, 0, DEFAULT.HEIGHT)}, DEFAULT.TRANS)
      task.delay(DEFAULT.TRANS*0.9, function() TabBar.Visible = true; Pages.Visible = true; MinBtn.Text = "—" end)
    end
  end)

  -- tab creation & selection
  local tabs = {}
  local function makeTab(name, index)
    local x = startX + (index-1) * (TAB_W + TAB_GAP)
    local bt = new("TextButton", {Parent = TabBar, Size = UDim2.new(0,TAB_W,1,0), Position = UDim2.new(0,x,0,0), BackgroundTransparency = 1, Text = name, Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = Color3.fromRGB(185,200,230)})
    return bt, x
  end

  local t1, tx1 = makeTab("Main", 1)
  local t2, tx2 = makeTab("Settings", 2)
  local t3, tx3 = makeTab("About", 3)
  local function select(i)
    if i == 1 then PageMain.Visible = true; PageSettings.Visible = false; PageAbout.Visible = false; Indicator:TweenPosition(UDim2.new(0, tx1, 1, -3), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, DEFAULT.TRANS, true)
    elseif i == 2 then PageMain.Visible = false; PageSettings.Visible = true; PageAbout.Visible = false; Indicator:TweenPosition(UDim2.new(0, tx2, 1, -3), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, DEFAULT.TRANS, true)
    else PageMain.Visible = false; PageSettings.Visible = false; PageAbout.Visible = true; Indicator:TweenPosition(UDim2.new(0, tx3, 1, -3), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, DEFAULT.TRANS, true) end
  end
  t1.MouseButton1Click:Connect(function() select(1) end)
  t2.MouseButton1Click:Connect(function() select(2) end)
  t3.MouseButton1Click:Connect(function() select(3) end)
  select(1)

  -- center cards & adjust canvas
  local function centerPageCards(page)
    for _,c in ipairs(page:GetChildren()) do
      if c:IsA("Frame") and c.Visible then
        local childW = c.Size.X.Offset
        local left = math.max(12, (DEFAULT.WIDTH - childW)/2)
        c.Position = UDim2.new(0, left, 0, c.Position.Y.Offset)
      end
    end
    local layout = page:FindFirstChildOfClass("UIListLayout")
    if layout then page.CanvasSize = UDim2.new(0,0,0, layout.AbsoluteContentSize.Y + 18) end
  end
  RunService.RenderStepped:Connect(function() centerPageCards(PageMain); centerPageCards(PageSettings); centerPageCards(PageAbout) end)

  -- ========== Component factories for the window (returning methods) ==========
  local WindowAPI = {}
  WindowAPI.ScreenGui = sg
  WindowAPI.Main = Main
  WindowAPI.Pages = {PageMain = PageMain, PageSettings = PageSettings, PageAbout = PageAbout}
  WindowAPI.Theme = theme

  -- create card helper
  local function makeCard(parent, top)
    local card = new("Frame", {Parent = parent, Size = UDim2.new(0, 360, 0, 68), BackgroundColor3 = theme.Surface, BorderSizePixel = 0})
    new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = card
    new("TextLabel", {Parent = card, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = theme.Text, Size = UDim2.new(0.6,0,0,24), Position = UDim2.new(0,12,0,10), TextXAlignment = Enum.TextXAlignment.Left})
    return card
  end

  function WindowAPI:CreateTab(name)
    -- create new tab at end (basic)
    local index = #tabs + 1
    local bt, posx = makeTab(name, index)
    tabs[index] = {Button = bt, X = posx}
    -- create page
    local page = makeScrolling(Pages)
    page.Name = name .. "_Page"
    -- update click selection
    bt.MouseButton1Click:Connect(function() select(index) end)
    return {
      _page = page,
      CreateToggle = function(_, cfg)
        cfg = cfg or {}; cfg.Name = cfg.Name or "Toggle"; cfg.Default = cfg.Default or false
        local card = new("Frame", {Parent = page, Size = UDim2.new(0,360,0,68), BackgroundColor3 = theme.Surface, BorderSizePixel = 0})
        new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = card
        local label = new("TextLabel", {Parent = card, Text = cfg.Name, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = theme.Text, Position = UDim2.new(0,12,0,10), Size = UDim2.new(0.6,0,0,24), TextXAlignment = Enum.TextXAlignment.Left})
        local btn = new("TextButton", {Parent = card, Size = UDim2.new(0,64,0,36), Position = UDim2.new(1,-96,0.5,-18), BackgroundColor3 = Color3.fromRGB(72,72,98), Text = "", AutoButtonColor = false})
        new("UICorner", {CornerRadius = UDim.new(0,18)}).Parent = btn
        local dot = new("Frame", {Parent = btn, Size = UDim2.new(0,30,0,30), Position = UDim2.new(0,2,0,2), BackgroundColor3 = Color3.fromRGB(245,245,250)})
        new("UICorner", {CornerRadius = UDim.new(0,15)}).Parent = dot
        local state = cfg.Default
        if state then btn.BackgroundColor3 = theme.Accent; dot.Position = UDim2.new(1,-32,0,2) end
        btn.MouseButton1Click:Connect(function()
          state = not state
          if state then tween(btn, {BackgroundColor3 = theme.Accent}, 0.14); dot:TweenPosition(UDim2.new(1,-32,0,2), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.14, true)
          else tween(btn, {BackgroundColor3 = Color3.fromRGB(72,72,98)}, 0.14); dot:TweenPosition(UDim2.new(0,2,0,2), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.14, true) end
          if cfg.Callback then pcall(cfg.Callback, state) end
        end)
        return card
      end,
      CreateSlider = function(_, cfg)
        cfg = cfg or {} cfg.Name = cfg.Name or "Slider" cfg.Min = cfg.Min or 1 cfg.Max = cfg.Max or 100 cfg.Default = cfg.Default or cfg.Min
        local card = new("Frame", {Parent = page, Size = UDim2.new(0,360,0,72), BackgroundColor3 = theme.Surface, BorderSizePixel = 0})
        new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = card
        new("TextLabel", {Parent = card, Text = cfg.Name, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = theme.Text, Position = UDim2.new(0,12,0,8), Size = UDim2.new(0.6,0,0,22), TextXAlignment = Enum.TextXAlignment.Left})
        local bar = new("Frame", {Parent = card, Size = UDim2.new(0,300,0,8), Position = UDim2.new(0,12,1,-22), BackgroundColor3 = Color3.fromRGB(58,58,76)})
        new("UICorner", {CornerRadius = UDim.new(0,6)}).Parent = bar
        local fill = new("Frame", {Parent = bar, Size = UDim2.new(((cfg.Default-cfg.Min)/(cfg.Max-cfg.Min)),0,1,0), BackgroundColor3 = theme.Accent})
        new("UICorner", {CornerRadius = UDim.new(0,6)}).Parent = fill
        local dragging = false
        bar.InputBegan:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = true end end)
        bar.InputEnded:Connect(function(i) if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then dragging = false end end)
        UserInputService.InputChanged:Connect(function(i)
          if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local rel = (i.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X
            rel = math.clamp(rel, 0, 1)
            fill.Size = UDim2.new(rel,0,1,0)
            local val = math.floor(cfg.Min + (cfg.Max - cfg.Min)*rel)
            if cfg.Callback then pcall(cfg.Callback, val) end
          end
        end)
        return card
      end,
      CreateDropdown = function(_, cfg)
        cfg = cfg or {} cfg.Name = cfg.Name or "Dropdown" cfg.Options = cfg.Options or {"A","B"} cfg.Default = cfg.Default or cfg.Options[1]
        local card = new("Frame", {Parent = page, Size = UDim2.new(0,360,0,68), BackgroundColor3 = theme.Surface, BorderSizePixel = 0})
        new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = card
        new("TextLabel", {Parent = card, Text = cfg.Name, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = theme.Text, Position = UDim2.new(0,12,0,10), Size = UDim2.new(0.6,0,0,24), TextXAlignment = Enum.TextXAlignment.Left})
        local btn = new("TextButton", {Parent = card, Size = UDim2.new(0,220,0,36), Position = UDim2.new(1,-250,0.5,-18), BackgroundColor3 = theme.Accent, Text = cfg.Default, Font = Enum.Font.GothamSemibold, TextSize = 14, TextColor3 = Color3.new(1,1,1)})
        new("UICorner", {CornerRadius = UDim.new(0,6)}).Parent = btn
        local drop = new("Frame", {Parent = card, Size = UDim2.new(0,220,0,0), Position = UDim2.new(1,-250,1,6), BackgroundColor3 = Color3.fromRGB(38,38,50), ClipsDescendants = true})
        new("UICorner", {CornerRadius = UDim.new(0,6)}).Parent = drop
        local open = false
        local function openDrop() drop.Visible = true; tween(drop, {Size = UDim2.new(0,220,0,#cfg.Options * 28)}, 0.18) open = true end
        local function closeDrop() tween(drop, {Size = UDim2.new(0,220,0,0)}, 0.16); task.delay(0.16, function() drop.Visible = false end); open = false end
        btn.MouseButton1Click:Connect(function() if open then closeDrop() else openDrop() end end)
        for i,opt in ipairs(cfg.Options) do
          local optBtn = new("TextButton", {Parent = drop, Size = UDim2.new(1,0,0,28), Position = UDim2.new(0,0,0,(i-1)*28), BackgroundTransparency = 1, Text = opt, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = theme.Text})
          optBtn.MouseButton1Click:Connect(function() btn.Text = opt; closeDrop(); if cfg.Callback then pcall(cfg.Callback, opt) end end)
        end
        return card
      end,
      CreateKeybind = function(_, cfg)
        cfg = cfg or {} cfg.Name = cfg.Name or "Keybind" cfg.Default = cfg.Default or "K"
        local card = new("Frame", {Parent = page, Size = UDim2.new(0,360,0,68), BackgroundColor3 = theme.Surface, BorderSizePixel = 0})
        new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = card
        new("TextLabel", {Parent = card, Text = cfg.Name, BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 16, TextColor3 = theme.Text, Position = UDim2.new(0,12,0,10), Size = UDim2.new(0.6,0,0,24), TextXAlignment = Enum.TextXAlignment.Left})
        local kb = new("TextButton", {Parent = card, Size = UDim2.new(0,140,0,36), Position = UDim2.new(1,-180,0.5,-18), BackgroundColor3 = theme.Accent, Text = cfg.Default, Font = Enum.Font.GothamSemibold, TextSize = 14, TextColor3 = Color3.new(1,1,1)})
        new("UICorner", {CornerRadius = UDim.new(0,6)}).Parent = kb
        local waiting = false
        kb.MouseButton1Click:Connect(function() if waiting then return end; waiting = true; kb.Text = "..." end)
        local conn
        conn = UserInputService.InputBegan:Connect(function(i, gp) if waiting and not gp and i.UserInputType == Enum.UserInputType.Keyboard then local name = tostring(i.KeyCode):gsub("Enum.KeyCode.",""); kb.Text = name; waiting = false; if cfg.Callback then pcall(cfg.Callback, name, i.KeyCode) end end end)
        return card
      end,
      CreateButton = function(_, cfg)
        cfg = cfg or {} cfg.Name = cfg.Name or "Button"
        local card = new("Frame", {Parent = page, Size = UDim2.new(0,360,0,72), BackgroundColor3 = theme.Surface, BorderSizePixel = 0})
        new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = card
        local btn = new("TextButton", {Parent = card, Size = UDim2.new(0,220,0,40), Position = UDim2.new(0.5,-110,0.5,-20), BackgroundColor3 = theme.Accent, Text = cfg.Name, Font = Enum.Font.GothamSemibold, TextSize = 16, TextColor3 = Color3.new(1,1,1)})
        new("UICorner", {CornerRadius = UDim.new(0,8)}).Parent = btn
        btn.MouseButton1Click:Connect(function() if cfg.Callback then pcall(cfg.Callback) end end)
        return card
      end
    }
  end

  -- Add some default content for pages
  new("TextLabel", {Parent = PageAbout, Text = "About - MyUI library\nCustom lightweight UI", BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 14, TextColor3 = theme.Subtext, Size = UDim2.new(0.9,0,0.9,0), Position = UDim2.new(0.05,0,0.05,0), TextWrapped = true})

  -- expose some helpers
  function WindowAPI:CreateTab(name)
    return WindowAPI:CreateTab -- not used externally here; use Window:CreateTab from top-level
  end

  -- Final window object (exposed to caller)
  local WindowObj = {
    ScreenGui = sg,
    Main = Main,
    CreateTab = function(_, name)
      -- simpler: reuse existing pages for first three, else create new tab button at right
      if name == "Main" then return { _page = PageMain, CreateToggle = WindowAPI.CreateTab(PageMain).CreateToggle } end
      -- fallback: create a 'tab' using internal factory by appending to TabBar; for simplicity, we return a minimal wrapper using PageMain
      return { _page = PageMain, CreateToggle = WindowAPI.CreateTab(PageMain).CreateToggle }
    end,
    Notify = function(_, msg) -- small wrapper
      local n = new("Frame", {Parent = sg, Size = UDim2.new(0,260,0,56), Position = UDim2.new(1, 320, 1, -120), BackgroundColor3 = Color3.fromRGB(40,40,54)})
      new("UICorner", {CornerRadius = UDim.new(0,10)}).Parent = n
      new("TextLabel", {Parent = n, BackgroundTransparency = 1, Size = UDim2.new(1,-24,1,0), Position = UDim2.new(0,12,0,0), Text = msg, Font = Enum.Font.GothamMedium, TextSize = 15, TextColor3 = Color3.fromRGB(240,240,240), TextXAlignment = Enum.TextXAlignment.Left})
      tween(n, {Position = UDim2.new(1, -320, 1, -120)}, 0.22)
      task.delay(3, function() tween(n, {Position = UDim2.new(1, 320, 1, -120)}, 0.18); task.wait(0.2); n:Destroy() end)
    end
  }

  -- wire toggle UI key if provided
  local keybind = opts.ToggleUIKeybind or "K"
  UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.Keyboard and tostring(input.KeyCode):gsub("Enum.KeyCode.","") == tostring(keybind) then
      Main.Visible = not Main.Visible
    end
  end)

  -- return object
  return WindowObj
end

-- expose library
return MyUI
