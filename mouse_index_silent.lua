-- 03_mouse_index_silent.lua
-- Method: __index hook on PlayerMouse (Hit, Target, UnitRay, X, Y) + Smart Ballistic Prediction + Deep ESP TeamCheck + Liquid Glass UI

local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local ScriptContext = cloneref(game:GetService("ScriptContext"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))
local Stats = cloneref(game:GetService("Stats"))

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local Config = {
    SilentEnabled = true,
    FOV = 180,
    ShowFOV = true,
    HitChance = 100,
    PredictionEnabled = true,
    PredictionScale = 1.00, -- Slider: 0.10 to 10.00
    AutoBallistics = true,
    TeamCheck = true,
    ESPTeamCheck = true,
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
    FireInterval = 85,
    RequireFullExposure = true,
    ChamsEnabled = true,
    ChamsFill = Color3.fromRGB(0, 170, 255),
    EnemyChamsFill = Color3.fromRGB(255, 35, 35),
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
                    if conn.Disable then conn:Disable() end
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
                    if type(det) == "function" and islclosure(det) and (not isexecutorclosure or not isexecutorclosure(det)) then
                        hookfunction(det, newcclosure(function() return true end))
                    end
                    if type(kill) == "function" and islclosure(kill) and (not isexecutorclosure or not isexecutorclosure(kill)) then
                        hookfunction(kill, newcclosure(function() return nil end))
                    end
                    local anti = rawget(v, "Anti")
                    if type(anti) == "table" and rawget(v, "Variables") and rawget(v, "Process") then
                        for _, func in pairs(anti) do
                            if type(func) == "function" and islclosure(func) and (not isexecutorclosure or not isexecutorclosure(func)) then
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

-- Deep Team / Faction Resolver
local TeamKeys = { "Team", "TeamName", "Faction", "Side", "Squad", "TeamId", "Group", "Allegiance" }

local function ExtractFactionId(plr)
    if not plr then return nil end
    if plr.Team ~= nil and not plr.Neutral then
        return "T_" .. tostring(plr.Team.Name)
    end
    if plr.TeamColor ~= nil and not plr.Neutral then
        return "TC_" .. tostring(plr.TeamColor.Name)
    end
    for i = 1, #TeamKeys do
        local k = TeamKeys[i]
        local attr = plr:GetAttribute(k)
        if attr ~= nil and attr ~= "" and attr ~= "None" then
            return "A_" .. tostring(attr)
        end
        local char = plr.Character
        if char then
            local cAttr = char:GetAttribute(k)
            if cAttr ~= nil and cAttr ~= "" and cAttr ~= "None" then
                return "CA_" .. tostring(cAttr)
            end
        end
    end
    for _, folderName in ipairs({ "leaderstats", "Data", "Stats", "Status", "PlayerData" }) do
        local f = plr:FindFirstChild(folderName)
        if f then
            for i = 1, #TeamKeys do
                local valObj = f:FindFirstChild(TeamKeys[i])
                if valObj and valObj:IsA("ValueBase") and valObj.Value ~= nil and tostring(valObj.Value) ~= "" then
                    return "V_" .. tostring(valObj.Value)
                end
            end
        end
    end
    local char = plr.Character
    if char then
        for i = 1, #TeamKeys do
            local valObj = char:FindFirstChild(TeamKeys[i])
            if valObj and valObj:IsA("ValueBase") and valObj.Value ~= nil then
                return "CV_" .. tostring(valObj.Value)
            end
        end
        if char.Parent and char.Parent ~= workspace and char.Parent.Name ~= "Characters" and char.Parent.Name ~= "Players" then
            return "P_" .. char.Parent.Name
        end
    end
    return nil
end

local function IsEnemy(plr)
    if not plr or plr == LocalPlayer then return false end
    local myFaction = ExtractFactionId(LocalPlayer)
    local theirFaction = ExtractFactionId(plr)
    if myFaction and theirFaction then
        return myFaction ~= theirFaction
    end
    return true
end

-- Deep Weapon & Custom Inventory Ballistics Scanner
local CachedBallistics = {
    LastScan = 0,
    ToolRef = nil,
    HasBallistics = false,
    BulletSpeed = 2500,
    BulletDrop = 0
}

local SpeedKeys = {
    "BSpeed", "BulletSpeed", "MuzzleVelocity", "ProjectileSpeed",
    "BulletVelocity", "Velocity", "Speed", "FireVelocity", "InitialVelocity"
}
local DropKeys = {
    "BDrop", "BulletDrop", "Gravity", "ProjectileGravity",
    "BulletGravity", "Drop", "GravityFactor", "BulletAcceleration"
}

local function ScanTableForBallistics(tbl, visited, depth)
    if depth > 3 or type(tbl) ~= "table" or visited[tbl] then return nil, nil end
    visited[tbl] = true
    local foundSpeed, foundDrop = nil, nil

    for i = 1, #SpeedKeys do
        local v = rawget(tbl, SpeedKeys[i])
        if type(v) == "number" and v > 25 and v < 25000 then
            foundSpeed = v
            break
        end
    end
    for i = 1, #DropKeys do
        local v = rawget(tbl, DropKeys[i])
        if type(v) == "number" and v >= 0 and v < 2000 then
            foundDrop = v
            break
        elseif typeof(v) == "Vector3" and v.Y ~= 0 then
            foundDrop = math.abs(v.Y)
            break
        end
    end
    if foundSpeed then return foundSpeed, foundDrop end

    for k, sub in pairs(tbl) do
        if type(sub) == "table" and k ~= "_G" and k ~= "shared" then
            local s, d = ScanTableForBallistics(sub, visited, depth + 1)
            if s then return s, d or foundDrop end
        end
    end
    return nil, nil
end

local function ExtractFromInstance(inst)
    if not inst then return nil, nil end
    local s, d = nil, nil
    for i = 1, #SpeedKeys do
        local a = inst:GetAttribute(SpeedKeys[i])
        if type(a) == "number" and a > 25 then s = a; break end
    end
    for i = 1, #DropKeys do
        local a = inst:GetAttribute(DropKeys[i])
        if type(a) == "number" and a >= 0 then d = a; break end
    end
    if s then return s, d end

    for _, desc in ipairs(inst:GetDescendants()) do
        if desc:IsA("NumberValue") or desc:IsA("IntValue") then
            local name = desc.Name
            for i = 1, #SpeedKeys do
                if name == SpeedKeys[i] and desc.Value > 25 then s = desc.Value; break end
            end
            for i = 1, #DropKeys do
                if name == DropKeys[i] and desc.Value >= 0 then d = desc.Value; break end
            end
        end
    end
    if s then return s, d end

    if getgc then
        local toolName = inst.Name
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" then
                    if rawget(v, "gunName") == toolName or rawget(v, "Name") == toolName or rawget(v, "ToolName") == toolName or rawget(v, "BSpeed") or rawget(v, "MuzzleVelocity") then
                        local gs, gd = ScanTableForBallistics(v, {}, 1)
                        if gs then
                            s, d = gs, gd
                            break
                        end
                    end
                end
            end
        end)
    end
    return s, d
