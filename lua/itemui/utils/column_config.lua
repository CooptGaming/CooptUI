--[[
    ItemUI Column Config
    Column definitions (availableColumns), visibility state, and autofit widths per view.
    Reduces locals/upvalues in init.lua.
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
        {key = "Name", label = "Name", numeric = false, default = true},
        {key = "Status", label = "Status", numeric = false, default = false},
        {key = "Value", label = "Value", numeric = true, default = true},
        {key = "Weight", label = "Weight", numeric = true, default = true},
        {key = "Type", label = "Type", numeric = false, default = true},
        {key = "Bag", label = "Bag", numeric = true, default = true},
        {key = "Slot", label = "Slot", numeric = true, default = false},
        {key = "Stack", label = "Stack", numeric = true, default = false},
        {key = "StackSizeMax", label = "Stack Max", numeric = true, default = false},
        {key = "Clicky", label = "Clicky", numeric = false, default = true},
        {key = "ID", label = "ID", numeric = true, default = false},
        {key = "Icon", label = "Icon", numeric = true, default = false},
        {key = "NoDrop", label = "NoDrop", numeric = false, default = false},
        {key = "NoTrade", label = "NoTrade", numeric = false, default = false},
        {key = "NoRent", label = "NoRent", numeric = false, default = false},
        {key = "Lore", label = "Lore", numeric = false, default = false},
        {key = "Magic", label = "Magic", numeric = false, default = false},
        {key = "Quest", label = "Quest", numeric = false, default = false},
        {key = "Collectible", label = "Collectible", numeric = false, default = false},
        {key = "Heirloom", label = "Heirloom", numeric = false, default = false},
        {key = "Prestige", label = "Prestige", numeric = false, default = false},
        {key = "Attuneable", label = "Attuneable", numeric = false, default = false},
        {key = "Tradeskills", label = "Tradeskills", numeric = false, default = false},
        {key = "AugSlots", label = "Aug Slots", numeric = true, default = false},
        {key = "Container", label = "Container", numeric = true, default = false},
        {key = "Size", label = "Size", numeric = true, default = false},
        {key = "SizeCapacity", label = "Size Cap", numeric = true, default = false},
        {key = "Tribute", label = "Tribute", numeric = true, default = false},
        {key = "Class", label = "Class", numeric = false, default = false},
        {key = "Race", label = "Race", numeric = false, default = false},
        {key = "WornSlots", label = "Worn Slots", numeric = false, default = false},
        {key = "RequiredLevel", label = "Req Lvl", numeric = true, default = false},
        {key = "RecommendedLevel", label = "Rec Lvl", numeric = true, default = false},
        {key = "Proc", label = "Proc", numeric = false, default = false},
        {key = "Focus", label = "Focus", numeric = false, default = false},
        {key = "Spell", label = "Spell", numeric = false, default = false},
        {key = "Worn", label = "Worn", numeric = false, default = false},
        {key = "InstrumentType", label = "Instrument Type", numeric = false, default = false},
        {key = "InstrumentMod", label = "Instrument Mod", numeric = true, default = false},
    },
    Sell = {
        {key = "Name", label = "Name", numeric = false, default = true},
        {key = "Status", label = "Status", numeric = false, default = true},
        {key = "Value", label = "Value", numeric = true, default = true},
        {key = "Stack", label = "Stack", numeric = true, default = true},
        {key = "StackSizeMax", label = "Stack Max", numeric = true, default = false},
        {key = "Type", label = "Type", numeric = false, default = true},
        {key = "Weight", label = "Weight", numeric = true, default = false},
        {key = "Bag", label = "Bag", numeric = true, default = false},
        {key = "Slot", label = "Slot", numeric = true, default = false},
        {key = "ID", label = "ID", numeric = true, default = false},
        {key = "Icon", label = "Icon", numeric = true, default = false},
        {key = "NoDrop", label = "NoDrop", numeric = false, default = false},
        {key = "NoTrade", label = "NoTrade", numeric = false, default = false},
        {key = "NoRent", label = "NoRent", numeric = false, default = false},
        {key = "Lore", label = "Lore", numeric = false, default = false},
        {key = "Magic", label = "Magic", numeric = false, default = false},
        {key = "Quest", label = "Quest", numeric = false, default = false},
        {key = "Collectible", label = "Collectible", numeric = false, default = false},
        {key = "Heirloom", label = "Heirloom", numeric = false, default = false},
        {key = "Prestige", label = "Prestige", numeric = false, default = false},
        {key = "Attuneable", label = "Attuneable", numeric = false, default = false},
        {key = "Tradeskills", label = "Tradeskills", numeric = false, default = false},
        {key = "AugSlots", label = "Aug Slots", numeric = true, default = false},
        {key = "Container", label = "Container", numeric = true, default = false},
        {key = "Size", label = "Size", numeric = true, default = false},
        {key = "Tribute", label = "Tribute", numeric = true, default = false},
        {key = "Class", label = "Class", numeric = false, default = false},
        {key = "Race", label = "Race", numeric = false, default = false},
        {key = "RequiredLevel", label = "Req Lvl", numeric = true, default = false},
        {key = "RecommendedLevel", label = "Rec Lvl", numeric = true, default = false},
        {key = "Clicky", label = "Clicky", numeric = false, default = false},
        {key = "Proc", label = "Proc", numeric = false, default = false},
        {key = "Focus", label = "Focus", numeric = false, default = false},
        {key = "Spell", label = "Spell", numeric = false, default = false},
        {key = "Worn", label = "Worn", numeric = false, default = false},
    },
    Bank = {
        {key = "Name", label = "Name", numeric = false, default = true},
        {key = "Status", label = "Status", numeric = false, default = false},
        {key = "Bag", label = "Bag", numeric = true, default = true},
        {key = "Slot", label = "Slot", numeric = true, default = true},
        {key = "Value", label = "Value", numeric = true, default = true},
        {key = "Stack", label = "Stack", numeric = true, default = true},
        {key = "StackSizeMax", label = "Stack Max", numeric = true, default = false},
        {key = "Type", label = "Type", numeric = false, default = true},
        {key = "Weight", label = "Weight", numeric = true, default = false},
        {key = "ID", label = "ID", numeric = true, default = false},
        {key = "Icon", label = "Icon", numeric = true, default = false},
        {key = "NoDrop", label = "NoDrop", numeric = false, default = false},
        {key = "NoTrade", label = "NoTrade", numeric = false, default = false},
        {key = "NoRent", label = "NoRent", numeric = false, default = false},
        {key = "Lore", label = "Lore", numeric = false, default = false},
        {key = "Magic", label = "Magic", numeric = false, default = false},
        {key = "Quest", label = "Quest", numeric = false, default = false},
        {key = "Collectible", label = "Collectible", numeric = false, default = false},
        {key = "Heirloom", label = "Heirloom", numeric = false, default = false},
        {key = "Prestige", label = "Prestige", numeric = false, default = false},
        {key = "Attuneable", label = "Attuneable", numeric = false, default = false},
        {key = "Tradeskills", label = "Tradeskills", numeric = false, default = false},
        {key = "AugSlots", label = "Aug Slots", numeric = true, default = false},
        {key = "Container", label = "Container", numeric = true, default = false},
        {key = "Size", label = "Size", numeric = true, default = false},
        {key = "Tribute", label = "Tribute", numeric = true, default = false},
        {key = "Class", label = "Class", numeric = false, default = false},
        {key = "Race", label = "Race", numeric = false, default = false},
        {key = "RequiredLevel", label = "Req Lvl", numeric = true, default = false},
        {key = "RecommendedLevel", label = "Rec Lvl", numeric = true, default = false},
        {key = "Clicky", label = "Clicky", numeric = false, default = false},
        {key = "Proc", label = "Proc", numeric = false, default = false},
        {key = "Focus", label = "Focus", numeric = false, default = false},
        {key = "Spell", label = "Spell", numeric = false, default = false},
        {key = "Worn", label = "Worn", numeric = false, default = false},
        {key = "InstrumentType", label = "Instrument Type", numeric = false, default = false},
        {key = "InstrumentMod", label = "Instrument Mod", numeric = true, default = false},
    },
}

-- Column visibility state per view (which columns are currently visible)
M.columnVisibility = {
    Inventory = {},
    Sell = {},
    Bank = {},
}

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
