--[[
    CoOpt UI shared theme — colors and text helpers for ItemUI and ScriptTracker.
    Single source so both components share the same look.
--]]

local ImGui = nil  -- set when ImGui is loaded by caller

local function ensureImGui()
    if ImGui then return end
    ImGui = require('ImGui')
end

--- Convert {r,g,b} or {r,g,b,a} (0–1) to ImVec4.
--- Uses global ImVec4 (set by require('ImGui')) — ensure ImGui is loaded first.
local function ToVec4(c)
    ensureImGui()
    if not c then return ImVec4(1, 1, 1, 1) end
    local r = c[1] or 1
    local g = c[2] or 1
    local b = c[3] or 1
    local a = c[4] or 1
    return ImVec4(r, g, b, a)
end

--- Colors: 0–1 RGBA. Used with ToVec4() for ImGui.
local Colors = {
    Error       = { 0.9, 0.25, 0.25, 1 },
    Success     = { 0.25, 0.75, 0.35, 1 },
    Muted       = { 0.5, 0.5, 0.55, 1 },
    -- The Muted split (windows pass §3.1): Muted was doing two jobs. One meaning each now —
    -- TextContent is anything you READ (labels, secondary values); TextFurniture is anything
    -- you IGNORE (separators, hints, units, placeholders). Muted stays for legacy call sites.
    TextContent   = { 0.659, 0.659, 0.698, 1 },  -- #a8a8b2
    TextFurniture = { 0.431, 0.431, 0.471, 1 },  -- #6e6e78
    Warning     = { 0.9, 0.7, 0.2, 1 },
    Header      = { 0.4, 0.75, 1.0, 1 },
    HeaderAlt   = { 0.65, 0.7, 0.75, 1 },
    Info        = { 0.5, 0.7, 0.9, 1 },
    RerollList  = { 0.35, 0.6, 0.95, 1 },  -- blue for Reroll List status in Inventory/Sell/Bank
    EpicQuest   = { 0.7, 0.5, 0.9, 1 },
    Keep = {
        Normal = { 0.2, 0.55, 0.25, 1 },
        Hover  = { 0.3, 0.65, 0.35, 1 },
        Active = { 0.15, 0.45, 0.2, 1 },
    },
    Delete = {
        Normal = { 0.7, 0.25, 0.25, 1 },
        Hover  = { 0.8, 0.35, 0.35, 1 },
        Active = { 0.6, 0.2, 0.2, 1 },
    },
    Junk = {
        Normal = { 0.75, 0.5, 0.2, 1 },
        Hover  = { 0.85, 0.6, 0.3, 1 },
        Active = { 0.65, 0.4, 0.15, 1 },
    },
    Loot = {
        Normal = { 0.2, 0.55, 0.25, 1 },
        Hover  = { 0.3, 0.65, 0.35, 1 },
        Active = { 0.15, 0.45, 0.2, 1 },
    },
    Skip = {
        Normal = { 0.7, 0.25, 0.25, 1 },
        Hover  = { 0.8, 0.35, 0.35, 1 },
        Active = { 0.6, 0.2, 0.2, 1 },
    },
    HP          = { 0.9, 0.3, 0.3, 1 },
    MP          = { 0.3, 0.5, 0.9, 1 },
    Endurance   = { 0.5, 0.7, 0.3, 1 },
    Combat      = { 0.8, 0.6, 0.2, 1 },
    Utility     = { 0.6, 0.8, 0.6, 1 },
    SectionHead = { 0.85, 0.85, 0.7, 1 },
    Highlight   = { 0.9, 0.85, 0.4, 1 },
}

