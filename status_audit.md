# CoOpt UI — Status System Audit

## Issues Log

Issues and ambiguities discovered during the audit are recorded here as they are found.

1. **`statusText` is an alias, not a first-class status.** Loot history entries store `statusText` (string) and `willSell` (bool) as their status representation. These are computed once when the item is ingested into history and never updated afterward. If the user changes sell config (e.g. adds an item to Keep list), stale history entries will show the old status. This is by design (history is a snapshot) but creates a UI inconsistency if the user expects live status.

2. **Bank items have no `willSell`/`sellReason` until first scan.** When bank cache is loaded from disk (`loadSnapshotsFromDisk`, `ensureBankCacheFromStorage`), sell status is NOT attached. The view (`bank.lua:341-346`) has a fallback to `getSellStatusForItem()` per-row, but this is a per-frame TLO call — expensive for large banks. The deferred scan in `handleAutoShowHide` (bank just opened) calls `computeAndAttachSellStatus(bankCache)` which fixes it, but there is a window of multiple frames where bank items have no status and the fallback fires.

3. **C++ `RulesEngine` does not know about RerollList protection.** The C++ `WillItemBeSold()` has no equivalent of the Lua `rerollListIdSet`/`rerollListNameSet` check. When the C++ plugin path is used for sell scanning (`scanSellItems` plugin fast path), items on the reroll list would be marked `willSell=true` by C++. This is mitigated by the Lua `computeAndAttachSellStatus` re-run after the plugin scan (scan.lua:517-519), which overwrites the C++ result. But if the re-run were ever skipped, reroll-listed items could be sold.

4. **`inKeep` / `inJunk` have dual representations.** The `inKeep` field is a *summary* boolean (`inKeepExact OR inKeepContains OR inKeepType`), while `inKeepExact` is the granular flag. Storage persists `inKeep`/`inJunk` (the summary), but `attachGranularFlags` only applies stored overrides to `inKeepExact`/`inJunkExact`. The summary `inKeep` is recomputed from granulars. This means stored `inKeep=true` from a contains-match survives only if the contains rule still matches. This is correct behavior but is confusing because the same field name means different things in storage vs. runtime.

5. **`willLoot` / `lootReason` are computed once per scan and never refreshed.** Loot items are scanned when the corpse window opens. If loot config changes while the corpse is open, stale `willLoot` values persist until the corpse is re-scanned (which only happens if items change). No config-change event triggers a loot rescan.

6. **`sellReason` string "Epic" is renamed to "EpicQuest" in every view independently.** The `willItemBeSold()` function returns `"Epic"` as the reason, but inventory.lua, sell.lua, bank.lua, and loot_ui.lua all independently check for `statusText == "Epic"` and rename it to `"EpicQuest"` for display. This is duplicated in 4 view files.

7. **`LoreDup` reason exists only in loot scan, not in rules.** The `LoreDup` loot reason is assigned in `scan.lua:749` when a lore item is already in inventory. This check bypasses the rules engine entirely — it runs *after* `shouldItemBeLooted()` returns and can override its result. This is intentional (game-state check, not config rule) but means the C++ loot evaluator and the Lua evaluator can diverge on lore items.

8. **Mythical alert `decision` field.** The mythical alert system uses a `decision` field with values `"pending"`, `"loot"`, `"destroy"` stored in `loot_mythical_alert.ini`. This is a separate status system from the item sell/loot status — it tracks the user's decision about a mythical item drop. It is read-only from the Lua side (written by loot.mac).

9. **`source` field inconsistency.** Items have a `source` field set to `"inv"`, `"bank"`, or `"loot"`. This is set during scan but not during `addItemToInventory` (item_ops.lua:366) — newly added items via that path have no `source`. The `buildItemFromMQ` function sets `source` based on the 4th parameter, but the item_ops manual add path does not. Bank items loaded from disk have their source force-set to `"bank"` in `ensureBankCacheFromStorage`.

10. **Reroll sync failure tracking (uncommitted change).** The pending sync system now tracks per-item failures (`syncedCount`, `failedCount`, `failedItems` with reason strings) and advances to the next item instead of aborting the entire sync. Three failure reasons are used: `"Server timeout"`, `"Not in inventory"`, `"Pickup timeout"`. These are transient state on `pendingRerollSync` — not persisted. This is correct behavior (failed items stay in the pending list for retry on next sync).

11. **Reroll view now has separate Status and Location columns (uncommitted change).** The reroll list table was restructured: the old "Status" column (which mixed availability and location) was split into "Status" (`"Available"` / `"List Only"`) and "Location" (`"Inventory"` / `"Bank"` / `"—"`). Three-tier coloring: green = inventory (ready to roll), yellow = bank (needs move), grey = list only. This is a display-only change with no status system implications.

12. **Generation-based cache invalidation for reroll lists (uncommitted change).** `reroll_service.lua` now uses a `_listGeneration` counter incremented on every list mutation (`markListDirty()`). Cached ID sets, deduplicated lists, and location sets are rebuilt only when the generation changes. This eliminates per-frame O(n) iteration for list lookups and sorts. The generation counter is also exposed via `getListGeneration()` for the view's sort cache to detect staleness.

---

## Phase 1 — Status Registry

