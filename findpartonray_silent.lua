-- 02_findpartonray_silent.lua
-- Method: __namecall hook on FindPartOnRay, FindPartOnRayWithIgnoreList, FindPartOnRayWithWhitelist + Ballistic Solver + Deep ESP TeamCheck + Fixed Liquid Glass UI

local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
local ScriptContext = cloneref(game:GetService("ScriptContext"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))

local RawWorkspace = workspace
local RawRaycast = RawWorkspace.Raycast
local LocalPlayer = Players.LocalPlayer
local Camera = RawWorkspace.CurrentCamera

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
    AutoBallistics = true,
    PredictionFactor = 1.00,
    InFlightHoming = true,
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
    ChamsFill = Color3.fromRGB(255, 40, 40),
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
                    if type(det) == "function" and islclosure(det) and (not isexecutorclosure or not isexecutorclosure(det)) then
                        pcall(hookfunction, det, newcclosure(function() return true end))
                    end
                    if type(kill) == "function" and islclosure(kill) and (not isexecutorclosure or not isexecutorclosure(kill)) then
                        pcall(hookfunction, kill, newcclosure(function() return nil end))
                    end
                    local anti = rawget(v, "Anti")
                    if type(anti) == "table" and rawget(v, "Variables") and rawget(v, "Process") then
                        for _, func in pairs(anti) do
                            if type(func) == "function" and islclosure(func) and (not isexecutorclosure or not isexecutorclosure(func)) then
                                pcall(hookfunction, func, newcclosure(function() return true end))
                            end
                        end
                    end
                end
            end
        end)
    end
end
pcall(BypassAntiCheats)

-- Deep Game Inspection TeamCheck
local TeamKeys = { "Team", "TeamName", "TeamId", "Faction", "Side", "Squad", "Clan", "Group", "Allegiance" }

local function ExtractIdentityToken(plr)
    if not plr then return nil end
    if plr.Team ~= nil and not plr.Neutral then
        return "T_" .. tostring(plr.Team.Name)
    end
    if not plr.Neutral and plr.TeamColor then
        return "TC_" .. tostring(plr.TeamColor.Name)
    end
    for i = 1, #TeamKeys do
        local k = TeamKeys[i]
        local attr = plr:GetAttribute(k)
        if attr ~= nil and tostring(attr) ~= "" and tostring(attr) ~= "None" then
            return "PA_" .. k .. "_" .. tostring(attr)
        end
    end
    local char = plr.Character
    if char then
        for i = 1, #TeamKeys do
            local k = TeamKeys[i]
            local attr = char:GetAttribute(k)
            if attr ~= nil and tostring(attr) ~= "" and tostring(attr) ~= "None" then
                return "CA_" .. k .. "_" .. tostring(attr)
            end
            local valObj = char:FindFirstChild(k)
            if valObj and valObj:IsA("ValueBase") and valObj.Value ~= nil then
                return "CV_" .. k .. "_" .. tostring(valObj.Value)
            end
        end
        if char.Parent and char.Parent ~= RawWorkspace and char.Parent.Name ~= "Characters" and char.Parent.Name ~= "Players" then
            return "CP_" .. char.Parent.Name
        end
    end
    for _, folderName in ipairs({ "leaderstats", "Status", "Data", "PlayerData", "Stats" }) do
        local sub = plr:FindFirstChild(folderName)
        if sub then
            for i = 1, #TeamKeys do
                local k = TeamKeys[i]
                local valObj = sub:FindFirstChild(k)
                if valObj and valObj:IsA("ValueBase") and valObj.Value ~= nil and tostring(valObj.Value) ~= "" then
                    return "SV_" .. k .. "_" .. tostring(valObj.Value)
                end
            end
        end
    end
    return nil
end

