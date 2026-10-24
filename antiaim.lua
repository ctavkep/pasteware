local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local GameSettings = nil
pcall(function()
	GameSettings = UserSettings():GetService("UserGameSettings")
end)


local Config = {
	Enabled = true,
	ToggleKey = Enum.KeyCode.L,

	
	PitchMode = "Down",       
	CustomPitch = -89,        

	
	YawBase = "Camera",       
	YawMode = "Backward",     
	YawOffset = 0,            
	ModifierRange = 45,       

	
	WorkInFirstPerson = true, 
	CameraSpoof = true,       
	ManipulateJoints = true,  
	StrictNeckYaw = true,     
}


local State = {
	SpinAngle = 0,
	JitterFlip = false,
	TargetYawRad = 0,
	TargetPitchRad = 0,
	FakeLookCFrame = CFrame.new(),

	CachedChar = nil,
	CachedHum = nil,
	CachedRoot = nil,
	CachedNeck = nil,
	CachedWaist = nil,
	CachedCam = Camera,

	OriginalNeckC0 = nil,
	OriginalNeckC1 = nil,
	OriginalWaistC0 = nil,
	OriginalWaistC1 = nil,
	IsR15 = false,
}

local function GetSafeGuiParent()
	if gethui then
		return gethui()
	elseif pcall(function() return CoreGui.Name end) then
		return CoreGui
	else
		return LocalPlayer:WaitForChild("PlayerGui")
	end
end

local function CacheCharacterReferences(character)
	State.CachedChar = character
	State.CachedHum = nil
	State.CachedRoot = nil
	State.CachedNeck = nil
	State.CachedWaist = nil
	State.OriginalNeckC0 = nil
	State.OriginalNeckC1 = nil
	State.OriginalWaistC0 = nil
	State.OriginalWaistC1 = nil

	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end

	State.CachedHum = humanoid
	State.CachedRoot = root
	State.IsR15 = (humanoid.RigType == Enum.HumanoidRigType.R15)

	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("Torso")
	local upperTorso = character:FindFirstChild("UpperTorso")

	if State.IsR15 then
		local neck = (head and head:FindFirstChild("Neck")) or character:FindFirstChild("Neck", true)
		local waist = (upperTorso and upperTorso:FindFirstChild("Waist")) or character:FindFirstChild("Waist", true)
		if neck and neck:IsA("Motor6D") then
			State.CachedNeck = neck
			State.OriginalNeckC0 = neck.C0
			State.OriginalNeckC1 = neck.C1
		end
		if waist and waist:IsA("Motor6D") then
			State.CachedWaist = waist
			State.OriginalWaistC0 = waist.C0
			State.OriginalWaistC1 = waist.C1
		end
	else
		local neck = (torso and torso:FindFirstChild("Neck")) or (head and head:FindFirstChild("Neck")) or character:FindFirstChild("Neck", true)
		if neck and neck:IsA("Motor6D") then
			State.CachedNeck = neck
			State.OriginalNeckC0 = neck.C0
			State.OriginalNeckC1 = neck.C1
		end
	end
end

if LocalPlayer.Character then
	CacheCharacterReferences(LocalPlayer.Character)
end

LocalPlayer.CharacterAdded:Connect(function(char)
	task.wait(0.25)
	CacheCharacterReferences(char)
end)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	Camera = workspace.CurrentCamera
	State.CachedCam = Camera
end)


local function GetTargetPitch()
	local mode = Config.PitchMode
	if mode == "Down" then
		return -89
	elseif mode == "Up" then
		return 89
	elseif mode == "Zero" or mode == "None" then
		return 0
	elseif mode == "Jitter" then
		return State.JitterFlip and -89 or 89
	elseif mode == "Custom" then
		return math.clamp(Config.CustomPitch, -89, 89)
	end
	return 0
end

