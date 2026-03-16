--[[
    Item stats tooltip: matches in-game Item Display (Description) for all items.
    Shows every property: name, ID, type, class/race/slot, augment slots, item info,
    primary stats (base+heroic), resistances, combat/utility stats, item effects, value.
    Used by Inventory, Bank, Sell, and Augments views on icon hover.
    opts.source = "inv" (default) or "bank" for Class/Race/Slot TLO when not cached.
--]]

local mq = require('mq')
require('ImGui')
local itemHelpers = require('itemui.utils.item_helpers')
local tooltip_layout = require('itemui.utils.tooltip_layout')
local tooltip_render = require('itemui.utils.tooltip_render')
local tooltip_data = require('itemui.utils.tooltip_data')

local ItemTooltip = {}

function ItemTooltip.beginItemTooltip(width, height)
    tooltip_layout.beginItemTooltip(width, height)
end

function ItemTooltip.prepareTooltipContent(item, ctx, opts)
    return tooltip_data.prepareTooltipContent(item, ctx, opts)
end

function ItemTooltip.invalidateTooltipCache()
    tooltip_data.invalidateTooltipCache()
end

--- Returns true if the current player can use the item (class, race, deity, level).
--- Used internally for name color; use getCanUseInfo for canUse + reason.
local function canPlayerUseItem(item, source)
    local info = ItemTooltip.getCanUseInfo(item, source)
    return info.canUse
end

--- Returns { canUse = boolean, reason = string|nil } for the current player and item.
--- reason is only set when canUse is false (e.g. "Requires level 85", "Requires Bard").
--- When item.requiredLevel/class/race/deity are missing (e.g. plugin scan rows), fetches from TLO so restrictions are applied.
function ItemTooltip.getCanUseInfo(item, source)
    local result = { canUse = true, reason = nil }
    if not item then return result end
    source = source or (item.source) or "inv"
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Level then return result end
    local myLevel = tonumber(Me.Level()) or 0
    -- Use item fields; if missing and we have bag/slot, fetch from TLO (plugin scan rows may not have class/race/deity/level)
    local reqLevel = (item.requiredLevel ~= nil and item.requiredLevel > 0) and item.requiredLevel or nil
    local clsStr = item.class and tostring(item.class) or ""
    local raceStr = item.race and tostring(item.race) or ""
    local deityStr = item.deity and tostring(item.deity) or ""
    if (reqLevel == nil or clsStr == "" or raceStr == "" or deityStr == "") and item.bag and item.slot and itemHelpers.getItemTLO then
        local it = itemHelpers.getItemTLO(item.bag, item.slot, source)
        if it and it.ID and it.ID() and it.ID() ~= 0 then
            if reqLevel == nil then
                local r = it.RequiredLevel and it.RequiredLevel()
                if r and r > 0 then reqLevel = r end
            end
            if clsStr == "" or raceStr == "" then
                local c, r = itemHelpers.getClassRaceStringsFromTLO(it)
                if clsStr == "" then clsStr = c and tostring(c) or "" end
                if raceStr == "" then raceStr = r and tostring(r) or "" end
            end
            if deityStr == "" and itemHelpers.getDeityStringFromTLO then
                deityStr = itemHelpers.getDeityStringFromTLO(it) or ""
            end
        end
    end
    if reqLevel and myLevel < reqLevel then
        result.canUse = false
        result.reason = "Requires level " .. tostring(reqLevel)
        return result
    end
    local myDeity = Me.Deity and Me.Deity() and tostring(Me.Deity()):lower() or ""
    if deityStr and deityStr ~= "" then
        local allowed = false
        for part in (tostring(deityStr):lower()):gmatch("%S+") do
            if part == myDeity then allowed = true break end
        end
        if not allowed then
            result.canUse = false
            result.reason = "Requires deity: " .. tostring(deityStr)
            return result
        end
    end
    local myClass = Me.Class and tostring(Me.Class() or ""):lower() or ""
    local myRace = Me.Race and tostring(Me.Race() or ""):lower() or ""
    if clsStr and clsStr ~= "" and clsStr:lower() ~= "all" then
        local ok = false
        for part in (tostring(clsStr):lower()):gmatch("%S+") do
            if part == myClass then ok = true break end
        end
        if not ok then
            result.canUse = false
            result.reason = "Requires class: " .. tostring(clsStr)
            return result
        end
    end
    if raceStr and raceStr ~= "" and raceStr:lower() ~= "all" then
        local ok = false
        for part in (tostring(raceStr):lower()):gmatch("%S+") do
            if part == myRace then ok = true break end
        end
        if not ok then
            result.canUse = false
            result.reason = "Requires race: " .. tostring(raceStr)
            return result
        end
    end
    return result
end

--- Render item display content (two-column layout: header/stats/augs in col1, effects/info/spell/value in col2).
--- Used by both the on-hover tooltip and the CoOpt Item Display window. Does not call BeginTooltip/EndTooltip.
function ItemTooltip.renderItemDisplayContent(item, ctx, opts)
    if not item then return end
    local api = {
        getTypeLine = tooltip_data.getTypeLine,
        formatSize = tooltip_data.formatSize,
        attrLine = tooltip_data.attrLine,
        slotStringToDisplay = tooltip_data.slotStringToDisplay,
        getSocketItemStats = tooltip_data.getSocketItemStats,
        getOrnamentFromIt = tooltip_data.getOrnamentFromIt,
        getAugmentSlotLinesFromIt = tooltip_data.getAugmentSlotLinesFromIt,
        getAugmentSlotLines = tooltip_data.getAugmentSlotLines,
        itemHelpers = itemHelpers,
        tooltip_layout = tooltip_layout,
        ORNAMENT_SLOT_INDEX = tooltip_data.ORNAMENT_SLOT_INDEX,
        AUG_TYPE_NAMES = tooltip_data.AUG_TYPE_NAMES,
        AUG_RESTRICTION_NAMES = tooltip_data.AUG_RESTRICTION_NAMES,
        SIZE_NAMES = tooltip_data.SIZE_NAMES,
        canPlayerUseItem = canPlayerUseItem,
        prepareTooltipContent = ItemTooltip.prepareTooltipContent,
        beginItemTooltip = ItemTooltip.beginItemTooltip,
        renderStatsTooltip = ItemTooltip.renderStatsTooltip,
    }
    tooltip_render.renderItemDisplayContent(item, ctx, opts, api)
end

--- Render full item tooltip matching in-game Item Display. Shows every property.
--- Runs content in pcall so binding/API errors do not leave tooltip stack inconsistent.
--- Caller must call BeginTooltip before and EndTooltip after.
function ItemTooltip.renderStatsTooltip(item, ctx, opts)
    if not item then return end
    opts = opts or {}
    local ok, err = pcall(function() ItemTooltip.renderItemDisplayContent(item, ctx, opts) end)
    if not ok then
        ImGui.Text("Item stats")
        local diagnostics = require('itemui.core.diagnostics')
        diagnostics.recordError("Item tooltip", "Tooltip render failed", err)
    end
end

return ItemTooltip
