-- 03_mouse_index_silent.lua
-- Method: __index hook on PlayerMouse (Hit, Target, UnitRay, X, Y) + Auto Weapon Ballistics + Deep TeamCheck + Liquid Glass UI

local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local ScriptContext = cloneref(game:GetService("ScriptContext"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))
local Teams = cloneref(game:GetService("Teams"))

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local Config = {
    SilentEnabled = true,
    FOV = 180,
    ShowFOV = true,
    HitChance = 100,
    TeamCheck = false,
    ESPTeamCheck = true,
    IgnoreForceField = true,
    WallCheck = true,
    Multipoint = true,
    MultipointScale = 0.72,
    PredictionEnabled = true,
    PredictionMultiplier = 1.0,
    AutoBallistics = true,
    DefaultBulletSpeed = 1200,
    DefaultBulletGravity = 196.2,
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
    FireInterval = 85,
    RequireFullExposure = true,
    ChamsEnabled = true,
    ChamsFill = Color3.fromRGB(0, 170, 255),
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

-- Deep Team & Enemy Identification Engine
local TeamAttributes = { "Team", "TeamName", "Faction", "Side", "Squad", "Clan", "Group", "TeamId", "TeamColor" }

local function ExtractCustomTeam(plr)
    if not plr then return nil end
    for i = 1, #TeamAttributes do
        local val = plr:GetAttribute(TeamAttributes[i])
        if val ~= nil and val ~= "" and val ~= "None" and val ~= "Neutral" then return tostring(val) end
    end
    local char = plr.Character
    if char then
        for i = 1, #TeamAttributes do
            local val = char:GetAttribute(TeamAttributes[i])
            if val ~= nil and val ~= "" and val ~= "None" and val ~= "Neutral" then return tostring(val) end
        end
        if char.Parent and char.Parent ~= workspace and char.Parent.Name ~= "Characters" and char.Parent.Name ~= "Players" then
            return "Folder_" .. char.Parent.Name
        end
    end
    local ls = plr:FindFirstChild("leaderstats")
    local st = plr:FindFirstChild("Stats") or plr:FindFirstChild("Data")
    for _, folder in ipairs({ ls, st, plr, char }) do
        if folder then
            for i = 1, #TeamAttributes do
                local obj = folder:FindFirstChild(TeamAttributes[i])
                if obj and obj:IsA("ValueBase") and obj.Value ~= nil and tostring(obj.Value) ~= "" then
                    return tostring(obj.Value)
                end
            end
        end
    end
    return nil
end

local function IsEnemy(plr)
    if not plr or plr == LocalPlayer then return false end
    if #Teams:GetTeams() > 0 then
        if not (plr.Neutral and LocalPlayer.Neutral) and plr.Team ~= nil and LocalPlayer.Team ~= nil then
            return plr.Team ~= LocalPlayer.Team
        end
    end
    if plr.TeamColor and LocalPlayer.TeamColor and not plr.Neutral and not LocalPlayer.Neutral then
        return plr.TeamColor ~= LocalPlayer.TeamColor
    end
    local myCustom = ExtractCustomTeam(LocalPlayer)
    local theirCustom = ExtractCustomTeam(plr)
    if myCustom and theirCustom then return myCustom ~= theirCustom end
    return true
end

-- Auto Weapon Ballistics Inspector
local SpeedKeys = { "BulletSpeed", "MuzzleVelocity", "Velocity", "Speed", "ProjectileSpeed", "travelSpeed", "bulletSpeed", "muzzleVelocity", "FireSpeed", "v0" }
local GravityKeys = { "BulletDrop", "Gravity", "Drop", "BulletGravity", "ProjectileGravity", "gravity", "bulletDrop", "Acceleration" }
local LiveWeaponData = { Speed = 0, Gravity = 0, IsBallistic = false, WeaponName = "Hitscan" }

local function ScanTableForBallistics(tbl, depth)
    if depth > 3 or type(tbl) ~= "table" then return nil, nil end
    local foundSpeed, foundGrav = nil, nil
    for i = 1, #SpeedKeys do
        local v = rawget(tbl, SpeedKeys[i])
        if type(v) == "number" and v > 25 and v < 30000 then foundSpeed = v; break end
    end
    for i = 1, #GravityKeys do
        local v = rawget(tbl, GravityKeys[i])
        if type(v) == "number" and v >= 0 and v < 5000 then foundGrav = v; break
        elseif typeof(v) == "Vector3" and v.Y < 0 then foundGrav = math.abs(v.Y); break end
    end
    if not foundSpeed then
        for k, v in pairs(tbl) do
            if type(v) == "table" and (k == "Setting" or k == "Settings" or k == "Config" or k == "Ballistics" or k == "Stats") then
                local s, g = ScanTableForBallistics(v, depth + 1)
                if s then foundSpeed = s; foundGrav = g; break end
            end
        end
    end
    return foundSpeed, foundGrav
end

local function InspectInstanceBallistics(inst)
    if not inst then return nil, nil end
    local s, g = nil, nil
    for i = 1, #SpeedKeys do
        local attr = inst:GetAttribute(SpeedKeys[i])
        if type(attr) == "number" and attr > 25 then s = attr; break end
        local valObj = inst:FindFirstChild(SpeedKeys[i], true)
        if valObj and valObj:IsA("NumberValue") and valObj.Value > 25 then s = valObj.Value; break end
    end
    for i = 1, #GravityKeys do
        local attr = inst:GetAttribute(GravityKeys[i])
        if type(attr) == "number" and attr >= 0 then g = attr; break end
        local valObj = inst:FindFirstChild(GravityKeys[i], true)
        if valObj and valObj:IsA("NumberValue") and valObj.Value >= 0 then g = valObj.Value; break end
    end
    if not s then
        for _, mod in ipairs(inst:GetDescendants()) do
            if mod:IsA("ModuleScript") then
                local ok, req = pcall(require, mod)
                if ok and type(req) == "table" then
                    local ms, mg = ScanTableForBallistics(req, 1)
                    if ms then s = ms; g = mg; break end
                end
            end
        end
    end
    return s, g
end

local function UpdateWeaponBallistics()
    if not Config.AutoBallistics then return end
    local char = LocalPlayer.Character
    local cam = workspace.CurrentCamera
    local s, g, wName = nil, nil, nil
    if char then
        local tool = char:FindFirstChildOfClass("Tool") or char:FindFirstChildOfClass("Model")
        if tool then
            s, g = InspectInstanceBallistics(tool)
            if s then wName = tool.Name end
        end
    end
    if not s and cam then
        for _, child in ipairs(cam:GetChildren()) do
            if child:IsA("Model") or child:IsA("Folder") then
                local ms, mg = InspectInstanceBallistics(child)
                if ms then s, g, wName = ms, mg, child.Name; break end
            end
        end
    end
    if not s and getgc then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" and (rawget(v, "Equipped") == true or rawget(v, "CurrentWeapon")) then
                    local sub = rawget(v, "CurrentWeapon") or v
                    local ms, mg = ScanTableForBallistics(sub, 1)
                    if ms then s, g, wName = ms, mg, "CustomGC"; break end
                end
            end
        end)
    end
    if s and s > 25 then
        LiveWeaponData.Speed = s
        LiveWeaponData.Gravity = g or workspace.Gravity
        LiveWeaponData.IsBallistic = true
        LiveWeaponData.WeaponName = wName or "Detected"
    else
        LiveWeaponData.Speed = 0
        LiveWeaponData.Gravity = 0
        LiveWeaponData.IsBallistic = false
        LiveWeaponData.WeaponName = "Hitscan"
    end
