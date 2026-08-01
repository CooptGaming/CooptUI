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

-- Module-local state (search, debounce, selection)
local searchText = ""
local searchTextApplied = ""
local searchDebounceAt = 0
local selectedAAName = nil
local canPurchaseOnly = false
-- Sort cache
local sortCache = { key = "", list = {} }
-- Filter cache: the tab/search/can-purchase pass over ~2k records used to
-- re-run (and re-allocate) every frame; only the SORT was cached.
local filterCache = { key = "", list = {} }

local function getFilteredList(ctx)
    local list = ctx.getAAList()
    if not list or #list == 0 then return {} end
    local tab = (ctx.sortState.aaTab and ctx.sortState.aaTab >= 1 and ctx.sortState.aaTab <= 4) and ctx.sortState.aaTab or 1
    local ptsKey = 0
    if canPurchaseOnly then
        local points = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
        ptsKey = points.aaPoints or 0
    end
    local rt = (ctx.uiState and ctx.uiState.aaDataRefreshedAt) or 0
    local cacheKey = string.format("%d|%s|%s|%d|%d|%s", tab, searchTextApplied or "",
        canPurchaseOnly and "1" or "0", #list, ptsKey, tostring(rt))
    if filterCache.key == cacheKey then return filterCache.list end
    local tabName = TAB_NAMES[tab]
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
    -- Search filter
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
    -- Can Purchase filter
    if canPurchaseOnly then
        local out = {}
        for _, aa in ipairs(filtered) do
            if aa.canTrain and ptsKey >= (aa.cost or 0) then out[#out + 1] = aa end
        end
        filtered = out
    end
    filterCache.key = cacheKey
    filterCache.list = filtered
    return filtered
end

local function buildSortKey(ctx, filtered)
    local col = ctx.sortState.aaColumn or "Title"
    local dir = ctx.sortState.aaDirection or ImGuiSortDirection.Ascending
    local tab = ctx.sortState.aaTab or 1
    local cp = canPurchaseOnly and "1" or "0"
    -- aaDataRefreshedAt: bumped by the main loop when a deferred AA rebuild completes,
    -- so freshly rebuilt rows always miss the cache.
    local rt = (ctx.uiState and ctx.uiState.aaDataRefreshedAt) or 0
    return string.format("%s|%d|%d|%s|%d|%s|%s", col, dir, tab, searchTextApplied or "", #filtered, cp, tostring(rt))
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
            if aa.name == selectedAAName and aa.canTrain and aaPoints >= (aa.cost or 0) and aa.nextIndex and aa.nextIndex > 0 then
                mq.cmd("/alt buy " .. tostring(aa.nextIndex))
                ctx.uiState.aaRefreshRequested = true  -- rebuild runs in the main loop, not this frame
                sortCache.key = ""
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
            statText = statText .. " . scanning AA tables"
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

    -- Search
    ImGui.Text("Search:")
    ImGui.SameLine()
    ImGui.SetNextItemWidth(200)
    local changed
    searchText, changed = ImGui.InputText("##AASearch", searchText or "")
    if changed then searchDebounceAt = mq.gettime() end
    ImGui.SameLine()
    if ImGui.Button("X##AAClearSearch", ImVec2(22, 0)) then searchText = ""; searchTextApplied = ""; sortCache.key = "" end
    if not barsOn then
        -- In bars the band above owns Refresh -- two buttons doing the identical thing on
        -- one window is the redundancy the §9 pass deletes.
        ImGui.SameLine()
        ctx.renderRefreshButton(ctx, "Refresh##AA", "Rescan AA list", function() ctx.refreshAA() end, { messageAfter = "AA list refreshed" })
    end
    ImGui.SameLine()
    if ctx.isAABuilding and ctx.isAABuilding() then
        ctx.theme.TextWarning("Scanning AA tables...")
    else
        ctx.theme.TextMuted(ctx.getAALastRefreshTime and ("Last: " .. os.date("%H:%M:%S", (ctx.getAALastRefreshTime() or 0) / 1000)) or "")
    end
    ImGui.Spacing()

    local filtered = getFilteredList(ctx)
    local sorted = getSortedList(ctx, filtered)
    local pointsSummary = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
    local aaPoints = pointsSummary.aaPoints or 0

    -- Two columns: left = table, right = panel
    ImGui.BeginChild("AALeft", ImVec2(-220, -80), true)
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
                if ImGui.Selectable((aa.name or ""), isSelected, ImGuiSelectableFlags.SpanAllColumns, ImVec2(0, 0)) then
                    selectedAAName = aa.name
                end
                -- Capture hover state of the row Selectable now: tooltip items below change "last item"
                local rowHovered = ImGui.IsItemHovered()
                if rowHovered then
                    ImGui.BeginTooltip()
                    ImGui.Text(aa.name or "")
                    if aa.description and aa.description ~= "" then ImGui.TextWrapped(aa.description) end
                    -- requiresAbilityName is resolved by the scan (gid -> name);
                    -- the raw requiresAbility field is a group-id STRING, so
                    -- .Name on it indexed the string library and always hid this line.
                    local reqName = aa.requiresAbilityName
                    if reqName and reqName ~= "" then
                        ImGui.Text(string.format("Requires: %s (rank %d)", reqName, tonumber(aa.requiresAbilityPoints) or 1))
                    end
                    ImGui.EndTooltip()
                end
                if rowHovered and ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) and isSelected and aa.canTrain and aaPoints >= (aa.cost or 0) then
                    if aa.nextIndex and aa.nextIndex > 0 then
                        mq.cmd("/alt buy " .. tostring(aa.nextIndex))
                        ctx.uiState.aaRefreshRequested = true  -- rebuild runs in the main loop, not this frame
                        sortCache.key = ""
                    end
                end
                ImGui.TableNextColumn()
                ImGui.Text(string.format("%d/%d", aa.rank or 0, aa.maxRank or 0))
                ImGui.TableNextColumn()
                ImGui.Text((aa.maxRank and aa.maxRank > 0 and aa.rank and aa.rank >= aa.maxRank) and "Max" or tostring(aa.cost or 0))
                ImGui.TableNextColumn()
                ImGui.Text(aa.category or "")
                ::continue::
            end
        end
        ImGui.EndTable()
    end
    ImGui.EndChild()

    ImGui.SameLine()
    ImGui.BeginChild("AARight", ImVec2(0, -80), true)
    -- Exp to AA
    local pctExp = pointsSummary.pctAAExp or 0
    ImGui.Text("Exp to AA:")
    ImGui.SameLine()
    ctx.theme.TextInfo(string.format("%.1f%%", pctExp))
    ImGui.ProgressBar((pctExp or 0) / 100.0, ImVec2(-1, 0))
    -- Points
    ImGui.Spacing()
    ImGui.Text("AA Points:")
    ImGui.SameLine()
    ImGui.Text(tostring(pointsSummary.aaPoints or 0))
    ImGui.Text("Assigned:")
    ImGui.SameLine()
    ImGui.Text(tostring(pointsSummary.assigned or 0))
    ImGui.Text("Total Spent:")
    ImGui.SameLine()
    ImGui.Text(tostring(pointsSummary.totalSpent or 0))
    ImGui.Spacing()
    -- Train
    local sel = selectedAAName
    local canTrainSel = false
    local selCost = 0
    if sel then
        for _, aa in ipairs(sorted) do
            if aa.name == sel then
                canTrainSel = aa.canTrain and (aaPoints >= (aa.cost or 0))
                selCost = aa.cost or 0
                break
            end
        end
    end
    if ctx.theme.PushKeepButton then ctx.theme.PushKeepButton(not (canTrainSel and sel)) end
    if ImGui.Button("Train", ImVec2(80, 0)) and canTrainSel and sel then
        for _, aa in ipairs(ctx.getAAList()) do
            if aa.name == sel and aa.nextIndex and aa.nextIndex > 0 then
                mq.cmd("/alt buy " .. tostring(aa.nextIndex))
                ctx.uiState.aaRefreshRequested = true  -- rebuild runs in the main loop, not this frame
                sortCache.key = ""

                break
            end
        end
    end
    if ctx.theme.PopButtonColors then ctx.theme.PopButtonColors() end
    ImGui.SameLine()
    if ImGui.Button("Hotkey", ImVec2(80, 0)) and sel then
        -- Use /aa act for activatable AAs (macro/keybind); no programmatic hotkey creation in MQ
        mq.cmd('/aa act "' .. (sel or ""):gsub('"', '\\"') .. '"')
        ctx.setStatusMessage('Use /aa act "' .. (sel or "") .. '" in a macro or keybind')
    end
    if ImGui.IsItemHovered() and sel then
        ImGui.BeginTooltip()
        ImGui.Text("Create hotkey for selected AA")
        ImGui.Text('Uses: /aa act "AbilityName" in macro or keybind')
        ImGui.EndTooltip()
    end
    ImGui.Spacing()
    local transferBusy = aa_transfer.isBusy()
    if ImGui.Button("Export", ImVec2(80, 0)) and not transferBusy then
        aa_transfer.requestExport()
    end
    ImGui.SameLine()
    if ImGui.Button("Import", ImVec2(80, 0)) and not transferBusy then
        local files = listBackupFiles(ctx)
        if #files == 0 then ctx.setStatusMessage("No aa_*.ini backups in Macros\aa_backups (or your AABackupPath folder)") end
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

    -- Bottom bar
    ImGui.Spacing()
    ctx.theme.TextMuted("Click an ability for more info. Train to spend points. Hotkey to assign.")
    ImGui.SameLine()
    local cpChanged
    canPurchaseOnly, cpChanged = ImGui.Checkbox("Can Purchase", canPurchaseOnly)
    if cpChanged then sortCache.key = "" end
    ImGui.SameLine()
    if ImGui.Button("Reset", ImVec2(60, 0)) then
        canPurchaseOnly = false
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
        AAView.render(ctx)
    end,
})

return AAView
