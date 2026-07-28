--[[
    dock_layout.lua — geometry for the top/bottom bars.

    Owns the two things that make the bars feel solid rather than twitchy:

      1. Fixed slot widths. Each segment reserves the width of its WIDEST POSSIBLE string,
         measured once with CalcTextSize and cached. Content changes inside the slot; the
         slot itself never resizes. This is the whole anti-jitter story — the old right-pane
         felt wrong because content decided layout.
      2. Screen geometry from ImGui.GetMainViewport(). Note: ImGui.GetIO().DisplaySize does
         NOT exist in this MQ binding (there is no DisplaySize anywhere in the tree), so the
         viewport is the only proven source. Probed once under pcall with a fallback, which
         is this codebase's convention for an ImGui/TLO member we cannot prove at load time.

    Leaf module: ImGui + constants only. No state, no services.
]]

local constants = require('itemui.constants')

local M = {}

-- Measured slot widths, keyed by slot id. Invalidated whenever the font metric or the
-- viewport size changes (a /loadskin or a game-window resize can move both).
local widthCache = {}
local cacheKey = nil

-- Fallbacks used only when GetMainViewport is unavailable in this binding.
local FALLBACK_W, FALLBACK_H = 1920, 1080

--- CalcTextSize returns two numbers in this binding, but views/item_display.lua:150-153
--- hedges against an ImVec2 return, so do the same rather than assume.
local function textWidth(s)
    local w = ImGui.CalcTextSize(tostring(s or ""))
    if type(w) == "number" then return w end
    if type(w) == "table" and w.x then return w.x end
    return 0
end
M.textWidth = textWidth

--- Screen geometry. Returns x, y, w, h of the usable area.
--- Uses the viewport's full Pos/Size rather than WorkPos/WorkSize: WorkArea is what
--- OTHER reserved strips have already carved out, and the bars are the thing doing the
--- reserving here — anchoring to the work area would make them drift as they reserve.
function M.viewport()
    local ok, x, y, w, h = pcall(function()
        local vp = ImGui.GetMainViewport and ImGui.GetMainViewport()
        if not vp then return nil end
        local pos, size = vp.Pos, vp.Size
        if not pos or not size then return nil end
        return pos.x, pos.y, size.x, size.y
    end)
    if ok and type(w) == "number" and w > 0 and type(h) == "number" and h > 0 then
        return x or 0, y or 0, w, h
    end
    return 0, 0, FALLBACK_W, FALLBACK_H
end

--- Bar height. Font-relative rather than a hard 30px so the strip stays one line at any
--- font MQ happened to load — the mockup's 30px is the default-font case of this.
function M.barHeight()
    local lh = ImGui.GetTextLineHeight and ImGui.GetTextLineHeight() or 13
    if type(lh) ~= "number" or lh <= 0 then lh = 13 end
    return math.floor(lh + (constants.UI.DOCK_BAR_PADDING_Y or 8) * 2 + 0.5)
end

--- Invalidate measured widths when the font metric or viewport size changes.
--- Cheap enough to call once per frame: two numbers and a string compare.
function M.refreshCacheKey()
    local lh = ImGui.GetTextLineHeight and ImGui.GetTextLineHeight() or 13
    local _, _, w, h = M.viewport()
    local key = string.format("%d:%d:%d", math.floor((tonumber(lh) or 13) * 10), math.floor(w), math.floor(h))
    if key ~= cacheKey then
        cacheKey = key
        widthCache = {}
        return true
    end
    return false
end

--- Width reserved for a slot: the widest of `samples`, measured once and cached under `id`.
--- `samples` must include the widest string the slot can EVER hold, including the states it
--- is not in right now — that is what stops the neighbours sliding around when a segment
--- wakes up. Extra is added on top (for an inline button, an icon, whatever).
function M.slotWidth(id, samples, extra)
    local cached = widthCache[id]
    if cached then return cached end
    local widest = 0
    for _, s in ipairs(samples or {}) do
        local w = textWidth(s)
        if w > widest then widest = w end
    end
    local pad = constants.UI.DOCK_SLOT_PADDING_X or 12
    local out = math.ceil(widest + pad * 2 + (extra or 0))
    widthCache[id] = out
    return out
end

--- Screen rect for a bar. edge is "top" or "bottom"; index 0 is the outermost strip on that
--- edge, 1 sits just inside it (so a top bar and a bottom bar can both be index 0).
function M.barRect(edge, index)
    local x, y, w, h = M.viewport()
    local bh = M.barHeight()
    local offset = bh * (index or 0)
    if edge == "bottom" then
        return x, y + h - bh - offset, w, bh
    end
    return x, y + offset, w, bh
end

--- The area left for companion windows once the bars are subtracted. Phase 4 placement
--- must run inside this, not the raw viewport, or a window can open under a bar.
--- topBars / bottomBars are counts of visible strips on each edge.
function M.workArea(topBars, bottomBars)
    local x, y, w, h = M.viewport()
    local bh = M.barHeight()
    local top = bh * (topBars or 0)
    local bottom = bh * (bottomBars or 0)
    return x, y + top, w, math.max(h - top - bottom, 1)
end

return M