### 1. Sell Status Fields

#### 1.1 `willSell` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `willSell` |
| **Type** | `boolean` |
| **Defined In** | Computed, not stored as constant. Lua: `rules.lua:271-335` (`willItemBeSold`), C++: `RulesEngine.cpp:328-388` (`WillItemBeSold`), struct field: `ItemData.h:37` |
| **Assigned By** | `sell_status.lua:139` (`computeAndAttachSellStatus`), `sell_status.lua:152` (`getSellStatusForItem`), `scan.lua:127-128,171-172,375-377,542-543` (full/targeted/incremental/sell scans), `item_ops.lua:201-203,376-377` (`updateSellStatusForItemName`, `addItemToInventory`), `loot_feed_events.lua:58`, `main_loop.lua:333,341` (loot session merge), `macro_bridge.lua:524,530` (IPC loot drain) |
| **Consumed By** | `sell.lua:108,145` (sell count, showOnlySellable filter), `inventory.lua:315-317`, `bank.lua:342-344`, `sell.lua:339-341`, `loot_ui.lua:428,479` (status column display), `ui_common.lua:20-31` (context menu icon), `filter_service.lua:146` (showOnlySellable filter), `sell_batch.lua:108` (batch queue filter), `storage.lua:127` (persistence), `sort.lua:22` (sort by status), `columns.lua:86` (column value) |
| **Intended Meaning** | Whether this item will be sold when Auto Sell runs. `true` = item will be sold to merchant. `false` = item is protected/kept. |
| **Conflicts** | See Conflict C1 (C++ vs Lua disagreement on reroll list). See Conflict C5 (stale after config change until rescan). |

#### 1.2 `sellReason` (string)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `sellReason` |
| **Type** | `string` |
| **Defined In** | Return values of `willItemBeSold()` in `rules.lua:271-335` and `RulesEngine.cpp:328-388` |
| **Valid Values** | `"RerollList"`, `"AugmentAlwaysSell"`, `"AugmentNeverLoot"`, `"NeverLoot"`, `"NoDrop"`, `"NoTrade"`, `"Epic"`, `"Keep"`, `"Junk"`, `"KeepKeyword"`, `"JunkKeyword"`, `"KeepType"`, `"ProtectedType"`, `"Lore"`, `"Quest"`, `"Collectible"`, `"Heirloom"`, `"Attuneable"`, `"AugSlots"`, `"HighValue"`, `"Tribute"`, `"BelowSell"`, `"Sell"` |
| **Assigned By** | Same as `willSell` — always set together. |
| **Consumed By** | `inventory.lua:316`, `sell.lua:340`, `bank.lua:343` (display text), `sort.lua:22,116` (sort key), `columns.lua:86` (column value), `sell_batch.lua:117,162` (logging), `storage.lua:128` (persistence). Views rename `"Epic"` → `"EpicQuest"` for display. |
| **Intended Meaning** | The rule that determined the sell decision. Used for display and debugging. |
| **Conflicts** | See Conflict C2 (display name diverges from internal name — `"Epic"` vs `"EpicQuest"`). |

### 2. Sell Filter Granular Flags

#### 2.1 `inKeepExact` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inKeepExact` |
| **Defined In** | `sell_status.lua:112` (`attachGranularFlags`) |
| **Assigned By** | `sell_status.lua:112,120-123` (from config list lookup + stored override), `item_ops.lua:191` (`updateSellStatusForItemName`) |
| **Consumed By** | `rules.lua:297` (step 4 of `willItemBeSold`), `storage.lua:124` (persisted as `inKeep`) |
| **Intended Meaning** | Item name is in the Keep exact list (sell_keep_exact.ini or valuable_exact.ini). |
| **Conflicts** | None. |

#### 2.2 `inJunkExact` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inJunkExact` |
| **Defined In** | `sell_status.lua:113` |
| **Assigned By** | `sell_status.lua:113,120-125` (from config list lookup + stored override), `item_ops.lua:192` |
| **Consumed By** | `rules.lua:299` (step 5 of `willItemBeSold`), `storage.lua:125` (persisted as `inJunk`) |
| **Intended Meaning** | Item name is in the Always-Sell exact list (sell_always_sell_exact.ini). |
| **Conflicts** | None. |

#### 2.3 `inKeepContains` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inKeepContains` |
| **Defined In** | `sell_status.lua:114` |
| **Assigned By** | `sell_status.lua:114`, `item_ops.lua:194` |
| **Consumed By** | `rules.lua:301` (step 6), summary into `inKeep` |
| **Intended Meaning** | Item name matches a Keep contains keyword. |

#### 2.4 `inJunkContains` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inJunkContains` |
| **Defined In** | `sell_status.lua:115` |
| **Assigned By** | `sell_status.lua:115`, `item_ops.lua:195` |
| **Consumed By** | `rules.lua:303` (step 7), summary into `inJunk` |
| **Intended Meaning** | Item name matches an Always-Sell contains keyword. |

#### 2.5 `inKeepType` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inKeepType` |
| **Defined In** | `sell_status.lua:116` |
| **Assigned By** | `sell_status.lua:116`, `item_ops.lua:196` |
| **Consumed By** | `rules.lua:305` (step 8), summary into `inKeep` |
| **Intended Meaning** | Item type is in the Keep types list. |

