--[[ coopt_poc.lua - Native-window extension proof of concept.

Proves that controls added to the stock RoF2 Merchant window by a custom UI
skin (uifiles\coopt_poc\EQUI_MerchantWnd.xml) can drive CoOpt features
through MacroQuest:

  1. Click detection - the skin buttons are Style_Checkbox, so a click
     latches bChecked. We poll Window("MerchantWnd").Child(...).Checked,
     act on it, then unlatch with /notify leftmouseup.
  2. Dynamic text - this MQ build's Window.SetText method only supports
     EditBoxes, so the skin ships a transparent borderless EditBox
     ("Coopt_Status") as the status line. The script self-tests two write
     paths (TLO method, then /invoke) and reports which one works.

In game:
  /loadskin coopt_poc       -- activate the skin (revert: /loadskin default)
  /lua run coopt_poc        -- start this watcher
  /lua stop coopt_poc       -- stop it
Then open any merchant and click the "CoOpt" / "CoOpt UI" buttons in the
bottom strip of the merchant window.

Nothing in this script sells, buys, or moves items.
]]

local mq = require('mq')

local WND      = 'MerchantWnd'
local PING_BTN = 'Coopt_PingBtn'
local UI_BTN   = 'Coopt_UiBtn'
local STATUS   = 'Coopt_Status'

local pingCount   = 0
local setTextMode = nil -- nil (untested) | 'method' | 'invoke' | 'unsupported'

local function out(fmt, ...)
    print(string.format('\ay[CoOpt POC]\ax ' .. fmt, ...))
end

local function child(name)
    return mq.TLO.Window(WND).Child(name)
end

local function merchantOpen()
    local w = mq.TLO.Window(WND)
    return w() ~= nil and w.Open()
end

-- Set the status EditBox text. First run probes which write path this MQ
-- build honors and reports the result (that IS one of the POC questions).
local function setStatus(text)
    if setTextMode == 'unsupported' then return end
    -- Missing children can have a non-nil ToString but nil members on this MQ
    -- build (e.g. right after /loadskin) - always test a member, not ToString.
    local c = child(STATUS)
    if c == nil or c.Text == nil then return end

    if setTextMode == nil or setTextMode == 'method' then
        pcall(function() c.SetText(text)() end)
        if (c.Text() or '') == text then
            if setTextMode == nil then out('\agPASS\ax: dynamic text via TLO method Window.SetText works.') end
            setTextMode = 'method'
            return
        end
    end

    mq.cmdf('/invoke ${Window[%s].Child[%s].SetText[%s]}', WND, STATUS, text)
    mq.delay(100)
    if (child(STATUS).Text() or '') == text then
        if setTextMode == nil then out('\agPASS\ax: dynamic text via /invoke SetText works (TLO method form did not).') end
        setTextMode = 'invoke'
        return
    end

    if setTextMode == nil then
        setTextMode = 'unsupported'
        out('\arFAIL\ax: SetText did not stick via TLO method or /invoke. Status line stays static; buttons are unaffected.')
    end
end

local function unlatch(btn)
    mq.cmdf('/notify %s %s leftmouseup', WND, btn)
end

local function onPing()
    pingCount = pingCount + 1
    out('\agPASS\ax: native button click #%d detected at %s.', pingCount, os.date('%H:%M:%S'))
    mq.cmd('/beep')
    setStatus(string.format('CoOpt link OK - ping #%d at %s', pingCount, os.date('%H:%M:%S')))
end

local function onUiButton()
    out('\agPASS\ax: native button -> /itemui toggle (CoOpt UI should open/close).')
    setStatus('Toggling CoOpt UI...')
    mq.cmd('/itemui toggle')
end

out('Watching %s for skin controls (%s, %s, %s).', WND, PING_BTN, UI_BTN, STATUS)
out('Skin: /loadskin coopt_poc   Revert: /loadskin default   Stop: /lua stop coopt_poc')

local announced = false
while true do
    if merchantOpen() then
        local ping = child(PING_BTN)
        if ping == nil or ping.Checked == nil then
            if not announced then
                out('\arMerchant window is open but %s was not found - is the coopt_poc skin loaded? (/loadskin coopt_poc)', PING_BTN)
                announced = true
            end
        else
            if not announced then
                out('\agPASS\ax: skin controls found inside %s. Click the CoOpt buttons in the merchant window.', WND)
                setStatus('CoOpt POC connected - click a button')
                announced = true
            end
            if ping.Checked() then
                unlatch(PING_BTN)
                onPing()
            end
            local ui = child(UI_BTN)
            if ui ~= nil and ui.Checked ~= nil and ui.Checked() then
                unlatch(UI_BTN)
                onUiButton()
            end
        end
    else
        announced = false
    end
    mq.delay(100)
end
