-- ProfessionCDTracker.lua
local ADDON_NAME = ...
local VERSION = "1.7"

ProfessionCDTrackerDB = ProfessionCDTrackerDB or { realms = {}, settings = {} }
ProfessionCDTrackerDB.settings = ProfessionCDTrackerDB.settings or {}
local settings = ProfessionCDTrackerDB.settings

-- Defaults (only set if not already saved)
settings.barWidth  = settings.barWidth or 170
settings.barHeight = settings.barHeight or 12
if settings.locked == nil then settings.locked = false end
-- Always ensure these keys exist in the table for SavedVariables to track them
if settings.showReadyOnly == nil then settings.showReadyOnly = false end
if settings.readyThresholdHours == nil then settings.readyThresholdHours = 10 end
if settings.showCDName == nil then settings.showCDName = false end

-- Frame + Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("BAG_UPDATE_COOLDOWN")

-- Our tracked cooldowns
local TRACKED = {
    ["Mooncloth"] = { label = "Mooncloth", type = "trade", icon = 14342 },
    ["Transmute: Arcanite"] = { label = "Transmute: Arcanite", type = "trade", icon = 12360 },
    -- [15846] = { label = "Salt Shaker", type = "item", icon = 15846 },
}

-- Bars container (invisible, draggable if unlocked)
local container = CreateFrame("Frame", "PCT_Container", UIParent)
container:SetPoint("CENTER")
container:SetSize(settings.barWidth, 200)
container:SetMovable(true)
container:EnableMouse(false)
container:SetClampedToScreen(true)
container:SetUserPlaced(true)

container:RegisterForDrag("LeftButton")
container:SetScript("OnDragStart", function(self)
    if self:IsMovable() then self:StartMoving() end
end)
local function SaveContainerPosition()
    local point, relativeTo, relativePoint, xOfs, yOfs = container:GetPoint()
    settings.anchor = settings.anchor or {}
    settings.anchor.point = point
    settings.anchor.relativePoint = relativePoint
    settings.anchor.x = xOfs
    settings.anchor.y = yOfs
end

container:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SaveContainerPosition()
end)

local function RestoreContainerPosition()
    if settings.anchor and settings.anchor.point then
        container:ClearAllPoints()
        container:SetPoint(settings.anchor.point, UIParent, settings.anchor.relativePoint or settings.anchor.point, settings.anchor.x or 0, settings.anchor.y or 0)
    else
        container:ClearAllPoints()
        container:SetPoint("CENTER")
    end
end

-- Declare bars early so other functions can reference it safely
local bars = {}

local function ApplyLockState()
    if settings.locked then
        container:SetMovable(false)
        for _, bar in ipairs(bars or {}) do
            if bar then bar:EnableMouse(false) end
        end
    else
        container:SetMovable(true)
        for _, bar in ipairs(bars or {}) do
            if bar then bar:EnableMouse(true) end
        end
    end
end

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
    -- Persist as absolute epoch so cross-session math is correct
    local nowUI = GetTime()
    local remain = math.max(0, (start or 0) + (duration or 0) - nowUI)
    if duration and duration > 0 then
        -- Clamp to the known duration to avoid bogus huge remains from bad APIs/saves
        remain = math.min(remain, duration)
    end
    local expiresEpoch = time() + remain
    charDB.cooldowns[key] = {
        duration = duration,
        expiresEpoch = expiresEpoch,
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
                -- print("|cff33ff99PCT|r Found", name, "CD:", SecondsToTime(cd))
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
                local remain = math.max(0, (start or 0) + duration - GetTime())
                if remain > 0 and remain < (120 * 24 * 60 * 60) then
                    -- print("|cff33ff99PCT|r Found", info.label, "CD:", SecondsToTime(remain))
                end
            end
        end
    end
end

local function ScanTrackedCooldowns()
    ScanTradeSkills()
    ScanItems()
end

-- Bars (already declared earlier)

local function CreateBar(index)
    local bar = CreateFrame("StatusBar", nil, container)
    bar:SetSize(settings.barWidth, settings.barHeight)
    bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    bar:SetStatusBarColor(1, 0, 0)
    bar:EnableMouse(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetMovable(true)
    bar:SetScript("OnDragStart", function(self)
        if not settings.locked then container:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        container:StopMovingOrSizing()
        SaveContainerPosition()
    end)

    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.8)

    if index == 1 then
        bar:SetPoint("TOP", container, "TOP", 0, 0)
    else
        bar:SetPoint("TOP", bars[index-1], "BOTTOM", 0, 0)
    end

    -- Create icon texture on the left side of the bar
    bar.icon = bar:CreateTexture(nil, "OVERLAY")
    bar.icon:SetSize(settings.barHeight, settings.barHeight)
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9) -- Trim edges for better appearance

    bar.left = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.left:SetPoint("LEFT", bar, "LEFT", settings.barHeight + 4, 0)

    bar.right = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)

    bars[index] = bar
    return bar
