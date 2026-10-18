-- 08_spherecast_blaster_silent_v2.lua
-- Method: Adonis/Client AC Bypass + Universal Cast Redirection + Dynamic Remote Spoofer + Deep TeamCheck ESP (Home toggle)
--Esp teamcheck---HOME
local cloneref = cloneref or function(o) return o end
local newcclosure = newcclosure or function(f) return f end
local hookmetamethod = hookmetamethod or function(obj, mt, fn)
    local raw = getrawmetatable(obj)
    setreadonly(raw, false)
    local old = raw[mt]
    raw[mt] = fn
    setreadonly(raw, true)
    return old
end
local checkcaller = checkcaller or function() return false end
local getnamecallmethod = getnamecallmethod or function() return "" end

local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local CoreGui = cloneref(game:GetService("CoreGui"))
local Workspace = cloneref(game:GetService("Workspace"))
local StarterGui = cloneref(game:GetService("StarterGui"))

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Config = {
    FOV = 200,
    TeamCheck = true, -- Toggled via Enum.KeyCode.Home
    IgnoreForceField = true,
    WallCheck = false,
    ChamsFillEnemy = Color3.fromRGB(0, 255, 220),
    ChamsFillTeam = Color3.fromRGB(0, 255, 100),
    ChamsOutline = Color3.fromRGB(255, 255, 255),
    ShowTeamESP = false -- When TeamCheck is ON, hide teammates completely
}

--------------------------------------------------------------------------------
-- 1. ADONIS & CLIENT ANTI-CHEAT NEUTRALIZER (GC + Metamethod Shield)
--------------------------------------------------------------------------------
local function BypassAntiCheats()
    if not getgc or not debug or not hookfunction then return end

    pcall(function()
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" then
                -- Adonis client table signatures: Detected, Kill, Kick, indexInstance
                local detected = rawget(v, "Detected")
                local kill = rawget(v, "Kill")
                local vars = rawget(v, "Variables")
                local idxInst = rawget(v, "indexInstance")

                if typeof(detected) == "function" and (typeof(kill) == "function" or vars ~= nil) then
                    hookfunction(detected, newcclosure(function(action, info, nocrash)
                        if rawequal(action, "_") or rawequal(info, "_") then
                            return true
                        end
                        return task.wait(9e9)
                    end))
                    if typeof(kill) == "function" then
                        hookfunction(kill, newcclosure(function()
                            return task.wait(9e9)
                        end))
                    end
                end

                -- Adonis metatable / kick detector array
                if type(idxInst) == "table" and idxInst[1] == "kick" then
                    for k, sub in pairs(v) do
                        if type(sub) == "table" and type(sub[2]) == "function" then
                            hookfunction(sub[2], newcclosure(function()
                                return false
                            end))
                        end
                    end
                end
            elseif type(v) == "function" and islclosure(v) and not isexecutorclosure(v) then
                local ok, consts = pcall(debug.getconstants, v)
                if ok and consts then
                    local hasAdonisSig = false
                    for _, c in ipairs(consts) do
                        if c == "Adonis" or c == "Detected" or c == "Pcall" or c == "Security" then
                            hasAdonisSig = true
                            break
                        end
                    end
                    if hasAdonisSig then
                        local info = debug.getinfo(v)
                        if info and info.name == "Detected" then
                            hookfunction(v, newcclosure(function() return true end))
                        end
                    end
                end
            end
        end
    end)
end

BypassAntiCheats()

--------------------------------------------------------------------------------
-- 2. DEEP TEAM CHECK RESOLVER (Properties, Attributes, Folders, Leaderstats, Color)
--------------------------------------------------------------------------------
local function GetCustomTeamIdentifier(plr)
    if not plr then return nil end

    -- 1. Standard Roblox Team & TeamColor
    if plr.Team ~= nil then
        return "TeamObj_" .. tostring(plr.Team)
    end
    if not plr.Neutral and plr.TeamColor then
        return "TeamColor_" .. tostring(plr.TeamColor)
    end

    -- 2. Player Attributes
    local attrNames = { "Team", "Faction", "Squad", "Side", "Group", "TeamId", "TeamName", "Role", "Clan" }
    for _, attr in ipairs(attrNames) do
        local val = plr:GetAttribute(attr)
        if val ~= nil and val ~= "" and val ~= "None" and val ~= "FFA" then
            return "PlrAttr_" .. attr .. "_" .. tostring(val)
        end
    end

    local char = plr.Character
    if char then
        -- 3. Character Attributes
        for _, attr in ipairs(attrNames) do
            local val = char:GetAttribute(attr)
            if val ~= nil and val ~= "" and val ~= "None" and val ~= "FFA" then
                return "CharAttr_" .. attr .. "_" .. tostring(val)
            end
        end

        -- 4. ValueObjects inside Character or Player
        for _, name in ipairs(attrNames) do
            local obj = char:FindFirstChild(name) or plr:FindFirstChild(name)
            if obj and (obj:IsA("StringValue") or obj:IsA("IntValue") or obj:IsA("ObjectValue") or obj:IsA("BrickColorValue")) then
                if obj.Value ~= nil and tostring(obj.Value) ~= "" and tostring(obj.Value) ~= "None" then
                    return "ValObj_" .. name .. "_" .. tostring(obj.Value)
                end
            end
        end

        -- 5. Parent Folder Hierarchy (e.g. workspace.Characters.BlueTeam.Player)
        local parent = char.Parent
        if parent and parent ~= Workspace and parent.Name ~= "Characters" and parent.Name ~= "Players" and parent.Name ~= "Entities" and parent.Name ~= "Live" then
            return "Folder_" .. parent.Name
        end

        -- 6. Torso / Root Color fallback for games that color-code teams without Teams service
        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        if torso and torso:IsA("BasePart") then
            local tag = torso:FindFirstChild("TeamColor") or char:FindFirstChild("TeamColor")
            if tag and tag:IsA("BrickColorValue") then
                return "TorsoTag_" .. tostring(tag.Value)
            end
        end
    end

    -- 7. Leaderstats Team Value
    local ls = plr:FindFirstChild("leaderstats")
    if ls then
        for _, attr in ipairs(attrNames) do
            local stat = ls:FindFirstChild(attr)
            if stat and stat:IsA("ValueBase") and stat.Value ~= nil and tostring(stat.Value) ~= "" then
                return "LS_" .. attr .. "_" .. tostring(stat.Value)
            end
        end
    end

    return nil
