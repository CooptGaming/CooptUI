# Sell Status Cache: Design and Implementation Plan

## Goal

Move “should this item be sold?” from the sell macro into ItemUI:

1. **ItemUI (Lua)** computes sell status once using existing rules (epic, keep, junk, value, etc.) and stores the result in the item cache.
2. **Sell macro** only sells items that are **flagged in the cache** as allowed to sell. It no longer duplicates keep/epic/value logic.

Benefits:

- **Single source of truth:** Epic, keep, junk, and value rules live only in ItemUI (rules.lua). No more macro/epic mismatch.
- **Consistency:** What ItemUI shows as “Sell” is exactly what the macro will sell.
- **Simpler macro:** No INI keep lists, epic lists, or EvaluateItem logic in the macro—just “is this item in the sell list?”
- **Epic items:** Never sold (excluded from sell list) and **always looted** (same epic list used for both; see below).

---

## Epic items: never sell, always loot

We want **epic items** to be:

1. **Never sold** – they must never appear in the sell list or be sold by the sell macro.
2. **Always looted** – they must always be picked up when they drop, regardless of value/skip lists.

### How this is ensured

**Never sold**

- In ItemUI, `willItemBeSold()` returns `false, "Epic"` for any item whose name is in the epic list (rules.lua, `epicItemSet` from `epic_items_exact.ini` / `epic_classes.ini`).
- When we compute and store sell status for the cache, epic items therefore get `willSell = false` and are **never** written to `sell_cache.ini`.
- The sell macro only sells items in that INI, so epic items are never sold.

**Always looted**

- **ItemUI (rules.lua):** `shouldItemBeLooted()` returns `true, "Epic"` for any item in `epicItemSet` when `alwaysLootEpic` is true (same epic list as sell).
- **Loot macro (loot.mac):** Already loads epic lists from `epic_classes.ini` + `epic_items_<class>.ini` or `epic_items_exact.ini` when `alwaysLootEpic` is true, and checks epic **first** in EvaluateItem (before skip lists). So epic items are always looted today.
- **Same epic list:** Sell and loot both use the same INI sources (`epic_items_exact.ini`, `epic_classes.ini`, `epic_items_<class>.ini`). So “epic” means the same set of items for both “never sell” and “always loot.”

No change is required to the loot macro for epic = always loot; the design only adds the sell cache. Ensure `loot_flags.ini` has `alwaysLootEpic=TRUE` (default) and that the shared epic INI files are populated.

### Optional: loot cache (future)

If we later add a **loot cache** (same pattern as sell cache):

- ItemUI would compute “should this be looted?” per corpse item (using `shouldItemBeLooted()`) and write `loot_cache.ini` with item names that **should** be looted.
- Epic items would always be included in that list (because `shouldItemBeLooted()` returns true for them when `alwaysLootEpic` is true).
- The loot macro would then only loot items in the loot list, and epic items would remain “always looted” by virtue of being in the list.

Until then, epic = always loot is already guaranteed by the existing loot macro + epic lists.

---

## Options Considered

### Option A: Item cache + macro-readable INI “sell list” (recommended)

- **Item cache (Lua):** Each item in `inventory.lua` gets `willSell` (and optionally `sellReason`). Computed at save time from `willItemBeSold()`.
- **Macro-readable file:** When saving the inventory cache, ItemUI also writes a small INI in the same char folder, e.g. `Chars/CharName/sell_cache.ini`, that lists **only item names that are allowed to be sold** (willSell == true).
- **Sell macro:** On startup, loads that INI (or skips if missing). For each item in bags, gets item name; if name is in the sell list → sell; else → skip. No EvaluateItem logic.

**Pros:** Clear contract, macro stays simple, one INI file per char.  
**Cons:** Two writes on save (inventory.lua + sell_cache.ini); macro must have path to char folder and read INI.

### Option B: Macro reads Lua cache

- Macro would need to “parse” `inventory.lua` (Lua table). MQ macro language cannot execute Lua or parse arbitrary Lua.

**Verdict:** Not viable. Macro must use INI or another format it can read.

### Option C: Item cache only; macro reads a “flat” export

- Same as A, but the “sell list” is the only thing the macro ever reads (no need for the macro to open inventory.lua). The cache in inventory.lua is still the source; we just always export the sell list to INI when we save.

**Verdict:** Same as A in practice. The “export” is the INI sell list.

### Option D: INI key = item name, value = 1/0

- One INI section `[Items]`, key = full item name, value = `1` (sell) or `0` (keep). Macro does a single lookup per item: `${Ini[path,Items,${itemName}]}`.

