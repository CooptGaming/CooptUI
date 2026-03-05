# CoOpt UI — Future Opportunities Analysis

**Date:** 2026-03-04 (revised)
**Scope:** Comprehensive opportunity analysis and prioritized roadmap for advancing CoOpt UI from its current post-expansion state to a world-class EverQuest EMU companion UI.
**Baseline:** Plugin expansion Phases A–D complete (full item data population, getItem API, cursor capabilities, window.isWindowOpen). Implementation Plan Phases 1–13 complete (native scanning, rules engine, IPC streaming, event-driven invalidation, TLO enhancements, perf metrics). Master_Plan_v2 Phases A–E complete.

---

## Section 1 — Executive Summary

CoOpt UI has crossed a critical threshold. With the completion of the plugin expansion (Phases A–D), every item scanned by the plugin now carries the full complement of 120+ fields — stats, descriptive properties, spell effect IDs, wornSlots, augType, augRestrictions — populated directly from `ItemDefinition` struct reads at zero TLO cost. Tooltips populate instantly. Stat columns sort correctly. Augment compatibility works from native data. The `getItem` API provides on-demand full item data for any slot (inventory, bank, equipped, corpse). Cursor state is cached per-frame from the plugin. Window visibility for the 4 main windows uses eqlib pointers instead of TLO. The data fidelity gap between the plugin path and the TLO path is closed.

Combined with the earlier implementation plan work (Phases 1–13) — native scanning at sub-millisecond speeds, a C++ rules engine, IPC event streaming for real-time loot/sell feedback, event-driven cache invalidation, and performance metrics — CoOpt UI's plugin layer is now comprehensive. The Lua layer has a clean registry pattern, non-blocking sell state machines, a 14-step onboarding wizard, a backup/restore system, and a macro bridge handling bidirectional IPC communication. This is a genuinely well-engineered product.

**What remains is not infrastructure — it is experience.** The highest-leverage opportunities now cluster into three categories:

1. **Eliminating the last blocking operations and per-frame waste.** Augment insert/remove still uses `mq.delay`, freezing the UI for 1+ second per operation. The quantity picker blocks for 450ms. `saveInventory` serializes 200+ items through 16,000 `string.format` calls at 4-second cost. Filtered/sorted lists are rebuilt every frame in 5+ views. These are the remaining moments where a player feels CoOpt UI stutter.

2. **Adding data surfaces that no other MQ2 tool provides.** Item stat comparison (side-by-side with green/red deltas), augment compatibility preview on hover, unified cross-view search, session history across restarts, and real-time inventory value tracking. Each of these is now trivial to implement because the plugin provides full item data instantly — the hard prerequisite (data population) is done.

3. **Hardening for real-world use.** A global error handler that prevents Lua crashes from killing the UI. Version compatibility detection between macros, Lua, and plugin. Inflight loot session persistence for crash recovery. A comprehensive `/cooptui health` command. These are the difference between a tool that works in testing and one that works reliably in daily use.

If the top opportunities were all realized, CoOpt UI would be a tool where: augment and stack-split operations never freeze the UI; items can be compared side-by-side from any view; a single search finds items across inventory, bank, and sell; the Loot Companion shows live high-value alerts; session history persists across restarts; and any error or misconfiguration is immediately surfaced with a clear fix. A player switching from any other MQ2 companion tool would immediately notice the difference.

---

## Section 2 — Opportunity Catalog

### 2.1 Performance

---

#### PERF-01: Eliminate saveInventory Serialization Bottleneck

**What it is:** Move the `storage.saveInventory` serialization from Lua to the plugin.

**Current state:** `storage.saveInventory` (storage.lua) serializes all items into a Lua file using 4 batched `string.format` calls per item x ~80 fields = ~16,000 `string.format` calls for 211 items. Profiled at 4,111ms. This runs on the game thread and blocks UI rendering during the entire operation.

**Improved state:** The plugin writes the inventory persistence file in C++ — either as a Lua-loadable file (same format, generated with `snprintf` in a pre-allocated buffer) or as a binary/JSON cache that Lua can load. The scan already has all data in C++ memory; serialization is a single pass over contiguous memory. Expected time: <5ms for 400 items.

**Player-visible impact:** Eliminates a 4-second UI freeze that occurs after every inventory scan. The periodic persist in main_loop phase 2 becomes invisible.

**Complexity:** M (file format compatibility with existing Lua `loadfile` consumption, or migration to a new format with backward compatibility)

**Dependencies:** None (full item data is now populated by the plugin)

**Layer:** Plugin + Lua

---

#### PERF-02: Cache Filtered/Sorted Lists Per View

**What it is:** Stop rebuilding filtered and sorted item lists every frame in sell.lua, bank.lua, inventory.lua, augments.lua, and reroll.lua.

**Current state:** Each view builds a `filtered` table every frame by iterating all items, applying text/flag filters, and then sorting. For 200+ items, this means 200+ iterations, string comparisons, and a `table.sort` call per frame per visible view. The data changes only when a scan completes or filter criteria change.

**Improved state:** Each view caches its filtered/sorted list and rebuilds only when (a) the source data version changes (tracked by scanState or CacheManager version counters), (b) the search text changes, or (c) the sort column/direction changes. Between changes, the cached list is used directly.

**Player-visible impact:** Smoother frame rates when large item tables are visible, especially with 300+ bank items. Eliminates per-frame GC pressure from table allocations.

**Complexity:** S (add a version/dirty check before filtering; 5-10 lines per view)

**Dependencies:** None

**Layer:** Lua

---

#### PERF-03: Avoid Redundant computeAndAttachSellStatus Calls

**What it is:** Add a timestamp to skip redundant sell-status computation.

**Current state:** `computeAndAttachSellStatus(inventoryItems)` is called in three places in quick succession: after scan completion, during periodic persist (main_loop phase 2), and on sell macro start. Each call iterates all items and evaluates multiple rule sets — O(N x R). Already identified in Master_Plan_v2.md S6.3.

