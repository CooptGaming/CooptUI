# Augment stats not showing in tooltip / Item Display

## Symptom

Some augments (e.g. Barbed Dragon Bones, Jade Prism of Hatred) had stats that showed in the default game UI and in the `/macro iteminfo` output, but did **not** show in CoOpt UI's on-hover tooltip or Item Display. Typically these were augments with only one or two stats (e.g. Shielding + DamShield, or HP Regen only).

## Cause

The lazy stat batch in `item_helpers.buildItemFromMQ` was storing the correct values (confirmed via debug), but the **table used when drawing the tooltip** was not always the same reference that had been batch-loaded. So the draw path sometimes read from a table that didn't have those stats set.

## Fix (in `item_tooltip.lua`)

1. **Re-fetch from TLO for augments**  
   Right before building the "All Stats" block, for augmentation items we call `getItemTLO(bag, slot, source)` and read **Shielding**, **DamShield**, and **HPRegen** from that TLO, then `rawset(item, "shielding", v)` (and same for `damageShield`, `hpRegen`) on the **current** `item` table we're about to use for the combat array. That way the table we render from always has these values.

2. **Use rawget + fallback when building combat**  
   For `shielding`, `damageShield`, and `hpRegen` we use `rawget(item, "…")` and fall back to `item.…` so we use the values we just set.

3. **Force "All Stats" for sparse augment stats**  
   If the item is an augmentation and any of `sh`, `ds`, or `hr` is non-zero, we set `hasAnyStat = true` so the "All Stats" section is always drawn for those augments.

4. **Single-column when only combat has content**  
   When `#attrs == 0` and `#resists == 0` and `#combat > 0`, we draw the combat stats in a single column instead of the normal 3-column layout so the stats aren't clipped.

## If more augment stats are missing later

1. In the augment re-fetch block in `item_tooltip.lua`, add the missing TLO name (e.g. `try(it, "HPRegen")`) and `rawset(item, "fieldName", v)`.
2. When building the combat (or attrs/resists) array, resolve that field with `rawget(item, "fieldName")` and use it in the `cl(...)` (or equivalent) call.
3. If the augment only has that stat, add it to the `augmentSparseStats` check so `hasAnyStat` is still true.

## Debug script

`lua/itemui/test_augment_stat_debug.lua` emulates the bag-scan TLO path and prints every stat. Run with:

- `/lua run itemui/test_augment_stat_debug <bag> <slot>` (same path as UI)
- `/lua run itemui/test_augment_stat_debug cursor` (cursor TLO for comparison)

Use it to confirm which stats the TLO returns for a given augment so you know what to add to the re-fetch list. (Note: script removed in Batch 2 cleanup; see archive.)
