-- The onboarding wizard's navigation: views/tutorial.lua's SEQUENCE walk.
--
-- WHY THIS FILE EXISTS. Cutting the wizard from thirteen steps to four, I rewrote the nav to
-- be sequence-driven and called saveLayoutForView("Inventory") without a width or height.
-- That function assigns its arguments straight through, so the call wrote NIL over
-- WidthInventory and the shared Height. It reached the field as "the Inventory Companion
-- keeps getting resized" -- the window was not being resized, its saved size was being
-- erased, and the next launch fell back to a default.
--
-- Nothing caught it: the file compiles, it lints, saveLayoutForView(view) is a legal call, and
-- the wizard had no test at all. Only exercising the walk catches this class, so here it is.

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
package.loaded['itemui.core.welcome_env_manifest'] = { validate = function() return {} end }

local registryCalls = {}
package.loaded['itemui.core.registry'] = {
    setWindowState = function(id, open, vis) registryCalls[#registryCalls + 1] = { id = id, open = open, vis = vis } end,
    isOpen = function() return false end,
    isRegistered = function() return true end,
    getEnabledModules = function() return {} end,
}

local tutorial = require('itemui.views.tutorial')
local theme = require('itemui.utils.theme')

-- ---------------------------------------------------------------- fixtures
local saved = {}
local function newRefs(step, winW, winH)
    stub.windowSize = { winW or 900, winH or 600 }
    return {
        uiState = { setupStep = step, setupMode = true },
        theme = theme,
        ImGui = _G.ImGui,
        saveLayoutForView = function(view, w, h)
            saved[#saved + 1] = { view = view, w = w, h = h }
        end,
        recordCompanionWindowOpened = function() end,
        setOnboardingComplete = function() end,
    }
end

local function walk(refs)
    local r = stub.frame(function() tutorial.renderSetupBar(refs) end)
    return r
end

-- =================================================================
-- 1. The sequence itself
-- =================================================================
do
    local refs = newRefs(2)
    local r = walk(refs)
    check('step 2 renders nav and is balanced', stub.balanced(r), stub.imbalance(r))
    check('step 2 is "Step 1 of 4"', stub.drew(r, 'Step 1 of 4'), table.concat(r.texts or {}, '|'))
    check('the first step offers no Back', not stub.drew(r, 'Back##TutorialBar'),
        table.concat(r.buttons, '|'))

    -- A step outside SEQUENCE gets no nav at all -- there is nowhere in the walk for it to go.
    local orphan = newRefs(9)
    local ro = walk(orphan)
    check('a retired step draws no nav', not stub.drew(ro, 'Next##TutorialBar')
        and not stub.drew(ro, 'Save & Finish##TutorialBar'), table.concat(ro.buttons, '|'))
    check('a retired step is still balanced', stub.balanced(ro), stub.imbalance(ro))
end

-- =================================================================
-- 2. THE REGRESSION. Advancing must save the live size, never nil.
-- =================================================================
do
    saved = {}
    local refs = newRefs(2, 1024, 720)
    stub.click = { ['Next##TutorialBar'] = true }
    walk(refs)
    stub.click = {}

    check('step 2 saves exactly one view', #saved == 1, #saved)
    local s1 = saved[1]
    check('step 2 saves Inventory', s1 and s1.view == 'Inventory', s1 and s1.view)
    -- The whole point. A nil here is the defect.
    check('step 2 saves a real WIDTH, not nil', type(s1 and s1.w) == 'number' and s1.w > 0,
        tostring(s1 and s1.w))
    check('step 2 saves a real HEIGHT, not nil', type(s1 and s1.h) == 'number' and s1.h > 0,
        tostring(s1 and s1.h))
    check('step 2 advances to step 4', refs.uiState.setupStep == 4, refs.uiState.setupStep)

    saved = {}
    local refs4 = newRefs(4, 880, 640)
    stub.click = { ['Next##TutorialBar'] = true }
    walk(refs4)
    stub.click = {}
    check('step 4 saves Sell with real numbers',
        #saved == 1 and saved[1].view == 'Sell'
        and type(saved[1].w) == 'number' and saved[1].w > 0
        and type(saved[1].h) == 'number' and saved[1].h > 0,
        saved[1] and (tostring(saved[1].view) .. '/' .. tostring(saved[1].w)))
end

-- =================================================================
-- 3. Bank and the all-windows step save THEMSELVES, so the wizard must not
--    call saveLayoutForView for them -- it has no Bank branch, so such a call
--    writes nothing but still rewrites the file.
-- =================================================================
do
    saved = {}
    registryCalls = {}
    local refs = newRefs(4)
    stub.click = { ['Next##TutorialBar'] = true }
    walk(refs)              -- 4 -> 6, which is the Bank step
    stub.click = {}
    check('arriving at the Bank step opens the Bank companion',
        (function()
            for _, c in ipairs(registryCalls) do
                if c.id == 'bank' and c.open == true then return true end
            end
            return false
        end)(), #registryCalls)

    saved = {}
    local refs6 = newRefs(6)
    stub.click = { ['Next##TutorialBar'] = true }
    walk(refs6)
    stub.click = {}
    check('the Bank step saves nothing through saveLayoutForView', #saved == 0,
        saved[1] and saved[1].view)
    check('the Bank step advances to the all-windows step', refs6.uiState.setupStep == 8,
        refs6.uiState.setupStep)
end

-- =================================================================
-- 4. The last step finishes rather than advancing.
-- =================================================================
do
    saved = {}
    local refs = newRefs(8)
    local r = walk(refs)
    check('the last step offers Save & Finish, not Next',
        stub.drew(r, 'Save & Finish##TutorialBar') and not stub.drew(r, 'Next##TutorialBar'),
        table.concat(r.buttons, '|'))
    check('the last step is "Step 4 of 4"', stub.drew(r, 'Step 4 of 4'),
        table.concat(r.texts or {}, '|'))

    stub.click = { ['Save & Finish##TutorialBar'] = true }
    walk(refs)
    stub.click = {}
    check('finishing leaves setup mode', refs.uiState.setupMode == false, refs.uiState.setupMode)
    check('finishing returns to screen 0', refs.uiState.setupStep == 0, refs.uiState.setupStep)
    check('finishing saves nothing through saveLayoutForView (step 8 windows save themselves)',
        #saved == 0, saved[1] and saved[1].view)
end

-- =================================================================
-- 5. Back walks the sequence, not the old step numbers.
-- =================================================================
do
    local refs = newRefs(6)
    stub.click = { ['Back##TutorialBar'] = true }
    walk(refs)
    stub.click = {}
    check('Back from the Bank step goes to Sell, not step 5', refs.uiState.setupStep == 4,
        refs.uiState.setupStep)
end

print(string.format('\n%d passed, %d failed', pass, fail))
os.exit(fail == 0 and 0 or 1)
