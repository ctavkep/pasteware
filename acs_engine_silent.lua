-- 05_acs_engine_silent.lua
-- Method: ACS 1.7.5 / 2.0.1 / FastCast Silent Aim 
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Config = {
    FOV = 220,
    TeamCheck = false,
    IgnoreForceField = true,
    ChamsFill = Color3.fromRGB(180, 50, 255),
    ChamsOutline = Color3.fromRGB(255, 255, 255)
}


local function BypassAntiCheats()
    if getconnections then
        for _, conn in ipairs(getconnections(ScriptContext.Error)) do
            pcall(function() conn:Disable() end)
        end
        for _, conn in ipairs(getconnections(LogService.MessageOut)) do
            pcall(function() conn:Disable() end)
        end
    end
    for _, v in ipairs(getgc(true)) do
        if type(v) == "table" then
            local det = rawget(v, "Detected")
            local kill = rawget(v, "Kill")
            if type(det) == "function" and islclosure(det) then
                hookfunction(det, newcclosure(function() return true end))
            end
            if type(kill) == "function" and islclosure(kill) then
                hookfunction(kill, newcclosure(function() return nil end))
            end
            local anti = rawget(v, "Anti")
            if type(anti) == "table" and rawget(v, "Variables") and rawget(v, "Process") then
                for _, func in pairs(anti) do
                    if type(func) == "function" and islclosure(func) then
                        hookfunction(func, newcclosure(function() return true end))
                    end
                end
            end
        end
    end
end
pcall(BypassAntiCheats)


local HeadAliases = { "Head", "FakeHead", "HeadHitbox", "HeadBox", "CustomHead", "head" }

local function ResolveTargetHead(char)
    if not char then return nil, nil end
    if Config.IgnoreForceField and char:FindFirstChildOfClass("ForceField") then
        return nil, nil
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil, nil end

    for _, name in ipairs(HeadAliases) do
        local p = char:FindFirstChild(name, true)
        if p and p:IsA("BasePart") then
            return p, p.Position
        end
    end

    local isR15 = (hum.RigType == Enum.HumanoidRigType.R15) or (char:FindFirstChild("UpperTorso") ~= nil)
    local torso = isR15 and char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")

    if torso and torso:IsA("BasePart") then
        local neck = torso:FindFirstChild("Neck", true) or char:FindFirstChild("Neck", true)
        if neck and neck:IsA("Motor6D") and neck.Part1 then
            return neck.Part1, neck.Part1.Position
        end
        local offset = isR15 and Vector3.new(0, 1.45, 0) or Vector3.new(0, 1.5, 0)
        return torso, (torso.CFrame * CFrame.new(offset)).Position
    end

    local root = hum.RootPart or char.PrimaryPart
    if root then
        return root, (root.CFrame * CFrame.new(0, 1.5, 0)).Position
    end
    return nil, nil
end


local SafeContainer = (gethui and gethui()) or CoreGui
local ChamsFolder = Instance.new("Folder")
ChamsFolder.Name = "RenderCache_05"
ChamsFolder.Parent = SafeContainer

local function ApplyChams(plr)
    if plr == LocalPlayer then return end
    local function OnChar(char)
        task.wait(0.1)
        local old = ChamsFolder:FindFirstChild(plr.Name)
        if old then old:Destroy() end

        local hl = Instance.new("Highlight")
        hl.Name = plr.Name
        hl.Adornee = char
        hl.FillColor = Config.ChamsFill
        hl.OutlineColor = Config.ChamsOutline
        hl.FillTransparency = 0.45
        hl.OutlineTransparency = 0.1
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
FOVCircle.Color = Color3.fromRGB(180, 50, 255)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Visible = true

local CurrentTarget = nil
local CurrentTargetPos = nil

local function GetClosestTarget()
    Camera = workspace.CurrentCamera
    if not Camera then return nil, nil end
    local bestDist = Config.FOV
    local bestPart, bestPos = nil, nil
    local mousePos = UserInputService:GetMouseLocation()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and (not Config.TeamCheck or plr.Team ~= LocalPlayer.Team) then
            local part, pos = ResolveTargetHead(plr.Character)
            if part and pos then
                local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                if onScreen then
                    local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPart = part
                        bestPos = pos
                    end
                end
            end
        end
    end
    return bestPart, bestPos
end

RunService.RenderStepped:Connect(function()
    FOVCircle.Position = UserInputService:GetMouseLocation()
    CurrentTarget, CurrentTargetPos = GetClosestTarget()
end)


for _, fn in ipairs(getgc(true)) do
    if type(fn) == "function" and islclosure(fn) and not isexecutorclosure(fn) then
        local info = debug.getinfo(fn)
        if info and (info.name == "CastRay" or info.name == "CreateBullet") then
            local oldFn
            oldFn = hookfunction(fn, newcclosure(function(...)
                if CurrentTarget and CurrentTargetPos then
                    local args = { ... }
                    for i, arg in ipairs(args) do
                        if typeof(arg) == "Vector3" and arg.Magnitude <= 1.05 and arg.Magnitude >= 0.95 then
                            args[i] = (CurrentTargetPos - Camera.CFrame.Position).Unit
                        end
                    end
                    return oldFn(unpack(args))
                end
                return oldFn(...)
            end))
        end
    end
end

local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnamecallmethod()
    if not checkcaller() and CurrentTarget and CurrentTargetPos then
        local args = { ... }
        if method == "FireServer" and (self.Name == "AntiCheat" or self.Name == "Exploit" or self.Name == "Ban") then
            return nil
        end

        if self == workspace then
            if method == "Raycast" and typeof(args[1]) == "Vector3" and typeof(args[2]) == "Vector3" then
                args[2] = (CurrentTargetPos - args[1]).Unit * math.max(args[2].Magnitude, 2000)
                return oldNamecall(self, unpack(args))
            elseif method == "FindPartOnRayWithIgnoreList" and typeof(args[1]) == "Ray" then
                local origin = args[1].Origin
                args[1] = Ray.new(origin, (CurrentTargetPos - origin).Unit * 2000)
                return oldNamecall(self, unpack(args))
            end
        end

        if method == "FireServer" and (self.Name == "Damage" or self.Name == "Hit" or self.Name == "HitEffect") then
            for i, v in ipairs(args) do
                if typeof(v) == "Instance" and v:IsA("BasePart") then
                    args[i] = CurrentTarget
                elseif typeof(v) == "Vector3" then
                    args[i] = CurrentTargetPos
                end
            end
            return oldNamecall(self, unpack(args))
        end
    end
    return oldNamecall(self, ...)
end))