--[[
    Item Display View - CoOpt UI Item Display window

    Tabbed window: each "CoOp UI Item Display" open adds a tab. Toolbar: Can I use?, Source,
    Locate, Refresh, Recent.
--]]

local mq = require('mq')
require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')

local ItemDisplayView = {}

--- Draw "Can I use?" banner + full item tooltip content for one tab entry.
--- entry = { bag, slot, source, item, label }
local function renderOneItemContent(ctx, entry)
    if not entry or not entry.item then return end
    local showItem = entry.item
    local source = entry.source or "inv"
    local canUseInfo = ItemTooltip.getCanUseInfo(showItem, source)
    if canUseInfo.canUse then
        ImGui.TextColored(ImVec4(0.35, 0.85, 0.35, 1.0), "You can use this item.")
    else
        ImGui.TextColored(ImVec4(0.95, 0.35, 0.35, 1.0), "You cannot use: " .. (canUseInfo.reason or "restriction"))
    end
    ImGui.Spacing()
    local opts = {
        source = source,
        bag = entry.bag,
        slot = entry.slot,
        isItemDisplayWindow = true,
        entry = entry,
    }
    local effects, _w, _h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
    opts.effects = effects
    opts.tooltipColWidth = nil
    local ok = pcall(function()
        ItemTooltip.renderItemDisplayContent(showItem, ctx, opts)
    end)
    if not ok then
        ImGui.TextColored(ImVec4(0.9, 0.3, 0.3, 1.0), "Error drawing item stats.")
    end
end

local function sourceLabel(source)
    if source == "bank" then return "Bank" end
    if source == "inv" then return "Inventory" end
    return tostring(source)
end

