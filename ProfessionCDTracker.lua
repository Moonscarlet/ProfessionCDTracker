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
if settings.limitEnabled == nil then settings.limitEnabled = false end
if settings.limitCount == nil then settings.limitCount = 10 end
if settings.blacklist == nil then settings.blacklist = {} end
if settings.scale == nil then settings.scale = 1.0 end
if settings.opacity == nil then settings.opacity = 1.0 end

-- Frame + Events
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:RegisterEvent("TRADE_SKILL_UPDATE")
f:RegisterEvent("PLAYER_LOGOUT")
f:RegisterEvent("BAG_UPDATE_COOLDOWN")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

-- Our tracked cooldowns
local TRACKED = {
    ["Mooncloth"] = { label = "Mooncloth", type = "trade", icon = 14342, duration = 331200 }, --added 1 hr to cd (old:327600)
    ["Transmute: Arcanite"] = { label = "Transmute: Arcanite", type = "trade", icon = 12360, duration = 82800 },
    ["Transmute: Life to Earth"] = { label = "Transmute: Life to Earth", type = "trade", icon = 16893, sharedCooldown = "transmute_life_undeath", duration = 72000 },
    ["Transmute: Undeath to Water"] = { label = "Transmute: Undeath to Water", type = "trade", icon = 16893, sharedCooldown = "transmute_life_undeath", duration = 72000 },
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
    container:SetScale(settings.scale or 1.0)
    container:SetAlpha(settings.opacity or 1.0)
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
    
    -- Handle hardcoded durations for tracked items
    local trackInfo = TRACKED[key]
    local hardcodedDuration = trackInfo and trackInfo.duration

    -- Persist as absolute epoch so cross-session math is correct
    local nowUI = GetTime()
    local remain = math.max(0, (start or 0) + (duration or 0) - nowUI)
    
    if duration and duration > 0 then
        -- Clamp to the known duration to avoid bogus huge remains from bad APIs/saves
        -- But if we have a hardcoded duration, use that as the clamp cap if larger
        local cap = hardcodedDuration or duration
        remain = math.min(remain, cap)
    end

    -- Use hardcoded duration for the DB entry if available
    local storedDuration = hardcodedDuration or duration

    local expiresEpoch = time() + remain
    charDB.cooldowns[key] = {
        duration = storedDuration,
        expiresEpoch = expiresEpoch,
    }

    -- Root cause fix: If this is a shared cooldown, update all other members of the group
    if trackInfo and trackInfo.sharedCooldown then
        for otherKey, otherInfo in pairs(TRACKED) do
            if otherKey ~= key and otherInfo.sharedCooldown == trackInfo.sharedCooldown then
                charDB.cooldowns[otherKey] = {
                    duration = storedDuration,
                    expiresEpoch = expiresEpoch,
                }
            end
        end
    end
end

-- Helper to get all tracked cooldowns, sorted and filtered
local function GetAllCooldowns()
    local cooldownData = {}
    local now = time()
    for realm, chars in pairs(ProfessionCDTrackerDB.realms) do
        for char, data in pairs(chars) do
            if data.cooldowns then
                for key, cd in pairs(data.cooldowns) do
                    local expiresEpoch = cd.expiresEpoch or cd.expires
                    if expiresEpoch then
                        local remain = math.max(0, expiresEpoch - now)
                        local duration = cd.duration or 1
                        
                        local info = TRACKED[key] or TRACKED[cd.label]
                        if info and info.duration then duration = info.duration end

                        local label = (type(key) == "string" and key) or (info and info.label) or "?"
                        
                        table.insert(cooldownData, {
                            char = char,
                            realm = realm,
                            key = key,
                            label = label,
                            remain = remain,
                            duration = duration,
                            expiresEpoch = expiresEpoch,
                            icon = info and info.icon,
                            sharedCooldown = info and info.sharedCooldown
                        })
                    end
                end
            end
        end
    end
    
    -- Filter out duplicates for shared cooldowns (keep the one with longest remaining time)
    local sharedCooldownGroups = {}
    local filteredByShared = {}
    for _, data in ipairs(cooldownData) do
        if data.sharedCooldown then
            local groupKey = data.realm .. ":" .. data.char .. ":" .. data.sharedCooldown
            if not sharedCooldownGroups[groupKey] or data.expiresEpoch > sharedCooldownGroups[groupKey].expiresEpoch then
                sharedCooldownGroups[groupKey] = data
            end
        else
            table.insert(filteredByShared, data)
        end
    end
    for _, data in pairs(sharedCooldownGroups) do
        table.insert(filteredByShared, data)
    end
    
    -- Sort by remaining time (ascending - least time first)
    table.sort(filteredByShared, function(a, b)
        return a.remain < b.remain
    end)
    
    return filteredByShared
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
    -- Get all cooldowns from our new helper
    local cooldownData = GetAllCooldowns()
    
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
    
    -- Now update bars in sorted order
    local i = 1
    local numVisible = 0
    for _, data in ipairs(cooldownData) do
        if settings.limitEnabled and numVisible >= settings.limitCount then
            break
        end
        local remain = data.remain
        local duration = data.duration
        local char = data.char
        --trim char name to 10 characters
        char = string.sub(char, 1, 7)
        local label = data.label
        local expiresEpoch = data.expiresEpoch
        local iconId = data.icon
        
        local nowEpoch = time()
        local readyAt = date("%H:%M", nowEpoch + remain)
        
        local bar = bars[i] or CreateBar(i)
        
        bar:SetWidth(settings.barWidth)
        bar:SetHeight(settings.barHeight)
        bar:SetMinMaxValues(0, duration)
        bar:SetValue(duration - remain)
        
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
        if remain <= 0 then
            bar.right:SetText("Ready")
        else
            bar.right:SetText(SecondsToTime(remain) .. " | " .. readyAt)
        end
        
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
    if args[1] == "show" then
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
    elseif args[1] == "limit" then
        if args[2] and tonumber(args[2]) then
            local val = tonumber(args[2])
            ProfessionCDTrackerDB.settings.limitCount = val
            ProfessionCDTrackerDB.settings.limitEnabled = true
            settings.limitCount = val
            settings.limitEnabled = true
            print("|cff33ff99PCT|r Limiting bars to " .. val)
        else
            ProfessionCDTrackerDB.settings.limitEnabled = not ProfessionCDTrackerDB.settings.limitEnabled
            settings.limitEnabled = ProfessionCDTrackerDB.settings.limitEnabled
            if settings.limitEnabled then
                print("|cff33ff99PCT|r Limiting bars to " .. settings.limitCount)
            else
                print("|cff33ff99PCT|r Bar limit disabled.")
            end
        end
        UpdateUI()
    elseif args[1] == "scale" and tonumber(args[2]) then
        local val = tonumber(args[2])
        settings.scale = val
        container:SetScale(val)
        print("|cff33ff99PCT|r Scale set to", val)
    elseif args[1] == "opacity" and tonumber(args[2]) then
        local val = tonumber(args[2])
        settings.opacity = val
        container:SetAlpha(val)
        print("|cff33ff99PCT|r Opacity set to", val)
    elseif args[1] == "blacklist" then
        local name = args[2]
        if not name or name == "" then
            print("|cff33ff99PCT|r Blacklisted characters:")
            local found = false
            for bName, _ in pairs(settings.blacklist) do
                print("  - " .. bName)
                found = true
            end
            if not found then print("  (none)") end
            print("Usage: /pct blacklist <name>")
        else
            -- Capitalize first letter of name for consistency
            name = name:sub(1,1):upper() .. name:sub(2):lower()
            if settings.blacklist[name] then
                settings.blacklist[name] = nil
                print("|cff33ff99PCT|r Removed " .. name .. " from blacklist.")
            else
                settings.blacklist[name] = true
                print("|cff33ff99PCT|r Added " .. name .. " to blacklist.")
            end
        end
    elseif args[1] == "prepare" then
        local currentName = UnitName("player")
        local currentRealm = GetRealmName()

        -- Use the helper to find the most ready character
        local cooldownData = GetAllCooldowns()
        local nextChar = nil
        
        -- pass 1: Find the first NON-blacklisted character that has a ready cooldown
        for _, data in ipairs(cooldownData) do
            if (data.char ~= currentName or data.realm ~= currentRealm) and not settings.blacklist[data.char] then
                if data.remain <= 0 then
                    nextChar = data.char
                    break
                end
            end
        end

        -- pass 2: Find the first blacklisted character that has a ready cooldown
        if not nextChar then
            for _, data in ipairs(cooldownData) do
                if (data.char ~= currentName or data.realm ~= currentRealm) and settings.blacklist[data.char] then
                    if data.remain <= 0 then
                        nextChar = data.char
                        break
                    end
                end
            end
        end

        -- pass 3: No one is ready. Pick the absolute soonest character, regardless of blacklist.
        if not nextChar then
            for _, data in ipairs(cooldownData) do
                if (data.char ~= currentName or data.realm ~= currentRealm) then
                    nextChar = data.char
                    break
                end
            end
        end

        local isBlacklisted = settings.blacklist[currentName]

        -- Only deactivate current if NOT blacklisted
        if not isBlacklisted then
            SendChatMessage(".char deactivate " .. currentName, "SAY")
        else
            print("|cff33ff99PCT|r " .. currentName .. " is blacklisted. Skipping deactivation.")
        end

        if nextChar then
            if not isBlacklisted then
                print("|cff33ff99PCT|r Deactivating " .. currentName .. " and activating " .. nextChar .. ".")
            else
                print("|cff33ff99PCT|r Activating " .. nextChar .. ".")
            end
            SendChatMessage(".char activate " .. nextChar, "SAY")
        elseif not isBlacklisted then
            print("|cff33ff99PCT|r Deactivating " .. currentName .. ". No other character with ready cooldowns found.")
        else
            print("|cff33ff99PCT|r No other character with ready cooldowns found.")
        end
    else
        print("|cff33ff99PCT|r Commands:")
        print("  /pct show - show the bars")
        print("  /pct hide - hide the bars")
        print("  /pct lock - lock the bars")
        print("  /pct unlock - unlock the bars")
        print("  /pct width <n> - set bar width")
        print("  /pct height <n> - set bar height")
        print("  /pct scale <n> - set overall UI scale")
        print("  /pct opacity <n> - set overall UI opacity")
        print("  /pct ready [<hr>] - filter by ready time")
        print("  /pct cdname - toggle cooldown names")
        print("  /pct limit [<n>] - limit number of bars")
        print("  /pct blacklist [<name>] - manage character blacklist")
        print("  /pct prepare - cycle to next character")
    end
end

-- Events
f:SetScript("OnEvent", function(self, event, ...)
    local arg1, arg2 = ...
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        print("|cff33ff99PCT|r Loaded " .. ADDON_NAME .. " v" .. VERSION)
        -- Ensure settings table exists and sync local reference
        ProfessionCDTrackerDB.settings = ProfessionCDTrackerDB.settings or {}
        settings = ProfessionCDTrackerDB.settings
        
        if ProfessionCDTrackerDB.settings.showReadyOnly == nil then
            ProfessionCDTrackerDB.settings.showReadyOnly = false
        end
        if ProfessionCDTrackerDB.settings.readyThresholdHours == nil then
            ProfessionCDTrackerDB.settings.readyThresholdHours = 10
        end
        if ProfessionCDTrackerDB.settings.showCDName == nil then
            ProfessionCDTrackerDB.settings.showCDName = false
        end
        if ProfessionCDTrackerDB.settings.limitEnabled == nil then
            ProfessionCDTrackerDB.settings.limitEnabled = false
        end
        if ProfessionCDTrackerDB.settings.limitCount == nil then
            ProfessionCDTrackerDB.settings.limitCount = 10
        end
        if ProfessionCDTrackerDB.settings.blacklist == nil then
            ProfessionCDTrackerDB.settings.blacklist = {}
        end
        if ProfessionCDTrackerDB.settings.scale == nil then
            ProfessionCDTrackerDB.settings.scale = 1.0
        end
        if ProfessionCDTrackerDB.settings.opacity == nil then
            ProfessionCDTrackerDB.settings.opacity = 1.0
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
    elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
        ScanTradeSkills()
        UpdateUI()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        ScanItems()
        UpdateUI()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, spellName = arg1, arg2
        if unit == "player" and TRACKED[spellName] then
            ScanTradeSkills()
            
            -- Force hardcoded duration on craft completion
            local info = TRACKED[spellName]
            if info and info.duration then
                SaveCooldown(spellName, GetTime(), info.duration)
            end
            
            UpdateUI()
        end
    end
end)

container:SetScript("OnUpdate", function()
    if container:IsShown() then UpdateUI() end
end)
