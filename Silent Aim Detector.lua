-- 00_silent_detector.lua
-- Uninject Key: Enum.KeyCode.Delete

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera

local Active = true
local Connections = {}
local Drawings = {}
local Restorers = {}


local function BypassAdonis()
    if not getgc or not hookfunction or not newcclosure then return end
    for _, v in ipairs(getgc(true)) do
        if type(v) == "table" then
            local det = rawget(v, "Detected")
            local kill = rawget(v, "Kill")
            if type(det) == "function" and islclosure(det) and not isexecutorclosure(det) then
                pcall(function() hookfunction(det, newcclosure(function() return true end)) end)
            end
            if type(kill) == "function" and islclosure(kill) and not isexecutorclosure(kill) then
                pcall(function() hookfunction(kill, newcclosure(function() return nil end)) end)
            end
            if rawget(v, "Variables") and rawget(v, "Process") and rawget(v, "Anti") then
                local anti = rawget(v, "Anti")
                if type(anti) == "table" then
                    for _, func in pairs(anti) do
                        if type(func) == "function" and islclosure(func) and not isexecutorclosure(func) then
                            pcall(function() hookfunction(func, newcclosure(function() return true end)) end)
                        end
                    end
                end
            end
        end
    end
end
pcall(BypassAdonis)


local RigProfile = {
    PlaceRigType = "DETECTING...",
    CustomModels = false,
    NonQueryableHeads = 0
}

local function ScanPlaceRigs()
    local r15, r6, custom, nonQuery = 0, 0, 0, 0
    for _, plr in ipairs(Players:GetPlayers()) do
        local char = plr.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local head = char:FindFirstChild("Head", true)
            if head and head:IsA("BasePart") and not head.CanQuery then
                nonQuery = nonQuery + 1
            end
            if hum then
                if hum.RigType == Enum.HumanoidRigType.R15 then
                    if char:FindFirstChild("UpperTorso") then r15 = r15 + 1 else custom = custom + 1 end
                elseif hum.RigType == Enum.HumanoidRigType.R6 then
                    if char:FindFirstChild("Torso") then r6 = r6 + 1 else custom = custom + 1 end
                end
            else
                custom = custom + 1
            end
        end
    end
    RigProfile.NonQueryableHeads = nonQuery
    RigProfile.CustomModels = custom > 0
    if custom > 0 then
        RigProfile.PlaceRigType = string.format("CUSTOM/HYBRID (R15:%d R6:%d Cust:%d | NonQueryHead:%d)", r15, r6, custom, nonQuery)
    elseif r15 >= r6 and r15 > 0 then
        RigProfile.PlaceRigType = string.format("R15 (NonQueryHead:%d)", nonQuery)
    elseif r6 > 0 then
        RigProfile.PlaceRigType = string.format("R6 (NonQueryHead:%d)", nonQuery)
    else
        RigProfile.PlaceRigType = "WAITING FOR SPAWN"
    end
end
task.spawn(function()
    while Active do
        pcall(ScanPlaceRigs)
        task.wait(1.5)
    end
end)


local BlacklistScriptKeywords = {
    "camera", "popcan", "popper", "transparency", "footstep", "sound", "material",
    "animate", "ik", "ragdoll", "weather", "rain", "particle", "vfx", "fx",
    "lighting", "shadow", "bubblechat", "chat", "freecam", "controlmodule", "water"
}

local WeaponScriptKeywords = {
    "gun", "weapon", "shoot", "fire", "bullet", "client", "tool", "combat",
    "ray", "hit", "damage", "sniper", "rifle", "pistol", "turret", "blaster",
    "fastcast", "acs", "fe_gun", "fegun", "framework", "sweps", "swep", "castrays", "castlongray"
}