**Improved state:** A `sellStatusAttachedAt` timestamp is set after each computation. Subsequent calls skip if the timestamp is more recent than the last scan.

**Player-visible impact:** Eliminates redundant work during the scan-persist-sell sequence. Reduces frame time spikes by ~50-200ms depending on item count.

**Complexity:** S (one timestamp check, 5 lines)

**Dependencies:** None

**Layer:** Lua

---

#### PERF-04: Cache Registry Module Lists

**What it is:** Cache `getEnabledModules()`, `getDrawableModules()`, and `getTickableModules()` results in registry.lua.

**Current state:** These functions create new tables with `setmetatable` wrappers on every call, every frame. `getEnabledModules()` is called once per frame during render. `getDrawableModules()` once per frame. That's 2 table allocations + N metatable wrappers per frame. Already identified in Master_Plan_v2.md S6.1.

**Improved state:** Results are cached with a dirty flag. Cache is invalidated only on `register()`, `toggleWindow()`, `setWindowState()`, `closeNewestOpen()`, and `applyEnabledFromLayout()`. Each getter returns cached list if not dirty.

**Player-visible impact:** Eliminates ~20-40 table allocations per frame. Reduces GC pressure over long sessions.

**Complexity:** M (add dirty flag, cache per getter, invalidation in 5 methods)

**Dependencies:** None

**Layer:** Lua

---

#### PERF-05: Replace getSellProgress INI-Every-Frame with IPC-Only

**What it is:** Stop reading `sell_progress.ini` every frame while the sell macro runs.

**Current state:** `macro_bridge.getSellProgress()` reads the INI file every frame when the sell macro is active (no throttle). This is redundant because Phase 9 already sends sell progress via IPC. The IPC drain updates `MacroBridge.state.sell.progress` per-frame.

**Improved state:** When IPC is available (plugin loaded), skip INI reads entirely for sell progress. Use INI reads only as fallback when plugin is absent.

**Player-visible impact:** Eliminates disk I/O on every frame during sell operations. Reduces frame time variance.

**Complexity:** S (add IPC availability check before INI read)

**Dependencies:** None (IPC already implemented in Phase 9)

**Layer:** Lua

---

#### PERF-06: Optimize getCompatibleAugments Per-Frame Recalculation

**What it is:** Cache augment compatibility results in augment_utility.lua.

**Current state:** `getCompatibleAugments` is called every frame when the Augment Utility view is open. It scans inventory and bank items, filters by augment type compatibility, scores each candidate with `augmentRanking.scoreAugment`, and sorts the result. For 300+ items, this is substantial per-frame work.

**Improved state:** Cache the compatible augments list, keyed by (target item ID, slot index, filter checkbox state). Invalidate when inventory version changes or target item changes.

**Player-visible impact:** Smooth Augment Utility rendering with no per-frame recalculation stutter.

**Complexity:** S (cache key + version check)

**Dependencies:** None

**Layer:** Lua

---

#### PERF-07: Wire Plugin Window Checks into Phase 8

**What it is:** Use the plugin's `window.isWindowOpen` (now implemented for all 4 main windows) for Phase 8 window state checks instead of TLO.

**Current state:** main_loop.lua phase 8 makes multiple Window TLO calls per frame: InventoryWindow, BigBankWnd, MerchantWnd, LootWnd, ConfirmationDialogBox, QuantityWnd, and Macro.Name. The plugin now implements `isWindowOpen` for the 4 main windows via eqlib pointers (Phase D complete), but `window_state.lua` only partially uses it.

**Improved state:** `window_state.lua` uses plugin window checks for all 4 main windows when the plugin is loaded. Phase 8 calls `window_state` functions instead of direct TLO.

**Player-visible impact:** Modest frame time reduction from eliminating TLO overhead for the most frequently checked windows.

**Complexity:** S (wire existing plugin API into window_state.lua)

**Dependencies:** None (Phase D complete)

**Layer:** Lua

---

### 2.2 Reliability

---

#### REL-01: Global Error Handler for Main Loop

**What it is:** Wrap the main loop tick in a pcall to prevent Lua errors from terminating CoOpt UI.

**Current state:** If any unhandled Lua error occurs during `mainLoop.tick()`, the entire Lua script terminates. The player loses the UI and must `/lua run itemui` to restart. There is no crash recovery, no error display, and no state preservation.

**Improved state:** `mainLoop.tick()` is wrapped in a pcall in `app.lua`. On error: the error is logged to `diagnostics.recordError()` and the debug log file, a red status message is shown in the main window ("Error occurred — see Advanced > Debug"), and the next tick retries normally. A consecutive error counter prevents infinite error loops (after 10 consecutive errors, pause ticking and show a recovery prompt).

**Player-visible impact:** CoOpt UI survives transient errors (zone transitions, TLO nil returns, augment edge cases) without requiring a manual restart.

**Complexity:** S (pcall wrapper + error counter in app.lua)

**Dependencies:** None

**Layer:** Lua

---

#### REL-02: Inflight Loot Session Persistence

**What it is:** Periodically save in-flight loot session data so it survives crashes.

**Current state:** Phase 9 IPC streaming delivers loot/skip events to Lua per-frame, where they accumulate in `uiState.lootRunLootedItems` and `uiState.skipHistory`. These are in-memory Lua tables — they survive a macro crash but not a full MQ/game crash. The Implementation Plan S9.7 documents this as a needed enhancement but it was not implemented.

**Improved state:** Every 10 seconds during an active loot session, the Lua drain writes current session data to `loot_session_inflight.ini` and `loot_skipped_inflight.ini`. On the next loot session start, CoOpt UI checks for inflight files and offers recovery in the Loot Companion.

**Player-visible impact:** After a crash during a loot run, the player's session data (items looted, items skipped, values) is recovered up to ~10 seconds before the crash.

**Complexity:** M (periodic write loop + startup recovery check + UI prompt)

