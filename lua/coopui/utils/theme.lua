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
    Warning     = { 0.9, 0.7, 0.2, 1 },
    Header      = { 0.4, 0.75, 1.0, 1 },
    HeaderAlt   = { 0.65, 0.7, 0.75, 1 },
    Info        = { 0.5, 0.7, 0.9, 1 },
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
    TextInfo = TextInfo,
    TextMuted = TextMuted,
    TextWarning = TextWarning,
    TextSuccess = TextSuccess,
    TextHeader = TextHeader,
    PushDeleteButton = PushDeleteButton,
    PushKeepButton = PushKeepButton,
    PushJunkButton = PushJunkButton,
    PushLootButton = PushLootButton,
    PushSkipButton = PushSkipButton,
    PopButtonColors = PopButtonColors,
    PushProgressBarColors = PushProgressBarColors,
    PopProgressBarColors = PopProgressBarColors,
    RenderProgressBar = RenderProgressBar,
}