local function GetTargetYaw(dt)
	local baseYaw = 0
	if Config.YawBase == "Camera" and State.CachedCam then
		local camLook = State.CachedCam.CFrame.LookVector
		baseYaw = math.deg(math.atan2(-camLook.X, -camLook.Z))
	end

	local modeYaw = 0
	local mode = Config.YawMode
	if mode == "Backward" then
		modeYaw = 180
	elseif mode == "Static" then
		modeYaw = 0
	elseif mode == "Jitter" then
		modeYaw = 180 + (State.JitterFlip and (Config.ModifierRange * 0.5) or -(Config.ModifierRange * 0.5))
	elseif mode == "Spin" then
		State.SpinAngle = (State.SpinAngle + (dt * Config.ModifierRange * 12)) % 360
		modeYaw = State.SpinAngle
	end

	return baseYaw + modeYaw + Config.YawOffset
end


if hookmetamethod and checkcaller then
	local oldIndex
	local inHook = false

	oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)

		if inHook or checkcaller() or not Config.Enabled then
			return oldIndex(self, key)
		end


		if key == "AutoRotate" and rawequal(self, State.CachedHum) then
			return true
		end


		if rawequal(self, State.CachedNeck) then
			if key == "C0" and State.OriginalNeckC0 then
				return State.OriginalNeckC0
			elseif key == "C1" and State.OriginalNeckC1 then
				return State.OriginalNeckC1
			end
		elseif rawequal(self, State.CachedWaist) then
			if key == "C0" and State.OriginalWaistC0 then
				return State.OriginalWaistC0
			elseif key == "C1" and State.OriginalWaistC1 then
				return State.OriginalWaistC1
			end
		end


		if Config.CameraSpoof and rawequal(self, State.CachedCam) and (key == "CFrame" or key == "CoordinateFrame") then
			if debug and debug.info then
				inHook = true
				local funcName = debug.info(3, "n") or debug.info(2, "n")
				inHook = false

				if funcName == "GetDirection" or funcName == "UpdateHead" or funcName == "UpdateTorso" or funcName == "Step" then
					return State.FakeLookCFrame
				end
			end
		end

		return oldIndex(self, key)
	end))
end


local function ApplyStrictJointAngles()
	local neck = State.CachedNeck
	local waist = State.CachedWaist

	if not Config.Enabled or not Config.ManipulateJoints or Config.PitchMode == "None" then
		if neck and State.OriginalNeckC0 then
			neck.C0 = State.OriginalNeckC0
			if State.OriginalNeckC1 then neck.C1 = State.OriginalNeckC1 end
		end
		if waist and State.OriginalWaistC0 then
			waist.C0 = State.OriginalWaistC0
			if State.OriginalWaistC1 then waist.C1 = State.OriginalWaistC1 end
		end
		return
	end

	local pitchRad = State.TargetPitchRad

	if State.IsR15 then
		if neck and State.OriginalNeckC0 then

			local basePos = State.OriginalNeckC0.Position
			neck.C0 = CFrame.new(basePos) * CFrame.Angles(pitchRad * 0.65, 0, 0)
			if Config.StrictNeckYaw and State.OriginalNeckC1 then
				neck.C1 = CFrame.new(State.OriginalNeckC1.Position)

				local tx, ty, tz = neck.Transform.X, neck.Transform.Y, neck.Transform.Z
				neck.Transform = CFrame.new(tx, ty, tz)
			end
		end
		if waist and State.OriginalWaistC0 then
			local basePos = State.OriginalWaistC0.Position
			waist.C0 = CFrame.new(basePos) * CFrame.Angles(pitchRad * 0.35, 0, 0)
			if Config.StrictNeckYaw and State.OriginalWaistC1 then
				waist.C1 = CFrame.new(State.OriginalWaistC1.Position)
				local tx, ty, tz = waist.Transform.X, waist.Transform.Y, waist.Transform.Z
				waist.Transform = CFrame.new(tx, ty, tz)
			end
		end
	else

		if neck and State.OriginalNeckC0 then
			local pos = State.OriginalNeckC0.Position
			neck.C0 = CFrame.new(pos) * CFrame.Angles(math.rad(-90) - pitchRad, 0, math.rad(180))
			if Config.StrictNeckYaw and State.OriginalNeckC1 then
				neck.C1 = CFrame.new(State.OriginalNeckC1.Position) * CFrame.Angles(math.rad(-90), 0, math.rad(180))
				local tx, ty, tz = neck.Transform.X, neck.Transform.Y, neck.Transform.Z
				neck.Transform = CFrame.new(tx, ty, tz)
			end
		end
	end