end

local function GetEquippedWeaponObject()
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then return tool end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Model") and (child:FindFirstChild("Handle") or child:FindFirstChild("Muzzle") or child:FindFirstChild("ACS_Modulo") or child:FindFirstChild("FirePoint")) then
                return child
            end
        end
    end
    if Camera then
        for _, child in ipairs(Camera:GetChildren()) do
            if child:IsA("Model") and (child.Name:lower():find("view") or child.Name:lower():find("arms") or child:FindFirstChild("Handle", true)) then
                return child
            end
        end
    end
    local bp = LocalPlayer:FindFirstChildOfClass("Backpack")
    if bp then
        for _, item in ipairs(bp:GetChildren()) do
            if item:GetAttribute("Equipped") == true or item:GetAttribute("Active") == true then
                return item
            end
        end
    end
    return nil
end

local function GetWeaponBallistics()
    if not Config.AutoBallistics then
        return false, 2500, 0
    end
    local now = os.clock()
    local weapon = GetEquippedWeaponObject()
    if weapon == CachedBallistics.ToolRef and (now - CachedBallistics.LastScan) < 0.35 then
        return CachedBallistics.HasBallistics, CachedBallistics.BulletSpeed, CachedBallistics.BulletDrop
    end
    CachedBallistics.LastScan = now
    CachedBallistics.ToolRef = weapon

    if weapon then
        local s, d = ExtractFromInstance(weapon)
        if s and s > 25 and s < 6000 then
            local drop = d or 0
            if drop > 0 and drop <= 5 then
                drop = workspace.Gravity * drop
            elseif drop == 0 and s < 3500 then
                drop = workspace.Gravity * 0.25
            end
            CachedBallistics.HasBallistics = true
            CachedBallistics.BulletSpeed = s
            CachedBallistics.BulletDrop = drop
            return true, s, drop
        end
    end

    CachedBallistics.HasBallistics = false
    CachedBallistics.BulletSpeed = 99999
    CachedBallistics.BulletDrop = 0
    return false, 99999, 0