#### 2.6 `isProtectedType` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `isProtectedType` |
| **Defined In** | `sell_status.lua:117` |
| **Assigned By** | `sell_status.lua:117`, `item_ops.lua:197` |
| **Consumed By** | `rules.lua:307` (step 9), summary into `isProtected` |
| **Intended Meaning** | Item type is in the Protected types list (sell_protected_types.ini). |

#### 2.7 `inKeep` (boolean — summary)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inKeep` |
| **Defined In** | `sell_status.lua:127` |
| **Assigned By** | `sell_status.lua:127` (`= inKeepExact OR inKeepContains OR inKeepType`), `item_ops.lua:198,388` |
| **Consumed By** | `ui_common.lua:20,202-260` (context menu — Keep/Junk buttons), `sell.lua:107,273,307` (keep count, button state), `storage.lua:306` (merge filter status), `reroll.lua:367` (context menu passthrough) |
| **Intended Meaning** | Summary: item is on any keep list (exact, contains, or type). |
| **Conflicts** | See Issue 4 (dual representation with storage). |

#### 2.8 `inJunk` (boolean — summary)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inJunk` |
| **Defined In** | `sell_status.lua:128` |
| **Assigned By** | `sell_status.lua:128` (`= inJunkExact OR inJunkContains`), `item_ops.lua:199,388` |
| **Consumed By** | `ui_common.lua:202-260` (context menu — Keep/Junk buttons), `sell.lua:274,317` (button state), `storage.lua:306` (merge filter status) |
| **Intended Meaning** | Summary: item is on any always-sell list (exact or contains). |

#### 2.9 `isProtected` (boolean — summary)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `isProtected` |
| **Defined In** | `sell_status.lua:129` |
| **Assigned By** | `sell_status.lua:129` (`= isProtectedType`), `item_ops.lua:200` |
| **Consumed By** | `sell.lua:114` (protected count display), `storage.lua:126` (persistence) |
| **Intended Meaning** | Summary: item type is protected from selling. |

### 3. Loot Status Fields

#### 3.1 `willLoot` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `willLoot` |
| **Type** | `boolean` |
| **Defined In** | Computed. Lua: `rules.lua:423-486` (`shouldItemBeLooted`), C++: `RulesEngine.cpp:393-447` (`ShouldItemBeLooted`), struct: `ItemData.h:39` |
| **Assigned By** | `scan.lua:762` (loot scan) |
| **Consumed By** | `filter_service.lua:151` (showOnlyLoot filter) |
| **Intended Meaning** | Whether this item should be looted from the corpse by loot.mac. |
| **Conflicts** | See Issue 5 (never refreshed after initial scan). See Issue 7 (`LoreDup` override). |

#### 3.2 `lootReason` (string)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `lootReason` |
| **Type** | `string` |
| **Defined In** | Return values of `shouldItemBeLooted()` in `rules.lua:423-486` and `RulesEngine.cpp:393-447`, plus `scan.lua:749` for `LoreDup` |
| **Valid Values** | `"RerollList"`, `"AugmentNeverLoot"`, `"Epic"`, `"SkipExact"`, `"SkipContains"`, `"SkipType"`, `"TributeOverride"`, `"AlwaysExact"`, `"AlwaysContains"`, `"AlwaysType"`, `"Value"`, `"Clicky"`, `"Quest"`, `"Collectible"`, `"Heirloom"`, `"Attuneable"`, `"AugSlots"`, `"NoMatch"`, `"NoConfig"`, `"LoreDup"` (scan-level override) |
| **Assigned By** | `scan.lua:763` |
| **Consumed By** | Not directly displayed in UI (loot view shows sell status, not loot reason). Used internally. |
| **Intended Meaning** | The rule that determined the loot decision. |

### 4. Loot History / Feed Status Fields

#### 4.1 `statusText` (string — loot history entry)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `statusText` |
| **Type** | `string` |
| **Defined In** | Not a constant. Computed inline. |
| **Assigned By** | `loot_feed_events.lua:45-48,58` (from `getSellStatusForItem`), `main_loop.lua:333,341,1625,1628` (session merge + deferred sell status), `macro_bridge.lua:524,530` (IPC loot drain) |
| **Consumed By** | `loot_ui.lua:426-432,477` (loot history/current tab display), `app.lua:272,287` (history persistence) |
| **Intended Meaning** | The sell status reason string for a looted item (what will happen when you try to sell it). Uses the same `sellReason` vocabulary but stored as `statusText` in history entries. |
| **Conflicts** | See Issue 1 (never updated after initial computation). Initialized as `"—"` (em dash) which is a display sentinel meaning "not yet computed". |

#### 4.2 Loot history `willSell` (boolean — in history entry)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `willSell` (on loot history entry, not the item) |
| **Assigned By** | `loot_feed_events.lua:58`, `main_loop.lua:333,341` |
| **Consumed By** | `loot_ui.lua:428,479` (status color: red=will sell, green=keep) |
| **Intended Meaning** | Whether looted item will be sold. Snapshot at loot time. |

### 5. Mythical Alert Decision

