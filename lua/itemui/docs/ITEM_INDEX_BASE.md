# ItemUI: Bag and Slot Index Base

## Rule: 1-based everywhere in ItemUI

- **Stored values:** `item.bag` and `item.slot` on all item tables (inventory, bank, sell, cache) are **1-based**.
- **TLO calls:** `Me.Inventory("pack"..bag).Item(slot)` and `Me.Bank(bag).Item(slot)` are called with **1-based** `bag` and `slot` (pack1–pack10, bank1–bank24, slot 1–N within container).
- **Commands:** `/itemnotify in pack%d %d` and `/itemnotify in bank%d %d` use the same 1-based bag and slot.

## MQ TLO nuance: ItemSlot / ItemSlot2

- MQ’s `item.ItemSlot()` and `item.ItemSlot2()` return **0-based** indices (per MQ convention).
- **Bank scan** in `services/scan.lua` converts these to 1-based when building cache entries:  
  `(islot or (bagNum-1)) + 1`, `(islot2 or (slotNum-1)) + 1`.
- All other code (inventory scan, views, tooltip, item_ops, getItemTLO) uses 1-based bag/slot only; no conversion.

## Single place for TLO resolution

- **`item_helpers.getItemTLO(bag, slot, source)`** is the single function that turns (bag, slot, source) into the item TLO. It expects 1-based bag and slot. Use it for any code that needs the live item at a location (lazy load, tooltip, effects, etc.).

## Summary

| Context              | Bag / slot base | Notes                                      |
|----------------------|-----------------|--------------------------------------------|
| item.bag, item.slot  | 1-based         | All stored and passed around in ItemUI     |
| getItemTLO(bag,slot) | 1-based         | Pass through as-is                         |
| Me.Bank / Me.Inventory | 1-based       | pack1..pack10, bank1..bank24, Item(1)..    |
| /itemnotify          | 1-based         | Same as above                               |
| MQ ItemSlot/ItemSlot2| 0-based         | Only in bank scan; convert to 1-based then |