local function IsTeammate(plr)
    if not plr or plr == LocalPlayer then return true end
    local char = plr.Character
    if char then
        if char:GetAttribute("IsTeammate") == true or char:GetAttribute("IsAlly") == true then return true end
        if char:GetAttribute("IsEnemy") == true then return false end
    end
    local myToken = ExtractIdentityToken(LocalPlayer)
    local theirToken = ExtractIdentityToken(plr)
    if myToken and theirToken then
        return myToken == theirToken
    end
    return false
end

local function IsValidEnemyForAim(plr)
    if not plr or plr == LocalPlayer then return false end
    if Config.TeamCheck and IsTeammate(plr) then return false end
    return true
end

-- Smart Weapon Inspector & Ballistic Solver
local SpeedKeys = {
    "MuzzleVelocity", "BulletSpeed", "ProjectileSpeed", "Velocity", "Speed",
    "BSpeed", "BulletVelocity", "InitialVelocity", "FireVelocity", "vel", "bulletSpeed"
}
local DropKeys = {
    "BulletDrop", "Gravity", "Drop", "ProjectileDrop", "BulletGravity",
    "Acceleration", "BulletAcceleration", "Grav", "drop", "gravity"
}

local CachedWeaponRef = nil
local CachedBallistics = { HasBallistics = false, Speed = math.huge, Gravity = 0 }
local LastWeaponScan = 0

local function ScanTableForBallistics(tbl, depth, visited)
    if depth > 3 or type(tbl) ~= "table" or visited[tbl] then return nil, nil end
    visited[tbl] = true
    local foundSpeed, foundDrop = nil, nil
    for i = 1, #SpeedKeys do
        local v = rawget(tbl, SpeedKeys[i])
        if type(v) == "number" and v > 15 and v < 30000 then foundSpeed = v; break end
    end
    for i = 1, #DropKeys do
        local v = rawget(tbl, DropKeys[i])
        if type(v) == "number" and v >= 0 and v < 2000 then foundDrop = v; break
        elseif typeof(v) == "Vector3" then foundDrop = math.abs(v.Y); break end
    end
    if foundSpeed then return foundSpeed, foundDrop end
    for k, sub in pairs(tbl) do
        if type(sub) == "table" and k ~= "__index" then
            local s, d = ScanTableForBallistics(sub, depth + 1, visited)
            if s then return s, d end
        end
    end
    return nil, nil
end

local function InspectContainerBallistics(container)
    if not container then return nil, nil end
    local s, d = nil, nil
    for i = 1, #SpeedKeys do
        local attr = container:GetAttribute(SpeedKeys[i])
        if type(attr) == "number" and attr > 15 and attr < 30000 then s = attr; break end
    end
    for i = 1, #DropKeys do
        local attr = container:GetAttribute(DropKeys[i])
        if type(attr) == "number" and attr >= 0 then d = attr; break end
        if typeof(attr) == "Vector3" then d = math.abs(attr.Y); break end
    end
    if s then return s, d end

    for _, desc in ipairs(container:GetDescendants()) do
        if desc:IsA("ValueBase") then
            for i = 1, #SpeedKeys do
                if desc.Name == SpeedKeys[i] and type(desc.Value) == "number" and desc.Value > 15 and desc.Value < 30000 then
                    s = desc.Value
                end
            end
            for i = 1, #DropKeys do
                if desc.Name == DropKeys[i] then
                    if type(desc.Value) == "number" then d = math.abs(desc.Value)
                    elseif typeof(desc.Value) == "Vector3" then d = math.abs(desc.Value.Y) end
                end
            end
        elseif desc:IsA("ModuleScript") then
            local ok, mod = pcall(require, desc)
            if ok and type(mod) == "table" then
                local ms, md = ScanTableForBallistics(mod, 1, {})
                if ms then s = ms; d = md or d; break end
            end
        end
    end
    return s, d
end

