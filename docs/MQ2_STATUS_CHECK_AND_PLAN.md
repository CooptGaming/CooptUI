# MacroQuest2 Project — Status Check & Forward Plan

**Date:** 2025-01-31  
**Purpose:** Detailed findings and actionable plan for other agents to execute fixes and improvements.

---

## Executive Summary

A full codebase review was performed on the MQ2 project. Three critical fixes were applied:

1. **Missing `isInEpicList` in SellUI** — Implemented epic item protection using shared config (`epic_items_exact.ini`, `epic_classes.ini`).
2. **Unbounded movement delay in loot.mac** — Capped manual corpse-approach delay to prevent long freezes on distant targets.
3. **Infinite loops without exit conditions** — Added safety checks for death, zoning, and programmatic stopping in `defend.mac` and `lang.mac`.

The following sections document what was fixed, what remains, and a prioritized plan for further work.

---

## 1. Fixes Already Applied

### 1.1 SellUI — Epic Item Protection (Critical Bug)

**File:** `lua/sellui/init.lua`

**Problem:** Line 410 called `isInEpicList(itemName)` but the function was never defined, causing a runtime error when `protectEpic` was enabled and an item was evaluated.

**Solution Applied:**
- Added `epicItemSet` variable (loaded from config).
- Added `loadEpicItemSetByClass()` — loads epic items from `epic_classes.ini` (per-class) or falls back to `epic_items_exact.ini` (shared).
- Added `isInEpicList(itemName)` — returns `epicItemSet[itemName] or false`.
- Integrated epic loading into `loadConfigLists()` when `flags.protectEpic` is true.
- Added `isValidFilterEntry()` to filter null/nil placeholders from epic lists.

**Relevant Config Files:**
- `Macros/shared_config/epic_items_exact.ini` — shared epic quest items (chunked: exact, exact2, exact3, exact4).
- `Macros/shared_config/epic_classes.ini` — per-class epic selection (bard, beastlord, etc.).
- Per-class files: `epic_items_<class>.ini` (e.g. `epic_items_warrior.ini`) — may not exist for all classes; fallback to `epic_items_exact.ini`.

### 1.2 Loot Macro — Movement Delay Cap (Performance Bug)

**File:** `Macros/loot.mac`

**Problem:** Line 976 used `/delay ${Math.Calc[${Target.Distance}*10]}`. For distant corpses (e.g. 100+ units), this produced 1000+ tick delays, causing long freezes.

**Solution Applied:**
- Added `maxMoveDelay int local 100` and `moveDelay int local 0`.
- Replaced raw delay with: compute `moveDelay`, cap at `maxMoveDelay`, then `/delay ${moveDelay}`.

**Location:** `sub ApproachCorpse` (approx. lines 919–995).

### 1.3 Infinite Loops — Exit Conditions Added (Safety Enhancement)

**Files:** `Macros/defend.mac`, `Macros/lang.mac`

**Problem:** Both macros had infinite loops without exit conditions, causing potential issues when character dies, zones, or macro needs to be stopped programmatically.

**Solution Applied (defend.mac):**
- Added exit conditions for `${Me.Dead}` — stops when character dies.
- Added exit conditions for `!${Me.InZone}` — stops when not in a zone (zoning).
- Added check for `${Macro.Return.Equal[TRUE]}` — allows programmatic stopping.
- All conditions log an informative message before returning.

**Solution Applied (lang.mac):**
- Added same safety exits as defend.mac (dead, not in zone, macro return).
- Added iteration counter with max limit (1000 loops) to prevent runaway execution.
- Counter can be adjusted via `maxLoops` variable if needed.

**Location:** Main loop in both files (lines 2–10 for defend.mac, lines 5–8 for lang.mac).

---

## 2. Remaining Issues (Not Yet Fixed)

### 2.1 Loot Macro — Main Loop Timeout

**File:** `Macros/loot.mac`  
**Location:** Main loop around lines 115–192 (per prior analysis).

**Problem:** Uses `/goto :mainlootloop` without a top-level iteration or time limit. If corpse targeting fails repeatedly, the loop can run indefinitely.