#### 5.1 `decision` (string — mythical alert)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `decision` (on `uiState.lootMythicalAlert`) |
| **Type** | `string` |
| **Defined In** | Read from `loot_mythical_alert.ini` |
| **Valid Values** | `"pending"`, `"loot"`, `"destroy"` |
| **Assigned By** | `main_loop.lua:237,248,444,455` (read from INI on poll) |
| **Consumed By** | `loot_ui.lua` (mythical decision card display — shows Loot/Destroy buttons when `"pending"`, shows outcome when decided) |
| **Intended Meaning** | User's decision about a mythical item drop. Written by loot.mac, read by ItemUI. |
| **Conflicts** | None — separate system, read-only from Lua. |

### 6. Item Source / Origin

#### 6.1 `source` (string)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `source` |
| **Type** | `string` |
| **Defined In** | Set during scan/creation. |
| **Valid Values** | `"inv"`, `"bank"`, `"loot"` |
| **Assigned By** | `scan.lua:110` (inventory plugin: `row.source or "inv"`), `scan.lua:405,480` (bank plugin/disk: `row.source or "bank"`), `scan.lua:443,450` (bank MQ scan: `buildItemFromMQ(..., "bank")`), C++ `ItemDataToTable.cpp` (sets `source` on scan results) |
| **Consumed By** | `augment_ops.lua` (determines pickup command: `pack` vs `bank`), `ui_common.lua` (context menu actions differ by source), `item_ops.lua` (move direction), `main_loop.lua:500-503` (quantity picker pickup command) |
| **Intended Meaning** | Where the item physically resides (inventory, bank, or corpse loot window). |
| **Conflicts** | See Issue 9 (`addItemToInventory` does not set `source`). |

### 7. Item Ordering

#### 7.1 `acquiredSeq` (number)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `acquiredSeq` |
| **Type** | `number` (monotonically increasing integer) |
| **Defined In** | `scanState.nextAcquiredSeq` in `state.lua:177` |
| **Assigned By** | `scan.lua:116-121,160-166,262-268,362-364` (all scan paths), `item_ops.lua:370-373` (`addItemToInventory`) |
| **Consumed By** | `sort.lua` (sort by acquired order), `storage.lua:129` (persistence) |
| **Intended Meaning** | Monotonic sequence number tracking when an item entered inventory. Used for "acquired order" sorting. Persisted so order survives reloads. |
| **Conflicts** | None. |

### 8. Reroll List Status

#### 8.1 Reroll List Protection (virtual status — no per-item field)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `rerollListIdSet` / `rerollListNameSet` (on sell/loot config cache, not on item) |
| **Defined In** | `reroll_service.lua:430-449` (`getRerollListProtection`) |
| **Assigned By** | `sell_status.lua:23-29` (merged into sell config cache), `scan.lua:702-706` (merged into loot config cache) |
| **Consumed By** | `rules.lua:274-276` (sell: step 0, highest priority), `rules.lua:431-433` (loot: highest priority skip) |
| **Intended Meaning** | Items on the augment or mythical reroll list must never be sold and should be skipped by loot automation. |
| **Conflicts** | See Issue 3 (C++ RulesEngine lacks this check). The `sellReason` value `"RerollList"` is displayed with a special color in views when `theme.Colors.RerollList` is defined. |

### 9. Macro State Flags

#### 9.1 `sellMacState.luaRunning` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `luaRunning` on `sellMacState` |
| **Assigned By** | `sell_batch.lua:143,227-229` |
| **Consumed By** | Sell progress bar (sell view checks `sellMacState.luaRunning` to show progress) |
| **Intended Meaning** | Whether a Lua batch sell is currently in progress. |

#### 9.2 `sellMacState.pendingScan` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `pendingScan` on `sellMacState` |
| **Assigned By** | `sell_batch.lua:215,235`, `main_loop.lua:180` (macro finish) |
| **Consumed By** | `main_loop.lua:1015-1023` (phase 8: triggers deferred inventory rescan) |
| **Intended Meaning** | Sell operation finished; inventory needs rescan. |

#### 9.3 `lootMacState.pendingScan` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `pendingScan` on `lootMacState` |
| **Assigned By** | `main_loop.lua:228` (loot macro finish) |
| **Consumed By** | `main_loop.lua:999-1013` (phase 8: triggers deferred incremental scan) |
| **Intended Meaning** | Loot operation finished; inventory needs rescan. |

#### 9.4 `uiState.rerollPendingScan` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `rerollPendingScan` on `uiState` |
| **Assigned By** | `main_loop.lua:813` (after mythical roll) |
| **Consumed By** | `main_loop.lua:1025-1033` (phase 8: triggers inventory + bank rescan) |
| **Intended Meaning** | Reroll operation finished; inventory/bank need rescan. |

### 10. Sell Batch Phase States

#### 10.1 Sell batch `phase` (string — internal to sell_batch.lua)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `phase` on `batchState.current` |
| **Valid Values** | `"wait_selected"`, `"wait_sold"` |
| **Defined In** | `sell_batch.lua:257,290` |
| **Intended Meaning** | Current state of the per-item sell state machine. `"wait_selected"` = waiting for merchant label to show item. `"wait_sold"` = waiting for slot to clear after sell button click. |

