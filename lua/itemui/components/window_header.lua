--[[
    The 26px window header band (kit §3.6). One contract, fixed order:

        name  →  the one number the bar does NOT already show  →  icon actions  →  lock

    The bars own bag count, XP, buffs, session, loot and sell progress. A window that
    restates any of those loses the space instead — spec.stat is the single string that
    answers this window's own question (Bags: "7,399p 0g total · last scan 19:52:51",
    Equipment: "3 upgrades in bags", Effects: "Buffs 16/30 · Songs 1 · Auras 1").

    render(spec) with:
      id       string   stable ImGui id scope; falls back to title
      title    string   drawn at the heading register (22px, white)
      stat     string?  drawn beside it in TextContent
      actions  table?   { { label=glyph_or_text, tooltip=str?, onClick=fn?, disabled=bool? }, … }
                        drawn right-aligned as 20px inset icon buttons, in order
      lock     table?   { locked=bool, onToggle=fn? } — rightmost slot, always last
    Never throws: action handlers run under pcall, and the band never scrolls (§3.7 —
    a header is not a scroll region).

    Sizing note: HEADER_H (26) minus FONT_HEADING (22) leaves 2px above and below the
    title; icon buttons are 20px squares centred by the same padding. If content doesn't
    fit, the caller's stat string is too long — the band never grows.
]]

local constants = require('itemui.constants')
local theme = require('itemui.utils.theme')
local fonts = require('itemui.utils.fonts')
-- core/registry requires only mq, so this closes no cycle and registers no window (a view
-- module's require-time registration order IS launcher-button order; a component's is not).
local registry = require('itemui.core.registry')
require('ImGui')

local M = {}

local K = constants.UI.KIT

-- FontAwesome glyphs, merged into MQ's default font at atlas build: U+F023 / U+F09C.
-- They MUST stay \xNN escapes: MQ's ImGui does not render Lua source as UTF-8, and an
-- editor round-trip through Latin-1 double-encodes a literal glyph permanently (it has
-- already destroyed two of these). scripts/tests/test_ascii_strings.lua enforces it.
local GLYPH_LOCKED   = "\xEF\x80\xA3"
local GLYPH_UNLOCKED = "\xEF\x82\x9C"

--- Shared glyph table, so the windows adopting this band in one pass do not each grow
--- their own copy of the same three escapes (item_display and augment_utility predate it
--- and keep theirs).
M.GLYPHS = {
    REFRESH = "\xEF\x80\xA1",  -- U+F021 refresh
    SEARCH  = "\xEF\x80\x82",  -- U+F002 magnifier
    FILTER  = "\xEF\x82\xB0",  -- U+F0B0 filter
    CLOCK   = "\xEF\x80\x97",  -- U+F017 clock
    FOLDER  = "\xEF\x81\xBB",  -- U+F07B folder
    -- Promoted from augment_utility's local (item 10). Already ships and already renders
    -- in that band, so this carries no new atlas risk: if it ever failed to rasterise it
    -- would draw a box, the band would still read "[] Black Scythe", and the pin's
    -- tooltip carries the words regardless.
    LINK    = "\xEF\x83\x81",  -- U+F0C1 link
    LOCKED  = GLYPH_LOCKED,
    UNLOCK  = GLYPH_UNLOCKED,
}

local ICON_W = 20          -- icon button square, centred in the 26px band
local ICON_GAP = K.GAP_INNER

--- Tuple-safe content-region width (the binding returns two floats; older paths a table).
local function availWidth()
    local ax = ImGui.GetContentRegionAvail()
    if type(ax) == 'number' then return ax end
    if type(ax) == 'table' and ax.x then return ax.x end
    return 0
end

--- Item rect as four numbers. The binding returns TWO FLOATS from GetItemRectMin/Max, not
--- an ImVec2 (lua_ImGuiCore.cpp:879) — indexing the return as `.x` throws.
local function itemRect()
    local x1, y1 = ImGui.GetItemRectMin()
    local x2, y2 = ImGui.GetItemRectMax()
    if type(x1) ~= 'number' or type(x2) ~= 'number' then return nil end
    return x1, y1, x2, y2
end

--- The kit's chip: one control shape for "this thing is open / active".
---
--- `lit` gets the product's open pair — the OpenWash fill plus a 2px OpenBlue accent on
--- `accentEdge` ("top" or "bottom"; nil draws the wash alone). Everything the user reads as
--- open uses this: bar launchers, the bottom bar's identity group, chat's tab strip. It
--- lives here because a second copy would be a second dialect.
---
--- The Push/Pop is a pcall SANDWICH, not a bare pair: a throw between them would skip the
--- pop and leak a colour every frame until ImGui asserts.
function M.chip(label, uid, lit, accentEdge, tint)
    local pushed = 0
    if lit then
        ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Kit.OpenWash))
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Kit.TextOnOpen))
        pushed = 2
    elseif tint then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(tint))
        pushed = 1
    end
    local ok, clicked = pcall(ImGui.SmallButton, label .. "##" .. uid)
    if pushed > 0 then ImGui.PopStyleColor(pushed) end
    if not ok then error(clicked, 0) end
    if lit and accentEdge then
        -- AddRectFilled, not AddRect: an outline is unproven in this binding, and a filled
        -- 2px strip is the treatment the mockups draw and dock_top already ships.
        pcall(function()
            local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
            if not dl or not dl.AddRectFilled then return end
            local x1, y1, x2, y2 = itemRect()
            if not x1 then return end
            local col = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(theme.Kit.OpenBlue))
                or 0xFFFA9642
            if accentEdge == "bottom" then
                dl:AddRectFilled(ImVec2(x1, y2 - 2), ImVec2(x2, y2), col)
            else
                dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y1 + 2), col)
            end
        end)
    end
    return clicked == true
