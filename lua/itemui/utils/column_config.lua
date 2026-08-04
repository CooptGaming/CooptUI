--[[
    ItemUI Column Config
    Column definitions (availableColumns), visibility state, and autofit widths per view.
    Reduces locals/upvalues in init.lua.

    ADDING A COLUMN THAT SHOULD REACH EXISTING INSTALLS: give it
    `since = <layout_schema.CURRENT + 1>` and bump CURRENT. ColumnVisibility persists as a
    "these are on" whitelist, so without that an install with a saved layout -- which is every
    install past its first session -- keeps its old set and never sees the new column, however
    the shipped default is written. utils/layout_schema.lua carries the mechanism and the
    history of the four times that bug shipped.

    Everything defined below predates the marker and is normalised to `since = 0` at the foot
    of this file, so it migrates to nobody. That is deliberate: the marker's first release
    changes exactly one thing in anyone's config (the launcher row), and a migration that
    quietly rearranged someone's Bags columns on upgrade would be a worse bug than the one it
    fixes.
--]]

local M = {}

-- Store autofit column widths per view and column key
M.columnAutofitWidths = {
    Inventory = {},
    Sell = {},
    Bank = {}
}

-- Column definitions per view (all item properties from iteminfo.mac; users can add/remove columns)
M.availableColumns = {
    Inventory = {
        {key = "Name", label = "Name", numeric = false, default = true, since = 0},
        {key = "Status", label = "Status", numeric = false, default = false, since = 0},
        {key = "Value", label = "Value", numeric = true, default = true, since = 0},
        {key = "Weight", label = "Weight", numeric = true, default = true, since = 0},
        {key = "Type", label = "Type", numeric = false, default = true, since = 0},
        {key = "Bag", label = "Bag", numeric = true, default = true, since = 0},
        {key = "Slot", label = "Slot", numeric = true, default = false, since = 0},
        -- On by default since the windows pass: it REPLACES the deleted Newest button.
        -- That button set a sort from a control that did not say so, and its second click
        -- silently restored Name order; a real column header does the same job and states
        -- what it is doing. Off by default it would have removed the capability instead of
        -- relocating it.
        {key = "Acquired", label = "Acquired", numeric = true, default = true, since = 0},
        {key = "Stack", label = "Stack", numeric = true, default = false, since = 0},
        {key = "StackSizeMax", label = "Stack Max", numeric = true, default = false, since = 0},
        {key = "Clicky", label = "Clicky", numeric = false, default = true, since = 0},
        {key = "ID", label = "ID", numeric = true, default = false, since = 0},
        {key = "Icon", label = "Icon", numeric = true, default = false, since = 0},
        {key = "NoDrop", label = "NoDrop", numeric = false, default = false, since = 0},
        {key = "NoTrade", label = "NoTrade", numeric = false, default = false, since = 0},
        {key = "NoRent", label = "NoRent", numeric = false, default = false, since = 0},
        {key = "Lore", label = "Lore", numeric = false, default = false, since = 0},
        {key = "Magic", label = "Magic", numeric = false, default = false, since = 0},
        {key = "Quest", label = "Quest", numeric = false, default = false, since = 0},
        {key = "Collectible", label = "Collectible", numeric = false, default = false, since = 0},
        {key = "Heirloom", label = "Heirloom", numeric = false, default = false, since = 0},
        {key = "Prestige", label = "Prestige", numeric = false, default = false, since = 0},
        {key = "Attuneable", label = "Attuneable", numeric = false, default = false, since = 0},
        {key = "Tradeskills", label = "Tradeskills", numeric = false, default = false, since = 0},
        {key = "AugSlots", label = "Aug Slots", numeric = true, default = false, since = 0},
        {key = "Container", label = "Container", numeric = true, default = false, since = 0},
        {key = "Size", label = "Size", numeric = true, default = false, since = 0},
        {key = "SizeCapacity", label = "Size Cap", numeric = true, default = false, since = 0},
        {key = "Tribute", label = "Tribute", numeric = true, default = false, since = 0},
        {key = "Class", label = "Class", numeric = false, default = false, since = 0},
        {key = "Race", label = "Race", numeric = false, default = false, since = 0},
        {key = "WornSlots", label = "Worn Slots", numeric = false, default = false, since = 0},
        {key = "RequiredLevel", label = "Req Lvl", numeric = true, default = false, since = 0},
        {key = "RecommendedLevel", label = "Rec Lvl", numeric = true, default = false, since = 0},
        {key = "Proc", label = "Proc", numeric = false, default = false, since = 0},
        {key = "Focus", label = "Focus", numeric = false, default = false, since = 0},
        {key = "Spell", label = "Spell", numeric = false, default = false, since = 0},
        {key = "Worn", label = "Worn", numeric = false, default = false, since = 0},
        {key = "InstrumentType", label = "Instrument Type", numeric = false, default = false, since = 0},
        {key = "InstrumentMod", label = "Instrument Mod", numeric = true, default = false, since = 0},
    },
    Sell = {
        {key = "Name", label = "Name", numeric = false, default = true, since = 0},
        {key = "Status", label = "Status", numeric = false, default = true, since = 0},
        {key = "Value", label = "Value", numeric = true, default = true, since = 0},
        {key = "Stack", label = "Stack", numeric = true, default = true, since = 0},
        {key = "StackSizeMax", label = "Stack Max", numeric = true, default = false, since = 0},
        {key = "Type", label = "Type", numeric = false, default = true, since = 0},
        {key = "Weight", label = "Weight", numeric = true, default = false, since = 0},
        {key = "Bag", label = "Bag", numeric = true, default = false, since = 0},
        {key = "Slot", label = "Slot", numeric = true, default = false, since = 0},
        {key = "ID", label = "ID", numeric = true, default = false, since = 0},
        {key = "Icon", label = "Icon", numeric = true, default = false, since = 0},
        {key = "NoDrop", label = "NoDrop", numeric = false, default = false, since = 0},
        {key = "NoTrade", label = "NoTrade", numeric = false, default = false, since = 0},
        {key = "NoRent", label = "NoRent", numeric = false, default = false, since = 0},
        {key = "Lore", label = "Lore", numeric = false, default = false, since = 0},
        {key = "Magic", label = "Magic", numeric = false, default = false, since = 0},
        {key = "Quest", label = "Quest", numeric = false, default = false, since = 0},
        {key = "Collectible", label = "Collectible", numeric = false, default = false, since = 0},
        {key = "Heirloom", label = "Heirloom", numeric = false, default = false, since = 0},
        {key = "Prestige", label = "Prestige", numeric = false, default = false, since = 0},
        {key = "Attuneable", label = "Attuneable", numeric = false, default = false, since = 0},
        {key = "Tradeskills", label = "Tradeskills", numeric = false, default = false, since = 0},
        {key = "AugSlots", label = "Aug Slots", numeric = true, default = false, since = 0},
        {key = "Container", label = "Container", numeric = true, default = false, since = 0},
        {key = "Size", label = "Size", numeric = true, default = false, since = 0},
        {key = "Tribute", label = "Tribute", numeric = true, default = false, since = 0},
        {key = "Class", label = "Class", numeric = false, default = false, since = 0},
        {key = "Race", label = "Race", numeric = false, default = false, since = 0},
        {key = "RequiredLevel", label = "Req Lvl", numeric = true, default = false, since = 0},
        {key = "RecommendedLevel", label = "Rec Lvl", numeric = true, default = false, since = 0},
        {key = "Clicky", label = "Clicky", numeric = false, default = false, since = 0},
        {key = "Proc", label = "Proc", numeric = false, default = false, since = 0},
        {key = "Focus", label = "Focus", numeric = false, default = false, since = 0},
        {key = "Spell", label = "Spell", numeric = false, default = false, since = 0},
        {key = "Worn", label = "Worn", numeric = false, default = false, since = 0},
    },
    Bank = {
        {key = "Name", label = "Name", numeric = false, default = true, since = 0},
        -- 20a: ON by default HERE (it stays off for Inventory). The bank is where
        -- "on a reroll list" and "ornament" are the facts you came to check, and the
        -- window's whole job is answering questions about items you are not carrying.
        {key = "Status", label = "Status", numeric = false, default = true, since = 0},
        {key = "Bag", label = "Bag", numeric = true, default = true, since = 0},
        {key = "Slot", label = "Slot", numeric = true, default = true, since = 0},
        {key = "Value", label = "Value", numeric = true, default = true, since = 0},
        {key = "Stack", label = "Stack", numeric = true, default = true, since = 0},
        {key = "StackSizeMax", label = "Stack Max", numeric = true, default = false, since = 0},
        {key = "Type", label = "Type", numeric = false, default = true, since = 0},
        {key = "Weight", label = "Weight", numeric = true, default = false, since = 0},
        {key = "ID", label = "ID", numeric = true, default = false, since = 0},
        {key = "Icon", label = "Icon", numeric = true, default = false, since = 0},
        {key = "NoDrop", label = "NoDrop", numeric = false, default = false, since = 0},
        {key = "NoTrade", label = "NoTrade", numeric = false, default = false, since = 0},
        {key = "NoRent", label = "NoRent", numeric = false, default = false, since = 0},
        {key = "Lore", label = "Lore", numeric = false, default = false, since = 0},
        {key = "Magic", label = "Magic", numeric = false, default = false, since = 0},
        {key = "Quest", label = "Quest", numeric = false, default = false, since = 0},
        {key = "Collectible", label = "Collectible", numeric = false, default = false, since = 0},
        {key = "Heirloom", label = "Heirloom", numeric = false, default = false, since = 0},
        {key = "Prestige", label = "Prestige", numeric = false, default = false, since = 0},
        {key = "Attuneable", label = "Attuneable", numeric = false, default = false, since = 0},
        {key = "Tradeskills", label = "Tradeskills", numeric = false, default = false, since = 0},
        {key = "AugSlots", label = "Aug Slots", numeric = true, default = false, since = 0},
        {key = "Container", label = "Container", numeric = true, default = false, since = 0},
        {key = "Size", label = "Size", numeric = true, default = false, since = 0},
        {key = "Tribute", label = "Tribute", numeric = true, default = false, since = 0},
        {key = "Class", label = "Class", numeric = false, default = false, since = 0},
        {key = "Race", label = "Race", numeric = false, default = false, since = 0},
        {key = "RequiredLevel", label = "Req Lvl", numeric = true, default = false, since = 0},
        {key = "RecommendedLevel", label = "Rec Lvl", numeric = true, default = false, since = 0},
        {key = "Clicky", label = "Clicky", numeric = false, default = false, since = 0},
        {key = "Proc", label = "Proc", numeric = false, default = false, since = 0},
        {key = "Focus", label = "Focus", numeric = false, default = false, since = 0},
        {key = "Spell", label = "Spell", numeric = false, default = false, since = 0},
        {key = "Worn", label = "Worn", numeric = false, default = false, since = 0},
        {key = "InstrumentType", label = "Instrument Type", numeric = false, default = false, since = 0},
        {key = "InstrumentMod", label = "Instrument Mod", numeric = true, default = false, since = 0},
    },
}

-- Column visibility state per view (which columns are currently visible)
M.columnVisibility = {
    Inventory = {},
    Sell = {},
    Bank = {},
}

-- Every column literal DECLARES its `since` in source -- no load-time normaliser filling
-- the field in. The normaliser made the "every column declares a since" guard un-failable
-- (it ran inside the test's own require), which is how the column half of the schema
-- migration shipped wired to nothing: zero literals carried the field, every column read
-- 0, and 0 > savedSchema is never true. test_layout_schema now scans this file's SOURCE,
-- so a new column added without deciding its since fails the build instead of silently
-- never reaching existing installs.
--
-- ADDING A COLUMN? Give it `since = layout_schema.CURRENT + 1` and bump CURRENT, or it
-- will never appear for anyone with a saved layout (which is everyone past their first
-- session). `since = 0` means "existed before the marker" and is only right for these.

function M.initColumnVisibility()
    for view, cols in pairs(M.availableColumns) do
        M.columnVisibility[view] = {}
        for _, col in ipairs(cols) do
            M.columnVisibility[view][col.key] = col.default
        end
    end
end

-- Initialize defaults on load
M.initColumnVisibility()

return M