end

local function UpdateAntiAimState(dt)
	local char = LocalPlayer.Character
	if char ~= State.CachedChar then
		CacheCharacterReferences(char)
	end

	local hum = State.CachedHum
	local root = State.CachedRoot
	if not hum or not root or hum.Health <= 0 then return end

	if not Config.Enabled then
		hum.AutoRotate = true
		return
	end


	hum.AutoRotate = false
	if Config.WorkInFirstPerson and GameSettings then
		if GameSettings.RotationType == Enum.RotationType.CameraRelative then
			GameSettings.RotationType = Enum.RotationType.MovementRelative
		end
	end


	State.JitterFlip = not State.JitterFlip
	local targetYawDeg = GetTargetYaw(dt)
	local targetPitchDeg = GetTargetPitch()

	local yawRad = math.rad(targetYawDeg)
	local pitchRad = math.rad(targetPitchDeg)

	State.TargetYawRad = yawRad
	State.TargetPitchRad = pitchRad


	local rootPos = root.Position
	root.CFrame = CFrame.new(rootPos) * CFrame.Angles(0, yawRad, 0)


	if State.CachedCam then
		local camPos = State.CachedCam.CFrame.Position
		State.FakeLookCFrame = CFrame.new(camPos) * CFrame.Angles(0, yawRad, 0) * CFrame.Angles(pitchRad, 0, 0)
	end


	ApplyStrictJointAngles()
end


RunService:BindToRenderStep("CS2_AA_PostCamera", Enum.RenderPriority.Last.Value + 10, function(dt)
	UpdateAntiAimState(dt)
end)


RunService.Stepped:Connect(function()
	if not Config.Enabled then return end
	local root = State.CachedRoot
	local hum = State.CachedHum
	if root and hum and hum.Health > 0 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, State.TargetYawRad, 0)
		ApplyStrictJointAngles()
	end
end)


RunService.Heartbeat:Connect(function()
	if not Config.Enabled then return end
	local root = State.CachedRoot
	local hum = State.CachedHum
	if root and hum and hum.Health > 0 then
		root.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, State.TargetYawRad, 0)
		ApplyStrictJointAngles()
	end
end)


local SafeParent = GetSafeGuiParent()
local OldGui = SafeParent:FindFirstChild("CS2_AntiAim_UI")
if OldGui then
	OldGui:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "CS2_AntiAim_UI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = SafeParent

local MainFrame = Instance.new("Frame")
MainFrame.Name = "Main"
MainFrame.Size = UDim2.new(0, 390, 0, 490)
MainFrame.Position = UDim2.new(0.5, -195, 0.5, -245)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
MainFrame.BorderSizePixel = 0
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 8)
UICorner.Parent = MainFrame

local UIStroke = Instance.new("UIStroke")
UIStroke.Color = Color3.fromRGB(95, 115, 255)
UIStroke.Thickness = 1.5
UIStroke.Parent = MainFrame

local Header = Instance.new("Frame")
Header.Size = UDim2.new(1, 0, 0, 38)
Header.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
Header.BorderSizePixel = 0
Header.Parent = MainFrame