end

local function UpdateUI()
    -- Collect all cooldowns into a sortable array
    local cooldownData = {}
    for realm, chars in pairs(ProfessionCDTrackerDB.realms) do
        for char, data in pairs(chars) do
            if data.cooldowns then
                for key, cd in pairs(data.cooldowns) do
                    local expiresEpoch = cd.expiresEpoch or cd.expires
                    if expiresEpoch then
                        local nowEpoch = time()
                        local remain = expiresEpoch - nowEpoch
                        if remain < 0 then remain = 0 end
                        local duration = cd.duration or 1
                        if duration > 0 then
                            -- Clamp to stored duration to prevent bogus long remains
                            remain = math.min(remain, duration)
                        end
                        
                        local info = TRACKED[key] or TRACKED[cd.label]
                        local label = (type(key) == "string" and key) or (info and info.label) or "?"
                        
                        table.insert(cooldownData, {
                            char = char,
                            key = key,
                            label = label,
                            remain = remain,
                            duration = duration,
                            expiresEpoch = expiresEpoch,
                            icon = info and info.icon
                        })
                    end
                end
            end
        end
    end
    
    -- Filter by ready time if enabled (read directly from SavedVariables to ensure we get the latest value)
    if ProfessionCDTrackerDB.settings.showReadyOnly then
        local readyThreshold = (ProfessionCDTrackerDB.settings.readyThresholdHours or 10) * 60 * 60 -- hours to seconds
        local filteredData = {}
        for _, data in ipairs(cooldownData) do
            if data.remain < readyThreshold then
                table.insert(filteredData, data)
            end
        end
        cooldownData = filteredData
    end
    
    -- Sort by remaining time (ascending - least time first)
    table.sort(cooldownData, function(a, b)
        return a.remain < b.remain
    end)
    
    -- Now update bars in sorted order
    local i = 1
    local numVisible = 0
    for _, data in ipairs(cooldownData) do
        local remain = data.remain
        local duration = data.duration
        local char = data.char
        local label = data.label
        local expiresEpoch = data.expiresEpoch
        local iconId = data.icon
        
        local nowEpoch = time()
        local readyAt = date("%H:%M", nowEpoch + remain)
        
        local bar = bars[i] or CreateBar(i)
        
        bar:SetWidth(settings.barWidth)
        bar:SetHeight(settings.barHeight)
        bar:SetMinMaxValues(0, duration)
        bar:SetValue(duration - math.min(remain, duration))
        
        -- Set icon texture if available
        if iconId and bar.icon then
            bar.icon:SetSize(settings.barHeight, settings.barHeight)
            local iconTexture = GetItemIcon(iconId)
            if iconTexture then
                bar.icon:SetTexture(iconTexture)
                bar.icon:Show()
            else
                bar.icon:Hide()
            end
        elseif bar.icon then
            bar.icon:Hide()
        end
        
        if remain <= 0 then
            bar:SetStatusBarColor(0, 1, 0)
        else
            bar:SetStatusBarColor(1, 0, 0)
        end
        
        -- Update left text position to account for icon
        bar.left:SetPoint("LEFT", bar, "LEFT", settings.barHeight + 4, 0)
        
        -- Set left text based on showCDName setting
        if settings.showCDName then
            -- bar.left:SetText(char .. " - " .. label)
            local displayLabel = (label and label:match("^(.-):")) or label or ""
            if displayLabel == "Transmute" then
                displayLabel = "Trans"
            elseif displayLabel == "Mooncloth" then
                displayLabel = "Moon"
            end
            bar.left:SetText(char .. "-" .. displayLabel)
        else
            -- Just show character name when CD name is hidden
            bar.left:SetText(char)
        end
        bar.right:SetText(SecondsToTime(remain) .. " | " .. readyAt)
        
        bar:Show()
        i = i + 1
        numVisible = numVisible + 1
    end
    
    -- Hide unused bars
    for j = i, #bars do bars[j]:Hide() end
    
    -- Resize container to exactly fit visible bars
    container:SetWidth(settings.barWidth)
    container:SetHeight(settings.barHeight * numVisible)
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
        settings.locked = false
        ApplyLockState()
        print("|cff33ff99PCT|r Bars unlocked (drag to move).")
    elseif args[1] == "lock" then
        settings.locked = true
        ApplyLockState()
        SaveContainerPosition()
        print("|cff33ff99PCT|r Bars locked.")
    elseif args[1] == "width" and tonumber(args[2]) then
        settings.barWidth = tonumber(args[2])
        print("|cff33ff99PCT|r Bar width set to", settings.barWidth)
        UpdateUI()
    elseif args[1] == "height" and tonumber(args[2]) then
        settings.barHeight = tonumber(args[2])
        print("|cff33ff99PCT|r Bar height set to", settings.barHeight)
        UpdateUI()
    elseif args[1] == "ready" then
        if args[2] and tonumber(args[2]) then
            -- Set threshold and enable filter (explicitly set on global table to ensure save)
            ProfessionCDTrackerDB.settings.readyThresholdHours = tonumber(args[2])
            ProfessionCDTrackerDB.settings.showReadyOnly = true
            settings.readyThresholdHours = ProfessionCDTrackerDB.settings.readyThresholdHours
            settings.showReadyOnly = ProfessionCDTrackerDB.settings.showReadyOnly
            print("|cff33ff99PCT|r Showing only cooldowns with < " .. ProfessionCDTrackerDB.settings.readyThresholdHours .. " hours remaining.")
            UpdateUI()
        else
            -- Toggle filter on/off (explicitly set on global table to ensure save)
            ProfessionCDTrackerDB.settings.showReadyOnly = not ProfessionCDTrackerDB.settings.showReadyOnly
            settings.showReadyOnly = ProfessionCDTrackerDB.settings.showReadyOnly
            if ProfessionCDTrackerDB.settings.showReadyOnly then
                print("|cff33ff99PCT|r Showing only cooldowns with < " .. ProfessionCDTrackerDB.settings.readyThresholdHours .. " hours remaining.")
            else
                print("|cff33ff99PCT|r Showing all cooldowns.")
            end
            UpdateUI()
        end
    elseif args[1] == "cdname" then
        -- Toggle CD name display (explicitly set on global table to ensure save)
        ProfessionCDTrackerDB.settings.showCDName = not ProfessionCDTrackerDB.settings.showCDName
        settings.showCDName = ProfessionCDTrackerDB.settings.showCDName
        if ProfessionCDTrackerDB.settings.showCDName then
            print("|cff33ff99PCT|r Cooldown names shown.")
        else
            print("|cff33ff99PCT|r Cooldown names hidden.")
        end
        UpdateUI()
    else
        print("|cff33ff99PCT|r Commands: /pct scan, /pct show, /pct hide, /pct lock, /pct unlock, /pct width <n>, /pct height <n>, /pct ready [<hr>], /pct cdname")
    end
