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
    local ok, err = pcall(function() ItemTooltip.renderItemDisplayContent(item, ctx, opts) end)
    if not ok then
        ImGui.Text("Item stats")
        local diagnostics = require('itemui.core.diagnostics')
        diagnostics.recordError("Item tooltip", "Tooltip render failed", err)
    end
end

--- Task 7.5: Get first equipment slot (0-22) for an equippable item and the currently equipped item in that slot.
--- Returns: slotIndex (number 0-22, or nil if not equippable), equippedItem (full stats table or nil if slot empty).
function ItemTooltip.getComparisonTarget(item, ctx, source)
    if not item or not ctx then return nil, nil end
    source = source or item.source or "inv"
    if source ~= "inv" and source ~= "bank" then return nil, nil end
    local bag, slot = item.bag, item.slot
    if bag == nil or slot == nil then return nil, nil end
    local it = itemHelpers.getItemTLO(bag, slot, source)
    if not it or not it.ID or it.ID() == 0 then return nil, nil end
    local set = itemHelpers.getWornSlotIndicesFromTLO(it)
    if not set or (type(set) == "table" and not next(set)) then return nil, nil end
    local slotIndex
    if set == "all" then
        slotIndex = 0
    else
        for i = 0, 22 do
            if set[i] then slotIndex = i; break end
        end
    end
    if slotIndex == nil then return nil, nil end
    local equippedRaw = ctx.equipmentCache and ctx.equipmentCache[slotIndex + 1]
    local hasEquipped = equippedRaw and ((equippedRaw.id and equippedRaw.id ~= 0) or (equippedRaw.name and equippedRaw.name ~= ""))
    local equippedItem = nil
    if hasEquipped and ctx.getItemStatsForTooltip then
        equippedItem = ctx.getItemStatsForTooltip({ bag = 0, slot = slotIndex }, "equipped")
    end
    return slotIndex, equippedItem
end

--- Task 7.5: Render side-by-side comparison tooltip (hovered inv/bank item vs equipped in same slot).
--- Caller must call BeginTooltip before and EndTooltip after. Uses COMPARISON_TOOLTIP_WIDTH.
function ItemTooltip.renderComparisonTooltip(hoveredItem, equippedItem, slotIndex, ctx, opts)
    if not hoveredItem or not ctx then return end
    opts = opts or {}
    local source = opts.source or hoveredItem.source or "inv"
    local slotLabel = (ctx.getEquipmentSlotLabel and ctx.getEquipmentSlotLabel(slotIndex)) or ("Slot " .. slotIndex)
    local compW = tooltip_layout.COMPARISON_TOOLTIP_WIDTH or 1000
    local colW = tooltip_layout.COMPARISON_TOOLTIP_COL_WIDTH or 500
    local estH = 420
    ItemTooltip.beginItemTooltip(compW, estH)
    ImGui.TextColored(ImVec4(0.6, 0.85, 1.0, 1.0), "Compare: " .. slotLabel)
    ImGui.Spacing()
    ImGui.Columns(2, "##CompareHeader", false)
    ImGui.SetColumnWidth(0, colW)
    ImGui.SetColumnWidth(1, colW)
    -- Left: hovered item
    if ctx.drawItemIcon and hoveredItem.icon and hoveredItem.icon > 0 then
        pcall(function() ctx.drawItemIcon(hoveredItem.icon, 24) end)
        ImGui.SameLine()
    end
    ImGui.TextWrapped(hoveredItem.name or "—")
    ImGui.TextColored(ImVec4(0.5, 0.65, 0.7, 1.0), source == "bank" and "Bank" or "Inventory")
    ImGui.NextColumn()
    -- Right: equipped item
    if equippedItem and equippedItem.name then
        if ctx.drawItemIcon and equippedItem.icon and equippedItem.icon > 0 then
            pcall(function() ctx.drawItemIcon(equippedItem.icon, 24) end)
            ImGui.SameLine()
        end
        ImGui.TextWrapped(equippedItem.name or "—")
        ImGui.TextColored(ImVec4(0.5, 0.65, 0.7, 1.0), "Equipped")
    else
        ImGui.TextColored(ImVec4(0.55, 0.55, 0.6, 1.0), "(no item equipped)")
        ImGui.TextColored(ImVec4(0.5, 0.65, 0.7, 1.0), "Equipped")
    end
    ImGui.NextColumn()
    ImGui.Columns(1)
    ImGui.Separator()
    ImGui.Spacing()
    local api = {
        formatSize = tooltip_data.formatSize,
        attrLine = tooltip_data.attrLine,
        itemHelpers = itemHelpers,
        tooltip_layout = tooltip_layout,
    }
    tooltip_render.renderComparisonStatBlocks(hoveredItem, equippedItem, ctx, api, colW)
    ImGui.Columns(1)
    ImGui.Spacing()
    ImGui.TextColored(ImVec4(0.55, 0.55, 0.6, 1.0), "Right-click → CoOp UI Item Display for full details.")
end

return ItemTooltip