end

-- Real-Time Velocity Resolver (handles CFrame-moved characters and physics velocity)
local VelocityTracker = setmetatable({}, { __mode = "k" })

local function UpdateVelocityTracking(dt)
    if dt <= 0 or dt > 0.5 then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character.PrimaryPart
            if hrp then
                local pos = hrp.Position
                local physVel = hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
                local data = VelocityTracker[plr]
                if not data then
                    VelocityTracker[plr] = { LastPos = pos, SmoothedVel = physVel }
                else
                    local deltaVel = (pos - data.LastPos) / dt
                    local rawVel = (deltaVel.Magnitude > physVel.Magnitude * 0.5) and deltaVel or physVel
                    if rawVel.Magnitude > 250 then rawVel = physVel end
                    data.SmoothedVel = data.SmoothedVel:Lerp(rawVel, math.clamp(dt * 14, 0.15, 0.85))
                    data.LastPos = pos
                end
            end
        end
    end
end

local function GetPingSeconds()
    local ok, p = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(p) == "number" then
        return math.clamp(p / 1000, 0.01, 0.4)
    end
    return 0.065
end

local function GetPredictedPosition(part, basePos)
    if not Config.PredictionEnabled or not part or not basePos then
        return basePos
    end
    local char = part.Parent
    local plr = char and Players:GetPlayerFromCharacter(char)
    local vel = Vector3.zero
    if plr and VelocityTracker[plr] then
        vel = VelocityTracker[plr].SmoothedVel
    else
        vel = part.AssemblyLinearVelocity or part.Velocity or Vector3.zero
    end
    if vel.Magnitude < 0.5 then
        return basePos
    end

    local origin = (Camera and Camera.CFrame.Position) or basePos
    local dist = (basePos - origin).Magnitude
    local scale = Config.PredictionScale
    local hasBallistics, bulletSpeed, bulletDrop = GetWeaponBallistics()

    if hasBallistics and bulletSpeed > 30 and bulletSpeed < 6000 then
        local tof = dist / bulletSpeed
        local nextPos = basePos + (vel * tof * scale)
        tof = (nextPos - origin).Magnitude / bulletSpeed
        local leadOffset = vel * (tof + GetPingSeconds() * 0.35) * scale
        local dropOffset = Vector3.new(0, 0.5 * bulletDrop * (tof * tof) * math.clamp(scale, 0.1, 3.0), 0)
        return basePos + leadOffset + dropOffset
    else
        local baseFactor = (GetPingSeconds() * 0.85 + 0.045) * (scale * 0.35)
        local horizVel = Vector3.new(vel.X, vel.Y * 0.35, vel.Z)
        return basePos + (horizVel * baseFactor)
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
        if not onScreen or not CastClear(origin, worldPt, char) then
            return false
        end
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
local CurrentPredictedPos = nil
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

-- Deep Team-Aware Chams ESP
local ChamsFolder = ProtectInstance(Instance.new("Folder"))
ChamsFolder.Name = RandomStr(10)
ChamsFolder.Parent = SafeContainer

