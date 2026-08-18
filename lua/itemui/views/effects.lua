--[[
    Effects Companion - buffs, songs, and auras merged into ONE compact window.

    RoF2's native BuffWindow/ShortDurationBuffWindow have zero EQTypes, so a
    merged NATIVE window is impossible at the SIDL level - this is the CoOpt
    replacement: every active effect in one place, denser and more informative
    than the three native windows combined.

    Two display modes (persisted): detailed rows (icon, name, hit counter,
    colored time remaining) and an icon grid (icon + tiny time label). Both
    show a hover tooltip (slot, spell id, exact time, hit count) and offer
    right-click > Remove via MQ's /removebuff. Auras are display-only (manage
    them in the game's Aura window). Close the native buff windows if you want
    this to be the only buff UI - the game remembers per-character.

    Also hosts the WORN tracker: every worn/focus effect line on the equipped
    set with its stacking rule, wasted duplicates flagged (utils/worn_effects -
    the same walk that feeds the upgrade/aug score context).

    Scan is throttled (500ms) - TLO reads happen at most twice a second, and
    only while the window is open.
]]

local mq = require('mq')
require('ImGui')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local dockState = require('itemui.services.dock_state')
local windowHeader = require('itemui.components.window_header')
local contextMenu = require('itemui.components.context_menu')
local wornEffects = require('itemui.utils.worn_effects')

local EffectsView = {}

local EFFECTS_WINDOW_WIDTH = 340
local EFFECTS_WINDOW_HEIGHT = 480

local SCAN_INTERVAL_MS = 500
local MAX_SONG_SLOTS = 30
local MAX_AURA_SLOTS = 8
local ICON_SIZE = 24

-- Scan cache: { buffs = {...}, songs = {...}, auras = {...}, maxBuffs = n }
local cache = { at = 0, buffs = {}, songs = {}, auras = {}, maxBuffs = 30 }

-- Worn/Focus tracker cache: rebuilt when the equipped set's fingerprint moves, plus a
-- short TTL retry (spell ids resolve lazily through the TLO; a read that landed during
-- zoning returns 0 uncached, and only a re-walk picks the late answer up).
local WORN_REBUILD_TTL_MS = 5000
local wornCache = { fp = nil, at = 0, built = nil }
local wornWarmAt = 0

local spellIconAnim = nil
local function drawSpellIcon(iconId, size)
    if not iconId or iconId < 0 then return false end
    if not spellIconAnim and mq.FindTextureAnimation then
        spellIconAnim = mq.FindTextureAnimation("A_SpellIcons")
    end
    if not spellIconAnim then return false end
    local ok = pcall(function()
        spellIconAnim:SetTextureCell(iconId)
        ImGui.DrawTextureAnimation(spellIconAnim, size, size)
    end)
    return ok
end

local function readEffect(kind, i)
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return nil end
    local b = (kind == "buff") and (Me.Buff and Me.Buff(i)) or (Me.Song and Me.Song(i))
    if not b or b() == nil then return nil end
    local e = { kind = kind, index = i, name = nil, seconds = nil, permanent = false, hitCount = 0, icon = nil, spellId = nil }
    pcall(function() e.name = b.Name() end)
    if not e.name or e.name == "" then return nil end
    pcall(function()
        local d = b.Duration
        local secs = d and d.TotalSeconds and d.TotalSeconds()
        if secs ~= nil then e.seconds = tonumber(secs) end
    end)
    if not e.seconds or e.seconds < 0 then
        e.seconds = nil
        e.permanent = true
    end
    pcall(function() e.hitCount = tonumber(b.HitCount()) or 0 end)
    pcall(function()
        local sp = b.Spell
        if sp and sp() ~= nil then
            e.spellId = tonumber(sp.ID())
            e.icon = tonumber(sp.SpellIcon())
            -- What the buff does. A dbstr lookup - can be empty on emu; hide then.
            local d = sp.Description and sp.Description()
            if d and d ~= "" and d ~= "NULL" then e.description = d end
        end
    end)
    pcall(function()
        local c = b.Caster and b.Caster()
        if c and c ~= "" and c ~= "NULL" then e.caster = c end
    end)
    return e
end

