--[[
    Favorites Service - user-defined clicky/favorites lists.

    Named per-character lists of items (id + name), e.g. "Buffs" and "Damage".
    The Clickies Companion shows each list with one-click activation, and every
    item on ANY list is protected from selling (rules.lua "Favorites" layer)
    and from the Delete menu until removed from its lists.

    Persistence: <char storage>/clicky_lists.lua, next to reroll_lists.lua.
    Matching is by item ID only (same policy as the reroll lists: same-name-
    different-id items are common on EQEmu servers).
--]]

local mq = require('mq')

local M = {}

local deps = {}          -- { getStoragePath(char, file), onChanged() }
local lists = {}         -- ordered: { { name = "Buffs", items = { {id=, name=}, ... } }, ... }
local loadedFor = nil    -- character the current lists belong to
local idSetCache = nil

function M.init(d)
    deps = d or {}
end

local function charName()
    local n = mq.TLO and mq.TLO.Me and mq.TLO.Me.Name and mq.TLO.Me.Name()
    if n and n ~= "" then return n end
    return nil
end

local function storagePath()
    local c = charName()
    if not c or not deps.getStoragePath then return nil end
    return deps.getStoragePath(c, "clicky_lists.lua")
end

local function saveToFile()
    local path = storagePath()
    if not path then return end
    local out = { "-- CoOpt UI clicky/favorites lists. Do not edit manually.", "return {", "  lists = {" }
    for _, l in ipairs(lists) do
        out[#out + 1] = string.format("    { name = %q, items = {", l.name)
        for _, it in ipairs(l.items) do
            out[#out + 1] = string.format("      { id = %d, name = %q },", it.id, it.name or "")
        end
        out[#out + 1] = "    } },"
    end
    out[#out + 1] = "  }"
    out[#out + 1] = "}"
    local f = io.open(path, "w")
    if f then
        f:write(table.concat(out, "\n"))
        f:close()
    end
end

local function ensureLoaded()
    local c = charName()
    if not c or loadedFor == c then return end
    loadedFor = c
    lists = {}
    idSetCache = nil
    local path = storagePath()
    if not path then return end
    local okChunk, chunk = pcall(loadfile, path)
    if not okChunk or not chunk then return end
    local okRun, data = pcall(chunk)
    if not okRun or type(data) ~= "table" or type(data.lists) ~= "table" then return end
    for _, l in ipairs(data.lists) do
        if type(l) == "table" and type(l.name) == "string" and l.name ~= "" then
            local items = {}
            for _, it in ipairs(l.items or {}) do
                local id = tonumber(it.id)
                if id then items[#items + 1] = { id = id, name = tostring(it.name or "") } end
            end
            lists[#lists + 1] = { name = l.name, items = items }
        end
    end
end

local function changed()
    idSetCache = nil
    saveToFile()
    if deps.onChanged then deps.onChanged() end
end

--- Ordered list-of-lists (do not modify).
function M.getLists()
    ensureLoaded()
    return lists
end

function M.findList(name)
    ensureLoaded()
    for _, l in ipairs(lists) do
        if l.name == name then return l end
    end
    return nil
end

function M.createList(name)
    ensureLoaded()
    name = (name or ""):match("^%s*(.-)%s*$") or ""
    if name == "" or M.findList(name) then return false end
    lists[#lists + 1] = { name = name, items = {} }
    changed()
    return true
end

--- Only empty lists can be deleted (remove items first; keeps protection honest).
function M.deleteList(name)
    ensureLoaded()
    for i, l in ipairs(lists) do
        if l.name == name then
            if #l.items > 0 then return false end
            table.remove(lists, i)
            changed()
            return true
        end
    end
    return false
end

function M.addItem(listName, id, itemName)
    ensureLoaded()
    id = tonumber(id)
    if not id then return false end
    local l = M.findList(listName)
    if not l then return false end
    for _, it in ipairs(l.items) do
        if it.id == id then return false end
    end
    l.items[#l.items + 1] = { id = id, name = itemName or "" }
    changed()
    return true
end

function M.removeItem(listName, id)
    ensureLoaded()
    id = tonumber(id)
    local l = M.findList(listName)
    if not l or not id then return false end
    for i, it in ipairs(l.items) do
        if it.id == id then
            table.remove(l.items, i)
            changed()
            return true
        end
    end
    return false
end

--- id -> true for every item on any list (sell/delete protection; cached).
function M.getProtectedIdSet()
    ensureLoaded()
    if idSetCache then return idSetCache end
    local set = {}
    for _, l in ipairs(lists) do
        for _, it in ipairs(l.items) do
            set[it.id] = true
        end
    end
    idSetCache = set
    return set
end

function M.isProtected(id)
    id = tonumber(id)
    if not id then return false end
    return M.getProtectedIdSet()[id] == true
end

--- Set of list names containing this id (for menu checkmarks).
function M.listsContaining(id)
    ensureLoaded()
    id = tonumber(id)
    local out = {}
    if not id then return out end
    for _, l in ipairs(lists) do
        for _, it in ipairs(l.items) do
            if it.id == id then
                out[l.name] = true
                break
            end
        end
    end
    return out
end

return M