local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 8)
HeaderCorner.Parent = Header

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -20, 1, 0)
TitleLabel.Position = UDim2.new(0, 12, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "ANTI-AIM"
TitleLabel.TextColor3 = Color3.fromRGB(235, 235, 245)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header


do
	local dragging, dragInput, dragStart, startPos
	Header.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = MainFrame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	Header.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			MainFrame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

local Container = Instance.new("ScrollingFrame")
Container.Size = UDim2.new(1, -20, 1, -50)
Container.Position = UDim2.new(0, 10, 0, 44)
Container.BackgroundTransparency = 1
Container.ScrollBarThickness = 3
Container.ScrollBarImageColor3 = Color3.fromRGB(95, 115, 255)
Container.CanvasSize = UDim2.new(0, 0, 0, 0)
Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
Container.Parent = MainFrame

local UIList = Instance.new("UIListLayout")
UIList.Padding = UDim.new(0, 8)
UIList.SortOrder = Enum.SortOrder.LayoutOrder
UIList.Parent = Container

local function CreateToggle(name, default, callback)
	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(1, -6, 0, 34)
	Frame.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
	Frame.Parent = Container

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 6)
	Corner.Parent = Frame

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -60, 1, 0)
	Label.Position = UDim2.new(0, 10, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = name
	Label.TextColor3 = Color3.fromRGB(215, 215, 225)
	Label.Font = Enum.Font.GothamMedium
	Label.TextSize = 13
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Frame

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(0, 42, 0, 20)
	Button.Position = UDim2.new(1, -52, 0.5, -10)
	Button.BackgroundColor3 = default and Color3.fromRGB(95, 115, 255) or Color3.fromRGB(50, 50, 65)
	Button.Text = default and "ON" or "OFF"
	Button.TextColor3 = Color3.fromRGB(255, 255, 255)
	Button.Font = Enum.Font.GothamBold
	Button.TextSize = 11
	Button.Parent = Frame

	local BtnCorner = Instance.new("UICorner")
	BtnCorner.CornerRadius = UDim.new(0, 5)
	BtnCorner.Parent = Button

	local state = default
	Button.MouseButton1Click:Connect(function()
		state = not state
		Button.BackgroundColor3 = state and Color3.fromRGB(95, 115, 255) or Color3.fromRGB(50, 50, 65)
		Button.Text = state and "ON" or "OFF"
		callback(state)
	end)
end

local function CreateSelector(name, options, default, callback)
	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(1, -6, 0, 36)
	Frame.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
	Frame.Parent = Container

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 6)
	Corner.Parent = Frame

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(0.52, 0, 1, 0)
	Label.Position = UDim2.new(0, 10, 0, 0)
	Label.BackgroundTransparency = 1
	Label.Text = name
	Label.TextColor3 = Color3.fromRGB(215, 215, 225)
	Label.Font = Enum.Font.GothamMedium
	Label.TextSize = 13
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Frame

	local Button = Instance.new("TextButton")
	Button.Size = UDim2.new(0.42, 0, 0, 24)
	Button.Position = UDim2.new(0.55, 0, 0.5, -12)
	Button.BackgroundColor3 = Color3.fromRGB(38, 38, 52)
	Button.Text = default
	Button.TextColor3 = Color3.fromRGB(130, 150, 255)
	Button.Font = Enum.Font.GothamBold
	Button.TextSize = 12
	Button.Parent = Frame

	local BtnCorner = Instance.new("UICorner")
	BtnCorner.CornerRadius = UDim.new(0, 5)
	BtnCorner.Parent = Button

	local idx = table.find(options, default) or 1
	Button.MouseButton1Click:Connect(function()
		idx = (idx % #options) + 1
		local selected = options[idx]
		Button.Text = selected
		callback(selected)
	end)
end

local function CreateSlider(name, minVal, maxVal, default, callback)
	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(1, -6, 0, 48)
	Frame.BackgroundColor3 = Color3.fromRGB(25, 25, 34)
	Frame.Parent = Container

	local Corner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, 6)
	Corner.Parent = Frame

	local Label = Instance.new("TextLabel")
	Label.Size = UDim2.new(1, -20, 0, 20)
	Label.Position = UDim2.new(0, 10, 0, 4)
	Label.BackgroundTransparency = 1
	Label.Text = name .. ": " .. tostring(default) .. "°"
	Label.TextColor3 = Color3.fromRGB(215, 215, 225)
	Label.Font = Enum.Font.GothamMedium
	Label.TextSize = 12
	Label.TextXAlignment = Enum.TextXAlignment.Left
	Label.Parent = Frame

	local Bar = Instance.new("Frame")
	Bar.Size = UDim2.new(1, -20, 0, 8)
	Bar.Position = UDim2.new(0, 10, 0, 30)
	Bar.BackgroundColor3 = Color3.fromRGB(45, 45, 60)
	Bar.Parent = Frame

	local BarCorner = Instance.new("UICorner")
	BarCorner.CornerRadius = UDim.new(1, 0)
	BarCorner.Parent = Bar

	local Fill = Instance.new("Frame")
	local initPercent = (default - minVal) / (maxVal - minVal)
	Fill.Size = UDim2.new(initPercent, 0, 1, 0)
	Fill.BackgroundColor3 = Color3.fromRGB(95, 115, 255)
	Fill.Parent = Bar

	local FillCorner = Instance.new("UICorner")
	FillCorner.CornerRadius = UDim.new(1, 0)
	FillCorner.Parent = Fill

	local sliding = false
	local function UpdateSlider(input)
		local rel = math.clamp((input.Position.X - Bar.AbsolutePosition.X) / Bar.AbsoluteSize.X, 0, 1)
		local val = math.floor(minVal + (maxVal - minVal) * rel)
		Fill.Size = UDim2.new(rel, 0, 1, 0)
		Label.Text = name .. ": " .. tostring(val) .. "°"
		callback(val)
	end

	Bar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = true
			UpdateSlider(input)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			sliding = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
			UpdateSlider(input)
		end
	end)