**Dependencies:** None (IPC drain already populates the data)

**Layer:** Lua

---

#### REL-03: Version Compatibility Detection

**What it is:** Detect and warn when components are out of sync (old macro + new Lua, or vice versa).

**Current state:** `coopui.version` defines `ITEMUI`, `SELL_MAC`, `LOOT_MAC` version strings, and `constants.TIMING.IPC_PROTOCOL_VERSION = 1`. But no code actually checks whether the running macro version matches the expected Lua version. If a player updates Lua but not the macros (or vice versa), IPC protocol mismatches, missing config keys, or changed INI formats could cause silent failures.

**Improved state:** On macro start (detected by macro_bridge), the macro sends its version via IPC: `/cooptui ipc send version "sell.mac|1.2.3"`. The Lua drain compares against `coopui.version.SELL_MAC`. If mismatched, a yellow banner appears in the main window: "sell.mac version 1.2.0 — expected 1.2.3. Update macros for best results." Similarly, the plugin version is checked against `coopui.version.ITEMUI` on load.

**Player-visible impact:** Clear, actionable warning when components are out of sync, instead of silent degradation.

**Complexity:** S (macro sends 1 line on start; Lua checks 1 value)

**Dependencies:** None

**Layer:** Macro + Lua

---

#### REL-04: Epic Items Resolved Inconsistency

**What it is:** Align the plugin's RulesEngine with the Lua/macro epic resolution path.

**Current state:** The RulesEngine loads epic items from `shared_config/epic_classes.ini` + per-class `epic_items_<class>.ini` files. The Lua layer and macros also use `shared_config/epic_items_resolved.ini` (a pre-resolved flat list). The RulesEngine does NOT read `epic_items_resolved.ini`. This means the plugin could make different epic protection decisions than Lua/macros if the per-class files differ from the resolved file.

**Improved state:** RulesEngine checks for `epic_items_resolved.ini` first and uses it if present (same behavior as Lua/macros). Falls back to per-class files if resolved file doesn't exist.

**Player-visible impact:** Consistent epic protection decisions across all code paths. Eliminates the risk of a player's epic item being sold because the plugin used a different source than the macro.

**Complexity:** S (add one file-existence check + read in RulesEngine)

**Dependencies:** None

**Layer:** Plugin

---

#### REL-05: Plugin/Lua Field Sync Safety Net

**What it is:** Add a lightweight `__index` fallback metatable to plugin-path items for forward compatibility.

