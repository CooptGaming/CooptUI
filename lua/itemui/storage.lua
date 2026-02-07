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
    s = s:gsub("\\", "\\\\")
    s = s:gsub('"', '\\"')
    s = s:gsub("\n", "\\n")
    s = s:gsub("\r", "\\r")
    return '"' .. s .. '"'
end

-- Serialize one item to Lua table literal (all properties from iteminfo.mac)
local function serializeItem(it)
    local parts = {}
    parts[#parts + 1] = string.format("bag=%d", it.bag or 0)
    parts[#parts + 1] = string.format("slot=%d", it.slot or 0)
    parts[#parts + 1] = "name=" .. escapeLuaString(it.name)
    parts[#parts + 1] = string.format("id=%d", it.id or 0)
    parts[#parts + 1] = string.format("value=%d", it.value or 0)
    parts[#parts + 1] = string.format("totalValue=%d", it.totalValue or 0)
    parts[#parts + 1] = string.format("stackSize=%d", it.stackSize or 1)
    parts[#parts + 1] = string.format("stackSizeMax=%d", it.stackSizeMax or 1)
    parts[#parts + 1] = "type=" .. escapeLuaString(it.type)
    parts[#parts + 1] = string.format("weight=%d", it.weight or 0)
    parts[#parts + 1] = string.format("icon=%d", it.icon or 0)
    parts[#parts + 1] = "itemLink=" .. escapeLuaString(it.itemLink or "")
    parts[#parts + 1] = string.format("tribute=%d", it.tribute or 0)
    parts[#parts + 1] = string.format("size=%d", it.size or 0)
    parts[#parts + 1] = string.format("sizeCapacity=%d", it.sizeCapacity or 0)
    parts[#parts + 1] = string.format("container=%d", it.container or 0)
    parts[#parts + 1] = string.format("nodrop=%s", it.nodrop and "true" or "false")
    parts[#parts + 1] = string.format("notrade=%s", it.notrade and "true" or "false")
    parts[#parts + 1] = string.format("norent=%s", it.norent and "true" or "false")
    parts[#parts + 1] = string.format("lore=%s", it.lore and "true" or "false")
    parts[#parts + 1] = string.format("magic=%s", it.magic and "true" or "false")
    parts[#parts + 1] = string.format("attuneable=%s", it.attuneable and "true" or "false")
    parts[#parts + 1] = string.format("heirloom=%s", it.heirloom and "true" or "false")
    parts[#parts + 1] = string.format("prestige=%s", it.prestige and "true" or "false")
    parts[#parts + 1] = string.format("collectible=%s", it.collectible and "true" or "false")
    parts[#parts + 1] = string.format("quest=%s", it.quest and "true" or "false")
    parts[#parts + 1] = string.format("tradeskills=%s", it.tradeskills and "true" or "false")
    parts[#parts + 1] = "class=" .. escapeLuaString(it.class or "")
    parts[#parts + 1] = "race=" .. escapeLuaString(it.race or "")
    parts[#parts + 1] = "wornSlots=" .. escapeLuaString(it.wornSlots or "")
    parts[#parts + 1] = string.format("requiredLevel=%d", it.requiredLevel or 0)
    parts[#parts + 1] = string.format("recommendedLevel=%d", it.recommendedLevel or 0)
    parts[#parts + 1] = string.format("augSlots=%d", it.augSlots or 0)
    parts[#parts + 1] = string.format("clicky=%d", it.clicky or 0)
    parts[#parts + 1] = string.format("proc=%d", it.proc or 0)
    parts[#parts + 1] = string.format("focus=%d", it.focus or 0)
    parts[#parts + 1] = string.format("worn=%d", it.worn or 0)
    parts[#parts + 1] = string.format("spell=%d", it.spell or 0)
    parts[#parts + 1] = "instrumentType=" .. escapeLuaString(it.instrumentType or "")
    parts[#parts + 1] = string.format("instrumentMod=%d", it.instrumentMod or 0)
    -- Item stats (so tooltip and views show full stats when loading from persistence)
    parts[#parts + 1] = string.format("ac=%d", it.ac or 0)
    parts[#parts + 1] = string.format("hp=%d", it.hp or 0)
    parts[#parts + 1] = string.format("mana=%d", it.mana or 0)
    parts[#parts + 1] = string.format("endurance=%d", it.endurance or 0)
    parts[#parts + 1] = string.format("str=%d", it.str or 0)
    parts[#parts + 1] = string.format("sta=%d", it.sta or 0)
    parts[#parts + 1] = string.format("agi=%d", it.agi or 0)
    parts[#parts + 1] = string.format("dex=%d", it.dex or 0)
    parts[#parts + 1] = string.format("int=%d", it.int or 0)
    parts[#parts + 1] = string.format("wis=%d", it.wis or 0)
    parts[#parts + 1] = string.format("cha=%d", it.cha or 0)
    parts[#parts + 1] = string.format("attack=%d", it.attack or 0)
    parts[#parts + 1] = string.format("accuracy=%d", it.accuracy or 0)
    parts[#parts + 1] = string.format("avoidance=%d", it.avoidance or 0)
    parts[#parts + 1] = string.format("shielding=%d", it.shielding or 0)
    parts[#parts + 1] = string.format("haste=%d", it.haste or 0)
    parts[#parts + 1] = string.format("damage=%d", it.damage or 0)
    parts[#parts + 1] = string.format("itemDelay=%d", it.itemDelay or 0)
    parts[#parts + 1] = string.format("dmgBonus=%d", it.dmgBonus or 0)
    parts[#parts + 1] = string.format("spellDamage=%d", it.spellDamage or 0)
    parts[#parts + 1] = string.format("strikeThrough=%d", it.strikeThrough or 0)
    parts[#parts + 1] = string.format("damageShield=%d", it.damageShield or 0)
    parts[#parts + 1] = string.format("combatEffects=%d", it.combatEffects or 0)
    parts[#parts + 1] = string.format("dotShielding=%d", it.dotShielding or 0)
    parts[#parts + 1] = string.format("hpRegen=%d", it.hpRegen or 0)
    parts[#parts + 1] = string.format("manaRegen=%d", it.manaRegen or 0)
    parts[#parts + 1] = string.format("enduranceRegen=%d", it.enduranceRegen or 0)
    parts[#parts + 1] = string.format("heroicSTR=%d", it.heroicSTR or 0)
    parts[#parts + 1] = string.format("heroicSTA=%d", it.heroicSTA or 0)
    parts[#parts + 1] = string.format("heroicAGI=%d", it.heroicAGI or 0)
    parts[#parts + 1] = string.format("heroicDEX=%d", it.heroicDEX or 0)
    parts[#parts + 1] = string.format("heroicINT=%d", it.heroicINT or 0)
    parts[#parts + 1] = string.format("heroicWIS=%d", it.heroicWIS or 0)
    parts[#parts + 1] = string.format("heroicCHA=%d", it.heroicCHA or 0)
    parts[#parts + 1] = string.format("svMagic=%d", it.svMagic or 0)
    parts[#parts + 1] = string.format("svFire=%d", it.svFire or 0)
    parts[#parts + 1] = string.format("svCold=%d", it.svCold or 0)
    parts[#parts + 1] = string.format("svPoison=%d", it.svPoison or 0)
    parts[#parts + 1] = string.format("svDisease=%d", it.svDisease or 0)
    parts[#parts + 1] = string.format("svCorruption=%d", it.svCorruption or 0)
    -- Filter status (for sell view)
    if it.inKeep ~= nil then parts[#parts + 1] = string.format("inKeep=%s", it.inKeep and "true" or "false") end
    if it.inJunk ~= nil then parts[#parts + 1] = string.format("inJunk=%s", it.inJunk and "true" or "false") end
    if it.isProtected ~= nil then parts[#parts + 1] = string.format("isProtected=%s", it.isProtected and "true" or "false") end
    -- Sell cache: computed sell status (for sell macro)
    if it.willSell ~= nil then parts[#parts + 1] = string.format("willSell=%s", it.willSell and "true" or "false") end
    if it.sellReason ~= nil and it.sellReason ~= "" then parts[#parts + 1] = "sellReason=" .. escapeLuaString(it.sellReason) end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- Build Lua file content
local function buildInventoryContent(items, savedAt)
    savedAt = savedAt or os.time()
    local lines = {"-- ItemUI inventory snapshot. Do not edit manually.", "return {"}
    lines[#lines + 1] = "  savedAt=" .. savedAt .. ","
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

-- Load inventory from char folder
local function loadInventory()
    local path = config.getCharStoragePath(getCharName(), INVENTORY_FILE)
    local data = loadLuaFile(path)
    if not data or not data.items then return nil, nil end
    return data.items, data.savedAt
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

-- Save inventory to char folder (safe write: no throw on disk full / permissions)
local function saveInventory(items)
    if not items then return false end
    local t0 = mq.gettime()
    local path = config.getCharStoragePath(getCharName(), INVENTORY_FILE)
    if not path then return false end
    local content = buildInventoryContent(items, os.time())
    local ok = file_safe.safeWrite(path, content)
    local e = mq.gettime() - t0
    if ok and profileConfig.enabled and e >= profileConfig.thresholdMs then
        print(string.format("\ag[ItemUI Profile]\ax storage.saveInventory: %d ms (%d items)", e, #items))
    end
    return ok
end

local SELL_CACHE_FILE = "sell_cache.ini"

-- Write macro-readable sell list INI (only item names with willSell == true).
-- Path: Macros/sell_config/Chars/<CharName>/sell_cache.ini
-- Format: [Meta] savedAt=... ; [Count] count=N ; [Items] 1=Name1 2=Name2 ...
local function writeSellCache(items)
    if not items or #items == 0 then return false end
    local path = config.getCharStoragePath(getCharName(), SELL_CACHE_FILE)
    if not path then return false end
    local toSell = {}
    for _, it in ipairs(items) do
        if it.willSell and it.name and (it.name or ""):match("^%s*(.-)%s*$") ~= "" then
            toSell[#toSell + 1] = (it.name or ""):match("^%s*(.-)%s*$")
        end
    end
    local lines = {}
    lines[#lines + 1] = "[Meta]"
    lines[#lines + 1] = "savedAt=" .. os.time()
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[Count]"
    lines[#lines + 1] = "count=" .. #toSell
    lines[#lines + 1] = ""
    lines[#lines + 1] = "[Items]"
    for i, name in ipairs(toSell) do
        -- INI value: escape only newlines; EQ item names rarely have = or ]
        local safe = (name or ""):gsub("\r", ""):gsub("\n", " ")
        lines[#lines + 1] = i .. "=" .. safe
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
