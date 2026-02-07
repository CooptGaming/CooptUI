# Quick Reference: New Features (2026-01-31)

## Loot Macro - Lore Item Caching

### What It Does
Dramatically speeds up lore item duplicate checking by caching previously seen items.

### How It Works
- First time seeing a lore item: Normal speed (scans inventory)
- Subsequent times: ~99% faster (checks cache instead)
- Cache automatically resets when you restart the macro

### User Impact
- **No configuration needed** - Works automatically
- **No behavior changes** - Still prevents lore duplicates correctly
- **Faster looting** - Especially noticeable when looting many corpses
- **Most helpful when**: Farming areas with common lore drops (quest items, collectibles)

### Performance Example
Before: Looting 100 corpses with same lore item = 100 full inventory scans
After: Looting 100 corpses with same lore item = 1 inventory scan + 99 instant cache checks

---

## Sell Macro - Timeout Protection

### What It Does
Prevents the macro from hanging indefinitely if the merchant window becomes unresponsive.

### How It Works
- Sets a maximum time limit for each item sell operation
- Default: 60 seconds per item (configurable)
- If timeout expires: Aborts gracefully, logs failure, continues to next item

### User Impact
- **Prevents freezes** - Macro won't hang for minutes if merchant UI is broken
- **Configurable** - Adjust timeout in `sell_value.ini` if needed
- **Better feedback** - Shows `[TIMEOUT]` message vs `[FAILED]` for different issues

### Configuration
Edit `Macros/sell_config/sell_value.ini`:

```ini
; Overall timeout in seconds for any single sell operation
; Default 60 = abort after 60 seconds regardless of retry count
sellMaxTimeoutSeconds=60
```

**Recommendations:**
- **High latency/lag**: Increase to 90-120 seconds
- **Local server/low lag**: Can decrease to 30-45 seconds
- **Default (60s)**: Works for most situations

### When Does Timeout Trigger?
- **Normal selling**: Never (completes in seconds)
- **Slight lag**: Existing retry system handles it
- **Severe lag/freeze**: Timeout catches it and moves on
- **UI crash**: Prevents indefinite hang

---

## Files Modified

### Loot Macro
- `Macros/loot.mac` - Core macro with cache implementation
- No config changes needed

### Sell Macro  
- `Macros/sell.mac` - Core macro with timeout protection
- `Macros/sell_config/sell_value.ini` - New timeout setting
- `ItemUI/Macros/sell_config/sell_value.ini` - Mirror update

---

## Troubleshooting

### Loot Macro

**Q: I'm still seeing "Skipping LORE DUPLICATE" for items I don't have**  
A: This shouldn't happen. The cache only stores items you actually own. If it does, restart the macro to clear the cache.

**Q: Does the cache persist across sessions?**  
A: No, it's intentionally session-based. Restarting the macro clears the cache.

**Q: Can I see cache statistics?**  
A: Not currently, but watch for messages ending in "(cached)" vs "(already owned - ID: XXX, cached)"

### Sell Macro

**Q: I'm seeing `[TIMEOUT]` messages when selling**  
A: This means the merchant window isn't responding within 60 seconds. Options:
   1. Check your connection (high latency?)
   2. Check merchant window is properly open
   3. Increase `sellMaxTimeoutSeconds` in sell_value.ini
   4. Report to developer if persistent

**Q: How do I change the timeout?**  
A: Edit `Macros/sell_config/sell_value.ini` and adjust `sellMaxTimeoutSeconds` value

**Q: Will this affect my normal selling?**  
A: No. The timeout is generous (60 seconds). Normal operations complete in 3-6 seconds.

**Q: What happens to timed-out items?**  
A: They're logged in the failed items file and remain in your inventory. You can manually sell or retry later.

---

## Testing Checklist

After updating, verify:

### Loot Macro
- [ ] Loot 10+ corpses with lore items
- [ ] Check for "(cached)" messages after first encounter
- [ ] Verify no lore duplicates are looted
- [ ] Notice improved responsiveness (optional)

### Sell Macro
- [ ] Sell 10+ items normally
- [ ] Verify no timeout messages
- [ ] Items sell at normal speed
- [ ] Check sell log for completions

### Optional: Timeout Test
- [ ] Temporarily set `sellMaxTimeoutSeconds=5` in sell_value.ini
- [ ] Try to sell an item (might timeout)
- [ ] Verify `[TIMEOUT]` message appears after ~5 seconds
- [ ] Reset to 60 when done testing

---

## Need Help?

If you experience issues:

1. **Check the detailed docs**: `docs/FIXES_2026_01_31_SECTIONS_2.2_AND_2.3.md`
2. **Review config files**: Make sure settings are correct
3. **Test with defaults**: Reset any custom timeout values
4. **Check logs**: Failed items are logged for review

**These changes are backward compatible** - your existing configurations and behavior remain unchanged except for the performance improvements and timeout protection.