#### 10.2 Manual sell `phase` (string — internal to item_ops.lua)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `phase` on `state.sellState` |
| **Valid Values** | `"initial_delay"`, `"after_pickup_delay"`, `"wait_selected"`, `"click_sell_delay"`, `"wait_sold"` |
| **Defined In** | `item_ops.lua:80,113,121,131,147` |
| **Intended Meaning** | Current state of the manual single-item sell state machine. |

### 11. Scan State Flags

#### 11.1 `scanState.sellStatusAttachedAt` (number | nil)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `sellStatusAttachedAt` |
| **Assigned By** | `scan.lua:92,128,173,256,288,309,337,377,394,521,549,559,566` (set to `mq.gettime()` after attach, `nil` before scan) |
| **Consumed By** | `main_loop.lua:929,933` (skip redundant re-attach if already done this scan cycle), `state.lua:181` (initial nil) |
| **Intended Meaning** | Timestamp when sell status was last computed for inventory items. `nil` = status needs recomputation. Used to avoid redundant sell-status computation when multiple code paths trigger scans in the same cycle. |

#### 11.2 `scanState.inventoryBagsDirty` (boolean)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `inventoryBagsDirty` |
| **Assigned By** | `sell_batch.lua:219,246` (after sell batch ends), `main_loop.lua:230,888` (loot window open/close) |
| **Consumed By** | `scan.lua:595` (`maybeScanInventory` — triggers targeted rescan of changed bags) |
| **Intended Meaning** | Inventory bags have changed and need re-fingerprinting. |

### 12. Reroll Sync State (uncommitted changes)

#### 12.1 `pendingRerollSync.syncedCount` (number)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `syncedCount` on `rerollState.pendingRerollSync` |
| **Assigned By** | `main_loop.lua:phase8b` (incremented on successful server ack) |
| **Consumed By** | `main_loop.lua:phase8b` (completion message), `reroll.lua` (sync button tooltip progress) |
| **Intended Meaning** | Number of pending items successfully synced to server in this sync run. |

#### 12.2 `pendingRerollSync.failedCount` (number)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `failedCount` on `rerollState.pendingRerollSync` |
| **Assigned By** | `main_loop.lua:phase8b` (incremented on timeout or item-not-found) |
| **Consumed By** | `main_loop.lua:phase8b` (completion message), `reroll.lua` (sync button tooltip) |
| **Intended Meaning** | Number of pending items that failed to sync in this sync run. |

#### 12.3 `pendingRerollSync.failedItems` (array of `{id, name, reason}`)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `failedItems` on `rerollState.pendingRerollSync` |
| **Valid Reasons** | `"Server timeout"`, `"Not in inventory"`, `"Pickup timeout"` |
| **Assigned By** | `main_loop.lua:phase8b` (appended on each failure) |
| **Consumed By** | Not yet displayed in UI (tracked for potential future display). |
| **Intended Meaning** | Per-item failure details for debugging/display. Transient — not persisted. |

#### 12.4 `pendingRerollSync.totalCount` (number)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `totalCount` on `rerollState.pendingRerollSync` |
| **Assigned By** | `reroll_service.lua:startPendingSync` (set to `#entries` at start) |
| **Consumed By** | `main_loop.lua:phase8b` (progress messages), `reroll.lua` (sync button label and tooltip) |
| **Intended Meaning** | Total number of pending items in this sync run (for progress display). |

### 13. Reroll List Cache Generation

#### 13.1 `_listGeneration` (number — internal to reroll_service.lua)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `_listGeneration` (module-local counter) |
| **Assigned By** | `reroll_service.lua:markListDirty()` (called on every augList/mythicalList mutation) |
| **Consumed By** | `reroll_service.lua` (cached ID sets, unique lists, location sets only rebuild when generation changes), `reroll.lua` (sort cache invalidation via `getListGeneration()`) |
| **Intended Meaning** | Monotonic counter that invalidates all derived caches when any reroll list changes. Avoids O(n) per-frame rebuilds. |
| **Conflicts** | None. |

### 14. Reroll View Display Status (uncommitted changes)

#### 14.1 Reroll list "Status" column

| Attribute | Detail |
|-----------|--------|
| **Valid Values** | `"Available"` (item in inventory or bank), `"List Only"` (item not found) |
| **Displayed In** | `reroll.lua` — server reroll list table, Status column |
| **Intended Meaning** | Whether the listed item is physically available to the character for a roll. |

#### 14.2 Reroll list "Location" column

| Attribute | Detail |
|-----------|--------|
| **Valid Values** | `"Inventory"` (green), `"Bank"` (yellow/warning), `"—"` (grey/muted) |
| **Displayed In** | `reroll.lua` — server reroll list table, Location column |
| **Intended Meaning** | Where the listed item is physically located. Inventory = ready to roll. Bank = needs to be moved first. `"—"` = not found in either. |

### 15. UI Display Sentinels

#### 15.1 `"—"` (em dash — display sentinel)

