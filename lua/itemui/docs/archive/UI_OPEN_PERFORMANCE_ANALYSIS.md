# ItemUI - UI Open Performance Analysis

## Executive Summary

This document analyzes performance bottlenecks when ItemUI and related UIs open, and documents optimizations applied.

---

## 1. UI Open Triggers & Flow

### Main ItemUI Open Paths
| Trigger | Path | Key Operations |
|---------|------|----------------|
| `/inv` or `/itemui` toggle | handleCommand → shouldDraw=true | loadLayoutConfig, maybeScanInventory, maybeScanBank, maybeScanSellItems |
| Press "I" (inventory key) | Main loop detects invOpen | Auto-show: loadLayoutConfig, maybeScanInventory (or deferred), maybeScanBank, maybeScanSellItems |
| Bank window opens | Main loop detects bankOpen | Auto-show or bank panel: loadLayoutConfig, maybeScanBank |
| Merchant opens | Main loop detects merchOpen | Switch to Sell view: maybeScanSellItems |

### Bank Window Open
| Trigger | Path |
|---------|------|
| Bank button click | bankWindowShouldDraw=true, bankWindowOpen=true |
| Bank window open (EQ) | Auto-show ItemUI if hidden |

### Config Window Open
| Trigger | Path |
|---------|------|
| Settings button | configWindowOpen=true, configNeedsLoad=true |
| Next frame | loadConfigCache() - reads ~25+ INI keys across sell/loot config |

---

## 2. Identified Bottlenecks

### 2.1 Layout File I/O (HIGH IMPACT)
**Problem:** `loadLayoutConfig()` reads `itemui_layout.ini` **3 times** on every UI open:
1. `loadDefaults()` - full file read, parses [Defaults], [ColumnVisibilityDefaults]
2. `parseLayoutFile()` - full file read, parses [Layout]
3. `loadColumnVisibility()` - full file read, parses [ColumnVisibility]

**Impact:** 3x disk I/O and 3x file parse on every open. On slow disks or network drives, adds 50-200ms+.

**Optimization:** Single-pass parse - read file once, extract all sections in one pass.

### 2.2 Inventory Scan (MEDIUM - Already Partially Addressed)
**Problem:** `scanInventory()` iterates all bags (1-10), each slot, building full item data via `buildItemFromMQ()` which does many mq.TLO calls per item.

**Impact:** ~50-200ms for full inventory depending on item count.

**Existing optimization:** Deferred scan when opening via "I" key - show cached data first, scan on next frame.

### 2.3 Sort Every Frame (MEDIUM IMPACT)
**Problem:** Inventory, Sell, and Bank views call `table.sort(filtered, ...)` every render frame, even when sort key, direction, and data haven't changed.

**Impact:** O(n log n) per frame. With 80 items, ~500+ comparisons per frame. At 60fps that's 30k comparisons/sec when idle.

**Optimization:** Cache sorted list; only re-sort when sort key, direction, filter, or item list changes.

### 2.4 Sell Config Cache (LOW - Lazy Load)
**Problem:** `loadSellConfigCache()` reads 10+ INI files when first needed (scanSellItems, willItemBeSold, etc.).

**Impact:** Only when merchant open or sell view first used. Cached after first load.

**Status:** Acceptable - lazy load is correct. Could add file-change detection to invalidate.

### 2.5 Config Window Load (LOW - On Demand)
**Problem:** `loadConfigCache()` reads ~25 INI keys when config window opens.

**Impact:** Only when user opens config. One-time per config open.

**Status:** Acceptable.

### 2.6 Main Loop Delay
**Current:** `mq.delay(33)` when UI visible (~30 FPS), `mq.delay(100)` when hidden.

**Note:** 33ms when visible for snappier feel; 100ms when hidden to reduce CPU.

### 2.7 Debounced Layout Saves (HIGH IMPACT)
**Problem:** Every sort click, tab switch, checkbox change triggered immediate file I/O (read + write layout + saveColumnVisibility = 2+ file ops).

**Optimization:** `scheduleLayoutSave()` debounces rapid changes (600ms). One save instead of many when user clicks multiple columns or tabs quickly.

---

## 3. Optimization Checklist

- [x] Consolidate layout file parsing (single read) — **DONE**: `parseLayoutFileFull()` reads once
- [x] Cache sorted lists (re-sort only on change) — **DONE**: perfCache.inv/sell/bank; invalidate on data change
- [x] Layout config caching (skip reload if file unchanged) — **DONE**: perfCache.layoutCached + layoutNeedsReload
- [x] Main loop delay (33ms when UI visible) — **DONE**: mq.delay(shouldDraw and 33 or 100)
- [x] Debounced layout saves — **DONE**: scheduleLayoutSave() for sort/tab/checkbox; immediate for setup/lock

---

## 4. Implementation Notes

### Single-Pass Layout Parse
Create `parseLayoutFileFull()` that:
1. Opens file once
2. Iterates lines, tracks current section
3. Returns `{ defaults = {...}, layout = {...}, columnVisibility = {...}, columnVisibilityDefaults = {...} }`
4. `loadLayoutConfig()` uses this single result for all loading

### Sort Cache
For each view (Inventory, Sell, Bank):
- `sortCache = { key, direction, filterHash, listHash, sortedList }`
- Before sort: if key/dir/filter/list unchanged, use cached sortedList
- On change: recompute and update cache