--- The kit palette (windows pass §3.1) — every fill the v2 windows may use, one meaning
--- each. A window that wants a colour outside this table doesn't get one. Two pairs must
--- never be confused: open-state blue (OpenBlue on a bar/tab) vs action blue (ActionBlue
--- on a button), and solid red (stop) vs outlined red (destroy).
local Kit = {
    WindowBg      = { 0.059, 0.059, 0.059, 1 },  -- #0f0f0f  window body
    WindowBorder  = { 0.294, 0.294, 0.322, 1 },  -- #4b4b52  window border
    Header        = { 0.086, 0.106, 0.133, 1 },  -- #161b22  window header band, and hover row
    Inset         = { 0.106, 0.106, 0.106, 1 },  -- #1b1b1b  stat strip, icon buttons, tray cells
    Divider       = { 0.169, 0.169, 0.188, 1 },  -- #2b2b30  every divider; every disabled fill
    OpenBlue      = { 0.259, 0.588, 0.980, 1 },  -- #4296fa  open-state / active tab / cursor-target ring
    OpenWash      = { 0.071, 0.086, 0.110, 1 },  -- #12161c  bar chip fill behind an open window
    ActionBlue    = { 0.137, 0.271, 0.427, 1 },  -- #23456d  action button: navigates or commits
    GoBg          = { 0.106, 0.227, 0.122, 1 },  -- #1b3a1f  go button fill
    GoBorder      = { 0.200, 0.549, 0.251, 1 },  -- #338c40  go button outline
    GoText        = { 0.498, 0.851, 0.561, 1 },  -- #7fd98f  go button label
    StopRed       = { 0.549, 0.169, 0.169, 1 },  -- #8c2b2b  stop button (solid, white label)
    DestroyBg     = { 0.227, 0.106, 0.106, 1 },  -- #3a1b1b  destroy button fill
    DestroyBorder = { 0.549, 0.169, 0.169, 1 },  -- #8c2b2b  destroy button outline
    DestroyText   = { 0.902, 0.565, 0.565, 1 },  -- #e69090  destroy button label
    Good          = { 0.251, 0.749, 0.349, 1 },  -- #40bf59  good, gain, live
    Attention     = { 0.902, 0.702, 0.200, 1 },  -- #e6b333  attention
    Loss          = { 0.902, 0.251, 0.251, 1 },  -- #e64040  loss, blocked
    SpellBlue     = { 0.400, 0.749, 1.000, 1 },  -- #66bfff  spell or effect name
    Mythic        = { 0.784, 0.659, 0.902, 1 },  -- #c8a8e6  mythic and ornament
    WashRunning   = { 0.086, 0.075, 0.063, 1 },  -- #161310  bar segment wash: running
    WashDone      = { 0.059, 0.086, 0.063, 1 },  -- #0f1610  bar segment wash: finished
    WashBad       = { 0.102, 0.063, 0.063, 1 },  -- #1a1010  bar segment wash: stopped badly
}

--- Draw text with Info color.
local function TextInfo(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.Info))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with Muted color.
local function TextMuted(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.Muted))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with TextContent color — labels, secondary values, anything you READ (kit §3.1).
local function TextContent(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.TextContent))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with TextFurniture color — separators, hints, units, placeholders, anything
--- you IGNORE (kit §3.1). If you're printing a value in this colour, you want TextContent.
local function TextFurniture(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.TextFurniture))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with Warning color.
local function TextWarning(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.Warning))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with Success color.
local function TextSuccess(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.Success))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with Header color.
local function TextHeader(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.Header))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with HeaderAlt color (used for section description/subtitle text).
local function TextHeaderAlt(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.HeaderAlt))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw wrapped text with HeaderAlt color (for multi-line description blocks).
local function TextWrappedHeaderAlt(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.HeaderAlt))
    ImGui.TextWrapped(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Draw text with Error color (red — used for destructive labels, missing state).
local function TextError(text)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(Colors.Error))
    ImGui.Text(tostring(text))
    ImGui.PopStyleColor(1)
end

--- Push button colors for Delete (red). Call PopButtonColors() after drawing the button.
local function PushDeleteButton()
    ensureImGui()
    local D = Colors.Delete
    ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(D.Normal))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(D.Hover))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(D.Active))
