--[[
    keybinds.lua — the product's MacroQuest key bindings (spec §10).

    The set here is the one that survived a real `/bind eqlist` audit against a live
    server; the design's original proposal (alt+letter, F1-F3) was collision-free on
    paper and collided with nine live binds in practice — alt+I is TOGGLE_BAZAARWIN,
    F1-F3 are TARGETME/PARTY1/PARTY2, even alt+F1 is TOGGLE_PETINFOWIN. The full dump
    and the reasoning are in docs/research/KEYBIND_PROPOSAL.md. ctrl+shift+<key> came
    back nearly empty (only ctrl+shift+F and ctrl+shift+S taken), so that is the scheme.

    THREE THINGS THAT ARE NOT STYLE:

    1. Every `-down` command is wrapped in `/timed 1`. MQ2CustomBinds runs its command
       directly on the keyboard-input path, and at least one field build (the stock E3
       bundle's MQ 3.1.4.9) crashes inside mq2lua when a Lua-bound command is invoked
       from there — mq2lua.DLL+1C87. `/timed` re-queues onto the normal pulse path: one
       decisecond later, same effect, crash path avoided, harmless everywhere else. The
       existing itemui_inv bind has always done this; every bind added here must too.

    2. The commands are all `/itemui …` subcommands that ENQUEUE onto the dock action
       queue rather than acting inline, so a keypress and a bar click land in the same
       single-action-per-tick drain and cannot race each other.

    3. Persistence is ONE CSV key, not eleven. `layout_io.loadLayoutValue`'s fallthrough
       is `tonumber(val) or default`, so an unlisted string key writes correctly, appears
       in the file, and reads back as its default forever — a silent-revert bug this
       codebase has already documented twice. One key means one place to get that right,
       following the PinnedWindows / SectionsCollapsed precedent.

    ItemUIToggleKey (shift+q, the hub) is deliberately NOT folded in here: it predates
    this, every existing user INI carries it, and it is the one bind whose default is
    non-empty. It keeps its own key and its own apply path in utils/layout.lua.
]]

local mq = require('mq')

local M = {}

--- Ordered, because Settings renders them in this order and the CSV is written in it.
--- `id`      stable key for the CSV and the ImGui widget ids — never rename
--- `bind`    the MQ2CustomBinds name (`/custombind add <bind>`)
--- `label`   what Settings and the Hub list call it
--- `cmd`     the slash command the bind fires (WITHOUT the /timed wrapper)
--- `default` the audited combo
M.BINDS = {
    { id = "inventory", bind = "coopt_inventory", label = "Bags (Inventory hub)",
      cmd = "/itemui toggle",            default = "ctrl+shift+I" },
    -- NOT in the audited set: that set was written when Bags+Bank were being merged, so
    -- ctrl+shift+I covered both ("Inventory (Bags·Bank pair once merged)"). The merge was
    -- rolled back, so Bank needs its own key or it is the one window with no shortcut.
    -- ctrl+shift+K is free in the same live dump the rest of the set was audited against
    -- (only ctrl+shift+F and ctrl+shift+S were taken) — flag for sign-off.
    { id = "bank",      bind = "coopt_bank",      label = "Bank",
      cmd = "/itemui window bank",       default = "ctrl+shift+K" },
    { id = "pair_idau", bind = "coopt_pair_idau", label = "Item Display + Aug Utility",
      cmd = "/itemui pair idau",         default = "ctrl+shift+D" },
    { id = "equipment", bind = "coopt_equipment", label = "Equipment",
      cmd = "/itemui window equipment",  default = "ctrl+shift+E" },
    { id = "effects",   bind = "coopt_effects",   label = "Effects",
      cmd = "/itemui window effects",    default = "ctrl+shift+B" },
    { id = "reroll",    bind = "coopt_reroll",    label = "Reroll",
      cmd = "/itemui window reroll",     default = "ctrl+shift+R" },
    { id = "mythicals", bind = "coopt_mythicals", label = "Mythics",
      cmd = "/itemui window mythicals",  default = "ctrl+shift+M" },
    { id = "aa",        bind = "coopt_aa",        label = "AA",
      cmd = "/itemui window aa",         default = "ctrl+shift+A" },
    { id = "preset1",   bind = "coopt_preset1",   label = "Layout preset 1",
      cmd = "/itemui preset 1",          default = "ctrl+shift+F1" },
    { id = "preset2",   bind = "coopt_preset2",   label = "Layout preset 2",
      cmd = "/itemui preset 2",          default = "ctrl+shift+F2" },
    { id = "preset3",   bind = "coopt_preset3",   label = "Layout preset 3",
      cmd = "/itemui preset 3",          default = "ctrl+shift+F3" },
}

-- id -> spec, for O(1) lookup from the views that draw shortcut hints.
M.BY_ID = {}
for _, b in ipairs(M.BINDS) do M.BY_ID[b.id] = b end

-- id -> combo. Populated from the INI (or the defaults) at load.
local current = nil

local function ensureLoaded()
    if current then return current end
    current = {}
    for _, b in ipairs(M.BINDS) do current[b.id] = b.default end
    return current
end

--- `"Ctrl Shift I"` / `"ctrl-shift-i"` -> `"ctrl+shift+I"`. Same rules as the hub bind's
--- normalizer (utils/layout.lua): modifiers lowercase and canonical, everything else
--- keeps its case, joined with `+`. Function keys survive intact.
function M.normalize(input)
    if type(input) ~= "string" then return "" end
    local s = input:match("^%s*(.-)%s*$")
    if s == "" then return "" end
    local parts = {}
    for part in s:gmatch("[^%s+%-]+") do
        local lower = part:lower()
        if lower == "shift" or lower == "ctrl" or lower == "control" or lower == "alt" then
            parts[#parts + 1] = (lower == "control") and "ctrl" or lower
        else
            parts[#parts + 1] = part
        end
    end
    if #parts == 0 then return "" end
    return table.concat(parts, "+")
end

-- ---------------------------------------------------------------------------
-- Persistence: one CSV, `id:combo` pairs. An id with an empty combo is UNBOUND,
-- which is a real state and distinct from "absent" (absent = take the default).
-- The `:` separator is safe: normalize only ever emits `+`-joined tokens.
-- ---------------------------------------------------------------------------

function M.getCSV()
    local c = ensureLoaded()
    local out = {}
    for _, b in ipairs(M.BINDS) do
        out[#out + 1] = b.id .. ":" .. tostring(c[b.id] or "")
    end
    return table.concat(out, ",")
end

function M.setFromCSV(csv)
    local c = ensureLoaded()
    -- Start from the defaults so a CSV written before a bind existed still gets that
    -- bind's default rather than nil.
    for _, b in ipairs(M.BINDS) do c[b.id] = b.default end
    for entry in tostring(csv or ""):gmatch("[^,]+") do
        local id, combo = entry:match("^%s*([^:]+):(.*)$")
        if id then
            id = id:match("^%s*(.-)%s*$")
            if M.BY_ID[id] then c[id] = M.normalize(combo) end
        end
    end
end

--- The combo for a bind id, or "" when unbound.
function M.get(id)
    return ensureLoaded()[id] or ""
end

--- Display form for a shortcut hint. nil when unbound, so callers can skip drawing.
function M.display(id)
    local v = M.get(id)
    return (v ~= "") and v or nil
end

function M.set(id, combo)
    if not M.BY_ID[id] then return false end
    ensureLoaded()[id] = M.normalize(combo)
    return true
end

--- Reset every bind to its audited default (Settings' "Restore defaults").
function M.resetAll()
    local c = ensureLoaded()
    for _, b in ipairs(M.BINDS) do c[b.id] = b.default end
end

--- Any two binds sharing a combo. Returns a list of { combo, ids } — Settings shows
--- this inline rather than silently letting the last-applied bind win.
function M.conflicts()
    local c = ensureLoaded()
    local seen, dupes = {}, {}
    for _, b in ipairs(M.BINDS) do
        local combo = c[b.id]
        if combo and combo ~= "" then
            local key = combo:lower()
            if seen[key] then
                if not dupes[key] then dupes[key] = { combo = combo, ids = { seen[key] } } end
                table.insert(dupes[key].ids, b.id)
            else
                seen[key] = b.id
            end
        end
    end
    local out = {}
    for _, v in pairs(dupes) do out[#out + 1] = v end
    table.sort(out, function(a, b) return a.combo < b.combo end)
    return out
end

-- ---------------------------------------------------------------------------
-- Apply
-- ---------------------------------------------------------------------------

--- Create the bind name and point it at its command. `/custombind add` is a no-op when
--- MQ2CustomBinds.txt already defines the name, so this is safe to re-run every time.
local function ensureBind(b)
    pcall(function()
        mq.cmd("/squelch /custombind add " .. b.bind)
        mq.cmd("/squelch /custombind set " .. b.bind .. "-down /timed 1 " .. b.cmd)
    end)
end

--- Push one bind to MQ. An empty combo clears it rather than leaving the old key live.
function M.apply(id)
    local b = M.BY_ID[id]
    if not b then return end
    ensureBind(b)
    local combo = M.get(id)
    pcall(function()
        if combo == "" then
            mq.cmd("/squelch /bind " .. b.bind .. " clear")
        else
            mq.cmd("/squelch /bind " .. b.bind .. " " .. combo)
        end
    end)
end

--- Push all of them. Cheap (squelched commands in pcalls), so Settings re-applies the
--- whole set on any edit rather than tracking which row changed.
function M.applyAll()
    for _, b in ipairs(M.BINDS) do M.apply(b.id) end
end

--- Test seam: drop the in-memory state so a suite can start from the defaults.
function M._resetForTests()
    current = nil
end

return M