local function ClassifyScriptContext(scr)
    if not scr or typeof(scr) ~= "Instance" then return "UNKNOWN", 0 end
    local fullName = scr:GetFullName():lower()
    local name = scr.Name:lower()

    for _, bad in ipairs(BlacklistScriptKeywords) do
        if name:find(bad, 1, true) or fullName:find("playerlist", 1, true) or fullName:find("playermodule", 1, true) then
            return "VFX_OR_SYSTEM", -100
        end
    end

    local score = 0
    local char = LocalPlayer.Character
    if char and scr:IsDescendantOf(char) then
        score = score + 45
        if scr:FindFirstAncestorOfClass("Tool") then score = score + 50 end
    end
    if scr:FindFirstAncestorOfClass("Tool") then score = score + 40 end

    for _, kw in ipairs(WeaponScriptKeywords) do
        if fullName:find(kw, 1, true) then
            score = score + 30
            break
        end
    end

    for level = 2, 6 do
        local fnName = debug.info and debug.info(level, "n")
        if fnName and #fnName > 0 then
            local lowFn = fnName:lower()
            for _, bad in ipairs(BlacklistScriptKeywords) do
                if lowFn:find(bad, 1, true) then return "VFX_OR_SYSTEM", -100 end
            end
            for _, kw in ipairs(WeaponScriptKeywords) do
                if lowFn:find(kw, 1, true) then score = score + 30 end
            end
        end
    end

    local m1Down = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
    local hasTool = char and char:FindFirstChildOfClass("Tool") ~= nil
    if m1Down then score = score + 35 end
    if hasTool then score = score + 20 end

    if score >= 35 then return "WEAPON", score end
    return "AMBIENT", score
end

local function IsWeaponRayGeometry(origin, direction)
    if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then return false, 0 end
    local mag = direction.Magnitude
    if mag < 15 and direction.Unit.Y < -0.8 then return false, -50 end

    local camPos = Camera and Camera.CFrame.Position or Vector3.zero
    local char = LocalPlayer.Character
    local head = char and char:FindFirstChild("Head", true)
    local root = char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)

    local nearCamera = (origin - camPos).Magnitude < 18
    local nearCharacter = (head and head:IsA("BasePart") and (origin - head.Position).Magnitude < 18)
        or (root and root:IsA("BasePart") and (origin - root.Position).Magnitude < 18)

    if not nearCamera and not nearCharacter then return false, -40 end

    local geoScore = 0
    if mag >= 40 then geoScore = geoScore + 35
    elseif mag >= 18 then geoScore = geoScore + 15
    else geoScore = geoScore - 20 end

    if Camera then
        local dot = direction.Unit:Dot(Camera.CFrame.LookVector)
        if dot > 0.45 then geoScore = geoScore + 25 end
    end
    return geoScore > 0, geoScore
end


local Telemetry = {
    ACS_Detected = false,
    ACS_Details = "",
    Blaster_Detected = false,
    Blaster_Details = "",
    Scores = {
        ["01_raycast_silent.lua"] = 0,
        ["02_findpartonray_silent.lua"] = 0,
        ["03_mouse_index_silent.lua"] = 0,
        ["04_viewport_point_to_ray_silent.lua"] = 0,
        ["05_acs_engine_silent.lua"] = 0,
        ["06_ray_constructor_hookfunction.lua"] = 0,
        ["07_hitbox_expander_silent.lua"] = 10,
        ["08_spherecast_blaster_silent.lua"] = 0,
    },
    WeaponHits = {
        Raycast = 0,
        Spherecast = 0,
        FindPartOnRay = 0,
        MouseIndex = 0,
        ViewportRay = 0,
        RayNew = 0,
        BlasterShoot = 0
    },
    IgnoredVFXRays = 0,
    LastWeaponScript = "None (Hold Gun & Shoot M1)",
    LastMethodTriggered = "Scanning...",
    BestScript = "07_hitbox_expander_silent.lua",
    BestReason = "Waiting for weapon fire (Press M1 with gun equipped)"
}

