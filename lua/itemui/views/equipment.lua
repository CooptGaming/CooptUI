--[[
    Equipment View - CoOpt UI Equipment Companion
    Separate window showing currently equipped items (slots 0-22) in a grid.
    Part of ItemUI; Phase 3 of Equipment Companion.
--]]

local mq = require('mq')
require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')

local EquipmentView = {}

local EQUIPMENT_WINDOW_WIDTH = 220
local EQUIPMENT_WINDOW_HEIGHT = 380
local EQUIPMENT_GRID_COLS = 4
local EQUIPMENT_SLOT_SIZE = 36

-- Module interface: render equipment companion window
function EquipmentView.render(ctx)
    if not ctx.uiState.equipmentWindowShouldDraw then return end

    -- Position (Phase 4 will add sync; use saved or default)
    local eqX = ctx.layoutConfig.EquipmentWindowX or 0
    local eqY = ctx.layoutConfig.EquipmentWindowY or 0
    if eqX ~= 0 or eqY ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(eqX, eqY), ImGuiCond.FirstUseEver)
    end

    local w = ctx.layoutConfig.WidthEquipmentPanel or EQUIPMENT_WINDOW_WIDTH
    local h = ctx.layoutConfig.HeightEquipment or EQUIPMENT_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Equipment Companion##ItemUIEquipment", ctx.uiState.equipmentWindowOpen, windowFlags)
    ctx.uiState.equipmentWindowOpen = winOpen
    ctx.uiState.equipmentWindowShouldDraw = winOpen

    if not winOpen then ImGui.End(); return end
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then
        ctx.uiState.equipmentWindowOpen = false
        ctx.uiState.equipmentWindowShouldDraw = false
        ImGui.End()
        return
    end
    if not winVis then ImGui.End(); return end

    -- Save size when resized (if unlocked)
    if not ctx.uiState.uiLocked then
        local currentW, currentH = ImGui.GetWindowSize()
        if currentW and currentH and currentW > 0 and currentH > 0 then
            ctx.layoutConfig.WidthEquipmentPanel = currentW
            ctx.layoutConfig.HeightEquipment = currentH
        end
    end
    -- Save position when moved (Phase 4 will add sync flag; for now always save when moved)
    local currentX, currentY = ImGui.GetWindowPos()
    if currentX and currentY then
        if not ctx.layoutConfig.EquipmentWindowX or math.abs((ctx.layoutConfig.EquipmentWindowX or 0) - currentX) > 1 or
           not ctx.layoutConfig.EquipmentWindowY or math.abs((ctx.layoutConfig.EquipmentWindowY or 0) - currentY) > 1 then
            ctx.layoutConfig.EquipmentWindowX = currentX
            ctx.layoutConfig.EquipmentWindowY = currentY
            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end
    end

    ctx.theme.TextHeader("Equipment")
    ImGui.Separator()

    -- Grid: 23 slots (0-22), 4 columns. equipmentCache[slotIndex+1] = item or nil
    local cache = ctx.equipmentCache or {}
    for slotIndex = 0, 22 do
        if slotIndex > 0 and slotIndex % EQUIPMENT_GRID_COLS == 0 then
            ImGui.NewLine()
        end
        ImGui.SameLine()

        local cacheIdx = slotIndex + 1
        local item = cache[cacheIdx]
        local slotLabel = ctx.getEquipmentSlotLabel and ctx.getEquipmentSlotLabel(slotIndex) or ("Slot " .. slotIndex)

        ImGui.PushID("EqSlot" .. slotIndex)
        if item and item.icon and item.icon ~= 0 then
            if ctx.drawItemIcon then
                ctx.drawItemIcon(item.icon, EQUIPMENT_SLOT_SIZE)
            end
        else
            if ctx.drawEmptySlotIcon then
                ctx.drawEmptySlotIcon()
            else
                ImGui.Dummy(ImVec2(EQUIPMENT_SLOT_SIZE, EQUIPMENT_SLOT_SIZE))
            end
        end

        if ImGui.IsItemHovered() then
            if item and item.name then
                local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip({ bag = 0, slot = slotIndex, source = "equipped" }, "equipped")) or item
                local opts = { source = "equipped", bag = 0, slot = slotIndex }
                local ok, effects, tw, th = pcall(ItemTooltip.prepareTooltipContent, showItem, ctx, opts)
                if ok and effects then opts.effects = effects end
                ItemTooltip.beginItemTooltip(tw or 400, th or 300)
                ImGui.Text("Stats")
                ImGui.Separator()
                ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                ImGui.EndTooltip()
            else
                ImGui.BeginTooltip()
                ImGui.Text(slotLabel .. " (empty)")
                ImGui.EndTooltip()
            end
        end
        ImGui.PopID()
    end

    ImGui.End()
end

return EquipmentView
