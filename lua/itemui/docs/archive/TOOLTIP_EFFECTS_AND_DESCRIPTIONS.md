# Tooltip: Item Effects and Descriptions

Notes on how the on-hover tooltip matches the default Item Display window for effects and description text.

---

## 1. Augment / ornament effects in the effects list

The default Item Display shows **all** item effects in one list: the main item's Clicky, Worn, Proc, Focus, and Spell effects, **plus** the same effect types from each slotted augment and from the ornament (slot 5).

Our tooltip does the same:

- Effects are collected from the **main item** (Clicky, Worn, Proc, Focus, Spell).
- Then, for each socket **1 .. min(5, augSlots)** (augments 1–4 and ornament 5), we build a socket item via `getSocketItemStats(parentIt, bag, slot, source, socketIndex)` and append that socket's effects to the same list.

`getItemSpellId` in `item_helpers` supports **socketed items**: when `item.socketIndex` is set, it resolves the parent TLO then `parent.Item(socketIndex)` so spell IDs come from the correct augment/ornament. No change to existing behavior for non-socketed items.

---

## 2. STML / colored text in descriptions

The in-game Item Display can show **STML** (styled markup) with light blue, green, yellow, etc. Our tooltip uses plain ImGui text (no rich-text control).

- **Spell descriptions** come from the MQ Spell TLO (`Spell(id).Description()`). If that string contains XML/STML-like tags (e.g. `<c "#00ff00">text</c>`), we **strip tags** via `stripDescriptionMarkup()` so the tooltip shows the text without raw markup. Color information is not preserved; only the text is shown.
- **Full STML rendering** (e.g. applying colors per segment) would require parsing STML and drawing multiple `TextColored` segments; not implemented. Showing the same text with tags stripped keeps the tooltip accurate and fast.

---

## 3. Effect placeholders vs. actual values

Spell descriptions from the TLO sometimes contain **placeholders** such as `#1`, `#3`, `@2`, `%z` (e.g. "#3 damage initially and between #2 and @2 damage every six seconds for %z"). The **game client** replaces these with actual values (level, duration, etc.) in its UI.

- **MQ Spell TLO** exposes the raw description string with placeholders. We **substitute** them using spell effect data from the same TLO:
  - **#n** → `Spell.Base(n)` (primary value for effect slot n, 1-based).
  - **@n** and **$n** → `Spell.Base2(n)` (second value for slot n); lone **$** is treated as **$1**.
  - **%z** → spell duration formatted as **H:MM:SS** (duration in ticks × 6 = seconds).
- Substitution runs in `getSpellDescription()` after tag stripping; the result is cached under `spell:desc:<id>` so both the on-hover tooltip and CoOpt UI Item Display get resolved text. If the spell object or any effect access fails, the description is shown with placeholders unchanged.

---

## 4. Item information and Spell Info blocks

- **Item information (blue)** — Main item only: Item ID, Icon ID, Value, Ratio (weapon), Item Lore (TLO), Item Timer (Ready green or Xs). Uses `getItemLoreText(it)` and cached `getTimerReady`.
- **Spell Info for Clicky (green)** / **Worn (yellow)** — Spell ID, Duration, RecoveryTime, RecastTime, Range via L2-cached helpers. Effect slot lines not exposed by Spell TLO.

---

## Summary

| Topic              | Behavior |
|--------------------|----------|
| Augment effects    | Included in the same "Item effects" list as the main item; socket items resolved via `socketIndex`. |
| STML / colors      | Tags stripped so only plain text is shown; no colored segments. |
| Placeholders       | Resolved from spell effect slots (Base/Base2) and duration when possible; otherwise shown as-is. |
| Item info / Spell Info | Blue item block (ID, Icon, Value, Ratio, Lore, Timer); green Clicky and yellow Worn Spell Info blocks with cached spell stats. |