local function GetHeldWeaponObject()
    local char = LocalPlayer.Character
    if char then
        local tool = char:FindFirstChildOfClass("Tool")
        if tool then return tool end
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Model") and (child:FindFirstChild("Handle") or child:FindFirstChild("Muzzle") or child:FindFirstChild("FirePoint") or child:FindFirstChild("ACS_Modulo")) then
                return child
            end
        end
    end
    if Camera then
        for _, child in ipairs(Camera:GetChildren()) do
            if child:IsA("Model") and (child.Name:lower():find("view") or child.Name:lower():find("arms") or child.Name:lower():find("weapon") or child:FindFirstChild("Muzzle", true)) then
                return child
            end
        end
    end
    return nil
end

local function GetWeaponBallistics()
    local now = os.clock()
    local weapon = GetHeldWeaponObject()
    if weapon == CachedWeaponRef and (now - LastWeaponScan) < 0.75 then
        return CachedBallistics
    end
    LastWeaponScan = now
    CachedWeaponRef = weapon

    local speed, drop = InspectContainerBallistics(weapon)
    if not speed and weapon then
        local wName = weapon.Name
        for _, folderName in ipairs({ "Weapons", "Guns", "Items", "WeaponConfigs", "GunModules", "ACS_Engine" }) do
            local repFolder = ReplicatedStorage:FindFirstChild(folderName, true)
            if repFolder then
                local cfg = repFolder:FindFirstChild(wName, true)
                if cfg then
                    if cfg:IsA("ModuleScript") then
                        local ok, mod = pcall(require, cfg)
                        if ok and type(mod) == "table" then
                            speed, drop = ScanTableForBallistics(mod, 1, {})
                        end
                    else
                        speed, drop = InspectContainerBallistics(cfg)
                    end
                end
            end
            if speed then break end
        end
    end

    if not speed and getgc and weapon then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" and (rawget(v, "MuzzleVelocity") or rawget(v, "BulletSpeed") or rawget(v, "BSpeed")) then
                    local s, d = ScanTableForBallistics(v, 1, {})
                    if s then speed = s; drop = d; break end
                end
            end
        end)
    end

    if speed and speed > 15 and speed < 25000 then
        local grav = drop or RawWorkspace.Gravity or 196.2
        if grav > 0 and grav <= 5 then grav = grav * (RawWorkspace.Gravity or 196.2) end
        CachedBallistics = { HasBallistics = true, Speed = speed, Gravity = grav }
    else
        CachedBallistics = { HasBallistics = false, Speed = math.huge, Gravity = 0 }
    end
    return CachedBallistics
end

local VelocityData = setmetatable({}, { __mode = "k" })

local function UpdateVelocityTracker(dt)
    if dt <= 0 then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            local hrp = plr.Character:FindFirstChild("HumanoidRootPart") or plr.Character.PrimaryPart
            if hrp then
                local pos = hrp.Position
                local data = VelocityData[plr]
                if not data then
                    VelocityData[plr] = { LastPos = pos, Vel = Vector3.zero, Accel = Vector3.zero }
                else
                    local rawDeltaVel = (pos - data.LastPos) / dt
                    local physVel = hrp.AssemblyLinearVelocity or hrp.Velocity or Vector3.zero
                    local blendedVel = (rawDeltaVel.Magnitude > 0.5) and rawDeltaVel or physVel
                    if blendedVel.Magnitude > 450 then blendedVel = physVel end
                    local newVel = data.Vel:Lerp(blendedVel, math.clamp(dt * 14, 0.15, 1))
                    data.Accel = data.Accel:Lerp((newVel - data.Vel) / dt, math.clamp(dt * 8, 0.1, 1))
                    data.Vel = newVel
                    data.LastPos = pos
                end
            end
        end
    end
end