end

local function IsTeammate(plr)
    if plr == LocalPlayer then return true end
    if not Config.TeamCheck then return false end

    -- Standard strict checks first
    if plr.Team ~= nil and LocalPlayer.Team ~= nil then
        if plr.Team == LocalPlayer.Team then return true end
    end
    if not plr.Neutral and not LocalPlayer.Neutral and plr.TeamColor == LocalPlayer.TeamColor then
        if plr.Team ~= nil or LocalPlayer.Team ~= nil then
            return true
        end
    end

    -- Deep custom check
    local myTeamId = GetCustomTeamIdentifier(LocalPlayer)
    local theirTeamId = GetCustomTeamIdentifier(plr)

    if myTeamId ~= nil and theirTeamId ~= nil and myTeamId == theirTeamId then
        return true
    end

    return false
end

--------------------------------------------------------------------------------
-- 3. TARGET HEAD & HITBOX RESOLVER
--------------------------------------------------------------------------------
local HeadAliases = { "Head", "FakeHead", "HeadHitbox", "HeadBox", "CustomHead", "head", "Hitbox" }

local function ResolveTargetHead(char)
    if not char then return nil, nil, nil end
    if Config.IgnoreForceField and char:FindFirstChildOfClass("ForceField") then
        return nil, nil, nil
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil, nil, nil end

    local exactHead = char:FindFirstChild("Head", true)
    if exactHead and exactHead:IsA("BasePart") then
        return exactHead, exactHead.Position, hum
    end

    for _, name in ipairs(HeadAliases) do
        local p = char:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then
            return p, p.Position, hum
        end
    end

    local isR15 = (hum.RigType == Enum.HumanoidRigType.R15) or (char:FindFirstChild("UpperTorso") ~= nil)
    local torso = isR15 and char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")

    if torso and torso:IsA("BasePart") then
        local neck = torso:FindFirstChild("Neck", true) or char:FindFirstChild("Neck", true)
        if neck and neck:IsA("Motor6D") and neck.Part1 then
            return neck.Part1, neck.Part1.Position, hum
        end
        local offset = isR15 and Vector3.new(0, 1.45, 0) or Vector3.new(0, 1.5, 0)
        return torso, (torso.CFrame * CFrame.new(offset)).Position, hum
    end

    local root = hum.RootPart or char.PrimaryPart
    if root then
        return root, (root.CFrame * CFrame.new(0, 1.5, 0)).Position, hum
    end
    return nil, nil, nil
end

