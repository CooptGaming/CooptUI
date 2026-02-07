# SellUI to ItemUI Migration Guide

**Date**: January 31, 2026  
**Status**: SellUI is deprecated - all features consolidated into ItemUI

---

## Overview

SellUI has been consolidated into **ItemUI** to provide a unified inventory management experience. This migration guide will help you transition from SellUI to ItemUI seamlessly.

---

## Quick Migration (2 minutes)

```bash
# 1. Stop SellUI (if running)
/lua stop sellui

# 2. Start ItemUI
/lua run itemui

# 3. (Optional) Enable merchant positioning
/itemui
# Click "Config" button → Check "Snap to Merchant (Sell View)"

# Done! Your config files work as-is.
```

---

## What's Different?

### UI Changes

| Aspect | SellUI | ItemUI |
|--------|--------|--------|
| **Window Management** | Auto-opens when merchant opens | Auto-switches to sell view when merchant opens |
| **Config Access** | Separate tabs (7 tabs) | Unified Config window (collapsing sections) |
| **Views** | Inventory + Config tabs | Dynamic view (gameplay/sell) + Bank panel |
| **Positioning** | Align to merchant window | Align to inventory (default) or merchant (opt-in) |

### Feature Additions

ItemUI includes **all SellUI features** plus:

- ✅ **Bank view** with live/historic modes
- ✅ **Loot view** when corpse window open
- ✅ **Character snapshots** for inventory/bank
- ✅ **Advanced filtering** (Phase 3 filter system)
- ✅ **Performance improvements** (Phase 1-2 caching)
- ✅ **Better architecture** (modular, extensible)

---

## Feature Mapping

### Core Features

| SellUI Feature | ItemUI Location | Notes |
|----------------|-----------------|-------|
| **Inventory Tab** | Main window (sell view) | Auto-switches when merchant opens |
| **Keep button** | Sell view action column | Same behavior, same config files |
| **Junk button** | Sell view action column | Same behavior, same config files |
| **Auto Sell button** | Top of sell view | Same functionality |
| **Search box** | Top of sell view | Enhanced with Phase 3 filters |
| **Show Only Sellable** | Top of sell view | Same checkbox |
| **Refresh button** | Top of sell view | Same functionality |

### Config Management

| SellUI Tab | ItemUI Location | Access Method |
|------------|-----------------|---------------|
| **Shared Valuable** | Config → Filters tab | Click "Config" → "Filters" tab |
| **Keep Lists** | Config → Filters tab | Select "Keep" from dropdown |
| **Always Sell** | Config → Filters tab | Select "Always Sell" from dropdown |
| **Protected Types** | Config → Filters tab | Select "Protected Types" from dropdown |
| **Flags** | Config → ItemUI tab | Click "Config" → "ItemUI" tab → "Sell protection" section |
| **Values** | Config → ItemUI tab | Click "Config" → "ItemUI" tab → "Value thresholds" section |

### Window Settings

| SellUI Setting | ItemUI Location | Notes |
|----------------|-----------------|-------|
| **Align to Merchant** | Config → ItemUI tab → "Snap to Merchant (Sell View)" | NEW: Opt-in feature |
| **Window Lock** | Main header → "Lock UI" | Controls window resizing |

---

## Configuration Files

### Good News: Zero Config Migration Required!

All your existing configuration files work unchanged:

```
Macros/sell_config/
├── sell_keep_exact.ini          ✅ Compatible
├── sell_keep_contains.ini       ✅ Compatible
├── sell_keep_types.ini          ✅ Compatible
├── sell_always_sell_exact.ini   ✅ Compatible
├── sell_always_sell_contains.ini✅ Compatible
├── sell_protected_types.ini     ✅ Compatible
├── sell_flags.ini               ✅ Compatible
└── sell_value.ini               ✅ Compatible

Macros/shared_config/
├── valuable_exact.ini           ✅ Compatible
├── valuable_contains.ini        ✅ Compatible
├── valuable_types.ini           ✅ Compatible
└── epic_classes.ini             ✅ Compatible
```

**No file conversion needed** - ItemUI reads from the same files as SellUI.

---

## Step-by-Step Migration

### Step 1: Stop SellUI

```bash
# If SellUI is currently running:
/lua stop sellui

# Verify it stopped:
/lua list
# (SellUI should not appear in the list)
```

### Step 2: Start ItemUI

```bash
# Start ItemUI:
/lua run itemui

# ItemUI will load your existing config files automatically
```

### Step 3: Configure Window Positioning (Optional)

If you liked SellUI's merchant window positioning:

1. Open ItemUI: `/itemui` (if not already open)
2. Click the **"Config"** button
3. Under **"Window behavior"** section:
   - Check ✅ **"Snap to Merchant (Sell View)"**
4. Close config window

Now ItemUI will position to the right of the merchant window (just like SellUI did).

### Step 4: Test Sell View

1. Open a merchant window (target vendor → right-click)
2. ItemUI should automatically switch to **sell view**
3. Verify:
   - Keep/Junk buttons appear
   - Auto Sell button at top
   - Items show correct Keep/Junk status
   - Search and filters work

### Step 5: Explore New Features

1. **Bank View**: Click "Bank" button (right side) to open bank panel
2. **Config Window**: Click "Config" to manage all settings in one place
3. **Filters Tab**: Click "Filters" in config for unified item management

---

## Common Workflows

### Adding Items to Keep List

**SellUI Method**:
- Click Keep button in Inventory tab
- OR go to Keep Lists tab → add manually

**ItemUI Method**:
- Click Keep button in sell view (same as SellUI)
- OR open Config → Filters tab → select "Keep - Exact" → add manually

