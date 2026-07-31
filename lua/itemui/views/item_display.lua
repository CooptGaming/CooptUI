--[[
    Item Display View - CoOpt UI Item Display window (windows pass v2, mockups 17b/18a/19a).

    Tabbed window: each "Open it" adds a tab. Tab strip carries the icon actions (recents,
    locate, refresh) and the lock. Below: identity card (the name appears HERE, once),
    verdict box, the type-aware stat strip (aug-inclusive totals — §0.1: one number
    everywhere), then the remembered sections: EFFECTS · ALL STATS · SPELL DATA & IDS ·
    AUGMENTS · RULES (open/closed persists per character via services/section_state).
--]]

local mq = require('mq')
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local ItemTooltip = require('itemui.utils.item_tooltip')
local ItemCompare = require('itemui.utils.item_compare')
local TooltipData = require('itemui.utils.tooltip_data')
local TooltipRender = require('itemui.utils.tooltip_render')
local constants = require('itemui.constants')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local uiState = require('itemui.state').uiState
local fonts = require('itemui.utils.fonts')
local dockLayout = require('itemui.utils.dock_layout')
local windowHeader = require('itemui.components.window_header')
local contextMenu = require('itemui.components.context_menu')
local sectionState = require('itemui.services.section_state')

local ItemDisplayView = {}