end

--- Push button colors for Keep (green). disabled=true uses muted style.
local function PushKeepButton(disabled)
    ensureImGui()
    if disabled then
        local M = Colors.Muted
        ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(M))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(M))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(M))
    else
        local K = Colors.Keep
        ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(K.Normal))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(K.Hover))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(K.Active))
    end
end

--- Push button colors for Junk (orange). disabled=true uses muted style.
local function PushJunkButton(disabled)
    ensureImGui()
    if disabled then
        local M = Colors.Muted
        ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(M))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(M))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(M))
    else
        local J = Colors.Junk
        ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(J.Normal))
        ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(J.Hover))
        ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(J.Active))
    end
end

--- Push button colors for Loot (green).
local function PushLootButton()
    ensureImGui()
    local L = Colors.Loot
    ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(L.Normal))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(L.Hover))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(L.Active))
end

--- Push button colors for Skip (red).
local function PushSkipButton()
    ensureImGui()
    local S = Colors.Skip
    ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(S.Normal))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(S.Hover))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(S.Active))
end

--- Pop the three button style colors pushed by Push*Button().
local function PopButtonColors()
    ensureImGui()
    ImGui.PopStyleColor(3)
end

-- ---------------------------------------------------------------- kit buttons (§3.5)
-- Four kinds, and that's the set: go (outlined green, starts something), stop (solid red,
-- interrupts a running job), destroy (outlined red, destroys something you own), action
-- (blue, navigates or commits). Flat and square: every helper pushes FrameRounding=0.
-- Disabled is PushKitDisabledButton, with the reason PRINTED BESIDE the button by the
-- caller (TextFurniture) — never in a tooltip. A green go button becomes its solid-red
-- stop IN PLACE: same slot, same width.
-- Every Push here pushes 5 colors + 2 style vars; pop with PopKitButton, NOT PopButtonColors.

local KitWhite = { 1, 1, 1, 1 }
-- Mechanical light/dark derivations of Kit fills for hover/active states. Not new meanings,
-- so deliberately not in the Kit table.
local KitHover = {
    GoBgHover       = { 0.143, 0.306, 0.165, 1 },
    GoBgActive      = { 0.085, 0.182, 0.098, 1 },
    StopHover       = { 0.659, 0.203, 0.203, 1 },
    StopActive      = { 0.467, 0.144, 0.144, 1 },
    DestroyBgHover  = { 0.306, 0.143, 0.143, 1 },
    DestroyBgActive = { 0.182, 0.085, 0.085, 1 },
    ActionHover     = { 0.171, 0.339, 0.534, 1 },
    ActionActive    = { 0.116, 0.230, 0.363, 1 },
}

local function pushKitButtonColors(bg, hover, active, text, border, borderSize)
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.Button, ToVec4(bg))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, ToVec4(hover))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, ToVec4(active))
    ImGui.PushStyleColor(ImGuiCol.Text, ToVec4(text))
    ImGui.PushStyleColor(ImGuiCol.Border, ToVec4(border))
    ImGui.PushStyleVar(ImGuiStyleVar.FrameRounding, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, borderSize)
end

--- Go: outlined green — starts something.
local function PushGoButton()
    pushKitButtonColors(Kit.GoBg, KitHover.GoBgHover, KitHover.GoBgActive, Kit.GoText, Kit.GoBorder, 1)
end

--- Stop: solid red, white label — interrupts a running job.
local function PushStopButton()
    pushKitButtonColors(Kit.StopRed, KitHover.StopHover, KitHover.StopActive, KitWhite, Kit.StopRed, 0)
end

--- Destroy: outlined red — destroys something you own.
local function PushDestroyButton()
    pushKitButtonColors(Kit.DestroyBg, KitHover.DestroyBgHover, KitHover.DestroyBgActive, Kit.DestroyText, Kit.DestroyBorder, 1)
