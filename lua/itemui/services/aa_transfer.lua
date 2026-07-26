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
local BUY_PACE_MS = 25
local ARM_WINDOW_MS = 10000
local FLOOD_SENDS_PER_TICK = 8     -- /alt buy commands per main-loop tick in flood mode
local FLOOD_SETTLE_MS = 4000       -- flood ends when confirms/refusals stop arriving for this long

local exportPending = false
local imp = nil            -- active import state
local armed = nil          -- { path, until, ranks, cost, exact }
local statusLine = "CoOpt: Export saves your AAs"
-- Stamped by the chat event when the server refuses a training request -
-- lets the stepper fail an in-flight buy instantly instead of waiting out
-- the 2s verify timeout (x2 retries, x2 passes) per refused line.
local lastUnableAt = 0
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

local ensuredDirs = {}
local migratedLegacy = false

local function ensureDir(d)
    if not d or d == "" or ensuredDirs[d] then return end
    ensuredDirs[d] = true
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
    if p and p ~= "" then
        -- Custom folder gets created too, else the first export to a
        -- not-yet-created path fails with an opaque "could not open file".
        ensureDir(p)
        return p
    end
    local d = (config.getAABackupPath and config.getAABackupPath()) or config.AA_BACKUP_PATH or ""
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

-- The character's TRUE trained rank per group (plugin: PcProfile AAList -
-- the store the server trains into). The char-side TLO Rank read resolves
-- level-appropriate entries and inflates for partially-trained lines - it
-- fooled both planning ("nothing missing" with 417 pts of holes) and
-- per-buy verification (bursts "verified" instantly at cap). Short TTL:
-- verification polls this while waiting for server confirms.
local ownedCache = { at = 0, map = nil }
local function ownedRanks(now)
    now = now or mq.gettime()
    if ownedCache.map and (now - ownedCache.at) < 100 then return ownedCache.map end
    local pa = plugAA()
    if pa and type(pa.getOwnedRanks) == 'function' then
        local ok, m = pcall(pa.getOwnedRanks)
        if ok and type(m) == 'table' then
            ownedCache.map = m
            ownedCache.at = now
            return m
        end
    end
    ownedCache.map = nil
    return nil
end

--- Current trained rank for a group: plugin truth first, TLO fallback.
local function curRankFor(gid, name, now)
    if gid then
        local m = ownedRanks(now)
        if m then return tonumber(m[gid]) or 0 end
    end
    return myRank(name)
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
    -- Ranks come from the plugin owned-ranks store when available - the SAME
    -- truth source import plans against. The scan records' TLO rank is
    -- inflated for partially-trained lines; exporting it would make a later
    -- import buy ranks the character never owned.
    local owned = ownedRanks(mq.gettime())
    local function exportRank(aa)
        if owned and aa.id then return tonumber(owned[aa.id]) or 0 end
        return tonumber(aa.rank) or 0
    end
    local count = 0
    local tmpPath = path .. ".tmp"
    local ok, err = pcall(function()
        local f = io.open(tmpPath, "w")
        if not f then error("could not open file") end
        local wok, werr = pcall(function()
            f:write("[Meta]\n")
            f:write("Character=" .. cname .. "\n")
            f:write("Class=" .. class .. "\n")
            f:write("Classes=" .. tagStr .. "\n")
            f:write("Exported=" .. os.date("%Y-%m-%d %H:%M:%S") .. "\n")
            for _, aa in ipairs(list) do
                if aa.name and exportRank(aa) > 0 then count = count + 1 end
            end
            f:write("TotalAAs=" .. tostring(count) .. "\n")
            f:write("[AAs]\n")
            for _, aa in ipairs(list) do
                local r = aa.name and exportRank(aa) or 0
                if r > 0 then
                    f:write(aa.name .. "=" .. tostring(r) .. "\n")
                end
            end
            -- Group ids as an import-resolution fallback (names are primary;
            -- ids survive if a name lookup ever fails against a fresh scan).
            f:write("[AAIds]\n")
            for _, aa in ipairs(list) do
                if aa.name and aa.id and exportRank(aa) > 0 then
                    f:write(aa.name .. "=" .. tostring(aa.id) .. "\n")
                end
            end
        end)
        f:close()
        if not wok then error(werr) end
    end)
    -- Write to .tmp then rename: an interrupted export must never leave a
    -- truncated, valid-looking aa_*.ini that a later import would restore.
    if ok then ok, err = pcall(function()
        os.remove(path)
        if not os.rename(tmpPath, path) then error("rename failed") end
    end) end
    if ok then
        fileList = nil
        fileShown = false
        say(string.format("Exported %d AAs -> %s", count, fname))
    else
        pcall(os.remove, tmpPath)
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
            -- Section header ONLY when the whole line is [Name]. Perky's
            -- rebirth-class AAs are named "[Berserker] Decapitation" etc. -
            -- an unanchored match ate the first such line as a section switch
            -- and silently dropped it and everything after it.
            if line:match("^%[([^%]]+)%]%s*$") then
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

