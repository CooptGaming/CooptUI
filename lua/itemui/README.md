# Item UI – Unified Inventory / Bank / Sell

One window with a **dynamic inventory view** and an optional **Bank slide-out**:
- **Inventory** switches between a **gameplay view** (bag, slot, weight, flags, To Bank when bank open) and a **sell view** (Status, Keep/Junk, Value, etc.) when a merchant is open.
- **Bank** is a slide-out panel opened by the **Bank** button on the right; it shows live data when the bank window is open ("Connected") and saved historic data when it's closed ("Historic").

---

## ⚠️ Migrating from SellUI

**ItemUI now includes all SellUI features** in a unified interface. Your existing configuration files are fully compatible.

## ⚠️ LootUI Deprecation

LootUI is deprecated. Use ItemUI for all loot configuration and valuable lists.

### What Changed

- **Sell view** is now part of ItemUI (opens automatically when merchant window opens)
- **Config management** moved to ItemUI's unified Config window
- **Keep/Junk buttons** work the same way in ItemUI's sell view
- **New features** available: Bank view, Loot view, Snapshots, Advanced filtering

### Migration Steps

1. **Stop SellUI**: `/lua stop sellui` (if running)
2. **Start ItemUI**: `/lua run itemui`
3. **Optional**: Enable "Snap to Merchant" in ItemUI config for SellUI-like positioning
4. **Done!** All your config files (`sell_config/`) work as-is

### Feature Mapping

| SellUI Feature | ItemUI Equivalent |
|----------------|-------------------|
| Inventory tab | Sell view (auto-switches when merchant opens) |
| Keep/Junk buttons | Same buttons in sell view |
| Auto Sell button | Same button at top of sell view |
| Config tabs | Config window (click "Config" button) |
| Align to merchant | "Snap to Merchant" option in config |
| Search & filter | Enhanced filter system (Phase 3) |

### Why Consolidate?

- **Unified experience**: One UI for inventory, bank, sell, and loot
- **Better performance**: Shared caching and state management
- **More features**: Bank snapshots, loot evaluation, advanced filtering
- **Easier maintenance**: Single codebase with modular architecture
- **Future-ready**: Foundation for Phase 5-7 improvements

For detailed migration information, see [SELLUI_MIGRATION_GUIDE.md](docs/SELLUI_MIGRATION_GUIDE.md).

---

## Load and toggle

- **Load:** `/lua run itemui`
- **Toggle:** `/itemui` or `/inv` or `/inventoryui` (aliases)
- **Show:** `/itemui show`
- **Hide:** `/itemui hide`
- **Refresh:** `/itemui refresh`
- **Setup:** `/itemui setup`
- **Unload:** `/itemui exit` (or `quit` / `unload`)

## Inventory (main area)

- **When no merchant is open (gameplay view):**
  - Columns: Name, Bag, Slot, Value, Stack, Weight, Type, Flags.
  - When the bank window is open: Shift+click item to move to bank.
  - Search, Refresh, bank-open hint.

- **When a merchant is open (sell view):**
  - Same area becomes sell-focused: **Auto Sell** button, **Show only sellable** filter, Search.
  - Columns: Name, **Status** (Keep/Junk/Will Sell etc.), **Keep / Junk** buttons, Value, Stack, Type.
  - Per-row **Keep** / **Junk** use the same INI files as SellUI (`Macros/sell_config`, `Macros/shared_config`).
  - Closing the merchant reverts to the gameplay view.

## Bank (slide-out)

- Click the **Bank** button (right side of the header) to open/close the bank panel.
- **When the bank window is open ("Connected"):**
  - Live bank list, search, Refresh, shift+click to move to first free inventory slot, right-click inspect.
- **When the bank window is closed ("Historic"):**
  - Shows the last saved bank snapshot and "(last: mm/dd HH:MM)". No moves; useful for checking what was in the bank.

## Behavior

- **Align to context:** If enabled, the window snaps next to the inventory, bank, or merchant window (whichever is open, merchant > bank > inventory).
- **Cross-refresh:** Moving items between bank and inventory refreshes both lists (and updates the bank cache when connected).
- **Cursor:** "Clear cursor" strip and right-click-to-put-back in the main window.
- **Auto-open:** Opening the in-game inventory, bank, or merchant window can auto-show Item UI when it was closed.

## Relation to other UIs

- Replaces **inventoryui** and **bankui** for normal use.
- Sell view shares keep/junk and sell config with **SellUI** (deprecated - migrate to ItemUI).
- **Config** has three tabs: ItemUI (window, layout, sell flags/values), Loot (flags, values, sorting), and **Filters** (unified add form for all sell and loot lists).
- **Filters tab** — One form to add items to any list: dropdown (target list) + type (full name/keyword/type) + input + Add + From cursor. Click X on a list entry to remove; the form fills for edit.
- **Loot view**: When the corpse loot window (LootWnd) is open, the main area shows live corpse items with Will Loot / Will Skip status (same filters as loot.mac). Rarely visible during macro looting.

## Testing

- **Rules unit tests:** `/lua run itemui/test_rules`
- Tests sell and loot rule evaluation (keep/junk/protected, skip/always-loot) using mock caches.
- Requires MQ2Lua and the IntegrationTests framework (`lua/IntegrationTests/mqTest.lua`).

## Files

- `lua/itemui/init.lua` – single entry; run with `/lua run itemui`.
- Canonical source is `lua/itemui/` (older `ItemUI/` or `itemui_package/` copies are deprecated).