end

--- Action: solid blue — navigates or commits (Insert, Send, Open X).
local function PushActionButton()
    pushKitButtonColors(Kit.ActionBlue, KitHover.ActionHover, KitHover.ActionActive, KitWhite, Kit.ActionBlue, 0)
end

--- Disabled: flat #2b2b30, no hover response. The caller prints the reason beside the
--- button (TextFurniture) — never in a tooltip.
local function PushKitDisabledButton()
    pushKitButtonColors(Kit.Divider, Kit.Divider, Kit.Divider, Colors.TextFurniture, Kit.Divider, 0)
end

--- Inset icon button (window-header actions, tray cells): #1b1b1b fill, content-grey glyph.
local function PushIconButton()
    pushKitButtonColors(Kit.Inset, Kit.Header, Kit.Inset, Colors.TextContent, Kit.Inset, 0)
end

--- Pop what any kit Push*Button pushed: 5 colors + 2 style vars.
local function PopKitButton()
    ensureImGui()
    ImGui.PopStyleColor(5)
    ImGui.PopStyleVar(2)
end

--- Push style color for progress bar fill (e.g. sell/loot progress). Call PopProgressBarColors() after.
local function PushProgressBarColors()
    ensureImGui()
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, ToVec4(Colors.Success))
end

--- Pop progress bar style color.
local function PopProgressBarColors()
    ensureImGui()
    ImGui.PopStyleColor(1)
end

--- Render a standard section break: Spacing + Separator + Spacing.
--- Replaces the common triple idiom used ~188 times across views.
local function SectionBreak()
    ensureImGui()
    ImGui.Spacing()
    ImGui.Separator()
    ImGui.Spacing()
end

--- Render content indented by INDENT px (from constants.UI.INDENT).
--- fn() is called between Indent/Unindent.
local INDENT_PX = 10  -- mirrors constants.UI.INDENT; avoids circular require
local function IndentBlock(fn)
    ensureImGui()
    ImGui.Indent(INDENT_PX)
    fn()
    ImGui.Unindent(INDENT_PX)
end

--- Draw a themed progress bar (push colors, draw, pop). Single path for Sell/Loot UI (Phase 5).
--- fraction: 0..1, size: ImVec2, overlay: optional string (e.g. "15 / 20").
local function RenderProgressBar(fraction, size, overlay)
    ensureImGui()
    PushProgressBarColors()
    ImGui.ProgressBar(fraction, size, overlay or "")
    PopProgressBarColors()
end

return {
    ToVec4 = ToVec4,
    Colors = Colors,
    Kit = Kit,
    TextInfo = TextInfo,
    TextMuted = TextMuted,
    TextContent = TextContent,
    TextFurniture = TextFurniture,
    TextWarning = TextWarning,
    TextSuccess = TextSuccess,
    TextHeader = TextHeader,
    TextHeaderAlt = TextHeaderAlt,
    TextWrappedHeaderAlt = TextWrappedHeaderAlt,
    TextError = TextError,
    PushDeleteButton = PushDeleteButton,
    PushKeepButton = PushKeepButton,
    PushJunkButton = PushJunkButton,
    PushLootButton = PushLootButton,
    PushSkipButton = PushSkipButton,
    PopButtonColors = PopButtonColors,
    PushGoButton = PushGoButton,
    PushStopButton = PushStopButton,
    PushDestroyButton = PushDestroyButton,
    PushActionButton = PushActionButton,
    PushKitDisabledButton = PushKitDisabledButton,
    PushIconButton = PushIconButton,
    PopKitButton = PopKitButton,
    PushProgressBarColors = PushProgressBarColors,
    PopProgressBarColors = PopProgressBarColors,
    RenderProgressBar = RenderProgressBar,
    SectionBreak = SectionBreak,
    IndentBlock = IndentBlock,
}