local function ComputePredictedPosition(origin, rawPos, plr)
    if not Config.PredictionEnabled then return rawPos end
    local vData = VelocityData[plr]
    local targetVel = vData and vData.Vel or Vector3.zero
    local targetAccel = vData and vData.Accel or Vector3.zero
    if plr and plr.Character and targetVel.Magnitude < 0.05 then
        local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
        if hrp then targetVel = hrp.AssemblyLinearVelocity or Vector3.zero end
    end

    local factor = Config.PredictionFactor
    local ballistics = Config.AutoBallistics and GetWeaponBallistics() or { HasBallistics = false }

    if ballistics.HasBallistics and ballistics.Speed < 25000 then
        local speed = math.max(ballistics.Speed, 25)
        local grav = ballistics.Gravity
        local t = (rawPos - origin).Magnitude / speed
        for _ = 1, 3 do
            local futurePos = rawPos + (targetVel * t) + (0.5 * Vector3.new(targetAccel.X, 0, targetAccel.Z) * (t * t) * 0.25)
            t = (futurePos - origin).Magnitude / speed
        end
        local scaledT = t * factor
        local leadOffset = (targetVel * scaledT) + (0.5 * Vector3.new(targetAccel.X, 0, targetAccel.Z) * (scaledT * scaledT) * 0.2)
        local dropCompensation = Vector3.new(0, 0.5 * grav * (t * t) * factor, 0)
        return rawPos + leadOffset + dropCompensation
    else
        if targetVel.Magnitude < 0.1 then return rawPos end
        local leadTime = (factor - 1.0) * 0.045
        if not Config.AutoBallistics then leadTime = factor * 0.045 end
        if leadTime <= 0 then return rawPos end
        return rawPos + (targetVel * leadTime)
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
    local res = RawRaycast(RawWorkspace, origin, dir, VisRayParams)
    if not res then return true end
    return res.Instance and res.Instance:IsDescendantOf(targetChar)
end

local function IsPartFullyExposed(part, char)
    Camera = RawWorkspace.CurrentCamera
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
    Camera = RawWorkspace.CurrentCamera
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
local CurrentTargetRawPos = nil
local CurrentTargetPos = nil
local CurrentTargetPlr = nil
local CurrentTargetFullyExposed = false

local function GetClosestTarget()
    Camera = RawWorkspace.CurrentCamera
    if not Camera or not Config.SilentEnabled then return nil, nil, nil, nil, false end
    local bestDist = Config.FOV
    local bestPart, bestRawPos, bestPlr, bestExposed = nil, nil, nil, false
    local mousePos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if IsValidEnemyForAim(plr) then
            local char = plr.Character
            local parts = GetCandidateParts(char)
            for i = 1, #parts do
                local part = parts[i]
                local pt, dist = ResolveMultipointOnPart(part, char, mousePos, bestDist)
                if pt and dist then
                    bestDist = dist
                    bestPart = part
                    bestRawPos = pt
                    bestPlr = plr
                    if Config.RequireFullExposure then
                        bestExposed = IsPartFullyExposed(part, char)
                    else
                        bestExposed = CastClear(Camera.CFrame.Position, pt, char)
                    end
                end
            end
        end
    end
    local predictedPos = bestRawPos and ComputePredictedPosition(Camera.CFrame.Position, bestRawPos, bestPlr) or nil
    return bestPart, bestRawPos, predictedPos, bestPlr, bestExposed
end

-- Enemy-Only Red Chams ESP
local ChamsFolder = ProtectInstance(Instance.new("Folder"))
ChamsFolder.Name = RandomStr(10)
ChamsFolder.Parent = SafeContainer

local PlayerHighlights = {}

local function RefreshChams()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local hl = PlayerHighlights[plr]
            if char and char.Parent then
                if not hl or not hl.Parent then
                    hl = ProtectInstance(Instance.new("Highlight"))
                    hl.Name = plr.Name
                    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    hl.FillTransparency = 0.42
                    hl.OutlineTransparency = 0.08
                    hl.Parent = ChamsFolder
                    PlayerHighlights[plr] = hl
                end
                hl.Adornee = char
                local teammate = IsTeammate(plr)
                if not Config.ChamsEnabled or (Config.ESPTeamCheck and teammate) then
                    hl.Enabled = false
                else
                    hl.Enabled = true
                    hl.FillColor = teammate and Color3.fromRGB(60, 180, 255) or Color3.fromRGB(255, 35, 35)
                    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                end
            elseif hl then
                hl.Enabled = false
            end
        end
    end
