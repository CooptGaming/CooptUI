--[[ layout_columns.lua: Column visibility and fixed-column order (Inventory/Bank). Requires init(deps). ]]
local LayoutColumns = {}

local columnVisibility
local layoutConfig
local availableColumns
local saveLayoutToFileImmediate

function LayoutColumns.init(deps)
    columnVisibility = deps.columnVisibility
    layoutConfig = deps.layoutConfig
    availableColumns = deps.availableColumns or {}
    saveLayoutToFileImmediate = deps.saveLayoutToFileImmediate
end

--- Apply column visibility from parsed INI. For Inventory and Bank also populates fixedColumnOrder.
function LayoutColumns.applyColumnVisibilityFromParsed(parsed)
    local cv = parsed.columnVisibility or {}
    layoutConfig.fixedColumnOrder = layoutConfig.fixedColumnOrder or { Inventory = {}, Bank = {} }

    for view, v in pairs(cv) do
        if columnVisibility[view] then
            for colKey, _ in pairs(columnVisibility[view]) do columnVisibility[view][colKey] = false end
            local ordered = {}
            for colKey in (v or ""):gmatch("([^/]+)") do
                colKey = colKey:match("^%s*(.-)%s*$")
                if columnVisibility[view][colKey] ~= nil then
                    columnVisibility[view][colKey] = true
                    table.insert(ordered, colKey)
                end
            end
            if (view == "Inventory" or view == "Bank") and #ordered > 0 then
                layoutConfig.fixedColumnOrder[view] = ordered
            end
        end
    end

    for _, view in ipairs({"Inventory", "Bank"}) do
        local list = layoutConfig.fixedColumnOrder[view]
        if not list or #list == 0 then
            local defaults = {}
            for _, colDef in ipairs(availableColumns[view] or {}) do
                if colDef.default then table.insert(defaults, colDef.key) end
            end
            layoutConfig.fixedColumnOrder[view] = defaults
        end
    end
end

--- Toggle a column in the fixed list (Inventory/Bank). Adds if not present, removes if present. Returns new state (true = in list, false = removed).
function LayoutColumns.toggleFixedColumn(view, colKey)
    if view ~= "Inventory" and view ~= "Bank" then return nil end
    layoutConfig.fixedColumnOrder = layoutConfig.fixedColumnOrder or { Inventory = {}, Bank = {} }
    local list = layoutConfig.fixedColumnOrder[view] or {}
    local found = nil
    for i, k in ipairs(list) do
        if k == colKey then found = i; break end
    end
    if found then
        if #list <= 1 then return true end
        table.remove(list, found)
        if saveLayoutToFileImmediate then saveLayoutToFileImmediate() end
        return false
    else
        table.insert(list, colKey)
        if saveLayoutToFileImmediate then saveLayoutToFileImmediate() end
        return true
    end
end

--- Check if column is in the fixed list (Inventory/Bank).
function LayoutColumns.isColumnInFixedSet(view, colKey)
    if view ~= "Inventory" and view ~= "Bank" then return false end
    local list = layoutConfig.fixedColumnOrder and layoutConfig.fixedColumnOrder[view] or {}
    for _, k in ipairs(list) do
        if k == colKey then return true end
    end
    return false
end

--- Get fixed column list for Inventory/Bank (ordered; used for fixed-display mode). Returns array of colDefs.
function LayoutColumns.getFixedColumns(view)
    if view ~= "Inventory" and view ~= "Bank" then return {} end
    local colDefByKey = {}
    for _, colDef in ipairs(availableColumns[view] or {}) do
        colDefByKey[colDef.key] = colDef
    end
    local ordered = layoutConfig.fixedColumnOrder and layoutConfig.fixedColumnOrder[view] or {}
    local result = {}
    for _, colKey in ipairs(ordered) do
        local colDef = colDefByKey[colKey]
        if colDef then table.insert(result, colDef) end
    end
    if #result == 0 then
        for _, colDef in ipairs(availableColumns[view] or {}) do
            if colDef.default then table.insert(result, colDef) end
        end
    end
    return result
end

--- Save column visibility (delegates to consolidated layout save).
function LayoutColumns.saveColumnVisibility()
    if saveLayoutToFileImmediate then saveLayoutToFileImmediate() end
end

return LayoutColumns
