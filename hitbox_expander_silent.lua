-- 07_hitbox_expander_silent.lua
-- Method: Rig Head Hitbox Expander with Original Size Cache & __index Spoofing

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local ScriptContext = game:GetService("ScriptContext")
local LogService = game:GetService("LogService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Config = {
    FOV = 180,
    ExpandedSize = Vector3.new(12, 12, 12),
    TeamCheck = false,
    IgnoreForceField = true,
    ChamsFill = Color3.fromRGB(255, 0, 120),
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
        return torso, torso.Position
    end
    return nil, nil
end


local SafeContainer = (gethui and gethui()) or CoreGui
local ChamsFolder = Instance.new("Folder")
ChamsFolder.Name = "RenderCache_07"
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


local OriginalSizes = setmetatable({}, { __mode = "k" })
local OriginalTrans = setmetatable({}, { __mode = "k" })

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
    if not checkcaller() and OriginalSizes[self] then
        if key == "Size" then
            return OriginalSizes[self]
        elseif key == "Transparency" then
            return OriginalTrans[self] or 0
        elseif key == "CanCollide" then
            return false
        end
    end
    return oldIndex(self, key)
end))


local FOVCircle = Drawing.new("Circle")
FOVCircle.Radius = Config.FOV
FOVCircle.Color = Color3.fromRGB(255, 0, 120)
FOVCircle.Thickness = 1.5
FOVCircle.Filled = false
FOVCircle.Visible = true

RunService.RenderStepped:Connect(function()
    Camera = workspace.CurrentCamera
    if not Camera then return end
    local mousePos = UserInputService:GetMouseLocation()
    FOVCircle.Position = mousePos

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and (not Config.TeamCheck or plr.Team ~= LocalPlayer.Team) then
            local part, pos = ResolveTargetHead(plr.Character)
            if part and pos then
                if not OriginalSizes[part] then
                    OriginalSizes[part] = part.Size
                    OriginalTrans[part] = part.Transparency
                end
                local screenPos, onScreen = Camera:WorldToViewportPoint(pos)
                local dist = onScreen and (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude or 9999
                if dist < Config.FOV then
                    part.Size = Config.ExpandedSize
                    part.Transparency = 0.85
                    part.CanCollide = false
                    part.Massless = true
                else
                    part.Size = OriginalSizes[part]
                    part.Transparency = OriginalTrans[part] or 0
                end
            end
        end
    end
end)