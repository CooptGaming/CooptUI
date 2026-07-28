--[[
    window_zones.lua — zone-based window placement, drag tracking, magnets, Re-tidy.
    Mockups 10a (zones), 10b (magnets); spec §8 phase 4.

    The old behaviour this extends: main_window.lua seeds hub-relative positions when a
    window's X/Y are the (0,0) "unset" sentinel. This service turns that hardcoded
    arithmetic into a table plus an occupancy check, and adds the three rules the mockup
    calls out: never overlap on open, off-screen is impossible, move-once-keep-it.

    Contract (same rules as dock_state):
      - NO ImGui calls, NO TLO calls, NO file reads. Pure reads of layoutConfig/uiState plus
        registry open-state. The work rect is stashed by the render path each frame
        (uiState.dockWorkRect); geometry comes from the same layoutConfig keys the views
        write back every frame, which is what makes drag detection possible from out here.
      - Runs on the main-loop tick (after dockState.tick). `now` is ms, threaded in.
      - Placement writes layoutConfig X/Y and raises uiState.layoutRevertedApplyFrames so
        the views re-apply with ImGuiCond.Always for a couple of frames — the same
        force-apply mechanism Reset Window Positions and Revert to Default already use.
        That global re-apply is safe because every view mirrors its live position/size back
        into layoutConfig each frame (bank.lua:66-84 is the pattern), so re-applying stored
        geometry is a no-op for windows this service did not just move.

    Zones (mockup 10a): L1/L2 left of the hub, R1/R2 right, B1/B2 below. A zone maps to a
    column plus a preference rank; a window opening walks its column's free slots top-down
    (rank 2 prefers the second), falls back to a clamped cascade so it always lands
    on-screen. The per-module zone is declared in the view's registry spec (`zone = "R1"`),
    overridden by the ZoneAssign CSV, both read at tick time.
]]

local registry = require('itemui.core.registry')

local M = {}

local d                    -- main-loop deps table (init)

M.GAP = 6                  -- gutter between placed/snapped windows (mockup 10b: "4px" + border)
M.MAGNET_PX = 12           -- snap threshold when a drag settles (mockup 10b)
M.DRIFT_PX = 8             -- movement beyond this marks a window user-placed
local NOMINAL_W, NOMINAL_H = 340, 420   -- Command Center estimate (the one sizeless window)

-- moduleId -> layoutConfig geometry keys. `config` is absent on purpose: settings.lua never
-- persists a position, so there is nothing to place against. `loot` is uiState-managed
-- rather than registry-registered but has geometry keys, so it places like a module.
local GEOM = {
    equipment      = { x = "EquipmentWindowX", y = "EquipmentWindowY", w = "WidthEquipmentPanel", h = "HeightEquipment" },
    augments       = { x = "AugmentsWindowX", y = "AugmentsWindowY", w = "WidthAugmentsPanel", h = "HeightAugments" },
    augmentUtility = { x = "AugmentUtilityWindowX", y = "AugmentUtilityWindowY", w = "WidthAugmentUtilityPanel", h = "HeightAugmentUtility" },
    bank           = { x = "BankWindowX", y = "BankWindowY", w = "WidthBankPanel", h = "HeightBank" },
    itemDisplay    = { x = "ItemDisplayWindowX", y = "ItemDisplayWindowY", w = "WidthItemDisplayPanel", h = "HeightItemDisplay" },
    aa             = { x = "AAWindowX", y = "AAWindowY", w = "WidthAAPanel", h = "HeightAA" },
    reroll         = { x = "RerollWindowX", y = "RerollWindowY", w = "WidthRerollPanel", h = "HeightReroll" },
    mythicals      = { x = "MythicalsWindowX", y = "MythicalsWindowY", w = "WidthMythicalsPanel", h = "HeightMythicals" },
    effects        = { x = "EffectsWindowX", y = "EffectsWindowY", w = "WidthEffectsPanel", h = "HeightEffects" },
    favorites      = { x = "FavoritesWindowX", y = "FavoritesWindowY", w = "WidthFavoritesPanel", h = "HeightFavorites" },
    commandCenter  = { x = "CommandCenterWindowX", y = "CommandCenterWindowY" }, -- AlwaysAutoResize: no size keys
    loot           = { x = "LootWindowX", y = "LootWindowY", w = "WidthLootPanel", h = "HeightLoot" },
    chat           = { x = "ChatWindowX", y = "ChatWindowY", w = "WidthChatPanel", h = "HeightChat" },
}

