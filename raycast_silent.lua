-- 01_raycast_silent.lua
-- Method: __namecall hook on workspace:Raycast & workspace:Spherecast + Full-Exposure Multipoint Autofire + Liquid Glass UI

local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local ScriptContext = cloneref(game:GetService("ScriptContext"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Config = {
    SilentEnabled = true,
    FOV = 180,
    ShowFOV = true,
    HitChance = 100,
    TeamCheck = false,
    IgnoreForceField = true,
    WallCheck = true,
    Multipoint = true,
    MultipointScale = 0.72,
    TargetParts = {
        Head = true,
        Torso = false,
        HumanoidRootPart = false,
        LeftArm = false,
        RightArm = false,
        LeftLeg = false,
        RightLeg = false
    },
    AutoFire = false,
    AutoFireKey = Enum.KeyCode.F,
    MenuKey = Enum.KeyCode.Delete,
    FireInterval = 85, -- ms (10 to 10000)
    RequireFullExposure = true,
    ChamsEnabled = true,
    ChamsFill = Color3.fromRGB(255, 50, 50),
    ChamsOutline = Color3.fromRGB(255, 255, 255)
}

local SafeContainer = (gethui and gethui()) or CoreGui
local ProtectedInstances = setmetatable({}, { __mode = "k" })
local function ProtectInstance(inst)
    ProtectedInstances[inst] = true
    return inst
end

local function RandomStr(len)
    local s = {}
    for i = 1, len or 12 do
        s[i] = string.char(math.random(97, 122))
    end
    return table.concat(s)
end

-- [1] 99% sUNC Anti-Cheat & GUI Detection Bypass
local function BypassAntiCheats()
    if getconnections then
        for _, sig in ipairs({ ScriptContext.Error, LogService.MessageOut, GuiService.MenuOpened }) do
            pcall(function()
                for _, conn in ipairs(getconnections(sig)) do
                    conn:Disable()
                end
            end)
        end
    end
    if getgc and hookfunction and newcclosure then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" then
                    local det = rawget(v, "Detected")
                    local kill = rawget(v, "Kill")
                    if type(det) == "function" and islclosure(det) and not isexecutorclosure(det) then
                        hookfunction(det, newcclosure(function() return true end))
                    end
                    if type(kill) == "function" and islclosure(kill) and not isexecutorclosure(kill) then
                        hookfunction(kill, newcclosure(function() return nil end))
                    end
                    local anti = rawget(v, "Anti")
                    if type(anti) == "table" and rawget(v, "Variables") and rawget(v, "Process") then
                        for _, func in pairs(anti) do
                            if type(func) == "function" and islclosure(func) and not isexecutorclosure(func) then
                                hookfunction(func, newcclosure(function() return true end))
                            end
                        end
                    end
                end
            end
        end)
    end
end
pcall(BypassAntiCheats)

-- [2] Bone Map & Multipoint Exposure Engine
local PartMap = {
    Head = { "Head", "FakeHead", "HeadHitbox", "HeadBox", "CustomHead", "head" },
    Torso = { "UpperTorso", "Torso", "LowerTorso" },
    HumanoidRootPart = { "HumanoidRootPart" },
    LeftArm = { "LeftUpperArm", "LeftArm", "Left Arm", "LeftHand" },
    RightArm = { "RightUpperArm", "RightArm", "Right Arm", "RightHand" },
    LeftLeg = { "LeftUpperLeg", "LeftLeg", "Left Leg", "LeftFoot" },
    RightLeg = { "RightUpperLeg", "RightLeg", "Right Leg", "RightFoot" }
}

local VisRayParams = RaycastParams.new()
VisRayParams.FilterType = Enum.RaycastFilterType.Exclude
VisRayParams.IgnoreWater = true

local function CastClear(origin, targetPos, targetChar)
    VisRayParams.FilterDescendantsInstances = { LocalPlayer.Character, Camera }
    local dir = targetPos - origin
    if dir.Magnitude < 0.01 then return true end
    local res = workspace:Raycast(origin, dir, VisRayParams)
    if not res then return true end
    return res.Instance and res.Instance:IsDescendantOf(targetChar)
end

-- Checks that the center AND all 4 outer corners of the part are 100% unoccluded
local function IsPartFullyExposed(part, char)
    Camera = workspace.CurrentCamera
    if not Camera then return false end
    local origin = Camera.CFrame.Position
    local cf = part.CFrame
    local half = part.Size * 0.45

    if not CastClear(origin, cf.Position, char) then
        return false
    end

    local cornerOffsets = {
        Vector3.new( half.X,  half.Y, 0),
        Vector3.new(-half.X,  half.Y, 0),
        Vector3.new( half.X, -half.Y, 0),
        Vector3.new(-half.X, -half.Y, 0)
    }

    for i = 1, 4 do
        local worldPt = cf:PointToWorldSpace(cornerOffsets[i])
        local _, onScreen = Camera:WorldToViewportPoint(worldPt)
        if not onScreen or not CastClear(origin, worldPt, char) then
            return false
        end
    end
    return true
end

-- Returns best multipoint or center on a part
local function ResolveMultipointOnPart(part, char, mousePos, maxFov)
    Camera = workspace.CurrentCamera
    local origin = Camera.CFrame.Position
    local cf = part.CFrame
    local s = part.Size * (Config.MultipointScale * 0.5)

    local points = { cf.Position }
    if Config.Multipoint then
        points[2] = cf:PointToWorldSpace(Vector3.new( s.X,  s.Y, 0))
        points[3] = cf:PointToWorldSpace(Vector3.new(-s.X,  s.Y, 0))
        points[4] = cf:PointToWorldSpace(Vector3.new( s.X, -s.Y, 0))
        points[5] = cf:PointToWorldSpace(Vector3.new(-s.X, -s.Y, 0))
        points[6] = cf:PointToWorldSpace(Vector3.new(0,  s.Y, 0))
        points[7] = cf:PointToWorldSpace(Vector3.new(0, -s.Y, 0))
    end

    local bestPt, bestDist = nil, maxFov
    for i = 1, #points do
        local pt = points[i]
        local scr, onScreen = Camera:WorldToViewportPoint(pt)
        if onScreen then
            local d = (Vector2.new(scr.X, scr.Y) - mousePos).Magnitude
            if d <= bestDist then
                if not Config.WallCheck or CastClear(origin, pt, char) then
                    bestDist = d
                    bestPt = pt
                end
            end
        end
    end
    return bestPt, bestDist
end

local function GetCandidateParts(char)
    local list = {}
    if not char then return list end
    if Config.IgnoreForceField and char:FindFirstChildOfClass("ForceField") then
        return list
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return list end

    for group, enabled in pairs(Config.TargetParts) do
        if enabled and PartMap[group] then
            for _, alias in ipairs(PartMap[group]) do
                local p = char:FindFirstChild(alias, true)
                if p and p:IsA("BasePart") then
                    list[#list + 1] = p
                    break
                end
            end
        end
    end
    return list
end

local CurrentTarget = nil
local CurrentTargetPos = nil
local CurrentTargetFullyExposed = false

local function GetClosestTarget()
    Camera = workspace.CurrentCamera
    if not Camera or not Config.SilentEnabled then return nil, nil, false end
    local bestDist = Config.FOV
    local bestPart, bestPos, bestExposed = nil, nil, false
    local mousePos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and (not Config.TeamCheck or plr.Team ~= LocalPlayer.Team) then
            local char = plr.Character
            local parts = GetCandidateParts(char)
            for i = 1, #parts do
                local part = parts[i]
                local pt, dist = ResolveMultipointOnPart(part, char, mousePos, bestDist)
                if pt and dist then
                    bestDist = dist
                    bestPart = part
                    bestPos = pt
                    if Config.RequireFullExposure then
                        bestExposed = IsPartFullyExposed(part, char)
                    else
                        bestExposed = CastClear(Camera.CFrame.Position, pt, char)
                    end
                end
            end
        end
    end
    return bestPart, bestPos, bestExposed
end

-- [3] Chams & FOV
local ChamsFolder = ProtectInstance(Instance.new("Folder"))
ChamsFolder.Name = RandomStr(10)
ChamsFolder.Parent = SafeContainer

local function ApplyChams(plr)
    if plr == LocalPlayer then return end
    local function OnChar(char)
        task.wait(0.1)
        local old = ChamsFolder:FindFirstChild(plr.Name)
        if old then old:Destroy() end
        local hl = ProtectInstance(Instance.new("Highlight"))
        hl.Name = plr.Name
        hl.Adornee = char
        hl.FillColor = Config.ChamsFill
        hl.OutlineColor = Config.ChamsOutline
        hl.FillTransparency = 0.45
        hl.OutlineTransparency = 0.1
        hl.Enabled = Config.ChamsEnabled
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ChamsFolder
    end
    if plr.Character then task.spawn(OnChar, plr.Character) end
    plr.CharacterAdded:Connect(OnChar)
end

for _, p in ipairs(Players:GetPlayers()) do ApplyChams(p) end
Players.PlayerAdded:Connect(ApplyChams)
Players.PlayerRemoving:Connect(function(p)
    local c = ChamsFolder:FindFirstChild(p.Name)
    if c then c:Destroy() end
end)

local FOVCircle = Drawing.new("Circle")
FOVCircle.Radius = Config.FOV
FOVCircle.Color = Color3.fromRGB(255, 50, 50)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Visible = Config.ShowFOV

-- [4] Liquid Glass UI (DELETE toggle, TopMost DisplayOrder, Interval Slider 10-10000ms)
local ScreenGui = ProtectInstance(Instance.new("ScreenGui"))
ScreenGui.Name = RandomStr(14)
ScreenGui.DisplayOrder = 2147483647
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.Parent = SafeContainer

local MainFrame = ProtectInstance(Instance.new("Frame"))
MainFrame.Size = UDim2.new(0, 390, 0, 520)
MainFrame.Position = UDim2.new(0.5, -195, 0.5, -260)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
MainFrame.BackgroundTransparency = 0.22
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Parent = ScreenGui

local Corner = ProtectInstance(Instance.new("UICorner", MainFrame))
Corner.CornerRadius = UDim.new(0, 14)

local GlassStroke = ProtectInstance(Instance.new("UIStroke", MainFrame))
GlassStroke.Thickness = 1.5
GlassStroke.Color = Color3.fromRGB(255, 255, 255)
GlassStroke.Transparency = 0.62

local GlassGrad = ProtectInstance(Instance.new("UIGradient", MainFrame))
GlassGrad.Rotation = 135
GlassGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(190, 210, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 140, 180))
})

