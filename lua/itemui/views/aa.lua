--[[
    AA View - Alt Advancement pop-out window
    Part of CoOpt UI Items Companion. Tabs, search, sortable table, Train/Hotkey, Export/Import.
--]]

local mq = require('mq')
require('ImGui')
local config = require('itemui.config')

local AAView = {}

local TAB_NAMES = { "General", "Archetype", "Class", "Special" }
local AA_WINDOW_WIDTH = 640
local AA_WINDOW_HEIGHT = 520
local SEARCH_DEBOUNCE_MS = 180
local IMPORT_DELAY_MS = 250

-- Module-local state (search, debounce, selection, import state)
local searchText = ""
local searchTextApplied = ""
local searchDebounceAt = 0
local selectedAAName = nil
local canPurchaseOnly = false
local importInProgress = false
local importProgressCurrent = 0
local importProgressTotal = 0
-- Sort cache
local sortCache = { key = "", list = {} }

local function getFilteredList(ctx)
    local list = ctx.getAAList()
    if not list or #list == 0 then return {} end
    local tab = (ctx.sortState.aaTab and ctx.sortState.aaTab >= 1 and ctx.sortState.aaTab <= 4) and ctx.sortState.aaTab or 1
    local tabName = TAB_NAMES[tab]
    local filtered = {}
    for i = 1, #list do
        local aa = list[i]
        local cat = (aa.category or ""):lower()
        if tab == 1 then
            if cat == "" or cat == "general" or (cat ~= "archetype" and cat ~= "class" and cat ~= "special") then
                filtered[#filtered + 1] = aa
            end
        elseif (tab == 2 and cat == "archetype") or (tab == 3 and cat == "class") or (tab == 4 and cat == "special") then
            filtered[#filtered + 1] = aa
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
        local points = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
        local aaPoints = (points.aaPoints or 0)
        local out = {}
        for _, aa in ipairs(filtered) do
            if aa.canTrain and aaPoints >= (aa.cost or 0) then out[#out + 1] = aa end
        end
        filtered = out
    end
    return filtered
end

local function buildSortKey(ctx, filtered)
    local col = ctx.sortState.aaColumn or "Title"
    local dir = ctx.sortState.aaDirection or ImGuiSortDirection.Ascending
    local tab = ctx.sortState.aaTab or 1
    return string.format("%s|%d|%d|%s|%d", col, dir, tab, searchTextApplied or "", #filtered)
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
    return config.CONFIG_PATH or ""
end

-- Export: write INI to AA backup dir (or CONFIG_PATH) as aa_CharName_date.ini
local function doExport(ctx)
    local list = ctx.getAAList()
    if not list then return end
    local Me = mq.TLO and mq.TLO.Me
    if not Me or not Me.Name then return end
    local charName = (Me.Name() or "Unknown"):gsub("[^%w_%-]", "_")
    local class = (Me.Class and Me.Class()) and Me.Class() or "Unknown"
    local fname = "aa_" .. charName .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".ini"
    local dir = getAABackupDir(ctx)
    local path = (dir and dir ~= "") and (dir .. "/" .. fname) or config.getConfigFile(fname)
    if not path then ctx.setStatusMessage("Export failed: no config path"); return end
    local countSpent = 0
    local ok, err = pcall(function()
        local f = io.open(path, "w")
        if not f then error("could not open file") end
        f:write("[Meta]\n")
        f:write("Character=" .. (Me.Name() or "") .. "\n")
        f:write("Class=" .. tostring(class) .. "\n")
        f:write("Exported=" .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        for _, aa in ipairs(list) do
            if aa.rank and aa.rank > 0 and aa.name then countSpent = countSpent + 1 end
        end
        f:write("TotalAAs=" .. tostring(countSpent) .. "\n")
        f:write("[AAs]\n")
        for _, aa in ipairs(list) do
            if aa.rank and aa.rank > 0 and aa.name then
                f:write(aa.name .. "=" .. tostring(aa.rank) .. "\n")
            end
        end
        f:close()
    end)
    if ok then
        ctx.setStatusMessage("Exported to " .. fname)
    else
        ctx.setStatusMessage("Export failed: " .. tostring(err))
    end
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

-- Parse INI [AAs] section: name=rank
local function parseAABackup(path)
    local meta = {} local aas = {}
    local section = nil
    local ok, err = pcall(function()
        local f = io.open(path, "r")
        if not f then error("cannot open") end
        for line in f:lines() do
            line = line:match("^%s*(.-)%s*$")
            if line:match("^%[([^%]]+)%]") then
                section = line:match("^%[([^%]]+)%]")
            elseif section == "Meta" and line:find("=") then
                local k, v = line:match("^([^=]+)=(.*)$")
                if k and v then meta[k:match("^%s*(.-)%s*$")] = v:match("^%s*(.-)%s*$") end
            elseif section == "AAs" and line:find("=") then
                local name, rank = line:match("^([^=]+)=(.*)$")
                if name and rank then
                    name = name:match("^%s*(.-)%s*$")
                    rank = tonumber(rank:match("^%s*(.-)%s*$"))
                    if name ~= "" and rank and rank > 0 then aas[#aas + 1] = { name = name, rank = rank } end
                end
            end
        end
        f:close()
    end)
    return ok and aas or nil, meta
end

-- Import: apply backup (run in coroutine or step-by-step with mq.delay)
local function startImport(ctx, path)
    local aas, meta = parseAABackup(path)
    if not aas or #aas == 0 then ctx.setStatusMessage("No AAs in file"); return end
    importInProgress = true
    importProgressTotal = 0
    for _, entry in ipairs(aas) do
        importProgressTotal = importProgressTotal + (entry.rank or 0)
    end
    importProgressCurrent = 0
    -- We'll process one buy per frame in render to avoid blocking
    ctx._aaImportQueue = { path = path, aas = aas, meta = meta, idx = 1, subRank = 0, targetRank = 0 }
end

local function stepImport(ctx)
    local q = ctx._aaImportQueue
    if not q or not importInProgress then return end
    local aas, idx, subRank, targetRank = q.aas, q.idx, q.subRank, q.targetRank
    if idx > #aas then
        ctx._aaImportQueue = nil
        importInProgress = false
        ctx.refreshAA()
        ctx.setStatusMessage("Import complete")
        return
    end
    local entry = aas[idx]
    local name, rank = entry.name, entry.rank or 0
    if targetRank == 0 then
        targetRank = rank
        local Me = mq.TLO and mq.TLO.Me
        local aa = Me and Me.AltAbility and Me.AltAbility(name)
        local current = (aa and aa.Rank and aa.Rank()) or 0
        subRank = current
        q.targetRank = targetRank
        q.subRank = subRank
    end
    if subRank >= targetRank then
        q.idx = q.idx + 1
        q.subRank = 0
        q.targetRank = 0
        return
    end
    local Me = mq.TLO and mq.TLO.Me
    local aa = Me and Me.AltAbility and Me.AltAbility(name)
    if not aa or not aa.NextIndex then q.idx = q.idx + 1; q.subRank = 0; q.targetRank = 0; return end
    local nextIdx = aa.NextIndex()
    if nextIdx and nextIdx > 0 then
        mq.cmd("/alt buy " .. tostring(nextIdx))
        importProgressCurrent = importProgressCurrent + 1
        q.subRank = (q.subRank or 0) + 1
    else
        q.idx = q.idx + 1
        q.subRank = 0
        q.targetRank = 0
    end
end

function AAView.render(ctx)
    if not ctx.uiState.aaWindowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig
    local ax = layoutConfig.AAWindowX or 0
    local ay = layoutConfig.AAWindowY or 0
    if ax and ay and (ax ~= 0 or ay ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), ImGuiCond.FirstUseEver)
    end
    local w = layoutConfig.WidthAAPanel or AA_WINDOW_WIDTH
    local h = layoutConfig.HeightAA or AA_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        ImGui.SetNextWindowSize(ImVec2(w, h), ImGuiCond.FirstUseEver)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI AAs Companion (Work in Progress)##ItemUIAA", ctx.uiState.aaWindowOpen, windowFlags)
    ctx.uiState.aaWindowOpen = winOpen
    ctx.uiState.aaWindowShouldDraw = winOpen

    if not winOpen then ImGui.End(); return end
    -- Escape closes this window via main Inventory Companion's LIFO handler only
    if not winVis then ImGui.End(); return end

    -- Enter = Train selected (if trainable)
    if ImGui.IsKeyPressed(ImGuiKey.Enter) and selectedAAName then
        local list = ctx.getAAList()
        local pointsSummary = (ctx.getAAPointsSummary and ctx.getAAPointsSummary()) or {}
        local aaPoints = pointsSummary.aaPoints or 0
        for _, aa in ipairs(list or {}) do
            if aa.name == selectedAAName and aa.canTrain and aaPoints >= (aa.cost or 0) and aa.nextIndex and aa.nextIndex > 0 then
                mq.cmd("/alt buy " .. tostring(aa.nextIndex))
                ctx.refreshAA()
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
            ctx.flushLayoutSave()
        end
    end

    -- Process import queue one step per frame
    if ctx._aaImportQueue and importInProgress then
        stepImport(ctx)
    end

    -- Refresh on open if needed
    if ctx.shouldRefreshAA and ctx.shouldRefreshAA() then
        ctx.refreshAA()
    end

    -- Debounce search
    local now = mq.gettime()
    if now - searchDebounceAt >= SEARCH_DEBOUNCE_MS then
        searchTextApplied = searchText
        searchDebounceAt = now
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
    ImGui.SameLine()
    ctx.renderRefreshButton(ctx, "Refresh##AA", "Rescan AA list", function() ctx.refreshAA() end, { messageAfter = "AA list refreshed" })
    ImGui.SameLine()
    ctx.theme.TextMuted(ctx.getAALastRefreshTime and ("Last: " .. os.date("%H:%M:%S", (ctx.getAALastRefreshTime() or 0) / 1000)) or "")
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
            local w = (name == "Cur/Max") and 60 or (name == "Cost") and 45 or (name == "Category") and 120 or 0
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
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(aa.name or "")
                    if aa.description and aa.description ~= "" then ImGui.TextWrapped(aa.description) end
                    local ok, reqName = pcall(function()
                        if aa.requiresAbility and aa.requiresAbility.Name then return aa.requiresAbility.Name() end
                        return nil
                    end)
                    if ok and reqName and reqName ~= "" then ImGui.Text("Requires: " .. tostring(reqName)) end
                    ImGui.EndTooltip()
                end
                if ImGui.IsMouseDoubleClicked(ImGuiMouseButton.Left) and isSelected and aa.canTrain and aaPoints >= (aa.cost or 0) then
                    if aa.nextIndex and aa.nextIndex > 0 then
                        mq.cmd("/alt buy " .. tostring(aa.nextIndex))
                        ctx.refreshAA()
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
                ctx.refreshAA()
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
    if ImGui.Button("Export", ImVec2(80, 0)) then doExport(ctx) end
    ImGui.SameLine()
    if ImGui.Button("Import", ImVec2(80, 0)) and not importInProgress then
        local files = listBackupFiles(ctx)
        if #files == 0 then ctx.setStatusMessage("No aa_*.ini backups in config folder") end
        -- Simple: use first file or show list; for v1 we use a combo
        if #files > 0 then
            ctx._aaImportFileCombo = ctx._aaImportFileCombo or 1
            ctx._aaImportFiles = files
        end
    end
    if ctx._aaImportFiles and #ctx._aaImportFiles > 0 and not importInProgress then
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
            if path then startImport(ctx, path) end
        end
    end
    if importInProgress then
        ctx.theme.TextWarning(string.format("Training %d / %d...", importProgressCurrent, importProgressTotal))
    end
    local backupDir = getAABackupDir(ctx)
    if backupDir and backupDir ~= "" then
        ctx.theme.TextMuted("Folder: " .. (backupDir:len() > 28 and ("..." .. backupDir:sub(-25)) or backupDir))
    else
        ctx.theme.TextMuted("Folder: (default)")
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Export/Import location. Set AABackupPath in itemui_layout.ini [Layout] to use a custom folder.")
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
        ctx.uiState.aaWindowOpen = false
        ctx.uiState.aaWindowShouldDraw = false
    end

    ImGui.End()
end

return AAView
