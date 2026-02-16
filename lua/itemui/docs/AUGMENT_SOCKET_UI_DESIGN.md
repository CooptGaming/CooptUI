# Augment / Ornament Socket UI — Issues, Improvements, Replication

Reference: `reference/EQUI_ItemDisplay.xml`. Game uses **IDW_Appearance_Socket_*** (ornament, 40×40) and **IDW_Socket_Slot_#_Item** (augments 1–6, 20×20), each a **Button** with **BDT_DragItem** that shows an icon decal and accepts drag-and-drop.

---

## Slot layout (tooltip implementation)

- **Indices are 1-based** per `lua/itemui/docs/ITEM_INDEX_BASE.md` (bag/slot and augment slots).
- **Slots 1–4**: Augment only. We show up to 4 augment rows; if the item has an ornament slot, we show `augSlots - 1` augment lines so the ornament is not duplicated as a fourth augment.
- **Slot 5**: Ornament only (socket type **20** = Ornamentation). We resolve ornament by:
  1. `getSlotType(it, 5) == 20` → name/icon from `it.Item(5)`.
  2. If not, fallback to `it.Ornament` (e.g. when TLO only exposes that).
- **Helpers**: `getSlotType(it, slotIndex)` returns socket type (tries `AugSlot#` then `AugSlot(i).Type`). `itemHasOrnamentSlot(it)` is true when slot 5 has type 20; used to set augment line count to `augSlots - 1` when present.

---

## Possible issues

1. **Row alignment** — Empty slots have no icon cell, so their text starts at the left while filled slots have icon + text. Rows don’t line up like the default UI.
2. **Empty-slot visual** — No dedicated “empty socket” graphic; empty rows are text-only. Default UI always shows a button (frame + optional empty decal).
3. **Tooltip lifetime** — Tooltips close when the mouse moves. Drag-drop *onto* a tooltip is therefore impractical; the tooltip would disappear before drop.
4. **Size mismatch** — Game uses 20×20 for augment sockets and 40×40 for ornament. We use 24×24 for both; acceptable for readability but not pixel-exact.
5. **Slot type for empty** — When `typ == 0` we show “Slot N: empty”. If the TLO ever reports slot type for an empty socket, we could show “Slot N, type X (Name): empty” for consistency.
6. **Performance** — Multiple `pcall` and TLO calls per hover; acceptable but could be cached if tooltip is shown repeatedly for the same item.

---

## Improvements (short term)

- **Consistent layout**: Reserve the same 24×24 space for every socket row (filled and empty) so description text aligns. Match default UI’s [icon | description] layout.
- **Empty placeholder**: Draw a reserved 24×24 area for empty slots (e.g. `Dummy` or, if available, a known “empty” texture cell from A_DragItem) so every row has [box][text].
- **No draw-list for empty**: Avoid `GetWindowDrawList():AddRect()` for the empty box if it causes binding issues; use texture or `Dummy` only.
- **Ornament size**: Optionally use a larger icon for ornament (e.g. 32×32) to mirror the game’s 40×40; lower priority.

---

## Replication strategy (default UI behavior)

We cannot embed the game’s Button control in ImGui. Replicate as follows:

### Visual (tooltip)

1. **Every socket row** (ornament + augment 1..N): same structure  
   `[ 24×24 icon area ]` + `SameLine` + `[ description text ]`.
2. **Filled slot**: Draw item icon via `ctx.drawItemIcon(iconId)` (A_DragItem texture, same as game).
3. **Empty slot**: Draw a 24×24 placeholder:
   - Prefer: same A_DragItem texture at a known “empty slot” cell if the client exposes one.
   - Fallback: `ImGui.Dummy(24, 24)` so space is reserved and rows align; no rect/border if draw-list is unreliable.
4. **Data**: Item TLO with slot rules above: `getSlotType(it, i)`, `it.AugSlot(i)`, `it.Item(i)` for slots 1–4; ornament from slot 5 type 20 or `it.Ornament` fallback.

### Interaction (CoOpt UI Item Display)

In the **Item Display** window (persistent, tabbed), augment slot rows are interactive via the **24×24 icon** only (no separate Add/Remove buttons):

- **Hover over icon**
  - **Filled slot**: Full augment stats tooltip + hint “Right-click icon to remove augment”.
  - **Empty slot**: “Slot N, type X (Name): Empty. Left-click to open Augment Utility and add an augment.”
- **Left-click empty slot icon**: Opens the standalone **Augment Utility** window with that slot selected; target is the current Item Display tab. User picks a compatible augment from the utility and inserts from there.
- **Right-click filled slot icon**: Runs the augment-utility remove-from-slot process (opens game Item Display and removes the augment; game picks distiller). Right-click is used to reduce accidental removal.

The augment **name** (text right of the icon) still shows the socketed augment tooltip on hover. The standalone Augment Utility window remains the place for browsing compatible augments and inserting when opened from an empty-slot click.

### Summary

- **Now**: Same row layout (icon left, text right), 24×24 for every slot, filled = item icon, empty = reserved 24×24. In Item Display, icon is the single interaction target: hover = tooltip, empty left-click = open Augment Utility, filled right-click = remove.
- **Game window**: Remove flow uses `mq.TLO.Window("ItemDisplayWindow")` and `/invoke`; actual distiller/confirmation stays in the game UI.