### Adding Items to Junk List

**SellUI Method**:
- Click Junk button in Inventory tab
- OR go to Always Sell tab → add manually

**ItemUI Method**:
- Click Junk button in sell view (same as SellUI)
- OR open Config → Filters tab → select "Always Sell - Exact" → add manually

### Changing Flags or Values

**SellUI Method**:
- Go to Flags tab → toggle checkboxes
- Go to Values tab → edit thresholds

**ItemUI Method**:
- Open Config → ItemUI tab
- Scroll to "Sell protection" section → toggle flags
- Scroll to "Value thresholds" section → edit values

---

## Troubleshooting

### Issue: ItemUI doesn't open when I open merchant

**Solution**: ItemUI switches views instead of opening/closing. If ItemUI isn't visible:
- Type `/itemui` to show ItemUI
- It will automatically switch to sell view when merchant is open

### Issue: Keep/Junk buttons don't work

**Solution**: 
- Verify config files exist in `Macros/sell_config/`
- Try clicking "Refresh" button in ItemUI
- Check that items are being added to correct files (check console messages)

### Issue: Window positioning is different

**Solution**: Enable "Snap to Merchant" in config:
- `/itemui` → "Config" → Check "Snap to Merchant (Sell View)"

### Issue: Can't find config tabs

**Solution**: Config moved to unified window:
- Click "Config" button in main ItemUI window
- Use tabs to switch between ItemUI / Loot / Filters
- Use collapsing sections within each tab

### Issue: SellUI still starts automatically

**Solution**: Remove SellUI from autostart:
- Edit `Macros/AutoLogin_Username_CharName.mac` (or similar)
- Remove `/lua run sellui` line
- Add `/lua run itemui` instead

---

## Performance Improvements

ItemUI includes significant performance optimizations:

### Phase 1: Instant Open
- **Old**: SellUI scanned inventory on open (50-200ms)
- **New**: ItemUI shows last snapshot instantly (<50ms)

### Phase 2: Smart Caching
- **Old**: SellUI rescanned on every change
- **New**: ItemUI uses granular cache invalidation

### Phase 3: Advanced Filtering
- **Old**: SellUI basic text search
- **New**: ItemUI enhanced filter service with persistence

---

## Keyboard Shortcuts

| Action | SellUI | ItemUI |
|--------|--------|--------|
| Toggle window | `/sellui` | `/itemui` |
| Refresh inventory | Click "Refresh" | Click "Refresh" |
| Open config | Switch to config tab | Click "Config" button |
| Sell item | Click "Sell" | Click "Sell" (same) |
| Add to Keep | Click "Keep" | Click "Keep" (same) |
| Add to Junk | Click "Junk" | Click "Junk" (same) |

---

## Frequently Asked Questions

### Q: Do I need to convert my config files?

**A: No!** ItemUI uses the exact same config files as SellUI. No conversion needed.

### Q: Can I run SellUI and ItemUI at the same time?

**A: Not recommended.** They use the same config files, so changes in one won't reflect in the other until restart. Choose one (ItemUI recommended).

### Q: Will SellUI still work?

**A: Yes, but deprecated.** SellUI will show a deprecation warning on startup and will be removed in a future update.

### Q: What if I prefer SellUI's tabbed interface?

**A: Try ItemUI's Config window.** It uses collapsing sections which allow viewing multiple sections at once (more efficient than tabs).

### Q: Can I keep SellUI's window positioning?

**A: Yes!** Enable "Snap to Merchant (Sell View)" in ItemUI config.

### Q: What happens to my Keep/Junk lists?

**A: They work as-is.** ItemUI reads from the same INI files, so all your existing lists are preserved.

### Q: Will my sell macros still work?

**A: Yes!** Macros read from `sell_config/` directory, which ItemUI also uses. No changes needed.

---

## Getting Help

If you encounter issues during migration:

1. **Check config files exist**: `Macros/sell_config/` should have all INI files
2. **Verify ItemUI is running**: `/lua list` should show `itemui`
3. **Try refreshing**: Click "Refresh" button in ItemUI
4. **Review console messages**: ItemUI logs helpful diagnostic messages
5. **Test with fresh merchant**: Close and reopen merchant window

---

## Benefits of Migration

### Why Switch to ItemUI?

1. **Unified Experience**: One UI for inventory, bank, sell, and loot
2. **Better Performance**: Phase 1-3 optimizations make it faster
3. **More Features**: Bank snapshots, loot view, advanced filtering
4. **Easier Management**: Config window consolidates all settings
5. **Future-Ready**: ItemUI is actively developed (Phase 4-7 planned)
6. **Better UX**: Context-aware views reduce window clutter

---

## Next Steps

After migrating:

1. **Explore Bank View**: Click "Bank" button to see your bank items
2. **Try Filters Tab**: Open Config → Filters for unified item management
3. **Customize Layout**: Use `/itemui setup` to adjust window sizes
4. **Enable Features**: Try "Snap to Merchant", "Sync Bank Window", etc.

---

## Conclusion

Migrating from SellUI to ItemUI is quick and seamless:

✅ **Zero config migration** (files work as-is)  
✅ **Same core features** (Keep/Junk buttons, Auto Sell)  
✅ **Better performance** (Phase 1-3 optimizations)  
✅ **More features** (Bank, Loot, Snapshots)  
✅ **Future-ready** (Active development)

**Recommended Action**: Migrate to ItemUI today!

---

**Questions or Issues?** Check the main ItemUI README or SELLUI_GAP_ANALYSIS.md for detailed feature comparisons.
