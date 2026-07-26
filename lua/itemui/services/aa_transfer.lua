--[[
    AA Transfer - export purchased AAs to a file; re-buy them after a reset.

    Driven from the main loop (tick), so it works with every CoOpt window
    closed - the native AA window's CoOpt Export/Import buttons (coopt skin)
    and the CoOpt AA Browser's buttons both route here.

    Export: waits for a fresh AA scan, then writes aa_<Char>_<date>.ini
    ([Meta] + [AAs] name=rank) to the backup dir (Settings) or CONFIG_PATH.

    Import: parses the file, plans only the missing ranks, and GATES on AA
    points first - with the plugin, per-rank costs come from the AA table
    (getGroupRankCosts), so "not enough points" aborts before anything is
    bought. Buys are VERIFIED: /alt buy, then poll the rank until it moves
    (2s timeout, one retry) before the next buy - no more fire-and-forget.
    Failures are collected and summarized instead of silently skipped.

    The native Import button arms first (armOrStartImport): first click
    reports what would be imported, a second click within 10s starts it.
--]]

local mq = require('mq')
local config = require('itemui.config')
local coopuiPlugin = require('itemui.utils.coopui_plugin')

local M = {}

local deps = {}            -- { setStatusMessage, layoutConfig, refreshAA, getAAList, isAABuilding }

local BUY_TIMEOUT_MS = 2000
local BUY_PACE_MS = 150
local ARM_WINDOW_MS = 10000

local exportPending = false
local imp = nil            -- active import state
local armed = nil          -- { path, until, ranks, cost, exact }
local statusLine = "CoOpt: Export saves your AAs"
-- File button selection (native window): newest-first backup list.
local fileList = nil       -- { { path=, name= }, ... }
local fileIdx = 1
local fileShown = false

local paCache
local function plugAA()
    if paCache ~= nil then return paCache or nil end
    local p = coopuiPlugin.getPlugin()
    paCache = (p and type(p.aa) == 'table') and p.aa or false
    return paCache or nil
end

local function say(msg)
    statusLine = msg
    if deps.setStatusMessage then deps.setStatusMessage(msg) end
end

local function charName()
    local me = mq.TLO and mq.TLO.Me
    local n = me and me.Name and me.Name()
    if not n or n == "" then return nil end
    return n
end

local function safeCharName()
    local n = charName()
    return n and n:gsub("[^%w_%-]", "_") or nil
end

local dirEnsured = false
local migratedLegacy = false

local function ensureDir(d)
    if dirEnsured or not d or d == "" then return end
    dirEnsured = true
    pcall(function() os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end)
end

-- One-time move of aa_*.ini out of the legacy default (Macros\sell_config -
-- a leftover from the sell-manager era) into the AA backup folder. Runs only
-- for the default location; a rename collision just keeps the old copy.
local function migrateLegacyFiles(dstDir)
    if migratedLegacy then return end
    migratedLegacy = true
    local legacy = config.CONFIG_PATH
    if not legacy or legacy == "" or not dstDir or dstDir == "" or legacy == dstDir then return end
    local moved = 0
    local ok, pipe = pcall(io.popen, 'dir /b "' .. legacy:gsub("/", "\\") .. '\\aa_*.ini" 2>nul')
    if ok and pipe then
        for line in pipe:lines() do
            if line and line:match("^aa_.*%.ini$") then
                if os.rename(legacy .. "/" .. line, dstDir .. "/" .. line) then moved = moved + 1 end
            end
        end
        pipe:close()
    end
    if moved > 0 then say(string.format("Moved %d AA export(s) to Macros\\aa_backups", moved)) end
end

--- The AA export folder: custom AABackupPath when set, else Macros\aa_backups
--- (created on demand; legacy files in sell_config migrate over once).
function M.getBackupDir()
    local lc = deps.layoutConfig
    local p = lc and lc.AABackupPath or ""
    if p and p ~= "" then return p end
    local d = config.AA_BACKUP_PATH or ""
    if d ~= "" then
        ensureDir(d)
        migrateLegacyFiles(d)
        return d
    end
    return config.CONFIG_PATH or ""
