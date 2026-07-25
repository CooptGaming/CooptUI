--[[
    Skin sync - install/refresh the CoOpt native skin into the EQ client.

    Releases (patcher manifest, zips, EMU deploy) only write under the
    MacroQuest root, but /loadskin loads from <EverQuest>\uifiles\<skin>.
    This service copies <MQ root>\uifiles\coopt into <EQ>\uifiles\coopt
    whenever a file is missing or its contents differ, and deletes skin
    files we shipped once but have since retired (e.g. the trialed
    loot-window strip), so stale overrides can't linger with dead controls.

    One shot at startup (app.lua); pure file I/O, no polling. Copying while
    a skin is loaded is safe - EQ reads skin XML only at /loadskin time.
    Degrades to a silent no-op when either path or the source folder is
    missing (skin not patched in yet).
]]

local mq = require('mq')

local M = {}

-- Shipped once, later removed from the skin; deleted from the EQ copy on sync.
local REMOVED_FILES = { 'EQUI_LootWnd.xml', 'EQUI_ItemDisplay.xml' }
-- Fallback listing when lfs is unavailable: the current skin files.
local STATIC_FILES = { 'EQUI_ActionsWindow.xml', 'EQUI_MerchantWnd.xml', 'EQUI_TipWnd.xml' }

local function readAll(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

-- Skin file names from the source folder (lfs when present, static list otherwise).
local function listSkinFiles(srcDir)
    local okLfs, lfs = pcall(require, 'lfs')
    if not (okLfs and type(lfs) == 'table') then lfs = nil end
    if lfs and lfs.dir then
        local names = {}
        local okIter = pcall(function()
            for name in lfs.dir(srcDir) do
                if name:lower():match('%.xml$') then names[#names + 1] = name end
            end
        end)
        if okIter and #names > 0 then return names, lfs end
    end
    return STATIC_FILES, lfs
end

--- Copy changed/missing skin files MQ -> EQ and remove retired ones.
--- Returns { copied = {...}, removed = {...}, freshInstall = bool },
--- or nil when there was nothing to do (or nothing could be done).
function M.sync()
    local mqPath = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    local eqPath = mq.TLO and mq.TLO.EverQuest and mq.TLO.EverQuest.Path and mq.TLO.EverQuest.Path()
    if not mqPath or mqPath == '' or not eqPath or eqPath == '' then return nil end
    local srcDir = tostring(mqPath):gsub('[\\/]+$', '') .. '\\uifiles\\coopt'
    local dstDir = tostring(eqPath):gsub('[\\/]+$', '') .. '\\uifiles\\coopt'
    -- MQ installed inside the EQ folder: the skin is already where EQ wants it.
    if srcDir:lower() == dstDir:lower() then return nil end

    local names, lfs = listSkinFiles(srcDir)
    local copied, removed = {}, {}
    local freshInstall = false
    local dirReady = false
    -- <EQ>\uifiles always exists (the default UI lives there); only 'coopt'
    -- may need creating. Without lfs we can't mkdir; the io.open below then
    -- fails closed and the sync is a no-op rather than an error.
    local function ensureDstDir()
        if dirReady then return end
        if lfs and lfs.attributes and not lfs.attributes(dstDir, 'mode') then
            freshInstall = true
            if lfs.mkdir then pcall(lfs.mkdir, dstDir) end
        end
        dirReady = true
    end

    for _, name in ipairs(names) do
        local srcData = readAll(srcDir .. '\\' .. name)
        if srcData then
            local dstFile = dstDir .. '\\' .. name
            if readAll(dstFile) ~= srcData then
                ensureDstDir()
                local f = io.open(dstFile, 'wb')
                if f then
                    f:write(srcData)
                    f:close()
                    copied[#copied + 1] = name
                end
            end
        end
    end
    for _, name in ipairs(REMOVED_FILES) do
        if os.remove(dstDir .. '\\' .. name) then removed[#removed + 1] = name end
    end
    if #copied == 0 and #removed == 0 then return nil end
    return { copied = copied, removed = removed, freshInstall = freshInstall }
end

return M
