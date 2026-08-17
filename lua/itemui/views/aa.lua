--[[
    AA View - Alt Advancement pop-out window
    Part of CoOpt UI Items Companion. Tabs, search, sortable table, Train/Hotkey, Export/Import.
--]]

local mq = require('mq')
require('ImGui')
local config = require('itemui.config')
local constants = require('itemui.constants')
local context = require('itemui.context')
local aa_data = require('itemui.services.aa_data')
local aa_transfer = require('itemui.services.aa_transfer')
local registry = require('itemui.core.registry')
local windowHeader = require('itemui.components.window_header')
local diagnostics = require('itemui.core.diagnostics')

local AAView = {}

local TAB_NAMES = { "General", "Archetype", "Class", "Special" }

-- Format-safe text for GAME-supplied strings (AA names and descriptions are the
-- classic '%' carriers: "increases ... by 3%"): ImGui.Text/TextWrapped treat their
-- argument as a printf format string and RAISE on stray specifiers - and a raise
-- inside theme's Push->Text->Pop helpers strands the pushed style colour for the
-- rest of the frame. Same guard as dock_top.safeText and effects.textWrapped.
-- Static strings we author ourselves do not need this.
local function safeText(s)
    s = tostring(s)
    if ImGui.TextUnformatted then
        ImGui.TextUnformatted(s)
    else
        ImGui.Text((s:gsub("%%", "%%%%")))
    end
end
local function safeTextWrapped(s)
    s = tostring(s)
    if ImGui.PushTextWrapPos and ImGui.TextUnformatted then
        ImGui.PushTextWrapPos(0.0)
        ImGui.TextUnformatted(s)
        ImGui.PopTextWrapPos()
    else
        ImGui.TextWrapped((s:gsub("%%", "%%%%")))
    end
end

-- Module-local state (search, debounce, selection)
local searchText = ""
local searchTextApplied = ""
local searchDebounceAt = 0
local selectedAAName = nil
-- The lens (mockup aa_inshape): Can Purchase promoted from a footer checkbox to the
-- window's visible filter - "buy" | "progress" | "all". Session state, like the old
-- checkbox; the counts live in the chip labels so the window states how many
-- decisions exist before you scroll.
local aaLens = "all"
-- Sort cache
local sortCache = { key = "", list = {} }
-- Two-stage filter cache over ~2k records: stage 1 (tab + search) also carries the
-- lens COUNTS, stage 2 applies the lens. Split so the chip labels can count the
-- other lenses without a second full pass.
local baseCache = { key = "", list = {}, canBuyN = 0, inProgN = 0 }
local filterCache = { key = "", list = {} }

