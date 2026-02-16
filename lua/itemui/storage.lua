--[[
    ItemUI Storage Module
    Character-specific inventory and bank snapshots with filter status.
    Path: Macros/sell_config/Chars/CharName/inventory.lua, bank.lua
    On open: load from file (fast), optionally reconcile with live scan.
    On close: save in-memory state to file.
--]]

local config = require('itemui.config')
local mq = require('mq')
local file_safe = require('itemui.utils.file_safe')

local INVENTORY_FILE = "inventory.lua"
local BANK_FILE = "bank.lua"

local function getCharName()
    local me = mq.TLO.Me
    return me and me.Name and me.Name() or ""
end

local function getCharFolder()
    local name = getCharName()
    if name == "" then return nil end
    return config.getCharStoragePath(name, nil)
end

-- Escape string for Lua literal
local function escapeLuaString(s)
    if s == nil then return "nil" end
    s = tostring(s)
    -- Fast-path: 95%+ of EQ item names have no special chars
    if not s:find('[\\"\n\r]') then return '"' .. s .. '"' end
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    return '"' .. s .. '"'
end

-- Pre-computed field definitions for batched serialization (module load time)
-- Numeric fields: { field_key, default_value } — batched into sub-groups of ~20 for string.format
local NUM_FIELDS_1 = {
    {"bag",0}, {"slot",0}, {"id",0}, {"value",0}, {"totalValue",0}, {"stackSize",1}, {"stackSizeMax",1},
    {"weight",0}, {"icon",0}, {"tribute",0}, {"size",0}, {"sizeCapacity",0}, {"container",0},
    {"requiredLevel",0}, {"recommendedLevel",0}, {"augSlots",0}, {"clicky",0}, {"proc",0}, {"focus",0}, {"worn",0},
}
local NUM_FIELDS_2 = {
    {"spell",0}, {"instrumentMod",0}, {"ac",0}, {"hp",0}, {"mana",0}, {"endurance",0},
    {"str",0}, {"sta",0}, {"agi",0}, {"dex",0}, {"int",0}, {"wis",0}, {"cha",0},
    {"attack",0}, {"accuracy",0}, {"avoidance",0}, {"shielding",0}, {"haste",0}, {"damage",0}, {"itemDelay",0},
}
local NUM_FIELDS_3 = {
    {"dmgBonus",0}, {"spellDamage",0}, {"strikeThrough",0}, {"damageShield",0}, {"combatEffects",0},
    {"dotShielding",0}, {"hpRegen",0}, {"manaRegen",0}, {"enduranceRegen",0},
    {"heroicSTR",0}, {"heroicSTA",0}, {"heroicAGI",0}, {"heroicDEX",0}, {"heroicINT",0}, {"heroicWIS",0}, {"heroicCHA",0},
    {"svMagic",0}, {"svFire",0}, {"svCold",0}, {"svPoison",0},
}
local NUM_FIELDS_4 = {
    {"svDisease",0}, {"svCorruption",0},
    {"heroicSvMagic",0}, {"heroicSvFire",0}, {"heroicSvCold",0}, {"heroicSvDisease",0}, {"heroicSvPoison",0}, {"heroicSvCorruption",0},
    {"spellShield",0}, {"damageShieldMitigation",0}, {"stunResist",0}, {"clairvoyance",0}, {"healAmount",0},
    {"luck",0}, {"purity",0}, {"charges",0}, {"range",0}, {"skillModValue",0}, {"skillModMax",0}, {"baneDMG",0},
}
-- Boolean fields: { field_key }
local BOOL_FIELDS = {
    "nodrop", "notrade", "norent", "lore", "magic", "attuneable", "heirloom",
    "prestige", "collectible", "quest", "tradeskills",
}
-- String fields (need escapeLuaString): { field_key, default }
local STR_FIELDS = {
    {"name", nil}, {"type", nil}, {"class", ""}, {"race", ""}, {"wornSlots", ""},
    {"instrumentType", ""}, {"baneDMGType", ""}, {"deity", ""}, {"dmgBonusType", ""},
}

