# ItemUI Module Split Analysis

Analysis of splitting `itemui/init.lua` (~4500 lines) into multiple modules. Use this to decide whether and how to proceed.

---

## Current State

- **init.lua**: Single file, ~4500 lines, ~105 local functions, ~150+ top-level locals (after consolidation)
- **Supporting modules**: `config.lua`, `rules.lua`, `storage.lua` (already extracted)
- **Lua 200-local limit**: Consolidation (C, uiState, configCache, filterState, sortState, perfCache) has reduced risk; splitting would eliminate it per-module

---

## Benefits of Splitting

| Benefit | Description |
|---------|-------------|
| **Eliminates 200-local limit** | Each module has its own scope; no single file approaches the limit |
| **Faster navigation** | Smaller files; easier to find specific logic |
| **Clearer ownership** | Each module has a focused responsibility |
| **Easier testing** | Smaller modules can be unit-tested in isolation |
| **Parallel work** | Different developers can work on different modules with fewer merge conflicts |
| **Lazy loading** | Optional features (e.g. bank, filters) could be loaded on demand |
| **Reusability** | Render modules could be reused by other UIs (e.g. bankui) |

---

## Negatives / Drawbacks

| Drawback | Description |
|----------|-------------|
| **Refactor effort** | Large one-time change; high risk of introducing bugs |
| **Cross-module state** | Shared state (inventoryItems, sellItems, uiState) must be passed or centralized |
| **Circular dependencies** | Risk of A→B→C→A if modules are not designed carefully |
| **More files** | 1 file → 6–8 files; harder to see full picture at a glance |
| **Module boundaries** | Decisions about what goes where can be subjective |
| **Debugging** | Stack traces span multiple files; need to jump between modules |

---

## Concerns

### 1. **Shared State**

ItemUI has many shared variables: `inventoryItems`, `bankItems`, `sellItems`, `uiState`, `perfCache`, `filterState`, `sortState`, `layoutConfig`, `columnVisibility`, etc.

**Options:**
- **Central state module**: `itemui/state.lua` holds all shared state; other modules require it
- **Pass as parameters**: Render functions receive state as arguments (verbose, many params)
- **Hybrid**: State module for core data; pass view-specific state to render functions

### 2. **Circular Dependencies**

Example: `render_inventory` needs `scanSellItems`; `scanSellItems` needs `rules`; `rules` needs nothing from render. But `render_inventory` might call `addToKeepList` which writes INI and invalidates cache—so it needs `config` and `perfCache`.

**Mitigation:** Dependency flow should be one-way:
```
config, rules, storage (no deps on init)
    ↓
state (holds shared refs)
    ↓
render_* (require state, config, rules)
    ↓
init (orchestrates, requires all)
```

### 3. **ImGui Call Order**

ImGui is immediate-mode; calls must happen in a fixed order each frame. Splitting render logic across modules means the main loop must call them in the correct sequence. Easy to break if order changes.

### 4. **MQ2 Lua Require Behavior**

MQ2’s Lua may cache `require()` results. Ensure modules don’t rely on reload semantics unless that’s explicitly supported.

---

## Proposed Module Structure

```
itemui/
├── init.lua           # Entry point, main loop, command handling (~400 lines)
├── config.lua         # (existing) INI read/write, paths
├── rules.lua          # (existing) Sell/loot rule evaluation
├── storage.lua        # (existing) Layout persistence
├── state.lua          # NEW: Shared state (inventoryItems, sellItems, uiState, etc.)
├── render_inventory.lua  # NEW: renderInventoryContent, sell view, gameplay view (~600 lines)
├── render_bank.lua    # NEW: renderBankWindow (~300 lines)
├── render_filters.lua    # NEW: renderFiltersSection, filter conflict modal (~400 lines)
├── render_config.lua  # NEW: renderConfigWindow, flags, values, lists (~500 lines)
└── utils.lua          # NEW: buildItemFromMQ, getSpellName, sort helpers, etc. (~400 lines)
```

**Rough line counts:** init 400, state 80, render_inventory 600, render_bank 300, render_filters 400, render_config 500, utils 400 = ~2680 in modules + ~1800 in init (main loop, setup, scanning, etc.). Some logic would stay in init.

---

## Migration Strategy

### Phase 1: Extract State (Low Risk)
- Create `state.lua` with all shared tables
- `init.lua` requires state and uses `state.inventoryItems` etc.
- No behavior change; just indirection

### Phase 2: Extract Utils (Low Risk)
- Move `buildItemFromMQ`, `getSpellName`, `getSpellDescription`, sort helpers, `getCellDisplayText`, etc. to `utils.lua`
- These are pure or mostly pure functions; minimal shared state

### Phase 3: Extract Render Modules (Medium Risk)
- Extract one render function at a time (e.g. `renderBankWindow` first—smallest)
- Pass required state as parameters or via `state` module
- Test after each extraction

### Phase 4: Extract Scanning / Business Logic (Medium Risk)
- Move `scanInventory`, `scanSellItems`, `scanBank`, add/remove list functions to a `scan.lua` or keep in init
- These touch many shared variables; may be easier to keep in init initially

---

## Recommendation

1. **Short term:** Rely on consolidation (C, uiState, configCache) to stay under the 200-local limit. Monitor as features are added.
2. **If limit is hit again:** Extract `state.lua` and `utils.lua` first (Phases 1–2). These are low-risk and reduce locals in init.
3. **If further reduction needed:** Extract render modules (Phase 3), starting with `render_bank.lua` as a pilot.
4. **Avoid:** Big-bang split of the entire file in one change.

---

## Effort Estimate

| Phase | Effort | Risk |
|-------|--------|------|
| Phase 1 (state) | 2–4 hours | Low |
| Phase 2 (utils) | 4–6 hours | Low |
| Phase 3 (render modules) | 8–16 hours | Medium |
| Phase 4 (scan/logic) | 4–8 hours | Medium |
| **Total** | **18–34 hours** | |

---

## Alternatives to Full Split

1. **Do-nothing:** Rely on consolidation; revisit only if the limit is hit again.
2. **Extract state only:** Single new module; biggest local-count reduction for least effort.
3. **Extract by feature flag:** Move bank UI to `render_bank.lua`; load only when bank is used (if MQ2 supports conditional require).
