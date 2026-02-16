--[[
    Item Display View - CoOpt UI Item Display window

    Persistent window showing the same content as the on-hover tooltip (stats, augments,
    ornaments, effects, etc.). Opened from item context menu ("Item Display") in
    Inventory, Sell, Bank, and Augments views. Single scrollable panel (no Lore tab).
--]]

require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')

local ItemDisplayView = {}

local ITEM_DISPLAY_WINDOW_WIDTH = 760
local ITEM_DISPLAY_WINDOW_HEIGHT = 520

-- Module interface: render Item Display pop-out window
function ItemDisplayView.render(ctx)
    if not ctx.uiState.itemDisplayWindowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig
    local itemDisplayItem = ctx.uiState.itemDisplayItem

    -- Position: use saved or default
    local px = layoutConfig.ItemDisplayWindowX or 0
    local py = layoutConfig.ItemDisplayWindowY or 0
    if px and py and (px ~= 0 or py ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.FirstUseEver)
    end

    local w = layoutConfig.WidthItemDisplayPanel or ITEM_DISPLAY_WINDOW_WIDTH
    local h = layoutConfig.HeightItemDisplay or ITEM_DISPLAY_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Item Display##ItemUIItemDisplay", ctx.uiState.itemDisplayWindowOpen, windowFlags)
    ctx.uiState.itemDisplayWindowOpen = winOpen
    ctx.uiState.itemDisplayWindowShouldDraw = winOpen

    if not winOpen then ImGui.End(); return end
    if ImGui.IsKeyPressed(ImGuiKey.Escape) then
        ctx.uiState.itemDisplayWindowOpen = false
        ctx.uiState.itemDisplayWindowShouldDraw = false
        ImGui.End()
        return
    end
    if not winVis then ImGui.End(); return end

    -- Persist position/size when changed
    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthItemDisplayPanel = cw
            layoutConfig.HeightItemDisplay = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy then
        if not layoutConfig.ItemDisplayWindowX or math.abs(layoutConfig.ItemDisplayWindowX - cx) > 1 or
           not layoutConfig.ItemDisplayWindowY or math.abs(layoutConfig.ItemDisplayWindowY - cy) > 1 then
            layoutConfig.ItemDisplayWindowX = cx
            layoutConfig.ItemDisplayWindowY = cy
            if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end
    end

    -- Content: scrollable child with shared item display content
    if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
        if not itemDisplayItem or not itemDisplayItem.item then
            ImGui.TextColored(ImVec4(0.7, 0.7, 0.7, 1.0), "No item selected. Right-click an item and choose \"CoOp UI Item Display\" to open.")
        else
            local showItem = itemDisplayItem.item
            local opts = {
                source = itemDisplayItem.source or "inv",
                bag = itemDisplayItem.bag,
                slot = itemDisplayItem.slot,
            }
            local effects, _w, _h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
            opts.effects = effects
            opts.tooltipColWidth = nil  -- use default in window
            local ok = pcall(function()
                ItemTooltip.renderItemDisplayContent(showItem, ctx, opts)
            end)
            if not ok then
                ImGui.TextColored(ImVec4(0.9, 0.3, 0.3, 1.0), "Error drawing item stats.")
            end
        end
        ImGui.EndChild()
    end

    ImGui.End()
end

return ItemDisplayView