end

local function backupDir()
    return M.getBackupDir()
end

local function myAA(name)
    local me = mq.TLO and mq.TLO.Me
    return me and me.AltAbility and me.AltAbility(name) or nil
end

local function myRank(name)
    local aa = myAA(name)
    local ok, r = pcall(function() return aa and aa.Rank and aa.Rank() end)
    return (ok and tonumber(r)) or 0
end

local function myPoints()
    local me = mq.TLO and mq.TLO.Me
    local ok, p = pcall(function() return me and me.AAPoints and me.AAPoints() end)
    return (ok and tonumber(p)) or 0
end

-- EQ class name -> 3-letter tag (title case). Unknown names fall back to
-- their first three letters so server-custom classes still tag something.
local CLASS_TAGS = {
    ["Warrior"] = "War", ["Cleric"] = "Clr", ["Paladin"] = "Pal", ["Ranger"] = "Rng",
    ["Shadow Knight"] = "Shd", ["Shadowknight"] = "Shd", ["Druid"] = "Dru", ["Monk"] = "Mnk",
    ["Bard"] = "Brd", ["Rogue"] = "Rog", ["Shaman"] = "Shm", ["Necromancer"] = "Nec",
    ["Wizard"] = "Wiz", ["Magician"] = "Mag", ["Enchanter"] = "Enc", ["Beastlord"] = "Bst",
    ["Berserker"] = "Ber",
}

local function classTag(name)
    if not name or name == "" then return nil end
    local t = CLASS_TAGS[name]
    if t then return t end
    local s = name:gsub("%s", ""):sub(1, 3)
    if s == "" then return nil end
    return s:sub(1, 1):upper() .. s:sub(2):lower()
end