local function RecomputeRecommendation()
    local bestName = "07_hitbox_expander_silent.lua"
    local bestScore = Telemetry.Scores[bestName]

    for scriptFile, sc in pairs(Telemetry.Scores) do
        if sc > bestScore then
            bestScore = sc
            bestName = scriptFile
        end
    end

    Telemetry.BestScript = bestName

    if bestName == "08_spherecast_blaster_silent.lua" then
        Telemetry.BestReason = "Spherecast / Blaster Hitscan Detected (" .. Telemetry.Blaster_Details .. ") -> Hook Spherecast + Shoot Remote"
    elseif bestName == "05_acs_engine_silent.lua" then
        Telemetry.BestReason = "ACS Engine Detected (" .. Telemetry.ACS_Details .. ") -> Hook CastRay + Remotes"
    elseif bestName == "01_raycast_silent.lua" then
        Telemetry.BestReason = "Weapon calls workspace:Raycast / Spherecast on fire (Updated 01 supports both)"
    elseif bestName == "02_findpartonray_silent.lua" then
        Telemetry.BestReason = "Weapon uses Legacy FindPartOnRay* + Ray.new"
    elseif bestName == "04_viewport_point_to_ray_silent.lua" then
        Telemetry.BestReason = "Weapon generates rays via Camera:ViewportPointToRay/ScreenPointToRay"
    elseif bestName == "03_mouse_index_silent.lua" then
        Telemetry.BestReason = "Weapon reads Mouse.Hit / Mouse.Target / Mouse.UnitRay directly"
    elseif bestName == "06_ray_constructor_hookfunction.lua" then
        Telemetry.BestReason = "Weapon constructs Ray.new directly without standard workspace namecall"
    else
        Telemetry.BestReason = "No client ray hooks triggered on fire -> Use 07_hitbox_expander_silent.lua"
    end
end

local function RunStaticDeepScan()
    
    local acsEngine = ReplicatedStorage:FindFirstChild("ACS_Engine")
        or ReplicatedStorage:FindFirstChild("ACS_Client")
        or workspace:FindFirstChild("ACS_WorkSpace")
    if acsEngine then
        Telemetry.ACS_Detected = true
        Telemetry.ACS_Details = "Found " .. acsEngine.Name
        Telemetry.Scores["05_acs_engine_silent.lua"] = Telemetry.Scores["05_acs_engine_silent.lua"] + 500
    end

    
    local blasterFolder = ReplicatedStorage:FindFirstChild("Blaster")
    if blasterFolder then
        Telemetry.Blaster_Detected = true
        Telemetry.Blaster_Details = "ReplicatedStorage.Blaster (castRays + Shoot Remote)"
        Telemetry.Scores["08_spherecast_blaster_silent.lua"] = Telemetry.Scores["08_spherecast_blaster_silent.lua"] + 600
        Telemetry.Scores["01_raycast_silent.lua"] = Telemetry.Scores["01_raycast_silent.lua"] + 250
    end

    if getgc and debug.getinfo then
        for _, v in ipairs(getgc(true)) do
            if type(v) == "function" and islclosure(v) and not isexecutorclosure(v) then
                local ok, info = pcall(debug.getinfo, v)
                if ok and info and info.name then
                    local fnName = tostring(info.name)
                    local src = tostring(info.source or ""):lower()
                    if fnName == "castRays" or fnName == "castLongRay" then
                        Telemetry.Blaster_Detected = true
                        Telemetry.Blaster_Details = "GC Function: " .. fnName
                        Telemetry.Scores["08_spherecast_blaster_silent.lua"] = Telemetry.Scores["08_spherecast_blaster_silent.lua"] + 500
                    elseif fnName == "CastRay" or fnName == "CreateBullet" or fnName == "HitEffect" then
                        if src:find("acs") or src:find("fastcast") or src:find("gun") then
                            Telemetry.ACS_Detected = true
                            Telemetry.ACS_Details = "GC Function: " .. fnName
                            Telemetry.Scores["05_acs_engine_silent.lua"] = Telemetry.Scores["05_acs_engine_silent.lua"] + 400
                        end
                    end
                end
            end
        end
    end
    RecomputeRecommendation()
end
task.spawn(RunStaticDeepScan)


