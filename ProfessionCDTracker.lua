-- ProfessionCDTracker.lua
local ADDON_NAME = ...
local VERSION = "1.5"

ProfessionCDTrackerDB = ProfessionCDTrackerDB or { realms = {} }

-- Frame + Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRADE_SKILL_SHOW")

-- Our tracked cooldowns
local TRACKED = {
    ["Mooncloth"] = { label = "Mooncloth", type = "trade", icon = 14342 },
    [15846] = { label = "Salt Shaker", type = "item", icon = 15846 },
}

-- Bars container (invisible, draggable if unlocked)
local container = CreateFrame("Frame", "PCT_Container", UIParent)
container:SetPoint("CENTER")
container:SetSize(350, 200)
container:SetMovable(true)
container:EnableMouse(false) -- only enabled on unlock

-- dragging scripts
container:RegisterForDrag("LeftButton")
container:SetScript("OnDragStart", function(self)
    if self:IsMovable() then self:StartMoving() end
end)
container:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- Helper: get character key
local function CharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return realm, name
end

-- Save cooldown info
local function SaveCooldown(key, start, duration)
    local realm, name = CharKey()
    ProfessionCDTrackerDB.realms[realm] = ProfessionCDTrackerDB.realms[realm] or {}
    ProfessionCDTrackerDB.realms[realm][name] = ProfessionCDTrackerDB.realms[realm][name] or {}
    local charDB = ProfessionCDTrackerDB.realms[realm][name]

    charDB.cooldowns = charDB.cooldowns or {}
    charDB.cooldowns[key] = {
        start = start,
        duration = duration,
        expires = start + duration,
    }
end

-- Scan tradeskill cooldowns (Mooncloth etc.)
local function ScanTradeSkills()
    local num = GetNumTradeSkills()
    for i = 1, num do
        local name, type = GetTradeSkillInfo(i)
        local cd = GetTradeSkillCooldown(i)
        if name and cd and cd > 0 then
            if TRACKED[name] and TRACKED[name].type == "trade" then
                SaveCooldown(name, GetTime(), cd)
                print("|cff33ff99PCT|r Found", name, "CD:", SecondsToTime(cd))
            end
        end
    end
end

-- Scan item cooldowns (Salt Shaker etc.)
local function ScanItems()
    for itemId, info in pairs(TRACKED) do
        if type(itemId) == "number" and info.type == "item" then
            local start, duration, enabled = GetItemCooldown(itemId)
            if enabled == 1 and duration > 0 then
                SaveCooldown(itemId, start, duration)
                print("|cff33ff99PCT|r Found", info.label, "CD:", SecondsToTime(duration))
            end
        end
    end
end

-- Full scan
local function ScanTrackedCooldowns()
    ScanTradeSkills()
    ScanItems()
end

-- Bars
local bars = {}

local function CreateBar(index)
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetSize(320, 20)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetStatusBarColor(0, 1, 0)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.8)

    if index == 1 then
        bar:SetPoint("TOP", container, "TOP", 0, -5)
    else
        bar:SetPoint("TOP", bars[index-1], "BOTTOM", 0, -5)
    end

    bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.left:SetPoint("LEFT", bar, "LEFT", 4, 0)

    bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

    bars[index] = bar
    return bar
end

local function UpdateUI()
    local i = 1
    for realm, chars in pairs(ProfessionCDTrackerDB.realms) do
        for char, data in pairs(chars) do
            if data.cooldowns then
                for key, cd in pairs(data.cooldowns) do
                    if cd.expires then
                        local now = GetTime()
                        local remain = cd.expires - now
                        if remain < 0 then remain = 0 end
                        local duration = cd.duration or 1
                        local readyAt = date("%H:%M", time() + remain)

                        local info = TRACKED[key] or TRACKED[cd.label]
                        local label = (type(key) == "string" and key) or (info and info.label) or "?"
                        local bar = bars[i] or CreateBar(i)

                        bar:SetMinMaxValues(0, duration)
                        bar:SetValue(duration - remain)

                        bar.left:SetText(char .. " - " .. label)
                        bar.right:SetText(SecondsToTime(remain) .. " | " .. readyAt)

                        bar:Show()
                        i = i + 1
                    end
                end
            end
        end
    end
    -- hide unused bars
    for j = i, #bars do
        bars[j]:Hide()
    end
end

-- Slash commands
SLASH_PCT1 = "/pct"
SlashCmdList["PCT"] = function(msg)
    msg = msg:lower()
    if msg == "scan" then
        ScanTrackedCooldowns()
        UpdateUI()
        container:Show()
        print("|cff33ff99PCT|r Manual scan complete.")
    elseif msg == "debug" then
        local num = GetNumTradeSkills()
        print("Found", num, "trade skills")
        for i = 1, num do
            local name, type = GetTradeSkillInfo(i)
            local cd = GetTradeSkillCooldown(i)
            print(i, "name:", name, "type:", type, "cd:", cd or "none")
        end
    elseif msg == "show" then
        UpdateUI()
        container:Show()
    elseif msg == "hide" then
        container:Hide()
    elseif msg == "unlock" then
        container:EnableMouse(true)
        container:SetMovable(true)
        print("|cff33ff99PCT|r Bars unlocked (drag to move).")
    elseif msg == "lock" then
        container:EnableMouse(false)
        container:SetMovable(false)
        print("|cff33ff99PCT|r Bars locked.")
    else
        print("|cff33ff99PCT|r Commands: /pct scan, /pct show, /pct hide, /pct lock, /pct unlock, /pct debug")
    end
end

-- Event handler
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        print("|cff33ff99PCT|r Loaded " .. ADDON_NAME .. " v" .. VERSION)
    elseif event == "PLAYER_LOGIN" then
        ScanTrackedCooldowns()
        UpdateUI()
        container:Show()
    elseif event == "TRADE_SKILL_SHOW" then
        ScanTradeSkills()
        UpdateUI()
    end
end)

-- OnUpdate for live bar ticking
container:SetScript("OnUpdate", function()
    if container:IsShown() then
        UpdateUI()
    end
end)
