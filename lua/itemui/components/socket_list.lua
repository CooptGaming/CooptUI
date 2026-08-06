--[[
    socket_list.lua — THE socket presentation, one component (field ruling 08-05:
    "the icons should be in a column with the name of the item next to it... the Aug
    Utility should have a similar setup" — and "we've had some regression here", so
    both hosts now render sockets through this single definition; a second copy would
    be a second dialect and the next regression).

    One row per socket, stacked as a COLUMN:
        [icon cell: Inset wash + identity-tinted 1px hairline]  Name of the aug
    Identity tint: spell-blue standard aug, mythic ornament, muted Divider on empty.
    An optional SELECTION edge (open-blue) marks the active row — the Aug Utility's
    picker state; Item Display passes none.

    The component owns: layout, the hover card (full socketed-item stats via the
    host's resolver, name-only fallback), and the row click (reported through
    opts.onRowClick — fired from the cell or the name, hover captured ONCE before
    any tooltip submits items; the dock_top captured-hover trap is why).
    Hosts own: context menus and any extra verbs, attached to the CELL item via
    opts.afterCell(row, isEmpty) — called straight after the cell so popup context
    binds to it — and the cursor ring via opts.ringWhen(row, isEmpty).

    Row shape (the tooltip cache's augLines/ornamentLine rows pass through as-is;
    hosts add isOrnament on a COPY, never on the cached row):
        { slotIndex, iconId, augName, socketType, prefix, isOrnament }
]]

require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')

local M = {}

local CELL_ICON = 24
local CELL_W = CELL_ICON + 6

