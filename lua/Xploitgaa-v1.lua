--== Load Rayfield ==--
local Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/shlexware/Rayfield/main/source"))()

--== Create Window ==--
local Window = Rayfield:CreateWindow({
    Name = "Mountain Hub (Mobile + PC)",
    Icon = 0,
    LoadingTitle = "Loading Mountain Hub...",
    LoadingSubtitle = "Mobile + PC Ready",
    Theme = "Default",

    ToggleUIKeybind = "RightShift",
    ShowText = "Mountain Menu",

    ConfigurationSaving = {
        Enabled = true,
        FileName = "MountainHub"
    }
})

--== Tabs ==--
local Main = Window:CreateTab("Main", 4483362458)
local Player = Window:CreateTab("Player", 4483362458)
local Teleport = Window:CreateTab("Teleport", 4483362458)

--== Main: Anti-Fall ==--
Main:CreateToggle({
	Name = "Anti Fall (Anti Slip)",
	CurrentValue = false,
	Flag = "AntiFall",
	Callback = function(v)
		local char = game.Players.LocalPlayer.Character
		if v then
			char.HumanoidRootPart.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.5)
		else
			char.HumanoidRootPart.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.3)
		end
	end,
})

--== Main: Auto Climb ==--
Main:CreateToggle({
    Name = "Auto Climb (Boost Vertical)",
    CurrentValue = false,
    Flag = "AutoClimb",
    Callback = function(v)
        getgenv().autoClimb = v
        while autoClimb do
            task.wait()
            local h = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if h then
                h.Velocity = Vector3.new(h.Velocity.X, 50, h.Velocity.Z)
            end
        end
    end,
})

--== Player: WalkSpeed ==--
Player:CreateSlider({
    Name = "WalkSpeed",
    Range = {16, 150},
    Increment = 1,
    Suffix = "Speed",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(v)
        game.Players.LocalPlayer.Character.Humanoid.WalkSpeed = v
    end,
})

--== Player: JumpPower ==--
Player:CreateSlider({
    Name = "JumpPower",
    Range = {50, 300},
    Increment = 5,
    Suffix = "Power",
    CurrentValue = 50,
    Flag = "JumpPower",
    Callback = function(v)
        game.Players.LocalPlayer.Character.Humanoid.JumpPower = v
    end,
})

--== Teleport: Locations ==--
local locations = {
    ["Basecamp"] = Vector3.new(0, 10, 0),
    ["Pos 1"] = Vector3.new(100, 50, -30),
    ["Pos 2"] = Vector3.new(200, 130, -60),
    ["Cliff Edge"] = Vector3.new(300, 200, -120),
    ["Peak / Summit"] = Vector3.new(380, 300, -180)
}

for name, pos in pairs(locations) do
    Teleport:CreateButton({
        Name = "Teleport ke "..name,
        Callback = function()
            local hrp = game.Players.LocalPlayer.Character:WaitForChild("HumanoidRootPart")
            hrp.CFrame = CFrame.new(pos)
        end,
    })
end