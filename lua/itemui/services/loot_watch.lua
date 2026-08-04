--[[
    loot_watch.lua — the one answer to "did this come off a corpse?"

    The session record used to source itself from the inventory delta: any row whose
    acquiredSeq landed at or above the session floor was "tonight's loot". That is not the
    same question. A row appears for every inflow the bags can have — an augment pulled
    out of a socket, a bank withdrawal, a trade, a merchant buy — and the record asked you
    to rule on all of them. The reported case was an ornamentation removed from a weapon:
    the player had owned it for weeks, and the panel queued it as fresh loot.

    So the record stops guessing and listens instead. The game says "You have looted ..."
    for a corpse pickup and for nothing else, which makes it the actual signal — and,
    unlike loot.mac's IPC feed, it fires for hand-looting too, so the record does not go
    blind the moment the macro stops. Each line becomes one CREDIT; a new inventory row is
    only recorded if it can claim one. Credits are consumed, so two of the same augment off
    two corpses need two lines.

    FAIL OPEN UNTIL ARMED. A gate that silently swallows everything is worse than no gate:
    if this server words the line differently, the record would just sit empty and the
    player would have no way to tell that from a quiet night. So claim() returns true until
    the first real loot line arrives. One corpse arms the watcher for the rest of the
    session; until then the behaviour is exactly what it was before.
]]

local mq = require('mq')
local item_name = require('itemui.utils.item_name')
local dbg = require('itemui.core.debug').channel('Loot')

local M = {}

local EVENT_NAME = "CooptUILootWatch"
local LINE_PATTERN = "#*#You have looted#*#"

-- A credit is worth claiming for a while: the inventory scan that notices the new row is
-- fingerprint-driven and can trail the chat line, and a full bag scan is spread over
-- frames. Five minutes is far past any of that and still short enough that a name looted
-- before a break cannot pay for a bank withdrawal after it.
local CREDIT_TTL_S = 300
local CREDITS_MAX = 500

local credits = {}      -- array of { name, raw, at } — oldest first
local armed = false     -- has a real corpse-loot line ever been seen?
local deniedSeen = {}   -- name -> true; a denial is logged once, not once per tick

local function lower(s) return tostring(s or ""):lower() end

--- Drop credits that aged out. Called on every add and every claim — and claim runs once
--- per unmatched row per main-loop tick, so the common case (nothing has expired) must not
--- allocate. Credits are appended in time order, so expiry is a prefix: shift it off in
--- place and touch nothing otherwise.
local function prune(nowS)
    local cutoff = (nowS or os.time()) - CREDIT_TTL_S
    local first = 1
    while credits[first] and credits[first].at < cutoff do first = first + 1 end
    -- A hard cap as well: a runaway pattern match must not grow this without limit.
    local over = (#credits - first + 1) - CREDITS_MAX
    if over > 0 then first = first + over end
    if first == 1 then return end
    local n = #credits
    local w = 0
    for i = first, n do w = w + 1; credits[w] = credits[i] end
    for i = w + 1, n do credits[i] = nil end
end

--- Strip the loot line down to an item name.
---
--- The line is "--You have looted a Rare Script of Lost Memories.--" — a grammatical
--- article, a sentence period and the chat window's own dashes wrapped around the thing we
--- actually want. Each of those is peeled separately, and BOTH the peeled and the unpeeled
--- forms are kept as claimable names: an item genuinely called "A Tattered Note" would
--- lose its first word to the article strip, and a claim that fails means real loot goes
--- unrecorded. Keeping both costs one table field and cannot be wrong in that direction.
local function parseLootedName(line)
    if type(line) ~= "string" then return nil, nil end
    local rest = line:match("[Yy]ou have looted%s+(.+)$")
    if not rest or rest == "" then return nil, nil end
    rest = rest:gsub("%-%-%s*$", "")            -- the chat window's closing dashes
    rest = rest:gsub("%s+$", "")
    rest = rest:gsub("%.$", "")                 -- the sentence period
    local raw = item_name.normalizeItemName(rest)
    if raw == "" then return nil, nil end
    local stripped = raw:gsub("^[Aa]n%s+", ""):gsub("^[Aa]%s+", "")
    return raw, (stripped ~= "" and stripped) or raw
end

--- Add a credit and arm the gate. `name` is an item name from any corpse-loot source.
function M.note(name, nowS)
    local n = item_name.normalizeItemName(name)
    if n == "" then return end
    armed = true
    nowS = nowS or os.time()
    prune(nowS)
    credits[#credits + 1] = { name = lower(n), raw = lower(n), at = nowS }
end

local function onLootLine(line)
    local raw, stripped = parseLootedName(line)
    if not raw then return end
    if not armed then dbg.log("loot gate: armed by the game's own loot line") end
    armed = true
    local nowS = os.time()
    prune(nowS)
    credits[#credits + 1] = { name = lower(stripped), raw = lower(raw), at = nowS }
end

--- Can `name` be accounted for by a corpse this session? Consumes the credit that pays
--- for it, so the same line can never pay twice.
---
--- Returns true while unarmed — see the header. That is the whole safety net: no loot
--- line ever seen means the pattern is wrong, and a record that behaves like it always
--- did is a far better failure than one that quietly stops recording.
function M.claim(name, nowS)
    if not armed then return true end
    local want = lower(item_name.normalizeItemName(name))
    if want == "" then return false end
    nowS = nowS or os.time()
    prune(nowS)
    for i = 1, #credits do
        local c = credits[i]
        if c.name == want or c.raw == want then
            table.remove(credits, i)
            deniedSeen[want] = nil
            return true
        end
    end
    -- The silent failure mode of this whole design is a loot line whose wording does not
    -- match, which looks exactly like a quiet night. Denials say so on the Loot channel —
    -- ONCE per name, because the merge walk retries an unmatched row every tick.
    if not deniedSeen[want] then
        deniedSeen[want] = true
        dbg.log(string.format("loot gate: '%s' has no corpse behind it - not recorded", want))
    end
    return false
end

--- Would claim() succeed, without spending anything? Used to tell a row that MOVED from a
--- row that was just LOOTED when the two look identical — a copy with a credit still
--- outstanding is fresh loot and deserves its own record; one with nothing left to pay
--- with is the copy already recorded, in a new slot.
---
--- Deliberately the opposite of claim() while unarmed: with no corpse signal at all there
--- is no evidence either way, and answering "yes, fresh" would invent a duplicate record
--- for an item that merely changed slots. Answering "no" only re-links, which is the
--- conservative direction.
function M.peek(name, nowS)
    if not armed then return false end
    local want = lower(item_name.normalizeItemName(name))
    if want == "" then return false end
    prune(nowS or os.time())
    for i = 1, #credits do
        local c = credits[i]
        if c.name == want or c.raw == want then return true end
    end
    return false
end

--- Whether a real loot line has been seen. Diagnostics and tests only — callers decide
--- nothing on this; claim() already folds it in.
function M.isArmed() return armed end

function M.init(d)
    local ok, err = pcall(function()
        mq.event(EVENT_NAME, LINE_PATTERN, onLootLine)
    end)
    if not ok and d and d.diagnostics then
        d.diagnostics.recordError("loot_watch", "Event registration failed", tostring(err or "unknown"))
    end
end

--- Test seam.
function M._resetForTests(startArmed)
    credits = {}
    deniedSeen = {}
    armed = startArmed == true
end

--- Test seam: drive the chat handler without an mq event pump.
function M._feedLine(line) onLootLine(line) end

return M