-- Build format templates at module load time (one per batch)
local function buildFmtTemplate(fields)
    local fmtParts = {}
    for _, f in ipairs(fields) do fmtParts[#fmtParts + 1] = f[1] .. "=%d" end
    return table.concat(fmtParts, ",")
end
local NUM_FMT_1 = buildFmtTemplate(NUM_FIELDS_1)
local NUM_FMT_2 = buildFmtTemplate(NUM_FIELDS_2)
local NUM_FMT_3 = buildFmtTemplate(NUM_FIELDS_3)
local NUM_FMT_4 = buildFmtTemplate(NUM_FIELDS_4)

-- Helper: extract values array for a batch of numeric fields
local function numVals(it, fields)
    local vals = {}
    for i, f in ipairs(fields) do vals[i] = it[f[1]] or f[2] end
    return vals
end

-- Serialize one item to Lua table literal (all properties from iteminfo.mac)
-- Uses batched string.format (4 sub-batches of ~20 numeric fields each) to reduce
-- from ~80 individual format calls per item down to 4.
local function serializeItem(it)
    local parts = {}
    -- Numeric batches (4 format calls instead of ~80)
    parts[#parts + 1] = string.format(NUM_FMT_1, unpack(numVals(it, NUM_FIELDS_1)))
    -- String fields (interspersed between numeric batches to maintain field ordering)
    parts[#parts + 1] = "name=" .. escapeLuaString(it.name)
    parts[#parts + 1] = "type=" .. escapeLuaString(it.type)
    -- Boolean fields (simple concat, no format call)
    for _, f in ipairs(BOOL_FIELDS) do
        parts[#parts + 1] = f .. "=" .. (it[f] and "true" or "false")
    end
    -- Remaining string fields
    parts[#parts + 1] = "class=" .. escapeLuaString(it.class or "")
    parts[#parts + 1] = "race=" .. escapeLuaString(it.race or "")
    parts[#parts + 1] = "wornSlots=" .. escapeLuaString(it.wornSlots or "")
    parts[#parts + 1] = "instrumentType=" .. escapeLuaString(it.instrumentType or "")
    -- Numeric batch 2
    parts[#parts + 1] = string.format(NUM_FMT_2, unpack(numVals(it, NUM_FIELDS_2)))
    -- Numeric batch 3
    parts[#parts + 1] = string.format(NUM_FMT_3, unpack(numVals(it, NUM_FIELDS_3)))
    -- Numeric batch 4
    parts[#parts + 1] = string.format(NUM_FMT_4, unpack(numVals(it, NUM_FIELDS_4)))
    -- Remaining string fields
    parts[#parts + 1] = "baneDMGType=" .. escapeLuaString(it.baneDMGType or "")
    parts[#parts + 1] = "deity=" .. escapeLuaString(it.deity or "")
    parts[#parts + 1] = "dmgBonusType=" .. escapeLuaString(it.dmgBonusType or "")
    -- Optional/conditional fields (individual appends). Only persist Keep/Junk when in exact list (not keyword/type-derived).
    if it.inKeepExact then parts[#parts + 1] = "inKeep=true" end
    if it.inJunkExact then parts[#parts + 1] = "inJunk=true" end
    if it.isProtected ~= nil then parts[#parts + 1] = "isProtected=" .. (it.isProtected and "true" or "false") end
    if it.willSell ~= nil then parts[#parts + 1] = "willSell=" .. (it.willSell and "true" or "false") end
    if it.sellReason ~= nil and it.sellReason ~= "" then parts[#parts + 1] = "sellReason=" .. escapeLuaString(it.sellReason) end
    if it.acquiredSeq then parts[#parts + 1] = "acquiredSeq=" .. tonumber(it.acquiredSeq) end
    if it.source and it.source ~= "" then parts[#parts + 1] = "source=" .. escapeLuaString(it.source) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Build Lua file content (nextAcquiredSeq optional, for static acquired order)
local function buildInventoryContent(items, savedAt, nextAcquiredSeq)
    savedAt = savedAt or os.time()
    local lines = {"-- ItemUI inventory snapshot. Do not edit manually.", "return {"}
    lines[#lines + 1] = "  savedAt=" .. savedAt .. ","
    if nextAcquiredSeq then
        lines[#lines + 1] = "  nextAcquiredSeq=" .. tonumber(nextAcquiredSeq) .. ","
    end
    lines[#lines + 1] = "  items={"
    for _, it in ipairs(items or {}) do
        lines[#lines + 1] = "    " .. serializeItem(it) .. ","
    end
    lines[#lines + 1] = "  }"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

local function buildBankContent(items, savedAt)
    savedAt = savedAt or os.time()
    local lines = {"-- ItemUI bank snapshot. Do not edit manually.", "return {"}
    lines[#lines + 1] = "  savedAt=" .. savedAt .. ","
    lines[#lines + 1] = "  items={"
    for _, it in ipairs(items or {}) do
        lines[#lines + 1] = "    " .. serializeItem(it) .. ","
    end
    lines[#lines + 1] = "  }"
    lines[#lines + 1] = "}"
    return table.concat(lines, "\n")
end

-- Load and execute Lua file, return data or nil (uses safe read so bad path/perms don't throw)
local function loadLuaFile(path)
    if not path then return nil end
    local content = file_safe.safeReadAll(path)
    if not content or content == "" then return nil end
    local fn, err = loadstring(content)
    if not fn then return nil end
    local ok, data = pcall(fn)
    if not ok or not data then return nil end
    return data
end

-- Load inventory from char folder (returns items, savedAt, nextAcquiredSeq)
local function loadInventory()
    local path = config.getCharStoragePath(getCharName(), INVENTORY_FILE)
    local data = loadLuaFile(path)
    if not data or not data.items then return nil, nil, nil end
    return data.items, data.savedAt, data.nextAcquiredSeq
end

-- Load bank from char folder
local function loadBank()
    local path = config.getCharStoragePath(getCharName(), BANK_FILE)
    local data = loadLuaFile(path)
    if not data or not data.items then return nil, nil end
    return data.items, data.savedAt
end

-- Profile: log when save exceeds threshold (set via storage.init from init.lua)
local profileConfig = { enabled = false, thresholdMs = 30 }

local function initStorage(opts)
    if opts then
        if opts.profileEnabled ~= nil then profileConfig.enabled = opts.profileEnabled end
        if opts.profileThresholdMs ~= nil then profileConfig.thresholdMs = opts.profileThresholdMs end
    end
end

-- Save inventory to char folder (nextAcquiredSeq optional, for persistent acquired order)
local function saveInventory(items, nextAcquiredSeq)
    if not items then return false end
    local t0 = mq.gettime()
    local path = config.getCharStoragePath(getCharName(), INVENTORY_FILE)
    if not path then return false end
    local content = buildInventoryContent(items, os.time(), nextAcquiredSeq)
    local ok = file_safe.safeWrite(path, content)
    local e = mq.gettime() - t0
    if ok and profileConfig.enabled and e >= profileConfig.thresholdMs then
        print(string.format("\ag[ItemUI Profile]\ax storage.saveInventory: %d ms (%d items)", e, #items))
    end
    return ok
end

local SELL_CACHE_FILE = "sell_cache.ini"

-- Chunk size for sell cache: must stay under 2048 so the expanded /call CheckFilterList "chunk" "itemName" ... line fits in MQ's parse buffer
local SELL_CACHE_CHUNK_LEN = 1700

-- Write macro-readable sell list INI (only item names with willSell == true).
-- Chunked so each [Items] key is under SELL_CACHE_CHUNK_LEN chars (avoids buffer overflow in macro).
-- Path: Macros/sell_config/Chars/<CharName>/sell_cache.ini
-- Format: [Meta] savedAt=... chunks=N ; [Count] count=M ; [Items] 1=name1/name2/... 2=name3/...
local function writeSellCache(items)
    if not items or #items == 0 then return false end
    -- Guard: skip writing if no items have willSell computed (prevents empty/stale cache)
    local hasComputed = false
    for _, it in ipairs(items) do
        if it.willSell ~= nil then hasComputed = true; break end
    end
    if not hasComputed then return false end
    local path = config.getCharStoragePath(getCharName(), SELL_CACHE_FILE)
    if not path then return false end
    local toSell = {}
    for _, it in ipairs(items) do
        if it.willSell and it.name then
            local trimmed = (it.name or ""):match("^%s*(.-)%s*$")
            if trimmed and trimmed ~= "" then
                toSell[#toSell + 1] = (trimmed):gsub("\r", ""):gsub("\n", " ")
            end
        end
    end
    if #toSell == 0 then return false end

    -- Build chunks (slash-delimited names, each chunk under SELL_CACHE_CHUNK_LEN)
    local chunks = {}
    local current = {}
    local currentLen = 0
    for _, name in ipairs(toSell) do
        local addLen = #name + (currentLen > 0 and 1 or 0)
        if currentLen + addLen > SELL_CACHE_CHUNK_LEN and #current > 0 then
            chunks[#chunks + 1] = table.concat(current, "/")
            current = { name }
            currentLen = #name
        else
            current[#current + 1] = name
            currentLen = currentLen + addLen
        end
    end
    if #current > 0 then
        chunks[#chunks + 1] = table.concat(current, "/")
    end

    local lines = {}
    lines[#lines + 1] = "[Meta]"
    lines[#lines + 1] = "savedAt=" .. os.time()
    lines[#lines + 1] = "chunks=" .. #chunks
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[Count]"
    lines[#lines + 1] = "count=" .. #toSell
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[Items]"
    for i, chunk in ipairs(chunks) do
        lines[#lines + 1] = i .. "=" .. chunk
    end
    local body = table.concat(lines, "\n")
    if not file_safe.safeWrite(path, body) then return false end
    -- Also write to sell_config/sell_cache.ini so the sell macro can read it without char path
    local configPath = config.getConfigFile(SELL_CACHE_FILE)
    if configPath and configPath ~= path then
        file_safe.safeWrite(configPath, body)
    end
    return true
end

-- Save bank to char folder (safe write: no throw on disk full / permissions)
local function saveBank(items)
    if not items then return false end
    local path = config.getCharStoragePath(getCharName(), BANK_FILE)
    if not path then return false end
    local content = buildBankContent(items, os.time())
    return file_safe.safeWrite(path, content)
end

-- Merge stored filter status (inKeep, inJunk) into live items by matching name
-- Returns merged items (live items with stored filter status applied where matched)
local function mergeFilterStatus(liveItems, storedItems)
    if not liveItems then return {} end
    if not storedItems or #storedItems == 0 then return liveItems end
    local byName = {}
    for _, it in ipairs(storedItems) do
        local n = (it.name or ""):match("^%s*(.-)%s*$")
        if n ~= "" then byName[n] = it end
    end
    local result = {}
    for _, it in ipairs(liveItems) do
        local dup = {}
        for k, v in pairs(it) do dup[k] = v end
        local stored = byName[(it.name or ""):match("^%s*(.-)%s*$")]
        if stored and (stored.inKeep ~= nil or stored.inJunk ~= nil) then
            if stored.inKeep ~= nil then dup.inKeep = stored.inKeep end
            if stored.inJunk ~= nil then dup.inJunk = stored.inJunk end
        end
        result[#result + 1] = dup
    end
    return result
end

-- Ensure character folder exists (create Chars/CharName if missing)
local function ensureCharFolderExists()
    local folder = getCharFolder()
    if not folder then return false end
    -- Try writing a marker file; if it succeeds, folder exists (safe write avoids throw)
    local markerPath = config.getCharStoragePath(getCharName(), ".exists")
    if file_safe.safeWrite(markerPath, "") then
        pcall(os.remove, markerPath)
        return true
    end
    -- Folder might not exist; try creating via mkdir (Windows: mkdir creates intermediates)
    if os.execute then
        local escaped = folder:gsub('"', '\\"')
        if package.config:sub(1,1) == "\\" then  -- Windows
            os.execute('mkdir "' .. escaped .. '" 2>nul')
        else
            os.execute('mkdir -p "' .. folder .. '" 2>/dev/null')
        end
    end
    return true
end

return {
    init = initStorage,
    getCharName = getCharName,
    getCharFolder = getCharFolder,
    loadInventory = loadInventory,
    loadBank = loadBank,
    saveInventory = saveInventory,
    saveBank = saveBank,
    mergeFilterStatus = mergeFilterStatus,
    ensureCharFolderExists = ensureCharFolderExists,
    writeSellCache = writeSellCache,
}
