# ItemUI: Upvalue Limit Fix & Module Refactor

**Purpose:** Reference for maintainers and AI agents. Documents the Lua 60-upvalue and 200-local limits, the refactor that addressed them, and how to extend ItemUI without regressing.

**When to use this doc:** You see "too many upvalues" or "60 upvalue" errors; you need to add new context keys for views; or you are splitting more logic out of `init.lua`.

---

## 1. The Problem: Lua Limits

- **60 upvalues per function**  
  A Lua function can close over at most 60 outer-scope variables. If `buildViewContext()` (or any closure) captures more than 60 names from its enclosing scope, Lua errors at load or runtime.

- **200 locals per scope**  
  A single block (e.g. the whole of `init.lua`) can have at most 200 local names. Too many top-level locals in one file triggers the same kind of limit error.

ItemUI’s view context was built by one big function that assigned 50+ keys from init’s locals, so it was at constant risk of hitting 60 upvalues as features grew.

---

## 2. Solution Overview

Two main strategies were applied:

1. **Single refs table (registry)**  
   Instead of a function that closes over 50+ separate locals, we use **one table** that holds every context key. The function that builds the context for views closes over **only that table** (1 upvalue). New keys are added to the table, not as new upvalues.

2. **Module splits**  
   Large blocks of logic were moved out of `init.lua` into dedicated modules. Each module has its own scope, so its locals and upvalues don’t count toward init’s limits. Init only keeps a small set of requires and wrapper calls.

---

## 3. Module Map (Refactor-Related)

| File | Role | Used by init.lua as |
|------|------|---------------------|
| **itemui/context.lua** | Holds the single refs table; provides `build()` and `extend()`. All view context keys live in this refs table. | `context.init(refs)`, `context.build()`, `context.extend(ctx)` |
| **itemui/config_cache.lua** | Cached sell/loot config from INI; keep/junk/loot list add/remove; augment list API. | `config_cache.init(opts)`, `config_cache.getCache()`, `config_cache.loadConfigCache()`, list APIs, `createAugmentListAPI()` |
| **itemui/services/scan.lua** | All scan logic: inventory, bank, sell, loot; fingerprint; incremental scan; snapshots; maybeScan*. | `scanService.init(env)`, then wrappers like `scanService.scanInventory()` |
| **itemui/utils/column_config.lua** | Column definitions (`availableColumns`), visibility state, autofit widths, `initColumnVisibility()`. | `columnConfig.availableColumns`, `columnConfig.columnVisibility`, `columnConfig.columnAutofitWidths`, `columnConfig.initColumnVisibility()` |
| **itemui/upvalue_check.lua** | CI-style check: ensures `context.build()` has fewer than 60 upvalues. | Run manually or in CI: `/lua run itemui.upvalue_check` or `lua itemui/upvalue_check.lua` |

Other existing modules (e.g. `config`, `rules`, `storage`, `views/*`, `utils/layout`, `utils/columns`, `utils/sort`, `utils/theme`) are unchanged in purpose; init now delegates more to the new modules above.

---

## 4. How the Context (View Registry) Works

- **Where refs are built:** `init.lua` builds one table passed to `context.init(refs)`. That table contains every key that views need: state tables, data arrays, config refs, and function refs (scan, layout, theme, columns, etc.). Search for `context.init({` in `init.lua` to see the full set.

- **How views get context:**  
  `buildViewContext()` returns a proxy that delegates to that refs table (`setmetatable({}, { __index = refs })`). So views still call `extendContext(buildViewContext())` and receive a table that behaves like the old context (same keys, same refs).

- **Adding a new context key:**  
  1. Add the key to the `context.init({ ... })` table in `init.lua` (e.g. `newThing = myNewThing`).  
  2. Do **not** add new top-level locals in init just to pass them into context; prefer adding them to an existing sub-module or the refs table.  
  This way the number of upvalues for the function that builds the context does not grow (it still closes over only the single refs table in `context.lua`).

- **Where it’s used:**  
  `renderInventoryContent()`, `renderBankWindow()`, `renderAugmentsWindow()`, Config view, and any code that does `local ctx = extendContext(buildViewContext())` and then calls `SomeView.render(ctx, ...)`.

---

## 5. How Each Split Module Is Wired

- **context**  
  - Init: `context.init(refs)` once, after all refs are defined (after scan wrappers, config_cache init, etc.).  
  - Build: `buildViewContext()` = `context.build()`, `extendContext(ctx)` = `context.extend(ctx)`.

- **config_cache**  
  - Init: `config_cache.init({ setStatusMessage, invalidateSellConfigCache, invalidateLootConfigCache, isInKeepList, isInJunkList })` after those functions exist in init.  
  - Then: `configCache = config_cache.getCache()`, and alias locals (e.g. `configSellFlags = configCache.sell.flags`). List APIs and `loadConfigCache` are assigned from `config_cache.*`.  
  - Call `loadConfigCache()` once at startup so the cache is populated.