end

-- Events
f:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        print("|cff33ff99PCT|r Loaded " .. ADDON_NAME .. " v" .. VERSION)
        -- Ensure settings table exists and sync local reference
        ProfessionCDTrackerDB.settings = ProfessionCDTrackerDB.settings or {}
        -- Update local settings reference to point to the (possibly reloaded) SavedVariables
        -- Note: Since 'settings' is a local reference, we need to ensure it points to the current table
        -- But actually, it's already a reference, so we just need to ensure values are set correctly
        if ProfessionCDTrackerDB.settings.showReadyOnly == nil then
            ProfessionCDTrackerDB.settings.showReadyOnly = false
        end
        if ProfessionCDTrackerDB.settings.readyThresholdHours == nil then
            ProfessionCDTrackerDB.settings.readyThresholdHours = 10
        end
        if ProfessionCDTrackerDB.settings.showCDName == nil then
            ProfessionCDTrackerDB.settings.showCDName = false
        end
        -- Restore early in case PLAYER_LOGIN timing varies
        RestoreContainerPosition()
        ApplyLockState()
        -- Migrate any legacy session-based cooldowns (expires using GetTime()) to epoch
        for realm, chars in pairs(ProfessionCDTrackerDB.realms or {}) do
            for char, data in pairs(chars or {}) do
                if data.cooldowns then
                    for key, cd in pairs(data.cooldowns) do
                        if cd.expires and not cd.expiresEpoch then
                            local remain = (cd.expires or 0) - GetTime()
                            if remain < 0 then remain = 0 end
                            -- Clamp to recorded duration when present
                            local dur = tonumber(cd.duration) or 0
                            if dur > 0 then
                                remain = math.min(remain, dur)
                            end
                            cd.expiresEpoch = time() + remain
                            cd.expires = nil
                            cd.start = nil
                        end
                    end
                end
            end
        end
    elseif event == "PLAYER_LOGIN" then
        ScanTrackedCooldowns()
        UpdateUI()
        container:Show()
    elseif event == "PLAYER_LOGOUT" then
        -- Ensure position/state saved
        SaveContainerPosition()
        -- Ensure all settings are explicitly saved (they should auto-save, but being explicit)
        -- Settings are already in ProfessionCDTrackerDB.settings which is a SavedVariable
    elseif event == "TRADE_SKILL_SHOW" then
        ScanTradeSkills()
        UpdateUI()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ScanItems()
        UpdateUI()
    end
end)

container:SetScript("OnUpdate", function()
    if container:IsShown() then UpdateUI() end
end)