--------------------------------------------------------------------------------
-- 4. STEALTH CHAMS / ESP & DYNAMIC TEAM REFRESH
--------------------------------------------------------------------------------
local function RandomString(len)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local b = {}
    for i = 1, len do
        local r = math.random(1, #chars)
        b[i] = string.sub(chars, r, r)
    end
    return table.concat(b)
end

local SafeContainer = (gethui and gethui()) or CoreGui
local ChamsFolder = Instance.new("Folder")
ChamsFolder.Name = RandomString(14)
ChamsFolder.Parent = SafeContainer

local PlayerHighlights = {}

local function UpdateHighlightState(plr)
    local hl = PlayerHighlights[plr]
    if not hl or not hl.Parent then return end

    local char = plr.Character
    if not char then
        hl.Enabled = false
        return
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then
        hl.Enabled = false
        return
    end

    hl.Adornee = char
    local teammate = IsTeammate(plr)

    if teammate then
        if Config.TeamCheck and not Config.ShowTeamESP then
            hl.Enabled = false
        else
            hl.Enabled = true
            hl.FillColor = Config.ChamsFillTeam
        end
    else
        hl.Enabled = true
        hl.FillColor = Config.ChamsFillEnemy
    end
end

local function ApplyChams(plr)
    if plr == LocalPlayer then return end

    local function SetupChar(char)
        if not char then return end
        task.wait(0.05)
        local old = PlayerHighlights[plr]
        if old then old:Destroy() end

        local hl = Instance.new("Highlight")
        hl.Name = RandomString(10)
        hl.Adornee = char
        hl.FillColor = Config.ChamsFillEnemy
        hl.OutlineColor = Config.ChamsOutline
        hl.FillTransparency = 0.45
        hl.OutlineTransparency = 0.1
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ChamsFolder

        PlayerHighlights[plr] = hl
        UpdateHighlightState(plr)
    end

    if plr.Character then task.spawn(SetupChar, plr.Character) end
    plr.CharacterAdded:Connect(SetupChar)
    plr:GetPropertyChangedSignal("Team"):Connect(function() UpdateHighlightState(plr) end)
    plr:GetPropertyChangedSignal("TeamColor"):Connect(function() UpdateHighlightState(plr) end)
end

for _, p in ipairs(Players:GetPlayers()) do ApplyChams(p) end
Players.PlayerAdded:Connect(ApplyChams)
Players.PlayerRemoving:Connect(function(p)
    local hl = PlayerHighlights[p]
    if hl then
        hl:Destroy()
        PlayerHighlights[p] = nil
    end
end)

local function RefreshAllESP()
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            UpdateHighlightState(p)
        end
    end
end

-- Periodic refresh in case custom Folder/Attribute teams change mid-round
task.spawn(function()
    while task.wait(0.5) do
        RefreshAllESP()
    end
end)

--------------------------------------------------------------------------------
-- 5. HOME KEYBIND TOGGLE + HUD INDICATOR
--------------------------------------------------------------------------------
local FOVCircle = Drawing.new("Circle")
FOVCircle.Radius = Config.FOV
FOVCircle.Color = Color3.fromRGB(0, 255, 220)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Visible = true

local StatusText = Drawing.new("Text")
StatusText.Size = 15
StatusText.Center = true
StatusText.Outline = true
StatusText.Color = Color3.fromRGB(0, 255, 220)
StatusText.Visible = true

local function UpdateStatusLabel()
    local state = Config.TeamCheck and "ON" or "OFF"
    StatusText.Text = string.format("[HOME] Deep TeamCheck: %s", state)
    StatusText.Color = Config.TeamCheck and Color3.fromRGB(0, 255, 220) or Color3.fromRGB(255, 90, 90)
end
UpdateStatusLabel()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Home then
        Config.TeamCheck = not Config.TeamCheck
        UpdateStatusLabel()
        RefreshAllESP()
    end
end)

--------------------------------------------------------------------------------
-- 6. CLOSEST TARGET ACQUISITION
--------------------------------------------------------------------------------
local CurrentTarget = nil
local CurrentTargetPos = nil
local CurrentHumanoid = nil

local function GetClosestTarget()
    Camera = Workspace.CurrentCamera
    if not Camera then return nil, nil, nil end
    local bestDist = Config.FOV
    local bestPart, bestPos, bestHum = nil, nil, nil
    local mousePos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and not IsTeammate(plr) then
            local part, pos, hum = ResolveTargetHead(plr.Character)
            if part and pos and hum then
                local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPart = part
                        bestPos = pos
                        bestHum = hum
                    end
                end
            end
        end
    end
    return bestPart, bestPos, bestHum
end

RunService.RenderStepped:Connect(function()
    local mousePos = UserInputService:GetMouseLocation()
    FOVCircle.Position = mousePos
    StatusText.Position = Vector2.new(mousePos.X, mousePos.Y + Config.FOV + 8)
    CurrentTarget, CurrentTargetPos, CurrentHumanoid = GetClosestTarget()
end)

--------------------------------------------------------------------------------
-- 7. UNIVERSAL CAST & REMOTE SPOOFING ENGINE
--------------------------------------------------------------------------------
local function RedirectVector(origin, currentDir, targetPos)
    local toTarget = (targetPos - origin)
    local dist = toTarget.Magnitude
    if dist < 0.001 then return currentDir end
    local segMag = math.max(currentDir.Magnitude, dist + 15)
    return toTarget.Unit * segMag
end

-- Sanitize RaycastParams so the target character is never accidentally blacklisted
local function SanitizeRaycastParams(params, targetChar)
    if typeof(params) ~= "RaycastParams" or not targetChar then return params end
    if params.FilterType == Enum.RaycastFilterType.Exclude then
        local list = params.FilterDescendantsInstances
        for i = #list, 1, -1 do
            if list[i] == targetChar or targetChar:IsAncestorOf(list[i]) then
                table.remove(list, i)
            end
        end