**Current state:** Plugin items are plain Lua tables with all 120+ fields populated. If a new Lua field is added later (e.g., a new UI column needs a field that doesn't exist in the plugin), access returns `nil` silently. The expansion design memo recommends Option A (keep plugin as authoritative source), which is correct architecturally, but in practice a version mismatch between plugin DLL and Lua code can happen during updates.

**Improved state:** After receiving plugin scan results, `scan.lua` optionally sets a lightweight `__index` metatable that logs a debug-channel warning on first access to a field that returns nil on a plugin item. No TLO fallback — just visibility. This makes field sync issues immediately diagnosable.

**Player-visible impact:** Version mismatch between plugin and Lua produces actionable debug output instead of silent nil values.

**Complexity:** S (metatable + debug logging in scan.lua; off by default, enabled in debug channel)

**Dependencies:** None

**Layer:** Lua

---

### 2.3 Real-Time Responsiveness

---

#### RT-01: Non-Blocking Augment Operations

**What it is:** Convert augment insert/remove from `mq.delay` blocking to state machines.

**Current state:** `augment_ops.lua` uses 7 `mq.delay()` calls (50ms-400ms) that block the entire Lua runtime including ImGui rendering. A full augment insert sequence blocks for 1+ second. Already identified in Master_Plan_v2.md S6.4.

**Improved state:** Augment operations use a state machine (similar to `sell_batch.lua`): `phase_inspect` -> `phase_wait_display_open` -> `phase_click_socket` -> `phase_wait_confirm` -> `phase_done`. Each phase checks its completion condition per tick and advances. No `mq.delay()`. The UI remains responsive throughout.

**Player-visible impact:** Augment insert/remove no longer freezes the game for 1+ second. The player sees each step happening with visual feedback.

**Complexity:** M (state machine with timing-sensitive transitions between inspect, display, socket, confirm)

**Dependencies:** None

**Layer:** Lua

---

#### RT-02: Non-Blocking Quantity Picker

**What it is:** Convert the quantity picker from `mq.delay` blocking to a state machine.

**Current state:** main_loop.lua phase 7 uses `mq.delay(300)` + `mq.delay(150)` = 450ms blocking while the QuantityWnd opens and the slider is set. Already identified in Master_Plan_v2.md S6.5.

**Improved state:** State machine: `phase_wait_qty_wnd` -> `phase_set_slider` -> `phase_click_accept` -> `phase_done`. Timeout of 2000ms with status message on failure.

**Player-visible impact:** Eliminates 450ms UI freeze during every stack split operation.

**Complexity:** S (simple 3-phase state machine)

**Dependencies:** None

**Layer:** Lua

---

#### RT-03: Live High-Value Item Alert

**What it is:** Show an ImGui popup when a looted item exceeds a configurable value threshold.

**Current state:** Items appear in the Loot Companion's Current tab via IPC streaming. High-value items are not called out. The player must watch the table to notice them.

**Improved state:** When `loot_item` IPC event arrives with value above threshold (configurable in settings, default 1000pp), a brief toast/popup appears: "[Item Name] — 2,500pp" with the item's icon. Auto-dismisses after 5 seconds. Threshold of 0 disables the feature.

**Player-visible impact:** Important loot is never missed, even when the player is focused on gameplay.

**Complexity:** S (one condition check in drainIPCFast + ImGui toast in main_window)

**Dependencies:** None (IPC drain already parses item values)

**Layer:** Lua

---

#### RT-04: Event-Driven Equipment Refresh

**What it is:** Refresh equipment cache on inventory change instead of timer-based throttle.

**Current state:** Equipment cache refreshes on a throttle timer (`EQUIPMENT_REFRESH_THROTTLE_MS`). After an item swap, there is a visible delay before the equipment view updates.

**Improved state:** When `InventoryScanner::HasChanged()` returns true (detected in Phase 8's deferred scan check), the equipment cache is also invalidated. The refresh happens on the next frame where the equipment view is visible.

**Player-visible impact:** Equipment view updates immediately after equip/swap instead of after a timer delay.

**Complexity:** S (add invalidation trigger to existing scan change detection)

**Dependencies:** None

**Layer:** Lua

---

### 2.4 Player Experience & UI Quality

---

#### UX-01: Item Stat Comparison

**What it is:** Side-by-side stat comparison between two items (e.g., equipped vs. bag item).

**Current state:** To compare items, the player must open Item Display for each and visually scan tooltips. No diff or delta display exists. This is the single most-requested feature in MQ2 companion tools.

**Improved state:** Right-click an item in any table and select "Compare with equipped" to open a comparison view showing both items side-by-side with stat deltas (green for improvement, red for downgrade). With the plugin now providing full item data, comparisons are instant — no TLO calls needed.

**Player-visible impact:** Gear upgrade decisions become trivially easy. This alone differentiates CoOpt UI from every other MQ2 tool.

**Complexity:** L (new view, delta computation, rendering, integration with context menu)

**Dependencies:** None (full stat data now available from plugin scans)

**Layer:** Lua

---

#### UX-02: Unified Cross-View Search

**What it is:** A single search that queries inventory, bank, and sell items simultaneously.

**Current state:** Each view (Inventory, Bank, Sell) has its own search bar. To find an item across all locations, the player must search each view separately.

**Improved state:** A global search field in the main window toolbar. Results appear in a unified list with a "Location" column (Inv Bag 3 Slot 5 / Bank Bag 12 Slot 3 / etc.). Clicking a result navigates to the item in the appropriate view. Search covers name, type, and effects.

**Player-visible impact:** "Where is my Cloak of Flames?" answered in one search instead of three.

**Complexity:** M (new search component, cross-list iteration, navigation hooks)

**Dependencies:** None

**Layer:** Lua

---

#### UX-03: Remove Dead Loot View Code

**What it is:** Remove the disabled `loot.lua` view and the `if false then LootView.render(ctx)` guard in main_window.lua.

**Current state:** `views/loot.lua` (175 lines) is a corpse loot view that is disabled by `if false then` in main_window.lua:96. The Loot Companion (`loot_ui.lua`) has replaced it entirely. The dead code confuses developers and inflates the codebase.

**Improved state:** Delete `views/loot.lua`. Remove the dead code path in main_window.lua. Remove the LootView require in wiring/context.

**Player-visible impact:** None directly — this is a code hygiene fix that reduces confusion.

**Complexity:** S (delete file + remove 3-4 lines)

**Dependencies:** None

**Layer:** Lua

---

#### UX-04: Augment Compatibility Preview on Hover

**What it is:** When hovering over an augment in the Augments view, show which equipped items it can fit.

**Current state:** To check augment compatibility, the player must open the Augment Utility, select a target item, select a slot, and then see the compatible augments list. This is a multi-step process.

**Improved state:** Hovering over an augment in the Augments table shows a tooltip section: "Fits: Earring of Station (slot 3), Ring of the Ancients (slot 1)." Computed from `augType` and `wornSlots` bitmask matching against equipment cache.

**Player-visible impact:** Instant visibility into augment compatibility without opening the Augment Utility.

**Complexity:** M (equipment cache iteration + bitmask matching + tooltip extension)

**Dependencies:** None (augType and wornSlots now populated by plugin)

**Layer:** Lua

---

#### UX-05: Session History Across Restarts

**What it is:** Persist loot/sell session summaries to a history file for review across play sessions.

**Current state:** Loot history and skip history are in-memory only. When CoOpt UI restarts (MQ reload, game restart), all history is lost. The player has no way to review what they looted or sold in a previous session.

**Improved state:** On loot/sell session completion, a summary (timestamp, item count, total value, best item, duration) is appended to `session_history.lua`. A new "History" tab in the Loot Companion shows past sessions with expandable details.

**Player-visible impact:** Players can track their loot efficiency over time. "How much did I make last night?" is answerable.

**Complexity:** M (file append + new UI tab + history loading)

**Dependencies:** None

**Layer:** Lua

---

#### UX-06: Shared Utility Functions (simpleHash, etc.)

**What it is:** Extract duplicated utility functions to shared modules.

**Current state:** `simpleHash` is duplicated identically in `inventory.lua` and `bank.lua`. Other patterns (filtered list construction, column configuration) are near-duplicates.

**Improved state:** Shared functions extracted to `utils/` module. Both views import from the shared location.

**Player-visible impact:** None directly — code quality improvement that reduces maintenance burden.

**Complexity:** S (extract + replace in 2 files)

**Dependencies:** None

**Layer:** Lua

---

### 2.5 Data Richness

---

#### DATA-01: Real-Time Inventory Value Tracking

**What it is:** Maintain a running total sell value of current inventory, updated as items are looted or sold.

**Current state:** `invTotalValue` is computed from `inventoryItems` when the cache is nil (inventory.lua:54-58). It shows the total value but does not distinguish between keep/sell items and does not update between scans.

**Improved state:** The plugin maintains `totalInventoryValue`, `totalSellableValue`, and `totalKeepValue` as running counters, updated on every scan. These are exposed via TLO (`${CoOptUI.Inventory.TotalValue}`) and Lua API. The UI shows "Sellable: 12,450pp | Keeping: 34,200pp" in the inventory footer.

**Player-visible impact:** Instant visibility into inventory composition without mental math. "Should I go sell?" is answered at a glance.

**Complexity:** S (sum during scan; expose via existing TLO/Lua)

**Dependencies:** None (all item values now populated by plugin)

**Layer:** Plugin + Lua

---

#### DATA-02: Augment Socket Detail in Scan Results

**What it is:** Include per-socket augment type and contents in scan results for non-augmentation items.

**Current state:** Scan results include `augSlots` (count) but not per-socket details (what type each socket accepts, what augment is currently in each socket). This data is available from `ItemDefinition` and is needed for accurate augment utility operation without additional TLO calls.

**Improved state:** Each item in scan results includes an `augSockets` sub-table: `{ {type=1, augId=12345, augName="..."}, {type=5, augId=0, augName=""}, ... }`. The Augment Utility can show currently-socketed augments without TLO calls.

**Player-visible impact:** Augment Utility shows current socket contents immediately. "What's already in this slot?" is visible without inspecting.

**Complexity:** M (iterate `AugSlot(1..6)` during scan; add sub-table to ItemDataToTable)

**Dependencies:** None (ItemDefinition access already in place via PopulateItemData)

**Layer:** Plugin

---

#### DATA-03: Historical Session Analytics

**What it is:** Track and display loot/sell efficiency metrics across sessions.

**Current state:** Session data exists only for the current session. No aggregation across sessions.

**Improved state:** A `session_analytics.lua` file accumulates: items per hour, average value per corpse, total value looted per session, items sold per session, sell success rate. A new "Analytics" section in Settings or a standalone view displays trends.

**Player-visible impact:** Players see whether their loot strategy is improving. "Am I making more per hour with the new config?" is quantifiable.

**Complexity:** L (persistent storage + aggregation + new UI surface)

**Dependencies:** UX-05 (session history persistence as foundation)

**Layer:** Lua

---

### 2.6 Macro Offloading

---

#### MACRO-01: Plugin-Based Rule Queries from Macros

**What it is:** Let loot.mac and sell.mac query the plugin's RulesEngine instead of reimplementing rule evaluation.

**Current state:** Both macros implement their own `EvaluateItem` / `CheckFilterList` subroutines that mirror the plugin's `RulesEngine::WillItemBeSold()` and `ShouldItemBeLooted()`. This is duplicated logic across two languages. When rules change, both implementations must be updated.

**Improved state:** Macros query `${CoOptUI.Rules.Evaluate[sell,ItemName]}` (already partially implemented in Phase 10 TLO) for sell decisions and `${CoOptUI.Rules.Evaluate[loot,ItemName]}` for loot decisions. The macro's own evaluation becomes the fallback (plugin absent).

**Player-visible impact:** Guaranteed consistency between macro decisions and UI display. If the UI says "Keep," the macro keeps. No more divergence.

**Complexity:** M (macro changes to prefer TLO query over local eval; TLO must handle items by name lookup)

**Dependencies:** Phase 10 TLO Enhancements (already partially complete)

**Layer:** Macro + Plugin

---

#### MACRO-02: Replace INI Progress Writes with IPC-Only

**What it is:** Eliminate remaining INI file writes for progress when the plugin is loaded.

**Current state:** loot.mac writes `loot_progress.ini` per corpse. sell.mac writes `sell_progress.ini` per item. These INI writes are preserved as fallback, but when the plugin is loaded, the IPC channel delivers the same data faster and without disk I/O.

**Improved state:** When `pluginLoaded = TRUE`, skip the INI progress writes entirely. The IPC channel is the sole progress data path. The INI writes remain only in the fallback (plugin absent) path.

**Player-visible impact:** Eliminates disk I/O during active loot/sell runs when the plugin is loaded. Marginal improvement in macro execution speed.

**Complexity:** S (add `pluginLoaded` guard around existing INI write lines)

**Dependencies:** None (IPC already implemented)

**Layer:** Macro

---

#### MACRO-03: Validate Config Script in Lua

**What it is:** Rewrite `shared_config/validate_config.mac` as a Lua script.

**Current state:** `validate_config.mac` validates INI files and checks for keep/sell conflicts using MQ2 macro TLO calls. It duplicates logic that exists in the Lua filter service and plugin RulesEngine.

**Improved state:** A Lua-based validator uses the plugin's `ini.readSection` API for fast INI access and the filter service's conflict detection logic (already implemented in `config_filters_actions.lua`). Accessible via `/itemui validate` or from the Settings UI.

**Player-visible impact:** Faster validation, better error messages, and integration with the Settings UI instead of a separate macro.

**Complexity:** S (translate macro logic to Lua using existing APIs)

**Dependencies:** None

**Layer:** Lua

---

### 2.7 Operational Quality

---

#### OPS-01: Comprehensive Health-Check Command

**What it is:** `/cooptui health` that validates all components and reports status.

**Current state:** `/cooptui status` shows cache sizes, rules counts, and debug level. It does not validate whether components are working correctly — just that they exist.

**Improved state:** `/cooptui health` runs a checklist:
- Plugin loaded and version matches Lua expectation
- Full data population verified (spot-check: a scanned item has non-zero `ac` or `hp` for a stat-bearing item)
- Rules loaded (sell sets > 0, loot sets > 0)
- IPC channels responding (send + receiveAll roundtrip)
- Config files exist and are readable (sell_config, loot_config, shared_config)
- Macro files exist at expected paths
- Last scan timestamps and durations
- Memory usage estimate

Output is color-coded: green for pass, yellow for warning, red for fail. Each failure includes the exact fix action.

**Player-visible impact:** "Something isn't working" -> `/cooptui health` -> immediate diagnosis with fix instructions. No more debugging by guesswork.

**Complexity:** M (validation logic for each component + formatted output)

**Dependencies:** None

**Layer:** Plugin + Lua

---

#### OPS-02: Patcher Auto-Update Check on Load

**What it is:** Check for updates when CoOpt UI loads, without requiring manual patcher launch.

**Current state:** The patcher is a standalone Python GUI that must be manually launched. Players who forget to check for updates run stale versions.

**Improved state:** On CoOpt UI startup, a lightweight HTTP check fetches the release manifest hash from GitHub. If it differs from the local manifest, a yellow banner appears: "CoOpt UI update available. Run the patcher to update." No automatic download — just notification.

**Player-visible impact:** Players always know when updates are available without manually checking.

**Complexity:** M (HTTP request from Lua using MQ's networking, or a simple `/shell curl` check; banner rendering)

**Dependencies:** None

**Layer:** Lua

---

#### OPS-03: Debug Diagnostics in Status Output

**What it is:** Include diagnostics ring buffer contents in `/cooptui status` output.

**Current state:** `diagnostics.lua` maintains a ring buffer of 20 errors. These are accessible in the Advanced tab but not from the `/cooptui status` command. A player troubleshooting in-game must navigate to Settings > Advanced to see errors.

**Improved state:** `/cooptui status` includes a "Recent errors:" section showing the last 5 entries from the diagnostics ring buffer. `/cooptui errors` shows all 20.

**Player-visible impact:** Faster troubleshooting from the console without navigating the UI.

**Complexity:** S (format diagnostics entries in command handler)

**Dependencies:** None

**Layer:** Lua (command handler in app.lua)

---

#### OPS-04: Plugin Build Verification in Deploy Pipeline

**What it is:** Add automated verification that the deployed plugin DLL matches the Lua layer version.

**Current state:** `build-and-deploy.ps1` and `sync-to-deploytest.ps1` copy files but do not verify version compatibility. A stale DLL could be deployed alongside new Lua code.

**Improved state:** The deploy script reads the plugin's embedded version string (from the DLL's `APIVersion` or a marker file) and compares against `coopui/version.lua:ITEMUI`. If mismatched, the script warns and optionally blocks deployment.

**Player-visible impact:** Eliminates a class of "works on my machine" deployment issues.

**Complexity:** S (version comparison in PowerShell deploy script)

**Dependencies:** None

**Layer:** Deployment

---

#### OPS-05: Commit Missing Plugin Source Files to Repo

**What it is:** Ensure all plugin source files referenced by the codebase are present in the repository.

**Current state:** `items.cpp` and `InventoryScanner.cpp` include `#include "../core/ItemDataPopulate.h"`. `items.cpp` also includes `#include "../scanners/SellScanner.h"` and `#include "../storage/SellCacheWriter.h"`. These files exist in the build environment (the plugin compiles and runs successfully per the validation checklist) but are not present in the `plugin/MQ2CoOptUI/` directory of the repository. A developer cloning the repo cannot compile the plugin without these files.

**Improved state:** All source files present in the repo. A developer can clone and build.

**Player-visible impact:** None directly — developer experience and build reproducibility.

**Complexity:** S (commit existing files)

**Dependencies:** None

**Layer:** Plugin (repo hygiene)

---

### 2.8 Phase 0 — Obvious Fixes

These are low-effort cleanups found during review that can be fixed immediately.

---

#### FIX-01: Remove Dead Loot View Code

Same as UX-03. `views/loot.lua` and `if false then LootView.render` in main_window.lua. Delete.

**Complexity:** S | **Layer:** Lua

---

#### FIX-02: Duplicate ImGui.SameLine() in config_general.lua

Lines 236-237 have two consecutive `ImGui.SameLine()` calls. Remove one.

**Complexity:** S | **Layer:** Lua

---

#### FIX-03: os.time() vs mq.gettime() Inconsistency in loot_ui.lua

`os.time()` is used for mythical countdown timing while `mq.gettime()` is used everywhere else. Use `mq.gettime()` consistently.

**Complexity:** S | **Layer:** Lua

---

#### FIX-04: os.execute Redundancy in settings.lua

Lines 72-73 use both `os.execute` and `mq.cmd` to open the config folder. One is sufficient.

**Complexity:** S | **Layer:** Lua

---

#### FIX-05: simpleHash Duplication

Identical `simpleHash` function in `inventory.lua` and `bank.lua`. Extract to `utils/`.

**Complexity:** S | **Layer:** Lua

---

## Section 3 — Prioritized Roadmap

### Rank 1: RT-01 — Non-Blocking Augment Operations

**Why #1:** With the data gap closed, this is now the most player-visible quality issue. Augment operations are one of the most common interactions in CoOpt UI (especially for EMU players who actively manage augments). The current 1+ second UI freeze per operation is jarring. Converting to a state machine follows the same proven pattern as `sell_batch.lua`, which already demonstrated this approach works perfectly.

**First step:** Define augment insert phases: `inspect`, `wait_display`, `click_socket`, `wait_confirm`, `done`. Implement each phase's completion check. Remove all `mq.delay()` calls from `augment_ops.lua`.

**Player experience the day it ships:** Click "Insert Augment" -> each step happens visibly without freezing the game. The player can continue playing while the operation proceeds.

---

### Rank 2: PERF-01 — Eliminate saveInventory Serialization Bottleneck

**Why #2:** A 4-second freeze after every inventory scan is the single most noticeable performance problem a regular player encounters. The plugin already has all 120+ fields per item in contiguous C++ memory — serialization to the Lua file format can be done in <5ms with `snprintf`. This is high impact with moderate effort.

**First step:** Add `saveInventoryToFile(path, items)` to `capabilities/items.cpp` that writes the same Lua-loadable format using `snprintf`. Replace `storage.saveInventory` call in `scan.lua` with the plugin version when available.

**Player experience the day it ships:** Open inventory -> items appear instantly -> no freeze. The 4-second hang is completely gone.

---

### Rank 3: REL-01 — Global Error Handler for Main Loop

**Why #3:** This is the highest reliability-to-effort ratio in the catalog. A single pcall wrapper in app.lua prevents the entire UI from crashing on any transient error. Takes 15 minutes to implement, prevents hundreds of potential crash scenarios. Every other improvement becomes more reliable once this is in place.

**First step:** In `app.lua`, wrap the `mainLoop.tick(now)` call in `pcall`. On error, call `diagnostics.recordError`, show status message, increment consecutive error counter.

**Player experience the day it ships:** CoOpt UI survives zone transitions, temporary TLO unavailability, and edge-case Lua errors without crashing. The player sees a brief error indicator instead of losing the UI entirely.

---

### Rank 4: UX-01 — Item Stat Comparison

**Why #4:** This is the single most differentiating feature CoOpt UI could add. No other MQ2 companion tool offers side-by-side stat comparison. For EMU players who actively manage gear, this transforms CoOpt UI from "a good inventory tool" to "the tool I can't play without." Now that the plugin provides all stat fields natively, comparisons are instant with no TLO overhead.

**First step:** Create `views/compare.lua` with a two-column layout. Accept two items (from right-click context menu: "Compare with equipped [slot]"). Compute delta per stat field. Render with green/red coloring.

**Player experience the day it ships:** Right-click any item -> "Compare with Earring" -> instant side-by-side stat diff. +15 HP, +3 AC, -2 STR shown clearly. Upgrade decisions become trivial.

---

### Rank 5: PERF-02 — Cache Filtered/Sorted Lists Per View

**Why #5:** This is a broad improvement across all 5+ table views that compounds over time. Eliminating per-frame filtered list construction reduces GC pressure and improves frame consistency, especially with 300+ bank items visible. Low effort, high breadth.

**First step:** In `inventory.lua`, add a version check: `if scanVersion == lastFilterVersion and searchText == lastSearchText then return cachedFiltered end`. Apply the same pattern to `bank.lua`, `sell.lua`, `augments.lua`, `reroll.lua`.

**Player experience the day it ships:** Smoother scrolling in all item tables, especially with large inventories. No more micro-stutters when browsing.

---

### Rank 6: OPS-01 — Comprehensive Health-Check Command

**Why #6:** This is the "tier-1 support experience." When something doesn't work, `/cooptui health` tells the player exactly what's wrong and how to fix it. With the expansion adding more components (full data population, cursor, window checks), there are more things that can be misconfigured. A health check catches them all.

**First step:** Create a `healthCheck()` function in `MQ2CoOptUI.cpp` that validates: plugin version, data population (spot-check one item for non-zero stats), rules loaded, config files present, IPC responsive. Format output with color-coded pass/warn/fail.

**Player experience the day it ships:** `/cooptui health` -> green checkmarks for everything working, red X with fix instructions for anything broken. No more guesswork.

---

### Rank 7: RT-02 — Non-Blocking Quantity Picker

**Why #7:** Every stack split freezes the UI for 450ms. This is a small annoyance that adds up over a session with many stackable items. Very low effort to fix.

**First step:** Replace the `mq.delay` calls in main_loop.lua phase 7 with a 3-phase state machine (`wait_qty_wnd` -> `set_slider` -> `click_accept`).

**Player experience the day it ships:** Stack splits happen smoothly without freezing the game.

---

### Rank 8: REL-03 — Version Compatibility Detection

**Why #8:** As CoOpt UI matures with more components (plugin, Lua, macros), version drift becomes a real risk. A simple check prevents hours of debugging when a player updates Lua but forgets the macros.

**First step:** Add `/cooptui ipc send version "loot.mac|X.Y.Z"` to loot.mac after `pluginLoaded` detection. In `drainIPCFast`, check a `version` channel and compare.

**Player experience the day it ships:** After updating, if macros are stale, a yellow banner appears immediately. No more "why isn't loot working right?"

---

### Rank 9: DATA-01 — Real-Time Inventory Value Tracking

**Why #9:** A "should I go sell?" indicator that updates as items are looted is a natural extension of the existing scan infrastructure. With the plugin now providing accurate values for every item, this is trivial to compute. Low effort, high utility for players who optimize their farming.

**First step:** After each inventory scan, sum `totalValue` for items where `willSell == true`. Store in CacheManager. Expose via TLO and Lua API. Add to inventory footer: "Sellable: 12,450pp."

**Player experience the day it ships:** Inventory footer shows live sellable value. Player knows at a glance whether it's worth visiting the merchant.

---

### Rank 10: RT-03 — Live High-Value Item Alert

**Why #10:** A natural extension of the IPC streaming infrastructure. During loot runs, high-value items deserve immediate attention. This is the kind of polish that makes players recommend a tool to others.

**First step:** In `drainIPCFast`, check item value against a configurable threshold. If exceeded, set `uiState.lootAlert = {name, value, expiry}`. In main_window, render a brief toast overlay when `lootAlert` is set and not expired.

**Player experience the day it ships:** During a loot run, a brief toast pops: "Crystallized Sulfur — 4,500pp!" The player never misses a valuable drop.

---

## Section 4 — The Vision

Imagine you're an EverQuest EMU player who just installed CoOpt UI for the first time. Here's what you experience:

You launch MQ and a Welcome process validates your environment — every config file checked, every folder verified, any missing defaults created automatically. A 14-step wizard walks you through your sell rules, loot preferences, and epic class configuration. You're productive in under three minutes.

You open your inventory. Items appear instantly — not in a second, not in 500 milliseconds, *instantly*. The table is dense with information: item name, value, weight, type, and stat columns for AC, HP, and whatever you've chosen to display. Hovering over any item pops a tooltip with complete stats, spell effects, class/race restrictions, and augment socket details. There is no "loading" delay. The data was read from the game's memory by a C++ scanner in 0 milliseconds during a single struct traversal. This is already real — the expansion made it so.

You right-click a ring in your inventory and select "Compare with equipped." A comparison view opens showing your equipped ring side-by-side with the bag ring: +12 HP, +3 AC, -1 STR, +2 svFire. Green and red deltas make the upgrade decision obvious. You click "Swap" and the equipment view updates in the same frame.

You search for "cloak" in the global search bar. Results appear from your inventory, your bank, and your sell list — all in one unified table. You see your Cloak of Flames is in Bank Bag 4 Slot 7. You click it and the Bank view opens, scrolled to that item.

You start a loot macro. The Loot Companion opens within one frame. As each corpse is looted, items appear in the Current tab in real time — not after the run, not in batches, but *as they are picked up*. A running total shows: "147 items, 34,250pp, Tribute: 12,100." Skipped items appear in the Skip History tab with reasons, also in real time. You see "Skipped: Bone Chips — below min value (2pp < 10pp)" and decide to lower your threshold for next time. A toast notification pops briefly: "Crystallized Sulfur — 4,500pp!" — your best drop this session.

You click the Augment Utility. It shows your target item's sockets with current contents. Compatible augments from your inventory and bank are listed, scored, and ranked. Hovering an augment in your Augments tab shows a tooltip: "Fits: Earring of Station (socket 3), Ring of the Ancients (socket 1)." You click Insert and the operation proceeds smoothly — no UI freeze, each step visible — while you continue playing.

You run `/cooptui health` and see green checkmarks across the board. Plugin loaded: v1.3.0 — data population verified. Rules loaded: 47 keep, 23 junk, 15 always-loot. Config: all files present. Macros: version match. IPC: responsive. Last scan: 0ms ago (142 items, full stats).

At the end of your session, you check the History tab. Items per hour: 312. Average value per corpse: 45pp. Total value looted this session: 34,250pp. Best session this week: 41,000pp. You export your config as a backup package and log off.

A player who has used MQ2 for years, who has tried every inventory tool and macro companion available, would immediately recognize that CoOpt UI is in a different class. Not because it has more features than other tools — but because every feature *works correctly, responds instantly, and provides exactly the information needed at the moment it's needed.*

---

## Section 5 — Risks and Constraints

### 5.1 MQ Internal API Limitations

The plugin reads `ItemDefinition*` struct members directly via `PopulateItemData`. These structs are defined in eqlib and their layout can change between MQ versions. The EMU branch of eqlib may have different struct definitions than the Live branch. Each MQ update carries a risk that struct field names or offsets change, requiring `PopulateItemData` updates. **Mitigation:** Pin to a specific MQ commit for each release. Test against eqlib member names before each build. Guard individual field reads with `#ifdef` where presence is uncertain.

### 5.2 EMU-Specific Constraints

EMU servers may have items with non-standard properties (custom AugType values, modified spell effects, items with IDs that conflict with standard EQ databases). The plugin reads whatever the game client provides — it cannot validate against a canonical item database. **Mitigation:** The plugin treats all data as opaque and does not apply EMU-vs-Live filtering. Edge cases (augType values that don't match standard bitmask definitions) should be handled gracefully with "Unknown" labels rather than crashes.

### 5.3 Item Comparison Complexity (UX-01)

Item comparison is straightforward for direct stats (AC, HP, STR) but complex for derived stats (haste, proc rates, focus effects). Comparing spell effects requires either a spell database or additional TLO calls to resolve spell IDs to names and effects. The comparison view should start with numeric stats only and add spell comparison in a second pass. **Mitigation:** Phase 1 of comparison is numeric-only. Spell comparison is a clear follow-on.

### 5.4 saveInventory Format Compatibility (PERF-01)

Moving serialization to C++ requires generating a Lua-loadable file format. If the format differs from what `storage.loadInventory()` expects, persistence breaks. **Mitigation:** Generate the exact same Lua table format as the current Lua serializer. Add a format version marker. Keep the Lua serializer as fallback.

### 5.5 Augment State Machine Timing (RT-01)

Augment operations interact with EQ windows (Inspect, ItemDisplayWindow, ConfirmationDialogBox) that have variable open times depending on server latency and client performance. A state machine with fixed timeouts could fail on slow clients or high-latency EMU servers. **Mitigation:** Use generous minimum settle times (200ms per phase). Make timeouts configurable. Add retry logic before declaring failure.

### 5.6 Session Analytics Privacy

Accumulating per-session analytics (items per hour, total value) could concern players who share their MQ instance. **Mitigation:** Analytics are stored locally only, in the same config directory as other CoOpt UI data. No data is ever transmitted. A clear "Clear History" button in the Analytics view.

### 5.7 Patcher HTTP Check (OPS-02)

Making HTTP requests from within MQ raises questions about network access, firewall rules, and EMU server ToS compliance. Some EMU servers restrict what network calls MQ plugins can make. **Mitigation:** The check is a single HTTPS GET to a known GitHub URL. It does not interact with the EMU server. The check is opt-in (disabled by default) and can be fully disabled in settings. If the check fails (network unavailable, blocked by firewall), it silently skips with no error.

### 5.8 Missing Repo Files (OPS-05)

Three source files referenced by `items.cpp` and `InventoryScanner.cpp` (`core/ItemDataPopulate.h`, `scanners/SellScanner.h`, `storage/SellCacheWriter.h` and their `.cpp` counterparts) exist in the build environment but are not present in the `plugin/MQ2CoOptUI/` directory of the repository. Until committed, a developer cloning the repo cannot compile the plugin. **Mitigation:** Commit these files from the build environment to the repo as a priority housekeeping item.

### 5.9 Ongoing Maintenance Burden

The opportunities with the highest ongoing maintenance cost are:
- **PopulateItemData** (already complete): Must be updated when eqlib struct layout changes. Cost: ~1 hour per MQ version update.
- **MACRO-01** (Plugin-based rule queries): Requires keeping the TLO rule evaluation in sync with the Lua evaluation. Cost: testing on rule changes.
- **UX-01** (Item comparison): New stats added to the game require comparison view updates. Cost: minimal if the stat is already in the scan.

The lowest-maintenance opportunities are PERF-02 (cached lists), REL-01 (error handler), RT-02 (quantity picker), and the Phase 0 fixes — all are one-time changes with no ongoing cost.