end

task.spawn(function()
    while task.wait(1.2) do pcall(UpdateWeaponBallistics) end
end)

local VelocityHistory = setmetatable({}, { __mode = "k" })

local function GetSmoothedVelocity(part, char)
    if not part then return Vector3.zero, Vector3.zero end
    local root = (char and char:FindFirstChild("HumanoidRootPart")) or part
    local now = os.clock()
    local data = VelocityHistory[char or part]
    local rawVel = root.AssemblyLinearVelocity or root.Velocity or Vector3.zero

    if not data then
        VelocityHistory[char or part] = { LastPos = root.Position, LastTime = now, SmoothedVel = rawVel, SmoothedAcc = Vector3.zero }
        return rawVel, Vector3.zero
    end

    local dt = now - data.LastTime
    if dt > 0.003 and dt < 0.5 then
        local deltaVel = (root.Position - data.LastPos) / dt
        local newVel = data.SmoothedVel:Lerp(rawVel:Lerp(deltaVel, 0.45), 0.38)
        local acc = (newVel - data.SmoothedVel) / dt
        data.SmoothedAcc = data.SmoothedAcc:Lerp(Vector3.new(acc.X, 0, acc.Z), 0.25)
        data.SmoothedVel = newVel
        data.LastPos = root.Position
        data.LastTime = now
    elseif dt >= 0.5 then
        data.LastPos = root.Position
        data.LastTime = now
        data.SmoothedVel = rawVel
        data.SmoothedAcc = Vector3.zero
    end
    return data.SmoothedVel, data.SmoothedAcc
