# CoOpt UI Architecture

> This document describes the current CoOpt UI runtime architecture in `lua/itemui`. The target branded layout is `lua/coopui/` (see Target directory layout below).

## Target directory layout (CoOpt UI branding)

The canonical install layout uses **`lua/coopui/`** as the unified root for CoOpt UI:

- `lua/coopui/init.lua`: bootstrap entrypoint (`/lua run coopui`).
- `lua/coopui/app.lua` (or `wiring.lua`): application kernel.
- `lua/coopui/context.lua`, `lua/coopui/context_init.lua`: shared dependency context.
- `lua/coopui/core/`: registry, events, cache, diagnostics.
- `lua/coopui/services/`, `lua/coopui/views/`, `lua/coopui/components/`, `lua/coopui/utils/`: runtime and UI.
- `lua/coopui/default_layout/`: bundled layout assets.
- `lua/coopui/docs/archive/`: historical notes (non-canonical).

Require paths in the target layout use `require('coopui.*')`. The patcher migrates existing installs from `lua/itemui/` to `lua/coopui/` and rewrites path-bearing INI values so user data is preserved. Current repo may still use `lua/itemui/` and `require('itemui.*')` until a full tree rename; the patcher ensures the installed layout and INI paths match the target.

## Module Map

```text
init.lua
  -> require('itemui.app')
app.lua
  -> initializes core infra (registry/events/cache/diagnostics)
  -> initializes services (scan, sell_status, item_ops, augment_ops, macro_bridge, main_loop, sell_batch)
  -> initializes context via context_init.init(refs)
  -> binds commands (/itemui, /inv, /inventoryui, /bankui, /dosell, /doloot)
  -> starts root render: MainWindow.render(context.build())
context_init.lua
  -> thin bootstrap for context.init(refs)
context.lua
  -> context.build() returns a metatable-backed dependency view
core/registry.lua
  -> module registration + enable/draw/tick lists + window lifecycle + newest-open lookup
views/*
  -> ImGui render modules for hub/companion windows
services/*
  -> runtime business logic, scanners, state machines, macro IPC
utils/*
  -> helper modules (layout, sort, columns, tooltips, item helpers, file safety)
```

## Data Flow

1. MQ TLO reads are pulled by scan/item helper functions (`getItemTLO`, inventory/bank scans).
2. `buildItemFromMQ` normalizes rows and uses lazy stat metatables in `item_helpers`.
3. Scans populate `inventoryItems`, `bankItems`/`bankCache`, and `sellItems`.
4. `sell_status.computeAndAttachSellStatus(...)` annotates rows (`willSell`, `sellReason`, protection flags).
5. View pipelines filter/sort through `filter_service`, `sort`, and `table_cache`.
6. Views render final lists/tables through context-backed dependencies.

**Optional C++ plugin (MQ2CoopUIHelper):** When the plugin is loaded, `scan.lua` uses `require("plugin.CoopUIHelper")` and calls `scanInventory()` / `scanBank()` from the plugin instead of the Lua/TLO path. Same data shape and post-scan logic; plugin source lives in `plugin/mq2coopuihelper/`. See `docs/CPP_PLUGIN_INVESTIGATION.md` and `plugin/mq2coopuihelper/README.md`.

## State Ownership

| Owner | State Responsibility |
|---|---|
| `core/registry.lua` | Companion registration, open/close/shouldDraw lifecycle, opened-at tracking |
| `services/item_ops.lua` | Cursor/move/destroy/quantity operation state |
| `services/augment_ops.lua` | Augment insert/remove state and queue advancement |
| `services/reroll_service.lua` | Reroll list and reroll flow state |
| `views/item_display.lua` | Item display tabs, active tab, recents, locate request state |
| `views/loot_ui.lua` | Loot run UI state (progress lists, mythical prompt, history) |
| `views/*` local module state | Per-view UI controls (sort/filter/search toggles) |
| `state.lua` | Shared runtime tables (`uiState`, scan/perf/layout state, core data lists) |

## Config Architecture

`config.lua` is the single path and INI I/O gateway.

- Sell config path root: `Macros/sell_config/*`
- Shared config path root: `Macros/shared_config/*`
- Loot config path root: `Macros/loot_config/*`
- Character storage path root: `Macros/sell_config/Chars/<CharName>/*`

Primary writers:
- `config_cache.lua` and settings/actions views write sell/loot/shared INI keys and lists.
- `storage.lua` writes per-character `inventory.lua`, `bank.lua`, and `sell_cache.ini`.
- Layout utilities write window/column/sort layout config.
- Macro bridge flows write/read progress/session INI files for IPC.

Primary readers:
- `app.lua`, services, and views read through `config_cache` and `config` accessors.
- `main_loop.lua` + `macro_bridge.lua` poll loot/sell progress and session INIs.

## Macro Bridge

`services/macro_bridge.lua` is the Lua IPC adapter for `sell.mac` and `loot.mac`.

- Versioned protocol via `[Protocol] Version` keys in IPC INI files.
- Throttled polling (`pollInterval`) instead of per-frame file reads.
- Reads/writes:
  - `sell_progress.ini`, `sell_failed.ini`
  - `loot_progress.ini`, `loot_session.ini`
- Emits runtime events (`sell:started/progress/complete`, `loot:started/complete`) to decouple UI logic from macro timing.

## Directory-to-Purpose Map

Current runtime (and repo) layout under `lua/itemui/`; target branded layout is `lua/coopui/` (same structure).

- `lua/itemui/init.lua` (target: `lua/coopui/init.lua`): bootstrap entrypoint.
- `lua/itemui/app.lua` or `wiring.lua` (target: `lua/coopui/`): application kernel/orchestration.
- `lua/itemui/context.lua`, `context_init.lua`: shared dependency context.
- `lua/itemui/core/`: registry/events/cache/diagnostics infrastructure.
- `lua/itemui/services/`: non-UI runtime logic.
- `lua/itemui/views/`: ImGui windows/tabs.
- `lua/itemui/components/`: reusable UI components.
- `lua/itemui/utils/`: helper and utility modules.
- `lua/itemui/default_layout/`: bundled layout assets.
- `lua/itemui/docs/archive/`: historical notes (non-canonical).

## Naming Conventions

- **Services**: `services/*.lua` - runtime/business logic modules.
- **Views**: `views/*.lua` - ImGui rendering modules.
- **Utils**: `utils/*.lua` - shared helper utilities.
- **Components**: `components/*.lua` - reusable UI building blocks.
- **Core**: `core/*.lua` - foundational runtime infrastructure.
