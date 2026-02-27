# CoOpt UI Developer Documentation

Start with [docs/COOPUI_OVERVIEW.md](COOPUI_OVERVIEW.md) for product scope and where to look. Historical phase and design docs are in `lua/itemui/docs/archive/`.

## Architecture Overview

### Entry Points

- **ItemUI**: `lua/itemui/init.lua` — loaded via `/lua run itemui`
- **ScriptTracker**: `lua/scripttracker/init.lua` — loaded via `/lua run scripttracker`
- **Auto Sell**: `Macros/sell.mac` — triggered via `/dosell` or `/macro sell`
- **Auto Loot**: `Macros/loot.mac` — triggered via `/doloot` or `/macro loot`

### Main Loop

`init.lua` sets up the MQ2 main loop:
1. Registers `/itemui`, `/inv`, `/inventoryui` bind commands
2. Initializes all modules via `init(deps)` pattern
3. Runs `mq.imgui.init('ItemUI', renderUI)` for the ImGui render callback
4. Main loop: checks for inventory fingerprint changes, flushes debounced saves, handles macro bridge status

### Module Map (36 Lua files)

#### ItemUI Core (`lua/itemui/`)

| File | Purpose |
|------|---------|
| `init.lua` | Entry point, main loop, command handler, module initialization |
| `config.lua` | INI read/write, list parsing, path helpers, chunked list I/O |
| `config_cache.lua` | Cached sell/loot config from INI, list add/remove APIs |
| `context.lua` | Context registry pattern (60-upvalue solution) |
| `rules.lua` | Sell and loot rule evaluation, epic item handling |
| `storage.lua` | Per-character persistence (bank snapshots, char folders) |

#### Core (`lua/itemui/core/`)

| File | Purpose |
|------|---------|
| `cache.lua` | Multi-tier caching with granular invalidation |
| `events.lua` | Event bus for decoupled module communication |
| `state.lua` | Unified state management |

#### Views (`lua/itemui/views/`)

| File | Purpose |
|------|---------|
| `inventory.lua` | Inventory table (gameplay view) |
| `sell.lua` | Sell view (merchant open) with keep/junk buttons |
| `bank.lua` | Bank slide-out panel (live + historic) |
| `loot.lua` | Live corpse loot evaluation |
| `config.lua` | Config window (3 tabs: General & Sell, Loot Rules, Item Lists) |
| `augments.lua` | Augmentation item display |

#### Services (`lua/itemui/services/`)

| File | Purpose |
|------|---------|
| `scan.lua` | Inventory scanning with fingerprinting and incremental updates |
| `filter_service.lua` | Unified filter system for item list management |
| `macro_bridge.lua` | `/dosell` and `/doloot` macro integration |
| `sell_status.lua` | Sell status computation and caching |
| `item_ops.lua` | Item operations (move, sell, bank transfer) |

#### Utils (`lua/itemui/utils/`)

| File | Purpose |
|------|---------|
| `layout.lua` | Window size, column visibility, sort persistence (INI-backed) |
| `theme.lua` | Color palette, button styling, text coloring |
| `columns.lua` | Column visibility, display text, autofit behavior |
| `column_config.lua` | Column configuration definitions |
| `sort.lua` | Sort value helpers and comparator builder |
| `icons.lua` | Icon constants and helpers |
| `item_helpers.lua` | Item data extraction and formatting |
| `item_tooltip.lua` | Rich item detail tooltip rendering |
| `window_state.lua` | Window open/close state management |
| `file_safe.lua` | Safe file I/O utilities |

#### Components (`lua/itemui/components/`)

| File | Purpose |
|------|---------|
| `searchbar.lua` | Search input component |
| `filters.lua` | Filter UI components |
| `progressbar.lua` | Progress bar variants (timed, indeterminate) |
| `character_stats.lua` | Character stat display (weight, slots, etc.) |

#### ScriptTracker (`lua/scripttracker/`)

| File | Purpose |
|------|---------|
| `init.lua` | ScriptTracker entry point, AA script progress tracking |

#### CoOpt UI Shared Core (`lua/coopui/`)

| File | Purpose |
|------|---------|
| `version.lua` | Single source of truth for all component versions |
| `core/events.lua` | Shared event bus |
| `core/cache.lua` | Shared caching infrastructure |
| `core/state.lua` | Shared state management |
| `utils/theme.lua` | Shared theme/color definitions |

#### Shared Utilities

| File | Purpose |
|------|---------|
| `lua/mq/ItemUtils.lua` | `formatValue()`, `formatWeight()` used across components |

#### Dev/Test Files (not shipped in releases)

| File | Purpose |
|------|---------|
| `upvalue_check.lua` | Upvalue count checker for build validation |

---

## Key Patterns

### Context Registry (60-Upvalue Solution)

Lua closures have a hard limit of 60 upvalues. With 30+ modules needing access to shared state, closing over individual variables would exceed this limit.

**Solution** (`context.lua`):
```lua
local refs = {}       -- single table holds ALL shared references
context.init(refs)    -- called once from init.lua

-- build() returns a metatable proxy:
function M.build()
    return setmetatable({}, { __index = refs })
end
```

Views call `context.build()` to get a proxy table. Accessing `ctx.scanInventory` routes through the metatable to `refs.scanInventory`. The closure only captures one upvalue (`refs`), not 60+.

