-- A recording ImGui stub, so the bars' RENDER path can be exercised without the game.
--
-- It is not a layout engine and cannot tell you anything about pixels. What it does give you,
-- mechanically rather than by code review:
--
--   * STACK BALANCE. Every Begin/End, BeginChild/EndChild, BeginGroup/EndGroup, PushStyleVar/
--     PopStyleVar(n), PushStyleColor/PopStyleColor(n) and PushID/PopID is counted, including
--     across a pcall that swallowed an error mid-frame. An imbalance here is the leak that
--     ends in an ImGui assert after a few thousand frames -- the exact failure a regex over
--     the source can only guess at.
--   * WHAT WAS ACTUALLY DRAWN. Every string reaches `rec.text`, so a test can assert the loot
--     slot really says "corpse 4/9" rather than trusting that the fields behind it are right.
--   * RENDER-PATH PURITY. mq.TLO is a trap: any access is recorded, so "no TLO calls in the
--     render path" becomes an assertion instead of a rule someone has to remember.
--   * INPUT. Hover and click are scriptable per widget id, which is enough to drive the
--     popover/menu open-close-pin logic and the Esc handling.
--
-- Usage:
--   local stub = require('imgui_stub')
--   stub.install()                       -- sets the ImGui global + enum tables + ImVec2/4
--   stub.frame(function() ... end)        -- runs one frame, returns the recording
--
-- Deliberately NOT modelled: real widths (CalcTextSize returns len * a constant), clipping,
-- z-order, and anything about focus. Tests must not assert on those.

local M = {}

local rec  -- current frame recording; pre-seeded below so a stray ImGui call OUTSIDE
           -- M.frame records into a throwaway table instead of crashing the stub itself

-- ---------------------------------------------------------------- recording
local function newRec()
    return {
        text = {},          -- every string drawn, in order
        buttons = {},       -- every button/selectable label offered, in order
        buttonSizes = {},   -- { label, w, h } per sized ImGui.Button call, in order
        progressBars = 0,   -- how many ImGui.ProgressBar calls this frame
        progressBarSizes = {},  -- { w, h } per ProgressBar call, in order
        windows = {},       -- names passed to Begin
        childArgs = {},     -- every BeginChild call's raw args (name/a/b/c/d), in order
        depth = { win = 0, child = 0, group = 0, id = 0, sv = 0, sc = 0, font = 0, menu = 0, tab = 0, tbl = 0 },
        max = { win = 0, child = 0 },
        tloAccess = {},     -- any mq.TLO.* touched during the frame
        commands = {},      -- any mq.cmd/cmdf issued during the frame
        draws = {},         -- every ImDrawList primitive, in order (see M.drawList)
        styleColors = {},   -- { idx, col } per PushStyleColor, in order
        errors = {},
    }
end

rec = newRec()

--- Widgets that should report hovered / clicked this frame, keyed by the label substring.
M.hover = {}
M.click = {}
--- Popups that report open (id substring), and submenus forced shut (label substring).
M.openPopups = {}
M.closedMenus = {}

--- Make a named ImGui call raise, e.g. M.throwOn = { CalcTextSize = true }. This models the
--- real failure the first in-game run hit: something between Begin and End threw, app.lua's
--- pcall swallowed it, End() never ran, and ImGui reported "Missing End()" with no Lua error
--- to go on. A stub where nothing ever throws cannot see that class at all.
M.throwOn = {}

--- Force BeginChild to report the child as clipped/invisible. Real ImGui does this routinely
--- (a child scrolled out of view), and the original stub always returning true meant the
--- false branch was never exercised.
M.childInvisible = false
M.keys  = {}    -- e.g. { Escape = true }
M.mouse = {}    -- e.g. { [2] = true } for a middle-click (ImGuiMouseButton.Middle)
--- Geometry overrides: { w, h } for GetWindowSize / GetContentRegionAvail. nil keeps the
--- historical defaults (2560x30 bar / 400x300 region) that older suites assert against.
M.windowSize = nil
M.contentAvail = nil