end

local function ComputePredictedPosition(origin, baseTargetPos, targetPart)
    if not Config.PredictionEnabled or not targetPart then return baseTargetPos end
    local vel, acc = GetSmoothedVelocity(targetPart, targetPart.Parent)
    if vel.Magnitude < 0.2 then return baseTargetPos end

    local mult = Config.PredictionMultiplier
    local dist = (baseTargetPos - origin).Magnitude
    local speed = LiveWeaponData.Speed
    local grav = LiveWeaponData.Gravity

    if Config.AutoBallistics and LiveWeaponData.IsBallistic and speed > 25 then
        local t = dist / speed
        local projPos = baseTargetPos + (vel * t) + (0.5 * acc * (t * t) * 0.25)
        t = (projPos - origin).Magnitude / speed
        local scaledT = t * mult
        local leadOffset = (vel * scaledT) + (0.5 * acc * (scaledT * scaledT) * 0.2)
        local dropHeight = 0.5 * grav * (t * t) * mult
        return baseTargetPos + leadOffset + Vector3.new(0, dropHeight, 0)
    else
        return baseTargetPos + (vel * (0.042 * mult))
    end
end

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

local function IsPartFullyExposed(part, char)
    Camera = workspace.CurrentCamera
    if not Camera then return false end
    local origin = Camera.CFrame.Position
    local cf = part.CFrame
    local half = part.Size * 0.45

    if not CastClear(origin, cf.Position, char) then return false end

    local cornerOffsets = {
        Vector3.new( half.X,  half.Y, 0),
        Vector3.new(-half.X,  half.Y, 0),
        Vector3.new( half.X, -half.Y, 0),
        Vector3.new(-half.X, -half.Y, 0)
    }

    for i = 1, 4 do
        local worldPt = cf:PointToWorldSpace(cornerOffsets[i])
        local _, onScreen = Camera:WorldToViewportPoint(worldPt)
        if not onScreen or not CastClear(origin, worldPt, char) then return false end
    end
    return true
end

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
    if Config.IgnoreForceField and char:FindFirstChildOfClass("ForceField") then return list end
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
        if plr ~= LocalPlayer and (not Config.TeamCheck or IsEnemy(plr)) then
            local char = plr.Character
            if char then
                GetSmoothedVelocity(char:FindFirstChild("HumanoidRootPart"), char)
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
    end

    if bestPart and bestPos then
        bestPos = ComputePredictedPosition(Camera.CFrame.Position, bestPos, bestPart)
    end
    return bestPart, bestPos, bestExposed
end

local ChamsFolder = ProtectInstance(Instance.new("Folder"))
ChamsFolder.Name = RandomStr(10)
ChamsFolder.Parent = SafeContainer
local PlayerHighlights = {}