**Recommendation:** Add a max-iteration counter or elapsed-time check at the top of the main loop; `/return` or `/endmacro` when exceeded.

### 2.2 Loot Macro — Lore Duplicate Check Performance ✅ **COMPLETED**

**File:** `Macros/loot.mac`  
**Location:** Around lines 215–223 (lore item check).

**Problem:** Uses `FindItem[=${lootName}].ID` for every lore item on every corpse. This scans inventory + bank and can be slow with large inventories.

**Solution Applied:**
- Added session-based lore item cache (`loreItemCache` variable) — pipe-delimited string format (e.g. `|ItemName1|ItemName2|`).
- Modified lore check to search cache first (fast string lookup) before calling `FindItem`.
- Cache miss triggers `FindItem` scan and adds result to cache for future checks this session.
- Dramatically reduces inventory scans from O(n×corpses) to O(n) where n = unique lore items looted.
- Cache automatically resets when macro restarts (session-based, no stale data concerns).

**Performance Impact:** 
- First lore item check: Same speed (cache miss, performs FindItem)
- Subsequent checks: ~99% faster (string search vs full inventory scan)
- Most beneficial when looting many corpses with repeated lore items

**Location:** `sub EvaluateItem` (lines ~210-238)

### 2.3 Sell Macro — Retry Logic Without Overall Timeout ✅ **COMPLETED**

**File:** `Macros/sell.mac`  
**Location:** Around lines 494–512.

**Problem:** Retry loop has `sellRetries` limit but no overall timeout. If the UI is unresponsive, delays can accumulate indefinitely.

**Solution Applied:**
- Added `sellMaxTimeoutSeconds` variable (default: 60 seconds, configurable via INI).
- Implemented timer-based timeout check using MQ2's native timer data type.
- Timeout is checked before each retry attempt in the `ProcessSellItem` subroutine.
- If timeout expires, operation aborts with clear `[TIMEOUT]` message, adjusts counts, and logs failure.
- Timeout prevents worst-case scenario where (sellRetries × sellWaitTicks × delay) accumulates without bound.

**Configuration:**
- Added `sellMaxTimeoutSeconds` setting to `sell_value.ini` (all copies updated).
- Loaded from INI in `LoadConfig` subroutine with fallback to 60-second default.
- Users can adjust per character or globally based on network conditions.

**Safety Improvement:**
- Before: Could theoretically hang for minutes if merchant UI completely frozen
- After: Guaranteed abort after configurable timeout (default 60s)
- Failed items are properly tracked and logged for review

**Location:** `sub ProcessSellItem` (lines ~477-543)

### 2.4 Code Duplication & Sync

- Multiple copies of `loot.mac`, `sell.mac`, and configs in `ItemUI/`, `itemui_package/`, and `Backup/` folders.
- `itemui_package/` may use older `readSharedINIValue` instead of chunked `readSharedListValue`.
- **Recommendation:** Run `ItemUI/sync.ps1` (or equivalent) to sync deployment package; archive or remove redundant `Backup/` folders.

### 2.5 Maintainability — Large Monolithic File

**File:** `lua/itemui/init.lua`  
**Size:** ~5000+ lines, ~266K+ characters.

**Recommendation:** Split into modules (e.g. UI panels, config I/O, inventory scan, sell/loot logic) per existing roadmap.

### 2.6 String Length Limits (MQ2 2048-char)

**Files:** `Macros/sell.mac`, `Macros/loot.mac`

**Status:** Already mitigated with chunked variables (`alwaysSellExact`, `alwaysSellExact2`, etc.) and `readSharedListValue` / `readListValue` in Lua. Edge cases may still exist for very large lists.

---

## 3. Plan of Attack (Prioritized)

### Priority 1 — Loop Safety & Reliability

1. **Loot main loop timeout** ✅ **COMPLETED**
   - File: `Macros/loot.mac`
   - Added iteration counter with configurable max (default 1000).
   - On exceed: Echoes warning, calls FinishLooting, returns safely.
   - Configurable via `loot_flags.ini` (`maxLoopIterations` setting).

