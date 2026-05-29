-- luacheck configuration for CoOpt UI
-- The addon runs inside MacroQuest2's MQ2Lua, which is LuaJIT (Lua 5.1 semantics).
-- Goal of this gate: catch the "loads fine, crashes on a player later" bug classes
-- (undefined globals/locals, use-before-declaration, accidental globals) — the
-- failure mode behind the Reroll / filters / searchbar crashes — without drowning
-- in cosmetic noise. The CI workflow scopes checking to lua/itemui + lua/coopui.

std = "luajit"
max_line_length = false

-- Globals injected by the MQ2Lua host and the ImGui binding (read-only from our
-- code), so listing them avoids false "accessing undefined variable" reports.
read_globals = {
    -- Core handles + ImGui constructors/classes
    "mq", "ImGui", "ImVec2", "ImVec4", "ImColor", "ImGuiListClipper",
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

-- `_` is the conventional throwaway for discarded multi-return values; allow writing it.
globals = { "_" }

-- What stays ENFORCED (not listed here) are the crash-class checks:
--   11x  setting/mutating an undefined (accidental) global
--   113  accessing an undefined variable  -> catches reroll-style "call a nil global"
--   143  accessing an undefined field of a global
--   221  local accessed but never set     -> catches filters/searchbar-style shadows
-- The categories below are code-cleanliness, not crash risks. Downgraded for this
-- first baseline so the gate is green on existing code; tighten later if desired.
ignore = {
    "211",  -- unused local variable / function
    "212",  -- unused argument
    "213",  -- unused loop variable
    "231",  -- variable assigned but never accessed
    "311",  -- value assigned is unused / overwritten before use
    "411",  -- redefining a local
    "421",  -- shadowing a local
    "431",  -- shadowing an upvalue
    "512",  -- loop can be executed at most once (idiomatic "is table non-empty?" check)
    "542",  -- empty if branch
    "611", "612", "613", "614",  -- trailing / whitespace-only lines
}

-- Don't lint the markdown/docs tree (luacheck would try to parse .md as Lua).
exclude_files = {
    "lua/itemui/docs",
}
