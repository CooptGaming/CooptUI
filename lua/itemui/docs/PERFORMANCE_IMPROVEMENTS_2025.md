# ItemUI Performance Improvements

## Changes Implemented

### 1. Debounced Layout Saves (High Impact)
**Problem:** Every sort click, tab switch, or checkbox change triggered immediate file I/O (read layout, write layout, read/write column visibility). Rapid interactions caused noticeable lag.

**Solution:** `scheduleLayoutSave()` debounces layout saves by 600ms. Rapid changes (e.g. clicking multiple sort columns) are batched into a single file write. Explicit user actions (Setup Save, lock toggle, view resize) still save immediately.

**Result:** Sort clicks and tab switches no longer block; UI stays responsive during rapid interaction.

### 2. Faster Main Loop (Medium Impact)
**Problem:** 50ms delay when UI visible (~20 FPS) felt sluggish.

**Solution:** Reduced to 33ms when UI visible (~30 FPS). Hidden state still uses 100ms to reduce CPU when not in use.

**Result:** Smoother, snappier feel when the UI is open.

### 3. Exit Flush
**Solution:** `flushLayoutSave()` runs before unload to persist any pending debounced changes.

---

## Existing Optimizations (Already in Place)

- **Layout parse:** Single-pass file read (`parseLayoutFileFull()`)
- **Layout cache:** Skip re-parse when config unchanged
- **Sort cache:** Re-sort only when key/dir/filter/data changes
- **Spell cache:** LRU cache for spell names/descriptions (Clicky column)
- **ImGuiListClipper:** Virtualized rendering for large lists

---

## Additional Optimizations (2025)

### Implemented
- **Pre-warm spell cache during scan:** buildItemFromMQ now calls getSpellName() for clicky/proc/focus/worn/spell IDs during scan, so first render doesn't need TLO calls.
- **Shared mq.ItemUtils:** formatValue/formatWeight moved to mq.ItemUtils; ItemUI, SellUI, BankUI use shared module.
- **SellUI recalculateSellStatus:** When flags or values change, recalculate willSell in-memory instead of full scanInventory (avoids 80+ TLO calls per item).
- **SellUI list edits:** addToList/removeFromList use recalculateSellStatus instead of scanInventory when on inventory tab.
- **BankUI transfer stamp throttle:** Check cross-UI refresh file every 500ms instead of every loop iteration.
- **Consolidate layout + column visibility save:** saveLayoutToFileImmediate now does Layout + ColumnVisibility in single read/write (was 2 reads, 2 writes).
- **TimerReady cache TTL:** Extended from 1s to 1.5s; reduces TLO calls ~33% for Clicky cooldown display.
- **formatValue/formatWeight cache:** mq.ItemUtils caches last 64/32 results; reduces allocations when same values formatted repeatedly in tables.

## Possible Future Improvements

### Deferred
- **Lazy column data:** Only fetch item properties for visible columns. Complex with dynamic columns; limited benefit.
- **Chunked inventory scan:** Not implemented per user preference.

---

## Summary

The main sources of sluggishness were:
1. **File I/O on every interaction** — Fixed with debouncing
2. **Slow main loop** — Fixed with 33ms delay
3. **Scan blocking on open** — Kept immediate (user preferred no shuffle); chunked scan could help in future
