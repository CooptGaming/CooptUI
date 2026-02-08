--[[
    CoopUI shared theme — colors and text helpers for ItemUI and ScriptTracker.
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

return {
    ToVec4 = ToVec4,
    Colors = Colors,
    TextInfo = TextInfo,
    TextMuted = TextMuted,
    TextWarning = TextWarning,
}
