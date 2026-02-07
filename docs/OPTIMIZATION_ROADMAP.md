# Code Optimization Roadmap

Prioritized list of optimization opportunities for the EverQuest UI overhaul.

## Completed ✓

### SellUI
- **recalculateSellStatus()** – When flags or values change, recalculate willSell in-memory instead of full scanInventory (avoids 80+ TLO calls per item)
- **List edits** – addToList/removeFromList use recalculateSellStatus when on inventory tab (no MQ reads needed)
- **Cached config in willItemBeSold** – Uses in-memory flags/values/lists; no INI reads per item
- **Main loop** – 33ms when visible, 100ms when hidden

### ItemUI
- **Pre-warm spell cache** – buildItemFromMQ calls getSpellName() for clicky/proc/focus/worn/spell during scan
- **mq.ItemUtils** – Shared formatValue/formatWeight; no duplication
- **Debounced layout saves** – 600ms debounce for rapid sort/tab changes
- **Sort cache** – Re-sort only when key/dir/filter/data changes
- **ImGuiListClipper** – Virtualized rendering for large lists

### BankUI
- **mq.ItemUtils** – Shared formatValue/formatWeight
- **Transfer stamp throttle** – Check cross-UI refresh file every 500ms instead of every loop
- **Main loop** – 33ms when visible, 100ms when hidden

## Additional Optimizations (2025 - Medium/Low)

### Implemented
- **Consolidate layout + column visibility save** – saveLayoutToFileImmediate now does Layout + ColumnVisibility in single read/write (was 2 reads, 2 writes).
- **TimerReady cache TTL** – Extended from 1s to 1.5s; reduces TLO calls ~33% for Clicky cooldown display.
- **formatValue/formatWeight cache** – mq.ItemUtils caches last 64/32 results; reduces allocations when same values formatted repeatedly in tables.

### Deferred
- **Lazy column data** – Deferred; complex with dynamic columns and multiple views; limited benefit since scan is one-time per open.
- **Chunked inventory scan** – Not implemented per user preference.

## Next Steps (Future)

### High Impact
1. **Chunked inventory scan** – (Not planned) Run scan in chunks across frames. Tradeoff: brief "loading" state vs. blocking open.

### Lower Impact
2. **Lazy column data** – Only fetch item properties for visible columns. Complex; deferred.

## Performance Checklist

- [x] No INI reads per item (SellUI willItemBeSold)
- [x] No full scan when only config changed (recalculateSellStatus)
- [x] Spell cache pre-warmed during scan
- [x] Shared utilities (mq.ItemUtils)
- [x] Main loop timing (33ms visible, 100ms hidden)
- [x] Debounced file writes (layout saves)
- [x] Sort cache (avoid re-sort when unchanged)
- [x] Throttled file polling (BankUI transfer stamp)
- [ ] Chunked scan (future)
- [ ] Single-pass layout save (future)