| Attribute | Detail |
|-----------|--------|
| **Identifier** | `"—"` (em dash, U+2014) |
| **Used In** | `inventory.lua:316`, `sell.lua:340,346`, `bank.lua:343,348`, `loot_ui.lua:367,426,477`, `loot_feed_events.lua:45`, `main_loop.lua:333,341`, `macro_bridge.lua:524,530` |
| **Intended Meaning** | "Status not yet computed" or "no status available". Displayed when `sellReason` is nil/empty or `statusText` has not been resolved. |
| **Conflicts** | This is a display string, not a status identifier. Used inconsistently — sometimes checked with `== ""`, sometimes with `== "—"`. The views normalize: `if statusText == "" then statusText = "—"`. |

---

## Phase 2 — Conflict & Precedence Analysis

### Precedence Order (Sell Rules)

The canonical sell rule evaluation order is defined in `rules.lua:271-335` and mirrored exactly in `RulesEngine.cpp:328-388`. The precedence is (highest to lowest):

1. **RerollList** — Items on augment/mythical reroll list are never sold (Lua only; C++ lacks this check)
2. **AugmentAlwaysSell** — Augmentation-type items on the augment-always-sell list
3. **AugmentNeverLoot** — Augmentation-type items on the augment-skip-loot list (sold to clear inventory)
4. **NeverLoot** — Items on the skip-loot exact list (sold to clear inventory)
5. **NoDrop** — Protected if `protectNoDrop` is enabled
6. **NoTrade** — Protected if `protectNoTrade` is enabled
7. **Epic** — Epic quest items (class-filtered)
8. **Keep** — Exact keep list match
9. **Junk** — Exact always-sell list match
10. **KeepKeyword** — Keep contains keyword match
11. **JunkKeyword** — Always-sell contains keyword match
12. **KeepType** — Keep by item type
13. **ProtectedType** — Protected by item type
14. **Lore** — Protected if `protectLore` is enabled
15. **Quest** — Protected if `protectQuest` is enabled
16. **Collectible** — Protected if `protectCollectible` is enabled
17. **Heirloom** — Protected if `protectHeirloom` is enabled
18. **Attuneable** — Protected if `protectAttuneable` is enabled
19. **AugSlots** — Protected if `protectAugSlots` is enabled and item has augment slots
20. **HighValue** — Protected if `totalValue >= maxKeepValue`
21. **Tribute** — Protected if `tribute >= tributeKeepOverride`
22. **BelowSell** — Protected if value is below minimum sell threshold
23. **Sell** — Default: item will be sold

### Precedence Order (Loot Rules)

The canonical loot rule evaluation order is defined in `rules.lua:423-486` and mirrored in `RulesEngine.cpp:393-447`:

1. **RerollList** — Items on reroll list are skipped (Lua only)
2. **AugmentNeverLoot** — Augmentation-type items on augment skip list
3. **Epic** — Epic quest items always looted (before skip lists)
4. **SkipExact** — Skip exact list match
5. **SkipContains** — Skip contains keyword match
6. **SkipType** — Skip by item type
7. **TributeOverride** — Loot if tribute exceeds threshold
8. **AlwaysExact** — Always-loot exact list match
9. **AlwaysContains** — Always-loot contains keyword match
10. **AlwaysType** — Always-loot by type
11. **Value** — Loot if value exceeds minimum
12. **Clicky** — Loot if clicky spell and worn slots
13. **Quest** — Loot if quest item and `lootQuest` enabled
14. **Collectible** — Loot if collectible and `lootCollectible` enabled
15. **Heirloom** — Loot if heirloom and `lootHeirloom` enabled
16. **Attuneable** — Loot if attuneable and `lootAttuneable` enabled
17. **AugSlots** — Loot if has aug slots and `lootAugSlots` enabled
18. **NoMatch** — Default: item is not looted

Post-rules override (scan level only):
- **LoreDup** — If item is lore and already in inventory, override to skip regardless of rules result

### Conflict Resolution Manifest

#### C1: C++ RulesEngine lacks RerollList protection

**Description:** The C++ `WillItemBeSold()` and `ShouldItemBeLooted()` functions do not check reroll list membership. When the C++ plugin scan path is used (e.g. `scanSellItems` with plugin, `scanInventory` with plugin), the initial C++ evaluation may mark a reroll-listed item as `willSell=true`.

**Current Mitigation:** After every C++ plugin scan, Lua re-runs `computeAndAttachSellStatus()` which overwrites the C++ result with the Lua evaluation (which includes the RerollList check). See `scan.lua:127,171,375,517-519`.

**Resolution:** No code change required. The current mitigation is correct and consistent. The Lua re-evaluation is authoritative. The C++ evaluation is used only as an optimization for the scan pass itself (reading item data from game memory), not for the final sell decision.

**Risk:** If a future code path uses C++ results without the Lua re-evaluation, reroll-listed items could be sold. The mitigation is already defense-in-depth (Lua always re-evaluates).

**Status: RESOLVED — Existing mitigation is sufficient. No change needed.**

#### C2: `sellReason` "Epic" renamed to "EpicQuest" in 4 views

**Description:** The rules engine returns `"Epic"` as the sell reason, but all 4 views that display it (inventory.lua, sell.lua, bank.lua, loot_ui.lua) independently rename it to `"EpicQuest"` for display.

**Resolution:** This is a display concern, not a status conflict. The internal identifier should remain `"Epic"` (matching the rule name). The display rename should be centralized into a single function.