M.GEOM = GEOM              -- layout_presets captures/applies geometry through this map

-- Fallback zones for the ids the registry cannot answer for (loot is not registered) or
-- that predate the spec fields. A view's own `zone =` declaration wins over this table;
-- the ZoneAssign CSV wins over both.
local ZONE_FALLBACK = { loot = "R2" }

-- zone id -> column + preference rank. Unknown zone strings fall back to R1 rather than
-- erroring: a hand-edited ZoneAssign should degrade, not break placement.
local ZONES = {
    L1 = { col = "L", rank = 1 }, L2 = { col = "L", rank = 2 },
    R1 = { col = "R", rank = 1 }, R2 = { col = "R", rank = 2 },
    B1 = { col = "B", rank = 1 }, B2 = { col = "B", rank = 2 },
}

-- ---------------------------------------------------------------------------
-- Tick-local state (module-locals; reset on /lua stop like everything else)
-- ---------------------------------------------------------------------------

local lastOpen = {}        -- id -> bool, previous tick's open set
local lastSeen = {}        -- id -> {x, y}, position observed last tick (drag detection)
local moving = {}          -- id -> true while the observed position is changing
local lastPlaced = {}      -- id -> {x, y}, where this service last put the window
local userPlaced = {}      -- id -> true; serialized to layoutConfig.UserPlaced
local attachments = {}     -- id -> {target=, edge=, align=}; serialized to WindowAttach
local lastUserPlacedCsv = nil   -- change detection for external writes (preset apply)
local lastAttachCsv = nil
local hubSeen = nil        -- {x, y} hub position last tick
local hubMoving = false
local hubSettledAt = nil   -- {x, y} hub position at last settle (delta base for follow)

function M.init(deps)
    d = deps
end

-- ---------------------------------------------------------------------------
-- CSV round-trips (UserPlaced=id,id  ·  WindowAttach=id:target:edge:align,...)
-- ---------------------------------------------------------------------------

