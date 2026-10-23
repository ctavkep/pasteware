-- 01_raycast_silent.lua
-- Method: __namecall hook on workspace:Raycast & workspace:Spherecast + Deep TeamCheck + Dynamic Ballistics & Smart Resolver + Full-Exposure Multipoint Autofire + Liquid Glass UI

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
local Camera = workspace.CurrentCamera

local math_clamp = math.clamp
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_random = math.random
local math_abs = math.abs
local os_clock = os.clock
local table_clear = table.clear
local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local unpack_fn = table.unpack or unpack

local Config = {
    SilentEnabled = true,
    FOV = 180,
    ShowFOV = true,
    HitChance = 100,

   
    TeamCheck = true,        
    TeamCheckESP = true,     
    DeepTeamScan = true,     

    IgnoreForceField = true,
    WallCheck = true,
    Multipoint = true,
    MultipointScale = 0.72,

   
    SmartPrediction = true,
    AutoBallistics = true,   
    DefaultBulletSpeed = 1200,
    BulletGravity = 0,       
    PingCompensation = true,

    
    SmartResolver = true,
    ResolverMissTimeout = 0.35, 

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
        s[i] = string.char(math_random(97, 122))
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


local TeamAttributeKeys = {
    "Team", "TeamName", "TeamId", "TeamID", "Faction", "Squad", "Side", "Group", "Clan", "Alliance", "Role"
}

local function GetDeepTeamIdentifier(plr, char)
    if plr.Team ~= nil then
        return "T_" .. tostring(plr.Team)
    end
    if not plr.Neutral and plr.TeamColor then
        return "TC_" .. tostring(plr.TeamColor)
    end

    if not Config.DeepTeamScan then return nil end

    for i = 1, #TeamAttributeKeys do
        local key = TeamAttributeKeys[i]
        local attr = plr:GetAttribute(key)
        if attr ~= nil and attr ~= "" and attr ~= "None" and attr ~= "FFA" then
            return "PA_" .. key .. "_" .. tostring(attr)
        end
    end

    if char then
        for i = 1, #TeamAttributeKeys do
            local key = TeamAttributeKeys[i]
            local attr = char:GetAttribute(key)
            if attr ~= nil and attr ~= "" and attr ~= "None" and attr ~= "FFA" then
                return "CA_" .. key .. "_" .. tostring(attr)
            end
        end

        local parent = char.Parent
        if parent and parent ~= workspace and parent.Name ~= "Characters" and parent.Name ~= "Players" and parent.Name ~= "Entities" and parent.Name ~= "Live" then
            return "CF_" .. parent.Name
        end

        for i = 1, #TeamAttributeKeys do
            local key = TeamAttributeKeys[i]
            local valObj = char:FindFirstChild(key) or plr:FindFirstChild(key)
            if valObj and valObj:IsA("ValueBase") and valObj.Value ~= nil and valObj.Value ~= "" then
                return "VO_" .. key .. "_" .. tostring(valObj.Value)
            end
        end

        local bodyColors = char:FindFirstChildOfClass("BodyColors")
        if bodyColors then
            return "BC_" .. tostring(bodyColors.TorsoColor)
        end
        local head = char:FindFirstChild("Head")
        if head then
            local bb = head:FindFirstChildOfClass("BillboardGui")
            if bb then
                local lbl = bb:FindFirstChildOfClass("TextLabel", true)
                if lbl and lbl.TextColor3 ~= Color3.new(1, 1, 1) then
                    local c = lbl.TextColor3
                    return string.format("UI_%d_%d_%d", math_floor(c.R * 255), math_floor(c.G * 255), math_floor(c.B * 255))
                end
            end
        end
    end

    local ls = plr:FindFirstChild("leaderstats") or plr:FindFirstChild("Status") or plr:FindFirstChild("Data")
    if ls then
        for i = 1, #TeamAttributeKeys do
            local key = TeamAttributeKeys[i]
            local v = ls:FindFirstChild(key)
            if v and v:IsA("ValueBase") and v.Value ~= nil and v.Value ~= "" then
                return "LS_" .. key .. "_" .. tostring(v.Value)
            end
        end
    end

    return nil
end

local function IsTeammate(plr)
    if plr == LocalPlayer then return true end
    local lChar = LocalPlayer.Character
    local tChar = plr.Character

    if Config.DeepTeamScan and tChar then
        local existingHl = tChar:FindFirstChildOfClass("Highlight")
        if existingHl and not ProtectedInstances[existingHl] then
            local fc = existingHl.FillColor
            if fc.G > 0.65 and fc.R < 0.35 then
                return true
            end
        end
    end

    local myId = GetDeepTeamIdentifier(LocalPlayer, lChar)
    local theirId = GetDeepTeamIdentifier(plr, tChar)

    if myId and theirId then
        return myId == theirId
    end
    return false
end


local ActiveBallistics = {
    Speed = Config.DefaultBulletSpeed,
    Gravity = Config.BulletGravity,
    CachedPing = 0,
    LastTool = nil,
    LastScan = 0
}

local SpeedKeys = {
    "BulletSpeed", "MuzzleVelocity", "Velocity", "ProjectileSpeed", "Speed", "FireSpeed", "vel", "bspeed"
}
local GravityKeys = {
    "Gravity", "BulletDrop", "Drop", "ProjectileGravity", "Acceleration", "grav"
}

local function UpdateCachedPing()
    if not Config.PingCompensation then
        ActiveBallistics.CachedPing = 0
        return
    end
    local ok, p = pcall(function()
        return LocalPlayer:GetNetworkPing()
    end)
    if ok and type(p) == "number" then
        ActiveBallistics.CachedPing = math_clamp(p * 0.5, 0, 0.3)
        return
    end
    pcall(function()
        local item = Stats and Stats.Network and Stats.Network.ServerStatsItem and Stats.Network.ServerStatsItem["Data Ping"]
        if item then
            ActiveBallistics.CachedPing = math_clamp((item:GetValue() / 1000) * 0.5, 0, 0.3)
        end
    end)
end

local function ScanToolBallistics()
    if not Config.AutoBallistics then
        ActiveBallistics.Speed = Config.DefaultBulletSpeed
        ActiveBallistics.Gravity = Config.BulletGravity
        return
    end

    local char = LocalPlayer.Character
    if not char then return end
    local tool = char:FindFirstChildOfClass("Tool") or char:FindFirstChildOfClass("Model")
    local now = os_clock()

    if tool == ActiveBallistics.LastTool and (now - ActiveBallistics.LastScan) < 2.0 then
        return
    end

    ActiveBallistics.LastTool = tool
    ActiveBallistics.LastScan = now

    local foundSpeed = nil
    local foundGrav = nil

    if tool then
        for i = 1, #SpeedKeys do
            local v = tool:GetAttribute(SpeedKeys[i])
            if type(v) == "number" and v > 10 then foundSpeed = v; break end
        end
        for i = 1, #GravityKeys do
            local v = tool:GetAttribute(GravityKeys[i])
            if type(v) == "number" then foundGrav = math_abs(v); break end
            if typeof(v) == "Vector3" then foundGrav = math_abs(v.Y); break end
        end

        if not foundSpeed then
            for _, desc in ipairs(tool:GetDescendants()) do
                if desc:IsA("NumberValue") or desc:IsA("IntValue") then
                    local n = desc.Name:lower()
                    for i = 1, #SpeedKeys do
                        if n == SpeedKeys[i]:lower() and desc.Value > 10 then
                            foundSpeed = desc.Value
                            break
                        end
                    end
                    for i = 1, #GravityKeys do
                        if n == GravityKeys[i]:lower() then
                            foundGrav = math_abs(desc.Value)
                            break
                        end
                    end
                elseif desc:IsA("ModuleScript") then
                    pcall(function()
                        local ok, mod = pcall(require, desc)
                        if ok and type(mod) == "table" then
                            for i = 1, #SpeedKeys do
                                local val = rawget(mod, SpeedKeys[i])
                                if type(val) == "number" and val > 10 then foundSpeed = val; break end
                            end
                            for i = 1, #GravityKeys do
                                local val = rawget(mod, GravityKeys[i])
                                if type(val) == "number" then foundGrav = math_abs(val); break end
                                if typeof(val) == "Vector3" then foundGrav = math_abs(val.Y); break end
                            end
                        end
                    end)
                end
            end
        end
    end

    if not foundSpeed and getgc and tool then
        pcall(function()
            local tName = tool.Name
            for _, v in ipairs(getgc(true)) do
                if type(v) == "table" and (rawget(v, "Name") == tName or rawget(v, "ToolName") == tName or rawget(v, "Weapon") == tName) then
                    for i = 1, #SpeedKeys do
                        local val = rawget(v, SpeedKeys[i])
                        if type(val) == "number" and val > 10 then foundSpeed = val; break end
                    end
                    for i = 1, #GravityKeys do
                        local val = rawget(v, GravityKeys[i])
                        if type(val) == "number" then foundGrav = math_abs(val); break end
                    end
                    if foundSpeed then break end
                end
            end
        end)
    end

    ActiveBallistics.Speed = foundSpeed or Config.DefaultBulletSpeed
    ActiveBallistics.Gravity = foundGrav or Config.BulletGravity
end


local PlayerTrackData = setmetatable({}, { __mode = "k" })

local function GetTracker(plr)
    local data = PlayerTrackData[plr]
    if not data then
        data = {
            LastPos = nil,
            LastVel = Vector3.zero,
            SmoothedVel = Vector3.zero,
            Accel = Vector3.zero,
            RightVec = Vector3_new(1, 0, 0),
            LastTime = os_clock(),
            LastHealth = nil,
            ResolverMode = 1,
            ConsecutiveHits = 0,
            ConsecutiveMisses = 0,
            PendingShot = false,
            ShotTimestamp = 0
        }
        PlayerTrackData[plr] = data
    end
    return data
end

local function UpdateTargetKinematics()
    UpdateCachedPing()
    ScanToolBallistics()

    local now = os_clock()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = plr.Character
            local root = char and (char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if root and hum and hum.Health > 0 then
                local tr = GetTracker(plr)
                local dt = now - tr.LastTime
                local curPos = root.Position
                tr.RightVec = root.CFrame.RightVector

                if dt > 0.001 and dt < 0.5 and tr.LastPos then
                    local realDeltaVel = (curPos - tr.LastPos) / dt
                    local engineVel = root.AssemblyLinearVelocity or root.Velocity

                    local chosenVel = engineVel
                    if (engineVel - realDeltaVel).Magnitude > 28 then
                        chosenVel = realDeltaVel
                    end

                    local alpha = math_clamp(dt * 14, 0, 1)
                    tr.SmoothedVel = tr.SmoothedVel + (chosenVel - tr.SmoothedVel) * alpha
                    tr.Accel = (tr.SmoothedVel - tr.LastVel) / dt
                    tr.LastVel = tr.SmoothedVel
                end

                tr.LastPos = curPos
                tr.LastTime = now

                if Config.SmartResolver then
                    if tr.LastHealth and hum.Health < tr.LastHealth then
                        tr.ConsecutiveHits = tr.ConsecutiveHits + 1
                        tr.ConsecutiveMisses = 0
                        tr.PendingShot = false
                    elseif tr.PendingShot and (now - tr.ShotTimestamp) >= Config.ResolverMissTimeout then
                        tr.PendingShot = false
                        tr.ConsecutiveMisses = tr.ConsecutiveMisses + 1
                        tr.ResolverMode = (tr.ResolverMode % 6) + 1
                    end
                    tr.LastHealth = hum.Health
                end
            end
        end
    end
end


local function ComputeSmartPredictedPosition(plr, basePos, origin)
    if not Config.SmartPrediction or not plr then
        return basePos
    end

    local tr = PlayerTrackData[plr]
    if not tr then
        return basePos
    end

    local dist = (basePos - origin).Magnitude
    local speed = math_max(ActiveBallistics.Speed, 50)
    local grav = ActiveBallistics.Gravity
    local pingSec = Config.PingCompensation and ActiveBallistics.CachedPing or 0

    local tof = (dist / speed) + pingSec
    local vel = tr.SmoothedVel
    local acc = tr.Accel

    if Config.SmartResolver then
        local mode = tr.ResolverMode
        if mode == 1 then
            vel = tr.SmoothedVel + (acc * (tof * 0.25))
        elseif mode == 2 then
            vel = tr.LastVel
        elseif mode == 3 then
            vel = tr.SmoothedVel * 0.45
        elseif mode == 4 then
            vel = tr.SmoothedVel + (tr.RightVec * 6.5)
        elseif mode == 5 then
            vel = tr.SmoothedVel - (tr.RightVec * 6.5)
        elseif mode == 6 then
            vel = Vector3_new(0, tr.SmoothedVel.Y * 0.5, 0)
        end
    end

    local displacedPos = basePos + (vel * tof)
    tof = ((displacedPos - origin).Magnitude / speed) + pingSec

    local dropOffset = Vector3_new(0, 0.5 * grav * (tof * tof), 0)
    return basePos + (vel * tof) + dropOffset
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

local CharacterBoneCache = setmetatable({}, { __mode = "k" })

local VisRayParams = RaycastParams.new()
VisRayParams.FilterType = Enum.RaycastFilterType.Exclude
VisRayParams.IgnoreWater = true

local FilterArray = { nil, nil }

local function CastClear(origin, targetPos, targetChar)
    FilterArray[1] = LocalPlayer.Character
    FilterArray[2] = Camera
    VisRayParams.FilterDescendantsInstances = FilterArray
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

    if not CastClear(origin, cf.Position, char) then
        return false
    end

    local c1 = cf:PointToWorldSpace(Vector3_new( half.X,  half.Y, 0))
    local c2 = cf:PointToWorldSpace(Vector3_new(-half.X,  half.Y, 0))
    local c3 = cf:PointToWorldSpace(Vector3_new( half.X, -half.Y, 0))
    local c4 = cf:PointToWorldSpace(Vector3_new(-half.X, -half.Y, 0))

    local corners = { c1, c2, c3, c4 }
    for i = 1, 4 do
        local worldPt = corners[i]
        local _, onScreen = Camera:WorldToViewportPoint(worldPt)
        if not onScreen or not CastClear(origin, worldPt, char) then
            return false
        end
    end
    return true
end

local MultipointBuffer = {}

local function ResolveMultipointOnPart(part, char, mousePos, maxFov)
    Camera = workspace.CurrentCamera
    local origin = Camera.CFrame.Position
    local cf = part.CFrame
    local s = part.Size * (Config.MultipointScale * 0.5)

    table_clear(MultipointBuffer)
    MultipointBuffer[1] = cf.Position
    if Config.Multipoint then
        MultipointBuffer[2] = cf:PointToWorldSpace(Vector3_new( s.X,  s.Y, 0))
        MultipointBuffer[3] = cf:PointToWorldSpace(Vector3_new(-s.X,  s.Y, 0))
        MultipointBuffer[4] = cf:PointToWorldSpace(Vector3_new( s.X, -s.Y, 0))
        MultipointBuffer[5] = cf:PointToWorldSpace(Vector3_new(-s.X, -s.Y, 0))
        MultipointBuffer[6] = cf:PointToWorldSpace(Vector3_new(0,  s.Y, 0))
        MultipointBuffer[7] = cf:PointToWorldSpace(Vector3_new(0, -s.Y, 0))
    end

    local bestPt, bestDist = nil, maxFov
    for i = 1, #MultipointBuffer do
        local pt = MultipointBuffer[i]
        local scr, onScreen = Camera:WorldToViewportPoint(pt)
        if onScreen then
            local d = (Vector2_new(scr.X, scr.Y) - mousePos).Magnitude
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

    local cached = CharacterBoneCache[char]
    if not cached then
        cached = {}
        for group, aliases in pairs(PartMap) do
            for i = 1, #aliases do
                local p = char:FindFirstChild(aliases[i], true)
                if p and p:IsA("BasePart") then
                    cached[group] = p
                    break
                end
            end
        end
        CharacterBoneCache[char] = cached
    end

    for group, enabled in pairs(Config.TargetParts) do
        if enabled then
            local part = cached[group]
            if part and part.Parent then
                list[#list + 1] = part
            end
        end
    end
    return list
end

local CurrentTargetPlayer = nil
local CurrentTarget = nil
local CurrentTargetRawPos = nil
local CurrentTargetPos = nil
local CurrentTargetFullyExposed = false

local function GetClosestTarget()
    Camera = workspace.CurrentCamera
    if not Camera or not Config.SilentEnabled then return nil, nil, nil, nil, false end
    local bestDist = Config.FOV
    local bestPlr, bestPart, bestRawPos, bestPredPos, bestExposed = nil, nil, nil, nil, false
    local mousePos = UserInputService:GetMouseLocation()
    local camOrigin = Camera.CFrame.Position

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and (not Config.TeamCheck or not IsTeammate(plr)) then
            local char = plr.Character
            local parts = GetCandidateParts(char)
            for i = 1, #parts do
                local part = parts[i]
                local pt, dist = ResolveMultipointOnPart(part, char, mousePos, bestDist)
                if pt and dist then
                    bestDist = dist
                    bestPlr = plr
                    bestPart = part
                    bestRawPos = pt
                    bestPredPos = ComputeSmartPredictedPosition(plr, pt, camOrigin)
                    if Config.RequireFullExposure then
                        bestExposed = IsPartFullyExposed(part, char)
                    else
                        bestExposed = CastClear(camOrigin, pt, char)
                    end
                end
            end
        end
    end
    return bestPlr, bestPart, bestRawPos, bestPredPos, bestExposed
end


local ChamsFolder = ProtectInstance(Instance.new("Folder"))
ChamsFolder.Name = RandomStr(10)
ChamsFolder.Parent = SafeContainer

local PlayerHighlights = {}

local function UpdateChamsVisibility()
    for plr, hl in pairs(PlayerHighlights) do
        if hl and hl.Parent then
            if not Config.ChamsEnabled then
                hl.Enabled = false
            else
                local isMate = Config.TeamCheckESP and IsTeammate(plr)
                hl.Enabled = not isMate
                hl.FillColor = Config.ChamsFill
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
        hl.FillColor = Config.ChamsFill
        hl.OutlineColor = Config.ChamsOutline
        hl.FillTransparency = 0.45
        hl.OutlineTransparency = 0.1
        local isMate = Config.TeamCheckESP and IsTeammate(plr)
        hl.Enabled = Config.ChamsEnabled and (not isMate)
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ChamsFolder
        PlayerHighlights[plr] = hl
    end
    if plr.Character then task.spawn(OnChar, plr.Character) end
    plr.CharacterAdded:Connect(OnChar)
    plr:GetPropertyChangedSignal("Team"):Connect(UpdateChamsVisibility)
    plr:GetPropertyChangedSignal("TeamColor"):Connect(UpdateChamsVisibility)
end

for _, p in ipairs(Players:GetPlayers()) do ApplyChams(p) end
Players.PlayerAdded:Connect(ApplyChams)
Players.PlayerRemoving:Connect(function(p)
    PlayerHighlights[p] = nil
    PlayerTrackData[p] = nil
    local c = ChamsFolder:FindFirstChild(p.Name)
    if c then c:Destroy() end
end)

LocalPlayer:GetPropertyChangedSignal("Team"):Connect(UpdateChamsVisibility)
LocalPlayer:GetPropertyChangedSignal("TeamColor"):Connect(UpdateChamsVisibility)

task.spawn(function()
    while task.wait(1.0) do
        UpdateChamsVisibility()
    end
end)

local FOVCircle = Drawing.new("Circle")
FOVCircle.Radius = Config.FOV
FOVCircle.Color = Color3.fromRGB(255, 50, 50)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Visible = Config.ShowFOV


local ScreenGui = ProtectInstance(Instance.new("ScreenGui"))
ScreenGui.Name = RandomStr(14)
ScreenGui.DisplayOrder = 2147483647
ScreenGui.IgnoreGuiInset = true
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
ScreenGui.Parent = SafeContainer

local MainFrame = ProtectInstance(Instance.new("Frame"))
MainFrame.Size = UDim2.new(0, 410, 0, 560)
MainFrame.Position = UDim2.new(0.5, -205, 0.5, -280)
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
Header.Size = UDim2.new(1, -24, 0, 32)
Header.Position = UDim2.new(0, 12, 0, 6)
Header.BackgroundTransparency = 1
Header.Text = "LIQUID GLASS // 01 RAYCAST SILENT V2"
Header.TextColor3 = Color3.fromRGB(245, 248, 255)
Header.Font = Enum.Font.GothamBold
Header.TextSize = 14
Header.TextXAlignment = Enum.TextXAlignment.Left

local SubHeader = ProtectInstance(Instance.new("TextLabel", MainFrame))
SubHeader.Size = UDim2.new(1, -24, 0, 16)
SubHeader.Position = UDim2.new(0, 12, 0, 26)
SubHeader.BackgroundTransparency = 1
SubHeader.Text = "[DELETE] Menu | [F] Autofire: OFF | Resolver: M1"
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
Scroll.CanvasSize = UDim2.new(0, 0, 0, 950)

local ListLayout = ProtectInstance(Instance.new("UIListLayout", Scroll))
ListLayout.Padding = UDim.new(0, 6)
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder

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
    local resMode = 1
    if CurrentTargetPlayer and PlayerTrackData[CurrentTargetPlayer] then
        resMode = PlayerTrackData[CurrentTargetPlayer].ResolverMode
    end
    SubHeader.Text = string.format(
        "[%s] Menu | [%s] Autofire: %s | Vel: %d | Res: M%d",
        Config.MenuKey.Name,
        Config.AutoFireKey.Name,
        Config.AutoFire and "ON" or "OFF",
        math_floor(ActiveBallistics.Speed),
        resMode
    )
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
        local rel = math_clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local val = math_floor(minVal + (maxVal - minVal) * rel + 0.5)
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

CreateToggle("TeamCheck (Silent Aim & Autofire)", Config.TeamCheck, function(v) Config.TeamCheck = v end)
CreateToggle("TeamCheck ESP (Enemies Red Only)", Config.TeamCheckESP, function(v)
    Config.TeamCheckESP = v
    UpdateChamsVisibility()
end)
CreateToggle("Deep Team Scan (Folders/Attrs/Colors)", Config.DeepTeamScan, function(v)
    Config.DeepTeamScan = v
    UpdateChamsVisibility()
end)


CreateToggle("Smart Prediction (Kinematics + Drop)", Config.SmartPrediction, function(v) Config.SmartPrediction = v end)
CreateToggle("Auto Analyze Weapon Ballistics", Config.AutoBallistics, function(v)
    Config.AutoBallistics = v
    ActiveBallistics.LastScan = 0
    ScanToolBallistics()
    RefreshStatusText()
end)
CreateSlider("Default Bullet Speed", 100, 5000, Config.DefaultBulletSpeed, " s/s", function(v)
    Config.DefaultBulletSpeed = v
    if not Config.AutoBallistics then ActiveBallistics.Speed = v end
    RefreshStatusText()
end)
CreateSlider("Default Bullet Gravity", 0, 400, Config.BulletGravity, " s/s²", function(v)
    Config.BulletGravity = v
    if not Config.AutoBallistics then ActiveBallistics.Gravity = v end
end)
CreateToggle("Ping Compensation", Config.PingCompensation, function(v) Config.PingCompensation = v end)
CreateToggle("Smart Resolver (Lock on Hit / Switch on Miss)", Config.SmartResolver, function(v) Config.SmartResolver = v end)

CreateToggle("Multipoint Scanning", Config.Multipoint, function(v) Config.Multipoint = v end)
CreateSlider("Multipoint Scale", 20, 95, math_floor(Config.MultipointScale * 100), "%", function(v) Config.MultipointScale = v / 100 end)
CreateToggle("WallCheck (Visible Only)", Config.WallCheck, function(v) Config.WallCheck = v end)
CreateToggle("Ignore ForceField", Config.IgnoreForceField, function(v) Config.IgnoreForceField = v end)
CreateToggle("Show FOV Circle", Config.ShowFOV, function(v) Config.ShowFOV = v; FOVCircle.Visible = v end)
CreateToggle("Chams ESP", Config.ChamsEnabled, function(v)
    Config.ChamsEnabled = v
    UpdateChamsVisibility()
end)

for _, bone in ipairs({ "Head", "Torso", "HumanoidRootPart", "LeftArm", "RightArm", "LeftLeg", "RightLeg" }) do
    CreateToggle("Target Bone: " .. bone, Config.TargetParts[bone], function(v)
        Config.TargetParts[bone] = v
    end)
end

ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Scroll.CanvasSize = UDim2.new(0, 0, 0, ListLayout.AbsoluteContentSize.Y + 24)
end)
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


local function RegisterShotFired(plr)
    if plr and Config.SmartResolver then
        local tr = PlayerTrackData[plr]
        if tr then
            tr.PendingShot = true
            tr.ShotTimestamp = os_clock()
        end
    end
end

local function TriggerMouseClick()
    if mouse1press and mouse1release then
        mouse1press()
        task.wait(0.01)
        mouse1release()
    end
end

RunService.Heartbeat:Connect(UpdateTargetKinematics)

RunService.RenderStepped:Connect(function()
    FOVCircle.Position = UserInputService:GetMouseLocation()
    CurrentTargetPlayer, CurrentTarget, CurrentTargetRawPos, CurrentTargetPos, CurrentTargetFullyExposed = GetClosestTarget()
    RefreshStatusText()

    if Config.AutoFire and not IsClicking and not ScreenGui.Enabled then
        if CurrentTarget and CurrentTargetPos and CurrentTargetFullyExposed then
            local now = os_clock() * 1000
            if (now - LastShotClock) >= Config.FireInterval then
                if math_random(1, 100) <= Config.HitChance then
                    LastShotClock = now
                    IsClicking = true
                    RegisterShotFired(CurrentTargetPlayer)
                    task.spawn(function()
                        TriggerMouseClick()
                        IsClicking = false
                    end)
                end
            end
        end
    end
end)


local setnamecallmethod_fn = setnamecallmethod
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
            if method == "Raycast" or method == "Spherecast" then
                if math_random(1, 100) <= Config.HitChance then
                    local args = { ... }
                    local dirIdx = (method == "Raycast") and 2 or 3
                    local origin = args[1]
                    local dir = args[dirIdx]
                    if typeof(origin) == "Vector3" and typeof(dir) == "Vector3" then
                        
                        if dir.Magnitude >= 15 then
                            local basePt = CurrentTargetRawPos or CurrentTargetPos
                            local targetPt = ComputeSmartPredictedPosition(CurrentTargetPlayer, basePt, origin)
                            RegisterShotFired(CurrentTargetPlayer)
                            local delta = targetPt - origin
                            local dist = delta.Magnitude
                            if dist > 0.001 then
                                local mag = math_max(dir.Magnitude, dist + 15)
                                args[dirIdx] = (delta / dist) * mag
                                if setnamecallmethod_fn then
                                    setnamecallmethod_fn(method)
                                end
                                return oldNamecall(self, unpack_fn(args))
                            end
                        end
                    end
                end
            end
        end
    end
    if setnamecallmethod_fn then
        setnamecallmethod_fn(method)
    end
    return oldNamecall(self, ...)
end))
