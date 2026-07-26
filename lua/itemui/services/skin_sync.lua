--[[
    Skin sync - keep an OPT-IN copy of the CoOpt native skin fresh in the EQ client.

    Releases (patcher manifest, zips, EMU deploy) ship the skin under the
    MacroQuest root, but /loadskin loads from <EverQuest>\uifiles\<skin>.
    The skin is OPTIONAL: nothing is ever written into the EQ client unless
    the user opted in - either by installing via the Settings button
    (sync{force=true}) or by copying uifiles\coopt over themselves.

    Once a <EQ>\uifiles\coopt folder exists, sync() keeps it current: copies
    files whose contents differ and deletes skin files we shipped once but
    have since retired (e.g. the trialed loot-window strip), so stale
    overrides can't linger with dead controls. Without that folder, sync()
    is a no-op - it never installs uninvited.

    One shot at startup (app.lua) plus the Settings button; pure file I/O,
    no polling. Copying while a skin is loaded is safe - EQ reads skin XML
    only at /loadskin time.
]]

local mq = require('mq')

local M = {}

-- Shipped once, later removed from the skin; deleted from the EQ copy on sync.
local REMOVED_FILES = { 'EQUI_LootWnd.xml', 'EQUI_ItemDisplay.xml' }
-- Fallback listing when lfs is unavailable: the current skin files.
local STATIC_FILES = { 'EQUI_AAWindow.xml', 'EQUI_ActionsWindow.xml', 'EQUI_MerchantWnd.xml', 'EQUI_TipWnd.xml' }

local function readAll(path)
    local f = io.open(path, 'rb')
    if not f then return nil end
    local data = f:read('*a')
    f:close()
    return data
end

local function getLfs()
    local ok, lfs = pcall(require, 'lfs')
    if ok and type(lfs) == 'table' then return lfs end
    return nil
end

local function paths()
    local mqPath = mq.TLO and mq.TLO.MacroQuest and mq.TLO.MacroQuest.Path and mq.TLO.MacroQuest.Path()
    local eqPath = mq.TLO and mq.TLO.EverQuest and mq.TLO.EverQuest.Path and mq.TLO.EverQuest.Path()
    if not mqPath or mqPath == '' or not eqPath or eqPath == '' then return nil end
    local srcDir = tostring(mqPath):gsub('[\\/]+$', '') .. '\\uifiles\\coopt'
    local dstDir = tostring(eqPath):gsub('[\\/]+$', '') .. '\\uifiles\\coopt'
    return srcDir, dstDir
end

local function dirExists(dir, lfs)
    if lfs and lfs.attributes then
        return lfs.attributes(dir, 'mode') == 'directory'
    end
    -- Without lfs: probe for any known skin file (good enough - a manual
    -- install that diverged still counts as installed).
    for _, name in ipairs(STATIC_FILES) do
        local f = io.open(dir .. '\\' .. name, 'rb')
        if f then f:close(); return true end
    end
    return false
end

-- Skin file names from the source folder (lfs when present, static list otherwise).
local function listSkinFiles(srcDir, lfs)
    if lfs and lfs.dir then
        local names = {}
        local okIter = pcall(function()
            for name in lfs.dir(srcDir) do
                if name:lower():match('%.xml$') then names[#names + 1] = name end
            end
        end)
        if okIter and #names > 0 then return names end
    end
    return STATIC_FILES
end

--- True when the user has the skin in the EQ client (i.e. opted in).
function M.isInstalled()
    local srcDir, dstDir = paths()
    if not dstDir then return false end
    if srcDir and srcDir:lower() == dstDir:lower() then return true end
    return dirExists(dstDir, getLfs())
end

--- Copy changed/missing skin files MQ -> EQ and remove retired ones.
--- Default: maintenance only - a no-op unless <EQ>\uifiles\coopt already
--- exists (the skin is opt-in). opts.force = true performs a first install
--- (creates the folder). Returns { copied = {...}, removed = {...},
--- freshInstall = bool }, or nil when there was nothing to do.
function M.sync(opts)
    local force = opts and opts.force or false
    local srcDir, dstDir = paths()
    if not srcDir then return nil end
    -- MQ installed inside the EQ folder: the skin is already where EQ wants it.
    if srcDir:lower() == dstDir:lower() then return nil end

    local lfs = getLfs()
    local installed = dirExists(dstDir, lfs)
    if not installed and not force then return nil end

    local freshInstall = false
    if not installed then
        -- <EQ>\uifiles always exists (the default UI lives there); only
        -- 'coopt' needs creating. Without lfs the io.open below fails closed
        -- and the install is reported as a no-op rather than an error.
        freshInstall = true
        if lfs and lfs.mkdir then pcall(lfs.mkdir, dstDir) end
    end

    local copied, removed = {}, {}
    for _, name in ipairs(listSkinFiles(srcDir, lfs)) do
        local srcData = readAll(srcDir .. '\\' .. name)
        if srcData then
            local dstFile = dstDir .. '\\' .. name
            if readAll(dstFile) ~= srcData then
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