local LegacyRayMethods = {
    FindPartOnRay = true,
    FindPartOnRayWithIgnoreList = true,
    FindPartOnRayWithWhitelist = true
}

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if Active and not checkcaller() then
        local method = getnamecallmethod()
        local args = {...}

        if self == workspace then
            if method == "Raycast" then
                local origin, dir = args[1], args[2]
                local isWepGeo, geoScore = IsWeaponRayGeometry(origin, dir)
                local caller = getcallingscript and getcallingscript()
                local kind, scrScore = ClassifyScriptContext(caller)

                if kind ~= "VFX_OR_SYSTEM" and isWepGeo and (scrScore + geoScore >= 45) then
                    Telemetry.WeaponHits.Raycast = Telemetry.WeaponHits.Raycast + 1
                    Telemetry.Scores["01_raycast_silent.lua"] = Telemetry.Scores["01_raycast_silent.lua"] + 55
                    Telemetry.LastWeaponScript = caller and caller:GetFullName() or "Weapon Thread"
                    Telemetry.LastMethodTriggered = "workspace:Raycast (Mag: " .. math.floor(dir.Magnitude) .. ")"
                    RecomputeRecommendation()
                else
                    Telemetry.IgnoredVFXRays = Telemetry.IgnoredVFXRays + 1
                end

            elseif method == "Spherecast" or method == "Blockcast" then
               
                local rawOrigin = args[1]
                local origin = typeof(rawOrigin) == "CFrame" and rawOrigin.Position or rawOrigin
                local dir = args[3]
                local isWepGeo, geoScore = IsWeaponRayGeometry(origin, dir)
                local caller = getcallingscript and getcallingscript()
                local kind, scrScore = ClassifyScriptContext(caller)

                if kind ~= "VFX_OR_SYSTEM" and isWepGeo and (scrScore + geoScore >= 35) then
                    Telemetry.WeaponHits.Spherecast = Telemetry.WeaponHits.Spherecast + 1
                    Telemetry.Blaster_Details = method .. " (Radius/Size: " .. tostring(args[2]) .. ")"
                    Telemetry.Scores["08_spherecast_blaster_silent.lua"] = Telemetry.Scores["08_spherecast_blaster_silent.lua"] + 85
                    Telemetry.Scores["01_raycast_silent.lua"] = Telemetry.Scores["01_raycast_silent.lua"] + 65
                    Telemetry.LastWeaponScript = caller and caller:GetFullName() or "Spherecast Caller"
                    Telemetry.LastMethodTriggered = "workspace:" .. method .. " (Mag: " .. math.floor(dir.Magnitude) .. ")"
                    RecomputeRecommendation()
                else
                    Telemetry.IgnoredVFXRays = Telemetry.IgnoredVFXRays + 1
                end

            elseif LegacyRayMethods[method] then
                local ray = args[1]
                if typeof(ray) == "Ray" then
                    local isWepGeo, geoScore = IsWeaponRayGeometry(ray.Origin, ray.Direction)
                    local caller = getcallingscript and getcallingscript()
                    local kind, scrScore = ClassifyScriptContext(caller)

                    if kind ~= "VFX_OR_SYSTEM" and isWepGeo and (scrScore + geoScore >= 45) then
                        Telemetry.WeaponHits.FindPartOnRay = Telemetry.WeaponHits.FindPartOnRay + 1
                        Telemetry.Scores["02_findpartonray_silent.lua"] = Telemetry.Scores["02_findpartonray_silent.lua"] + 55
                        Telemetry.Scores["06_ray_constructor_hookfunction.lua"] = Telemetry.Scores["06_ray_constructor_hookfunction.lua"] + 30
                        Telemetry.LastWeaponScript = caller and caller:GetFullName() or "Weapon Thread"
                        Telemetry.LastMethodTriggered = "workspace:" .. method
                        RecomputeRecommendation()
                    else
                        Telemetry.IgnoredVFXRays = Telemetry.IgnoredVFXRays + 1
                    end
                end
            end

        elseif self == Camera and (method == "ViewportPointToRay" or method == "ScreenPointToRay") then
            local caller = getcallingscript and getcallingscript()
            local kind, scrScore = ClassifyScriptContext(caller)
            if kind == "WEAPON" and scrScore >= 40 then
                Telemetry.WeaponHits.ViewportRay = Telemetry.WeaponHits.ViewportRay + 1
                Telemetry.Scores["04_viewport_point_to_ray_silent.lua"] = Telemetry.Scores["04_viewport_point_to_ray_silent.lua"] + 60
                Telemetry.LastWeaponScript = caller and caller:GetFullName() or "Camera Ray Caller"
                Telemetry.LastMethodTriggered = "Camera:" .. method
                RecomputeRecommendation()
            end

        elseif method == "FireServer" and typeof(self) == "Instance" and self:IsA("RemoteEvent") then
            if self.Name == "Shoot" or self.Name == "ReplicateShot" or (typeof(args[3]) == "CFrame" and type(args[4]) == "table" and type(args[5]) == "table") then
                Telemetry.WeaponHits.BlasterShoot = Telemetry.WeaponHits.BlasterShoot + 1
                Telemetry.Blaster_Details = "Remote: " .. self:GetFullName()
                Telemetry.Scores["08_spherecast_blaster_silent.lua"] = Telemetry.Scores["08_spherecast_blaster_silent.lua"] + 120
                Telemetry.LastMethodTriggered = "RemoteEvent:" .. self.Name
                RecomputeRecommendation()
            end
        end
    end
    return oldNamecall(self, ...)