end

--- The cursor-target ring (item 10): *this will take what is on your cursor.* One meaning,
--- everywhere, forever — not selection, not focus, not validity in the abstract.
---
--- Drawn over the LAST item, so call it straight after the widget it rings. Four
--- AddRectFilled edges rather than AddRect, for the reason chip records above: an outline
--- is unproven in this binding and filled strips are what ships.
---
--- Slots, sockets and cells only. NEVER a table row — rows are a list of what you have,
--- slots are destinations, and ringing a row promises a drop target that does not exist.
function M.cursorRing()
    pcall(function()
        local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
        if not dl or not dl.AddRectFilled then return end
        local x1, y1, x2, y2 = itemRect()
        if not x1 then return end
        local col = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(theme.Kit.OpenBlue))
            or 0xFFFA9642
        dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y1 + 2), col)          -- top
        dl:AddRectFilled(ImVec2(x1, y2 - 2), ImVec2(x2, y2), col)          -- bottom
        dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x1 + 2, y2), col)          -- left
        dl:AddRectFilled(ImVec2(x2 - 2, y1), ImVec2(x2, y2), col)          -- right
    end)
end

--- A count that belongs to the chip beside it (19b: "counts sit in their own pill"). A
--- number welded into a label reads as part of the NAME; a pill reads as a quantity. It
--- stays clickable and does the chip's own action, so it is never a dead zone inside a
--- live control.
function M.pill(count, uid)
    ImGui.SameLine(0, 1)
    ImGui.PushStyleColor(ImGuiCol.Button, theme.ToVec4(theme.Kit.Divider))
    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.TextContent))
    local ok, clicked = pcall(ImGui.SmallButton, tostring(count) .. "##" .. uid)
    ImGui.PopStyleColor(2)
    if not ok then error(clicked, 0) end
    return clicked == true
end

--- The lock slot every registry window's band carries, built once here rather than
--- six times at six call sites. The glyph is the CLOSE-SURVIVAL pin (registry.isPinned) —
--- resize-prevention is the separate global `uiState.uiLocked` toggle, and the two never
--- share a word (decision recorded 2026-07-31 in docs/WINDOWS_PASS.md).
function M.registryLock(id, ctx)
    return {
        locked = registry.isPinned(id),
        onToggle = function()
            registry.setPinned(id, not registry.isPinned(id))
            if ctx and ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
        end,
    }
end

--- 20px inset icon button (exported: toolbars that are not header bands — Item Display's
--- tab strip — draw the same control so the kit stays one kit).
function M.iconButton(id, label, tooltip, disabled, accent)
    if disabled then
        theme.PushKitDisabledButton()
    else
        theme.PushIconButton()
    end
    if accent then
        ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Kit.OpenBlue))
    end
    local clicked = ImGui.Button(label .. id, ImVec2(ICON_W, ICON_W))
    if accent then
        ImGui.PopStyleColor(1)
    end
    theme.PopKitButton()
    if tooltip and ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text(tooltip)
        ImGui.EndTooltip()
    end
    return clicked and not disabled
end

--- Band content, split out so M.render can pcall it INSIDE the child: a throw here
--- must never skip EndChild — one skipped close pauses the plugin overlay in-game.
local function renderBandContent(spec, idScope, actions, rightSlots)
    fonts.pushHeading()
    pcall(ImGui.Text, tostring(spec.title or ''))  -- a throw must not leak the font push
    fonts.pop()

    if spec.stat and spec.stat ~= '' then
        ImGui.SameLine(0, K.PAD)
        theme.TextContent(spec.stat)
    end

    if rightSlots > 0 then
        local needed = rightSlots * ICON_W + (rightSlots - 1) * ICON_GAP
        ImGui.SameLine(0, 0)
        local slack = availWidth() - needed
        if slack > 0 then
            ImGui.SameLine(0, slack)
        else
            ImGui.SameLine(0, ICON_GAP)
        end
        for i, a in ipairs(actions) do
            if i > 1 then ImGui.SameLine(0, ICON_GAP) end
            if M.iconButton('##hdract_' .. idScope .. '_' .. i, tostring(a.label or '?'),
                    a.tooltip, a.disabled, false) and a.onClick then
                pcall(a.onClick)
            end
        end
        if spec.lock then
            if #actions > 0 then ImGui.SameLine(0, ICON_GAP) end
            local glyph = spec.lock.locked and GLYPH_LOCKED or GLYPH_UNLOCKED
            local tip = spec.lock.locked and 'Unlock window position' or 'Lock window position'
            if M.iconButton('##hdrlock_' .. idScope, glyph, tip, false, spec.lock.locked)
                    and spec.lock.onToggle then
                pcall(spec.lock.onToggle)
            end
        end
    end
end

function M.render(spec)
    if not spec then return end
    local idScope = tostring(spec.id or spec.title or 'window')
    local actions = spec.actions or {}
    local rightSlots = #actions + (spec.lock and 1 or 0)

    ImGui.PushStyleColor(ImGuiCol.ChildBg, theme.ToVec4(theme.Kit.Header))
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, ImVec2(K.PAD, (K.HEADER_H - K.FONT_HEADING) / 2))
    local flags = bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)
    if ImGui.BeginChild('##winheader_' .. idScope, ImVec2(0, K.HEADER_H), false, flags) then
        pcall(renderBandContent, spec, idScope, actions, rightSlots)
    end
    ImGui.EndChild()
    ImGui.PopStyleVar(1)
    ImGui.PopStyleColor(1)
end

return M