local function csvSplit(s)
    local out = {}
    for part in tostring(s or ""):gmatch("[^,]+") do
        local t = part:match("^%s*(.-)%s*$")
        if t ~= "" then out[#out + 1] = t end
    end
    return out
end

function M.parseUserPlaced(csvStr)
    local set = {}
    for _, id in ipairs(csvSplit(csvStr)) do set[id] = true end
    return set
end

function M.serializeUserPlaced(set)
    local ids = {}
    for id in pairs(set) do ids[#ids + 1] = id end
    table.sort(ids)
    return table.concat(ids, ",")
end

function M.parseAttachments(csvStr)
    local out = {}
    for _, tuple in ipairs(csvSplit(csvStr)) do
        local id, target, edge, align = tuple:match("^([^:]+):([^:]+):([^:]+):([^:]+)$")
        if id then out[id] = { target = target, edge = edge, align = align } end
    end
    return out
end

function M.serializeAttachments(map)
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        local a = map[id]
        parts[#parts + 1] = string.format("%s:%s:%s:%s", id, a.target, a.edge, a.align)
    end
    return table.concat(parts, ",")
end

-- ---------------------------------------------------------------------------
-- Pure geometry (exposed for the headless tests)
-- ---------------------------------------------------------------------------

--- Overlap with a small shrink so windows sharing a gutter edge do not count as colliding.
function M.rectsOverlap(a, b)
    local s = 2
    return a.x + s < b.x + b.w - s and b.x + s < a.x + a.w - s
       and a.y + s < b.y + b.h - s and b.y + s < a.y + a.h - s
end

--- Clamp a w×h rect at (x,y) fully into the work rect. Oversized windows pin to the
--- work origin on that axis — partially visible beats entirely off-screen.
--- Never returns exactly (0,0): that pair is the codebase's "unset" sentinel (views skip
--- SetNextWindowPos for it and main_window re-seeds it), so a legitimate placement at the
--- true top-left corner is nudged one pixel.
function M.clampToWork(x, y, w, h, work)
    local maxX = work.x + work.w - w
    local maxY = work.y + work.h - h
    x = (maxX < work.x) and work.x or math.max(work.x, math.min(x, maxX))
    y = (maxY < work.y) and work.y or math.max(work.y, math.min(y, maxY))
    if x == 0 and y == 0 then x = 1 end
    return x, y
end

--- Candidate positions for a w×h window in a column, occupancy-aware.
--- col: "L" (right-aligned to the hub's left edge), "R" (left-aligned to its right edge),
--- "B" (below the hub, packed left to right). occupants: list of open rects already in
--- that column region. rank 2 prefers the second slot when more than one exists.
function M.candidatesFor(col, rank, w, h, hub, occupants, work)
    local gap = M.GAP
    local cands = {}
    if col == "B" then
        local y = hub.y + hub.h + gap
        cands[#cands + 1] = { x = hub.x, y = y }
        for _, o in ipairs(occupants) do
            cands[#cands + 1] = { x = o.x + o.w + gap, y = y }     -- pack the row rightward
        end
        for _, o in ipairs(occupants) do
            cands[#cands + 1] = { x = o.x, y = o.y + o.h + gap }   -- second row under each
        end
    else
        local x = (col == "L") and (hub.x - w - gap) or (hub.x + hub.w + gap)
        cands[#cands + 1] = { x = x, y = hub.y }
        for _, o in ipairs(occupants) do
            cands[#cands + 1] = { x = x, y = o.y + o.h + gap }
        end
        -- Second column further from the hub once the first has occupants: real screens run
        -- out of column height long before they run out of width, and without this a full
        -- column dumped everything into the escape cascade.
        local extreme = nil
        for _, o in ipairs(occupants) do
            local edge = (col == "L") and o.x or (o.x + o.w)
            if not extreme or ((col == "L") and edge < extreme) or ((col == "R") and edge > extreme) then
                extreme = edge
            end
        end
        if extreme then
            local x2 = (col == "L") and (extreme - w - gap) or (extreme + gap)
            cands[#cands + 1] = { x = x2, y = hub.y }
            for _, o in ipairs(occupants) do
                cands[#cands + 1] = { x = x2, y = o.y + o.h + gap }
            end
        end
    end
    if rank == 2 and #cands > 1 then
        table.insert(cands, table.remove(cands, 1))    -- prefer the second slot
    end
    return cands
end

--- First candidate that, after clamping, overlaps no open window. Falls back to a clamped
--- cascade offset so the answer is always fully on-screen even when nothing is free.
function M.firstFreeSlot(cands, w, h, openRects, work, cascadeIndex)
    for _, c in ipairs(cands) do
        local x, y = M.clampToWork(c.x, c.y, w, h, work)
        local r = { x = x, y = y, w = w, h = h }
        local clean = true
        for _, o in ipairs(openRects) do
            if M.rectsOverlap(r, o) then clean = false; break end
        end
        if clean then return x, y, true end
    end
    local k = (cascadeIndex or 0) % 10
    local x, y = M.clampToWork(work.x + 24 * (k + 1), work.y + 24 * (k + 1), w, h, work)
    return x, y, false
end

--- Magnet check for a settled rect against a set of named rects. Returns the aligned
--- position and the attachment tuple, or nil when nothing is within the threshold.
--- Edges: the window sits right-of / left-of / below / above the target; align records
--- which perpendicular edge matched (top/left) so re-anchoring keeps the line.
function M.magnetFor(rect, others, gap, threshold)
    gap = gap or M.GAP
    threshold = threshold or M.MAGNET_PX
    local best, bestDist = nil, threshold + 1
    for name, o in pairs(others) do
        local checks = {
            { edge = "right",  x = o.x + o.w + gap,      y = rect.y, dist = math.abs(rect.x - (o.x + o.w + gap)) },
            { edge = "left",   x = o.x - rect.w - gap,   y = rect.y, dist = math.abs(rect.x - (o.x - rect.w - gap)) },
            { edge = "bottom", x = rect.x, y = o.y + o.h + gap,      dist = math.abs(rect.y - (o.y + o.h + gap)) },
            { edge = "top",    x = rect.x, y = o.y - rect.h - gap,   dist = math.abs(rect.y - (o.y - rect.h - gap)) },
        }
        for _, c in ipairs(checks) do
            if c.dist <= threshold and c.dist < bestDist then
                -- Perpendicular edge alignment: only snap when the windows actually line up
                -- along the other axis too, else distant windows on the same y would grab.
                local align = nil
                if c.edge == "right" or c.edge == "left" then
                    if math.abs(rect.y - o.y) <= threshold then align = "top"; c.y = o.y
                    elseif rect.y < o.y + o.h and o.y < rect.y + rect.h then align = "free" end
                else
                    if math.abs(rect.x - o.x) <= threshold then align = "left"; c.x = o.x
                    elseif rect.x < o.x + o.w and o.x < rect.x + rect.w then align = "free" end
                end
                if align then
                    best = { x = c.x, y = c.y, target = name, edge = c.edge, align = align }
                    bestDist = c.dist
                end
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- layoutConfig plumbing
-- ---------------------------------------------------------------------------

local function lc() return d and d.layoutConfig end

local function isOpen(id)
    if id == "loot" then
        return (d and d.uiState and d.uiState.lootUIOpen) == true
    end
    return registry.isOpen(id)
end

--- Current rect from layoutConfig, or nil while the position is the (0,0) unset sentinel
--- (main_window's hub-relative seeding owns that case until the first placement).
function M.rectOf(id)
    local g, c = GEOM[id], lc()
    if not g or not c then return nil end
    local x, y = tonumber(c[g.x]), tonumber(c[g.y])
    if not x or not y or (x == 0 and y == 0) then return nil end
    local w = (g.w and tonumber(c[g.w])) or NOMINAL_W
    local h = (g.h and tonumber(c[g.h])) or NOMINAL_H
    return { x = x, y = y, w = w, h = h }
end

local function hubRect()
    local u = d and d.uiState
    local c = lc()
    local hx = u and tonumber(u.itemUIPositionX)
    local hy = u and tonumber(u.itemUIPositionY)
    local work = M.workRect()
    if not hx or not hy then
        -- Hub has never been drawn this session: anchor placements around the work-area
        -- centre so a bar-launched window still lands somewhere sane.
        hx = work.x + math.floor(work.w * 0.3)
        hy = work.y + math.floor(work.h * 0.1)
    end
    local hw = (c and tonumber(c.WidthInventory)) or 900
    local hh = (c and tonumber(c.Height)) or 620
    return { x = hx, y = hy, w = hw, h = hh }
end

--- The work rect the render path stashed (viewport minus bar strips). The 1920×1080
--- fallback only matters before the first bars frame of a session.
function M.workRect()
    local u = d and d.uiState
    local r = u and u.dockWorkRect
    if type(r) == "table" and tonumber(r.w) and r.w > 0 and tonumber(r.h) and r.h > 0 then
        return { x = r.x or 0, y = r.y or 0, w = r.w, h = r.h }
    end
    return { x = 0, y = 0, w = 1920, h = 1080 }
end

--- Effective zone for a module: ZoneAssign CSV > registry spec > fallback table.
function M.zoneOf(id)
    local c = lc()
    if c and c.ZoneAssign and c.ZoneAssign ~= "" then
        for _, pair in ipairs(csvSplit(c.ZoneAssign)) do
            local pid, z = pair:match("^([^:]+):(.+)$")
            if pid == id then return z end
        end
    end
    local z = registry.getZone and registry.getZone(id)
    return z or ZONE_FALLBACK[id]
end

local function persistUserPlaced()
    local c = lc()
    if not c then return end
    lastUserPlacedCsv = M.serializeUserPlaced(userPlaced)
    c.UserPlaced = lastUserPlacedCsv
    if d.scheduleLayoutSave then d.scheduleLayoutSave() end
end

local function persistAttachments()
    local c = lc()
    if not c then return end
    lastAttachCsv = M.serializeAttachments(attachments)
    c.WindowAttach = lastAttachCsv
    if d.scheduleLayoutSave then d.scheduleLayoutSave() end
end

--- Pick up UserPlaced / WindowAttach values something else wrote (a preset apply, a hand
--- edit + reload) without clobbering them with our stale in-memory copies.
--- Exposed as M.syncFromConfigNow for layout_presets: apply() rewrites both CSVs and then
--- calls placeMissing, which consults the in-memory sets — without an immediate sync a
--- window the user once dragged would still read as user-placed and be stranded on the
--- (0,0) sentinel the preset just wiped it to.
local function syncFromConfig()
    local c = lc()
    if not c then return end
    local up = tostring(c.UserPlaced or "")
    if up ~= lastUserPlacedCsv then
        userPlaced = M.parseUserPlaced(up)
        lastUserPlacedCsv = up
    end
    local at = tostring(c.WindowAttach or "")
    if at ~= lastAttachCsv then
        attachments = M.parseAttachments(at)
        lastAttachCsv = at
    end
end

-- ---------------------------------------------------------------------------
-- Placement
-- ---------------------------------------------------------------------------

local function forceApply(frames)
    local u = d and d.uiState
    if not u then return end
    local have = tonumber(u.layoutRevertedApplyFrames) or 0
    u.layoutRevertedApplyFrames = math.max(have, frames or 2)
    if d.scheduleLayoutSave then d.scheduleLayoutSave() end
end

--- Open rects in a column region, for occupancy walks. Column membership is by position
--- relative to the hub, not by zone label — a dragged window occupies wherever it IS.
local function columnOccupants(col, hub, exceptId)
    local out = {}
    for id in pairs(GEOM) do
        if id ~= exceptId and isOpen(id) then
            local r = M.rectOf(id)
            if r then
                local inCol
                if col == "L" then inCol = (r.x + r.w) <= hub.x + M.MAGNET_PX
                elseif col == "R" then inCol = r.x >= (hub.x + hub.w) - M.MAGNET_PX
                else inCol = r.y >= (hub.y + hub.h) - M.MAGNET_PX end
                if inCol then out[#out + 1] = r end
            end
        end
    end
    table.sort(out, function(a, b)
        if col == "B" then return a.x < b.x end
        return a.y < b.y
    end)
    return out
end

local function allOpenRects(exceptId)
    local out = {}
    for id in pairs(GEOM) do
        if id ~= exceptId and isOpen(id) then
            local r = M.rectOf(id)
            if r then out[#out + 1] = r end
        end
    end
    -- The hub is an obstacle too: "never overlap on open" would ring hollow if the slot a
    -- window took was on top of the one window that anchors everything. Only while it is
    -- actually drawn — a closed hub (Farming / Raid presets) must not cast a phantom shadow.
    if d and d.getShouldDraw and d.getShouldDraw() then
        out[#out + 1] = hubRect()
    end
    return out
end

-- When a window's own column has no free slot, try the remaining columns before giving up
-- to the cascade — a full left column should spill below the hub, not stack on top of a
-- neighbour. Order: below first (most screens have more free height than width there).
local SPILL = {
    L = { "B", "R" },
    R = { "B", "L" },
    B = { "R", "L" },
}

--- Place one window into its zone. Returns true when a position was written.
local function placeWindow(id, cascadeIndex)
    local g, c = GEOM[id], lc()
    if not g or not c then return false end
    local zone = M.zoneOf(id)
    local z = zone and ZONES[zone] or (zone and ZONES.R1)
    if not z then return false end                 -- no zone declared: never auto-place
    local hub = hubRect()
    local work = M.workRect()
    local w = (g.w and tonumber(c[g.w])) or NOMINAL_W
    local h = (g.h and tonumber(c[g.h])) or NOMINAL_H
    local open = allOpenRects(id)
    local x, y, clean
    for _, col in ipairs({ z.col, SPILL[z.col][1], SPILL[z.col][2] }) do
        local cands = M.candidatesFor(col, (col == z.col) and z.rank or 1, w, h, hub,
            columnOccupants(col, hub, id), work)
        x, y, clean = M.firstFreeSlot(cands, w, h, open, work, cascadeIndex)
        if clean then break end
    end
    c[g.x], c[g.y] = x, y
    lastPlaced[id] = { x = x, y = y }
    lastSeen[id] = { x = x, y = y }
    return true
end

--- Re-tidy (mockup 10a: "puts every open window back into its zone in one frame").
--- Clears user-placed and attachments, then re-places every open zoned window in a stable
--- order (zone rank, then id) so the outcome is deterministic.
function M.retidy()
    userPlaced = {}
    attachments = {}
    persistUserPlaced()
    persistAttachments()
    local ids = {}
    for id in pairs(GEOM) do
        if isOpen(id) and M.zoneOf(id) then ids[#ids + 1] = id end
    end
    table.sort(ids, function(a, b)
        local za, zb = M.zoneOf(a) or "R1", M.zoneOf(b) or "R1"
        if za ~= zb then return za < zb end
        return a < b
    end)
    -- Wipe positions first so earlier placements do not collide with stale rects of
    -- windows that are about to move anyway.
    local c = lc()
    for _, id in ipairs(ids) do
        local g = GEOM[id]
        if c and g then c[g.x], c[g.y] = 0, 0 end
        lastPlaced[id] = nil
    end
    local n = 0
    for i, id in ipairs(ids) do
        if placeWindow(id, i - 1) then n = n + 1 end
    end
    if n > 0 then forceApply(3) end
    return n
end

--- Adopt the CURRENT open set as already-seen, so the next tick's open-edge detection does
--- not fire for windows something else (a preset apply) just opened and positioned in this
--- same main-loop pass — without this, tick step 1 re-zoned every preset-opened window and
--- discarded the exact geometry "Save current as..." captured.
function M.markOpenSetCurrent()
    for id in pairs(GEOM) do
        lastOpen[id] = isOpen(id)
        if lastOpen[id] then
            local r = M.rectOf(id)
            if r then lastSeen[id] = { x = r.x, y = r.y } end
        end
    end
end

--- Public wrapper for the CSV re-sync (see syncFromConfig's doc block).
function M.syncFromConfigNow()
    syncFromConfig()
end

--- Place every open, zoned window whose position is still the (0,0) unset sentinel.
--- Used by preset apply: it wipes the X/Y of windows the preset gave no geometry, then
--- calls this so they flow into their zones without disturbing user-placed windows or
--- the attachments the preset itself just installed (unlike retidy, which clears both).
function M.placeMissing()
    local ids = {}
    for id in pairs(GEOM) do
        if isOpen(id) and M.zoneOf(id) and not userPlaced[id] and not M.rectOf(id) then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids, function(a, b)
        local za, zb = M.zoneOf(a) or "R1", M.zoneOf(b) or "R1"
        if za ~= zb then return za < zb end
        return a < b
    end)
    local n = 0
    for i, id in ipairs(ids) do
        if placeWindow(id, i - 1) then n = n + 1 end
    end
    if n > 0 then forceApply(3) end
    return n
end

-- ---------------------------------------------------------------------------
-- Tick
-- ---------------------------------------------------------------------------

function M.tick(now)
    local c = lc()
    if not c or tostring(c.UIMode or "classic") ~= "bars" then
        -- Classic mode: keep the open-set memory current so switching to bars later does
        -- not treat every already-open window as "newly opened" and rearrange the screen.
        for id in pairs(GEOM) do lastOpen[id] = isOpen(id) end
        return
    end
    syncFromConfig()

    local u = d and d.uiState
    local altHeld = u and u.dockAltHeld == true
    local changed = false

    -- 1. Newly-opened windows land in their zone (unless the user placed them earlier).
    for id in pairs(GEOM) do
        local open = isOpen(id)
        if open and not lastOpen[id] and not userPlaced[id] then
            if placeWindow(id) then changed = true end
        end
        if not open and lastOpen[id] then
            -- Close edge: anything attached to this window takes its place (the mockup's
            -- "slide up"), then re-anchors to the closed window's own target, if any.
            local closingRect = lastSeen[id]
            local ownAttach = attachments[id]
            for childId, a in pairs(attachments) do
                if a.target == id then
                    local g = GEOM[childId]
                    if g and closingRect and isOpen(childId) then
                        c[g.x], c[g.y] = closingRect.x, closingRect.y
                        lastPlaced[childId] = { x = closingRect.x, y = closingRect.y }
                        lastSeen[childId] = { x = closingRect.x, y = closingRect.y }
                        changed = true
                    end
                    if ownAttach then
                        attachments[childId] = { target = ownAttach.target, edge = a.edge, align = a.align }
                    else
                        attachments[childId] = nil
                    end
                end
            end
            if attachments[id] then attachments[id] = nil end
            persistAttachments()
        end
        lastOpen[id] = open
    end

    -- 2. Drag tracking: mark user-placed on real movement; magnet-snap when a drag settles.
    -- Two gates protect it from false positives:
    --   * While a force-apply is in flight (preset apply, Reset Window Positions, Revert —
    --     anything that raises layoutRevertedApplyFrames), geometry writes are programmatic:
    --     adopt them silently. Without this, every preset apply re-marked its own windows
    --     user-placed and UserPlaced repopulated itself right after being cleared.
    --   * While the left mouse button is held (stashed by the render callback), a stationary
    --     window is a PAUSED drag, not a finished one — settling it would snap the window
    --     out from under the cursor.
    local applying = (tonumber(u and u.layoutRevertedApplyFrames) or 0) > 0
    local mouseHeld = u and u.dockMouseHeld == true
    local hubDrawn = (not d.getShouldDraw) or d.getShouldDraw()
    for id in pairs(GEOM) do
        if isOpen(id) then
            local r = M.rectOf(id)
            if r then
                local seen = lastSeen[id]
                if applying then
                    moving[id] = nil
                    lastSeen[id] = { x = r.x, y = r.y }
                    r = nil                        -- consumed; skip the branches below
                elseif seen and (math.abs(r.x - seen.x) > 1 or math.abs(r.y - seen.y) > 1) then
                    moving[id] = true
                elseif moving[id] and not mouseHeld then
                    -- Settled this tick. Drift beyond the threshold marks the window
                    -- user-placed; the magnet check runs on ANY settle (a 9px nudge toward
                    -- an edge should still snap — coupling it to the drift threshold made
                    -- small adjustment drags dead zones).
                    moving[id] = nil
                    local placed = lastPlaced[id]
                    local driftedFromPlacement = not placed
                        or math.abs(r.x - placed.x) > M.DRIFT_PX
                        or math.abs(r.y - placed.y) > M.DRIFT_PX
                    if driftedFromPlacement and not userPlaced[id] then
                        userPlaced[id] = true
                        persistUserPlaced()
                    end
                    if not altHeld then
                        -- A closed hub is not a magnet target: attaching to an invisible
                        -- anchor reads as windows snapping to nothing.
                        local others = {}
                        if hubDrawn then others.hub = hubRect() end
                        for oid in pairs(GEOM) do
                            if oid ~= id and isOpen(oid) then
                                local o = M.rectOf(oid)
                                if o then others[oid] = o end
                            end
                        end
                        local snap = M.magnetFor(r, others, M.GAP, M.MAGNET_PX)
                        if snap then
                            local g = GEOM[id]
                            local x, y = M.clampToWork(snap.x, snap.y, r.w, r.h, M.workRect())
                            c[g.x], c[g.y] = x, y
                            -- Mutate the observed rect too: the unconditional lastSeen
                            -- update below must record the SNAPPED position, or the write
                            -- itself reads as another drag next tick.
                            r.x, r.y = x, y
                            attachments[id] = { target = snap.target, edge = snap.edge, align = snap.align }
                            persistAttachments()
                            changed = true
                        elseif attachments[id] then
                            attachments[id] = nil
                            persistAttachments()
                        end
                    end
                end
                if r then lastSeen[id] = { x = r.x, y = r.y } end
            end
        else
            moving[id] = nil
        end
    end

    -- 3. Hub-follow: windows attached to the hub travel with it, once its drag settles.
    -- Only while the hub's position is REAL (it has been drawn and wrote itemUIPositionX):
    -- hubRect() otherwise returns a synthetic work-area anchor, and seeding hubSettledAt
    -- from that would turn the hub's first genuine draw into a bogus follow delta that
    -- flings every attached window across the screen.
    local hubReal = u and tonumber(u.itemUIPositionX) ~= nil
    if not hubReal or applying then
        hubSeen, hubMoving = nil, false
        hubSettledAt = hubReal and { x = hubRect().x, y = hubRect().y } or nil
        if changed then forceApply(2) end
        return
    end
    local hub = hubRect()
    if mouseHeld and hubSeen and (math.abs(hub.x - hubSeen.x) <= 1 and math.abs(hub.y - hubSeen.y) <= 1) and hubMoving then
        -- Stationary but the button is still down: a paused hub drag, not a settle.
        hubSeen = { x = hub.x, y = hub.y }
        if changed then forceApply(2) end
        return
    end
    if hubSeen and (math.abs(hub.x - hubSeen.x) > 1 or math.abs(hub.y - hubSeen.y) > 1) then
        hubMoving = true
    elseif hubMoving then
        hubMoving = false
        if hubSettledAt then
            local dx, dy = hub.x - hubSettledAt.x, hub.y - hubSettledAt.y
            if dx ~= 0 or dy ~= 0 then
                local work = M.workRect()
                for id, a in pairs(attachments) do
                    if a.target == "hub" and isOpen(id) then
                        local g, r = GEOM[id], M.rectOf(id)
                        if g and r then
                            local x, y = M.clampToWork(r.x + dx, r.y + dy, r.w, r.h, work)
                            c[g.x], c[g.y] = x, y
                            lastPlaced[id] = { x = x, y = y }
                            lastSeen[id] = { x = x, y = y }
                            changed = true
                        end
                    end
                end
            end
        end
        hubSettledAt = { x = hub.x, y = hub.y }
    end
    if not hubSettledAt and not hubMoving then hubSettledAt = { x = hub.x, y = hub.y } end
    hubSeen = { x = hub.x, y = hub.y }

    if changed then forceApply(2) end
end

--- Test/inspection hooks. _state returns internals by reference; tests only.
function M._state()
    return {
        userPlaced = userPlaced, attachments = attachments,
        lastPlaced = lastPlaced, lastOpen = lastOpen,
    }
end

--- Reset all tick-local state (tests; also useful if a preset apply wants a clean slate).
function M._reset()
    lastOpen, lastSeen, moving, lastPlaced = {}, {}, {}, {}
    userPlaced, attachments = {}, {}
    lastUserPlacedCsv, lastAttachCsv = nil, nil
    hubSeen, hubMoving, hubSettledAt = nil, false, nil
end

return M