local function RefreshAllChams()
    for plr, hl in pairs(PlayerHighlights) do
        if plr and plr.Parent and hl and hl.Parent then
            local enemy = IsEnemy(plr)
            if not Config.ChamsEnabled then
                hl.Enabled = false
            elseif Config.ESPTeamCheck then
                hl.Enabled = enemy
                hl.FillColor = Color3.fromRGB(255, 40, 40)
                hl.OutlineColor = Color3.fromRGB(255, 255, 255)
            else
                hl.Enabled = true
                hl.FillColor = enemy and Color3.fromRGB(255, 40, 40) or Config.ChamsFill
                hl.OutlineColor = Config.ChamsOutline
            end
        end
    end
end

local function ApplyChams(plr)
    if plr == LocalPlayer then return end
    local function OnChar(char)
        task.wait(0.1)
        local old = ChamsFolder:FindFirstChild(plr.Name)
        if old then old:Destroy() end
        local hl = ProtectInstance(Instance.new("Highlight"))
        hl.Name = plr.Name
        hl.Adornee = char
        hl.FillColor = Color3.fromRGB(255, 40, 40)
        hl.OutlineColor = Config.ChamsOutline
        hl.FillTransparency = 0.45
        hl.OutlineTransparency = 0.1
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ChamsFolder
        PlayerHighlights[plr] = hl
        RefreshAllChams()
    end
    if plr.Character then task.spawn(OnChar, plr.Character) end
    plr.CharacterAdded:Connect(OnChar)
    plr:GetPropertyChangedSignal("Team"):Connect(RefreshAllChams)
    plr:GetPropertyChangedSignal("TeamColor"):Connect(RefreshAllChams)
end

for _, p in ipairs(Players:GetPlayers()) do ApplyChams(p) end
Players.PlayerAdded:Connect(ApplyChams)
Players.PlayerRemoving:Connect(function(p)
    PlayerHighlights[p] = nil
    local c = ChamsFolder:FindFirstChild(p.Name)
    if c then c:Destroy() end
end)
LocalPlayer:GetPropertyChangedSignal("Team"):Connect(RefreshAllChams)
LocalPlayer:GetPropertyChangedSignal("TeamColor"):Connect(RefreshAllChams)

local FOVCircle = Drawing.new("Circle")
FOVCircle.Radius = Config.FOV
FOVCircle.Color = Color3.fromRGB(0, 170, 255)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Visible = Config.ShowFOV

-- Liquid Glass UI
local ScreenGui = ProtectInstance(Instance.new("ScreenGui"))
ScreenGui.Name = RandomStr(14)
ScreenGui.DisplayOrder = 2147483647
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.Parent = SafeContainer

local MainFrame = ProtectInstance(Instance.new("Frame", ScreenGui))
MainFrame.Size = UDim2.new(0, 395, 0, 540)
MainFrame.Position = UDim2.new(0.5, -197, 0.5, -270)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
MainFrame.BackgroundTransparency = 0.22
MainFrame.BorderSizePixel = 0
MainFrame.Active = true

ProtectInstance(Instance.new("UICorner", MainFrame)).CornerRadius = UDim.new(0, 14)
local GlassStroke = ProtectInstance(Instance.new("UIStroke", MainFrame))
GlassStroke.Thickness = 1.5
GlassStroke.Color = Color3.fromRGB(140, 210, 255)
GlassStroke.Transparency = 0.62

local GlassGrad = ProtectInstance(Instance.new("UIGradient", MainFrame))
GlassGrad.Rotation = 135
GlassGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 220, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 140, 190))
})

local TopBanner = ProtectInstance(Instance.new("Frame", MainFrame))
TopBanner.Size = UDim2.new(1, 0, 0, 44)
TopBanner.BackgroundTransparency = 1
TopBanner.Active = true

local Header = ProtectInstance(Instance.new("TextLabel", TopBanner))
Header.Size = UDim2.new(1, -24, 0, 24)
Header.Position = UDim2.new(0, 12, 0, 6)
Header.BackgroundTransparency = 1
Header.Text = "LIQUID GLASS // 03 MOUSE INDEX SILENT"
Header.TextColor3 = Color3.fromRGB(240, 248, 255)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextXAlignment = Enum.TextXAlignment.Left

local SubHeader = ProtectInstance(Instance.new("TextLabel", TopBanner))
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
Scroll.CanvasSize = UDim2.new(0, 0, 0, 860)