--- name -> groupId and name -> scan record for every AA the browser scan
--- knows (ownership-INDEPENDENT - this is the global table, so it resolves
--- post-reset when Me.AltAbility(name) can't: that TLO only finds abilities
--- you own). Records also carry requiresAbility/requiresAbilityPoints (the
--- table's first-prerequisite data) for import ordering and diagnostics.
local function buildNameMaps()
    local ids, recs = {}, {}
    for _, r in ipairs((deps.getAAList and deps.getAAList()) or {}) do
        if r.name then
            if r.id then ids[r.name] = r.id end
            recs[r.name] = r
        end
    end
    return ids, recs
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
--- Last-resort group id: the GLOBAL TLO's name branch is table-wide and
--- ownership-independent - covers AAs the browser's visible list excludes
--- (e.g. rebirth-class lines) in exports that predate [AAIds].
local function gidByName(name)
    local ok, id = pcall(function()
        local ga = mq.TLO.AltAbility and mq.TLO.AltAbility(name)
        return ga and ga.ID and ga.ID()
    end)
    id = ok and tonumber(id) or nil
    if id and id > 0 then return id end
    return nil
end

local function planImport(aas, nameIds, nameRecs)
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
            -- Group id: current scan first, the export's own [AAIds], then a
            -- global-TLO name probe. Never the character-side TLO - post-
            -- reset it resolves nothing.
            local gid = nameIds[entry.name] or entry.id or gidByName(entry.name)
            local cur = curRankFor(gid, entry.name)
            if entry.rank > cur then
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
    -- Prerequisite ordering: buy prereq lines before their dependents. The
    -- scan records carry the table's FIRST required group per AA (name +
    -- required rank); buying the whole prereq line first satisfies any
    -- required rank, so entry-level topological order suffices. Multi-prereq
    -- AAs (rare) are covered by the timeout-retry pass instead. A cycle or
    -- self-reference just emits the remainder in file order.
    if nameRecs then
        local queued = {}
        for _, q in ipairs(plan.queue) do queued[q.name] = true end
        local ordered, emitted = {}, {}
        for _ = 1, #plan.queue do
            local progressed = false
            for _, q in ipairs(plan.queue) do
                if not emitted[q.name] then
                    local rec = nameRecs[q.name]
                    -- requiresAbilityName is the scan's gid->name translation of
                    -- the raw requiresAbility field (which the TLO renders as the
                    -- required GROUP ID string - useless against name-keyed maps).
                    local prereq = rec and rec.requiresAbilityName
                    if type(prereq) ~= "string" or prereq == "" then prereq = nil end
                    if not (prereq and queued[prereq] and not emitted[prereq]) then
                        ordered[#ordered + 1] = q
                        emitted[q.name] = true
                        progressed = true
                    end
                end
            end
            if not progressed or #ordered == #plan.queue then break end
        end
        for _, q in ipairs(plan.queue) do
            if not emitted[q.name] then ordered[#ordered + 1] = q end
        end
        plan.queue = ordered
    end
    return plan
end

--- Start importing from a backup file. Gates on AA points when the cost is
--- known exactly; refuses to start when nothing is missing. force = true
--- (the native arm flow's confirmed click) allows a partial import when
--- points fall short - safe because the plan only ever buys missing ranks,
--- so re-importing later resumes where it stopped. prebuilt (arm flow) is
--- the plan already computed at arm time - re-planning walks the 50k-entry
--- cost/index maps again for nothing.
function M.startImport(path, force, prebuilt)
    if imp then say("Import already running") return false end
    if exportPending then say("Export running - wait for it") return false end
    local nameIds, nameRecs, plan
    if prebuilt and prebuilt.path == path then
        nameIds, nameRecs, plan = prebuilt.nameIds, prebuilt.nameRecs, prebuilt.plan
    else
        -- The global AA scan is the resolver for unowned names; without it
        -- the whole import would misreport. Kick a scan, ask for a re-click.
        nameIds, nameRecs = buildNameMaps()
        if next(nameIds) == nil then
            if deps.refreshAA then deps.refreshAA() end
            say("Scanning AA tables - click Import again in a moment")
            return false
        end
        local aas, meta = M.parseBackup(path)
        if not aas then say("Import failed: " .. tostring(meta)) return false end
        if #aas == 0 then say("No AAs in file") return false end
        local metaTotal = tonumber(meta and meta.TotalAAs) or 0
        if metaTotal > 0 and #aas < metaTotal then
            -- Fatal, matching the arm flow: a short parse means a truncated or
            -- corrupted export - importing it would silently restore a partial set.
            say(string.format("Import aborted: parsed only %d of %d file entries", #aas, metaTotal))
            return false
        end
        plan = planImport(aas, nameIds, nameRecs)
    end
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
    -- Exact per-rank table ids (plugin): enables precise buys and burst mode.
    local rankIndexes = nil
    local pa = plugAA()
    if pa and type(pa.getGroupRankIndexes) == 'function' then
        local okR, m = pcall(pa.getGroupRankIndexes)
        if okR and type(m) == 'table' then rankIndexes = m end
    end
    imp = {
        queue = plan.queue, idx = 1, phase = "begin",
        expectRank = 0, buyAt = 0, retries = 0, nextActionAt = 0,
        totalRanks = plan.ranks, doneRanks = 0, failed = {},
        pass = 1, skippedAuto = plan.skippedAuto or 0,
        nameRecs = nameRecs, rankIndexes = rankIndexes,
        t0 = mq.gettime(), tSendDone = nil, tSettleDone = nil,
    }
    -- Flood mode: with exact per-rank ids, send EVERY missing rank of every
    -- line up front (prereq order preserved - the server processes serially)
    -- and verify the whole batch against the owned-ranks store in ONE settle,
    -- instead of a verify round-trip per line. Shortfalls and lines without
    -- complete id chains drop to the careful per-rank lane as pass 2.
    if rankIndexes then
        local sends, floodTargets, deferred = {}, {}, {}
        for _, q in ipairs(plan.queue) do
            local grp = q.gid and rankIndexes[q.gid] or nil
            local ids, complete = {}, grp ~= nil
            if complete then
                for r = (q.startRank or 0) + 1, q.target do
                    local ix = tonumber(grp[r])
                    if ix and ix > 0 then
                        ids[#ids + 1] = ix
                    else
                        complete = false
                        break
                    end
                end
            end
            if complete and #ids > 0 then
                for _, ix in ipairs(ids) do sends[#sends + 1] = ix end
                floodTargets[#floodTargets + 1] = q
            else
                deferred[#deferred + 1] = q
            end
        end
        if #sends > 0 then
            imp.flood = { sends = sends, pos = 1, targets = floodTargets, deferred = deferred,
                          lastProgressAt = 0, lastDone = -1 }
            imp.phase = "floodsend"
        end
    end
    return true
end

--- Buy id for one missing rank, most-authoritative source first:
---  1. The plugin's per-rank table-id map - EXACT rank cur+1 by id. The
---     global TLO's first match for a group is NOT guaranteed to be rank 1
---     on this server's custom table, and /alt buy with a mid-chain id gets
---     "Unable to train" (seen in the field: multi-rank General/Class lines
---     refused while single-rank Specials bought fine).
---  2. Owned AAs: the character-side NextIndex (id of the next rank entry).
---  3. Last resort: the global first-match entry's Index (correct whenever
---     rank 1 happens to be the lowest-index entry, e.g. single-rank AAs).
local function resolveBuyId(entry, rankIndexes, cur)
    if rankIndexes and entry.gid then
        local grp = rankIndexes[entry.gid]
        local ix = grp and tonumber(grp[(cur or 0) + 1]) or nil
        if ix and ix > 0 then return ix end
    end
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
        local prebuilt = armed.prebuilt
        armed = nil
        M.startImport(path, force, prebuilt)
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
    local nameIds, nameRecs = buildNameMaps()
    if next(nameIds) == nil then
        if deps.refreshAA then deps.refreshAA() end
        say("Scanning AA tables - click Import again in a moment")
        return
    end
    local aas, meta = M.parseBackup(path)
    if not aas then say("Import failed: " .. tostring(meta)) return end
    local metaTotal = tonumber(meta and meta.TotalAAs) or 0
    if metaTotal > 0 and #aas < metaTotal then
        say(string.format("Warning: parsed %d of %d file entries", #aas, metaTotal))
        return
    end
    local plan = planImport(aas, nameIds, nameRecs)
    if plan.ranks == 0 then say("Nothing missing vs " .. fname) return end
    local have = myPoints()
    local prebuilt = { path = path, nameIds = nameIds, nameRecs = nameRecs, plan = plan }
    if plan.exact and plan.cost > have then
        -- Not enough points: arm a PARTIAL import instead of dead-ending -
        -- the plan only buys missing ranks, so a later re-import resumes.
        armed = { path = path, armedUntil = now + ARM_WINDOW_MS, partial = true, prebuilt = prebuilt }
        say(string.format("Need %d pts, have %d. Import again for a PARTIAL import.", plan.cost, have))
        return
    end
    armed = { path = path, armedUntil = now + ARM_WINDOW_MS, prebuilt = prebuilt }
    if plan.exact then
        say(string.format("%s: %d ranks, %d pts. Import again to start.", fname, plan.ranks, plan.cost))
    else
        say(string.format("%s: %d ranks. Import again to start.", fname, plan.ranks))
    end
end

-- Phase timing for the summary/report: shows where the seconds go (send =
-- our pacing, confirm = the server working through the buys, careful = the
-- per-rank tail). This is the data that decides any future speed work.
local function timingLine()
    local now = mq.gettime()
    local total = (now - (imp.t0 or now)) / 1000
    local parts = { string.format("total %.1fs", total) }
    if imp.tSendDone then
        parts[#parts + 1] = string.format("send %.1fs", (imp.tSendDone - imp.t0) / 1000)
    end
    if imp.tSettleDone and imp.tSendDone then
        parts[#parts + 1] = string.format("confirm %.1fs", (imp.tSettleDone - imp.tSendDone) / 1000)
    end
    if imp.tSettleDone and now > imp.tSettleDone + 500 then
        parts[#parts + 1] = string.format("careful %.1fs", (now - imp.tSettleDone) / 1000)
    end
    return "Timing: " .. table.concat(parts, ", ")
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
        f:write(string.format("Trained %d/%d ranks. %d entries not trained:\n", imp.doneRanks, imp.totalRanks, #imp.failed))
        f:write(timingLine() .. "\n\n")
        for _, fl in ipairs(imp.failed) do
            f:write(string.format("%s  (wanted rank %d, had %s)  - %s\n",
                fl.name, fl.wanted or 0, tostring(fl.had or "?"), fl.reason or "unknown"))
        end
        f:close()
    end)
    return ok and "aa_import_report.txt" or nil
end

local function finishImport()
    -- One extra sweep over timeout/prereq failures: chains the plan-time
    -- ordering missed (multi-prereq AAs) resolve once everything else from
    -- pass 1 exists. Unresolvable/unbuyable entries would fail identically.
    local function retryable(f)
        return f.reason and (f.reason:match("^buy timed out") or f.reason:match("^prereq not met")
            or f.reason:match("^burst stalled") or f.reason:match("^server refused")) ~= nil
    end
    if imp.pass == 1 then
        local retryQueue = {}
        for _, f in ipairs(imp.failed) do
            if retryable(f) then
                -- Reuse the ORIGINAL gid (may have come from the export's [AAIds]
                -- or a global-TLO probe for scan-invisible lines); the scan record
                -- is only a fallback. Retrying with gid=nil falls back to the
                -- lying character TLO and silently drops partially-trained lines.
                local rec = imp.nameRecs and imp.nameRecs[f.name]
                retryQueue[#retryQueue + 1] = { name = f.name, target = f.wanted, gid = f.gid or (rec and rec.id) or nil }
            end
        end
        if #retryQueue > 0 then
            local keep = {}
            for _, f in ipairs(imp.failed) do
                if not retryable(f) then keep[#keep + 1] = f end
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
    -- Always written: clean runs record the phase timing breakdown too.
    local report = writeImportReport()
    local msg
    if nFailed == 0 then
        msg = string.format("Import complete: %d ranks trained (%.1fs)", imp.doneRanks,
            (mq.gettime() - (imp.t0 or mq.gettime())) / 1000)
    else
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

    if imp.phase == "floodsend" then
        local fl = imp.flood
        for _ = 1, FLOOD_SENDS_PER_TICK do
            if fl.pos > #fl.sends then break end
            mq.cmd("/alt buy " .. tostring(fl.sends[fl.pos]))
            fl.pos = fl.pos + 1
        end
        statusLine = string.format("Buying %d/%d...", math.min(fl.pos - 1, #fl.sends), #fl.sends)
        if fl.pos > #fl.sends then
            imp.buyAt = now
            fl.lastProgressAt = now
            imp.tSendDone = now
            imp.phase = "floodsettle"
        end
        return
    elseif imp.phase == "floodsettle" then
        local fl = imp.flood
        -- No owned-ranks truth (plugin fault / not ready): HOLD, don't reconcile
        -- against an empty map - that would zero doneRanks and re-queue every
        -- line as a shortfall. Bail to the careful lane only if truth stays
        -- unavailable for 10s straight.
        local m = ownedRanks(now)
        if not m then
            fl.noTruthSince = fl.noTruthSince or now
            if (now - fl.noTruthSince) <= 10000 then return end
            m = {}
        else
            fl.noTruthSince = nil
        end
        local allMet, doneCount = true, 0
        for _, t in ipairs(fl.targets) do
            local got = tonumber(m[t.gid]) or 0
            if got < t.target then allMet = false end
            doneCount = doneCount + math.max(0, math.min(got, t.target) - (t.startRank or 0))
        end
        if fl.lastDone ~= doneCount then
            fl.lastDone = doneCount
            fl.lastProgressAt = now
            statusLine = string.format("Confirmed %d/%d...", doneCount, imp.totalRanks)
        end
        -- Refusal chatter is ALSO the server working through our queue - it
        -- must hold the settle open. Exiting early while flood commands were
        -- still draining made the careful lane race the queue (rank
        -- collisions -> spurious "unable to train"; field-observed as "run
        -- it twice and the stragglers go through").
        local lastActivity = math.max(fl.lastProgressAt, (lastUnableAt >= (imp.t0 or 0)) and lastUnableAt or 0)
        if allMet or (now - lastActivity) > FLOOD_SETTLE_MS then
            -- Reconcile against server truth: credit what landed, hand the
            -- shortfalls + deferred lines to the careful per-rank lane.
            imp.doneRanks = doneCount
            local rest = {}
            for _, t in ipairs(fl.targets) do
                local got = tonumber(m[t.gid]) or 0
                if got < t.target then
                    rest[#rest + 1] = { name = t.name, target = t.target, gid = t.gid, startRank = got }
                end
            end
            for _, q in ipairs(fl.deferred) do rest[#rest + 1] = q end
            imp.flood = nil
            imp.tSettleDone = now
            if #rest == 0 then finishImport() return end
            imp.queue = rest
            imp.idx = 1
            imp.phase = "begin"
            imp.retries = 0
            imp.pass = 2
            -- Extra beat before the careful lane touches anything: the queue
            -- is quiet per the settle, but cheap insurance against one last
            -- in-flight confirm.
            imp.nextActionAt = now + 750
            statusLine = string.format("Finishing %d lines carefully...", #rest)
        end
        return
    end

    local entry = imp.queue[imp.idx]
    if not entry then finishImport() return end

    if imp.phase == "begin" then
        local cur = curRankFor(entry.gid, entry.name, now)
        if cur >= entry.target then
            imp.idx = imp.idx + 1
            imp.retries = 0
            return
        end
        if myPoints() <= 0 then
            -- Out of points: drain the rest fast with a clear reason instead
            -- of burning two 2s timeouts per remaining entry.
            imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, gid = entry.gid, reason = "out of AA points" }
            imp.idx = imp.idx + 1
            imp.retries = 0
            return
        end
        -- Burst mode (pass 1): when every missing rank's exact table id is
        -- known, fire the whole line one buy per tick and verify ONCE at the
        -- end - an order of magnitude faster than buy/verify per rank on
        -- long passive lines. Pass 2 stays in the careful per-rank lane.
        if imp.pass == 1 and imp.rankIndexes and entry.gid then
            local grp = imp.rankIndexes[entry.gid]
            if grp then
                local ids, complete = {}, true
                for r = cur + 1, entry.target do
                    local ix = tonumber(grp[r])
                    if ix and ix > 0 then
                        ids[#ids + 1] = ix
                    else
                        complete = false
                        break
                    end
                end
                if complete and #ids > 1 then
                    entry.burstIds = ids
                    entry.burstPos = 1
                    entry.burstStart = cur
                    entry.burstT0 = now
                    imp.phase = "burst"
                    statusLine = string.format("Buying %s %d..%d", entry.name, cur + 1, entry.target)
                    return
                end
            end
        end
        local buyId, why = resolveBuyId(entry, imp.rankIndexes, cur)
        if not buyId then
            imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, gid = entry.gid, reason = why or "unresolvable" }
            imp.idx = imp.idx + 1
            imp.retries = 0
            return
        end
        mq.cmd("/alt buy " .. tostring(buyId))
        imp.expectRank = cur + 1
        imp.buyAt = now
        imp.phase = "verify"
    elseif imp.phase == "burst" then
        mq.cmd("/alt buy " .. tostring(entry.burstIds[entry.burstPos]))
        entry.burstPos = entry.burstPos + 1
        if entry.burstPos > #entry.burstIds then
            imp.buyAt = now
            imp.phase = "burstverify"
        end
    elseif imp.phase == "burstverify" then
        local cur = curRankFor(entry.gid, entry.name, now)
        -- Server refusal announced in chat during/after this burst: settle
        -- briefly, then finalize from the actual rank - no timeout wait.
        local refused = lastUnableAt >= (entry.burstT0 or 0)
            and (now - math.max(imp.buyAt, lastUnableAt)) > 600
        if cur >= entry.target then
            imp.doneRanks = imp.doneRanks + (entry.target - entry.burstStart)
            imp.idx = imp.idx + 1
            imp.retries = 0
            imp.phase = "begin"
            statusLine = string.format("Importing %d/%d...", imp.doneRanks, imp.totalRanks)
        elseif refused or (now - imp.buyAt) > (1500 + 100 * #entry.burstIds) then
            -- Credit whatever landed; the remainder goes to pass 2's careful
            -- per-rank lane (a hard server gate will just refuse fast again).
            if cur > entry.burstStart then
                imp.doneRanks = imp.doneRanks + (cur - entry.burstStart)
            end
            local reason = refused
                and string.format("server refused training at rank %d/%d", cur, entry.target)
                or string.format("burst stalled at rank %d/%d", cur, entry.target)
            imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, gid = entry.gid, reason = reason }
            imp.idx = imp.idx + 1
            imp.retries = 0
            imp.phase = "begin"
        end
    elseif imp.phase == "verify" then
        local cur = curRankFor(entry.gid, entry.name, now)
        if cur >= imp.expectRank then
            imp.doneRanks = imp.doneRanks + 1
            imp.retries = 0
            imp.phase = "begin"
            imp.nextActionAt = now + BUY_PACE_MS
            statusLine = string.format("Importing %d/%d...", imp.doneRanks, imp.totalRanks)
        elseif lastUnableAt >= imp.buyAt and (now - lastUnableAt) > 250 then
            -- The server said no in chat: fail this entry now, no timeout.
            imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, gid = entry.gid,
                reason = string.format("server refused training at rank %d", imp.expectRank) }
            imp.idx = imp.idx + 1
            imp.retries = 0
            imp.phase = "begin"
        elseif (now - imp.buyAt) > BUY_TIMEOUT_MS then
            imp.retries = imp.retries + 1
            if imp.retries >= 2 then
                -- Two timeouts on the same rank: record and move on. When the
                -- table says a prereq line is short, name it - that's almost
                -- always why a server refuses a buy.
                local reason = "buy timed out (rank never moved)"
                local rec = imp.nameRecs and imp.nameRecs[entry.name]
                -- Diagnose via the gid->NAME translation; the raw requiresAbility
                -- is a group-id string that matches nothing in name-keyed maps
                -- (it produced reports like "prereq not met: 487 ... have 0").
                local prereq = rec and rec.requiresAbilityName
                if type(prereq) == "string" and prereq ~= "" then
                    local need = tonumber(rec.requiresAbilityPoints) or 0
                    local prereqRec = imp.nameRecs and imp.nameRecs[prereq]
                    local haveR = curRankFor(prereqRec and prereqRec.id or nil, prereq, now)
                    if need > 0 and haveR < need then
                        reason = string.format("prereq not met: %s rank %d (have %d)", prereq, need, haveR)
                    end
                end
                imp.failed[#imp.failed + 1] = { name = entry.name, wanted = entry.target, had = cur, gid = entry.gid, reason = reason }
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
    if imp then
        -- Zoning/death guard: TLO reads go nil (myPoints()=0, ownedRanks()=nil)
        -- and would drain the queue as "out of AA points" / reconcile against
        -- nothing. Freeze the import by refreshing every timing reference each
        -- tick until the world is back.
        local okGS, gs = pcall(function()
            return mq.TLO and mq.TLO.EverQuest and mq.TLO.EverQuest.GameState and mq.TLO.EverQuest.GameState()
        end)
        if not okGS or gs ~= "INGAME" then
            imp.nextActionAt = now + 500
            imp.buyAt = now
            if imp.flood then imp.flood.lastProgressAt = now end
            local e = imp.queue[imp.idx]
            if e and e.burstT0 then e.burstT0 = now end
            statusLine = "Import paused (zoning)..."
            return
        end
        tickImport(now)
    end
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
    -- Server refusal line ("Unable to train in ability.") -> instant fail
    -- for the in-flight buy. Registered once; main_loop pumps mq.doevents.
    pcall(function()
        mq.event('cooptAAUnable', '#*#Unable to train in ability#*#', function()
            lastUnableAt = mq.gettime()
        end)
    end)
end

return M
