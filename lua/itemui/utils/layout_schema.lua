--[[
    Layout schema versioning.

    THE PROBLEM. Three settings persist as "these are on" whitelists -- DockButtons,
    DockSegments and ColumnVisibility. Each is rewritten in full on every change, and none
    carried a version. So the moment a shipped default gained a member, every install with a
    saved layout -- which is every install past its first session -- kept the old set,
    silently, and the new thing looked unshipped. That has now bitten four times, most
    recently when Clickies joined the launcher row and did not appear for the person who
    reported it missing.

    THE FIX, AND WHY IT IS NOT JUST A UNION. Unioning the whole shipped default into a saved
    list on every load would resurrect every entry the user had ever deliberately turned off.
    So each canonical entry carries `since` -- the schema at which it first shipped -- and a
    load only adds entries NEWER than the schema the file was saved at. An id the user
    switched off was present at their schema level, so it is never re-added; an id they have
    never seen is. No second "explicitly off" key, and no re-appearance tax.

    A file with no `LayoutSchema=` predates the marker and reads as schema 0.

    ADDING AN ENTRY: give it `since = <CURRENT + 1>`, then bump CURRENT. Adding one with
    `since = 0` means "existing installs should not get this", which is occasionally right
    and always worth a comment.

    Entries that ship OFF (`default = false`) are never migrated in regardless of `since` --
    they are offerable, not shipped, and turning them on is the user's business.
--]]

local M = {}

--- Bump when adding a canonical entry that existing installs should receive.
---   0 -> no marker in the file (every install before 2026-08-02)
---   1 -> Clickies joined the launcher row (utils/dock_buttons.lua)
M.CURRENT = 1

M.KEY = "LayoutSchema"

--- Read the saved schema. Anything missing, blank or unparseable is 0 -- a pre-marker file,
--- which is exactly the case this exists to migrate.
function M.saved(value)
    local n = tonumber(value)
    if not n or n ~= n then return 0 end          -- n ~= n catches NaN
    n = math.floor(n)
    if n < 0 then return 0 end
    return n
end

--- Ids from `entries` that ship ON and first appeared after `savedSchema`.
--- `entries` is any ordered list of { [idField] = ..., default = bool, since = number }.
function M.additions(entries, savedSchema, idField)
    idField = idField or "id"
    local out = {}
    for _, e in ipairs(entries or {}) do
        local id = e[idField]
        if id and e.default and (tonumber(e.since) or 0) > savedSchema then
            out[#out + 1] = id
        end
    end
    return out
end

--- Migrate a CSV whitelist. Returns the new CSV and whether anything changed.
---
--- Order matters for DockButtons (it is the bar's left-to-right order), so a new id is
--- inserted at its CANONICAL position relative to the ids already present, not appended --
--- otherwise a migrated install gets a row in a different order from a fresh one.
function M.migrateCsv(savedCsv, entries, savedSchema, idField)
    idField = idField or "id"
    local additions = M.additions(entries, savedSchema, idField)
    if #additions == 0 then return savedCsv, false end

    -- "none" is not an empty list, it is a RECORDED CHOICE: config_general writes it when the
    -- user unchecks the last launcher, and it means "I want no row". Migrating into it would
    -- override that with one chip -- defensible under the per-id rule (favorites was never
    -- present at schema 0, so adding it is not a resurrection) and wrong against what the file
    -- actually records. Only pre-marker files can be in this state; any later edit stamps.
    if tostring(savedCsv or "") == "none" then return savedCsv, false end

    local order, present = {}, {}
    for part in tostring(savedCsv or ""):gmatch("([^,]+)") do
        local id = part:match("^%s*(.-)%s*$")
        -- A stray "none" mid-list is still not an id -- carrying it through would produce
        -- the literal string sitting in the row.
        if id ~= "" and id ~= "none" then
            order[#order + 1] = id
            present[id] = true
        end
    end

    local canonPos = {}
    for i, e in ipairs(entries or {}) do
        if e[idField] then canonPos[e[idField]] = i end
    end

    local added = false
    for _, id in ipairs(additions) do
        if not present[id] then
            local at = #order + 1
            for i, existing in ipairs(order) do
                if (canonPos[existing] or math.huge) > (canonPos[id] or math.huge) then
                    at = i
                    break
                end
            end
            table.insert(order, at, id)
            present[id] = true
            added = true
        end
    end
    if not added then return savedCsv, false end
    return table.concat(order, ","), true
end

--- Migrate a per-view visibility map: { [view] = { [key] = bool } }, against
--- { [view] = { {key=..., default=..., since=...}, ... } }. Only turns things ON.
function M.migrateVisibility(visibility, available, savedSchema)
    local changed = false
    for view, cols in pairs(available or {}) do
        local target = visibility and visibility[view]
        if target then
            for _, id in ipairs(M.additions(cols, savedSchema, "key")) do
                if target[id] ~= true then
                    target[id] = true
                    changed = true
                end
            end
        end
    end
    return changed
end

return M
