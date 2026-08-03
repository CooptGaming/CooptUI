--[[
    The command bar's launcher row: which windows can be a chip, in bar order, and which of
    them ship on.

    This exists because the same list used to live in two places that drifted apart -- the
    shipped `DockButtons` default (state.lua) and the Settings editor's own table
    (config_general.lua). Three ways they disagreed, all shipped: itemDisplay and
    scripttracker were on the bar with no way to edit them, `augments` was editable but is
    classicOnly so it could never draw, and favorites/loot were in neither although
    hub_list.ENTRIES offered both. A drawn-chip sweep in test_dock_render catches the next
    drift, but one list is what stops there being a next one.

    Pure data, no requires -- state.lua loads this and declares itself free of anything but
    pure state.

    Adding a `default = true` entry DOES reach an existing install, via the `since` field and
    utils/layout_schema.lua. Give the new entry `since = layout_schema.CURRENT + 1` and bump
    CURRENT; a load then adds it to any file saved before that number, without resurrecting
    anything the user turned off.

    (This paragraph used to say the opposite -- correctly, until the schema marker shipped one
    commit later and made it false. Which is the residue problem this file exists to prevent,
    in this file, about this file.)
--]]

local M = {}

--- Canonical order. `default` is what a fresh install gets; everything here is offerable in
--- Settings whether it ships on or not.
---
--- `loot` ships OFF: the Loot window opens itself whenever a run starts
--- (main_window.lua:113, :122 and eight more sites) and the action lane reports the run
--- without it, so a launcher for it is a chip you press roughly never. It stays in the table
--- because "you cannot turn it on" was the actual bug.
---
--- `augments` is absent entirely, which is different from shipping off: it folded into Aug
--- Utility's All tab and its id is classicOnly, so a chip for it could never draw in bars
--- mode. Offering it in Settings was offering a control that does nothing.
--- `since` is the layout schema at which the entry first shipped; utils/layout_schema.lua
--- uses it to add new entries to an existing install without resurrecting ones the user
--- turned off. Everything present before the marker existed is `since = 0`.
M.BUTTONS = {
    { id = "bags",           label = "Bags",            default = true,  since = 0 },
    { id = "bank",           label = "Bank",            default = true,  since = 0 },
    { id = "itemDisplay",    label = "Item Display",    default = true,  since = 0 },
    { id = "augmentUtility", label = "Augment Utility", default = true,  since = 0 },
    { id = "equipment",      label = "Equipment",       default = true,  since = 0 },
    { id = "effects",        label = "Effects",         default = true,  since = 0 },
    { id = "mythicals",      label = "Mythics",         default = true,  since = 0 },
    { id = "reroll",         label = "Reroll",          default = true,  since = 0 },
    { id = "scripttracker",  label = "Scripts",         default = true,  since = 0 },
    { id = "aa",             label = "AA",              default = true,  since = 0 },
    { id = "favorites",      label = "Clickies",        default = true,  since = 1 },
    -- Ships off, so it is never migrated in -- `since` only records when it became
    -- offerable.
    { id = "loot",           label = "Loot",            default = false, since = 1 },
}

--- The shipped `DockButtons` value, built from the table above so the two cannot disagree.
function M.defaultCsv()
    local out = {}
    for _, b in ipairs(M.BUTTONS) do
        if b.default then out[#out + 1] = b.id end
    end
    return table.concat(out, ",")
end

--- Is this id offerable at all? (Not "is it on" -- that is the saved CSV's answer.)
function M.isKnown(id)
    for _, b in ipairs(M.BUTTONS) do
        if b.id == id then return true end
    end
    return false
end

return M
