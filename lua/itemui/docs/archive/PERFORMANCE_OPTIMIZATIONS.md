# ItemUI Performance Optimizations

## Summary of Changes (Latest)

### 1. **Debounced Layout Saves** (High Impact)
- **Before:** Every sort click, tab switch, checkbox change triggered immediate file I/O (read + write layout + saveColumnVisibility = 2+ file ops).
- **After:** `scheduleLayoutSave()` debounces rapid changes (600ms). Rapid clicks (e.g. multiple sort columns) trigger one save instead of many.
- **Exception:** Explicit user saves (Setup Save, lock toggle, view resize, bank position) still save immediately.
- **On exit:** `flushLayoutSave()` persists any pending changes before unload.

### 2. **Main Loop Delay** (Medium Impact)
- **Before:** 50ms when UI visible (~20 FPS).
- **After:** 33ms when UI visible (~30 FPS) for snappier feel.
- **Hidden:** Still 100ms when UI hidden to reduce CPU when not in use.

### 3. **Existing Optimizations** (Already in place)
- **Layout parse:** Single-pass `parseLayoutFileFull()` reads file once.
- **Layout cache:** Skip re-parse when `perfCache.layoutNeedsReload` is false.
- **Sort cache:** perfCache.inv/sell/bank avoid re-sorting when key/dir/filter/data unchanged.
- **Spell cache:** getSpellName/getSpellDescription use LRU cache (128 entries).

## Expected Results

- **UI responsiveness:** Smoother (30 FPS vs 20 FPS).
- **File I/O:** Fewer layout writes; rapid changes are batched.
- **Sort/tab clicks:** No blocking file I/O; UI stays responsive.

## Possible Future Optimizations

1. **Chunked scans:** Run inventory scan in chunks across frames (e.g. 2 bags per frame) to avoid blocking on open.
2. **Lazy column data:** Only fetch item properties for visible columns.
3. **Consolidate layout + column visibility save:** Single read/write pass instead of two.
4. **Pre-warm spell cache:** Populate spell name cache during scan instead of on first render.