**Pros:** One lookup per item; no loop.  
**Cons:** Item names can contain `]`, `=`, etc. Some MQ/INI implementations may break on these. Safer to avoid using item name as INI key unless we define and test an escaping scheme.

---

## Recommended Option: A (item cache + INI sell list)

- **Item cache** remains the source of truth and stores `willSell` (and optionally `sellReason`) per item for UI and consistency.
- **Macro** only needs a simple “sell list” INI that ItemUI writes from that cache. Using a **list format** (numeric keys, value = item name) avoids special-character issues in INI keys.

---

## Implementation Plan

### 1. ItemUI: Compute and store sell status in the cache

**1.1 When to compute**

- Whenever we are about to save the inventory snapshot:
  - In **full scan:** at the end of `scanInventory()`, before `storage.saveInventory(inventoryItems)`.
  - In **incremental scan:** when we finish and call `storage.saveInventory(inventoryItems)`.
- Use the **same** inputs as today: for each item, build `itemData` (name, type, value, totalValue, stackSize, nodrop, notrade, lore, quest, collectible, heirloom, **inKeep**, **inJunk**) where inKeep/inJunk come from keep/junk lists + stored snapshot (same as `getSellStatusForItem` / `scanSellItems`). Then call `willItemBeSold(itemData, sellConfigCache)` and set:
  - `item.willSell = willSell`
  - `item.sellReason = reason` (optional; useful for debugging and for UI if we ever want to show cached reason before re-run).

**1.2 Where to compute**

- Add a small helper, e.g. `computeAndAttachSellStatus(items)` (in init.lua or a small helper module), that:
  - Ensures `perfCache.sellConfigCache` and stored snapshot (for inKeep/inJunk overrides) are up to date.
  - For each item in `items`, builds itemData, calls `willItemBeSold()`, sets `item.willSell` and `item.sellReason`.
- Call this **immediately before** every `storage.saveInventory(items)` (full and incremental).

**1.3 Persist in inventory.lua**

- **storage.lua**  
  - In `serializeItem()`: if `it.willSell ~= nil`, write `willSell=true` or `willSell=false`. If `it.sellReason` is present, optionally write `sellReason="..."` (escape string).  
  - On load, existing code already passes through unknown keys; ensure loaded items have `willSell` and `sellReason` so UI and export stay consistent.

Result: the **inventory cache** (in-memory and file) always carries the last computed sell decision per item.

---

### 2. ItemUI: Write macro-readable “sell list” INI

**2.1 File and path**

- **Path:** Same character folder as inventory.lua:  
  `Macros/sell_config/Chars/<CharName>/sell_cache.ini`  
  (use existing `config.getCharStoragePath(CharName, "sell_cache.ini")`).

**2.2 Format (INI list to avoid special chars in keys)**

- Section `[Meta]` (optional): e.g. `savedAt=<timestamp>` so macro can detect freshness.
- Section `[Count]`: single key `count` = number of items in the sell list.
- Section `[Items]`: keys `1`, `2`, … `count`; value = **exact item name** (only items with `willSell == true`). Order does not matter.

Example:

```ini
[Meta]
savedAt=1738640000

[Count]
count=2

[Items]
1=Junk Dagger
2=Common Shield
```

- Item names that contain `=` or `]` are only in the **value** part; INI values are generally safe. If the macro’s INI reader trims or misparses values, we can add a note to escape newlines in item names (EQ item names typically do not contain newlines).

**2.3 When to write**

- Immediately after a successful `storage.saveInventory(items)` (same `items` that already have `willSell` set).
- New helper: e.g. `storage.writeSellCache(items)` in storage.lua:
  - Takes the same `items` array.
  - Opens `getCharStoragePath(CharName, "sell_cache.ini")`.
  - Writes [Meta], [Count], and [Items] with only items where `it.willSell == true`.
  - If no such items, write `count=0` and no keys in [Items].

**2.4 Edge cases**

- **No char name / path:** Do not write sell_cache.ini (same as not writing inventory.lua).
- **Read-only or missing char folder:** Write is best-effort; if it fails, log and continue. Macro will see missing file and can fall back to “don’t sell anything” or legacy behavior.

---

### 3. Sell macro: Use cache only (no EvaluateItem)

**3.1 Load sell list at startup**

- After parsing args and setting `configPath` / `sharedConfigPath`, build char-specific path to sell cache. Macro has `${Me.Name}`; sanitize the same way ItemUI does (e.g. replace non-alphanumeric with `_`). Path:  
  `${configPath}/Chars/${sanitizedName}/sell_cache.ini`
- If the file does not exist (e.g. ItemUI never saved for this char), either:
  - **Strict:** Treat as “no items allowed to sell” and skip selling (or exit with a message), or
  - **Fallback:** Keep current EvaluateItem logic when sell_cache.ini is missing (optional; adds back duplicate logic only when cache is absent).