end

Players.PlayerRemoving:Connect(function(p)
    if PlayerHighlights[p] then
        PlayerHighlights[p]:Destroy()
        PlayerHighlights[p] = nil
    end
end)

local FOVCircle = Drawing.new("Circle")
FOVCircle.Radius = Config.FOV
FOVCircle.Color = Color3.fromRGB(0, 255, 140)
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
MainFrame.Size = UDim2.new(0, 400, 0, 550)
MainFrame.Position = UDim2.new(0.5, -200, 0.5, -275)
MainFrame.BackgroundColor3 = Color3.fromRGB(16, 24, 22)
MainFrame.BackgroundTransparency = 0.22
MainFrame.BorderSizePixel = 0
MainFrame.Active = true

ProtectInstance(Instance.new("UICorner", MainFrame)).CornerRadius = UDim.new(0, 14)
local GlassStroke = ProtectInstance(Instance.new("UIStroke", MainFrame))
GlassStroke.Thickness = 1.5
GlassStroke.Color = Color3.fromRGB(160, 255, 210)
GlassStroke.Transparency = 0.62

local GlassGrad = ProtectInstance(Instance.new("UIGradient", MainFrame))
GlassGrad.Rotation = 135
GlassGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(180, 255, 220)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(110, 170, 150))
})

local DragHeader = ProtectInstance(Instance.new("Frame", MainFrame))
DragHeader.Size = UDim2.new(1, 0, 0, 46)
DragHeader.BackgroundTransparency = 1
DragHeader.Active = true

local Header = ProtectInstance(Instance.new("TextLabel", DragHeader))
Header.Size = UDim2.new(1, -24, 0, 28)
Header.Position = UDim2.new(0, 12, 0, 4)
Header.BackgroundTransparency = 1
Header.Text = "LIQUID GLASS // 02 FINDPARTONRAY SILENT"
Header.TextColor3 = Color3.fromRGB(240, 255, 250)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextXAlignment = Enum.TextXAlignment.Left