--- The row body, pcall'd under renderRow's PushID/PopID pair so a throw anywhere in
--- here (icon, name, tooltip, a host hook) can never leak the id stack - the render
--- suite injects exactly that and asserts balance.
local function renderRowBody(ctx, row, opts)
    local isEmpty = (row.augName == nil or row.augName == "empty" or row.augName == "")
    local isOrn = row.isOrnament == true
    local selected = opts.selectedSlot ~= nil and opts.selectedSlot == row.slotIndex

    ImGui.PushStyleColor(ImGuiCol.ChildBg, ctx.theme.ToVec4(ctx.theme.Kit.Inset))
    local okCell = pcall(function()
        -- border = FALSE: the bool-border overload pays WindowPadding and clips a
        -- 30px cell's icon. Containment is the wash + the hairline below. The child
        -- NAME is globally unique (not just PushID-scoped): the render suite's hover
        -- model matches children by name, and every cell sharing "cell" would make
        -- the sockets untestable.
        if ImGui.BeginChild((opts.idPrefix or "sock") .. "cell_" .. tostring(row.slotIndex)
                    .. (isOrn and "_orn" or ""), ImVec2(CELL_W, CELL_W), false,
                bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
            ImGui.SetCursorPosX(3)
            ImGui.SetCursorPosY(3)
            if not isEmpty and (row.iconId or 0) > 0 and ctx.drawItemIcon then
                local okIcon = pcall(ctx.drawItemIcon, row.iconId, CELL_ICON)
                if not okIcon then ImGui.Dummy(ImVec2(CELL_ICON, CELL_ICON)) end
            else
                ImGui.Dummy(ImVec2(CELL_ICON, CELL_ICON))
            end
        end
        ImGui.EndChild()
    end)
    ImGui.PopStyleColor(1)
    if not okCell then return end

    -- Hairline over the cell rect: SELECTION beats identity (open-blue active row);
    -- identity tint otherwise. Four AddRectFilled strips (outline unproven).
    pcall(function()
        local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
        if not dl or not dl.AddRectFilled then return end
        local x1, y1 = ImGui.GetItemRectMin()
        local x2, y2 = ImGui.GetItemRectMax()
        if type(x1) ~= "number" or type(x2) ~= "number" then return end
        local c
        if selected then
            c = ctx.theme.Kit.OpenBlue
        elseif isEmpty then
            c = ctx.theme.Kit.Divider
        elseif isOrn then
            c = ctx.theme.Kit.Mythic
        else
            c = ctx.theme.Kit.SpellBlue
        end
        local col = ImGui.GetColorU32 and ImGui.GetColorU32(ctx.theme.ToVec4(c)) or 0xFF302B2B
        dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y1 + 1), col)
        dl:AddRectFilled(ImVec2(x1, y2 - 1), ImVec2(x2, y2), col)
        dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x1 + 1, y2), col)
        dl:AddRectFilled(ImVec2(x2 - 1, y1), ImVec2(x2, y2), col)
    end)
    -- Hover captured ONCE, before rings/menus/tooltips submit their own items.
    local cellHovered = ImGui.IsItemHovered()
    if opts.ringWhen and opts.ringWhen(row, isEmpty) then
        -- Drawn straight after the cell so it rings that rect (window_header rule).
        local windowHeader = require('itemui.components.window_header')
        windowHeader.cursorRing()
    end
    if opts.afterCell then opts.afterCell(row, isEmpty) end

    -- The name, vertically centered against the cell.
    ImGui.SameLine(0, 8)
    do
        local lineH = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14
        local dy = math.max(0, (CELL_W - lineH) * 0.5)
        ImGui.SetCursorPosY(ImGui.GetCursorPosY() + dy)
    end
    local label, color
    if isEmpty then
        if row.prefix and row.prefix ~= "" then
            label = row.prefix .. "empty"
        elseif isOrn then
            label = "Ornament (type 20): empty"
        else
            local typ = tonumber(row.socketType) or 0
            label = string.format("Slot %d: empty%s", row.slotIndex,
                (typ > 0) and (" . type " .. typ) or "")
        end
        color = ctx.theme.Colors.TextFurniture
    else
        label = tostring(row.augName) .. (isOrn and " . ornament" or "")
        color = isOrn and ctx.theme.Kit.Mythic or ctx.theme.Kit.SpellBlue
    end
    ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(color))
    pcall(ImGui.Text, label)
    ImGui.PopStyleColor(1)
    local nameHovered = ImGui.IsItemHovered()

    -- The hover card: full socketed-item stats when the host can resolve them,
    -- name (or the host's empty hint) otherwise.
    if cellHovered or nameHovered then
        local full = (not isEmpty and opts.resolveFull) and opts.resolveFull(row) or nil
        if full then
            local topts = (opts.tooltipOpts and opts.tooltipOpts(row)) or {}
            local effects, tw, th = ItemTooltip.prepareTooltipContent(full, ctx, topts)
            topts.effects = effects
            ItemTooltip.beginItemTooltip(tw or constants.UI.TOOLTIP_MIN_WIDTH,
                th or constants.UI.TOOLTIP_MIN_HEIGHT)
            ImGui.Text("Stats")
            ImGui.Separator()
            ItemTooltip.renderStatsTooltip(full, ctx, topts)
            ImGui.EndTooltip()
        else
            ImGui.BeginTooltip()
            ImGui.Text(label)
            if opts.hoverHint then ImGui.Text(tostring(opts.hoverHint)) end
            ImGui.EndTooltip()
        end
    end
    if (cellHovered or nameHovered) and ImGui.IsMouseClicked and ImGui.IsMouseClicked(ImGuiMouseButton.Left) then
        if opts.onRowClick then opts.onRowClick(row, isEmpty) end
    end
end

--- One socket row. opts per the header; ctx supplies theme + drawItemIcon.
function M.renderRow(ctx, row, opts)
    opts = opts or {}
    local isOrn = row.isOrnament == true
    ImGui.PushID((opts.idPrefix or "sock") .. "_" .. tostring(row.slotIndex) .. (isOrn and "_orn" or ""))
    pcall(renderRowBody, ctx, row, opts)
    ImGui.PopID()
end

--- The column of rows. rows render in order; ornament rows carry isOrnament=true.
function M.render(ctx, rows, opts)
    for _, row in ipairs(rows or {}) do
        M.renderRow(ctx, row, opts)
    end
end

M.CELL_W = CELL_W
M.CELL_ICON = CELL_ICON

return M