local TopHighlight = ProtectInstance(Instance.new("Frame", MainFrame))
TopHighlight.Size = UDim2.new(1, -20, 0, 1)
TopHighlight.Position = UDim2.new(0, 10, 0, 1)
TopHighlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TopHighlight.BackgroundTransparency = 0.5
TopHighlight.BorderSizePixel = 0

local Header = ProtectInstance(Instance.new("TextLabel", MainFrame))
Header.Size = UDim2.new(1, -24, 0, 36)
Header.Position = UDim2.new(0, 12, 0, 6)
Header.BackgroundTransparency = 1
Header.Text = "LIQUID GLASS // 01 RAYCAST SILENT"
Header.TextColor3 = Color3.fromRGB(245, 248, 255)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextXAlignment = Enum.TextXAlignment.Left

local SubHeader = ProtectInstance(Instance.new("TextLabel", MainFrame))
SubHeader.Size = UDim2.new(1, -24, 0, 16)
SubHeader.Position = UDim2.new(0, 12, 0, 26)
SubHeader.BackgroundTransparency = 1
SubHeader.Text = "[DELETE] Menu | [F] Autofire: OFF"
SubHeader.TextColor3 = Color3.fromRGB(255, 110, 110)
SubHeader.Font = Enum.Font.GothamMedium
SubHeader.TextSize = 11
SubHeader.TextXAlignment = Enum.TextXAlignment.Left