- If file exists: read `[Count]` `count`. Then for `i = 1` to `count`, read `[Items]` key `i` → value = item name. Store in a macro array or a long string `sellList` with delimiters (e.g. `/`) so we can check `${sellList.Find[|${itemName}|]}` or similar. Macro variable length limits (2048) may require multiple variables (sellList1, sellList2, …) or a single section where keys are indices and we loop.

**3.2 Sell pass**

- For each bag/slot with an item:
  - `/varset itemName ${Me.Inventory[pack${bag}].Item[${slot}].Name}`.
  - If using a delimited string: check whether itemName appears in the sell list (with a safe delimiter so “Shield” doesn’t match “Fine Shield”). For example, store names as `|Name|` and use `${sellList.Find[|${itemName}|]}`.
  - If using indexed INI: loop `i = 1` to `count`, `/varset allowedName ${Ini[path,Items,${i}]}`, `/if (${itemName.Equal[${allowedName}]})` then sell and break.
  - If item is in the sell list → call existing `ProcessSellItem` (or equivalent). If not in list → skip (no sell).

**3.3 Remove or bypass EvaluateItem**

- **Option 3a (recommended):** Remove EvaluateItem’s keep/epic/value logic entirely. EvaluateItem becomes: “get item name; if name in sell list then set shouldSell TRUE and call ProcessSellItem; else return.” All “should I sell?” logic lives in ItemUI.
- **Option 3b:** Keep EvaluateItem as a fallback when `sell_cache.ini` is missing (so users who never open ItemUI can still use the macro with old behavior). When sell_cache.ini exists, use only the cache.

**3.4 Count pass (preview)**

- Same as sell pass: for each item, only count it as “to be sold” if it is in the sell list. No need to run old EvaluateItem for preview.

---

### 4. Stale cache and “Run sell macro” from ItemUI

- **Stale cache:** If the user runs `/macro sell` without having ItemUI open, the macro uses the last written sell_cache.ini. Items picked up after the last save are not in the cache; define behavior: either “not in list = do not sell” (safe) or “missing file = fallback to old EvaluateItem” (optional).
- **When user clicks “Run sell macro” in ItemUI:** Before launching the macro, ItemUI can:
  1. Refresh inventory (full or incremental),
  2. Call `computeAndAttachSellStatus(inventoryItems)`,
  3. Save inventory (so both inventory.lua and sell_cache.ini are up to date),
  4. Then start the sell macro.

So when run from ItemUI, the cache is always fresh.

---

### 5. Summary of file and code touch points

| Layer        | File / area              | Change |
|-------------|---------------------------|--------|
| ItemUI      | init.lua                 | Add `computeAndAttachSellStatus(items)`; call before every `storage.saveInventory(items)`. Before starting sell macro, ensure scan + compute + save. |
| ItemUI      | storage.lua              | In `serializeItem()`, persist `willSell` (and optionally `sellReason`). Add `writeSellCache(items)` and call it after `saveInventory(items)`. |
| ItemUI      | config.lua               | No change (path already from `getCharStoragePath`). |
| Sell macro  | sell.mac                  | At startup, load `sell_cache.ini` for current char; build sell list (indexed or delimited). In EvaluateItem (or single sell loop), only sell if item name is in sell list. Remove or bypass existing keep/epic/value logic when cache is used. |

---

### 6. Testing

- **ItemUI:** After scan + save, open inventory.lua and sell_cache.ini; confirm items have `willSell` and only “Sell” items appear in sell_cache.ini. Toggle Keep/Junk, rescan/save, confirm cache and INI update.
- **Macro:** With sell_cache.ini present, run `/macro sell` and `/macro sell confirm`; only items in the sell list should be sold. Run without ItemUI (no recent save); confirm behavior (no sell or fallback).
- **Epic:** Mark an item as epic in config; ensure it never appears in sell_cache.ini and is never sold by the sell macro. Run the loot macro on a corpse that has an epic item; ensure the epic item is always looted (loot.mac already does this via epic lists).

### Epic checklist

- Epic items use the same list for **sell** (protectEpic → never in sell list) and **loot** (alwaysLootEpic → always looted).
- Config: `sell_flags.ini` → `protectEpic=TRUE`; `loot_flags.ini` → `alwaysLootEpic=TRUE`; shared `epic_items_exact.ini` / `epic_classes.ini` populated.

This design gives a single place (ItemUI + item cache) where “sell or not” is computed, and a simple, safe contract (INI sell list) so the sell macro only sells what’s in the cache. Epic items are never sold and are always looted via the same epic list.
