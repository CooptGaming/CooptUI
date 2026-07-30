--[[
    Type registers for the windows pass (kit §3.2): three sizes, rasterised.

        heading  22px  item names, window headings         pushHeading() … pop()
        body     16px  labels, rows, buttons, bar text     (no push — MQ's default font)
        mono     13px  number columns only                  pushMono() … pop()

    Why this module exists: SetWindowFontScale stretches the rasterised 16px atlas
    bitmap — it is literally the blur. ImGui 1.92's PushFont(font, size) re-rasterises
    the glyphs at the requested size instead (both the DX9 and DX11 backends on the
    pinned MQ set ImGuiBackendFlags_RendererHasTextures, so this holds on the EMU
    client). Heading pushes the default Roboto at 22; mono pushes MQ's ConsoleFont
    (Lucida Console, baked at exactly 13). Never reintroduce SetWindowFontScale.

    Failure posture: the sized PushFont overload is probed once, inside the first frame
    that asks for it. If the binding lacks it (older MQ), heading degrades to the body
    font and mono falls back to the one-argument PushFont(ConsoleFont) — the layout
    stays correct, only the size ambition is dropped. Every push records whether a real
    ImGui push happened, and pop() only pops those, so a degraded or failed push can
    never unbalance the font stack (the render path must survive anything).
]]

local constants = require('itemui.constants')

local M = {}

local ImGui = nil
local function ensureImGui()
    if ImGui then return end
    ImGui = require('ImGui')
end

local K = constants.UI.KIT

local stack = {}      -- per-push: true where a real ImGui.PushFont happened
local sizedOk = nil   -- nil = not probed yet; probe runs inside the first frame that asks

local function probeSizedOverload()
    -- GetDefaultFont and the (font, size) PushFont overload arrived together (1.92);
    -- treat them as one capability. Balanced push/pop inside the pcall, so a throwing
    -- overload leaves no residue.
    local ok = pcall(function()
        local f = ImGui.GetDefaultFont()
        if f == nil then error('no default font') end
        ImGui.PushFont(f, K.FONT_BODY)
        ImGui.PopFont()
    end)
    sizedOk = ok and true or false
end

--- Heading register: default font at 22px. Pair with M.pop().
function M.pushHeading()
    ensureImGui()
    if sizedOk == nil then probeSizedOverload() end
    local pushed = false
    if sizedOk then
        pushed = pcall(function() ImGui.PushFont(ImGui.GetDefaultFont(), K.FONT_HEADING) end)
    end
    stack[#stack + 1] = pushed
end

--- Mono register: ConsoleFont at 13px (its native size). Pair with M.pop().
function M.pushMono()
    ensureImGui()
    if sizedOk == nil then probeSizedOverload() end
    local pushed = false
    local f = ImGui.ConsoleFont
    if f ~= nil then
        if sizedOk then
            pushed = pcall(function() ImGui.PushFont(f, K.FONT_MONO) end)
        end
        if not pushed then
            -- One-argument PushFont(font) predates 1.92 and uses the baked size (13).
            pushed = pcall(function() ImGui.PushFont(f) end)
        end
    end
    stack[#stack + 1] = pushed
end

--- Pop one register pushed by pushHeading/pushMono. Safe when that push degraded to
--- nothing; a pop without any push is a caller bug and is ignored rather than thrown.
function M.pop()
    local pushed = table.remove(stack)
    if pushed then
        pcall(ImGui.PopFont)
    end
end

--- True when the sized PushFont overload is live (after the first push has probed it).
--- Layout code must NOT branch on this — the registers own all sizing decisions.
function M.sizedFontsAvailable()
    return sizedOk == true
end

--- Test hook: forget the probe result and any stack residue between stub frames.
function M._resetForTests()
    stack = {}
    sizedOk = nil
    ImGui = nil
end

return M
