--[[
    CoOpt UI Inventory Companion
    Purpose: Unified Inventory / Bank / Sell / Loot Interface
    Part of CoOpt UI — EverQuest EMU Companion
    Author: Perky's Crew
    Version: see coopui.version (ITEMUI)
    Dependencies: mq2lua, ImGui

    - Inventory: one area that switches view by context:
      * Loot window open: live loot view (corpse items with Will Loot / Will Skip; same filters as loot.mac).
      * Merchant open: sell view (Status, Keep/Junk buttons, Value, Stack, Type, Show only sellable, Auto Sell).
      * No merchant/loot: gameplay view (bag, slot, weight, flags); Shift+click to move when bank open.
    - Bank: slide-out panel (Bank button on right). When bank window open = "Online" + live list;
      when closed = "Offline" + last saved snapshot. Bank adds width to the base inventory size.
    - Layout setup: /itemui setup or click Setup. Resize the window for Inventory, Sell, and Inv+Bank
      then click the matching Save button. Sizes are stored in Macros/sell_config/itemui_layout.ini.
      Column widths are saved automatically when you resize them.
    Uses Macros/sell_config/ for keep/junk/sell config lists.

    Usage: /lua run itemui
    Toggle: /itemui   Setup: /itemui setup

    NOTE: Lua has a 200 local variable limit per scope. To avoid hitting this limit,
    related state is consolidated into tables (filterState, sortState). When adding
    new state variables, consider adding them to an existing table or creating a
    new consolidated table rather than adding new top-level locals.
--]]

local mq = require('mq')
local app = require('itemui.app')
app.runMain(mq)