-- Module interface: render main Item Display window (tabbed)
function ItemDisplayView.render(ctx)
    if not ctx.uiState.itemDisplayWindowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig
    local tabs = ctx.uiState.itemDisplayTabs
    local activeIdx = ctx.uiState.itemDisplayActiveTabIndex
    if activeIdx < 1 or activeIdx > #tabs then
        ctx.uiState.itemDisplayActiveTabIndex = #tabs > 0 and 1 or 0
        activeIdx = ctx.uiState.itemDisplayActiveTabIndex
    end

    local px = layoutConfig.ItemDisplayWindowX or 0
    local py = layoutConfig.ItemDisplayWindowY or 0
    if px and py and (px ~= 0 or py ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(px, py), ImGuiCond.FirstUseEver)
    end

    local w = layoutConfig.WidthItemDisplayPanel or constants.VIEWS.WidthItemDisplayPanel
    local h = layoutConfig.HeightItemDisplay or constants.VIEWS.HeightItemDisplay
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

    if not winOpen then
        ctx.uiState.itemDisplayTabs = {}
        ctx.uiState.itemDisplayActiveTabIndex = 1
        ImGui.End()
        return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end

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

    -- Custom tab row: button (click to select tab) + X button (click to close); wrap to next line when width exceeded
    if #tabs > 0 then
        local closeSet = {}
        local closeIndices = {}
        local style = ImGui.GetStyle()
        local framePadX = (style and style.FramePadding and style.FramePadding.x) or 4
        local availX = constants.UI.ITEM_DISPLAY_AVAIL_X
        do
            local ax, ay = ImGui.GetContentRegionAvail()
            if type(ax) == "number" and ax > 0 then availX = ax end
            if type(ax) == "table" and ax.x then availX = ax.x end
        end
        local X_BUTTON_W = 20
        local lineWidth = 0
        for i, tab in ipairs(tabs) do
            local tabLabel = tab.label or ("Item " .. tostring(i))
            local isSelected = (activeIdx == i)
            local tw = constants.UI.ITEM_DISPLAY_TAB_LABEL_WIDTH
            do
                local cw, ch = ImGui.CalcTextSize(tabLabel)
                if type(cw) == "number" then tw = cw
                elseif type(cw) == "table" and cw.x then tw = cw.x
                end
            end
            local btnW = tw + framePadX * 2
            if btnW < 80 then btnW = 80 end
            local tabTotalW = btnW + 2 + X_BUTTON_W + (i < #tabs and 6 or 0)
            if i > 1 and (lineWidth + tabTotalW > availX) then
                ImGui.NewLine()
                lineWidth = 0
            elseif i > 1 then
                ImGui.SameLine(0, 6)
            end
            if isSelected then
                ImGui.PushStyleColor(ImGuiCol.Button, ImGui.GetStyleColorVec4(ImGuiCol.HeaderActive))
                ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImGui.GetStyleColorVec4(ImGuiCol.Header))
                ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImGui.GetStyleColorVec4(ImGuiCol.Header))
            end
            if ImGui.Button(tabLabel .. "##ItemDisplayTab" .. tostring(i), ImVec2(btnW, 0)) then
                ctx.uiState.itemDisplayActiveTabIndex = i
            end
            if isSelected then
                ImGui.PopStyleColor(3)
            end
            if ImGui.IsItemHovered() and ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
                if not closeSet[i] then closeSet[i] = true; closeIndices[#closeIndices + 1] = i end
            end
            ImGui.SameLine(0, 2)
            ImGui.PushStyleColor(ImGuiCol.Button, ImVec4(0.5, 0.2, 0.2, 0.6))
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ImVec4(0.7, 0.25, 0.25, 0.9))
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, ImVec4(0.8, 0.3, 0.3, 1.0))
            if ImGui.SmallButton("X##CloseTab" .. tostring(i)) then
                if not closeSet[i] then closeSet[i] = true; closeIndices[#closeIndices + 1] = i end
            end
            ImGui.PopStyleColor(3)
            lineWidth = lineWidth + btnW + 2 + X_BUTTON_W + (i < #tabs and 6 or 0)
        end
        ImGui.NewLine()
        -- Remove closed tabs (from high index down so indices stay valid)
        local t = ctx.uiState.itemDisplayTabs
        local curActive = ctx.uiState.itemDisplayActiveTabIndex
        table.sort(closeIndices, function(a, b) return a > b end)
        for _, idx in ipairs(closeIndices) do
            if idx >= 1 and idx <= #t then
                table.remove(t, idx)
                if curActive > idx then
                    curActive = curActive - 1
                elseif curActive == idx then
                    curActive = math.max(1, math.min(idx, #t))
                end
            end
        end
        ctx.uiState.itemDisplayActiveTabIndex = curActive
        if #ctx.uiState.itemDisplayTabs > 0 and (ctx.uiState.itemDisplayActiveTabIndex < 1 or ctx.uiState.itemDisplayActiveTabIndex > #ctx.uiState.itemDisplayTabs) then
            ctx.uiState.itemDisplayActiveTabIndex = 1
        end
        if #ctx.uiState.itemDisplayTabs == 0 then
            ctx.uiState.itemDisplayWindowOpen = false
            ctx.uiState.itemDisplayWindowShouldDraw = false
        end
        -- Use current selection for content (updated by tab click or close)
        activeIdx = ctx.uiState.itemDisplayActiveTabIndex
        if activeIdx < 1 or activeIdx > #ctx.uiState.itemDisplayTabs then
            activeIdx = math.max(1, #ctx.uiState.itemDisplayTabs)
        end
    end

    -- Toolbar and content
    if #tabs == 0 then
        if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
            ImGui.TextColored(ImVec4(0.7, 0.7, 0.7, 1.0), "No item selected. Right-click an item and choose \"CoOp UI Item Display\" to open.")
            ImGui.EndChild()
        end
    else
        local tab = tabs[activeIdx]
        if tab then
            -- Toolbar: row 1 = Locate, Refresh, Recent; row 2 = Source
            ImGui.Spacing()
            if ImGui.SmallButton("Locate##ItemDisplay") then
                ctx.uiState.itemDisplayLocateRequest = { source = tab.source, bag = tab.bag, slot = tab.slot }
                ctx.uiState.itemDisplayLocateRequestAt = mq.gettime()
            end
            ImGui.SameLine()
            if ImGui.SmallButton("Refresh##ItemDisplay") then
                if ctx.getItemStatsForTooltip then
                    local fresh = ctx.getItemStatsForTooltip({ bag = tab.bag, slot = tab.slot }, tab.source)
                    if fresh and fresh.id and fresh.id ~= 0 then
                        tab.item = fresh
                    end
                end
            end
            ImGui.SameLine()
            local recent = ctx.uiState.itemDisplayRecent
            if #recent > 0 then
                local currentLabel = tab.label or ""
                local comboW = 280
                do
                    local cw, ch = ImGui.CalcTextSize(("W"):rep(35))
                    if type(cw) == "number" then comboW = cw end
                    if type(cw) == "table" and cw and cw.x then comboW = cw.x end
                    comboW = comboW + 24
                end
                ImGui.SetNextItemWidth(comboW)
                if ImGui.BeginCombo("Recent##ItemDisplay", currentLabel, ImGuiComboFlags.None) then
                    for _, r in ipairs(recent) do
                        local sel = (r.bag == tab.bag and r.slot == tab.slot and r.source == tab.source)
                        if ImGui.Selectable((r.label or "?") .. "##Recent" .. tostring(r.bag) .. "_" .. tostring(r.slot), sel) then
                            -- Find or add tab for this recent entry
                            local found
                            for i, t in ipairs(tabs) do
                                if t.bag == r.bag and t.slot == r.slot and t.source == r.source then
                                    ctx.uiState.itemDisplayActiveTabIndex = i
                                    found = true
                                    break
                                end
                            end
                            if not found and ctx.getItemStatsForTooltip then
                                local showItem = ctx.getItemStatsForTooltip({ bag = r.bag, slot = r.slot }, r.source)
                                if showItem and showItem.id and showItem.id ~= 0 then
                                    local label = (showItem.name and showItem.name ~= "" and showItem.name:sub(1, 35)) or "Item"
                                    if #label == 35 and (showItem.name or ""):len() > 35 then label = label .. "…" end
                                    tabs[#tabs + 1] = { bag = r.bag, slot = r.slot, source = r.source, item = showItem, label = label }
                                    ctx.uiState.itemDisplayActiveTabIndex = #tabs
                                end
                            end
                        end
                    end
                    ImGui.EndCombo()
                end
            end
            ImGui.TextColored(ImVec4(0.6, 0.6, 0.65, 1.0), "Source: " .. sourceLabel(tab.source) .. " | Bag " .. tostring(tab.bag) .. ", Slot " .. tostring(tab.slot))
            ImGui.Spacing()
            if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
                renderOneItemContent(ctx, tab)
                ImGui.EndChild()
            end
        end
    end

    ImGui.End()
end

return ItemDisplayView
