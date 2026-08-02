-- Regression test for lua/itemui/services/skin_sync.lua
-- Runs on the exact LuaJIT MQ links against. Uses a fake MQ root + fake EQ root
-- on disk, and stubs require('mq') with the two TLO paths skin_sync reads.
--
-- Covers the two defects fixed in this pass:
--   1. first install must work WITHOUT lfs (os.execute mkdir fallback)
--   2. a file must never be left missing when the tmp->dst rename fails
-- plus the pre-existing contracts (no-op when not installed, incremental copy,
-- retired-file removal) so the fix is shown not to have broken them.

local repo = assert(os.getenv('COOPT_REPO'), 'set COOPT_REPO')
local tmp  = assert(os.getenv('COOPT_TMP'), 'set COOPT_TMP')

package.path = repo .. '\\lua\\?.lua;' .. repo .. '\\lua\\?\\init.lua;' .. package.path

local MQ_ROOT = tmp .. '\\mq'
local EQ_ROOT = tmp .. '\\eq'

local function sh(cmd) os.execute(cmd .. ' >nul 2>nul') end
local function mkdir(d) sh('mkdir "' .. d .. '"') end
local function write(path, data)
    local f = assert(io.open(path, 'wb'), 'open ' .. path)
    f:write(data); f:close()
end
local function read(path)
    local f = io.open(path, 'rb'); if not f then return nil end
    local d = f:read('*a'); f:close(); return d
end
local function exists(p) local f = io.open(p, 'rb'); if f then f:close(); return true end return false end

-- Stub the MQ host module.
package.loaded['mq'] = {
    TLO = {
        MacroQuest = { Path = function() return MQ_ROOT end },
        EverQuest  = { Path = function() return EQ_ROOT end },
    },
}
-- Force the no-lfs path: this is the environment the old code silently failed in.
package.preload['lfs'] = function() error('no lfs in this MQ2Lua build') end

local skin = require('itemui.services.skin_sync')

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then pass = pass + 1; print('PASS: ' .. name)
    else fail = fail + 1; print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or '')) end
end

-- Build the source skin under the fake MQ root.
mkdir(MQ_ROOT .. '\\uifiles\\coopt')
mkdir(EQ_ROOT .. '\\uifiles')
local SRC = MQ_ROOT .. '\\uifiles\\coopt'
local DST = EQ_ROOT .. '\\uifiles\\coopt'
write(SRC .. '\\EQUI_AAWindow.xml',     '<AA v1/>')
write(SRC .. '\\EQUI_ActionsWindow.xml', '<Actions v1/>')
write(SRC .. '\\EQUI_MerchantWnd.xml',  '<Merchant v1/>')
write(SRC .. '\\EQUI_TipWnd.xml',       '<Tip v1/>')

-- 1. Opt-in contract: with no <EQ>\uifiles\coopt, a maintenance sync installs nothing.
local res = skin.sync()
check('maintenance sync never installs uninvited', res == nil and not exists(DST .. '\\EQUI_AAWindow.xml'))
check('isInstalled() false before install', skin.isInstalled() == false)

-- 2. force install must succeed with NO lfs available (the regression).
local res2, err2 = skin.sync({ force = true })
check('force install returns a result without lfs', res2 ~= nil, err2)
check('force install reports no error', err2 == nil, err2)
if res2 then
    check('force install marked freshInstall', res2.freshInstall == true)
    check('force install copied all 4 skin files', #res2.copied == 4, res2 and #res2.copied)
    check('force install recorded no failures', #res2.failed == 0)
end
check('AAWindow landed in EQ dir', read(DST .. '\\EQUI_AAWindow.xml') == '<AA v1/>')
check('MerchantWnd landed in EQ dir', read(DST .. '\\EQUI_MerchantWnd.xml') == '<Merchant v1/>')
check('isInstalled() true after install', skin.isInstalled() == true)

-- 3. Idempotence: a second sync with identical content is a no-op.
check('re-sync with no changes is a no-op', skin.sync() == nil)

-- 4. Incremental: only the changed file is copied, and the swap leaves it intact.
write(SRC .. '\\EQUI_MerchantWnd.xml', '<Merchant v2/>')
local res3 = skin.sync()
check('changed file triggers a copy', res3 ~= nil and #res3.copied == 1, res3 and #res3.copied)
check('changed file has new content', read(DST .. '\\EQUI_MerchantWnd.xml') == '<Merchant v2/>')
check('unchanged file untouched', read(DST .. '\\EQUI_AAWindow.xml') == '<AA v1/>')
check('no .tmp left behind', not exists(DST .. '\\EQUI_MerchantWnd.xml.tmp'))

-- 5. Retired files shipped once are removed from the EQ copy.
write(DST .. '\\EQUI_LootWnd.xml', '<stale/>')
local res4 = skin.sync()
check('retired file removed', res4 ~= nil and #res4.removed == 1, res4 and #res4.removed)
check('retired file gone from disk', not exists(DST .. '\\EQUI_LootWnd.xml'))

-- 6. The destination is never left missing when the swap cannot complete.
--    Simulate a failing rename by making os.rename always fail, the exact condition
--    under which the old code deleted the destination and then gave up.
write(SRC .. '\\EQUI_TipWnd.xml', '<Tip v2/>')
local realRename = os.rename
os.rename = function() return nil, 'simulated rename failure' end
local res5, err5 = skin.sync()
os.rename = realRename
check('rename failure still delivers the file', read(DST .. '\\EQUI_TipWnd.xml') == '<Tip v2/>',
      'content=' .. tostring(read(DST .. '\\EQUI_TipWnd.xml')))
check('rename failure counted as copied, not failed', res5 ~= nil and #res5.copied == 1 and #res5.failed == 0, err5)
check('no .tmp left behind after recovery', not exists(DST .. '\\EQUI_TipWnd.xml.tmp'))

print(('\n%d passed, %d failed'):format(pass, fail))
os.exit(fail == 0 and 0 or 1)