- **scan**  
  - Init: `scanService.init(scanEnv)` where `scanEnv` contains refs to inventoryItems, bankItems, perfCache, scanState, and callbacks (buildItemFromMQ, invalidateSortCache, computeAndAttachSellStatus, isBankWindowOpen, storage, events, rules, sell helpers, etc.).  
  - Init defines thin wrappers (e.g. `local function scanInventory() scanService.scanInventory() end`) so the rest of init and the context refs table can keep using the same names.

- **column_config**  
  - No init from init.lua; the module creates its own tables and runs `initColumnVisibility()` on load.  
  - Init does: `availableColumns = columnConfig.availableColumns`, `columnVisibility = columnConfig.columnVisibility`, `columnAutofitWidths = columnConfig.columnAutofitWidths`, and `initColumnVisibility = function() columnConfig.initColumnVisibility() end`.  
  - Layout and columns utils still receive these same refs.

---

## 6. Adding New Features Without Breaking Limits

- **New view context key:**  
  Add it to the single `context.init({ ... })` table in `init.lua`. Do not add a new closure in init that captures many locals just to build context.

- **New scan-related logic:**  
  Prefer adding it in `itemui/services/scan.lua` and exposing it via the same `env` or a new method on the scan API; init can then add a one-line wrapper and put that wrapper in the context refs table if views need it.

- **New config or list API:**  
  Prefer adding it in `itemui/config_cache.lua` and exposing it via `config_cache`; init assigns to a local or to the context refs table as needed.

- **New column or column state:**  
  Prefer adding it in `itemui/utils/column_config.lua` and exposing it; init keeps a single ref (e.g. to the module or to a sub-table) and passes that into context if needed.

- **If you must add many new locals in init:**  
  Consider moving that block into a new module that returns one table or a few tables; init then requires it and passes the returned value(s) into the context refs table. That keeps init under the 200-local limit and keeps the context builder under the 60-upvalue limit.

---

## 7. Verifying Upvalue Count (CI / Manual)

- **In-game (recommended):**  
  Run `/lua run itemui.upvalue_check`. It loads `itemui.context`, inits with a minimal refs table, and calls `context.checkUpvalueLimits()`. It prints OK or FAILED and, if the environment supports it, exits with 0 or 1.

- **At load time:**  
  In `init.lua`, the `C` table has `UPVALUE_DEBUG`. Set `UPVALUE_DEBUG = true` to log upvalue counts for `context.build()` and `context.extend()` when ItemUI loads.

- **Programmatic:**  
  `context.getUpvalueCount(fn)` returns the upvalue count for a function (requires `debug`). `context.checkUpvalueLimits()` returns `ok, message`; `ok` is false if `build()` has ≥ 60 upvalues.

- **Phase 7 check script:**  
  `itemui/phase7_check.ps1` includes a step that checks for the presence of `context.lua` and that init uses `require('itemui.context')`.

---

## 8. If the 60-Upvalue Error Comes Back

1. **Confirm the single-refs design is still in use.**  
   In `init.lua`, search for `context.init({`. The view context should be built from that one table only. There should not be a separate large function that assigns 50+ keys to a context table from 50+ distinct locals.

2. **Check that new context keys were added to the refs table.**  
  New keys must be added inside the `context.init({ ... })` table. Adding them via a different code path (e.g. a new closure that closes over many locals) can create a new function that exceeds 60 upvalues.

3. **Check other closures in init.**  
  Any `local function` in init that captures many outer locals can hit the limit. If you added a new such function, consider moving it into a module or reducing what it closes over (e.g. pass a single table of dependencies).

4. **Run the upvalue check.**  
  Use `itemui.upvalue_check.lua` or `UPVALUE_DEBUG` to see which function has a high count and fix that function (or move it into a module).

---

## 9. Key File Locations (Quick Reference)

- **Context and refs table:** `lua/itemui/init.lua` — search for `context.init({` and `buildViewContext`.
- **Context module (build/extend/check):** `lua/itemui/context.lua`.
- **Config cache (loadConfigCache, list APIs):** `lua/itemui/config_cache.lua`.
- **Scan service (scanInventory, scanBank, etc.):** `lua/itemui/services/scan.lua`.
- **Column definitions and state:** `lua/itemui/utils/column_config.lua`.
- **Upvalue check script:** `lua/itemui/upvalue_check.lua`.
- **Phase 7 / structure check:** `lua/itemui/phase7_check.ps1`.

---

## 10. Related Docs

- **MODULE_SPLIT_ANALYSIS.md** — Earlier analysis of splitting init.lua; the refactor implements parts of that and adds the registry/context pattern for the upvalue limit.
- **PHASE7_*.md** — Layout and Phase 7 integration; context and views are part of that story.