local Scroll = ProtectInstance(Instance.new("ScrollingFrame", MainFrame))
Scroll.Size = UDim2.new(1, -20, 1, -56)
Scroll.Position = UDim2.new(0, 10, 0, 48)
Scroll.BackgroundTransparency = 1
Scroll.BorderSizePixel = 0
Scroll.ScrollBarThickness = 3
Scroll.CanvasSize = UDim2.new(0, 0, 0, 680)

local ListLayout = ProtectInstance(Instance.new("UIListLayout", Scroll))
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- Dragging logic
do
    local dragging, dragStart, startPos
    MainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = false
        end
    end)
end

local function RefreshStatusText()
    SubHeader.Text = string.format("[%s] Menu | [%s] Autofire: %s", Config.MenuKey.Name, Config.AutoFireKey.Name, Config.AutoFire and "ON" or "OFF")
    SubHeader.TextColor3 = Config.AutoFire and Color3.fromRGB(110, 255, 150) or Color3.fromRGB(255, 110, 110)
end

local function CreateToggle(name, default, callback)
    local row = ProtectInstance(Instance.new("TextButton", Scroll))
    row.Size = UDim2.new(1, -8, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
    row.BackgroundTransparency = 0.35
    row.Text = ""
    row.AutoButtonColor = false
    ProtectInstance(Instance.new("UICorner", row)).CornerRadius = UDim.new(0, 8)
    local st = ProtectInstance(Instance.new("UIStroke", row))
    st.Color = Color3.fromRGB(255, 255, 255)
    st.Transparency = 0.82

    local lbl = ProtectInstance(Instance.new("TextLabel", row))
    lbl.Size = UDim2.new(1, -60, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = name
    lbl.TextColor3 = Color3.fromRGB(235, 240, 255)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local ind = ProtectInstance(Instance.new("Frame", row))
    ind.Size = UDim2.new(0, 34, 0, 16)
    ind.Position = UDim2.new(1, -44, 0.5, -8)
    ind.BackgroundColor3 = default and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(60, 65, 80)
    ProtectInstance(Instance.new("UICorner", ind)).CornerRadius = UDim.new(1, 0)

    local state = default
    local function SetState(v)
        state = v
        ind.BackgroundColor3 = state and Color3.fromRGB(255, 70, 70) or Color3.fromRGB(60, 65, 80)
        callback(state)
    end
    row.MouseButton1Click:Connect(function()
        SetState(not state)
    end)
    return SetState
end

local function CreateSlider(name, minVal, maxVal, default, suffix, callback)
    local box = ProtectInstance(Instance.new("Frame", Scroll))
    box.Size = UDim2.new(1, -8, 0, 44)
    box.BackgroundColor3 = Color3.fromRGB(32, 36, 48)
    box.BackgroundTransparency = 0.35
    ProtectInstance(Instance.new("UICorner", box)).CornerRadius = UDim.new(0, 8)
    local st = ProtectInstance(Instance.new("UIStroke", box))
    st.Color = Color3.fromRGB(255, 255, 255)
    st.Transparency = 0.82

    local lbl = ProtectInstance(Instance.new("TextLabel", box))
    lbl.Size = UDim2.new(1, -20, 0, 20)
    lbl.Position = UDim2.new(0, 10, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = string.format("%s: %d%s", name, default, suffix or "")
    lbl.TextColor3 = Color3.fromRGB(235, 240, 255)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local bar = ProtectInstance(Instance.new("Frame", box))
    bar.Size = UDim2.new(1, -20, 0, 8)
    bar.Position = UDim2.new(0, 10, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
    ProtectInstance(Instance.new("UICorner", bar)).CornerRadius = UDim.new(1, 0)

    local fill = ProtectInstance(Instance.new("Frame", bar))
    local initRatio = (default - minVal) / (maxVal - minVal)
    fill.Size = UDim2.new(initRatio, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
    ProtectInstance(Instance.new("UICorner", fill)).CornerRadius = UDim.new(1, 0)

    local sliding = false
    local function UpdateFromInput(input)
        local rel = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = math.floor(minVal + (maxVal - minVal) * rel + 0.5)
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = string.format("%s: %d%s", name, val, suffix or "")
        callback(val)
    end
    bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = true
            UpdateFromInput(input)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            UpdateFromInput(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = false
        end
    end)
end

local WaitingBind = false
local BindBtn = ProtectInstance(Instance.new("TextButton", Scroll))
BindBtn.Size = UDim2.new(1, -8, 0, 30)
BindBtn.BackgroundColor3 = Color3.fromRGB(40, 46, 64)
BindBtn.BackgroundTransparency = 0.3
BindBtn.Text = "Autofire Toggle Bind: [ F ] (Click to Change)"
BindBtn.TextColor3 = Color3.fromRGB(255, 220, 140)
BindBtn.Font = Enum.Font.GothamBold
BindBtn.TextSize = 12
ProtectInstance(Instance.new("UICorner", BindBtn)).CornerRadius = UDim.new(0, 8)
BindBtn.MouseButton1Click:Connect(function()
    WaitingBind = true
    BindBtn.Text = "Press any key for Autofire Bind..."
end)

local SetAutoFireUI = CreateToggle("Autofire (Full-Exposure + FOV)", Config.AutoFire, function(v)
    Config.AutoFire = v
    RefreshStatusText()
end)
CreateToggle("Require 100% Full Part Exposure", Config.RequireFullExposure, function(v) Config.RequireFullExposure = v end)
CreateSlider("Autofire Click Interval", 10, 10000, Config.FireInterval, " ms", function(v) Config.FireInterval = v end)
CreateToggle("Silent Aim Enabled", Config.SilentEnabled, function(v) Config.SilentEnabled = v end)
CreateSlider("Aim FOV Radius", 20, 600, Config.FOV, " px", function(v) Config.FOV = v; FOVCircle.Radius = v end)
CreateSlider("HitChance", 1, 100, Config.HitChance, "%", function(v) Config.HitChance = v end)
CreateToggle("Multipoint Scanning", Config.Multipoint, function(v) Config.Multipoint = v end)
CreateSlider("Multipoint Scale", 20, 95, math.floor(Config.MultipointScale * 100), "%", function(v) Config.MultipointScale = v / 100 end)
CreateToggle("WallCheck (Visible Only)", Config.WallCheck, function(v) Config.WallCheck = v end)
CreateToggle("TeamCheck", Config.TeamCheck, function(v) Config.TeamCheck = v end)
CreateToggle("Ignore ForceField", Config.IgnoreForceField, function(v) Config.IgnoreForceField = v end)
CreateToggle("Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v; FOVCircle.Visible = v end)
CreateToggle("Chams ESP", Config.ChamsEnabled, function(v)
    Config.ChamsEnabled = v
    for _, c in ipairs(ChamsFolder:GetChildren()) do
        if c:IsA("Highlight") then c.Enabled = v end
    end
end)

for _, bone in ipairs({ "Head", "Torso", "HumanoidRootPart", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }) do
    CreateToggle("Target Bone: " .. bone, Config.TargetParts[bone], function(v)
        Config.TargetParts[bone] = v
    end)
end

Scroll.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 20)

UserInputService.InputBegan:Connect(function(input, gp)
    if WaitingBind and input.UserInputType == Enum.UserInputType.Keyboard then
        WaitingBind = false
        Config.AutoFireKey = input.KeyCode
        BindBtn.Text = "Autofire Toggle Bind: [ " .. input.KeyCode.Name .. " ] (Click to Change)"
        RefreshStatusText()
        return
    end
    if input.KeyCode == Config.MenuKey then
        ScreenGui.Enabled = not ScreenGui.Enabled
        return
    end
    if not gp and input.KeyCode == Config.AutoFireKey then
        SetAutoFireUI(not Config.AutoFire)
    end
end)

-- [5] RenderStepped Target Sync + Zero-Miss Autofire Loop
local LastShotClock = 0
local IsClicking = false

local function TriggerMouseClick()
    if mouse1press and mouse1release then
        mouse1press()
        task.wait(0.01)
        mouse1release()
    end
end

RunService.RenderStepped:Connect(function()
    FOVCircle.Position = UserInputService:GetMouseLocation()
    CurrentTarget, CurrentTargetPos, CurrentTargetFullyExposed = GetClosestTarget()

    if Config.AutoFire and not IsClicking and not ScreenGui.Enabled then
        if CurrentTarget and CurrentTargetPos and CurrentTargetFullyExposed then
            local now = os.clock() * 1000
            if (now - LastShotClock) >= Config.FireInterval then
                if math.random(1, 100) <= Config.HitChance then
                    LastShotClock = now
                    IsClicking = true
                    task.spawn(function()
                        TriggerMouseClick()
                        IsClicking = false
                    end)
                end
            end
        end
    end
end)

-- [6] Metamethod Hook (__namecall Raycast / Spherecast + GUI Spoof)
local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if not checkcaller() then
        if (method == "FindFirstChild" or method == "FindFirstChildOfClass") and (self == CoreGui or self == SafeContainer) then
            local res = oldNamecall(self, ...)
            if res and ProtectedInstances[res] then return nil end
            return res
        end
        if self == workspace and Config.SilentEnabled and CurrentTarget and CurrentTargetPos then
            if math.random(1, 100) <= Config.HitChance then
                local args = { ... }
                if method == "Raycast" then
                    local origin = args[1]
                    local dir = args[2]
                    if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                        local mag = math.max(dir.Magnitude, (CurrentTargetPos - origin).Magnitude + 15)
                        args[2] = (CurrentTargetPos - origin).Unit * mag
                        return oldNamecall(self, unpack(args))
                    end
                elseif method == "Spherecast" then
                    local origin = args[1]
                    local dir = args[3]
                    if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                        local mag = math.max(dir.Magnitude, (CurrentTargetPos - origin).Magnitude + 15)
                        args[3] = (CurrentTargetPos - origin).Unit * mag
                        return oldNamecall(self, unpack(args))
                    end
                end
            end
        end
    end
    return oldNamecall(self, ...)
end))
