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
require('ImGui')

local M = {}

local K = constants.UI.KIT

-- FontAwesome glyphs, merged into MQ's default font at atlas build: U+F023 / U+F09C.
local GLYPH_LOCKED   = "\xEF\x80\xA3"
local GLYPH_UNLOCKED = "\xEF\x82\x9C"

local ICON_W = 20          -- icon button square, centred in the 26px band
local ICON_GAP = K.GAP_INNER

--- Tuple-safe content-region width (the binding returns two floats; older paths a table).
local function availWidth()
    local ax = ImGui.GetContentRegionAvail()
    if type(ax) == 'number' then return ax end
    if type(ax) == 'table' and ax.x then return ax.x end
    return 0
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