--- Rail cache: per-selection derived data (next-rank description via one TLO read,
--- the prereq's owned rank) so the right rail never does per-frame TLO or list walks.
local railCache = { sel = nil, gen = nil, nextDesc = nil, reqOwned = 0 }

--- hasRankTruth is a PLUGIN WALK behind a 100ms TTL (sized for aa_transfer's buy
--- verification, not for a render loop) - calling it every frame walked the whole
--- owned-ranks store ~10x/second and was the field's "window freezes on open".
--- The answer changes only when the plugin loads/unloads: probe once per data
--- generation, not per frame.
local rankTruthCache = { gen = nil, val = true }
local function hasRankTruthCached(ctx)
    local gen = (ctx.uiState and ctx.uiState.aaDataRefreshedAt) or 0
    if rankTruthCache.gen ~= gen then
        rankTruthCache.gen = gen
        rankTruthCache.val = aa_transfer.hasRankTruth()
    end
    return rankTruthCache.val
end

--- The one train path (Enter, double-click, and the Train button all land
--- here). Fires the buy at the record's nextIndex - which the truth overlay
--- has made the actual next-rank table id - then bumps the record in place
--- (noteAATrained) so a repeat-click trains the NEXT rank instead of re-firing
--- the one just bought while the rescan is still pumping, and schedules that
--- rescan. Both caches are cleared: the row's spend fields just changed.
local function fireTrain(ctx, aa)
    if not (aa and aa.nextIndex and aa.nextIndex > 0) then return end
    mq.cmd("/alt buy " .. tostring(aa.nextIndex))
    if ctx.noteAATrained then ctx.noteAATrained(aa.id) end
    ctx.uiState.aaRefreshRequested = true  -- rebuild runs in the main loop, not this frame
    sortCache.key = ""
    filterCache.key = ""
end

--- True when the record is buyable right now (the "Can buy" lens and the green cost).
local function isBuyable(aa, points)
    return aa.canTrain and points >= (aa.cost or 0)
end

--- True when the line is started but not finished (the "In progress" lens).
local function isInProgress(aa)
    local r = tonumber(aa.rank) or 0
    local m = tonumber(aa.maxRank) or 0
    return r > 0 and (m == 0 or r < m)
end

local function getFilteredList(ctx)
    local list = ctx.getAAList()
    if not list or #list == 0 then
        baseCache.key, baseCache.list, baseCache.canBuyN, baseCache.inProgN = "", {}, 0, 0
        return {}
    end
    local tab = (ctx.sortState.aaTab and ctx.sortState.aaTab >= 1 and ctx.sortState.aaTab <= 4) and ctx.sortState.aaTab or 1
    local points = ((ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}).aaPoints or 0
    local rt = (ctx.uiState and ctx.uiState.aaDataRefreshedAt) or 0
    -- Stage 1: tab + search (points ride the key because the canBuy COUNT depends on them).
    local baseKey = string.format("%d|%s|%d|%d|%s", tab, searchTextApplied or "", #list, points, tostring(rt))
    if baseCache.key ~= baseKey then
        local filtered = {}
        for i = 1, #list do
            local aa = list[i]
            -- Prefer the numeric Type (matches the client's own AA window tabs);
            -- fall back to the category string for records without one.
            local t = tonumber(aa.aatype) or 0
            if t >= 1 and t <= 4 then
                if t == tab then filtered[#filtered + 1] = aa end
            else
                local cat = (aa.category or ""):lower()
                if tab == 1 then
                    if cat == "" or cat == "general" or (cat ~= "archetype" and cat ~= "class" and cat ~= "special") then
                        filtered[#filtered + 1] = aa
                    end
                elseif (tab == 2 and cat == "archetype") or (tab == 3 and cat == "class") or (tab == 4 and cat == "special") then
                    filtered[#filtered + 1] = aa
                end
            end
        end
        local search = (searchTextApplied or ""):lower()
        if search ~= "" then
            local out = {}
            for _, aa in ipairs(filtered) do
                if (aa.name and aa.name:lower():find(search, 1, true)) or (aa.category and aa.category:lower():find(search, 1, true)) then
                    out[#out + 1] = aa
                end
            end
            filtered = out
        end
        local canBuyN, inProgN = 0, 0
        for _, aa in ipairs(filtered) do
            if isBuyable(aa, points) then canBuyN = canBuyN + 1 end
            if isInProgress(aa) then inProgN = inProgN + 1 end
        end
        baseCache.key = baseKey
        baseCache.list = filtered
        baseCache.canBuyN = canBuyN
        baseCache.inProgN = inProgN
    end
    -- Stage 2: the lens.
    local lensKey = baseCache.key .. "|" .. aaLens
    if filterCache.key == lensKey then return filterCache.list end
    local out
    if aaLens == "buy" then
        out = {}
        for _, aa in ipairs(baseCache.list) do
            if isBuyable(aa, points) then out[#out + 1] = aa end
        end
    elseif aaLens == "progress" then
        out = {}
        for _, aa in ipairs(baseCache.list) do
            if isInProgress(aa) then out[#out + 1] = aa end
        end
    else
        out = baseCache.list
    end
    filterCache.key = lensKey
    filterCache.list = out
    return out
end

local function buildSortKey(ctx, filtered)
    local col = ctx.sortState.aaColumn or "Title"
    local dir = ctx.sortState.aaDirection or ImGuiSortDirection.Ascending
    local tab = ctx.sortState.aaTab or 1
    -- aaDataRefreshedAt: bumped by the main loop when a deferred AA rebuild completes,
    -- so freshly rebuilt rows always miss the cache.
    local rt = (ctx.uiState and ctx.uiState.aaDataRefreshedAt) or 0
    return string.format("%s|%d|%d|%s|%d|%s|%s", col, dir, tab, searchTextApplied or "", #filtered, aaLens, tostring(rt))
end

local function getSortedList(ctx, filtered)
    local key = buildSortKey(ctx, filtered)
    if sortCache.key == key and #sortCache.list > 0 then return sortCache.list end
    local col = ctx.sortState.aaColumn or "Title"
    local dir = ctx.sortState.aaDirection or ImGuiSortDirection.Ascending
    -- Schwartzian: precompute keys then sort
    local decorated = {}
    for i, aa in ipairs(filtered) do
        local v
        if col == "Title" then v = aa.name or ""
        elseif col == "Cur/Max" then v = string.format("%d_%d", aa.rank or 0, aa.maxRank or 0)
        elseif col == "Cost" then v = aa.cost or 0
        elseif col == "Category" then v = aa.category or ""
        else v = aa.name or "" end
        decorated[i] = { aa = aa, key = v }
    end
    local asc = (dir == ImGuiSortDirection.Ascending)
    table.sort(decorated, function(a, b)
        if col == "Cost" then
            local va, vb = tonumber(a.key) or 0, tonumber(b.key) or 0
            if va == vb then return false end
            return (asc and (va < vb)) or ((not asc) and (va > vb))
        end
        if a.key == b.key then return false end
        return (asc and (a.key < b.key)) or ((not asc) and (a.key > b.key))
    end)
    local out = {}
    for _, d in ipairs(decorated) do out[#out + 1] = d.aa end
    sortCache.key = key
    sortCache.list = out
    return out
end

-- Resolve AA backup directory: AABackupPath if set, else config.CONFIG_PATH
local function getAABackupDir(ctx)
    local p = (ctx.layoutConfig and ctx.layoutConfig.AABackupPath) and ctx.layoutConfig.AABackupPath or ""
    if p and p ~= "" then return p end
    -- Service owns the default (Macros\aa_backups) + one-time legacy migration.
    return aa_transfer.getBackupDir()
end

-- List backup files in AA backup dir (or CONFIG_PATH)
local function listBackupFiles(ctx)
    local dir = (ctx and getAABackupDir(ctx)) or config.CONFIG_PATH
    if not dir or dir == "" then return {} end
    local out = {}
    local ok, pipe = pcall(io.popen, 'dir /b "' .. dir:gsub("/", "\\") .. '\\aa_*.ini" 2>nul')
    if ok and pipe then
        for line in pipe:lines() do
            if line and line:match("aa_.*%.ini") then out[#out + 1] = line end
        end
        pipe:close()
    end
    return out
end

-- Export/import live in services/aa_transfer.lua (main-loop driven, shared
-- with the native AA window's CoOpt buttons): verified buys + points gate.

function AAView.render(ctx)
    local state = registry.getWindowState("aa")
    if not state.windowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.AAWindowX or 0
    local ay = layoutConfig.AAWindowY or 0
    if ax and ay and (ax ~= 0 or ay ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end
    local w = layoutConfig.WidthAAPanel or constants.VIEWS.WidthAAPanel
    local h = layoutConfig.HeightAA or constants.VIEWS.HeightAA
    if w > 0 and h > 0 then
        -- Size floor (handoff item 6): band + table header + three rows - below this the
        -- 26px band stat is the first casualty.
        ImGui.SetNextWindowSizeConstraints(ImVec2(400, 240), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI AAs Companion##ItemUIAA", state.windowOpen, windowFlags)
    registry.setWindowState("aa", winOpen, winOpen)

    if not winOpen then ImGui.End(); return end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end
    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    -- The kit band carries the pin in bars; the legacy checkbox row stays for classic.
    if not barsOn and ctx.renderWindowLock then ctx.renderWindowLock(ctx, "aa") end

    -- Enter = Train selected (if trainable). Gated to this window (incl. child regions) having
    -- focus and no active widget, so Enter in another window or the search box can't train.
    if ImGui.IsKeyPressed(ImGuiKey.Enter) and selectedAAName
        and ImGui.IsWindowFocused(ImGuiFocusedFlags.RootAndChildWindows) and not ImGui.IsAnyItemActive() then
        local list = ctx.getAAList()
        local pointsSummary = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
        local aaPoints = pointsSummary.aaPoints or 0
        for _, aa in ipairs(list or {}) do
            if aa.name == selectedAAName and aa.canTrain and aaPoints >= (aa.cost or 0) then
                fireTrain(ctx, aa)
                break
            end
        end
    end

    -- Save size/position
    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthAAPanel = cw
            layoutConfig.HeightAA = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy then
        if not layoutConfig.AAWindowX or math.abs(layoutConfig.AAWindowX - cx) > 1 or
           not layoutConfig.AAWindowY or math.abs(layoutConfig.AAWindowY - cy) > 1 then
            layoutConfig.AAWindowX = cx
            layoutConfig.AAWindowY = cy
            ctx.scheduleLayoutSave()
        end
    end

    -- Refresh on open if needed. Invalidate the sort cache: refresh rebuilds the AA row
    -- objects but the cache key (col|dir|tab|search|count) may not change, serving stale rows.
    if ctx.shouldRefreshAA and ctx.shouldRefreshAA() then
        ctx.uiState.aaRefreshRequested = true  -- rebuild runs in the main loop, not this frame
        sortCache.key = ""
    end

    -- Debounce search
    local now = mq.gettime()
    if now - searchDebounceAt >= constants.TIMING.AA_SEARCH_DEBOUNCE_MS then
        searchTextApplied = searchText
        searchDebounceAt = now
    end

    -- 19d: the shared band. The XP/AA bar cell reports AAPointsTotal -- everything you have
    -- ever earned. The number you act on in HERE is what is still unspent, which is the one
    -- the bar never shows, so that is the band's stat (header contract, kit 3.6).
    if barsOn then
        local summary = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
        local unspent = tonumber(summary.aaPoints) or 0
        local statText = string.format("%d unspent", unspent)
        if ctx.isAABuilding and ctx.isAABuilding() then
            statText = statText .. string.format(" . scanning AA tables %d%%",
                math.floor((aa_data.getBuildProgress() or 0) * 100 + 0.5))
        end
        windowHeader.render({
            id = "aa", title = "AA", stat = statText,
            actions = {
                { label = windowHeader.GLYPHS.REFRESH, tooltip = "Rescan the AA list",
                  onClick = function() if ctx.refreshAA then ctx.refreshAA() end end },
            },
            lock = windowHeader.registryLock("aa", ctx),
        })
    end

    -- Tabs
    local tab = ctx.sortState.aaTab or 1
    for i = 1, 4 do
        if i > 1 then ImGui.SameLine() end
        if ImGui.Button(TAB_NAMES[i], ImVec2(80, 0)) then
            ctx.sortState.aaTab = i
            sortCache.key = ""
            ctx.scheduleLayoutSave()
        end
        if tab == i then
            ImGui.SameLine(0, 2)
            ctx.theme.TextMuted("(active)")
        end
    end
    ImGui.Spacing()

    local filtered = getFilteredList(ctx)
    local pointsSummary = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
    local aaPoints = pointsSummary.aaPoints or 0

    -- Search + the lens chips (mockup aa_inshape): Can Purchase promoted from a footer
    -- checkbox to the window's visible filter, counts in the labels - "Can buy (3)" is
    -- the window stating how many decisions exist before you scroll.
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(150)
    local changed
    searchText, changed = ImGui.InputText("##AASearch", searchText or "")
    if changed then searchDebounceAt = mq.gettime() end
    ImGui.SameLine()
    if ImGui.Button("X##AAClearSearch", ImVec2(22, 0)) then searchText = ""; searchTextApplied = ""; sortCache.key = "" end
    ImGui.SameLine(0, 12)
    do
        local chips = {
            { lens = "buy", label = string.format("Can buy (%d)", baseCache.canBuyN or 0) },
            { lens = "progress", label = string.format("In progress (%d)", baseCache.inProgN or 0) },
            { lens = "all", label = string.format("All (%d)", #(baseCache.list or {})) },
        }
        for ci, c in ipairs(chips) do
            if ci > 1 then ImGui.SameLine(0, 6) end
            if windowHeader.chip(c.label, "aaLens_" .. c.lens, aaLens == c.lens, "bottom") then
                aaLens = c.lens
                sortCache.key = ""
            end
        end
    end
    if not barsOn then
        -- In bars the band above owns Refresh -- two buttons doing the identical thing on
        -- one window is the redundancy the §9 pass deletes.
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##AA", "Rescan AA list", function() ctx.refreshAA() end, { messageAfter = "AA list refreshed" })
    end
    if ctx.isAABuilding and ctx.isAABuilding() then
        ctx.theme.TextWarning(string.format("Scanning AA tables... %d%%",
            math.floor((aa_data.getBuildProgress() or 0) * 100 + 0.5)))
    else
        ctx.theme.TextMuted(ctx.getAALastRefreshTime and ("Last: " .. os.date("%H:%M:%S", (ctx.getAALastRefreshTime() or 0) / 1000)) or "")
    end
    ImGui.Spacing()

    local sorted = getSortedList(ctx, filtered)

    -- Two columns: left = table, right = panel
    ImGui.BeginChild("AALeft", ImVec2(-220, -80), true)
    -- Three-way empty state (mockup aa_inshape, the augment_utility pattern): a scan in
    -- flight, a lens/search that filtered everything out, and a truly empty list are
    -- three different facts and each names its own way out.
    if #sorted == 0 then
        if ctx.isAABuilding and ctx.isAABuilding() then
            ctx.theme.TextWarning(string.format("Scanning AA tables... %d%%",
                math.floor((aa_data.getBuildProgress() or 0) * 100 + 0.5)))
        elseif #(ctx.getAAList() or {}) == 0 then
            ctx.theme.TextMuted("No AA data yet. Refresh to scan.")
        elseif aaLens == "buy" then
            ctx.theme.TextWarning("Nothing you can buy right now.")
            local remain = {}
            if (baseCache.inProgN or 0) > 0 then remain[#remain + 1] = "In progress" end
            if #(baseCache.list or {}) > 0 then remain[#remain + 1] = "All" end
            if #remain > 0 then
                ctx.theme.TextMuted(table.concat(remain, " and ") .. " still "
                    .. (#remain == 1 and "has" or "have") .. " entries.")
            end
        elseif aaLens == "progress" then
            ctx.theme.TextMuted("Nothing in progress on this tab. All still has entries.")
        else
            ctx.theme.TextMuted("Nothing matches your search.")
        end
    else
    -- The table lives in its own child with the legend's height RESERVED below it.
    -- A ScrollY table fills all remaining height, so the legend used to land past
    -- the frame and buy the whole center section a scrollbar just to show one line
    -- (field report). Reserving the line first means everything fits the frame.
    local legendH = ((ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14) + 8
    ImGui.BeginChild("AATableWrap", ImVec2(0, -legendH), false)
    local colNames = { "Title", "Cur/Max", "Cost", "Category" }
    local tableFlags = bit32.bor(ImGuiTableFlags.ScrollY, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter, ImGuiTableFlags.BordersV, ImGuiTableFlags.Resizable, ImGuiTableFlags.Sortable)
    if ImGui.BeginTable("AATable", 4, tableFlags) then
        local sortCol = ctx.sortState.aaColumn or "Title"
        for i = 1, 4 do
            local name = colNames[i]
            local flags = (name == "Title") and ImGuiTableColumnFlags.WidthStretch or ImGuiTableColumnFlags.WidthFixed
            if name == sortCol then flags = bit32.bor(flags, ImGuiTableColumnFlags.DefaultSort) end
            local w = (name == "Cur/Max") and constants.UI.AA_COL_CURMAX_WIDTH or (name == "Cost") and constants.UI.AA_COL_COST_WIDTH or (name == "Category") and constants.UI.AA_COL_CATEGORY_WIDTH or 0
            ImGui.TableSetupColumn(name, flags, w, i)
        end
        ImGui.TableSetupScrollFreeze(0, 1)
        local sortSpecs = ImGui.TableGetSortSpecs()
        if sortSpecs and sortSpecs.SpecsDirty and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                local idx = (spec.ColumnIndex or 0) + 1
                if idx >= 1 and idx <= 4 then
                    ctx.sortState.aaColumn = colNames[idx]
                    ctx.sortState.aaDirection = spec.SortDirection or ImGuiSortDirection.Ascending
                    sortCache.key = ""
                    ctx.scheduleLayoutSave()
                end
            end
            sortSpecs.SpecsDirty = false
        end
        ImGui.TableHeadersRow()

        local clipper = ImGuiListClipper.new()
        clipper:Begin(#sorted)
        while clipper:Step() do
            for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
                local aa = sorted[i]
                if not aa then goto continue end
                ImGui.TableNextRow()
                local isSelected = (selectedAAName == aa.name)
                if isSelected then
                    ImGui.TableSetBgColor(ImGuiTableBgTarget.RowBg0, ImGui.GetColorU32(ImGuiCol.Header, 0.4))
                end
                ImGui.TableNextColumn()
                -- The activated marker (mockup aa_inshape): " *" on abilities Hotkey
                -- applies to, so the Hotkey audience can scan for them. Passives get
                -- nothing - the legend under the table says what * means.
                local rowLabel = (aa.name or "") .. ((aa.passive == false) and " *" or "")
                if ImGui.Selectable(rowLabel, isSelected, ImGuiSelectableFlags.SpanAllColumns, ImVec2(0, 0)) then
                    selectedAAName = aa.name
                end
                -- Capture hover state of the row Selectable now: tooltip items below change "last item"
                local rowHovered = ImGui.IsItemHovered()
                if rowHovered then
                    ImGui.BeginTooltip()
                    safeText(aa.name or "")
                    if aa.description and aa.description ~= "" then safeTextWrapped(aa.description) end
                    -- requiresAbilityName is resolved by the scan (gid -> name);
                    -- the raw requiresAbility field is a group-id STRING, so
                    -- .Name on it indexed the string library and always hid this line.
                    local reqName = aa.requiresAbilityName
                    if reqName and reqName ~= "" then
                        -- safeText, not Text: the formatted RESULT still goes through
                        -- ImGui's own format pass, and reqName is a game-supplied name.
                        safeText(string.format("Requires: %s (rank %d)", reqName, tonumber(aa.requiresAbilityPoints) or 1))
                    end
                    ImGui.EndTooltip()
                end
                if rowHovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) and isSelected and aa.canTrain and aaPoints >= (aa.cost or 0) then
                    fireTrain(ctx, aa)
                end
                ImGui.TableNextColumn()
                ImGui.Text(string.format("%d/%d", aa.rank or 0, aa.maxRank or 0))
                -- Cost vocabulary (mockup aa_inshape): green = buyable NOW, plain =
                -- trainable but unaffordable, muted Max at cap. The table answers the
                -- spend question at a glance - no per-row buttons, no new columns.
                ImGui.TableNextColumn()
                if aa.maxRank and aa.maxRank > 0 and aa.rank and aa.rank >= aa.maxRank then
                    ctx.theme.TextMuted("Max")
                elseif isBuyable(aa, aaPoints) then
                    ctx.theme.TextSuccess(tostring(aa.cost or 0))
                else
                    ImGui.Text(tostring(aa.cost or 0))
                end
                ImGui.TableNextColumn()
                ImGui.Text(aa.category or "")
                ::continue::
            end
        end
        ImGui.EndTable()
    end
    ImGui.EndChild()
    ctx.theme.TextMuted("cost: green = buyable now . plain = need more points . * = activated (hotkey-able)")
    end
    ImGui.EndChild()

    ImGui.SameLine()
    ImGui.BeginChild("AARight", ImVec2(0, -80), true)
    -- The rail leads with the SELECTION (mockup aa_inshape): the thing being bought is
    -- the rail's job; the wallet strip and exp progress close it. The next rank's text
    -- leads because it is what the purchase buys; the current rank's sits muted below
    -- when the two differ. Stated degradation: when no next-rank text resolves, the
    -- current text stands alone - no apology line.
    local sel = selectedAAName
    local selRec = nil
    if sel then
        for _, aa in ipairs(sorted) do
            if aa.name == sel then selRec = aa; break end
        end
        -- The selection can live outside the current lens/tab; fall back to the full
        -- list so switching lens does not blank the rail under a live selection.
        if not selRec then
            for _, aa in ipairs(ctx.getAAList() or {}) do
                if aa.name == sel then selRec = aa; break end
            end
        end
    end
    local canTrainSel, selCost, selTrainable = false, 0, false
    if selRec then
        selCost = selRec.cost or 0
        selTrainable = selRec.canTrain and true or false
        canTrainSel = selTrainable and (aaPoints >= selCost)
    end
    -- Per-selection derived data, cached: ONE TLO read for the next rank's description
    -- (the truth overlay's per-rank table id makes AltAbility(nextIndex) the right
    -- entry) and one list walk for the prereq's owned rank. Refreshed when the
    -- selection or the data generation changes - never per frame.
    local gen = (ctx.uiState and ctx.uiState.aaDataRefreshedAt) or 0
    if selRec and (railCache.sel ~= sel or railCache.gen ~= gen) then
        railCache.sel, railCache.gen = sel, gen
        railCache.nextDesc = nil
        railCache.reqOwned = 0
        if (selRec.nextIndex or 0) > 0 then
            pcall(function()
                local na = mq.TLO.AltAbility and mq.TLO.AltAbility(selRec.nextIndex)
                local d = na and na.Description and na.Description()
                if d and tostring(d) ~= "" and tostring(d):lower() ~= "null" then
                    railCache.nextDesc = tostring(d)
                end
            end)
        end
        if selRec.requiresAbilityName and selRec.requiresAbilityName ~= "" then
            for _, aa in ipairs(ctx.getAAList() or {}) do
                if aa.name == selRec.requiresAbilityName then
                    railCache.reqOwned = tonumber(aa.rank) or 0
                    break
                end
            end
        end
    end

    if not selRec then
        -- The rail's empty state IS the old footer legend, in the place the info
        -- appears - and it makes a grey Train self-explaining before any tooltip.
        ctx.theme.TextMuted(string.format("Select an ability. You have %d points to spend.", aaPoints))
    else
        safeText(sel)
        local maxR = tonumber(selRec.maxRank) or 0
        if maxR > 0 then
            ctx.theme.TextMuted(string.format("rank %d of %d . cost %d", selRec.rank or 0, maxR, selCost))
        else
            ctx.theme.TextMuted(string.format("rank %d . cost %d", selRec.rank or 0, selCost))
        end
        ImGui.Spacing()
        local nd = railCache.nextDesc
        local cur = tostring(selRec.description or "")
        if nd and nd ~= cur then
            ctx.theme.TextMuted("next rank:")
            safeTextWrapped(nd)
            if cur ~= "" then
                -- theme.TextMuted is Push -> ImGui.Text -> Pop: escape the game text.
                ctx.theme.TextMuted(("now: " .. cur):gsub("%%", "%%%%"))
            end
        elseif cur ~= "" then
            safeTextWrapped(cur)
        end
        ImGui.Spacing()
        if ctx.theme.PushKeepButton then ctx.theme.PushKeepButton(not canTrainSel) end
        if ImGui.Button("Train", ImVec2(-1, 0)) and canTrainSel then
            for _, aa in ipairs(ctx.getAAList()) do
                if aa.name == sel then
                    fireTrain(ctx, aa)
                    break
                end
            end
        end
        if ctx.theme.PopButtonColors then ctx.theme.PopButtonColors() end
        -- Capture the button's hover NOW - the printed reason below submits its own
        -- item, and a later IsItemHovered() would be asking about the wrong one.
        local trainHovered = ImGui.IsItemHovered()
        -- The reason is PRINTED beside the grey (kit 3.5 / the W7 rule) - the rail has
        -- the room the bar cells lack. The hover tooltip stays; it is no longer the
        -- only place the answer lives.
        if not canTrainSel then
            local reason
            local reqRank = tonumber(selRec.requiresAbilityPoints) or 1
            if maxR > 0 and (tonumber(selRec.rank) or 0) >= maxR then
                reason = "maxed"
            elseif not selTrainable and selRec.requiresAbilityName and selRec.requiresAbilityName ~= ""
                and railCache.reqOwned < reqRank then
                reason = string.format("requires %s %d (you: %d)", selRec.requiresAbilityName, reqRank, railCache.reqOwned)
            elseif selTrainable and aaPoints < selCost then
                reason = string.format("costs %d - you have %d", selCost, aaPoints)
            else
                reason = "prerequisites not met"
            end
            ctx.theme.TextWarning(reason)
        end
        if trainHovered and not canTrainSel then
            ImGui.BeginTooltip()
            if selTrainable and aaPoints < selCost then
                ImGui.Text(string.format("Costs %d points - you have %d.", selCost, aaPoints))
            else
                ImGui.Text("Already at max rank, or prerequisites not met.")
            end
            ImGui.EndTooltip()
        end
        -- Hotkey: rendered ONLY for activated abilities (mockup aa_inshape) - absent on
        -- passives, never greyed. A passive can never be hotkeyed; a grey that can
        -- never un-grey teaches grey is furniture.
        if selRec.passive == false then
            if ImGui.Button("Hotkey", ImVec2(-1, 0)) then
                -- Use /aa act for activatable AAs (macro/keybind); no programmatic hotkey creation in MQ
                mq.cmd('/aa act "' .. (sel or ""):gsub('"', '\\"') .. '"')
                ctx.setStatusMessage('Use /aa act "' .. (sel or "") .. '" in a macro or keybind')
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Create hotkey for selected AA")
                ImGui.Text('Uses: /aa act "AbilityName" in macro or keybind')
                ImGui.EndTooltip()
            end
        end
    end
    ImGui.Spacing()
    -- Wallet strip closes the rail: two numbers, not three - Assigned duplicated what
    -- Cur/Max already says per row. The exp bar under it is why you come back tomorrow.
    ctx.theme.TextMuted(string.format("%d unspent . %d spent", aaPoints, pointsSummary.totalSpent or 0))
    local pctExp = pointsSummary.pctAAExp or 0
    ImGui.Text("Exp to AA:")
    ImGui.SameLine()
    ctx.theme.TextInfo(string.format("%.1f%%", pctExp))
    ImGui.ProgressBar((pctExp or 0) / 100.0, ImVec2(-1, 0))
    ImGui.Spacing()
    -- Export/Import are only accurate when the plugin's owned-ranks store is readable.
    -- Without it both fall back to the TLO rank read, which inflates on partially
    -- trained lines - the profile can be wrong and every status message still reads
    -- like success. Say so up front rather than letting the user find out later.
    if not hasRankTruthCached(ctx) then
        ctx.theme.TextWarning("AA rank data unavailable - Export/Import may be incomplete")
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("The MQ2CoOptUI plugin supplies your true trained AA ranks.")
            ImGui.Text("It is not loaded (it is disabled on stock MacroQuest installs), so CoOpt")
            ImGui.Text("falls back to the game's rank read, which over-reports partially trained lines.")
            ImGui.Text("Exports can record ranks you do not have, and an import can skip AAs it")
            ImGui.Text("believes are already trained. Verify the result in the AA window afterwards.")
            ImGui.EndTooltip()
        end
    end
    local transferBusy = aa_transfer.isBusy()
    if ImGui.Button("Export", ImVec2(80, 0)) and not transferBusy then
        aa_transfer.requestExport()
    end
    ImGui.SameLine()
    if ImGui.Button("Import", ImVec2(80, 0)) and not transferBusy then
        local files = listBackupFiles(ctx)
        if #files == 0 then ctx.setStatusMessage("No aa_*.ini backups in Macros\\aa_backups (or your AABackupPath folder)") end
        if #files > 0 then
            ctx._aaImportFileCombo = ctx._aaImportFileCombo or 1
            ctx._aaImportFiles = files
        end
    end
    if ctx._aaImportFiles and #ctx._aaImportFiles > 0 and not transferBusy then
        local idx = ctx._aaImportFileCombo or 1
        local changed
        idx, changed = ImGui.Combo("##ImportFile", idx, ctx._aaImportFiles)
        if changed then ctx._aaImportFileCombo = idx end
        ImGui.SameLine()
        if ImGui.Button("Load & Import", ImVec2(100, 0)) then
            local dir = getAABackupDir(ctx)
            -- Combo index: use as 1-based for Lua table; if binding is 0-based, use idx+1
            local oneBased = (type(idx) == "number" and idx >= 1) and idx or ((type(idx) == "number" and idx >= 0) and (idx + 1) or 1)
            local fname = ctx._aaImportFiles[oneBased]
            local path = (dir and dir ~= "" and fname) and (dir .. "/" .. fname) or (config.CONFIG_PATH and config.CONFIG_PATH .. "/" .. (fname or "")) or config.getConfigFile(fname or "")
            if path then
                if aa_transfer.startImport(path) then ctx._aaImportFiles = nil end
            end
        end
    end
    local prog = aa_transfer.getProgress()
    if prog then
        ctx.theme.TextWarning(string.format("Training %d / %d... (verified per rank)", prog.done, prog.total))
    end
    local backupDir = getAABackupDir(ctx)
    if backupDir and backupDir ~= "" then
        ctx.theme.TextMuted("Folder: " .. (backupDir:len() > 28 and ("..." .. backupDir:sub(-25)) or backupDir))
    else
        ctx.theme.TextMuted("Folder: (default)")
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Export/Import location (default: Macros\\aa_backups). Set AABackupPath in itemui_layout.ini [Layout] to use a custom folder.")
        ImGui.EndTooltip()
    end
    ImGui.EndChild()

    -- Bottom bar. The legend sentence and the Can Purchase checkbox both died into
    -- better homes (the rail's empty state; the lens chips) - Reset now covers the
    -- lens along with the search.
    ImGui.Spacing()
    if ImGui.Button("Reset", ImVec2(60, 0)) then
        aaLens = "all"
        searchText = ""
        searchTextApplied = ""
        sortCache.key = ""
    end
    ImGui.SameLine(ImGui.GetWindowWidth() - 70)
    if ImGui.Button("Done", ImVec2(60, 0)) then
        registry.setWindowState("aa", false, false)
    end

    ImGui.End()
end

-- Registry: AA module (Task 4.1 — first extraction)
registry.register({
    id          = "aa",
    zone        = "R2",  -- window_zones placement column/slot (mockup 10a)
    label       = "AA",
    buttonWidth = 45,
    tooltip     = "Track and manage Alternate Advancement abilities",
    layoutKeys  = { x = "AAWindowX", y = "AAWindowY" },
    enableKey   = "ShowAAWindow",
    onOpen      = function() end,
    onClose     = function() end,
    onTick      = nil,
    render      = function(refs)
        local ctx = context.build()
        ctx.refreshAA = aa_data.refresh
        ctx.getAAList = aa_data.getList
        ctx.getAAPointsSummary = aa_data.getPointsSummary
        ctx.shouldRefreshAA = aa_data.shouldRefresh
        ctx.getAALastRefreshTime = aa_data.getLastRefreshTime
        ctx.isAABuilding = aa_data.isBuilding
        ctx.noteAATrained = aa_data.noteTrained
        AAView.render(ctx)
    end,
})

return AAView