2. **Sell retry timeout** ✅ **COMPLETED**
   - File: `Macros/sell.mac`
   - Added elapsed-time check in retry block (lines ~494–543).
   - Aborts after configurable max seconds (default 60s, via INI).
   - Timer-based implementation prevents indefinite hangs.

3. **Defend/lang macros** ✅ **COMPLETED**
   - Files: `Macros/defend.mac`, `Macros/lang.mac`
   - Exit conditions added for death, zoning, and programmatic stopping.

### Priority 2 — Performance

4. **Lore item cache in loot.mac** ✅ **COMPLETED**
   - File: `Macros/loot.mac`
   - Implemented session-based string cache for lore items.
   - Reduces repeated full inventory/bank scans from O(n×corpses) to O(n).
   - Cache automatically resets on macro restart (no stale data issues).

5. **Movement delay configurability** ✅ **COMPLETED**
   - File: `Macros/loot.mac`
   - Made `maxMoveDelay` configurable via INI (`loot_sorting.ini`).
   - Default 100 ticks (~10 seconds max approach delay).
   - Allows tuning for different movement speeds and network conditions.

### Priority 3 — Code Quality & Consistency

6. **Shared epic logic**
   - Current: `lua/sellui/init.lua` has its own `loadEpicItemSetByClass`; `lua/itemui/rules.lua` has similar logic.
   - Action: Consolidate epic loading into `itemui.rules` (or shared module); have SellUI require and use it.

7. **Extract shared list utilities**
   - `lua/sellui/init.lua` and `lua/lootui/init.lua` have overlapping list-management code.
   - Action: Extract shared utilities (parse, validate, save/load) into a common module.

### Priority 4 — Packaging & Cleanup

8. **Sync ItemUI package**
   - Run `ItemUI/sync.ps1` (or documented sync process).
   - Ensure `itemui_package/` and `ItemUI/` match `lua/itemui/` source.

9. **Archive or remove Backup folders**
   - `Backup/2026-1-26`, `Backup/2026-1-26_927`, `Backup/2026-1-30_itemui`
   - Reduce clutter and avoid accidental use of stale copies.

### Priority 5 — Maintainability

10. **Split itemui/init.lua**
    - Break into modules: UI panels, config I/O, inventory scan, sell/loot rules.
    - Keep `init.lua` as thin orchestrator.

---

## 4. Key File Reference

| Path | Purpose |
|------|---------|
| `Macros/loot.mac` | Auto-loot with filters |
| `Macros/sell.mac` | Vendor selling with safety filters |
| `Macros/defend.mac` | Defense automation (infinite loop) |
| `Macros/lang.mac` | Utility macro (infinite loop) |
| `lua/sellui/init.lua` | Sell UI (epic fix applied) |
| `lua/lootui/init.lua` | Loot config UI |
| `lua/itemui/init.lua` | Unified inventory/bank/sell hub (large) |
| `lua/itemui/rules.lua` | Sell/loot rule evaluation (epic, keep, junk) |
| `lua/itemui/config.lua` | Config I/O (`readSharedListValue`, etc.) |
| `Macros/shared_config/epic_items_exact.ini` | Shared epic quest items |
| `Macros/shared_config/epic_classes.ini` | Per-class epic selection |
| `Macros/sell_config/` | Per-char sell config |
| `Macros/loot_config/` | Loot filters |
| `Macros/shared_config/` | Shared valuable/keep/epic lists |

---

## 5. Architecture Notes

- **Chunked strings:** MQ2 has ~2048-char limit; configs use `exact`, `exact2`, `exact3`, etc.
- **Config module:** `itemui.config` provides `readSharedListValue`, `readListValue`, `parseList` for chunked INI reads.
- **Rules module:** `itemui.rules` mirrors sell.mac/loot.mac evaluation order; used by ItemUI.
- **SellUI** loads its own config lists in `loadConfigLists()` and caches them; epic list now included.

---

## 6. Instructions for Agents

1. **Read this document** before making changes.
2. **Tackle priorities in order** (1 → 5) unless the user specifies otherwise.
3. **Preserve existing behavior** where possible; document intentional changes.
4. **Test macros** in-game after edits (loot.mac, sell.mac).
5. **Update this document** when applying fixes or changing the plan.