-- Base class + rebirth classes found in the AA list ("Rebirth <Class>" with
-- rank > 0 = an active class on Perky), e.g. Warrior + Berserker/Wizard
-- rebirths -> "WarBerWiz". Base first, rebirths sorted for stable names.
local function classTagString(list, baseClassName)
    local base = classTag(baseClassName)
    local seen, rebirth = {}, {}
    for _, aa in ipairs(list or {}) do
        if aa.rank and aa.rank > 0 and aa.name then
            local cls = aa.name:match("^Rebirth%s+(.+)$")
            local t = cls and classTag(cls) or nil
            if t and t ~= base and not seen[t] then
                seen[t] = true
                rebirth[#rebirth + 1] = t
            end
        end
    end
    table.sort(rebirth)
    local s = (base or "") .. table.concat(rebirth, "")
    return s ~= "" and s or "Unk"
end

--- Export -----------------------------------------------------------------

--- Start an export: refreshes the AA scan first so ranks are current
--- (tick writes the file when the rebuild completes).
function M.requestExport()
    if imp then say("Import running - wait for it to finish") return false end
    if exportPending then return true end
    exportPending = true
    if deps.refreshAA then deps.refreshAA() end
    say("Scanning AAs for export...")
    return true
end

local function doExportNow()
    local list = (deps.getAAList and deps.getAAList()) or {}
    local me = mq.TLO and mq.TLO.Me
    local cname = charName()
    if not cname then say("Export failed: no character") return end
    local class = (me.Class and me.Class()) and tostring(me.Class()) or "Unknown"
    local tagStr = classTagString(list, class)
    local fname = "aa_" .. safeCharName() .. "_" .. tagStr .. "_" .. os.date("%Y%m%d_%H%M%S") .. ".ini"
    local dir = backupDir()
    local path = (dir ~= "") and (dir .. "/" .. fname) or config.getConfigFile(fname)
    if not path then say("Export failed: no config path") return end
    local count = 0
    local ok, err = pcall(function()
        local f = io.open(path, "w")
        if not f then error("could not open file") end
        f:write("[Meta]\n")
        f:write("Character=" .. cname .. "\n")
        f:write("Class=" .. class .. "\n")
        f:write("Classes=" .. tagStr .. "\n")
        f:write("Exported=" .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
        for _, aa in ipairs(list) do
            if aa.rank and aa.rank > 0 and aa.name then count = count + 1 end
        end
        f:write("TotalAAs=" .. tostring(count) .. "\n")
        f:write("[AAs]\n")
        for _, aa in ipairs(list) do
            if aa.rank and aa.rank > 0 and aa.name then
                f:write(aa.name .. "=" .. tostring(aa.rank) .. "\n")
            end
        end
        -- Group ids as an import-resolution fallback (names are primary;
        -- ids survive if a name lookup ever fails against a fresh scan).
        f:write("[AAIds]\n")
        for _, aa in ipairs(list) do
            if aa.rank and aa.rank > 0 and aa.name and aa.id then
                f:write(aa.name .. "=" .. tostring(aa.id) .. "\n")
            end
        end
        f:close()
    end)
    if ok then
        fileList = nil
        fileShown = false
        say(string.format("Exported %d AAs -> %s", count, fname))
    else
        say("Export failed: " .. tostring(err))
    end
end

--- Parse / files ----------------------------------------------------------

--- Parse an aa_*.ini backup. Returns entries array, meta table (or nil, err).
--- Newer exports carry an optional [AAIds] section (name=groupId); when
--- present the ids are attached to the entries as a resolution fallback.
function M.parseBackup(path)
    local meta, aas, ids = {}, {}, {}
    local section = nil
    local ok, err = pcall(function()
        local f = io.open(path, "r")
        if not f then error("cannot open " .. tostring(path)) end
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
            elseif section == "AAIds" and line:find("=") then
                local name, id = line:match("^([^=]+)=(.*)$")
                if name and id then
                    name = name:match("^%s*(.-)%s*$")
                    id = tonumber(id:match("^%s*(.-)%s*$"))
                    if name ~= "" and id then ids[name] = id end
                end
            end
        end
        f:close()
    end)
    if not ok then return nil, err end
    for _, e in ipairs(aas) do e.id = ids[e.name] end
    return aas, meta
end

--- name -> groupId for every AA the browser scan knows (ownership-
--- INDEPENDENT - this is the global table, so it resolves post-reset when
--- Me.AltAbility(name) can't: that TLO only finds abilities you own).
local function buildNameIdMap()
    local map = {}
    for _, r in ipairs((deps.getAAList and deps.getAAList()) or {}) do
        if r.name and r.id then map[r.name] = r.id end
    end
    return map
end

--- Rebuild the newest-first backup list for this character. Sort by the
--- trailing timestamp, not the whole name - filenames carry the class tag
--- (aa_Char_WarBerWiz_date.ini), and after a class swap the tag changes,
--- which would break plain lexicographic "newest first".
local function refreshFileList()
    fileList = {}
    local cn = safeCharName()
    local dir = backupDir()
    if not cn or dir == "" then return end
    local names = {}
    local ok, pipe = pcall(io.popen, 'dir /b "' .. dir:gsub("/", "\\") .. '\\aa_' .. cn .. '_*.ini" 2>nul')
    if ok and pipe then
        for line in pipe:lines() do
            if line and line:match("^aa_.*%.ini$") then names[#names + 1] = line end
        end
        pipe:close()
    end
    local function stamp(n) return n:match("_(%d+_%d+)%.ini$") or n end
    table.sort(names, function(a, b) return stamp(a) > stamp(b) end)
    for _, n in ipairs(names) do
        fileList[#fileList + 1] = { path = dir .. "/" .. n, name = n }
    end
end

--- Newest aa_<ThisChar>_*.ini in the backup dir.
function M.findLatestBackup()
    refreshFileList()
    local f = fileList[1]
    if not f then return nil end
    return f.path, f.name
end

--- File button: first click shows the newest file, further clicks cycle
--- toward older ones (wrapping). Changing the file disarms a pending import.
function M.cycleFile()
    if imp then say("Import already running") return end
    if not fileShown or not fileList or #fileList == 0 then
        refreshFileList()
        fileIdx = 1
        fileShown = #fileList > 0
    else
        fileIdx = (fileIdx % #fileList) + 1
    end
    armed = nil
    if not fileList or #fileList == 0 then
        fileShown = false
        say("No aa_*.ini exports for this character")
        return
    end
    say(string.format("File %d/%d: %s", fileIdx, #fileList, fileList[fileIdx].name))
end

--- Import -----------------------------------------------------------------

--- Plan an import: entries needing ranks, total ranks, and the AA-point cost
--- (exact when the plugin cost map is available). Pure - buys nothing.
local function planImport(aas, nameIds)
    local plan = { queue = {}, ranks = 0, cost = 0, exact = false, skippedAuto = 0 }
    nameIds = nameIds or {}
    local costs = nil
    local pa = plugAA()
    if pa and type(pa.getGroupRankCosts) == 'function' then
        local ok, map = pcall(pa.getGroupRankCosts)
        if ok and type(map) == 'table' then costs = map end
    end
    plan.exact = costs ~= nil
    for _, entry in ipairs(aas) do
        -- Perky: "Rebirth <Class>" AAs are server-granted markers of your
        -- chosen classes, never bought - buying would only burn timeouts.
        -- They stay in exports as documentation of the spec.
        if entry.name:match("^Rebirth ") then
            plan.skippedAuto = plan.skippedAuto + 1
        else
            local cur = myRank(entry.name)
            if entry.rank > cur then
                -- Group id: current scan first, the export's own [AAIds] as
                -- fallback. Never the character-side TLO - post-reset it
                -- resolves nothing.
                local gid = nameIds[entry.name] or entry.id
                plan.queue[#plan.queue + 1] = { name = entry.name, target = entry.rank, startRank = cur, gid = gid }
                plan.ranks = plan.ranks + (entry.rank - cur)
                local groupCosts = (costs and gid) and costs[gid] or nil
                if groupCosts then
                    for r = cur + 1, entry.rank do
                        local c = tonumber(groupCosts[r])
                        if c then plan.cost = plan.cost + c else plan.exact = false end
                    end
                else
                    plan.exact = false
                end
            end
        end
    end
    return plan
end

--- Start importing from a backup file. Gates on AA points when the cost is
--- known exactly; refuses to start when nothing is missing. force = true
--- (the native arm flow's confirmed click) allows a partial import when
--- points fall short - safe because the plan only ever buys missing ranks,
--- so re-importing later resumes where it stopped.
function M.startImport(path, force)
    if imp then say("Import already running") return false end
    if exportPending then say("Export running - wait for it") return false end
    -- The global AA scan is the resolver for unowned names; without it the
    -- whole import would misreport. Kick a scan and ask for a re-click.
    local nameIds = buildNameIdMap()
    if next(nameIds) == nil then
        if deps.refreshAA then deps.refreshAA() end
        say("Scanning AA tables - click Import again in a moment")
        return false
    end
    local aas, err = M.parseBackup(path)
    if not aas then say("Import failed: " .. tostring(err)) return false end
    if #aas == 0 then say("No AAs in file") return false end
    local plan = planImport(aas, nameIds)
    if plan.ranks == 0 then say("Nothing to import - all exported AAs already trained") return false end
    local have = myPoints()
    if plan.exact and plan.cost > have and not force then
        say(string.format("Need %d AA pts for %d ranks - you have %d. Import aborted.", plan.cost, plan.ranks, have))
        return false
    end
    if not plan.exact then
        say(string.format("Importing %d ranks (point check unavailable)...", plan.ranks))
    else
        say(string.format("Importing %d ranks (%d pts, %d available)...", plan.ranks, plan.cost, have))
    end
    imp = {
        queue = plan.queue, idx = 1, phase = "begin",
        expectRank = 0, buyAt = 0, retries = 0, nextActionAt = 0,
        totalRanks = plan.ranks, doneRanks = 0, failed = {},
        pass = 1, skippedAuto = plan.skippedAuto or 0,
    }
    return true
end

--- Buy id for one missing rank. Owned AAs: the character-side NextIndex
--- (id of the next rank's entry). Unowned (post-reset): Me.AltAbility can't
--- see them, so resolve the group through the GLOBAL table - its first
--- entry is rank 1 and its Index is the same id currency /alt buy takes
--- (NextIndex is literally NextGroupAbilityId).
local function resolveBuyId(entry)
    local aa = myAA(entry.name)
    if aa and aa() ~= nil then
        local okN, nextIdx = pcall(function() return aa.NextIndex and aa.NextIndex() end)
        nextIdx = okN and tonumber(nextIdx) or nil
        if nextIdx and nextIdx > 0 then return nextIdx end
        return nil, "no trainable next rank (auto-granted?)"
    end
    if not entry.gid then return nil, "name not in AA tables" end
    local okI, idx = pcall(function()
        local ga = mq.TLO.AltAbility and mq.TLO.AltAbility(entry.gid)
        return ga and ga.Index and ga.Index()
    end)
    idx = okI and tonumber(idx) or nil
    if idx and idx > 0 then return idx end
    return nil, "group id not in AA tables"
end

--- Native-button flow: first click reports what WOULD happen, second click
--- within the window actually starts (a full re-buy from one click is too
--- easy to fat-finger on a native window with no dialog). Uses the File
--- button's selection when one was made, the newest export otherwise.
function M.armOrStartImport()
    if imp then say("Import already running") return end
    local now = mq.gettime()
    if armed and now < armed.armedUntil then
        local path = armed.path
        local force = armed.partial == true
        armed = nil
        M.startImport(path, force)
        return
    end
    armed = nil
    local path, fname
    if fileShown and fileList and fileList[fileIdx] then
        path, fname = fileList[fileIdx].path, fileList[fileIdx].name
    else
        path, fname = M.findLatestBackup()
    end
    if not path then say("No aa_*.ini export found for this character") return end
    local nameIds = buildNameIdMap()
    if next(nameIds) == nil then
        if deps.refreshAA then deps.refreshAA() end
        say("Scanning AA tables - click Import again in a moment")
        return
    end
    local aas, err = M.parseBackup(path)
    if not aas then say("Import failed: " .. tostring(err)) return end
    local plan = planImport(aas, nameIds)
    if plan.ranks == 0 then say("Nothing missing vs " .. fname) return end
    local have = myPoints()
    if plan.exact and plan.cost > have then
        -- Not enough points: arm a PARTIAL import instead of dead-ending -
        -- the plan only buys missing ranks, so a later re-import resumes.
        armed = { path = path, armedUntil = now + ARM_WINDOW_MS, partial = true }
        say(string.format("Need %d pts, have %d. Import again for a PARTIAL import.", plan.cost, have))
        return
    end
    armed = { path = path, armedUntil = now + ARM_WINDOW_MS }
    if plan.exact then
        say(string.format("%s: %d ranks, %d pts. Import again to start.", fname, plan.ranks, plan.cost))
    else
        say(string.format("%s: %d ranks. Import again to start.", fname, plan.ranks))
    end
end

-- Full detail per non-trained entry -> aa_import_report.txt in the backup
-- dir, so a bad run is diagnosable instead of a mystery count.
local function writeImportReport()
    local dir = backupDir()
    if not dir or dir == "" then return nil end
    local path = dir .. "/aa_import_report.txt"
    local ok = pcall(function()
        local f = io.open(path, "w")
        if not f then error("open failed") end
        f:write(string.format("CoOpt AA import report - %s - %s\n", charName() or "?", os.date("%Y-%m-%d %H:%M:%S")))
        f:write(string.format("Trained %d/%d ranks. %d entries not trained:\n\n",
            imp.doneRanks, imp.totalRanks, #imp.failed))
        for _, fl in ipairs(imp.failed) do
            f:write(string.format("%s  (wanted rank %d, had %s)  - %s\n",
                fl.name, fl.wanted or 0, tostring(fl.had or "?"), fl.reason or "unknown"))
        end
        f:close()
    end)
    return ok and "aa_import_report.txt" or nil
end

local function finishImport()
    -- One extra sweep over TIMEOUT failures only: simple RequiresAbility
    -- chains resolve once prerequisites bought later in pass 1 exist.
    -- Unresolvable/unbuyable entries would just fail identically again.
    if imp.pass == 1 then
        local retryQueue = {}
        for _, f in ipairs(imp.failed) do
            if f.reason == "buy timed out (rank never moved)" then
                retryQueue[#retryQueue + 1] = { name = f.name, target = f.wanted }
            end
        end
        if #retryQueue > 0 then
            local keep = {}
            for _, f in ipairs(imp.failed) do
                if f.reason ~= "buy timed out (rank never moved)" then keep[#keep + 1] = f end
            end
            imp.queue = retryQueue
            imp.failed = keep
            imp.idx = 1
            imp.phase = "begin"
            imp.retries = 0
            imp.pass = 2
            say(string.format("Retrying %d failed...", #retryQueue))
            return
        end
    end
    local nFailed = #imp.failed
    local msg
    if nFailed == 0 then
        msg = string.format("Import complete: %d ranks trained", imp.doneRanks)
    else
        local report = writeImportReport()
        local names = {}
        for i = 1, math.min(2, nFailed) do names[#names + 1] = imp.failed[i].name end
        msg = string.format("Import: %d trained, %d not trained (%s%s)%s", imp.doneRanks, nFailed,
            table.concat(names, ", "), nFailed > 2 and ", ..." or "",
            report and (" - see " .. report) or "")
    end
    if (imp.skippedAuto or 0) > 0 then
        msg = msg .. string.format(" [%d auto-granted skipped]", imp.skippedAuto)
    end
    imp = nil
    fileList = nil
    fileShown = false
    if deps.refreshAA then deps.refreshAA() end
    say(msg)
end

local function tickImport(now)
    if now < (imp.nextActionAt or 0) then return end
    local entry = imp.queue[imp.idx]
    if not entry then finishImport() return end

    if imp.phase == "begin" then
        local cur = myRank(entry.name)
        if cur >= entry.target then
            imp.idx = imp.idx + 1
            imp.retries = 0
            return
        end
        if myPoints() <= 0 then
            -- Out of points: drain the rest fast with a clear reason instead
            -- of burning two 2s timeouts per remaining entry.
            imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, reason = "out of AA points" }
            imp.idx = imp.idx + 1
            imp.retries = 0
            return
        end
        local buyId, why = resolveBuyId(entry)
        if not buyId then
            imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, reason = why or "unresolvable" }
            imp.idx = imp.idx + 1
            imp.retries = 0
            return
        end
        mq.cmd("/alt buy " .. tostring(buyId))
        imp.expectRank = cur + 1
        imp.buyAt = now
        imp.phase = "verify"
    elseif imp.phase == "verify" then
        local cur = myRank(entry.name)
        if cur >= imp.expectRank then
            imp.doneRanks = imp.doneRanks + 1
            imp.retries = 0
            imp.phase = "begin"
            imp.nextActionAt = now + BUY_PACE_MS
            statusLine = string.format("Importing %d/%d...", imp.doneRanks, imp.totalRanks)
        elseif (now - imp.buyAt) > BUY_TIMEOUT_MS then
            imp.retries = imp.retries + 1
            if imp.retries >= 2 then
                -- Two timeouts on the same rank: record and move on (points
                -- exhausted, server refused, or rank mismatch).
                imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, reason = "buy timed out (rank never moved)" }
                imp.idx = imp.idx + 1
                imp.retries = 0
                imp.phase = "begin"
            else
                imp.phase = "begin"  -- re-issue the buy once
            end
        end
    end
end

--- Main-loop pump: advances export and import. Cheap no-op when idle.
function M.tick(now)
    if exportPending then
        if not (deps.isAABuilding and deps.isAABuilding()) then
            exportPending = false
            doExportNow()
        end
        return
    end
    if imp then tickImport(now) end
    if armed and now >= armed.armedUntil then armed = nil end
end

function M.isBusy()
    return imp ~= nil or exportPending
end

function M.isImporting()
    return imp ~= nil
end

--- { done, total } while importing, nil otherwise (for the view's progress).
function M.getProgress()
    if not imp then return nil end
    return { done = imp.doneRanks, total = imp.totalRanks }
end

--- One-line status for the native AA window strip.
function M.getStatusLine()
    return statusLine
end

function M.init(d)
    deps = d or {}
end

return M
