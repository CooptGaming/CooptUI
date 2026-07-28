--[[
    chat_feed.lua — capture chat into a ring buffer for the bottom bar's chat line.

    Structure is cloned from script_consume_events.lua (module-scope pattern constants,
    one-arg handler, pcall-wrapped mq.event inside init(d), diagnostics on failure). What is
    different, and why it matters:

      * The pattern is a bare catch-all, which nothing in this product has used before. MQ
        pumps events from mq.doevents() in main_loop's phase 10, after a 33ms delay while the
        UI is visible, so this handler runs on EVERY chat line at roughly 30 Hz. It must stay
        allocation-light: one table per retained line, no string building, no scanning.

      * It NEVER mutates config or protection state. reroll_service.lua:320-331 records what
        happens when a broad chat pattern is allowed to write a cache that doubles as a
        sell/loot protection set: a stray line wiped the reroll list and the next Auto Sell
        vendored items that should have been protected. This module only appends to its own
        buffer.

      * keepLinks is on. mq.event takes an optional 4th options table and the default STRIPS
        EQ item links out of the delivered line (see examples/linkdetector.lua:43). A chat
        feed that swallowed item links would be visibly worse than the game's own window.

    Typing is deliberately NOT reimplemented: Enter hands focus back to EQ's own chat input.
    An overlay that tried to replace the game's input is the one thing that always goes wrong.
]]

local mq = require('mq')
local constants = require('itemui.constants')

local M = {}
local deps

local EVENT_NAME = "ItemUIChatFeedLine"
local LINE_PATTERN = "#*#"

local MAX_LINES = (constants.LIMITS and constants.LIMITS.CHAT_FEED_MAX) or 200

-- Ring buffer of { text, channel, tab }. Newest last.
local lines = {}
-- Per-channel unread counts, cleared when the user looks at that tab.
local unread = {}
local started = false

--- Channel classification. Ordered longest/most-specific first; the patterns are plain
--- `string.find(..., true)` substring tests rather than Lua patterns, because this runs on
--- every chat line and pattern matching here would be the expensive part.
local CHANNELS = {
    { id = "coopt", needle = "[CoOpt" },
    { id = "coopt", needle = "[ItemUI" },
    { id = "mq",    needle = "[MQ2" },
    { id = "tell",  needle = " tells you," },
    { id = "tell",  needle = " told you," },
    { id = "group", needle = " tells the group," },
    { id = "guild", needle = " tells the guild," },
    { id = "say",   needle = " says," },
    { id = "say",   needle = " shouts," },
    -- The player's own half of each conversation, or Main shows only what other people said.
    { id = "tell",  needle = "You told " },
    { id = "group", needle = "You tell your party," },
    { id = "guild", needle = "You say to your guild," },
    { id = "say",   needle = "You say," },
    { id = "say",   needle = "You shout," },
}

--- Coarse bucket for the channel tabs: Main / MQ / Other / CoOpt (mockup 13b).
local TAB_OF = {
    say = "main", tell = "main", group = "main", guild = "main",
    mq = "mq", coopt = "coopt",
}

local function classify(text)
    for i = 1, #CHANNELS do
        local c = CHANNELS[i]
        if text:find(c.needle, 1, true) then return c.id end
    end
    return "other"
end

local function onChatLine(line)
    if not line or type(line) ~= "string" or line == "" then return end
    local channel = classify(line)
    local tab = TAB_OF[channel] or "other"
    lines[#lines + 1] = { text = line, channel = channel, tab = tab }
    -- Trim with table.move rather than a table.remove loop: this is the hot path, and the
    -- same trim shape services/loot_feed_events.lua:58-63 already uses.
    local over = #lines - MAX_LINES
    if over > 0 then
        table.move(lines, over + 1, #lines, 1)
        for i = #lines - over + 1, #lines do lines[i] = nil end
    end
    unread[tab] = (unread[tab] or 0) + 1
end

function M.init(d)
    deps = d
    if started then return end
    local ok, err = pcall(function()
        -- 4th arg: keep EQ item links intact in the delivered text.
        mq.event(EVENT_NAME, LINE_PATTERN, onChatLine, { keepLinks = true })
    end)
    if ok then
        started = true
    else
        local diag = deps and deps.diagnostics or require('itemui.core.diagnostics')
        if diag and diag.recordError then
            diag.recordError("chat_feed", "Event registration failed", tostring(err or "unknown"))
        end
    end
end

--- Newest `count` lines, oldest first, optionally filtered to one tab.
--- Returns a COPY so a mid-render mutation cannot shift indices under ImGui — the same
--- contract core/diagnostics.lua:30-34 uses for its buffer.
function M.getLines(count, tab)
    local out = {}
    count = tonumber(count) or 1
    for i = #lines, 1, -1 do
        local e = lines[i]
        if not tab or tab == "all" or e.tab == tab then
            table.insert(out, 1, e)
            if #out >= count then break end
        end
    end
    return out
end

function M.getUnread(tab)
    if not tab or tab == "all" then
        local n = 0
        for _, v in pairs(unread) do n = n + v end
        return n
    end
    return unread[tab] or 0
end

function M.clearUnread(tab)
    if not tab or tab == "all" then
        unread = {}
    else
        unread[tab] = 0
    end
end

function M.count()
    return #lines
end

return M
