-- Kit tests (windows pass phase 7): the type registers (utils/fonts.lua), the 26px window
-- header (components/window_header.lua), the kit button helpers (theme), and the registry's
-- classicOnly gate (§0.3, Command Center).
--
-- Like the other suites this proves balance and behaviour, not pixels:
--   1. Every fonts.push* is popped even when the sized PushFont overload is missing or
--      throwing — the degrade paths must never unbalance the font stack.
--   2. The header draws the contract (title, stat, actions, lock), fires callbacks on
--      click, and survives a throwing callback with its stacks intact.
--   3. Each kit button Push/Pop pair nets to zero styles.
--   4. A classicOnly module is offered in classic, hidden in bars, and force-closed by
--      applyEnabledFromLayout when the mode flips under it.

local repo = os.getenv('COOPT_REPO') or 'C:/Claude/CooptUI'
package.path = repo .. '/lua/?.lua;' .. repo .. '/lua/?/init.lua;'
    .. repo .. '/scripts/tests/?.lua;' .. package.path

local pass, fail = 0, 0
local function check(name, cond, extra)
    if cond then
        pass = pass + 1
        print('PASS: ' .. name)
    else
        fail = fail + 1
        print('FAIL: ' .. name .. (extra and ('  -> ' .. tostring(extra)) or ''))
    end
end

local stub = require('imgui_stub')
stub.install()
package.loaded['mq'] = stub.newMq()

local fonts = require('itemui.utils.fonts')
local theme = require('itemui.utils.theme')
local header = require('itemui.components.window_header')
local registry = require('itemui.core.registry')

-- ---------------------------------------------------------------- fonts: happy path
do
    fonts._resetForTests()
    local r = stub.frame(function()
        fonts.pushHeading()
        fonts.pop()
        fonts.pushMono()
        fonts.pop()
    end)
    check('fonts: heading+mono balanced', stub.balanced(r), stub.imbalance(r))
    check('fonts: sized overload detected on the stub', fonts.sizedFontsAvailable())
end

-- ---------------------------------------------------------------- fonts: degraded paths
do
    -- Sized overload probe fails (GetDefaultFont throws): pushes must degrade to no-ops
    -- for heading, one-arg PushFont for mono, and stay balanced either way.
    fonts._resetForTests()
    stub.throwOn = { GetDefaultFont = true }
    local r = stub.frame(function()
        fonts.pushHeading()
        fonts.pop()
        fonts.pushMono()
        fonts.pop()
    end)
    stub.throwOn = {}
    check('fonts: probe failure degrades but stays balanced', stub.balanced(r), stub.imbalance(r))
    check('fonts: sized overload reported unavailable after failed probe',
        not fonts.sizedFontsAvailable())

    -- PushFont itself throwing mid-frame: pop() must not pop what never pushed.
    fonts._resetForTests()
    stub.throwOn = { PushFont = true }
    local r2 = stub.frame(function()
        fonts.pushHeading()
        fonts.pop()
        fonts.pushMono()
        fonts.pop()
    end)
    stub.throwOn = {}
    check('fonts: throwing PushFont never unbalances', stub.balanced(r2), stub.imbalance(r2))

    -- A pop with nothing pushed is a caller bug but must be inert.
    fonts._resetForTests()
    local r3 = stub.frame(function()
        fonts.pop()
        fonts.pushHeading()
        fonts.pop()
    end)
    check('fonts: stray pop is inert', stub.balanced(r3), stub.imbalance(r3))
end

-- ---------------------------------------------------------------- theme: kit buttons
do
    fonts._resetForTests()
    local r = stub.frame(function()
        for _, push in ipairs({
            theme.PushGoButton, theme.PushStopButton, theme.PushDestroyButton,
            theme.PushActionButton, theme.PushKitDisabledButton, theme.PushIconButton,
        }) do
            push()
            ImGui.Button('kit')
            theme.PopKitButton()
        end
        theme.TextContent('content')
        theme.TextFurniture('furniture')
    end)
    check('theme: six kit button pairs net zero', stub.balanced(r), stub.imbalance(r))
    check('theme: TextContent draws', stub.drew(r, 'content'))
    check('theme: TextFurniture draws', stub.drew(r, 'furniture'))
    check('theme: Kit palette exported', type(theme.Kit) == 'table'
        and type(theme.Kit.OpenBlue) == 'table' and type(theme.Colors.TextContent) == 'table')
