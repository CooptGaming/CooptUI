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
function ItemTooltip.getCanUseInfo(item, source)
    local result = { canUse = true, reason = nil }
    if not item then return result end
    source = source or (item.source) or "inv"
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Level then return result end
    local myLevel = tonumber(Me.Level()) or 0
    local reqLevel = (item.requiredLevel and item.requiredLevel > 0) and item.requiredLevel or nil
    if reqLevel and myLevel < reqLevel then
        result.canUse = false
        result.reason = "Requires level " .. tostring(reqLevel)
        return result
    end
    local myDeity = Me.Deity and Me.Deity() and tostring(Me.Deity()):lower() or ""
    if item.deity and item.deity ~= "" then
        local allowed = false
        for part in (tostring(item.deity):lower()):gmatch("%S+") do
            if part == myDeity then allowed = true break end
        end
        if not allowed then
            result.canUse = false
            result.reason = "Requires deity: " .. tostring(item.deity)
            return result
        end
    end
    local myClass = Me.Class and tostring(Me.Class() or ""):lower() or ""
    local myRace = Me.Race and tostring(Me.Race() or ""):lower() or ""
    if item.class and item.class ~= "" and item.class:lower() ~= "all" then
        local ok = false
        for part in (tostring(item.class):lower()):gmatch("%S+") do
            if part == myClass then ok = true break end
        end
        if not ok then
            result.canUse = false
            result.reason = "Requires class: " .. tostring(item.class)
            return result
        end
    end
    if item.race and item.race ~= "" and item.race:lower() ~= "all" then
        local ok = false
        for part in (tostring(item.race):lower()):gmatch("%S+") do
            if part == myRace then ok = true break end
        end
        if not ok then
            result.canUse = false
            result.reason = "Requires race: " .. tostring(item.race)
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
    local ok = pcall(function() ItemTooltip.renderItemDisplayContent(item, ctx, opts) end)
    if not ok then
        ImGui.Text("Item stats")
    end
end

return ItemTooltip
