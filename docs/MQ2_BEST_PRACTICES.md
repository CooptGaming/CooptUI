# MacroQuest2 UI Best Practices

Guidelines for this project's EverQuest UI overhaul using MQ2 Lua and ImGui.

## Lua Best Practices (from docs.macroquest.org)

- **Use `local`** – Declare variables as `local` to avoid globals
- **200-local limit** – Lua has a hard limit of 200 local variables per scope. Consolidate related state into tables (e.g. `uiState`, `configCache`, `filterState`) rather than adding many top-level locals. See `lua/itemui/docs/MODULE_SPLIT_ANALYSIS.md` for module-split options if the limit is approached.
- **Require modules** – Use `require('module')` for shared code
- **nil checks** – Use `if variable then` pattern for nil checks
- **TLO access** – Prefer `mq.TLO.Something()` over macro-style parsing

## Project Structure

### Config Location
- **Macros/sell_config/** – User-editable sell/keep/junk lists, layout
- **Macros/shared_config/** – Shared valuable items (loot + sell)
- **Macros/loot_config/** – Loot filters

MQ2 convention: user configs live under `Macros/` so they persist across updates.

### Lua Module Layout
```
lua/
├── itemui/       # Main unified UI (require('itemui'))
├── mq/           # Shared MQ utilities (require('mq.ItemUtils'))
├── sellui/       # Standalone sell UI
└── bankui/       # Standalone bank UI
```

## Performance

### Avoid INI Reads Per Item
- Load config once (e.g. `loadConfigLists()`), cache in memory
- `willItemBeSold()` should use cached flags/lists, not read INI per call

### Main Loop Timing
- **33ms** when UI visible (~30 FPS) – snappy interaction
- **100ms** when UI hidden – reduce CPU when not in use

### Debounce File Writes
- Layout/config saves: debounce 600ms for rapid changes
- Immediate save on explicit user action (e.g. "Save" button)

### Sort Caching
- Cache sorted list; re-sort only when key, direction, filter, or data changes
- Avoid `table.sort()` every frame when idle

## ImGui Usage

- **PushID/PopID** – Use in loops to avoid ID conflicts
- **ImGuiListClipper** – Virtualize large lists when possible
- **SetNextWindowPos** – Position relative to EQ windows for better UX

## Command Bindings

- Bind `/itemui`, `/inv` for ItemUI
- Bind `/sellui`, `/sell` for SellUI
- Bind `/bankui` for BankUI
- Unbind on script exit

## User Setup

1. Extract to MQ2 root
2. Merge `lua/` and `Macros/` with existing
3. Run `/lua run itemui` (or sellui/bankui)
4. Config files created on first use in `Macros/sell_config/`