end

-- ---------------------------------------------------------------- window header
do
    fonts._resetForTests()
    local opened, refreshed, lockFlips = false, false, 0
    local spec = {
        id = 'bags',
        title = 'Bags',
        stat = '7,399p 0g total',
        actions = {
            { label = 'R', tooltip = 'Rescan', onClick = function() refreshed = true end },
            { label = 'O', onClick = function() opened = true end, disabled = true },
        },
        lock = { locked = false, onToggle = function() lockFlips = lockFlips + 1 end },
    }

    local r = stub.frame(function() header.render(spec) end)
    check('header: balanced', stub.balanced(r), stub.imbalance(r))
    check('header: title drawn', stub.drew(r, 'Bags'))
    check('header: stat drawn', stub.drew(r, '7,399p 0g total'))
    check('header: no errors', r.ok, r.err)

    stub.click = { hdract_bags_1 = true }
    stub.frame(function() header.render(spec) end)
    stub.click = {}
    check('header: action click fires', refreshed)

    stub.click = { hdract_bags_2 = true }
    stub.frame(function() header.render(spec) end)
    stub.click = {}
    check('header: disabled action does not fire', not opened)

    stub.click = { hdrlock_bags = true }
    stub.frame(function() header.render(spec) end)
    stub.click = {}
    check('header: lock toggles', lockFlips == 1)

    -- A throwing onClick must not leak stacks or kill the frame.
    spec.actions[1].onClick = function() error('boom') end
    stub.click = { hdract_bags_1 = true }
    local r2 = stub.frame(function() header.render(spec) end)
    stub.click = {}
    check('header: throwing onClick contained', r2.ok and stub.balanced(r2),
        (r2.err or '') .. ' ' .. stub.imbalance(r2))

    local r3 = stub.frame(function() header.render({ title = 'Bare' }) end)
    check('header: minimal spec renders', r3.ok and stub.balanced(r3),
        (r3.err or '') .. ' ' .. stub.imbalance(r3))

    local r4 = stub.frame(function() header.render(nil) end)
    check('header: nil spec is inert', r4.ok, r4.err)
end

-- ---------------------------------------------------------------- registry: classicOnly
do
    local layoutConfig = { UIMode = 'classic' }
    registry.init({ layoutConfig = layoutConfig, companionWindowOpenedAt = {} })
    registry.register({
        id = 'kitTestClassicOnly', label = 'CC', classicOnly = true,
        render = function() end,
    })
    registry.register({
        id = 'kitTestAlways', label = 'Always',
        render = function() end,
    })

    local function listed(id)
        for _, m in ipairs(registry.getEnabledModules()) do
            if m.id == id then return true end
        end
        return false
    end

    check('registry: classicOnly offered in classic', listed('kitTestClassicOnly'))
    layoutConfig.UIMode = 'bars'
    registry.applyEnabledFromLayout(layoutConfig)
    check('registry: classicOnly hidden in bars', not listed('kitTestClassicOnly'))
    check('registry: plain module unaffected by mode', listed('kitTestAlways'))

    -- Open it in classic, flip to bars: applyEnabledFromLayout must close it.
    layoutConfig.UIMode = 'classic'
    registry.applyEnabledFromLayout(layoutConfig)
    registry.toggleWindow('kitTestClassicOnly')
    check('registry: opens in classic', registry.isOpen('kitTestClassicOnly'))
    layoutConfig.UIMode = 'bars'
    registry.applyEnabledFromLayout(layoutConfig)
    check('registry: closed by the mode flip', not registry.isOpen('kitTestClassicOnly'))
    check('registry: not drawable in bars', (function()
        for _, m in ipairs(registry.getDrawableModules()) do
            if m.id == 'kitTestClassicOnly' then return false end
        end
        return true
    end)())
end

-- ---------------------------------------------------------------- summary
local missing = {}
for k, v in pairs(stub.missing) do missing[#missing + 1] = k .. 'x' .. v end
if #missing > 0 then print('\nunstubbed ImGui calls seen: ' .. table.concat(missing, ', ')) end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
