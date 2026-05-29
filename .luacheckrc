-- luacheck configuration for CoOpt UI
-- The addon runs inside MacroQuest2's MQ2Lua, which is LuaJIT (Lua 5.1 semantics).
-- Goal of this gate: catch the "loads fine, crashes on a player later" bug classes
-- (undefined globals/locals, use-before-declaration, accidental globals, shadowing)
-- without drowning in cosmetic noise.

std = "luajit"
max_line_length = false

-- Globals injected by the MQ2Lua host and the ImGui binding. These are read-only
-- from our code's perspective, so list them as read_globals to avoid false
-- "accessing undefined variable" reports.
read_globals = {
    -- Core handles
    "mq",          -- usually `local mq = require('mq')`, but allow the global form too
    "ImGui",       -- require('ImGui') also publishes the global ImGui table
    "ImVec2", "ImVec4", "ImColor",
    -- bit32 is provided by the host shim (LuaJIT itself ships `bit`, covered by std)
    "bit32",
    -- ImGui enum tables (each is a global table exposed by the binding)
    "ImGuiWindowFlags", "ImGuiChildFlags", "ImGuiInputTextFlags", "ImGuiTreeNodeFlags",
    "ImGuiPopupFlags", "ImGuiSelectableFlags", "ImGuiComboFlags", "ImGuiTabBarFlags",
    "ImGuiTabItemFlags", "ImGuiTableFlags", "ImGuiTableColumnFlags", "ImGuiTableRowFlags",
    "ImGuiTableBgTarget", "ImGuiFocusedFlags", "ImGuiHoveredFlags", "ImGuiDragDropFlags",
    "ImGuiDir", "ImGuiSortDirection", "ImGuiKey", "ImGuiMod", "ImGuiConfigFlags",
    "ImGuiBackendFlags", "ImGuiCol", "ImGuiStyleVar", "ImGuiButtonFlags",
    "ImGuiColorEditFlags", "ImGuiSliderFlags", "ImGuiMouseButton", "ImGuiMouseCursor",
    "ImGuiCond", "ImGuiViewportFlags", "ImDrawFlags",
}

-- Categories we deliberately don't gate on — they're style, not correctness, and
-- the codebase intentionally has unused ctx/refs/self parameters in render funcs.
ignore = {
    "212",  -- unused argument
    "213",  -- unused loop variable
    "542",  -- empty if branch (used a few places as explicit "do nothing" markers)
}

-- Only gate the shipped CoOpt UI Lua. The CI workflow already scopes to these dirs;
-- this is a safety net for anyone running `luacheck .` at the repo root.
include_files = {
    "lua/itemui",
    "lua/coopui",
    ".luacheckrc",
}