local function matches(set, label)
    if not label then return false end
    for k, v in pairs(set) do
        if v and string.find(tostring(label), tostring(k), 1, true) then return true end
    end
    return false
end

-- ---------------------------------------------------------------- vec types
local function vec2(x, y) return { x = x or 0, y = y or 0 } end
local function vec4(r, g, b, a) return { x = r or 0, y = g or 0, z = b or 0, w = a or 1 } end

-- ---------------------------------------------------------------- the stub
local lastLabel = nil

local function addText(s)
    if s ~= nil then rec.text[#rec.text + 1] = tostring(s) end
end

local ImGuiStub = {}

-- windows -------------------------------------------------------------------
function ImGuiStub.Begin(name, open, _flags)
    rec.windows[#rec.windows + 1] = name
    rec.depth.win = rec.depth.win + 1
    if rec.depth.win > rec.max.win then rec.max.win = rec.depth.win end
    return (open == nil) and true or open, true      -- (open, visible)
end
function ImGuiStub.End() rec.depth.win = rec.depth.win - 1 end

-- Child names are stacked so EndChild can restore lastLabel. In real ImGui the child window
-- becomes the "last item" once EndChild returns, which is what makes
-- `EndChild(); IsItemHovered()` a valid way to ask "is the mouse over that child" -- the
-- pattern dock_top uses for its slots. Without this the label is whatever the segment drew
-- INSIDE the child, and hover never matches the slot.
local childStack = {}
function ImGuiStub.BeginChild(name, a, b, c, d)
    lastLabel = name
    childStack[#childStack + 1] = name
    rec.depth.child = rec.depth.child + 1
    if rec.depth.child > rec.max.child then rec.max.child = rec.depth.child end
    -- Arg recording, both binding formats (lua_ImGuiCore.cpp:438-457): the deprecated
    -- (name, sx, sy, boolBorder, flags) and the new (name, sx, sy, childFlags, flags).
    -- Position 4's TYPE is what disambiguates them in sol2, so it is preserved raw here
    -- and tests assert on it — the ResizeX+NoSavedSettings pairing is load-bearing.
    rec.childArgs[#rec.childArgs + 1] = { name = name, a = a, b = b, c = c, d = d }
    -- Real ImGui returns false for a clipped/invisible child, and EndChild must STILL be
    -- called. Returning false here proves callers do that.
    return not M.childInvisible
end
function ImGuiStub.EndChild()
    rec.depth.child = rec.depth.child - 1
    lastLabel = childStack[#childStack]
    childStack[#childStack] = nil
end

function ImGuiStub.BeginGroup() rec.depth.group = rec.depth.group + 1 end
function ImGuiStub.EndGroup() rec.depth.group = rec.depth.group - 1 end

function ImGuiStub.BeginTooltip() rec.depth.win = rec.depth.win + 1 end
function ImGuiStub.EndTooltip() rec.depth.win = rec.depth.win - 1 end

-- stacks --------------------------------------------------------------------
function ImGuiStub.PushStyleVar() rec.depth.sv = rec.depth.sv + 1 end
function ImGuiStub.PopStyleVar(n) rec.depth.sv = rec.depth.sv - (n or 1) end
-- Records WHICH colour, not just that one was pushed: "the open chip is filled with the
-- open-blue wash, not the go-green" is a real assertion, and it was not previously
-- expressible (the bottom bar shipped the wrong one for a whole phase).
local function packVec(v)
    if type(v) == 'table' and v.x then
        return string.format('%.3f,%.3f,%.3f,%.3f', v.x or 0, v.y or 0, v.z or 0, v.w or 1)
    end
    return v
end
function ImGuiStub.PushStyleColor(idx, v)
    rec.depth.sc = rec.depth.sc + 1
    rec.styleColors[#rec.styleColors + 1] = { idx = idx, col = packVec(v) }
end
function ImGuiStub.PopStyleColor(n) rec.depth.sc = rec.depth.sc - (n or 1) end
function ImGuiStub.PushID() rec.depth.id = rec.depth.id + 1 end
function ImGuiStub.PopID() rec.depth.id = rec.depth.id - 1 end
function ImGuiStub.PushTextWrapPos() end
function ImGuiStub.PopTextWrapPos() end

-- text ----------------------------------------------------------------------
function ImGuiStub.Text(s) lastLabel = s; addText(s) end
function ImGuiStub.TextUnformatted(s) lastLabel = s; addText(s) end
function ImGuiStub.TextColored(_c, s) lastLabel = s; addText(s) end
function ImGuiStub.TextWrapped(s) lastLabel = s; addText(s) end
function ImGuiStub.TextDisabled(s) lastLabel = s; addText(s) end
function ImGuiStub.Separator() end
function ImGuiStub.SeparatorText(s) addText(s) end
function ImGuiStub.Spacing() end
function ImGuiStub.SetNextItemWidth() end
function ImGuiStub.NewLine() end
function ImGuiStub.Dummy() end
function ImGuiStub.Indent() end
function ImGuiStub.Unindent() end
function ImGuiStub.SameLine() end
function ImGuiStub.AlignTextToFramePadding() end
function ImGuiStub.SetWindowFontScale() end

-- fonts ---------------------------------------------------------------------
-- Sentinel handles: identity is all render code may rely on. PushFont mirrors the 1.92
-- binding's overloads — (), (font) and (font, size) — and joins the balance count like
-- every other stack; utils/fonts.lua's degrade-gracefully paths all still push and pop
-- through here, so an unbalanced register shows up as depth.font ~= 0.
local stubDefaultFont = { Name = 'RobotoRegular (stub)', LegacySize = 16 }
ImGuiStub.ConsoleFont = { Name = 'LucidaConsole (stub)', LegacySize = 13 }
function ImGuiStub.GetDefaultFont() return stubDefaultFont end
function ImGuiStub.PushFont(_font, _size) rec.depth.font = rec.depth.font + 1 end
function ImGuiStub.PopFont() rec.depth.font = rec.depth.font - 1 end

-- widgets -------------------------------------------------------------------
local function widget(label)
    lastLabel = label
    rec.buttons[#rec.buttons + 1] = label
    return matches(M.click, label)
end
-- Button records its REQUESTED size too. The stub is not a layout engine and never will
-- be, but "how tall did the caller ask for" is a plain fact worth asserting: a bar button
-- taller than one text line clips against its segment child, which shipped once.
function ImGuiStub.Button(label, size)
    local h, w
    if type(size) == 'table' then w, h = size.x, size.y end
    rec.buttonSizes[#rec.buttonSizes + 1] = { label = tostring(label), w = w, h = h }
    return widget(label)
end
function ImGuiStub.SmallButton(label) return widget(label) end
-- A real item (hoverable, clickable, occupies layout) that draws nothing itself — the
-- caller paints it via the draw list. The bottom bar's unread dots are exactly this.
function ImGuiStub.InvisibleButton(label, size)
    local h, w
    if type(size) == 'table' then w, h = size.x, size.y end
    rec.buttonSizes[#rec.buttonSizes + 1] = { label = tostring(label), w = w, h = h }
    return widget(label)
end
-- (selected, pressed) -- selected FIRST, like the binding (lua_ImGuiWidgets.cpp:906,
-- std::make_tuple(selected, pressed)). `if ImGui.Selectable(label, true)` therefore takes the
-- branch EVERY frame, not on click; callers must read the SECOND return for the click.
function ImGuiStub.Selectable(label, sel)
    local pressed = widget(label)
    if sel == nil then sel = false end
    if pressed then sel = not sel end
    return sel, pressed
end
function ImGuiStub.Checkbox(label, v) lastLabel = label; rec.buttons[#rec.buttons + 1] = label; return v end
function ImGuiStub.RadioButton(label, active) lastLabel = label; rec.buttons[#rec.buttons + 1] = label; return matches(M.click, label) and not active end
--- Faithful enough for section-memory tests: SetNextItemOpen forces the next header's
--- state (consumed once, like real ImGui); a matching M.click flips it (user toggle).
local nextItemOpen = nil
function ImGuiStub.SetNextItemOpen(v) nextItemOpen = v and true or false end
function ImGuiStub.CollapsingHeader(label)
    addText(label)
    rec.buttons[#rec.buttons + 1] = label
    local open = nextItemOpen
    nextItemOpen = nil
    if open == nil then open = true end
    if matches(M.click, label) then open = not open end
    return open
end
-- Records the requested size. Same reason Button does: a bar taller than the one-line
-- segment child clips, and "how tall did the caller ask for" is a plain assertable fact.
function ImGuiStub.ProgressBar(_frac, size)
    rec.progressBars = (rec.progressBars or 0) + 1
    local w, h
    if type(size) == 'table' then w, h = size.x, size.y end
    rec.progressBarSizes[#rec.progressBarSizes + 1] = { w = w, h = h }
end
function ImGuiStub.InputText(_id, buf) return buf, false end
-- popups & menus -------------------------------------------------------------
-- Closed by default like real ImGui. A test opens one by putting an id substring in
-- M.openPopups; an open popup counts as a window (EndPopup closes it), so imbalance
-- shows up in depth.win. BeginMenu returns true by default so submenu CONTENTS are
-- recorded; menus a test wants shut go in M.closedMenus by label substring.
function ImGuiStub.BeginPopupContextItem(id)
    if not matches(M.openPopups, id) then return false end
    rec.depth.win = rec.depth.win + 1
    return true
end
function ImGuiStub.BeginPopup(id)
    if not matches(M.openPopups, id) then return false end
    rec.depth.win = rec.depth.win + 1
    return true
end
function ImGuiStub.EndPopup() rec.depth.win = rec.depth.win - 1 end
function ImGuiStub.OpenPopup() end
function ImGuiStub.CloseCurrentPopup() end
-- Tab bars: every tab reports selected so tests exercise all tab bodies in one frame
-- (real ImGui shows one). Balance rides the tab counter.
function ImGuiStub.BeginTabBar() rec.depth.tab = rec.depth.tab + 1; return true end
function ImGuiStub.EndTabBar() rec.depth.tab = rec.depth.tab - 1 end
function ImGuiStub.BeginTabItem(label) addText(label); rec.depth.tab = rec.depth.tab + 1; return true, true end
function ImGuiStub.EndTabItem() rec.depth.tab = rec.depth.tab - 1 end
function ImGuiStub.BeginMenu(label)
    lastLabel = label
    rec.buttons[#rec.buttons + 1] = label
    if matches(M.closedMenus, label) then return false end
    rec.depth.menu = rec.depth.menu + 1
    return true
end
function ImGuiStub.EndMenu() rec.depth.menu = rec.depth.menu - 1 end
--- Faithful to the MQ binding (lua_ImGuiWidgets.cpp:942): returns (activated, value) —
--- activated FIRST. With a `selected` arg the second return is the toggled value;
--- without one it mirrors activated. enabled=false blocks activation entirely.
function ImGuiStub.MenuItem(label, _shortcut, selected, enabled)
    lastLabel = label
    rec.buttons[#rec.buttons + 1] = label
    addText(label)
    local activated = enabled ~= false and matches(M.click, label) or false
    local value
    if selected ~= nil then
        value = selected
        if activated then value = not selected end
    else
        value = activated
    end
    return activated, value
end

-- queries -------------------------------------------------------------------
function ImGuiStub.IsItemHovered() return matches(M.hover, lastLabel) end
function ImGuiStub.IsWindowHovered() return M.windowHovered == true end
function ImGuiStub.IsItemDeactivatedAfterEdit() return false end
function ImGuiStub.IsKeyPressed(k) return M.keys[k] == true end
function ImGuiStub.IsMouseClicked(b) return M.mouse[b] == true end
function ImGuiStub.IsMouseReleased() return false end
function ImGuiStub.GetIO()
    return { KeyShift = M.keys.Shift == true, WantTextInput = false, WantCaptureMouse = false }
end

-- geometry ------------------------------------------------------------------
--- Viewport override, so a test can ask "what does this bar do at 1280 wide" without a
--- game. Set M.viewportSize = { w, h }; nil restores the 2560x1440 default. GetWindowWidth
--- follows it, because a full-width bar IS the viewport width.
M.viewportSize = nil
local function vpW() return (M.viewportSize and M.viewportSize[1]) or 2560 end
local function vpH() return (M.viewportSize and M.viewportSize[2]) or 1440 end
function ImGuiStub.GetMainViewport()
    return { Pos = vec2(0, 0), Size = vec2(vpW(), vpH()),
             WorkPos = vec2(0, 0), WorkSize = vec2(vpW(), vpH()), ID = 0 }
end
function ImGuiStub.GetTextLineHeight() return 14 end
function ImGuiStub.GetTextLineHeightWithSpacing() return 18 end
function ImGuiStub.CalcTextSize(s) return #tostring(s or "") * 7, 14 end
function ImGuiStub.GetWindowWidth() return vpW() end
function ImGuiStub.GetWindowHeight() return 30 end
function ImGuiStub.GetWindowSize()
    local ws = M.windowSize
    if ws then return ws[1] or 2560, ws[2] or 30 end
    return 2560, 30
end
function ImGuiStub.GetContentRegionAvail()
    local ca = M.contentAvail
    if ca then return ca[1] or 400, ca[2] or 300 end
    return 400, 300
end
function ImGuiStub.GetWindowPos() return 100, 100 end
local stubStyle = { FramePadding = { x = 4, y = 3 }, ItemSpacing = { x = 8, y = 4 } }
function ImGuiStub.GetStyle() return stubStyle end
function ImGuiStub.GetStyleColorVec4() return vec4(0.5, 0.5, 0.5, 1) end
function ImGuiStub.GetCursorPosX() return 400 end
function ImGuiStub.GetCursorPos() return 0, 0 end
function ImGuiStub.SetCursorPos() end
function ImGuiStub.SetCursorPosX() end
-- TWO NUMBERS, not an ImVec2 -- MQ registers these as tuple returns (lua_ImGuiCore.cpp:879,
-- std::make_tuple(v.x, v.y)); the ImVec2-returning variants are the *Vec names. The stub's
-- first version returned a .x-indexable table here, which let `rmin.x` pass every test while
-- throwing in the game -- the exact bug that blanked both bars after their first element.
function ImGuiStub.GetItemRectMin() return 100, 0 end
function ImGuiStub.GetItemRectMax() return 200, 30 end
function ImGuiStub.GetItemRectMinVec() return vec2(100, 0) end
function ImGuiStub.GetItemRectMaxVec() return vec2(200, 30) end
function ImGuiStub.SetNextWindowPos() end
function ImGuiStub.SetNextWindowSize() end
function ImGuiStub.SetNextWindowSizeConstraints() end
function ImGuiStub.SetNextFrameWantCaptureKeyboard() end
function ImGuiStub.SetKeyboardFocusHere() end
-- A RECORDING draw list. It used to be nil, which meant every draw-list guard
-- (`if not dl then return end`) short-circuited and no primitive was ever exercised — so
-- "the status dot is a filled square" and "the lit chip has no accent" were both invisible
-- to the suite. Colours are recorded as whatever GetColorU32 was handed, so a test can ask
-- WHICH colour a dot got, not just that one was drawn. Methods take an explicit self
-- (colon call), like the binding: ImDrawList is a usertype, and a dot-call is a real bug
-- the stub must not paper over — hence the self-shape assertion in each.
local function drawListSelfCheck(self, name)
    if self ~= M.drawList then
        rec.errors[#rec.errors + 1] = 'ImDrawList:' .. name .. ' called without self (dot call?)'
    end
end
M.drawList = {
    AddRectFilled = function(self, a, b, col)
        drawListSelfCheck(self, 'AddRectFilled')
        rec.draws[#rec.draws + 1] = { kind = 'rectFilled', x1 = a and a.x, y1 = a and a.y,
            x2 = b and b.x, y2 = b and b.y, col = col }
    end,
    AddRect = function(self, a, b, col)
        drawListSelfCheck(self, 'AddRect')
        rec.draws[#rec.draws + 1] = { kind = 'rect', x1 = a and a.x, y1 = a and a.y,
            x2 = b and b.x, y2 = b and b.y, col = col }
    end,
    AddCircleFilled = function(self, c, r, col)
        drawListSelfCheck(self, 'AddCircleFilled')
        rec.draws[#rec.draws + 1] = { kind = 'circleFilled', x = c and c.x, y = c and c.y,
            r = r, col = col }
    end,
    AddLine = function(self, a, b, col)
        drawListSelfCheck(self, 'AddLine')
        rec.draws[#rec.draws + 1] = { kind = 'line', x1 = a and a.x, y1 = a and a.y,
            x2 = b and b.x, y2 = b and b.y, col = col }
    end,
    AddText = function(self, p, col, s)
        drawListSelfCheck(self, 'AddText')
        rec.draws[#rec.draws + 1] = { kind = 'text', x = p and p.x, y = p and p.y,
            col = col, text = tostring(s) }
    end,
}
function ImGuiStub.GetWindowDrawList() return M.drawList end
--- Packs the vec back into something a test can compare. Not ImGui's real ABGR packing —
--- it only has to round-trip, so `stub.colorOf(theme.Kit.OpenBlue)` names a recorded colour.
function ImGuiStub.GetColorU32(v)
    if type(v) == 'table' and v.x then
        return string.format('%.3f,%.3f,%.3f,%.3f', v.x or 0, v.y or 0, v.z or 0, v.w or 1)
    end
    return v or 0
end
function M.colorOf(rgba)
    return string.format('%.3f,%.3f,%.3f,%.3f', rgba[1] or 0, rgba[2] or 0, rgba[3] or 0, rgba[4] or 1)
end
--- Every draw-list primitive of `kind` this frame (nil = all of them).
function M.draws(r, kind)
    local out = {}
    for _, d in ipairs((r or rec).draws or {}) do
        if not kind or d.kind == kind then out[#out + 1] = d end
    end
    return out
end

--- Was `rgba` (a theme colour table) pushed as a style colour this frame?
function M.pushedColor(r, rgba)
    local want = M.colorOf(rgba)
    for _, c in ipairs((r or rec).styleColors or {}) do
        if c.col == want then return true end
    end
    return false
end

--- Was `rgba` handed to a draw-list primitive this frame (any kind, or one kind)?
function M.drewColor(r, rgba, kind)
    local want = M.colorOf(rgba)
    for _, d in ipairs(M.draws(r, kind)) do
        if d.col == want then return true end
    end
    return false
end

-- tables --------------------------------------------------------------------
-- Modeled just enough for the row loops to run: BeginTable returns true (a false return
-- means "skip the body AND EndTable" in real ImGui, so tests that want the false branch
-- can throwOn it instead), the sort-spec object is nil (every caller guards), and the
-- hovered column is -1 (no header menu). Column layout itself is not modeled.
function ImGuiStub.BeginTable(_id, _nCols, _flags)
    rec.depth.tbl = rec.depth.tbl + 1
    return true
end
function ImGuiStub.EndTable() rec.depth.tbl = rec.depth.tbl - 1 end
function ImGuiStub.TableSetupColumn() end
function ImGuiStub.TableSetupScrollFreeze() end
function ImGuiStub.TableHeadersRow() end
function ImGuiStub.TableNextRow() end
function ImGuiStub.TableNextColumn() return true end
function ImGuiStub.TableSetBgColor() end
function ImGuiStub.TableGetSortSpecs() return nil end
function ImGuiStub.TableGetHoveredColumn() return -1 end

--- Wrap every entry so M.throwOn can make a named call raise.
for name, fn in pairs(ImGuiStub) do
    if type(fn) == 'function' then
        ImGuiStub[name] = function(...)
            if M.throwOn[name] then error('injected failure in ImGui.' .. name, 2) end
            return fn(...)
        end
    end
end

--- Anything the bars reach for that is not modelled returns nil rather than exploding, but
--- the access is recorded so a test can notice a genuinely missing stub.
M.missing = {}
setmetatable(ImGuiStub, {
    __index = function(_, k)
        M.missing[k] = (M.missing[k] or 0) + 1
        return nil
    end,
})

-- ---------------------------------------------------------------- install
function M.install()
    _G.ImGui = ImGuiStub
    _G.ImVec2 = vec2
    _G.ImVec4 = vec4
    package.loaded['ImGui'] = ImGuiStub

    -- bit32 is a host shim in MQ; LuaJIT ships `bit`.
    if not _G.bit32 then
        local ok, b = pcall(require, 'bit')
        _G.bit32 = ok and { bor = b.bor, band = b.band, bnot = b.bnot } or {
            bor = function(a, c) return (a or 0) + (c or 0) end,
        }
    end

    -- Enum tables. Values only have to be distinct; nothing here depends on the real numbers.
    local function enum(names)
        local t, i = {}, 1
        for _, n in ipairs(names) do t[n] = i; i = i * 2 end
        return t
    end
    _G.ImGuiWindowFlags = enum({ 'None', 'NoTitleBar', 'NoResize', 'NoMove', 'NoScrollbar',
        'NoScrollWithMouse', 'NoCollapse', 'AlwaysAutoResize', 'NoSavedSettings',
        'NoFocusOnAppearing', 'NoBringToFrontOnFocus', 'NoNav', 'NoDocking', 'NoBackground',
        'AlwaysVerticalScrollbar', 'MenuBar' })
    _G.ImGuiCol = enum({ 'Text', 'Button', 'ButtonHovered', 'ButtonActive', 'ChildBg',
        'Border', 'PlotHistogram', 'Header', 'HeaderHovered', 'HeaderActive' })
    _G.ImGuiStyleVar = enum({ 'Alpha', 'WindowRounding', 'WindowBorderSize', 'WindowPadding',
        'ItemSpacing', 'ChildBorderSize', 'ChildRounding', 'FramePadding',
        'FrameRounding', 'FrameBorderSize' })
    _G.ImGuiKey = enum({ 'Escape', 'F1', 'F2', 'Tab', 'Enter' })
    _G.ImGuiMouseButton = { Left = 0, Right = 1, Middle = 2 }
    _G.ImGuiHoveredFlags = enum({ 'None', 'ChildWindows', 'AllowWhenBlockedByPopup' })
    _G.ImGuiTreeNodeFlags = enum({ 'None', 'DefaultOpen' })
    _G.ImGuiSelectableFlags = enum({ 'None' })
    _G.ImGuiInputTextFlags = enum({ 'None', 'CharsDecimal' })
    _G.ImGuiSortDirection = { None = 0, Ascending = 1, Descending = 2 }
    _G.ImGuiCond = enum({ 'None', 'Always', 'Once', 'FirstUseEver', 'Appearing' })
    -- Both spellings: the real binding enums 'Borders' (1.92 name); 'Border' kept for any
    -- older caller. ResizeX is the splitter flag the merged Inventory pairs with
    -- NoSavedSettings (lua_ImGuiEnums.cpp:73-77).
    _G.ImGuiChildFlags = enum({ 'None', 'Border', 'Borders', 'AlwaysUseWindowPadding', 'ResizeX', 'ResizeY' })
    _G.ImGuiTableColumnFlags = enum({ 'None', 'WidthStretch', 'WidthFixed', 'DefaultSort' })
    _G.ImGuiTableBgTarget = { None = 0, RowBg0 = 1, RowBg1 = 2, CellBg = 3 }
    -- One-pass clipper: Step() hands back the whole range once, so row loops render every
    -- item under test instead of a viewport's worth.
    _G.ImGuiListClipper = {
        new = function()
            local c = { DisplayStart = 0, DisplayEnd = 0 }
            function c.Begin(self, n) self._n = n or 0; self._stepped = false end
            function c.Step(self)
                if self._stepped then return false end
                self._stepped = true
                self.DisplayStart = 0
                self.DisplayEnd = self._n or 0
                return true
            end
            return c
        end,
    }
end

--- An mq stub whose TLO is a trap: touching it during a frame is recorded, which is how the
--- "no TLO calls in the render path" rule becomes testable.
--- The stub clock, in milliseconds. Tests MUST advance it between frames when exercising
--- anything time-based: the popover and menu close on a DOCK_POPOVER_GRACE_MS mouse-out
--- window, so a frozen clock leaves them open forever and every later frame inherits a stray
--- window. Advance with M.advance(ms).
M.now = 100000
function M.advance(ms) M.now = M.now + (ms or 1) end

function M.newMq(opts)
    opts = opts or {}
    if opts.now then M.now = opts.now end
    local trap
    trap = setmetatable({}, {
        __index = function(_, k)
            if rec then rec.tloAccess[#rec.tloAccess + 1] = tostring(k) end
            return trap
        end,
        __call = function() return nil end,
    })
    return {
        gettime = function() return M.now end,
        cmd     = function(c) if rec then rec.commands[#rec.commands + 1] = c end end,
        cmdf    = function(f, ...) if rec then rec.commands[#rec.commands + 1] = string.format(f, ...) end end,
        delay   = function() end,
        event   = function() end,
        TLO     = trap,
        imgui   = { init = function() end, destroy = function() end },
    }
end

--- Run one frame. Returns the recording; `ok`/`err` report whether fn threw.
function M.frame(fn)
    rec = newRec()
    local ok, err = pcall(fn)
    if not ok then rec.errors[#rec.errors + 1] = tostring(err) end
    rec.ok = ok
    rec.err = err
    return rec
end

--- Convenience: did any drawn string contain `needle`?
function M.drew(r, needle)
    for _, s in ipairs(r.text) do
        if string.find(s, needle, 1, true) then return true end
    end
    for _, s in ipairs(r.buttons) do
        if s and string.find(tostring(s), needle, 1, true) then return true end
    end
    return false
end

--- Every stack back to zero, and no window/child left open.
function M.balanced(r)
    local d = r.depth
    return d.win == 0 and d.child == 0 and d.group == 0 and d.id == 0 and d.sv == 0 and d.sc == 0
        and d.font == 0 and d.tab == 0 and d.menu == 0 and d.tbl == 0
end

function M.imbalance(r)
    local out, d = {}, r.depth
    for _, k in ipairs({ 'win', 'child', 'group', 'id', 'sv', 'sc', 'font', 'menu', 'tab' }) do
        if d[k] ~= 0 then out[#out + 1] = string.format('%s=%+d', k, d[k]) end
    end
    return table.concat(out, ' ')
end

return M