### init(deps) Dependency Injection

Every module follows the same pattern:

```lua
local M = {}
local deps

function M.init(d)
    deps = d  -- store injected dependencies
end

-- Module functions use deps.xxx for external references
function M.doSomething()
    deps.scanInventory()
end

return M
```

`init.lua` calls each module's `init()` with the specific dependencies it needs. This avoids global state and makes dependencies explicit.

### Event Bus

`core/events.lua` provides pub/sub for decoupled communication:

```lua
events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
events.on(events.EVENTS.CONFIG_SELL_CHANGED, function() ... end)
```

Key events: `CONFIG_SELL_CHANGED`, `CONFIG_LOOT_CHANGED`, `INVENTORY_CHANGED`, `BANK_CHANGED`.

### Config System (INI Chunking)

MQ macro variables have a 2048-character limit. `config.lua` handles this transparently:

- **Read**: `readListValue()` reads `key`, `key2`, `key3`, ... and concatenates with `/`
- **Write**: `writeListValue()` splits at `/` boundaries when over 2000 chars
- **Safety limit**: Max 20 chunks per key (prevents infinite loops from corrupt data)

### Scan System (Fingerprinting)

`services/scan.lua` uses per-bag fingerprinting to avoid rescanning unchanged bags:

1. Each bag gets a fingerprint (hash of item IDs + counts)
2. On scan, only bags with changed fingerprints are rescanned
3. Scanning is incremental: 2 bags per frame to avoid blocking the UI thread

### State Tables (200-Local Solution)

Lua has a 200-local limit per scope. Instead of 200 individual `local` variables, state is consolidated into tables:

- `uiState` — window visibility, setup mode, config open, etc.
- `perfCache` — performance metrics and timing
- `sortState` — sort column and direction per view
- `filterState` — active filter criteria

---

## Build & Release

### Build Script

`scripts/build-release.ps1` packages the release zip:

```powershell
.\scripts\build-release.ps1 -Version "0.2.0-alpha"
```

The zip includes:
- `lua/itemui/`, `lua/scripttracker/`, `lua/coopui/`, `lua/mq/ItemUtils.lua`
- `Macros/sell.mac`, `Macros/loot.mac`, `Macros/shared_config/*.mac`
- `config_templates/` (INI templates for first-time install)
- `resources/UIFiles/Default/` (UI files)
- `DEPLOY.md`, `CHANGELOG.md`

Dev files excluded: `lua/itemui/docs/`, `upvalue_check.lua`.

### Release Workflow

`.github/workflows/release.yml` triggers on `v*` tags:

1. Strips `v` prefix from tag name
2. Runs `build-release.ps1` with the version
3. Creates a draft GitHub release with the zip attached

```bash
git tag v0.2.0-alpha && git push origin v0.2.0-alpha
```

### Release checklist (see .cursor/rules/release.mdc)

1. Update `lua/coopui/version.lua` (PACKAGE, ITEMUI).
2. Optionally update `CHANGELOG.md`.
3. Run `.\scripts\build-release.ps1 -Version "X.Y.Z-alpha"` to verify.
4. Commit, push, then `git tag vX.Y.Z-alpha && git push origin vX.Y.Z-alpha`.
5. Publish the draft release on GitHub.

### Versioning

Single source of truth: `lua/coopui/version.lua`

```lua
return {
    PACKAGE = "0.2.0-alpha",
    ITEMUI = "0.2.0-alpha",
    SCRIPTTRACKER = "0.1.0-alpha",
    SELL_MAC = "3.0",
    LOOT_MAC = "4.0",
}
```

---

## Testing

### Upvalue Check

`lua/itemui/upvalue_check.lua` — validates that `context.build()` stays under 60 upvalues. Run to ensure new code doesn't exceed Lua limits.

### Manual Testing

See `lua/itemui/docs/archive/PHASE7_TESTING_GUIDE.md` for a comprehensive functional test suite covering:
- UI load, window display, inventory rendering
- Sort persistence, column width saving
- Bank panel, sell view, config window
- Macro bridge integration

---

## Internal Dev Docs Index

Historical phase and design docs have been moved to `lua/itemui/docs/archive/`. For current scope and roadmap, see [docs/COOPUI_OVERVIEW.md](COOPUI_OVERVIEW.md) and [lua/itemui/docs/PROJECT_ROADMAP.md](lua/itemui/docs/PROJECT_ROADMAP.md).

---

## Contributing

### Branch Workflow

1. Create a feature branch from `master`: `feature/my-feature`
2. Make changes, test in-game
3. Open a PR to `master`

### Guidelines

- **init.lua size**: Keep under 1300 lines. Extract new modules rather than adding to init.lua.
- **New modules**: Follow the `init(deps)` pattern. Register dependencies explicitly.
- **Upvalue limit**: Run `upvalue_check.lua` after changes. If `context.build()` approaches 60 upvalues, consolidate into tables.
- **200-local limit**: Use state tables (`uiState`, etc.) instead of loose local variables.
- **Config changes**: Add new INI keys to both `config_cache.lua` (for ItemUI) and the corresponding macro (for sell.mac/loot.mac).
- **Testing**: Manual smoke test in-game for UI and sell/loot logic. Run `upvalue_check.lua` after changes that touch context.