-- FontAwesome glyphs (merged into MQ's default font at atlas build).
local GLYPH_RECENT   = "\xEF\x87\x9A"  -- U+F1DA history
local GLYPH_LOCATE   = "\xEF\x81\x9B"  -- U+F05B crosshairs
local GLYPH_REFRESH  = "\xEF\x80\xA1"  -- U+F021 refresh
local GLYPH_LOCKED   = "\xEF\x80\xA3"  -- U+F023 lock
local GLYPH_UNLOCKED = "\xEF\x82\x9C"  -- U+F09C unlock

-- Per 4.2 state ownership: tabs, active index, recent, locate request, augment slot active
local state = {
    itemDisplayTabs = {},
    itemDisplayActiveTabIndex = 1,
    itemDisplayRecent = {},
    itemDisplayLocateRequest = nil,
    itemDisplayLocateRequestAt = nil,
    itemDisplayAugmentSlotActive = nil,
}
function ItemDisplayView.getState()
    return state
end

-- ============================================================================
-- Verdict card (design pass 3e): header, equipped-item comparison, tile grid, rules.
-- ============================================================================

--- Resolve the item's first (lowest-index) worn slot (0-22), and attach Augs filled/total onto
--- the item row for item_compare's pure "augs" tile (item_compare itself never touches a TLO —
--- see item_compare.lua's header comment). Returns nil when the item can't be worn, or is worn
--- "anywhere" (WornSlots >= 20 — too rare/ambiguous a case for one specific equipped-slot
--- comparison, so it's treated the same as "not wearable" here).
--- Multi-slot items (Ear, Wrist, Ring): comparing against the LOWEST slot index is a simple,
--- deterministic choice rather than "best of both" — keeps the verdict box to one comparison.
local function resolveCompareSlot(ctx, entry)
    local item = entry.item
    if not ctx.getItemTLO then return nil end
    local it = ctx.getItemTLO(entry.bag, entry.slot, entry.source or "inv")
    if not it then return nil end

    if ctx.getStandardAugSlotsCountFromTLO then
        local total = ctx.getStandardAugSlotsCountFromTLO(it) or 0
        item.augsTotal = total
        if total > 0 and ctx.getFilledStandardAugmentSlotIndices then
            local filled = ctx.getFilledStandardAugmentSlotIndices(entry.bag, entry.slot, entry.source or "inv")
            item.augsFilled = (filled and #filled) or 0
        else
            item.augsFilled = 0
        end
    end

    if not ctx.getWornSlotIndicesFromTLO then return nil end
    local indices = ctx.getWornSlotIndicesFromTLO(it)
    if type(indices) ~= "table" then return nil end
    local first = nil
    for idx in pairs(indices) do
        if first == nil or idx < first then first = idx end
    end
    return first
end

-- ============================================================================
-- Verdict memo (design pass 3e follow-up): renderOneItemContent runs every frame for the active
-- tab. resolveCompareSlot alone is ~15-25 TLO probes (worn-slot + aug-slot walks), and
-- ctx.getSellStatusForItem shallow-copies the whole ~85+-field item table on top of that.
-- Neither needs to run more than once per TTL window per tab identity. Mirrors the
-- tooltipStatsMemo precedent (app.lua's getItemStatsForTooltipRef) — same TTL, same "one fresh
-- read, then reuse" shape.
-- ============================================================================
local verdictMemo = {}
local VERDICT_TTL_MS = 1500

local function verdictMemoKey(entry)
    local item = entry.item
    return (entry.source or "inv") .. ":" .. tostring(entry.bag) .. ":" .. tostring(entry.slot) .. ":" .. tostring(item and item.id)
end

--- Returns { wornSlotIndex, augsTotal, augsFilled, reason, willSell, inKeep, inJunk }, refreshed
--- at most once per VERDICT_TTL_MS per (source,bag,slot,item.id). On a cache hit, re-attaches
--- augsTotal/augsFilled onto entry.item — Refresh swaps in a brand new item table, so those
--- plain fields need re-stamping every frame even though the TLO walk that produced them didn't
--- re-run. The reroll list-membership check in renderRulesBlock is deliberately NOT part of this
--- memo: rerollService.getListStatus is already an O(1) cached-set lookup, so it's called live.
local function getVerdictMemo(ctx, entry)
    local key = verdictMemoKey(entry)
    local now = mq.gettime()
    local memo = verdictMemo[key]
    if memo and (now - memo.at) < VERDICT_TTL_MS then
        if entry.item then
            entry.item.augsTotal = memo.augsTotal
            entry.item.augsFilled = memo.augsFilled
        end
        return memo
    end
    local wornSlotIndex = resolveCompareSlot(ctx, entry)
    local reason, willSell, inKeep, inJunk
    if ctx.getSellStatusForItem then
        reason, willSell, inKeep, inJunk = ctx.getSellStatusForItem(entry.item)
    end
    memo = {
        at = now,
        wornSlotIndex = wornSlotIndex,
        augsTotal = entry.item and entry.item.augsTotal,
        augsFilled = entry.item and entry.item.augsFilled,
        reason = reason, willSell = willSell, inKeep = inKeep, inJunk = inJunk,
    }
    verdictMemo[key] = memo
    return memo
end

--- Resolve "what's currently equipped in slotIndex" for the verdict box. Primary and normal
--- path: a live, TTL-memoized TLO probe (ctx.getItemStatsForTooltip with source="equipped") —
--- this does NOT depend on the Equipment Companion window ever having been opened, since the
--- underlying TLOs (Me.Inventory / InvSlot) are live MQ state, not a CoOpt cache. When the probe
--- reports "no item" AND the TLO infra (Me.Inventory) is reachable, that is trusted as a
--- genuinely empty slot — no cache fallback, so an item removed via native inventory can never
--- linger in the verdict box. Fallback: ctx.equipmentCache, which IS only populated while the
--- Equipment window is open (see app.lua's refreshEquipmentCache, gated in main_window.lua) — is
--- consulted ONLY when the TLO infra itself is unreachable (e.g. a mid-zone frame), which is the
--- one case the live probe cannot resolve to "empty" on its own.
--- Returns the equipped item table, or nil when the slot is genuinely empty (or, rarely, no data
--- is available from either path during that mid-zone window).
local function resolveEquippedForSlot(ctx, slotIndex)
    if slotIndex == nil then return nil end
    if ctx.getItemStatsForTooltip then
        local ok, fresh = pcall(ctx.getItemStatsForTooltip, { bag = 0, slot = slotIndex, source = "equipped" }, "equipped")
        if ok and fresh and fresh.id and fresh.id ~= 0 then return fresh end
        -- Live probe found no item. If Me.Inventory is reachable, the slot is genuinely
        -- empty -- do NOT fall back to the (possibly stale) cache. Only fall through to the
        -- cache when the TLO infra itself is unavailable (e.g. a mid-zone frame).
        local infraOk, infraUp = pcall(function() return (mq.TLO and mq.TLO.Me and mq.TLO.Me.Inventory) ~= nil end)
        if ok and infraOk and infraUp then return nil end
    end
    local cached = ctx.equipmentCache and ctx.equipmentCache[slotIndex + 1]
    if cached and cached.id and cached.id ~= 0 then return cached end
    return nil
end

--- Format one tile's big value. Kit rule: zero is "—" where the row asks for it (heroic).
local function tileValueString(row)
    if row.zeroAsDash and tonumber(row.value) == 0 then return "\xe2\x80\x94" end
    if type(row.value) == "number" then
        return tostring(row.value) .. (row.suffix or "")
    end
    return tostring(row.value)
end

--- One stat tile, drawn WITHOUT a BeginChild (§3.7.1: a stat tile is never a scroll
--- region — the old 54px child clipped its own delta behind a scrollbar). The cell is a
--- reserved Dummy with an inset fill painted under it, then the three lines are laid at
--- fixed offsets: label (16, furniture) / value (22, heading register) / delta (16).
--- delta colouring honours betterWhenLower (delay: negative is the good direction);
--- isText rows (proc) print their note where the delta would be.
local TILE_W = 110
local TILE_H = 68
local TILE_PAD_X = 8

local function renderCompareTile(ctx, row, baseX, baseY)
    ImGui.SetCursorPos(baseX, baseY)
    ImGui.Dummy(ImVec2(TILE_W, TILE_H))
    pcall(function()
        local drawList = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
        if not drawList or not drawList.AddRectFilled then return end
        local x1, y1 = dockLayout.itemRectMin()
        local x2, y2 = dockLayout.itemRectMax()
        if not (x1 and x2) then return end
        local color = ImGui.GetColorU32 and ImGui.GetColorU32(ctx.theme.ToVec4(ctx.theme.Kit.Inset)) or 0xFF1B1B1B
        drawList:AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y2), color)
    end)

    ImGui.SetCursorPos(baseX + TILE_PAD_X, baseY + 4)
    ctx.theme.TextFurniture(string.upper(row.label or ""))

    ImGui.SetCursorPos(baseX + TILE_PAD_X, baseY + 20)
    local valStr = tileValueString(row)  -- computed before the push so a throw stays outside it
    fonts.pushHeading()
    pcall(ImGui.Text, valStr)
    fonts.pop()

    ImGui.SetCursorPos(baseX + TILE_PAD_X, baseY + 46)
    if row.isText then
        ctx.theme.TextFurniture(row.note or " ")
    elseif row.isRatio then
        ctx.theme.TextFurniture(" ")
    elseif row.delta == nil then
        ctx.theme.TextFurniture("\xe2\x80\x94")
    elseif row.delta == 0 then
        ctx.theme.TextFurniture("=")
    else
        local good = (row.delta > 0) ~= (row.betterWhenLower == true)
        local color = good and ctx.theme.Kit.Good or ctx.theme.Kit.Loss
        local fmt = row.isFloat and "%+.1f%s" or "%+d%s"
        ImGui.TextColored(ctx.theme.ToVec4(color), string.format(fmt, row.delta, row.suffix or ""))
    end
end

--- Tile grid: fixed-size cells laid by explicit cursor math (wraps on width), cursor left
--- at flow position under the last row so the rest of the window renders normally.
local function renderCompareTileGrid(ctx, rows)
    if not rows or #rows == 0 then return end
    local spacing = constants.UI.ITEM_DISPLAY_TILE_SPACING
    local availX = constants.UI.ITEM_DISPLAY_AVAIL_X
    do
        local ax, ay = ImGui.GetContentRegionAvail()
        if type(ax) == "number" and ax > 0 then availX = ax end
        if type(ax) == "table" and ax.x then availX = ax.x end
    end
    local perRow = math.max(1, math.floor((availX + spacing) / (TILE_W + spacing)))
    local cx, cy = ImGui.GetCursorPos()
    cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
    local gridRows = 0
    for i, row in ipairs(rows) do
        local col = (i - 1) % perRow
        local rowIdx = math.floor((i - 1) / perRow)
        gridRows = math.max(gridRows, rowIdx + 1)
        renderCompareTile(ctx, row,
            cx + col * (TILE_W + spacing),
            cy + rowIdx * (TILE_H + spacing))
    end
    ImGui.SetCursorPos(cx, cy + gridRows * (TILE_H + spacing))
end

-- Verdict -> theme color key + headline verb. "none" covers both "not wearable" (box isn't
-- shown at all — see renderVerdictBox) and "wearable but no comparison data".
local VERDICT_COLOR_KEY = { upgrade = "Success", downgrade = "Error", sidegrade = "Muted", none = "Muted" }

--- Bordered verdict box: "Upgrade over <equipped name>" / delta summary, or an honest
--- "nothing to compare" note when there's no worn slot or no equipped-item data. isSelfView
--- means the tab IS the item currently worn in that slot (identity match, not id match — see
--- renderOneItemContent) — that gets its own truthful text instead of the generic "nothing
--- equipped" message, which would otherwise lie (something IS equipped: this exact item).
local function renderVerdictBox(ctx, cmp, equippedItem, hasWornSlot, isSelfView)
    if not hasWornSlot then return end
    local color = ctx.theme.ToVec4(ctx.theme.Colors[VERDICT_COLOR_KEY[cmp.verdict] or "Muted"])
    ImGui.PushStyleColor(ImGuiCol.Border, color)
    ImGui.PushStyleVar(ImGuiStyleVar.ChildBorderSize, 2)
    if ImGui.BeginChild("##ItemDisplayVerdict", ImVec2(0, constants.UI.ITEM_DISPLAY_VERDICT_HEIGHT), true) then
        if cmp.verdict == "none" and isSelfView then
            ctx.theme.TextMuted("No comparison needed")
            ImGui.TextWrapped("This is your equipped item — open a bag copy or another candidate to compare.")
        elseif cmp.verdict == "none" then
            ctx.theme.TextMuted("No comparison available")
            ImGui.TextWrapped("Nothing is equipped there right now, or the comparison data isn't fresh — equip something, or open Equipment once, to compare.")
        else
            local eqName = (equippedItem and equippedItem.name and equippedItem.name ~= "") and equippedItem.name or "your current item"
            local headline
            if cmp.verdict == "upgrade" then headline = "Upgrade over " .. eqName
            elseif cmp.verdict == "downgrade" then headline = "Downgrade from " .. eqName
            else headline = "Sidegrade — similar to " .. eqName end
            ImGui.TextColored(color, headline)
            ctx.theme.TextMuted(cmp.summary ~= "" and cmp.summary or "No stat difference.")
        end
    end
    ImGui.EndChild()
    ImGui.PopStyleVar()
    ImGui.PopStyleColor()
end

--- Identity card (18a): the ONE place the item's name and location appear (§9 killed the
--- other three). icon + name at the heading register, coloured by usability; then a
--- content line (type · value), a furniture flags line ("Magic · No Drop · … · you can
--- use this"), and a furniture locator line (where · id · tribute). A failed usability
--- check stays a loud red line — that one is load-bearing, not furniture.
local function renderHeader(ctx, entry)
    local item = entry.item
    local source = entry.source or "inv"
    local canUseInfo = ItemTooltip.getCanUseInfo(item, source)

    if ctx.drawItemIcon and item.icon and item.icon > 0 then
        ctx.drawItemIcon(item.icon, 32)
        ImGui.SameLine()
    end
    local nameColorKey = canUseInfo.canUse and "Success" or "Error"
    ImGui.PushStyleColor(ImGuiCol.Text, ctx.theme.ToVec4(ctx.theme.Colors[nameColorKey]))
    fonts.pushHeading()
    ImGui.TextWrapped(item.name or "\xe2\x80\x94")
    fonts.pop()
    ImGui.PopStyleColor()

    local line2 = {}
    if item.type and item.type ~= "" then line2[#line2 + 1] = item.type end
    local val = item.totalValue or item.value
    if val and val ~= 0 then
        line2[#line2 + 1] = (ItemUtils and ItemUtils.formatValue) and ItemUtils.formatValue(val) or tostring(val)
    end
    if #line2 > 0 then ctx.theme.TextContent(table.concat(line2, "  \xc2\xb7  ")) end

    -- Flags + fit, one furniture line. getTypeLine already ends with the item type — that
    -- lives on line 2 here, so strip a trailing ", <type>" match before reusing it.
    local flags = TooltipData.getTypeLine and TooltipData.getTypeLine(item) or nil
    if flags and item.type and item.type ~= "" then
        local suffix = ", " .. item.type
        if flags:sub(-#suffix) == suffix then flags = flags:sub(1, #flags - #suffix) end
    end
    local parts = {}
    if flags and flags ~= "" then parts[#parts + 1] = (flags:gsub(", ", " \xc2\xb7 ")) end
    if TooltipData.formatSize then
        -- formatSize takes the ITEM (it reads item.size itself) — passing the number
        -- indexed a number and threw mid-child on the first in-game render.
        local sz = TooltipData.formatSize(item)
        if sz and sz ~= "" then parts[#parts + 1] = "size " .. sz end
    end
    if (tonumber(item.weight) or 0) > 0 then parts[#parts + 1] = string.format("wt %s", tostring(item.weight)) end
    local reqLevel = tonumber(item.reqLevel) or 0
    if reqLevel > 0 then parts[#parts + 1] = string.format("req %d", reqLevel) end
    if canUseInfo.canUse then parts[#parts + 1] = "you can use this" end
    if #parts > 0 then ctx.theme.TextFurniture(table.concat(parts, " \xc2\xb7 ")) end
    if not canUseInfo.canUse then
        ctx.theme.TextError("You cannot use: " .. (canUseInfo.reason or "restriction"))
    end

    local loc = {}
    if source == "bank" then
        loc[#loc + 1] = string.format("bank %s, slot %s", tostring(entry.bag), tostring(entry.slot))
    elseif source == "equipped" then
        loc[#loc + 1] = "equipped"
    else
        loc[#loc + 1] = string.format("bag %s, slot %s", tostring(entry.bag), tostring(entry.slot))
    end
    if item.id and item.id ~= 0 then loc[#loc + 1] = "id " .. tostring(item.id) end
    if (tonumber(item.tribute) or 0) > 0 then loc[#loc + 1] = "tribute " .. tostring(item.tribute) end
    ctx.theme.TextFurniture(table.concat(loc, " \xc2\xb7 "))
end

--- Rules block: sell status line (all sources) + action buttons gated per-action rather than by
--- a single source check. Keep/Junk are name-keyed INI edits needing no bag/slot, so they render
--- for every sellListSource (inv/sell/bank/augments/reroll — mirrors ui_common.lua's context-menu
--- gate). Add to Reroll / Aug Utility need a live pickup or getItemTLO path, so they render only
--- for packBacked sources (inv/sell/augments) or bank (explicit bank branch in both the pickup
--- and getItemTLO paths); "reroll"-sourced tabs are excluded from both — the item is already on
--- a list, and its bag/slot may be bank coordinates that getItemTLO's pack-fallback branch would
--- misresolve. reason/willSell/inKeep/inJunk come from the caller's per-tab memo (see
--- getVerdictMemo) instead of a fresh ctx.getSellStatusForItem call every frame; reroll list
--- membership is looked up live since rerollService.getListStatus is already O(1).
local function renderRulesBlock(ctx, entry, memo)
    local item = entry.item
    local source = entry.source or "inv"
    if not ctx.getSellStatusForItem then return end

    -- Header/space come from the RULES section wrapper (beginSection) since the v2 pass.
    local reason, willSell, inKeep, inJunk = memo.reason, memo.willSell, memo.inKeep, memo.inJunk
    local label = willSell and "Sells because: " or "Stays because: "
    if ctx.formatSellStatus then
        local statusText, statusColor = ctx.formatSellStatus(reason, willSell, ctx.theme)
        ImGui.TextColored(statusColor, label .. statusText)
    else
        ImGui.Text(label .. tostring(reason))
    end

    local packBacked = (source == "inv" or source == "sell" or source == "augments")
    local sellListSource = packBacked or source == "bank" or source == "reroll"  -- mirror ui_common.lua:339
    if not sellListSource then return end  -- equipped/corpse tabs: status line only, as today

    ImGui.Spacing()
    if item.name and item.name ~= "" and ctx.applySellListChange then
        ctx.theme.PushKeepButton(not inKeep)
        if ImGui.Button("Keep##ItemDisplayRules") then
            if inKeep then ctx.applySellListChange(item.name, false, inJunk)
            else ctx.applySellListChange(item.name, true, false) end
            verdictMemo[verdictMemoKey(entry)] = nil  -- Rules line reflects the change next frame
        end
        ctx.theme.PopButtonColors()
        ImGui.SameLine()
        ctx.theme.PushJunkButton(not inJunk)
        if ImGui.Button("Junk##ItemDisplayRules") then
            if inJunk then ctx.applySellListChange(item.name, inKeep, false)
            else ctx.applySellListChange(item.name, false, true) end
            verdictMemo[verdictMemoKey(entry)] = nil
        end
        ctx.theme.PopButtonColors()
    end

    if (packBacked or source == "bank") and ctx.resolveRerollList and ctx.requestAddToRerollList then
        local resolvedList = ctx.resolveRerollList(item.name, item.type)
        if resolvedList then
            ImGui.SameLine()
            local itemId = item.id or item.ID
            -- listStatus covers both the confirmed server list and the pending-sync list, so an
            -- out-of-guild-hall click ("Already on pending list") also renders as a disabled
            -- button with truthful feedback instead of a silent no-op.
            local listStatus = (itemId and ctx.rerollService and ctx.rerollService.getListStatus)
                and ctx.rerollService.getListStatus(resolvedList, itemId) or nil
            local rerollDisabled = (listStatus ~= nil)
                or (ctx.uiState.pendingRerollAdd ~= nil and ctx.uiState.pendingRerollAdd.list == resolvedList)
            ctx.theme.PushKeepButton(rerollDisabled)
            if ImGui.Button("Add to Reroll##ItemDisplayRules") then
                -- Re-check at click time (matches augments.lua's pattern) so a same-frame
                -- double-click can't queue a duplicate server add.
                if not rerollDisabled then
                    local payload = (source == "bank")
                        and { bag = entry.bag, slot = entry.slot, id = itemId, name = item.name, source = "bank" }
                        or item
                    ctx.requestAddToRerollList(resolvedList, payload)
                end
            end
            if listStatus and ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text(listStatus == "listed"
                    and ((resolvedList == "mythical") and "Already on mythical reroll list." or "Already on augment reroll list.")
                    or "Already on pending list (syncs in guild hall).")
                ImGui.EndTooltip()
            end
            ctx.theme.PopButtonColors()
        end
    end

    if packBacked or source == "bank" then
        ImGui.SameLine()
        if ImGui.Button("Aug Utility##ItemDisplayRules") then
            -- Augment Utility's own target resolution reads the active Item Display tab (this
            -- window) — see augment_utility.lua — so opening it here is enough, no bag/slot needed.
            ctx.uiState.augmentUtilitySlotIndex = 1
            registry.setWindowState("augmentUtility", true, true)
        end
    end
end

-- ---------------------------------------------------------------- v2 sections (18a)
-- Collapsibles remember open/closed per character (services/section_state, spec §6).
-- Defaults per the mockup: SPELL DATA starts closed, everything else open.

local SECTION_DEFAULTS = { Effects = true, AllStats = true, SpellData = false, Augments = true, Rules = true }

local function beginSection(id, label)
    local default = SECTION_DEFAULTS[id]
    local open = sectionState.isOpen("ItemDisplay", id, default)
    if ImGui.SetNextItemOpen then ImGui.SetNextItemOpen(open) end
    -- The count lives in the label; the ##IDsec id keeps the header stable while it moves.
    local shown = ImGui.CollapsingHeader(tostring(label) .. "##IDsec" .. id) and true or false
    if shown ~= open then sectionState.set("ItemDisplay", id, default, shown) end
    return shown
end

local EFFECT_KIND_LABEL = { Clicky = "clicky", Worn = "worn", Proc = "combat proc",
                            Focus = "focus", Spell = "spell" }

--- EFFECTS: one row per effect (item's own + socketed augs' — the cache already merged
--- them), spell-blue name, furniture kind, and a hover card with the readable facts.
local function renderEffectsSection(ctx, effects)
    if not effects or #effects == 0 then return end
    if not beginSection("Effects", string.format("EFFECTS (%d)", #effects)) then return end
    for i, e in ipairs(effects) do
        ImGui.PushID("IDeffect_" .. i)
        ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Kit.SpellBlue), e.spellName or "?")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            -- pcall between Begin/EndTooltip: a throw here must never skip EndTooltip.
            pcall(function()
                ImGui.Text(e.spellName or "?")
                ctx.theme.TextFurniture((EFFECT_KIND_LABEL[e.key] or tostring(e.key))
                    .. " \xc2\xb7 spell " .. tostring(e.spellId))
                if e.desc and e.desc ~= "" then
                    ImGui.PushTextWrapPos(320)
                    pcall(ImGui.TextWrapped, e.desc)  -- keep the wrap-pos stack balanced too
                    ImGui.PopTextWrapPos()
                end
                local castT = tonumber(e.castTime)
                if castT and castT > 0 then
                    ctx.theme.TextContent(string.format("cast %.1fs", castT))
                end
                local recastT = tonumber(e.recastTime)
                if recastT and recastT > 0 then
                    ctx.theme.TextContent("recast " .. TooltipRender.formatSeconds(recastT))
                end
            end)
            ImGui.EndTooltip()
        end
        ImGui.SameLine()
        ctx.theme.TextFurniture("\xc2\xb7 " .. (EFFECT_KIND_LABEL[e.key] or tostring(e.key)))
        ImGui.PopID()
    end
end

-- The compact stat grid's field set. The strip's own cells (hp/mana/end/ac/haste/regen —
-- or the weapon cells) stay out of this list so nothing is stated twice (§9); attack and
-- dmg/delay join it only when the GENERAL strip is up (they'd otherwise be invisible on
-- e.g. attack jewelry).
local ALL_STATS_SPECS = {
    { key = "str", h = "heroicSTR", label = "str" },
    { key = "sta", h = "heroicSTA", label = "sta" },
    { key = "agi", h = "heroicAGI", label = "agi" },
    { key = "dex", h = "heroicDEX", label = "dex" },
    { key = "int", h = "heroicINT", label = "int" },
    { key = "wis", h = "heroicWIS", label = "wis" },
    { key = "cha", h = "heroicCHA", label = "cha" },
    { key = "svMagic", h = "heroicSvMagic", label = "magic" },
    { key = "svFire", h = "heroicSvFire", label = "fire" },
    { key = "svCold", h = "heroicSvCold", label = "cold" },
    { key = "svPoison", h = "heroicSvPoison", label = "poison" },
    { key = "svDisease", h = "heroicSvDisease", label = "disease" },
    { key = "svCorruption", h = "heroicSvCorruption", label = "corrupt" },
    { key = "accuracy", label = "accuracy" },
    { key = "avoidance", label = "avoidance" },
    { key = "shielding", label = "shielding" },
    { key = "strikeThrough", label = "strikethru" },
    { key = "damageShield", label = "dmg shield" },
    { key = "combatEffects", label = "combat eff" },
    { key = "dotShielding", label = "dot shield" },
    { key = "spellShield", label = "spell shield" },
    { key = "stunResist", label = "stun resist" },
    { key = "clairvoyance", label = "clairvoy" },
    { key = "healAmount", label = "heal amt" },
    { key = "spellDamage", label = "spell dmg" },
    { key = "dmgBonus", label = "dmg bonus" },
    { key = "manaRegen", label = "mana regen" },
    { key = "enduranceRegen", label = "end regen" },
    { key = "luck", label = "luck" },
    { key = "purity", label = "purity" },
}

--- ALL STATS: every non-zero stat as "label value" ("40 +8" = base+heroic, the game's own
--- convention), aug-inclusive, three columns. Nothing here restates a strip cell.
local function renderAllStatsSection(ctx, item, augStats, strip)
    local function sv(f) return (tonumber(item[f]) or 0) + ((augStats and tonumber(augStats[f])) or 0) end
    local rows = {}
    local function consider(spec)
        local v = sv(spec.key)
        local h = spec.h and sv(spec.h) or 0
        if v ~= 0 or h ~= 0 then rows[#rows + 1] = { label = spec.label, v = v, h = h } end
    end
    for _, spec in ipairs(ALL_STATS_SPECS) do consider(spec) end
    if strip == "general" then
        consider({ key = "attack", label = "attack" })
        consider({ key = "damage", label = "dmg" })
        consider({ key = "itemDelay", label = "delay" })
    end
    if #rows == 0 then return end
    if not beginSection("AllStats", string.format("ALL STATS (%d)", #rows)) then return end
    local COL_W, LABEL_W, PER_ROW = 150, 70, 3
    for i, r in ipairs(rows) do
        local col = (i - 1) % PER_ROW
        if col ~= 0 then ImGui.SameLine(col * COL_W) end
        ctx.theme.TextFurniture(r.label)
        ImGui.SameLine(col * COL_W + LABEL_W)
        local str = tostring(r.v)
        if r.h ~= 0 then str = str .. string.format(" +%d", r.h) end
        ctx.theme.TextContent(str)
    end
end

--- SPELL DATA & IDS: the raw numbers, off by default (18a: "stays closed"). Zero-valued
--- recovery/recast rows are omitted outright — a zero here is furniture, not information.
local function renderSpellDataSection(ctx, effects)
    if not effects or #effects == 0 then return end
    if not beginSection("SpellData", "SPELL DATA & IDS") then return end
    for i, e in ipairs(effects) do
        ctx.theme.TextContent(string.format("%s \xe2\x80\x94 %s", tostring(e.key), tostring(e.spellName)))
        ctx.theme.TextFurniture("  id " .. tostring(e.spellId))
        local dur = ctx.getSpellDuration and ctx.getSpellDuration(e.spellId) or nil
        if dur ~= nil and (tonumber(dur) or 0) ~= 0 then
            ctx.theme.TextFurniture("  duration " .. TooltipRender.formatSeconds(dur))
        end
        local rec = ctx.getSpellRecoveryTime and ctx.getSpellRecoveryTime(e.spellId) or nil
        if rec ~= nil and (tonumber(rec) or 0) > 0 then
            ctx.theme.TextFurniture(string.format("  recovery %.2fs", rec))
        end
        local rt = ctx.getSpellRecastTime and ctx.getSpellRecastTime(e.spellId) or nil
        if rt ~= nil and (tonumber(rt) or 0) > 0 then
            ctx.theme.TextFurniture("  recast " .. TooltipRender.formatSeconds(rt))
        end
        local rng = ctx.getSpellRange and ctx.getSpellRange(e.spellId) or nil
        if rng ~= nil and rng ~= 0 then
            ctx.theme.TextFurniture("  range " .. tostring(rng))
        end
        if i < #effects then ImGui.Spacing() end
    end
end

--- Resolve a socket's full item table (live TLO — click-time only, never per frame).
local function resolveSocketItem(entry, socketIndex)
    local ItemHelpers = require('itemui.utils.item_helpers')
    local ok, full = pcall(function()
        local parentIt = ItemHelpers.getItemTLO(entry.bag, entry.slot, entry.source)
        if not parentIt then return nil end
        return TooltipData.getSocketItemStats(parentIt, entry.bag, entry.slot, entry.source, socketIndex)
    end)
    if ok then return full end
    return nil
end

--- One socket row: icon, name (spell-blue; ornament in mythic), or "+ empty · type".
--- Left-click: empty → Aug Utility opened to this socket; filled → opens as a tab.
--- Right-click on a filled socket: the augInserted context menu — where the shift-gated,
--- cost-stated Remove lives (rule 6; the old icon right-click removed with NO gate).
local function renderAugmentRow(ctx, entry, row, isOrnament)
    ImGui.PushID("IDaug_" .. tostring(row.slotIndex))
    local isEmpty = (row.augName == nil or row.augName == "empty" or row.augName == "")
    if (row.iconId or 0) > 0 and ctx.drawItemIcon then
        pcall(function() ctx.drawItemIcon(row.iconId, 20) end)
    elseif ctx.drawEmptySlotIcon then
        pcall(function() ctx.drawEmptySlotIcon() end)
    else
        ImGui.Dummy(ImVec2(20, 20))
    end
    ImGui.SameLine()
    if isEmpty then
        local t
        if row.prefix and row.prefix ~= "" then
            t = row.prefix .. "empty"
        elseif isOrnament then
            t = "Ornament (type 20): empty"
        else
            t = "Slot " .. tostring(row.slotIndex) .. ": empty"
        end
        ctx.theme.TextFurniture("+ " .. t)
    else
        local color = isOrnament and ctx.theme.Kit.Mythic or ctx.theme.Kit.SpellBlue
        ImGui.TextColored(ctx.theme.ToVec4(color), row.augName)
        if isOrnament then
            ImGui.SameLine()
            ctx.theme.TextFurniture("\xc2\xb7 ornament")
        end
    end
    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
        if isEmpty then
            uiState.augmentUtilitySlotIndex = row.slotIndex
            uiState.augmentUtilityWindowOpen = true
            uiState.augmentUtilityWindowShouldDraw = true
        else
            local full = resolveSocketItem(entry, row.slotIndex)
            if full and ctx.addItemDisplayTab then ctx.addItemDisplayTab(full, entry.source) end
        end
    end
    if not isEmpty then
        contextMenu.render(ctx, {
            name = row.augName, icon = row.iconId,
            type = isOrnament and "Ornament" or "Augmentation",
            bag = entry.bag, slot = entry.slot,
        }, {
            popupId = "ItemContextAugSocket_" .. tostring(row.slotIndex) .. "_"
                .. tostring(entry.bag) .. "_" .. tostring(entry.slot),
            context = "augInserted",
            source = entry.source,
            where = isOrnament and "Ornament slot"
                or ("Socket " .. tostring(row.slotIndex) .. " of " .. tostring(entry.item and entry.item.name or "?")),
            onOpenSubject = function()
                local full = resolveSocketItem(entry, row.slotIndex)
                if full and ctx.addItemDisplayTab then ctx.addItemDisplayTab(full, entry.source) end
            end,
            onRemoveAugment = (not isOrnament and ctx.removeAugment) and function()
                ctx.removeAugment(entry.bag, entry.slot, entry.source, row.slotIndex)
            end or nil,
        })
    end
    ImGui.PopID()
end

--- AUGMENTS (n/m): standard sockets from the scan-invalidated cache, then the ornament
--- slot (19a). The one how-to line is this section's footer — no per-row hints.
local function renderAugmentsSection(ctx, entry, cachedTip)
    local augLines = cachedTip and cachedTip.augLines or nil
    if augLines == false then augLines = nil end
    local ornament = cachedTip and cachedTip.ornamentLine or nil
    if (not augLines or #augLines == 0) and not ornament then return end
    local filled, total = 0, 0
    if augLines then
        total = #augLines
        for _, r in ipairs(augLines) do
            if r.augName and r.augName ~= "empty" and r.augName ~= "" then filled = filled + 1 end
        end
    end
    if ornament then
        total = total + 1
        if ornament.augName and ornament.augName ~= "empty" and ornament.augName ~= "" then filled = filled + 1 end
    end
    if not beginSection("Augments", string.format("AUGMENTS (%d/%d)", filled, total)) then return end
    if augLines then
        for _, row in ipairs(augLines) do renderAugmentRow(ctx, entry, row, false) end
    end
    if ornament then renderAugmentRow(ctx, entry, ornament, true) end
    ctx.theme.TextFurniture("click an empty slot \xe2\x86\x92 Aug Utility \xc2\xb7 click a filled one \xe2\x86\x92 opens it as a tab")
end

--- Draw the full verdict card + full detail for one tab entry. entry = { bag, slot, source, item, label }
local function renderOneItemContent(ctx, entry)
    if not entry or not entry.item then return end
    local item = entry.item
    local source = entry.source or "inv"

    -- Prewarm lazy stat/worn/aug fields before item_compare and the slot/aug resolution below
    -- touch them (buildItemFromMQ batch-loads all STAT_FIELDS off the first access to any one).
    local _ = item.ac
    _ = item.wornSlots
    _ = item.augSlots

    renderHeader(ctx, entry)
    ImGui.Spacing()

    -- One prepare per frame: effects + the scan-invalidated cache entry carrying the
    -- summed socket stats (augStats) and the socket rows (augLines/ornamentLine). This is
    -- what makes every number below aug-inclusive — §0.1's "one number everywhere".
    local tipOpts = { source = source, bag = entry.bag, slot = entry.slot, entry = entry }
    local effects = ItemTooltip.prepareTooltipContent(item, ctx, tipOpts)
    local cachedTip = TooltipData.getCachedTooltipEntry(item, tipOpts)
    local augStats = cachedTip and cachedTip.augStats or nil

    local memo = getVerdictMemo(ctx, entry)
    local wornSlotIndex = memo.wornSlotIndex
    local equippedItem = resolveEquippedForSlot(ctx, wornSlotIndex)
    -- Self-view: an equipped-source tab whose worn slot resolves back to itself. Match on
    -- identity (source+slot), NOT item.id -- EQ ids are template ids, so a bag copy of an item
    -- you already wear would false-positive on an id compare and lose its legitimate
    -- "identical" comparison (which item_compare already renders honestly as a sidegrade with
    -- "No stat difference."). Cross-slot equipped views (e.g. a Ring2 item vs the Ring1
    -- occupant) are NOT a self-view and still compare normally.
    local isSelfView = (source == "equipped" and entry.slot == wornSlotIndex)
    if isSelfView then equippedItem = nil end

    -- The equipped side's socket stats, same cache, so the comparison is totals vs totals.
    local equippedAugStats = nil
    if equippedItem then
        local eqOpts = { source = "equipped", bag = equippedItem.bag or 0, slot = equippedItem.slot }
        pcall(function() ItemTooltip.prepareTooltipContent(equippedItem, ctx, eqOpts) end)
        local eqTip = TooltipData.getCachedTooltipEntry(equippedItem, eqOpts)
        equippedAugStats = eqTip and eqTip.augStats or nil
    end

    local procName = nil
    for _, e in ipairs(effects or {}) do
        if e.key == "Proc" then procName = e.spellName; break end
    end

    local cmp = ItemCompare.compare(item, equippedItem, {
        augStats = augStats, equippedAugStats = equippedAugStats, procName = procName,
    })
    renderVerdictBox(ctx, cmp, equippedItem, wornSlotIndex ~= nil, isSelfView)
    if wornSlotIndex ~= nil then ImGui.Spacing() end

    renderCompareTileGrid(ctx, cmp.rows)
    if cmp.rows and #cmp.rows > 0 then ImGui.Spacing() end

    ImGui.Separator()
    local ok, err = pcall(function()
        renderEffectsSection(ctx, effects)
        renderAllStatsSection(ctx, item, augStats, cmp.strip)
        renderSpellDataSection(ctx, effects)
        renderAugmentsSection(ctx, entry, cachedTip)
        if beginSection("Rules", "RULES") then
            renderRulesBlock(ctx, entry, memo)
        end
    end)
    if not ok then
        ctx.theme.TextError("Error drawing item sections.")
        local diagnostics = require('itemui.core.diagnostics')
        diagnostics.recordError("Item Display", "Error drawing item sections", err)
    end
end

-- Module interface: render main Item Display window (tabbed)
function ItemDisplayView.render(ctx)
    if not registry.shouldDraw("itemDisplay") then return end

    local layoutConfig = ctx.layoutConfig
    local tabs = state.itemDisplayTabs
    local activeIdx = state.itemDisplayActiveTabIndex
    if activeIdx < 1 or activeIdx > #tabs then
        state.itemDisplayActiveTabIndex = #tabs > 0 and 1 or 0
        activeIdx = state.itemDisplayActiveTabIndex
    end

    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local px = layoutConfig.ItemDisplayWindowX or 0
    local py = layoutConfig.ItemDisplayWindowY or 0
    if px and py and (px ~= 0 or py ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(px, py), condPos)
    end

    local w = layoutConfig.WidthItemDisplayPanel or constants.VIEWS.WidthItemDisplayPanel
    local h = layoutConfig.HeightItemDisplay or constants.VIEWS.HeightItemDisplay
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Item Display##ItemUIItemDisplay", registry.isOpen("itemDisplay"), windowFlags)
    registry.setWindowState("itemDisplay", winOpen, winOpen)

    if not winOpen then
        state.itemDisplayTabs = {}
        state.itemDisplayActiveTabIndex = 1
        ImGui.End()
        return
    end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    -- (The old top-right Lock checkbox moved into the icon toolbar below — same registry pin.)

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
                state.itemDisplayActiveTabIndex = i
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
        local t = state.itemDisplayTabs
        local curActive = state.itemDisplayActiveTabIndex
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
        state.itemDisplayActiveTabIndex = curActive
        if #state.itemDisplayTabs > 0 and (state.itemDisplayActiveTabIndex < 1 or state.itemDisplayActiveTabIndex > #state.itemDisplayTabs) then
            state.itemDisplayActiveTabIndex = 1
        end
        if #state.itemDisplayTabs == 0 then
            registry.setWindowState("itemDisplay", false, false)
        end
        -- Use current selection for content (updated by tab click or close)
        activeIdx = state.itemDisplayActiveTabIndex
        if activeIdx < 1 or activeIdx > #state.itemDisplayTabs then
            activeIdx = math.max(1, #state.itemDisplayTabs)
        end
    end

    -- Toolbar and content
    if #tabs == 0 then
        if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
            ImGui.TextColored(ImVec4(0.7, 0.7, 0.7, 1.0), "No item selected. Right-click an item and choose \"CoOp UI Item Display\" to open.")
        end
        ImGui.EndChild()
    else
        local tab = tabs[activeIdx]
        if tab then
            -- Icon toolbar (18a): recents · locate · refresh, lock right-aligned. The old
            -- Source line and the wide Recent combo are gone — the identity card states
            -- where the item is (§9), and recents live behind the history glyph.
            ImGui.Spacing()
            local recent = state.itemDisplayRecent
            if windowHeader.iconButton("##IDRecentBtn", GLYPH_RECENT,
                    "Recent items", #recent == 0, false) then
                ImGui.OpenPopup("##IDRecentPopup")
            end
            if #recent > 0 then
                ImGui.SameLine(0, 2)
                ctx.theme.TextFurniture(tostring(#recent))
            end
            ImGui.SameLine(0, 8)
            if windowHeader.iconButton("##IDLocateBtn", GLYPH_LOCATE,
                    "Locate: flash this item's native slot", false, false) then
                state.itemDisplayLocateRequest = { source = tab.source, bag = tab.bag, slot = tab.slot }
                state.itemDisplayLocateRequestAt = mq.gettime()
            end
            ImGui.SameLine(0, 4)
            if windowHeader.iconButton("##IDRefreshBtn", GLYPH_REFRESH,
                    "Re-read this item from the game", false, false) then
                if ctx.getItemStatsForTooltip then
                    local fresh = ctx.getItemStatsForTooltip({ bag = tab.bag, slot = tab.slot }, tab.source)
                    if fresh and fresh.id and fresh.id ~= 0 then
                        tab.item = fresh
                        verdictMemo = {}  -- Refresh should not show stale verdict/rules data
                    end
                end
            end
            do  -- lock, right-aligned: the same registry pin the old checkbox drove
                local availX = 0
                local ax = ImGui.GetContentRegionAvail()
                if type(ax) == "number" then availX = ax
                elseif type(ax) == "table" and ax.x then availX = ax.x end
                if availX > 30 then ImGui.SameLine(0, availX - 24) else ImGui.SameLine(0, 8) end
                local locked = registry.isPinned("itemDisplay")
                local tip = locked and "Unlock: ESC and close-alls affect this window again"
                    or "Lock: stays up through ESC, the toggle keybind and close-alls"
                if windowHeader.iconButton("##IDLockBtn", locked and GLYPH_LOCKED or GLYPH_UNLOCKED,
                        tip, false, locked) then
                    registry.setPinned("itemDisplay", not locked)
                    if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                end
            end
            if ImGui.BeginPopup("##IDRecentPopup") then
                for _, r in ipairs(recent) do
                    local isCurrent = (r.bag == tab.bag and r.slot == tab.slot and r.source == tab.source)
                    -- Selectable returns (selected, pressed) — act on the SECOND value.
                    local _sel, pressed = ImGui.Selectable(
                        (r.label or "?") .. "##Recent" .. tostring(r.bag) .. "_" .. tostring(r.slot), isCurrent)
                    if pressed then
                        local found
                        for i, t in ipairs(tabs) do
                            if t.bag == r.bag and t.slot == r.slot and t.source == r.source then
                                state.itemDisplayActiveTabIndex = i
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
                                state.itemDisplayActiveTabIndex = #tabs
                            end
                        end
                        ImGui.CloseCurrentPopup()
                    end
                end
                ImGui.EndPopup()
            end
            ImGui.Spacing()
            if ImGui.BeginChild("##ItemDisplayScroll", ImVec2(0, 0), true) then
                -- pcall INSIDE the child: a throw in content must never skip EndChild —
                -- one skipped EndChild pauses the whole plugin overlay ("ImGui Critical
                -- Failure: Missing EndChild()"), and /lua stop from that paused state
                -- crashes the client in mq2lua. Learned in-game 2026-07-30.
                local contentOk, contentErr = pcall(renderOneItemContent, ctx, tab)
                if not contentOk then
                    ctx.theme.TextError("Error drawing this item.")
                    local diagnostics = require('itemui.core.diagnostics')
                    diagnostics.recordError("Item Display", "Error drawing item content", contentErr)
                end
            end
            ImGui.EndChild()
        end
    end

    ImGui.End()
end

-- Registry: Item Display module (4.2 state ownership — window in registry, tabs/recent/locate in view)
registry.register({
    id          = "itemDisplay",
    zone        = "R1",  -- window_zones placement column/slot (mockup 10a)
    label       = "Item Display",
    buttonWidth = 90,
    tooltip     = "Inspect item stats and augments",
    layoutKeys  = { x = "ItemDisplayWindowX", y = "ItemDisplayWindowY" },
    enableKey   = "ShowItemDisplayWindow",
    onClose     = function()
        state.itemDisplayTabs = {}
        state.itemDisplayActiveTabIndex = 1
        uiState.removeAllQueue = nil
        uiState.optimizeQueue = nil
        verdictMemo = {}  -- bound growth across the window's lifetime, not just per-tab TTL
    end,
    render      = function(refs)
        local ctx = context.build()
        ItemDisplayView.render(ctx)
    end,
})

return ItemDisplayView
