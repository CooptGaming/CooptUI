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
local EQUIPMENT_SLOT_SIZE = 40
local SLOT_SPACING = 4
local ROW_GAP_OFFSET = -2  -- pull next row up (px) for tighter vertical packing
local SLOT_FRAME_PADDING = 2  -- inner padding so icon sits inside the slot frame

-- Paper-doll order from EQUI_Inventory.xml (Y then X): matches in-game Inventory tab layout.
-- Row 1: Ear, Head, Face, Ear (Y=12)
-- Row 2: Chest, Neck (Y=55)
-- Row 3: Back, Arms (Y=98-99)
-- Row 4: Shoulder, Waist (Y=141-142)
-- Row 5: Wrist, Wrist (Y=185)
-- Row 6: Legs, Hands, Charm, Feet (Y=228)
-- Row 7: Ring, Ring, Power (Y=272)
-- Row 8: Primary, Secondary, Ranged, Ammo (Y=316)
local EQUIPMENT_PAPER_DOLL_ORDER = {
    1, 2, 3, 4,       -- row 1
    17, 5,            -- row 2
    8, 7,             -- row 3
    6, 20,            -- row 4
    9, 10,            -- row 5
    18, 12, 0, 19,    -- row 6
    15, 16, 21,       -- row 7
    13, 14, 11, 22,   -- row 8
}
local EQUIPMENT_ROW_LENGTHS = { 4, 2, 2, 2, 2, 4, 3, 4 }

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

    -- Tighter vertical spacing between rows (icons unchanged)
    local style = ImGui.GetStyle()
    local spacingX = (style and style.ItemSpacing and style.ItemSpacing.x) or SLOT_SPACING
    ImGui.PushStyleVar(ImGuiStyleVar.ItemSpacing, spacingX, 0)

    -- Grid: paper-doll order; rows 2-5 are [icon] [blank] [blank] [icon] (full width)
    local cache = ctx.equipmentCache or {}
    local idx = 1
    local maxCols = 4
    for row = 1, #EQUIPMENT_ROW_LENGTHS do
        local rowLen = EQUIPMENT_ROW_LENGTHS[row]
        local isSparseRow = (row >= 2 and row <= 5 and rowLen == 2)  -- rows 2-5: 1 icon, 2 blank, 1 icon
        local numCells = isSparseRow and 4 or rowLen
        -- Center every row (same spacing, row as a group centered)
        do
            local availW = ImGui.GetContentRegionAvail()
            if type(availW) ~= "number" then availW = select(1, ImGui.GetContentRegionAvail()) end
            local avail = (availW and availW > 0) and availW or (maxCols * (EQUIPMENT_SLOT_SIZE + SLOT_SPACING) - SLOT_SPACING)
            local rowWidth = numCells * EQUIPMENT_SLOT_SIZE + (numCells - 1) * SLOT_SPACING
            local offset = math.max(0, (avail - rowWidth) / 2)
            if offset > 0 then
                ImGui.SetCursorPosX(ImGui.GetCursorPosX() + offset)
            end
        end
        for col = 1, numCells do
            if col > 1 then ImGui.SameLine(0, SLOT_SPACING) end
            local slotIndex
            if isSparseRow then
                if col == 1 or col == 4 then
                    slotIndex = EQUIPMENT_PAPER_DOLL_ORDER[idx]
                    idx = idx + 1
                else
                    slotIndex = nil  -- blank
                end
            else
                slotIndex = EQUIPMENT_PAPER_DOLL_ORDER[idx]
                idx = idx + 1
            end

            local cellId = (slotIndex ~= nil) and ("EqSlot" .. slotIndex) or ("EqBlank" .. row .. "_" .. col)
            ImGui.PushID(cellId)

            if slotIndex == nil then
                -- Empty space (placeholder): no grey square, just reserve layout space
                ImGui.Dummy(ImVec2(EQUIPMENT_SLOT_SIZE, EQUIPMENT_SLOT_SIZE))
            else
                -- Real equipment slot: grey square, darker when empty; center icon inside
                local cacheIdx = slotIndex + 1
                local item = cache[cacheIdx]
                local hasItem = item and item.icon and item.icon ~= 0
                local slotBg = hasItem and ImVec4(0.18, 0.18, 0.22, 0.95) or ImVec4(0.11, 0.11, 0.14, 0.95)
                if ImGuiCol.ChildBg then
                    ImGui.PushStyleColor(ImGuiCol.ChildBg, slotBg)
                end
                local childFlags = (ImGuiWindowFlags and ImGuiWindowFlags.NoScrollbar) or 0
                if ImGui.BeginChild("EqSlotBg" .. cellId, ImVec2(EQUIPMENT_SLOT_SIZE, EQUIPMENT_SLOT_SIZE), false, childFlags) then
                    local iconSize = EQUIPMENT_SLOT_SIZE - SLOT_FRAME_PADDING * 2
                    local cw, ch = ImGui.GetContentRegionAvail()
                    if type(cw) == "table" then cw, ch = cw.x or EQUIPMENT_SLOT_SIZE, (cw.y or cw.x or EQUIPMENT_SLOT_SIZE) end
                    if type(cw) ~= "number" or cw <= 0 then cw = EQUIPMENT_SLOT_SIZE end
                    if type(ch) ~= "number" or ch <= 0 then ch = EQUIPMENT_SLOT_SIZE end
                    local ox = math.max(0, (cw - iconSize) / 2)
                    local oy = math.max(0, (ch - iconSize) / 2)
                    ImGui.SetCursorPosX(ox)
                    ImGui.SetCursorPosY(ImGui.GetCursorPosY() + oy)
                    local slotLabel = ctx.getEquipmentSlotLabel and ctx.getEquipmentSlotLabel(slotIndex) or ("Slot " .. slotIndex)
                    if hasItem then
                        if ctx.drawItemIcon then
                            ctx.drawItemIcon(item.icon, iconSize)
                        end
                    else
                        if ctx.drawEmptySlotIcon then
                            ctx.drawEmptySlotIcon()
                        else
                            ImGui.Dummy(ImVec2(iconSize, iconSize))
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
                end
                ImGui.EndChild()
                if ImGuiCol.ChildBg then
                    ImGui.PopStyleColor()
                end
                -- Slot border
                pcall(function()
                    local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
                    if not dl then return end
                    local rmin = ImGui.GetItemRectMin and ImGui.GetItemRectMin()
                    local rmax = ImGui.GetItemRectMax and ImGui.GetItemRectMax()
                    if not rmin or not rmax then return end
                    local borderCol = ImGui.GetColorU32 and ImGui.GetColorU32(ImVec4(0.35, 0.35, 0.4, 0.9))
                    if not borderCol then borderCol = 0xFF595966 end
                    if dl.AddRect then
                        dl.AddRect(rmin, rmax, borderCol)
                    elseif dl.add_rect then
                        dl.add_rect(rmin, rmax, borderCol)
                    end
                end)
            end
            ImGui.PopID()
        end
        ImGui.NewLine()
        if row < #EQUIPMENT_ROW_LENGTHS and ROW_GAP_OFFSET ~= 0 then
            ImGui.SetCursorPosY(ImGui.GetCursorPosY() + ROW_GAP_OFFSET)
        end
    end

    ImGui.PopStyleVar()

    ImGui.End()
end

return EquipmentView
