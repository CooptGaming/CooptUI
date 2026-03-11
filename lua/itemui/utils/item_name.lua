--[[
    ItemUI - Item name normalization
    Single source of truth for normalizing item names from IPC, INI, or echo
    so quoted vs unquoted names deduplicate and match (e.g. looted list, skip history).
--]]

local M = {}

--- Normalize an item name for comparison and storage: trim whitespace and strip one level of surrounding double quotes.
--- Returns the normalized string, or "" if name is nil or becomes empty after normalization.
function M.normalizeItemName(name)
    if name == nil or type(name) ~= "string" then return "" end
    name = name:match("^%s*(.-)%s*$") or ""
    if name == "" then return "" end
    -- Strip one level of surrounding double quotes (e.g. from macro/INI)
    local inner = name:match('^"(.*)"%s*$')
    if inner then
        name = inner:match("^%s*(.-)%s*$") or inner
    end
    return name
end

return M