local SubHeader = ProtectInstance(Instance.new("TextLabel", DragHeader))
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
    DragHeader.InputBegan:Connect(function(input)
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
    local bInfo = CachedBallistics.HasBallistics and string.format(" | V:%.0f", CachedBallistics.Speed) or " | Hitscan"
    SubHeader.Text = string.format("[%s] Menu | [%s] Autofire: %s%s", Config.MenuKey.Name, Config.AutoFireKey.Name, Config.AutoFire and "ON" or "OFF", bInfo)
    SubHeader.TextColor3 = Config.AutoFire and Color3.fromRGB(0, 255, 140) or Color3.fromRGB(255, 110, 110)
end

local function CreateToggle(name, default, callback)
    local row = ProtectInstance(Instance.new("TextButton", Scroll))
    row.Size = UDim2.new(1, -8, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(28, 40, 36)
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
    lbl.TextColor3 = Color3.fromRGB(235, 255, 245)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local ind = ProtectInstance(Instance.new("Frame", row))
    ind.Size = UDim2.new(0, 34, 0, 16)
    ind.Position = UDim2.new(1, -44, 0.5, -8)
    ind.BackgroundColor3 = default and Color3.fromRGB(0, 230, 130) or Color3.fromRGB(60, 75, 70)
    ProtectInstance(Instance.new("UICorner", ind)).CornerRadius = UDim.new(1, 0)

    local state = default
    local function SetState(v)
        state = v
        ind.BackgroundColor3 = state and Color3.fromRGB(0, 230, 130) or Color3.fromRGB(60, 75, 70)
        callback(state)
    end
    row.MouseButton1Click:Connect(function()
        SetState(not state)
    end)
    return SetState
end

local function CreateSlider(name, minVal, maxVal, default, suffix, callback, decimals)
    local box = ProtectInstance(Instance.new("Frame", Scroll))
    box.Size = UDim2.new(1, -8, 0, 44)
    box.BackgroundColor3 = Color3.fromRGB(28, 40, 36)
    box.BackgroundTransparency = 0.35
    box.Active = true
    ProtectInstance(Instance.new("UICorner", box)).CornerRadius = UDim.new(0, 8)
    local st = ProtectInstance(Instance.new("UIStroke", box))
    st.Color = Color3.fromRGB(255, 255, 255)
    st.Transparency = 0.82

    local fmt = decimals and ("%s: %." .. tostring(decimals) .. "f%s") or "%s: %d%s"

    local lbl = ProtectInstance(Instance.new("TextLabel", box))
    lbl.Size = UDim2.new(1, -20, 0, 20)
    lbl.Position = UDim2.new(0, 10, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = string.format(fmt, name, default, suffix or "")
    lbl.TextColor3 = Color3.fromRGB(235, 255, 245)
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local bar = ProtectInstance(Instance.new("Frame", box))
    bar.Size = UDim2.new(1, -20, 0, 8)
    bar.Position = UDim2.new(0, 10, 0, 28)
    bar.BackgroundColor3 = Color3.fromRGB(45, 60, 55)
    ProtectInstance(Instance.new("UICorner", bar)).CornerRadius = UDim.new(1, 0)

    local fill = ProtectInstance(Instance.new("Frame", bar))
    fill.Size = UDim2.new(math.clamp((default - minVal) / (maxVal - minVal), 0, 1), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(0, 230, 130)
    ProtectInstance(Instance.new("UICorner", fill)).CornerRadius = UDim.new(1, 0)

    local hitBtn = ProtectInstance(Instance.new("TextButton", box))
    hitBtn.Size = UDim2.new(1, 0, 1, 0)
    hitBtn.BackgroundTransparency = 1
    hitBtn.Text = ""
    hitBtn.AutoButtonColor = false

    local sliding = false
    local function UpdateFromPos(xPos)
        local rel = math.clamp((xPos - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
        local raw = minVal + (maxVal - minVal) * rel
        local val
        if decimals then
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
        UpdateFromPos(x)
    end)
    UserInputService.InputChanged:Connect(function(input)
        if sliding and input.UserInputType == Enum.UserInputType.MouseMovement then
            UpdateFromPos(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 and sliding then
            sliding = false
            AnySliderDragging = false
            Scroll.ScrollingEnabled = true
        end
    end)
end

local WaitingBind = false
local BindBtn = ProtectInstance(Instance.new("TextButton", Scroll))
BindBtn.Size = UDim2.new(1, -8, 0, 30)
BindBtn.BackgroundColor3 = Color3.fromRGB(36, 52, 48)
BindBtn.BackgroundTransparency = 0.3
BindBtn.Text = "Autofire Toggle Bind: [ F ] (Click to Change)"
BindBtn.TextColor3 = Color3.fromRGB(150, 255, 200)
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
CreateToggle("Smart Prediction Enabled", Config.PredictionEnabled, function(v) Config.PredictionEnabled = v end)
CreateToggle("Auto Weapon Ballistics Inspector", Config.AutoBallistics, function(v) Config.AutoBallistics = v end)
CreateSlider("Prediction Scale (0.10 - 10.0)", 0.10, 10.00, Config.PredictionFactor, "x", function(v) Config.PredictionFactor = v end, 2)
CreateToggle("In-Flight Projectile Homing", Config.InFlightHoming, function(v) Config.InFlightHoming = v end)
CreateSlider("Aim FOV Radius", 20, 600, Config.FOV, " px", function(v) Config.FOV = v; FOVCircle.Radius = v end)
CreateSlider("HitChance", 1, 100, Config.HitChance, "%", function(v) Config.HitChance = v end)
CreateToggle("Multipoint Scanning", Config.Multipoint, function(v) Config.Multipoint = v end)
CreateSlider("Multipoint Scale", 20, 95, math.floor(Config.MultipointScale * 100), "%", function(v) Config.MultipointScale = v / 100 end)
CreateToggle("WallCheck (Visible Only)", Config.WallCheck, function(v) Config.WallCheck = v end)
CreateToggle("Aim TeamCheck", Config.TeamCheck, function(v) Config.TeamCheck = v end)
CreateToggle("ESP TeamCheck (Enemies Only Red)", Config.ESPTeamCheck, function(v) Config.ESPTeamCheck = v; RefreshChams() end)
CreateToggle("Ignore ForceField", Config.IgnoreForceField, function(v) Config.IgnoreForceField = v end)
CreateToggle("Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v; FOVCircle.Visible = v end)
CreateToggle("Chams ESP (Enemy Red)", Config.ChamsEnabled, function(v) Config.ChamsEnabled = v; RefreshChams() end)

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
local LastChamsClock = 0
local IsClicking = false

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
    UpdateVelocityTracker(dt)
    FOVCircle.Position = UserInputService:GetMouseLocation()
    CurrentTarget, CurrentTargetRawPos, CurrentTargetPos, CurrentTargetPlr, CurrentTargetFullyExposed = GetClosestTarget()

    local now = os.clock()
    if (now - LastChamsClock) >= 0.25 then
        LastChamsClock = now
        RefreshChams()
        RefreshStatusText()
    end

    if Config.AutoFire and not IsClicking and not ScreenGui.Enabled then
        if CurrentTarget and CurrentTargetPos and CurrentTargetFullyExposed then
            local nowMs = now * 1000
            if (nowMs - LastShotClock) >= Config.FireInterval then
                if math.random(1, 100) <= Config.HitChance then
                    LastShotClock = nowMs
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

local RayMethods = {
    FindPartOnRay = true,
    FindPartOnRayWithIgnoreList = true,
    FindPartOnRayWithWhitelist = true
}

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if not checkcaller() then
        local method = getnamecallmethod()
        if (method == "FindFirstChild" or method == "FindFirstChildOfClass") and (self == CoreGui or self == SafeContainer) then
            local res = oldNamecall(self, ...)
            if res and ProtectedInstances[res] then return nil end
            return res
        end
        if self == RawWorkspace and RayMethods[method] and Config.SilentEnabled and CurrentTarget and CurrentTargetPos and CurrentTargetRawPos then
            if math.random(1, 100) <= Config.HitChance then
                local args = { ... }
                local ray = args[1]
                if typeof(ray) == "Ray" then
                    local origin = ray.Origin
                    local dir = ray.Direction
                    local camPos = Camera and Camera.CFrame.Position or origin
                    local distFromCam = (origin - camPos).Magnitude
                    local distToTarget = (CurrentTargetRawPos - origin).Magnitude

                    if distFromCam < 28 then
                        local exactAimPos = ComputePredictedPosition(origin, CurrentTargetRawPos, CurrentTargetPlr)
                        local mag = math.max(dir.Magnitude, (exactAimPos - origin).Magnitude + 15)
                        args[1] = Ray.new(origin, (exactAimPos - origin).Unit * mag)
                        return oldNamecall(self, unpack(args))
                    elseif Config.InFlightHoming and distToTarget <= math.max(dir.Magnitude * 3.5, 45) then
                        local mag = math.max(dir.Magnitude, distToTarget + 5)
                        args[1] = Ray.new(origin, (CurrentTargetRawPos - origin).Unit * mag)
                        return oldNamecall(self, unpack(args))
                    end
                end
            end
        end
    end
    return oldNamecall(self, ...)
end))
