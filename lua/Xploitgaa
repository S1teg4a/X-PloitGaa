-- UI KUSTOM BY YOU

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Parent = game.CoreGui
ScreenGui.ResetOnSpawn = false

-- Tombol Buka UI (khusus mobile)
local OpenButton = Instance.new("TextButton")
OpenButton.Size = UDim2.new(0,120,0,40)
OpenButton.Position = UDim2.new(0,20,0.85,0)
OpenButton.Text = "OPEN MENU"
OpenButton.BackgroundColor3 = Color3.fromRGB(35,35,35)
OpenButton.TextColor3 = Color3.new(1,1,1)
OpenButton.Parent = ScreenGui

-- MAIN UI FRAME
local Main = Instance.new("Frame")
Main.Size = UDim2.new(0,350,0,280)
Main.Position = UDim2.new(0.5,-175,0.5,-140)
Main.BackgroundColor3 = Color3.fromRGB(25,25,25)
Main.Visible = false
Main.Parent = ScreenGui

local UICorner = Instance.new("UICorner", Main)
UICorner.CornerRadius = UDim.new(0,8)

-- DRAG FUNCTION (untuk mobile & pc)
local dragging = false
local dragInput, dragStart, startPos

local function update(input)
	local delta = input.Position - dragStart
	Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
end

Main.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = Main.Position
		
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end)

Main.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		update(input)
	end
end)

-- BUTTON
local Button = Instance.new("TextButton")
Button.Size = UDim2.new(0,300,0,40)
Button.Position = UDim2.new(0,25,0,40)
Button.Text = "CLICK ME"
Button.BackgroundColor3 = Color3.fromRGB(60,60,60)
Button.TextColor3 = Color3.new(1,1,1)
Button.Parent = Main

Button.MouseButton1Click:Connect(function()
	print("Button ditekan!")
end)

-- TOGGLE
local Toggle = Instance.new("TextButton")
Toggle.Size = UDim2.new(0,300,0,40)
Toggle.Position = UDim2.new(0,25,0,90)
Toggle.BackgroundColor3 = Color3.fromRGB(60,60,60)
Toggle.TextColor3 = Color3.new(1,1,1)
Toggle.Text = "Toggle: OFF"
Toggle.Parent = Main

local toggle_state = false

Toggle.MouseButton1Click:Connect(function()
	toggle_state = not toggle_state
	Toggle.Text = "Toggle: " .. (toggle_state and "ON" or "OFF")
end)

-- SLIDER (simple version)
local SliderFrame = Instance.new("Frame")
SliderFrame.Size = UDim2.new(0,300,0,40)
SliderFrame.Position = UDim2.new(0,25,0,140)
SliderFrame.BackgroundColor3 = Color3.fromRGB(50,50,50)
SliderFrame.Parent = Main

local SliderBar = Instance.new("Frame")
SliderBar.Size = UDim2.new(0.5,0,1,0)
SliderBar.BackgroundColor3 = Color3.fromRGB(0,120,255)
SliderBar.Parent = SliderFrame

local SliderValue = 50

SliderFrame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local pos = (input.Position.X - SliderFrame.AbsolutePosition.X) / SliderFrame.AbsoluteSize.X
		pos = math.clamp(pos, 0, 1)
		SliderBar.Size = UDim2.new(pos,0,1,0)
		SliderValue = math.floor(pos * 100)
		print("Slider:", SliderValue)
	end
end)

-- OPEN BUTTON
OpenButton.MouseButton1Click:Connect(function()
	Main.Visible = not Main.Visible
end)