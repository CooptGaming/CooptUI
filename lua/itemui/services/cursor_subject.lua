--[[
    cursor_subject.lua — what is on your cursor, and what will take it (windows pass item 10).

    Two states, one fact seen from both ends:

      RING  a 2px OpenBlue edge on a destination: *this will take what is on your cursor.*
      DIM   45% on the row the item LEFT: *this item is not in that slot right now.*

    They are the same state. A ring without its dim claims the item is in two places; a
    dim without its rings is a row that went quiet for no visible reason. So both read the
    same three things from here, and every window asking gets the same answer in the same
    frame — that is what makes the ring "a map of where this can go" rather than a hover
    response.

    Contract:
      - NO ImGui calls. Pure reads of uiState plus one cached TLO read per frame for the
        carried augment's type. Views call M.beginFrame() once (app.lua does it) and then
        ask the predicates as they draw.
      - Degrades to nothing. No cursor state -> no ring, no dim, and the design still
        works because the game's own cursor art already shows what you are carrying. This
        is an accelerant, not a dependency, which is why every predicate answers FALSE
        when it does not know. **Never draw a ring you are not sure about** — a ring on a
        slot that rejects the drop is worse than no ring.
]]

local augmentHelpers = require('itemui.utils.augment_helpers')

local M = {}

local d                 -- deps (uiState, itemOps)

-- Per-frame cache. Rebuilt once per beginFrame so a hundred rows asking cost one read.
local frame = {
    active = false,     -- something is on the cursor AND we know where it came from
    bag = nil, slot = nil, source = nil,
    augType = nil,      -- >0 when the carried item is an augment
}

function M.init(deps)
    d = deps
end

--- Once per frame, before anything draws. Cheap when the cursor is empty (one bool).
function M.beginFrame()
    frame.active, frame.bag, frame.slot, frame.source, frame.augType = false, nil, nil, nil, nil
    local uiState = d and d.uiState
    local itemOps = d and d.itemOps
    if not (uiState and itemOps) then return end

    local carrying = false
    if uiState.hasItemOnCursorThisFrame ~= nil then
        carrying = uiState.hasItemOnCursorThisFrame and true or false
    else
        local ok, v = pcall(itemOps.hasItemOnCursor)
        carrying = ok and v and true or false
    end
    if not carrying then return end

    -- Where it came from. Without this there is no source row to dim, and a ring with no
    -- dim is the half-state this module exists to prevent — so both stay off.
    local lp = uiState.lastPickup
    if not (lp and lp.bag and lp.slot) then return end
    frame.active = true
    frame.bag, frame.slot, frame.source = lp.bag, lp.slot, lp.source or "inv"

    -- The carried augment's type, for socket targeting. One TLO read per frame, only
    -- while something is actually on the cursor.
    local ok, it = pcall(function()
        local getTLO = require('itemui.utils.item_helpers').getItemTLO
        return getTLO and getTLO(frame.bag, frame.slot, frame.source)
    end)
    if ok and it then
        local okT, t = pcall(function()
            return require('itemui.utils.item_tlo').getAugTypeFromTLO(it)
        end)
        if okT then frame.augType = tonumber(t) or nil end
    end
end

--- Is anything being carried that we can reason about?
function M.active()
    return frame.active
end

--- The DIM predicate: is THIS row the one the carried item left?
--- Source row only — a row scrolled out of view or in a closed window dims nothing and
--- nothing scrolls to find it.
function M.isSourceRow(bag, slot, source)
    if not frame.active then return false end
    if bag == nil or slot == nil then return false end
    return frame.bag == bag and frame.slot == slot
        and frame.source == (source or "inv")
end

--- The RING predicate for an augment socket: would the carried item go in here?
--- False unless we positively know the answer.
function M.socketAccepts(socketType)
    if not frame.active then return false end
    if not frame.augType or frame.augType <= 0 then return false end
    return augmentHelpers.augmentFitsSocket(frame.augType, socketType) and true or false
end

--- 45% of the row's OWN colour, for the dim. Not a blend toward grey: a mythic row must
--- dim to faint mythic, or the dim doubles as a category change. Alpha only, so
--- background, stripe and separators stay full and the table's rhythm is unbroken.
function M.dimColor(rgba)
    if type(rgba) ~= "table" then return rgba end
    return { rgba[1], rgba[2], rgba[3], (rgba[4] or 1) * 0.45 }
end

return M