end))

table.insert(Restorers, function()
    pcall(hookmetamethod, game, "__namecall", oldNamecall)
end)

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
    if Active and not checkcaller() and self == Mouse then
        if key == "Hit" or key == "Target" or key == "UnitRay" then
            local caller = getcallingscript and getcallingscript()
            local kind, scrScore = ClassifyScriptContext(caller)
            if kind == "WEAPON" and scrScore >= 50 then
                Telemetry.WeaponHits.MouseIndex = Telemetry.WeaponHits.MouseIndex + 1
                Telemetry.Scores["03_mouse_index_silent.lua"] = Telemetry.Scores["03_mouse_index_silent.lua"] + 35
                Telemetry.LastWeaponScript = caller and caller:GetFullName() or "Mouse Caller"
                Telemetry.LastMethodTriggered = "Mouse." .. tostring(key)
                RecomputeRecommendation()
            end
        end
    end
    return oldIndex(self, key)
end))

table.insert(Restorers, function()
    pcall(hookmetamethod, game, "__index", oldIndex)
end)

if Ray and Ray.new and hookfunction then
    local oldRayNew
    oldRayNew = hookfunction(Ray.new, newcclosure(function(origin, direction)
        if Active and not checkcaller() and typeof(origin) == "Vector3" and typeof(direction) == "Vector3" then
            local isWepGeo, geoScore = IsWeaponRayGeometry(origin, direction)
            local caller = getcallingscript and getcallingscript()
            local kind, scrScore = ClassifyScriptContext(caller)

            if kind ~= "VFX_OR_SYSTEM" and isWepGeo and (scrScore + geoScore >= 55) then
                Telemetry.WeaponHits.RayNew = Telemetry.WeaponHits.RayNew + 1
                Telemetry.Scores["06_ray_constructor_hookfunction.lua"] = Telemetry.Scores["06_ray_constructor_hookfunction.lua"] + 25
                RecomputeRecommendation()
            end
        end
        return oldRayNew(origin, direction)
    end))

    table.insert(Restorers, function()
        pcall(hookfunction, Ray.new, oldRayNew)
    end)
end


local function CreateDraw(class, props)
    local obj = Drawing.new(class)
    for k, v in pairs(props) do obj[k] = v end
    table.insert(Drawings, obj)
    return obj
end

local PanelWidth = 720
local PanelHeight = 138

local BgBox = CreateDraw("Square", {
    Filled = true,
    Color = Color3.fromRGB(14, 14, 20),
    Transparency = 0.88,
    Thickness = 1,
    Visible = true
})

local BorderBox = CreateDraw("Square", {
    Filled = false,
    Color = Color3.fromRGB(0, 255, 160),
    Transparency = 1,
    Thickness = 1.5,
    Visible = true
})