local function RefreshAllChams()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local hl = ChamsFolder:FindFirstChild(plr.Name)
            local char = plr.Character
            if hl and hl:IsA("Highlight") then
                if not char or not Config.ChamsEnabled then
                    hl.Enabled = false
                else
                    local enemy = IsEnemy(plr)
                    if Config.ESPTeamCheck then
                        hl.Enabled = enemy
                        hl.FillColor = Config.EnemyChamsFill
                        hl.OutlineColor = Color3.fromRGB(255, 160, 160)
                    else
                        hl.Enabled = true
                        hl.FillColor = enemy and Config.EnemyChamsFill or Config.ChamsFill
                        hl.OutlineColor = Config.ChamsOutline
                    end
                end
            end
        end
    end
end

local function ApplyChams(plr)
    if plr == LocalPlayer then return end
    local function OnChar(char)
        task.wait(0.1)
        if not char then return end
        local old = ChamsFolder:FindFirstChild(plr.Name)
        if old then old:Destroy() end
        local hl = ProtectInstance(Instance.new("Highlight"))
        hl.Name = plr.Name
        hl.Adornee = char
        hl.FillTransparency = 0.42
        hl.OutlineTransparency = 0.08
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ChamsFolder
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
    local c = ChamsFolder:FindFirstChild(p.Name)
    if c then c:Destroy() end
end)
LocalPlayer:GetPropertyChangedSignal("Team"):Connect(RefreshAllChams)

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
MainFrame.Size = UDim2.new(0, 390, 0, 540)
MainFrame.Position = UDim2.new(0.5, -195, 0.5, -270)
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

local DragBar = ProtectInstance(Instance.new("Frame", MainFrame))
DragBar.Size = UDim2.new(1, 0, 0, 44)
DragBar.BackgroundTransparency = 1
DragBar.Active = true

local Header = ProtectInstance(Instance.new("TextLabel", DragBar))
Header.Size = UDim2.new(1, -24, 0, 24)
Header.Position = UDim2.new(0, 12, 0, 4)
Header.BackgroundTransparency = 1
Header.Text = "LIQUID GLASS // 03 MOUSE INDEX SILENT"
Header.TextColor3 = Color3.fromRGB(240, 248, 255)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextXAlignment = Enum.TextXAlignment.Left

local SubHeader = ProtectInstance(Instance.new("TextLabel", DragBar))
SubHeader.Size = UDim2.new(1, -24, 0, 16)
SubHeader.Position = UDim2.new(0, 12, 0, 24)
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

