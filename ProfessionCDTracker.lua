-- ProfessionCDTracker.lua
local ADDON_NAME = ...
local VERSION = "1.6"

ProfessionCDTrackerDB = ProfessionCDTrackerDB or { realms = {}, settings = {} }
local settings = ProfessionCDTrackerDB.settings

-- Defaults
settings.barWidth  = settings.barWidth  or 200
settings.barHeight = settings.barHeight or 12

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
container:SetSize(settings.barWidth, 200)
container:SetMovable(true)
container:EnableMouse(true)

container:RegisterForDrag("LeftButton")
container:SetScript("OnDragStart", function(self)
    if self:IsMovable() then self:StartMoving() end
end)
container:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- Helpers
local function CharKey()
    local name, realm = UnitName("player"), GetRealmName()
    return realm, name
end

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

-- Scans
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

local function ScanTrackedCooldowns()
    ScanTradeSkills()
    ScanItems()
end

-- Bars
local bars = {}

local function CreateBar(index)
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetSize(settings.barWidth, settings.barHeight)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0, 0)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.8)

    if index == 1 then
        bar:SetPoint("TOP", container, "TOP", 0, 0)
    else
        bar:SetPoint("TOP", bars[index-1], "BOTTOM", 0, 0)
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

                        bar:SetWidth(settings.barWidth)
                        bar:SetHeight(settings.barHeight)
                        bar:SetMinMaxValues(0, duration)
                        bar:SetValue(duration - remain)

                        if remain <= 0 then
                            bar:SetStatusBarColor(0, 1, 0)
                        else
                            bar:SetStatusBarColor(1, 0, 0)
                        end

                        bar.left:SetText(char .. " - " .. label)
                        bar.right:SetText(SecondsToTime(remain) .. " | " .. readyAt)

                        bar:Show()
                        i = i + 1
                    end
                end
            end
        end
    end
    for j = i, #bars do bars[j]:Hide() end
end

-- Slash commands
SLASH_PCT1 = "/pct"
SlashCmdList["PCT"] = function(msg)
    local args = { strsplit(" ", msg:lower()) }
    if args[1] == "scan" then
        ScanTrackedCooldowns()
        UpdateUI()
        container:Show()
    elseif args[1] == "show" then
        UpdateUI(); container:Show()
    elseif args[1] == "hide" then
        container:Hide()
    elseif args[1] == "unlock" then
        container:EnableMouse(true); container:SetMovable(true)
        print("|cff33ff99PCT|r Bars unlocked (drag to move).")
    elseif args[1] == "lock" then
        container:EnableMouse(false); container:SetMovable(false)
        print("|cff33ff99PCT|r Bars locked.")
    elseif args[1] == "width" and tonumber(args[2]) then
        settings.barWidth = tonumber(args[2])
        print("|cff33ff99PCT|r Bar width set to", settings.barWidth)
        UpdateUI()
    elseif args[1] == "height" and tonumber(args[2]) then
        settings.barHeight = tonumber(args[2])
        print("|cff33ff99PCT|r Bar height set to", settings.barHeight)
        UpdateUI()
    else
        print("|cff33ff99PCT|r Commands: /pct scan, /pct show, /pct hide, /pct lock, /pct unlock, /pct width <n>, /pct height <n>")
    end
end

-- Events
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

container:SetScript("OnUpdate", function()
    if container:IsShown() then UpdateUI() end
end)