-- Wrapped, format-safe text (descriptions can contain '%', which ImGui.Text
-- would treat as a format string).
local function textWrapped(s)
    s = tostring(s)
    if ImGui.PushTextWrapPos then ImGui.PushTextWrapPos(340) end
    if ImGui.TextUnformatted then
        ImGui.TextUnformatted(s)
    else
        ImGui.Text((s:gsub("%%", "%%%%")))
    end
    if ImGui.PopTextWrapPos then ImGui.PopTextWrapPos() end
end

local function rescan()
    local Me = mq.TLO and mq.TLO.Me
    if not Me then return end
    local maxBuffs = 30
    pcall(function() maxBuffs = tonumber(Me.MaxBuffSlots()) or 30 end)
    cache.maxBuffs = maxBuffs

    local buffs = {}
    for i = 1, maxBuffs do
        local e = readEffect("buff", i)
        if e then buffs[#buffs + 1] = e end
    end

    -- Auras BEFORE songs, and same name-prefix guard as dock_state.lua's walkEffects (this
    -- is only the cold-start fallback -- dockState.getEffects() overwrites cache once the
    -- shared walk has run -- but the first-frame path must agree with it). An active aura
    -- grants itself as a temp buff, so Me.Song(n) and Me.Aura(n) are two independent TLO
    -- views of the same effect with no spell id to join on; the aura name is the only key.
    local auras = {}
    local auraSet = {}
    for i = 1, MAX_AURA_SLOTS do
        local ok, name = pcall(function()
            local a = Me.Aura and Me.Aura(i)
            return a and a()
        end)
        if ok and name and name ~= "" and name ~= "NULL" then
            auras[#auras + 1] = { kind = "aura", index = i, name = name, permanent = true, hitCount = 0 }
            auraSet[name:lower()] = true
        end
    end

    local songs = {}
    for i = 1, MAX_SONG_SLOTS do
        local e = readEffect("song", i)
        if e then
            -- Prefix match, not exact: EQ commonly names the granted temp buff
            -- "<Aura> Effect" / "<Aura> Rk. II" rather than reusing the aura's own name.
            local lname = e.name:lower()
            local isAuraEffect = false
            for auraName in pairs(auraSet) do
                if lname:sub(1, #auraName) == auraName then
                    isAuraEffect = true
                    break
                end
            end
            if not isAuraEffect then songs[#songs + 1] = e end
        end
    end
    cache.buffs, cache.songs, cache.auras = buffs, songs, auras
end

local function formatTime(seconds)
    if not seconds then return "" end
    local s = math.floor(seconds + 0.5)
    if s >= 3600 then return string.format("%dh%02dm", math.floor(s / 3600), math.floor((s % 3600) / 60)) end
    if s >= 60 then return string.format("%dm%02ds", math.floor(s / 60), s % 60) end
    return string.format("%ds", s)
end

-- Time-remaining urgency color; nil = default text color.
local function timeColor(e)
    if e.permanent then return nil end
    local s = e.seconds or 0
    if s <= 30 then return ImVec4(1.0, 0.35, 0.35, 1.0) end
    if s <= 120 then return ImVec4(1.0, 0.8, 0.3, 1.0) end
    return nil
end

local function effectTooltip(ctx, e)
    ImGui.BeginTooltip()
    ImGui.Text(e.name)
    ImGui.Separator()
    if e.description then
        textWrapped(e.description)
        ImGui.Spacing()
    end
    local kindLabel = (e.kind == "buff" and "Buff") or (e.kind == "song" and "Song") or "Aura"
    ctx.theme.TextMuted(string.format("%s slot %d", kindLabel, e.index))
    if e.caster then ctx.theme.TextMuted("From: " .. e.caster) end
    if e.permanent then
        ctx.theme.TextMuted("Duration: permanent")
    else
        ImGui.Text("Remaining: " .. formatTime(e.seconds))
    end
    if (e.hitCount or 0) > 0 then ImGui.Text(string.format("Hits left: %d", e.hitCount)) end
    if e.spellId and e.spellId > 0 then ctx.theme.TextMuted("Spell ID: " .. tostring(e.spellId)) end
    if e.kind ~= "aura" then
        ImGui.Spacing()
        ctx.theme.TextMuted("Right-click: remove")
    end
    ImGui.EndTooltip()
end

-- Per-effect remove popup (buffs and songs; /removebuff finds either by name). Since the
-- windows pass this rides the one context-menu builder — the effect row is §7's seventh
-- context, so it gets the same identity-first skeleton as every item menu.
local function removePopup(ctx, e)
    if e.kind == "aura" then return end
    contextMenu.render(ctx, { name = e.name, kind = e.kind, index = e.index }, {
        popupId = "EffRemove_" .. e.kind .. "_" .. e.index,
        context = "effect",
        where = (e.kind == "song") and "song" or "buff",
        onRemoveEffect = function()
            mq.cmdf('/removebuff "%s"', e.name)
            -- Forces the shared walk to re-run on the next dock tick so the row disappears
            -- promptly. (The old `cache.at = 0` here is gone: cache.at is now overwritten
            -- every frame from the shared cache, so zeroing it no longer triggers anything.)
            dockState.invalidateEffects()
        end,
    })
end

local function renderRow(ctx, e)
    ImGui.PushID("eff_" .. e.kind .. "_" .. e.index)
    ImGui.BeginGroup()
    if not drawSpellIcon(e.icon, ICON_SIZE) then
        ImGui.Dummy(ImVec2(ICON_SIZE, ICON_SIZE))
    end
    ImGui.SameLine()
    local label = e.name
    if (e.hitCount or 0) > 0 then label = string.format("%s (x%d)", label, e.hitCount) end
    ImGui.AlignTextToFramePadding()
    ImGui.Text(label)
    -- Right-aligned time
    local t = e.permanent and "--" or formatTime(e.seconds)
    local tw = ImGui.CalcTextSize(t)
    ImGui.SameLine(math.max(ImGui.GetWindowWidth() - tw - 14, 0))
    local col = timeColor(e)
    if e.permanent then
        ctx.theme.TextMuted(t)
    elseif col then
        ImGui.TextColored(col, t)
    else
        ImGui.Text(t)
    end
    ImGui.EndGroup()
    if ImGui.IsItemHovered() then effectTooltip(ctx, e) end
    removePopup(ctx, e)
    ImGui.PopID()
end

local function renderIconGrid(ctx, list)
    local perRow = math.max(1, math.floor((ImGui.GetWindowWidth() - 16) / (ICON_SIZE + 12)))
    local n = 0
    for _, e in ipairs(list) do
        if n > 0 and (n % perRow) ~= 0 then ImGui.SameLine() end
        n = n + 1
        ImGui.PushID("effg_" .. e.kind .. "_" .. e.index)
        ImGui.BeginGroup()
        if not drawSpellIcon(e.icon, ICON_SIZE) then
            ImGui.Dummy(ImVec2(ICON_SIZE, ICON_SIZE))
        end
        local t = e.permanent and "--" or formatTime(e.seconds)
        -- Compact label under the icon: minutes-level once >10m to stay narrow
        if not e.permanent and (e.seconds or 0) >= 600 then t = string.format("%dm", math.floor(e.seconds / 60)) end
        local col = timeColor(e)
        if e.permanent then
            ctx.theme.TextMuted(t)
        elseif col then
            ImGui.TextColored(col, t)
        else
            ImGui.Text(t)
        end
        ImGui.EndGroup()
        if ImGui.IsItemHovered() then effectTooltip(ctx, e) end
        removePopup(ctx, e)
        ImGui.PopID()
    end
end

local function renderSection(ctx, title, list, iconMode)
    ctx.theme.TextMuted(title)
    ImGui.Separator()
    if #list == 0 then
        -- Terse on purpose: this is a SECTION state under a header that already names what is
        -- missing, and there is no path to offer -- you get buffs by being buffed. What went
        -- is the two-leading-space indent hack, which was doing alignment with spaces.
        ImGui.Indent(8)
        ctx.theme.TextMuted("none")
        ImGui.Unindent(8)
    elseif iconMode then
        renderIconGrid(ctx, list)
    else
        for _, e in ipairs(list) do renderRow(ctx, e) end
    end
    ImGui.Spacing()
end

-- Game-supplied names can carry '%' and ImGui.Text formats; escape before any theme helper.
local function esc(s)
    return (tostring(s):gsub("%%", "%%%%"))
end

-- One sentence per stacking rule, for the line-row hover.
local function stackingSentence(g)
    if g.stacking == "highest" then
        return "highest-only: the largest copy applies; extra copies do nothing."
    elseif g.stacking == "additive_capped" then
        return g.cap and string.format("additive to a cap of %d.", g.cap) or "additive to a cap."
    end
    return "additive: every copy applies."
end

-- Units display: whole numbers stay whole ("7"), fractional units keep one decimal.
local function unitsStr(n)
    n = tonumber(n) or 0
    if n == math.floor(n) then return string.format("%d", n) end
    return string.format("%.1f", n)
end

--- The Worn tracker: every worn/focus effect LINE on the equipped set, its stacking
--- rule, and which copies are wasted — the "make sure we aren't stacking up" surface.
--- One TABLE (field round: the freeform rows clipped item names mid-word and pushed
--- the wasted reason off-screen): Effect | Value | Item | Slot, the effect named on
--- its group's first row only, Item stretching with ellipsis, a warning-colored "*"
--- on wasted values with the WHY on the row hover, and one legend line when waste
--- exists. Renders from the same worn_effects walk that feeds the score context, so
--- this section and the Aug Utility's "already worn (higher)" grey can never disagree.
local function wornRowTooltip(ctx, g, en)
    ImGui.BeginTooltip()
    ImGui.Text(esc(en.effName))
    ImGui.Separator()
    ctx.theme.TextMuted(esc(string.format("%s (%s), %s effect", en.itemName, en.slotName, en.kind)))
    textWrapped(g.displayName .. ": " .. stackingSentence(g))
    if en.wasted then
        ctx.theme.TextWarning(esc("wasted: " .. (en.wastedWhy or "a larger copy is worn")))
    elseif g.overCap then
        ctx.theme.TextWarning(string.format("line total %s exceeds the cap of %d by %s",
            unitsStr(g.total), g.cap, unitsStr(g.overCap)))
    end
    ImGui.EndTooltip()
end

local function renderWornSection(ctx, built, equipmentKnown)
    local groups = (built and built.groups) or {}
    local untracked = (built and built.untracked) or {}
    local overlapped, overCap = wornEffects.wasteSummary(built)
    ctx.theme.TextMuted(string.format("Worn effects (%d)", #groups))
    if overlapped + overCap > 0 then
        ImGui.SameLine()
        local bits = {}
        if overlapped > 0 then bits[#bits + 1] = string.format("%d wasted", overlapped) end
        if overCap > 0 then bits[#bits + 1] = string.format("%d over cap", overCap) end
        ctx.theme.TextWarning(table.concat(bits, ", "))
    end
    ImGui.Separator()
    if #groups == 0 and #untracked == 0 then
        ImGui.Indent(8)
        ctx.theme.TextMuted(equipmentKnown and "none on the equipped set" or "equipment not scanned yet")
        ImGui.Unindent(8)
        ImGui.Spacing()
        return
    end
    local flags = (ImGuiTableFlags and bit32.bor(ImGuiTableFlags.RowBg, ImGuiTableFlags.SizingStretchProp)) or 0
    if ImGui.BeginTable and ImGui.BeginTable("##WornTable", 4, flags) then
        -- pcall INSIDE BeginTable/EndTable: an unbalanced table is an uncatchable
        -- ImGuiException (the extracted-tables invariant).
        local ok, err = pcall(function()
            ImGui.TableSetupColumn("Effect", ImGuiTableColumnFlags.WidthFixed, 110)
            ImGui.TableSetupColumn("Value", ImGuiTableColumnFlags.WidthFixed, 44)
            ImGui.TableSetupColumn("Item", ImGuiTableColumnFlags.WidthStretch, 0)
            ImGui.TableSetupColumn("Slot", ImGuiTableColumnFlags.WidthFixed, 78)
            ImGui.TableHeadersRow()
            for _, g in ipairs(groups) do
                for i, en in ipairs(g.entries) do
                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    if i == 1 then
                        -- The effect names its group once; capped lines carry the
                        -- running total right where the eye already is.
                        local label = g.displayName
                        if g.stacking == "additive_capped" and g.cap then
                            label = string.format("%s %s/%d", label, unitsStr(g.total), g.cap)
                        elseif g.stacking == "additive" and #g.entries > 1 then
                            label = string.format("%s (%s total)", label, unitsStr(g.total))
                        end
                        if g.overCap then ctx.theme.TextWarning(esc(label)) else ImGui.Text(esc(label)) end
                    end
                    ImGui.TableNextColumn()
                    if en.wasted then
                        ctx.theme.TextWarning(unitsStr(en.units) .. " *")
                    else
                        ImGui.Text(unitsStr(en.units))
                    end
                    -- Row hover carries the detail the table clips (full names, the rule,
                    -- the why) - captured per CELL, value through slot, since a table
                    -- row is not itself an item.
                    local hovered = ImGui.IsItemHovered()
                    ImGui.TableNextColumn()
                    ctx.theme.TextMuted(esc(en.itemName))
                    hovered = hovered or ImGui.IsItemHovered()
                    ImGui.TableNextColumn()
                    ctx.theme.TextMuted(esc(en.slotName))
                    hovered = hovered or ImGui.IsItemHovered()
                    if hovered then wornRowTooltip(ctx, g, en) end
                end
            end
            -- Untracked names ride the same columns, muted: the calibration feed
            -- (an honest gap, not a silent zero), never invisible.
            for i, u in ipairs(untracked) do
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                if i == 1 then ctx.theme.TextFurniture("not tracked") end
                ImGui.TableNextColumn()
                ctx.theme.TextFurniture("-")
                local uHovered = ImGui.IsItemHovered()
                ImGui.TableNextColumn()
                ctx.theme.TextMuted(esc(u.effName .. "  (" .. u.itemName .. ")"))
                uHovered = uHovered or ImGui.IsItemHovered()
                ImGui.TableNextColumn()
                ctx.theme.TextMuted(esc(u.slotName))
                if uHovered or ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(esc(u.effName))
                    ImGui.Separator()
                    ctx.theme.TextMuted(esc(string.format("%s (%s), %s effect", u.itemName, u.slotName, u.kind)))
                    textWrapped("Not in the score data yet - name it to the build and it joins the tracker and the score model.")
                    ImGui.EndTooltip()
                end
            end
        end)
        ImGui.EndTable()
        if not ok then
            local diagnostics = require('itemui.core.diagnostics')
            diagnostics.recordError("Effects", "Worn table render error", err)
        end
    end
    if overlapped + overCap > 0 then
        ctx.theme.TextFurniture("* wasted - a larger copy of the same line is worn. Hover a row for why.")
    end
    ImGui.Spacing()
end

function EffectsView.render(ctx)
    if not registry.shouldDraw("effects") then return end

    local layoutConfig = ctx.layoutConfig
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.EffectsWindowX or 0
    local ay = layoutConfig.EffectsWindowY or 0
    if ax ~= 0 or ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end
    local w = layoutConfig.WidthEffectsPanel or EFFECTS_WINDOW_WIDTH
    local h = layoutConfig.HeightEffects or EFFECTS_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        -- Size floor (handoff item 6): band + table header + three rows - below this the
        -- 26px band stat is the first casualty.
        ImGui.SetNextWindowSizeConstraints(ImVec2(300, 220), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Effects##ItemUIEffects", registry.isOpen("effects"), windowFlags)
    registry.setWindowState("effects", winOpen, winOpen)
    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end
    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    if not barsOn and ctx.renderWindowLock then ctx.renderWindowLock(ctx, "effects") end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthEffectsPanel = cw
            layoutConfig.HeightEffects = ch
        end
    end
    local px, py = ImGui.GetWindowPos()
    if px and py then
        if not layoutConfig.EffectsWindowX or math.abs(layoutConfig.EffectsWindowX - px) > 1 or
           not layoutConfig.EffectsWindowY or math.abs(layoutConfig.EffectsWindowY - py) > 1 then
            layoutConfig.EffectsWindowX = px
            layoutConfig.EffectsWindowY = py
            ctx.scheduleLayoutSave()
        end
    end

    -- Buffs/songs/auras come from services/dock_state, which owns the single TLO walk shared
    -- with the top bar's buffs segment. Calling getEffects() also registers demand, so the
    -- walk keeps running on the dock tick while this window is open. Without the sharing this
    -- window and the bar would each do 40-70 TLO reads on their own cadence.
    -- Falls back to the local rescan if dock_state has not ticked yet (it needs init(d) from
    -- app.lua, and this window can be opened on the very first frame after a /lua reload).
    local now = mq.gettime()
    do
        local walked, b, s, a, mb = dockState.getEffects()
        if walked then
            cache.buffs, cache.songs, cache.auras = b, s, a
            cache.maxBuffs = mb or cache.maxBuffs
            cache.at = now
        elseif (now - cache.at) >= SCAN_INTERVAL_MS then
            -- dock_state has not ticked yet (it needs init(d) from app.lua, and this window
            -- can be opened on the first frame after a /lua reload). Gate on `walked` rather
            -- than on the tables being non-empty: a character with genuinely no buffs looks
            -- exactly like a cold cache, and we would walk forever alongside the shared walk.
            cache.at = now
            rescan()
        end
    end

    -- Worn tracker data. The walk memoizes spell ids on the equipment rows, so the
    -- fingerprint key does the real throttling; the TTL only exists to pick up
    -- lazily-resolved reads that landed as 0 during zoning. Warm the equipment cache
    -- when empty (the Aug Utility's own on-open pattern) - without a scan this
    -- window cannot answer the worn question.
    do
        if ctx.refreshEquipmentCache and not next(ctx.equipmentCache or {}) then
            if (now - wornWarmAt) > 2000 then
                wornWarmAt = now
                pcall(ctx.refreshEquipmentCache)
            end
        end
        local fp = wornEffects.fingerprint(ctx.equipmentCache)
        if not wornCache.built or wornCache.fp ~= fp or (now - wornCache.at) >= WORN_REBUILD_TTL_MS then
            wornCache.fp = fp
            wornCache.at = now
            wornCache.built = wornEffects.build(ctx)
        end
    end
    local wornGroups = (wornCache.built and wornCache.built.groups) or {}

    if barsOn then
        local nb = #(cache.buffs or {})
        local stat
        if (cache.maxBuffs or 0) > 0 then
            stat = string.format("Buffs %d/%d . Songs %d . Auras %d . Worn %d",
                nb, cache.maxBuffs, #(cache.songs or {}), #(cache.auras or {}), #wornGroups)
        else
            stat = string.format("Buffs %d . Songs %d . Auras %d . Worn %d",
                nb, #(cache.songs or {}), #(cache.auras or {}), #wornGroups)
        end
        windowHeader.render({
            id = "effects", title = "Effects", stat = stat,
            lock = {
                locked = registry.isPinned("effects"),
                onToggle = function()
                    registry.setPinned("effects", not registry.isPinned("effects"))
                    if ctx.scheduleLayoutSave then ctx.scheduleLayoutSave() end
                end,
            },
        })
    end

    local iconMode = (tonumber(layoutConfig.EffectsCompact) or 0) == 1
    local newIconMode = ImGui.Checkbox("Icon grid", iconMode)
    if newIconMode ~= iconMode then
        layoutConfig.EffectsCompact = newIconMode and 1 or 0
        ctx.scheduleLayoutSave()
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Icon grid: densest view - icons with a small time label, details on hover.")
        ImGui.Text("Unchecked: one row per effect with name, hit counter, and colored time remaining.")
        ImGui.EndTooltip()
    end
    if not barsOn then
        -- §9: in bars the band above already states exactly this, two lines higher. One
        -- window, one home for a number.
        ImGui.SameLine()
        ctx.theme.TextMuted(string.format("Buffs %d/%d | Songs %d | Auras %d | Worn %d",
            #cache.buffs, cache.maxBuffs, #cache.songs, #cache.auras, #wornGroups))
    end
    ImGui.Spacing()

    if ImGui.BeginChild("EffectsScroll", ImVec2(0, 0), false) then
        renderSection(ctx, string.format("Buffs (%d/%d)", #cache.buffs, cache.maxBuffs), cache.buffs, newIconMode)
        renderSection(ctx, string.format("Songs (%d)", #cache.songs), cache.songs, newIconMode)
        renderSection(ctx, string.format("Auras (%d)", #cache.auras), cache.auras, newIconMode)
        renderWornSection(ctx, wornCache.built, next(ctx.equipmentCache or {}) ~= nil)
    end
    ImGui.EndChild()

    ImGui.End()
end

registry.register({
    id          = "effects",
    zone        = "B1",  -- window_zones placement column/slot (mockup 10a)
    label       = "Effects",
    buttonWidth = 60,
    tooltip     = "Buffs, songs, auras, and worn-effect stacking in one compact window - timers, hit counts, wasted-copy flags, right-click remove",
    layoutKeys  = { x = "EffectsWindowX", y = "EffectsWindowY" },
    enableKey   = "ShowEffectsWindow",
    render      = function(refs)
        local ctx = context.build()
        EffectsView.render(ctx)
    end,
})

return EffectsView