local ListLayout = ProtectInstance(Instance.new("UIListLayout", Scroll))
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local IsDraggingSlider = false
do
    local dragging, dragStart, startPos
    DragBar.InputBegan:Connect(function(input)
        if not IsDraggingSlider and input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and not IsDraggingSlider and input.UserInputType == Enum.UserInputType.MouseMovement then
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

local function CreateSlider(name, minVal, maxVal, default, suffix, callback, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    local fmt = decimals > 0 and ("%s: %." .. tostring(decimals) .. "f%s") or "%s: %d%s"

    local box = ProtectInstance(Instance.new("Frame", Scroll))
    box.Size = UDim2.new(1, -8, 0, 44)
    box.BackgroundColor3 = Color3.fromRGB(26, 34, 48)
    box.BackgroundTransparency = 0.35
    box.Active = true
    ProtectInstance(Instance.new("UICorner", box)).CornerRadius = UDim.new(0, 8)
    local st = ProtectInstance(Instance.new("UIStroke", box))
    st.Color = Color3.fromRGB(255, 255, 255)
    st.Transparency = 0.82

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

    local sliding = false
    local function UpdateFromX(xPos)
        local rel = math.clamp((xPos - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local raw = minVal + (maxVal - minVal) * rel
        local val = math.floor(raw * mult + 0.5) / mult
        fill.Size = UDim2.new(rel, 0, 1, 0)
        lbl.Text = string.format(fmt, name, val, suffix or "")
        callback(val)
    end

    hitBtn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            sliding = true
            IsDraggingSlider = true
            UpdateFromX(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            UpdateFromX(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and sliding then
            sliding = false
            IsDraggingSlider = false
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
CreateSlider("Autofire Click Interval", 10, 10000, Config.FireInterval, " ms", function(v) Config.FireInterval = v end, 0)
CreateToggle("Silent Aim Enabled", Config.SilentEnabled, function(v) Config.SilentEnabled = v end)
CreateToggle("Smart Prediction Enabled", Config.PredictionEnabled, function(v) Config.PredictionEnabled = v end)
CreateSlider("Prediction Scale (0.10 - 10)", 0.10, 10.00, Config.PredictionScale, "x", function(v) Config.PredictionScale = v end, 2)
CreateToggle("Auto Weapon Ballistics Inspector", Config.AutoBallistics, function(v) Config.AutoBallistics = v; CachedBallistics.LastScan = 0 end)
CreateSlider("Aim FOV Radius", 20, 600, Config.FOV, " px", function(v) Config.FOV = v; FOVCircle.Radius = v end, 0)
CreateSlider("HitChance", 1, 100, Config.HitChance, "%", function(v) Config.HitChance = v end, 0)
CreateToggle("Multipoint Scanning", Config.Multipoint, function(v) Config.Multipoint = v end)
CreateSlider("Multipoint Scale", 20, 95, math.floor(Config.MultipointScale * 100), "%", function(v) Config.MultipointScale = v / 100 end, 0)
CreateToggle("WallCheck (Visible Only)", Config.WallCheck, function(v) Config.WallCheck = v end)
CreateToggle("Aim TeamCheck (Deep)", Config.TeamCheck, function(v) Config.TeamCheck = v end)
CreateToggle("ESP TeamCheck (Enemies Only = Red)", Config.ESPTeamCheck, function(v) Config.ESPTeamCheck = v; RefreshAllChams() end)
CreateToggle("Chams ESP", Config.ChamsEnabled, function(v) Config.ChamsEnabled = v; RefreshAllChams() end)
CreateToggle("Ignore ForceField", Config.IgnoreForceField, function(v) Config.IgnoreForceField = v end)
CreateToggle("Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v; FOVCircle.Visible = v end)

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
local LastChamsRefresh = 0

local function TriggerMouseClick()
    if mouse1click then
        mouse1click()
    elseif mouse1press and mouse1release then
        mouse1press()
        task.wait(0.01)
        mouse1release()
    end
end

RunService.RenderStepped:Connect(function(dt)
    UpdateVelocityTracking(dt)
    FOVCircle.Position = UserInputService:GetMouseLocation()
    CurrentTarget, CurrentTargetPos, CurrentTargetFullyExposed = GetClosestTarget()
    if CurrentTarget and CurrentTargetPos then
        CurrentPredictedPos = GetPredictedPosition(CurrentTarget, CurrentTargetPos)
    else
        CurrentPredictedPos = nil
    end

    local nowSec = os.clock()
    if (nowSec - LastChamsRefresh) > 0.5 then
        LastChamsRefresh = nowSec
        RefreshAllChams()
    end

    if Config.AutoFire and not IsClicking and not ScreenGui.Enabled then
        if CurrentTarget and CurrentPredictedPos and CurrentTargetFullyExposed then
            local now = nowSec * 1000
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
    if not checkcaller() and self == Mouse and Config.SilentEnabled and CurrentTarget and CurrentPredictedPos then
        if math.random(1, 100) <= Config.HitChance then
            local aimPt = CurrentPredictedPos
            if key == "Hit" then
                return CFrame.new(aimPt)
            elseif key == "Target" then
                return CurrentTarget
            elseif key == "UnitRay" then
                local origin = Camera.CFrame.Position
                return Ray.new(origin, (aimPt - origin).Unit)
            elseif key == "X" then
                local pos = Camera:WorldToViewportPoint(aimPt)
                return pos.X
            elseif key == "Y" then
                local pos = Camera:WorldToViewportPoint(aimPt)
                return pos.Y
            end
        end
    end
    return oldIndex(self, key)
end))