end


CreateToggle("Enable Anti-Aim", Config.Enabled, function(v)
	Config.Enabled = v
	if not v then
		ApplyStrictJointAngles()
		if State.CachedHum then State.CachedHum.AutoRotate = true end
	end
end)

CreateSelector("Pitch Mode", {"Down", "Up", "Zero", "Jitter", "Custom", "None"}, Config.PitchMode, function(v)
	Config.PitchMode = v
end)

CreateSlider("Custom Pitch", -89, 89, Config.CustomPitch, function(v)
	Config.CustomPitch = v
end)

CreateSelector("Yaw Base", {"Camera", "World"}, Config.YawBase, function(v)
	Config.YawBase = v
end)

CreateSelector("Yaw Mode", {"Backward", "Static", "Jitter", "Spin"}, Config.YawMode, function(v)
	Config.YawMode = v
end)

CreateSlider("Yaw Offset", -180, 180, Config.YawOffset, function(v)
	Config.YawOffset = v
end)

CreateSlider("Jitter / Spin Диапазон", 1, 180, Config.ModifierRange, function(v)
	Config.ModifierRange = v
end)

CreateToggle("Lock Neck Yaw", Config.StrictNeckYaw, function(v)
	Config.StrictNeckYaw = v
end)

CreateToggle("FirstPerson & ShiftLock Bypass", Config.WorkInFirstPerson, function(v)
	Config.WorkInFirstPerson = v
end)

CreateToggle("Spoof GetDirection", Config.CameraSpoof, function(v)
	Config.CameraSpoof = v
end)

CreateToggle("Direct Neck/Waist Motor6D", Config.ManipulateJoints, function(v)
	Config.ManipulateJoints = v
	if not v then ApplyStrictJointAngles() end
end)


UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Config.ToggleKey then
		ScreenGui.Enabled = not ScreenGui.Enabled
	end
end)