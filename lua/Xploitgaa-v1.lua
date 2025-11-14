--== Load Rayfield ==--
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

--== Create Window ==--
local Window = Rayfield:CreateWindow({
    Name = "Universal Hub (Mobile + PC)",
    Icon = 0,
    LoadingTitle = "Loading UI...",
    LoadingSubtitle = "Mobile + PC Ready",
    Theme = "Default",

    -- PC Keybind
    ToggleUIKeybind = "RightShift", 

    -- Penting banget untuk MOBILE
    ShowText = "Open Menu",

    ConfigurationSaving = {
        Enabled = true,
        FileName = "UniversalHub"
    }
})

--== Create Tabs ==--
local MainTab = Window:CreateTab("Main", 4483362458)
local PlayerTab = Window:CreateTab("Player", 4483362458)

--== MAIN: Button ==--
MainTab:CreateButton({
    Name = "Print Test",
    Callback = function()
        print("Button ditekan!")
    end,
})

--== MAIN: Toggle ==--
MainTab:CreateToggle({
    Name = "Toggle Contoh",
    CurrentValue = false,
    Flag = "ExampleToggle",
    Callback = function(v)
        print("Toggle:", v)
    end,
})

--== PLAYER: Slider ==--
PlayerTab:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 200},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "SpeedSlider",
    Callback = function(value)
        game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = value
    end,
})

--== PLAYER: Slider Jump ==--
PlayerTab:CreateSlider({
    Name = "JumpPower",
    Range = {50, 300},
    Increment = 5,
    Suffix = "Power",
    CurrentValue = 50,
    Flag = "JumpSlider",
    Callback = function(value)
        game.Players.LocalPlayer.Character.Humanoid.JumpPower = value
    end,
})