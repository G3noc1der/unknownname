local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")

local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
local root = pg:WaitForChild("SillyTiles")

local Config = {
    Enabled = false,
    Keys = { "D", "F", "J", "K" },
    HitRatio = 806 / 1009,
    HitOffset = 0,
    LeadMs = 16,
    TapTime = 0.03,
    ReleaseAt = 8,
}

local noteState = setmetatable({}, { __mode = "k" })
local lanes = {}
local frameId = 0

local function sendKey(key, down)
    local kc = Enum.KeyCode[key]
    if kc then pcall(function() VIM:SendKeyEvent(down, kc, false, game) end) end
end

local function getLane(i)
    local L = lanes[i]
    if not L then
        L = { down = false, mode = nil, releaseAt = 0, releasedFrame = -1, queue = {}, note = nil }
        lanes[i] = L
    end
    return L
end

local function releaseAll()
    for i, L in pairs(lanes) do
        if L.down and Config.Keys[i] then sendKey(Config.Keys[i], false) end
        L.down = false; L.mode = nil; L.note = nil
        table.clear(L.queue)
    end
end

local function stepLane(i, L, now)
    local key = Config.Keys[i]
    if not key then return end

    if L.down then
        if L.mode == "hold" then
            local n = L.note
            local body = n and n.Parent and n:FindFirstChild("Body")
            if not body or body.AbsoluteSize.Y <= Config.ReleaseAt then
                sendKey(key, false)
                L.down = false; L.mode = nil; L.note = nil
                L.releasedFrame = frameId
            end
        elseif #L.queue > 0 or now >= L.releaseAt then
            -- release early if another note is waiting in this lane
            sendKey(key, false)
            L.down = false; L.mode = nil
            L.releasedFrame = frameId
        end
    end

    -- press on a later frame than the release so the game sees a fresh keypress
    if not L.down and #L.queue > 0 and frameId > L.releasedFrame then
        local req = table.remove(L.queue, 1)
        sendKey(key, true)
        L.down = true
        if req.hold then
            L.mode = "hold"; L.note = req.note
        else
            L.mode = "tap"; L.releaseAt = now + Config.TapTime
        end
    end
end

RunService.Heartbeat:Connect(function(dt)
    if not Config.Enabled then return end
    frameId += 1
    local now = os.clock()
    dt = math.max(dt, 1 / 240)

    local gf = root:FindFirstChild("Frame")
    if gf and gf.Visible then
        local hitY = gf.AbsolutePosition.Y + gf.AbsoluteSize.Y * Config.HitRatio + Config.HitOffset
        local laneCount = #Config.Keys
        local laneW = gf.AbsoluteSize.X / laneCount
        local lead = Config.LeadMs / 1000

        for _, n in ipairs(gf:GetChildren()) do
            if n:IsA("Frame") and n:FindFirstChild("Head") then
                local y = n.AbsolutePosition.Y
                local s = noteState[n]
                if not s then
                    -- notes first seen already past the line (enabled mid-song) are skipped
                    s = { lastY = y, vel = 0, hit = y > hitY }
                    noteState[n] = s
                else
                    if y < s.lastY - 30 then
                        s.hit = false; s.vel = 0 -- frame was recycled for a new note
                    else
                        s.vel = s.vel * 0.5 + math.max((y - s.lastY) / dt, 0) * 0.5
                    end
                    s.lastY = y

                    if not s.hit and y + s.vel * lead >= hitY then
                        s.hit = true
                        local cx = n.AbsolutePosition.X + n.AbsoluteSize.X / 2
                        local lane = math.clamp(math.floor((cx - gf.AbsolutePosition.X) / laneW) + 1, 1, laneCount)
                        local L = getLane(lane)
                        table.insert(L.queue, { hold = n:FindFirstChild("Body") ~= nil, note = n })
                    end
                end
            end
        end
    end

    for i, L in pairs(lanes) do stepLane(i, L, now) end
end)

-- UI
local Window = Rayfield:CreateWindow({
    Name = "Silly Tiles | Playtest",
    LoadingTitle = "Silly Tiles",
    LoadingSubtitle = "Playtest tool",
    ConfigurationSaving = { Enabled = false },
    KeySystem = false,
})

local Main = Window:CreateTab("Autoplay")

Main:CreateToggle({
    Name = "Enable Autoplay",
    CurrentValue = false,
    Callback = function(v)
        Config.Enabled = v
        if not v then releaseAll() end
    end,
})

Main:CreateSlider({
    Name = "Hit Offset (px)",
    Range = { -120, 120 }, Increment = 1, CurrentValue = 0,
    Callback = function(v) Config.HitOffset = v end,
})

Main:CreateSlider({
    Name = "Look-ahead (ms)",
    Range = { 0, 100 }, Increment = 1, CurrentValue = 16,
    Callback = function(v) Config.LeadMs = v end,
})

Main:CreateSlider({
    Name = "Tap Time (ms)",
    Range = { 10, 100 }, Increment = 5, CurrentValue = 30,
    Callback = function(v) Config.TapTime = v / 1000 end,
})

Main:CreateSlider({
    Name = "Hold Release Threshold (px)",
    Range = { 0, 60 }, Increment = 1, CurrentValue = 8,
    Callback = function(v) Config.ReleaseAt = v end,
})

Main:CreateInput({
    Name = "Keys (4, left to right)",
    PlaceholderText = "D,F,J,K",
    RemoveTextAfterFocusLost = false,
    Callback = function(t)
        local keys = {}
        for k in string.gmatch(t, "[^,%s]+") do keys[#keys + 1] = string.upper(k) end
        if #keys > 0 then releaseAll(); Config.Keys = keys end
    end,
})