local TitleText = CreateDraw("Text", {
    Size = 16,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(0, 255, 160),
    Text = "[ SILENT AIM & RIG DEEP DETECTOR | PRESS DELETE TO UNINJECT ]",
    Visible = true
})

local RecText = CreateDraw("Text", {
    Size = 18,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(255, 230, 60),
    Text = "RECOMMENDED SCRIPT: Scanning...",
    Visible = true
})

local ReasonText = CreateDraw("Text", {
    Size = 14,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(210, 210, 220),
    Text = "Reason: Equip weapon & shoot M1 to profile hitscan/raycast",
    Visible = true
})

local RigText = CreateDraw("Text", {
    Size = 14,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(255, 150, 220),
    Text = "Place Rig Profile: Scanning...",
    Visible = true
})

local CallerText = CreateDraw("Text", {
    Size = 14,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(140, 200, 255),
    Text = "Weapon Script: None | Last Trigger: None",
    Visible = true
})

local StatsText = CreateDraw("Text", {
    Size = 13,
    Center = true,
    Outline = true,
    Color = Color3.fromRGB(160, 160, 175),
    Text = "Counters -> Raycast: 0 | Spherecast: 0 | Blaster: 0 | FindPart: 0 | Mouse: 0 | CamRay: 0",
    Visible = true
})

local renderConn = RunService.RenderStepped:Connect(function()
    if not Active then return end
    Camera = workspace.CurrentCamera
    if not Camera then return end

    local vp = Camera.ViewportSize
    local startX = (vp.X / 2) - (PanelWidth / 2)
    local startY = 12

    BgBox.Position = Vector2.new(startX, startY)
    BgBox.Size = Vector2.new(PanelWidth, PanelHeight)
    BorderBox.Position = Vector2.new(startX, startY)
    BorderBox.Size = Vector2.new(PanelWidth, PanelHeight)

    local centerX = vp.X / 2
    TitleText.Position = Vector2.new(centerX, startY + 6)
    RecText.Position = Vector2.new(centerX, startY + 26)
    ReasonText.Position = Vector2.new(centerX, startY + 48)
    RigText.Position = Vector2.new(centerX, startY + 68)
    CallerText.Position = Vector2.new(centerX, startY + 88)
    StatsText.Position = Vector2.new(centerX, startY + 110)

    RecText.Text = "USE SCRIPT:  >>  " .. Telemetry.BestScript .. "  <<"
    ReasonText.Text = "Verdict: " .. Telemetry.BestReason
    RigText.Text = "Place Rig Mode: " .. RigProfile.PlaceRigType
    CallerText.Text = string.format("Weapon Script: %s  |  Active Method: %s",
        tostring(Telemetry.LastWeaponScript),
        tostring(Telemetry.LastMethodTriggered)
    )
    StatsText.Text = string.format(
        "Calls -> Raycast: %d | Spherecast: %d | BlasterRemote: %d | FindPart: %d | Mouse: %d | CamRay: %d [VFX Ignored: %d]",
        Telemetry.WeaponHits.Raycast,
        Telemetry.WeaponHits.Spherecast,
        Telemetry.WeaponHits.BlasterShoot,
        Telemetry.WeaponHits.FindPartOnRay,
        Telemetry.WeaponHits.MouseIndex,
        Telemetry.WeaponHits.ViewportRay,
        Telemetry.IgnoredVFXRays
    )
end)
table.insert(Connections, renderConn)


local function UninjectDetector()
    if not Active then return end
    Active = false
    for _, conn in ipairs(Connections) do
        if conn and conn.Connected then pcall(function() conn:Disconnect() end) end
    end
    table.clear(Connections)
    for _, restoreFn in ipairs(Restorers) do pcall(restoreFn) end
    table.clear(Restorers)
    for _, drawObj in ipairs(Drawings) do
        pcall(function() drawObj.Visible = false; drawObj:Remove() end)
    end
    table.clear(Drawings)
end

local inputConn = UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.Delete then UninjectDetector() end
end)
table.insert(Connections, inputConn)