**Proposed Change:** Add a `formatSellReasonForDisplay(reason)` function to `ui_common.lua` or `columns.lua` that handles the rename and all other display transformations (NoDrop/NoTrade color, RerollList color). All 4 views call this instead of duplicating the logic.

**Status: ACTIONABLE — Implement in Phase 3.**

#### C3: Bank items missing sell status on initial display

**Description:** When bank cache is loaded from disk, items have no `willSell`/`sellReason` until the bank window opens and triggers `computeAndAttachSellStatus(bankCache)`. During the gap (multiple frames), the bank view falls back to per-row `getSellStatusForItem()` calls.

**Current Mitigation:** The fallback in `bank.lua:346` calls `getSellStatusForItem()` per row when `sellReason` is nil. This works but is expensive (computes sell status per-frame per-row).

**Resolution:** The current behavior is acceptable. The bank-just-opened handler in `main_loop.lua:890-891` immediately attaches sell status to bankCache on the first frame after bank open. The fallback only fires for the 1-2 frames before that. No change needed.

**Status: RESOLVED — Existing behavior is acceptable.**

#### C4: `inKeep`/`inJunk` dual representation in storage vs runtime

**Description:** Storage persists `inKeep`/`inJunk` (summary booleans). On load, `attachGranularFlags` only applies stored values to `inKeepExact`/`inJunkExact` when the item is still in the exact list. The summary is then recomputed from granulars. This means a stored `inKeep=true` from a contains-match is correctly not applied as an exact override.

**Resolution:** This is correct behavior. The storage format uses `inKeep`/`inJunk` as legacy names but they are actually exact-list overrides (see `storage.lua:124-125` which persists only when `inKeepExact` or `inJunkExact` is true). The `mergeFilterStatus` in `storage.lua:293-313` similarly only merges `inKeep`/`inJunk` — these are consumed by `refreshStoredInvByNameIfNeeded` which validates them against the current config before applying.

**Status: RESOLVED — Behavior is correct despite naming confusion.**

#### C5: Sell status stale after config change

**Description:** When the user changes sell config (e.g. adds/removes items from Keep/Junk lists via the Config view), the sell status on existing items may be stale until the next scan or config-change event fires.

**Current Mitigation:** `sell_status.lua:16-17` subscribes to `CONFIG_SELL_CHANGED` and `CONFIG_LOOT_CHANGED` events, which call `invalidateSellConfigCache()`. This causes the next `computeAndAttachSellStatus` call to reload config. The `perfCache.sellConfigPendingRefresh` flag (set by config_cache APIs) triggers a full re-evaluation in `main_loop.lua:927-936` (phase 8 deferred scans).

Additionally, `item_ops.lua:184-221` (`updateSellStatusForItemName`) immediately re-evaluates all items with the changed name when a user clicks Keep/Junk buttons.

**Resolution:** The current system handles this correctly via events + deferred refresh. No change needed.

**Status: RESOLVED — Event-driven refresh is sufficient.**

#### C6: `willLoot`/`lootReason` never refresh after loot config change

**Description:** Loot items scanned from a corpse have `willLoot`/`lootReason` computed once. If loot config changes while the corpse window is open, the displayed loot decisions are stale.

**Resolution:** This is acceptable behavior. Corpse windows are typically open for seconds, not long enough for config changes. The loot macro makes its own real-time decisions from the INI files, so the UI staleness does not affect actual loot behavior — it only affects the preview display.

**Status: RESOLVED — Acceptable behavior, no change needed.**

#### C7: `LoreDup` bypasses rules engine

**Description:** The `LoreDup` reason is assigned in `scan.lua:749` after `shouldItemBeLooted()` returns. It overrides the rules result when a lore item is already in inventory.

**Resolution:** This is intentionally outside the rules engine. It requires live game state (FindItem TLO) that the rules engine does not have access to. The override is correct: a lore item you already have should not be looted regardless of value or other rules. No change needed.

**Status: RESOLVED — Intentional design, correct behavior.**

#### C8: `source` field not set by `addItemToInventory`

**Description:** `item_ops.lua:addItemToInventory` (line 366) creates a new item row without setting the `source` field. This means items added via this path (e.g. after a move from bank to inventory) have `source = nil` instead of `"inv"`.

**Resolution:** This is a minor inconsistency. The `source` field is primarily used for context menu actions and augment operations, which check for `"bank"` explicitly and treat everything else as inventory. Setting `source = "inv"` would be cleaner.

**Proposed Change:** Add `source = "inv"` to the item row in `addItemToInventory`.

**Status: ACTIONABLE — Fix in Phase 3.**

#### C9: `statusText` sentinel `"—"` vs empty string

**Description:** Loot history entries and some view code use `"—"` (em dash) as a sentinel for "status not computed". Some code checks `statusText == ""`, others check for `"—"`. The normalization `if statusText == "" then statusText = "—"` runs in views, but loot feed and session merge set `"—"` directly.

**Resolution:** This is consistent in practice — the em dash is always the final display value for "no status". The empty string is an intermediate state that gets normalized before display. No functional issue, but the initial value should be standardized.

**Proposed Change:** No change needed. The pattern is: initial `"—"`, deferred sell-status lookup replaces it with the actual reason. Views normalize empty to `"—"` as a safety net. This is correct.