local ListLayout = ProtectInstance(Instance.new("UIListLayout", Scroll))
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local AnySliderDragging = false

do
    local dragging, dragStart, startPos
    TopBanner.InputBegan:Connect(function(input)
        if not AnySliderDragging and input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and not AnySliderDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
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
    SubHeader.Text = string.format("[%s] Menu | [%s] Autofire: %s | Gun: %s", Config.MenuKey.Name, Config.AutoFireKey.Name, Config.AutoFire and "ON" or "OFF", LiveWeaponData.WeaponName)
    SubHeader.TextColor3 = Config.AutoFire and Color3.fromRGB(0, 195, 255) or Color3.fromRGB(255, 110, 110)
end

local function CreateToggle(name, default, callback)
    local row = ProtectInstance(Instance.new("TextButton", Scroll))
    row.Size = UDim2.new(1, -8, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(26, 34, 48)
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
    lbl.TextColor3 = Color3.fromRGB(235, 245, 255)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local ind = ProtectInstance(Instance.new("Frame", row))
    ind.Size = UDim2.new(0, 34, 0, 16)
    ind.Position = UDim2.new(1, -44, 0.5, -8)
    ind.BackgroundColor3 = default and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(55, 65, 80)
    ProtectInstance(Instance.new("UICorner", ind)).CornerRadius = UDim.new(1, 0)

    local state = default
    local function SetState(v)
        state = v
        ind.BackgroundColor3 = state and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(55, 65, 80)
        callback(state)
    end
    row.MouseButton1Click:Connect(function()
        SetState(not state)
    end)
    return SetState
end

local function CreateSlider(name, minVal, maxVal, default, suffix, decimals, callback)
    local box = ProtectInstance(Instance.new("Frame", Scroll))
    box.Size = UDim2.new(1, -8, 0, 46)
    box.BackgroundColor3 = Color3.fromRGB(26, 34, 48)
    box.BackgroundTransparency = 0.35
    box.Active = true
    ProtectInstance(Instance.new("UICorner", box)).CornerRadius = UDim.new(0, 8)
    local st = ProtectInstance(Instance.new("UIStroke", box))
    st.Color = Color3.fromRGB(255, 255, 255)
    st.Transparency = 0.82

    local fmt = decimals and decimals > 0 and ("%s: %." .. tostring(decimals) .. "f%s") or "%s: %d%s"

    local lbl = ProtectInstance(Instance.new("TextLabel", box))
    lbl.Size = UDim2.new(1, -20, 0, 20)
    lbl.Position = UDim2.new(0, 10, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = string.format(fmt, name, default, suffix or "")
    lbl.TextColor3 = Color3.fromRGB(235, 245, 255)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local bar = ProtectInstance(Instance.new("Frame", box))
    bar.Size = UDim2.new(1, -20, 0, 8)
    bar.Position = UDim2.new(0, 10, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(45, 55, 70)
    ProtectInstance(Instance.new("UICorner", bar)).CornerRadius = UDim.new(1, 0)

    local fill = ProtectInstance(Instance.new("Frame", bar))
    fill.Size = UDim2.new(math.clamp((default - minVal) / (maxVal - minVal), 0, 1), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
    ProtectInstance(Instance.new("UICorner", fill)).CornerRadius = UDim.new(1, 0)

    local hitBtn = ProtectInstance(Instance.new("TextButton", box))
    hitBtn.Size = UDim2.new(1, 0, 1, 0)
    hitBtn.BackgroundTransparency = 1
    hitBtn.Text = ""
    hitBtn.AutoButtonColor = false
    hitBtn.ZIndex = 10

    local sliding = false
    local function UpdateFromX(absX)
        local rel = math.clamp((absX - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local raw = minVal + (maxVal - minVal) * rel
        local val
        if decimals and decimals > 0 then
            local mult = 10 ^ decimals
            val = math.floor(raw * mult + 0.5) / mult
        else
            val = math.floor(raw + 0.5)
        end
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = string.format(fmt, name, val, suffix or "")
        callback(val)
    end

    hitBtn.MouseButton1Down:Connect(function(x)
        sliding = true
        AnySliderDragging = true
        Scroll.ScrollingEnabled = false
        UpdateFromX(x)
    end)
    hitBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true
            AnySliderDragging = true
            Scroll.ScrollingEnabled = false
            UpdateFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            UpdateFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            if sliding then
                sliding = false
                AnySliderDragging = false
                Scroll.ScrollingEnabled = true
            end
        end
    end)
end

local WaitingBind = false
local BindBtn = ProtectInstance(Instance.new("TextButton", Scroll))
BindBtn.Size = UDim2.new(1, -8, 0, 30)
BindBtn.BackgroundColor3 = Color3.fromRGB(36, 48, 68)
BindBtn.BackgroundTransparency = 0.3
BindBtn.Text = "Autofire Toggle Bind: [ F ] (Click to Change)"
BindBtn.TextColor3 = Color3.fromRGB(130, 220, 255)
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
CreateSlider("Autofire Click Interval", 10, 10000, Config.FireInterval, " ms", 0, function(v) Config.FireInterval = v end)
CreateToggle("Silent Aim Enabled", Config.SilentEnabled, function(v) Config.SilentEnabled = v end)
CreateToggle("Smart Prediction Enabled", Config.PredictionEnabled, function(v) Config.PredictionEnabled = v end)
CreateSlider("Prediction Scale (0.10 - 10)", 0.10, 10.00, Config.PredictionMultiplier, "x", 2, function(v) Config.PredictionMultiplier = v end)
CreateToggle("Auto Weapon Ballistics Inspector", Config.AutoBallistics, function(v) Config.AutoBallistics = v; task.spawn(UpdateWeaponBallistics) end)
CreateSlider("Aim FOV Radius", 20, 600, Config.FOV, " px", 0, function(v) Config.FOV = v; FOVCircle.Radius = v end)
CreateSlider("HitChance", 1, 100, Config.HitChance, "%", 0, function(v) Config.HitChance = v end)
CreateToggle("Multipoint Scanning", Config.Multipoint, function(v) Config.Multipoint = v end)
CreateSlider("Multipoint Scale", 20, 95, math.floor(Config.MultipointScale * 100), "%", 0, function(v) Config.MultipointScale = v / 100 end)
CreateToggle("WallCheck (Visible Only)", Config.WallCheck, function(v) Config.WallCheck = v end)
CreateToggle("Aim TeamCheck (Enemies Only)", Config.TeamCheck, function(v) Config.TeamCheck = v end)
CreateToggle("ESP TeamCheck (Red Enemies Only)", Config.ESPTeamCheck, function(v) Config.ESPTeamCheck = v; RefreshAllChams() end)
CreateToggle("Ignore ForceField", Config.IgnoreForceField, function(v) Config.IgnoreForceField = v end)
CreateToggle("Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v; FOVCircle.Visible = v end)
CreateToggle("Chams ESP", Config.ChamsEnabled, function(v)
    Config.ChamsEnabled = v
    RefreshAllChams()
end)

for _, bone in ipairs({ "Head", "Torso", "HumanoidRootPart", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }) do
    CreateToggle("Target Bone: " .. bone, Config.TargetParts[bone], function(v)
        Config.TargetParts[bone] = v
    end)
end

Scroll.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 24)

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

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
    if not checkcaller() and self == Mouse and Config.SilentEnabled and CurrentTarget and CurrentTargetPos then
        if math.random(1, 100) <= Config.HitChance then
            if key == "Hit" then
                return CFrame.new(CurrentTargetPos)
            elseif key == "Target" then
                return CurrentTarget
            elseif key == "UnitRay" then
                local origin = Camera.CFrame.Position
                return Ray.new(origin, (CurrentTargetPos - origin).Unit)
            elseif key == "X" then
                local pos = Camera:WorldToViewportPoint(CurrentTargetPos)
                return pos.X
            elseif key == "Y" then
                local pos = Camera:WorldToViewportPoint(CurrentTargetPos)
                return pos.Y
            end
        end
    end
    return oldIndex(self, key)
end))