**Status: RESOLVED — No change needed.**

### Summary of Actionable Items for Phase 3

| ID | Change | Files | Risk |
|----|--------|-------|------|
| C2 | Centralize `sellReason` display formatting (Epic→EpicQuest, NoDrop/NoTrade color, RerollList color) into a shared function | `ui_common.lua`, `inventory.lua`, `sell.lua`, `bank.lua`, `loot_ui.lua` | Low |
| C8 | Add `source = "inv"` to `addItemToInventory` item row | `item_ops.lua` | Very low |

### Structural Assessment

After thorough analysis, the status system is **architecturally sound**. The core design — a rules engine that evaluates items against a prioritized list of sell/loot rules, with results cached on item rows and invalidated by config-change events — is correct and well-implemented. Key findings:

1. **Precedence is well-defined and consistent.** The sell rules follow a strict 23-step priority order, mirrored identically between Lua and C++. The loot rules follow an 18-step priority order with a scan-level LoreDup override.

2. **Status propagation is immediate in all important cases.** Scans always attach sell status before returning. Config changes trigger event-based cache invalidation and deferred re-evaluation. User-initiated changes (Keep/Junk buttons) immediately re-evaluate all matching items.

3. **The dual Lua/C++ evaluation is correctly handled.** C++ provides fast scanning, Lua provides authoritative sell/loot decisions with full context (reroll lists, stored overrides). The re-evaluation pattern is consistent across all scan paths.

4. **No status conflicts can cause data loss or incorrect automation.** The reroll list protection, which is the highest-priority rule, prevents items from being sold or looted incorrectly. The C++ gap is mitigated by Lua re-evaluation.

The two actionable items (C2, C8) are minor code quality improvements, not correctness fixes. **No architectural overhaul is warranted.**

**Uncommitted reroll changes assessment:** The generation-based cache invalidation (`_listGeneration` / `markListDirty()`) is well-integrated with the existing `onRerollListChangedFn` callback chain. `markListDirty()` invalidates internal caches (ID sets, dedup lists, location sets) while `onRerollListChangedFn` invalidates the sell config cache (so `RerollList` protection updates). During burst list parsing, `markListDirty()` fires per-line but `onRerollListChangedFn` fires once at parse-window close — this is correct (avoids redundant sell-cache rebuilds during burst). The sync failure tracking (`syncedCount`/`failedCount`/`failedItems`) is transient state with no persistence implications. No new conflicts introduced.

---

## Phase 4 — Verification Checklist

### V1: C2 — Centralized sellReason display formatting

| Attribute | Detail |
|-----------|--------|
| **Conflict Resolved** | C2: `sellReason` "Epic" renamed to "EpicQuest" in 4 views independently |
| **Before** | Each view (inventory.lua, sell.lua, bank.lua, loot_ui.lua) independently checked for `sellReason == "Epic"` and renamed to `"EpicQuest"`, applied NoDrop/NoTrade/RerollList coloring, and handled empty/nil fallback to `"—"`. 4 copies of identical ~10-line blocks. |
| **After** | Two shared functions in `ui_common.lua`: `formatSellStatus(reason, willSell, theme)` handles reason→display text rename and coloring; `resolveSellStatusDisplay(ctx, item)` additionally resolves the reason from item row state or `getSellStatusForItem` fallback. All 4 views replaced with single-line calls. Both functions wired through `ctx` in `app.lua`. |
| **Files Modified** | `lua/itemui/components/ui_common.lua` (added `formatSellStatus`, `resolveSellStatusDisplay`), `lua/itemui/app.lua` (wired into ctx), `lua/itemui/views/inventory.lua`, `lua/itemui/views/sell.lua`, `lua/itemui/views/bank.lua`, `lua/itemui/views/loot_ui.lua` (2 locations) |
| **Edge Cases for In-Game Verification** | 1. Inventory/Sell/Bank status column: verify Epic items show "EpicQuest" in muted color. 2. NoDrop/NoTrade items show red (Error) color. 3. RerollList items show RerollList theme color. 4. Normal Keep items show green (Success). 5. Normal Sell items show red (Error). 6. Items with no status computed yet show "—". 7. Loot history current tab and history tab: verify same coloring rules apply. |

### V2: C8 — `source = "inv"` on `addItemToInventory`

| Attribute | Detail |
|-----------|--------|
| **Conflict Resolved** | C8: Items added via `addItemToInventory` had no `source` field |
| **Before** | `item_ops.lua:addItemToInventory` created item rows without `source`. Items added through this path (e.g. after bank-to-inventory move bookkeeping) had `source = nil`. Context menu and augment operations that check `source == "bank"` would treat these correctly (nil != "bank"), but any code checking `source == "inv"` would fail. |
| **After** | Added `source = "inv"` to the row constructor in `addItemToInventory`. Items added through this path now have the correct source. |
| **Files Modified** | `lua/itemui/services/item_ops.lua` (line 369: added `source = "inv"` to row table) |
| **Edge Cases for In-Game Verification** | 1. Move item from bank to inventory, then right-click it — context menu should show inventory-appropriate options (Move to Bank, not "already in bank"). 2. After bank-to-inv move, augment operations should use `pack` pickup commands, not `bank` commands. |
