# CoOpt UI Configuration Reference

CoOpt UI uses INI-based configuration files shared between ItemUI and the sell/loot macros. All config files live under `Macros/` in three directories.

## Config File Inventory

| Directory | File | Purpose |
|-----------|------|---------|
| `sell_config/` | `sell_flags.ini` | Flag-based sell protection (NoDrop, Lore, etc.) |
| `sell_config/` | `sell_value.ini` | Value thresholds and sell timing |
| `sell_config/` | `sell_keep_exact.ini` | Exact item names to never sell |
| `sell_config/` | `sell_keep_contains.ini` | Keywords — never sell if name contains |
| `sell_config/` | `sell_keep_types.ini` | Item types to never sell |
| `sell_config/` | `sell_always_sell_exact.ini` | Exact item names to always sell (junk) |
| `sell_config/` | `sell_always_sell_contains.ini` | Keywords — always sell if name contains |
| `sell_config/` | `sell_protected_types.ini` | Item types protected from selling |
| `sell_config/` | `sell_augment_always_sell_exact.ini` | Augmentation items to always sell |
| `loot_config/` | `loot_flags.ini` | Flag-based loot rules (quest, collectible, etc.) |
| `loot_config/` | `loot_value.ini` | Loot value thresholds and tribute override |
| `loot_config/` | `loot_sorting.ini` | Post-loot inventory sorting |
| `loot_config/` | `loot_always_exact.ini` | Exact item names to always loot |
| `loot_config/` | `loot_always_contains.ini` | Keywords — always loot if name contains |
| `loot_config/` | `loot_always_types.ini` | Item types to always loot |
| `loot_config/` | `loot_skip_exact.ini` | Exact item names to never loot |
| `loot_config/` | `loot_skip_contains.ini` | Keywords — never loot if name contains |
| `loot_config/` | `loot_skip_types.ini` | Item types to never loot |
| `loot_config/` | `loot_augment_skip_exact.ini` | Augmentation items to never loot |
| `shared_config/` | `valuable_exact.ini` | Shared valuable items (keep from sell, always loot) |
| `shared_config/` | `valuable_contains.ini` | Shared valuable keywords |
| `shared_config/` | `valuable_types.ini` | Shared valuable item types |
| `shared_config/` | `epic_classes.ini` | Which classes have epic protection enabled |
| `shared_config/` | `epic_items_<class>.ini` | Per-class epic item lists (16 classes) |
| `shared_config/` | `epic_items_exact.ini` | All epic items (fallback when no classes selected) |

---

## Sell Configuration

### sell_flags.ini

Flag-based protection rules. All default to `TRUE` (protect) unless noted.

```ini
[Settings]
protectNoDrop=TRUE          ; Never sell NoDrop items
protectNoTrade=TRUE         ; Never sell NoTrade items
protectLore=TRUE            ; Never sell Lore items
protectQuest=TRUE           ; Never sell Quest items
protectCollectible=TRUE     ; Never sell Collectible items
protectHeirloom=TRUE        ; Never sell Heirloom items
protectEpic=TRUE            ; Never sell epic quest items
```

### sell_value.ini

Value thresholds (all values in copper: 1pp = 1000cp).

```ini
[Settings]
minSellValue=50             ; Skip non-stackable items worth less than this
minSellValueStack=10        ; Skip stackable items worth less than this per unit
maxKeepValue=10000          ; Never sell items worth more than this (total value)
sellWaitTicks=30            ; Ticks to wait before considering sell failed (10 ticks/sec)
sellRetries=4               ; Retries on sell failure (up to 5 total attempts)
```

### Sell Lists

| File | Key | Match Type | Effect |
|------|-----|------------|--------|
| `sell_keep_exact.ini` | `exact` | Exact name | Never sell |
| `sell_keep_contains.ini` | `contains` | Substring | Never sell |
| `sell_keep_types.ini` | `types` | Item type | Never sell |
| `sell_always_sell_exact.ini` | `exact` | Exact name | Always sell |
| `sell_always_sell_contains.ini` | `contains` | Substring | Always sell |
| `sell_protected_types.ini` | `types` | Item type | Never sell |
| `sell_augment_always_sell_exact.ini` | `exact` | Exact name | Always sell (augments only) |

---

## Loot Configuration

### loot_flags.ini

```ini
[Settings]
lootClickies=TRUE           ; Loot items with clicky effects (wearable only)
lootQuest=FALSE             ; Loot quest items
lootCollectible=FALSE       ; Loot collectible items
lootHeirloom=FALSE          ; Loot heirloom items
lootAttuneable=FALSE        ; Loot attuneable items
lootAugSlots=FALSE          ; Loot items with augmentation slots
alwaysLootEpic=TRUE         ; Always loot epic quest items
```

### loot_value.ini

```ini
[Settings]
minLootValue=999            ; Minimum value for non-stackable items (copper)
minLootValueStack=200       ; Minimum value for stackable items (copper)
tributeOverride=0           ; Always loot if tribute >= this (0 = disabled)
```

### loot_sorting.ini

```ini
[Settings]
enableSorting=FALSE         ; Master toggle for post-loot sorting
enableWeightSort=FALSE      ; Sort by weight (heavy to front bags)
minWeight=40                ; Weight threshold (tenths: 40 = 4.0 lbs)
```

### Loot Lists

| File | Key | Match Type | Effect |
|------|-----|------------|--------|
| `loot_always_exact.ini` | `exact` | Exact name | Always loot |
| `loot_always_contains.ini` | `contains` | Substring | Always loot |
| `loot_always_types.ini` | `types` | Item type | Always loot |
| `loot_skip_exact.ini` | `exact` | Exact name | Never loot |
| `loot_skip_contains.ini` | `contains` | Substring | Never loot |
| `loot_skip_types.ini` | `types` | Item type | Never loot |
| `loot_augment_skip_exact.ini` | `exact` | Exact name | Never loot (augments only) |

---

## Shared Configuration

Files in `shared_config/` are referenced by **both** sell and loot systems:

- **`valuable_exact.ini`** — Items here are kept from selling AND always looted
- **`valuable_contains.ini`** — Keywords here protect from selling AND trigger looting
- **`valuable_types.ini`** — Types here are protected from selling AND always looted

### Epic Protection

Epic quest items are protected from selling and always looted. Configuration:

1. **`epic_classes.ini`** — Toggle per-class epic protection (`[Classes]` section, `bard=TRUE`, etc.)
2. **`epic_items_<class>.ini`** — Per-class epic item lists (bard, cleric, druid, etc.)
3. **`epic_items_exact.ini`** — Fallback: all epic items (used when no classes are selected)

If specific classes are selected, only those classes' epic items are protected. If no classes are selected (or selected classes have empty lists), the full `epic_items_exact.ini` list is used as a fallback.

---

## Sell Decision Logic

The sell system evaluates items in this order. First match wins.

| # | Check | Result | Source |
|---|-------|--------|--------|
| 1 | Augment always-sell list (augments only) | **SELL** | `sell_augment_always_sell_exact.ini` |
| 2 | Augment never-loot list (augments only) | **SELL** | `loot_augment_skip_exact.ini` |
| 3 | Never-loot list (sell to clear inventory) | **SELL** | `loot_skip_exact.ini` |
| 4 | NoDrop flag + protectNoDrop | **KEEP** | `sell_flags.ini` |
| 5 | NoTrade flag + protectNoTrade | **KEEP** | `sell_flags.ini` |
| 6 | Epic item (normalized name match) | **KEEP** | `epic_items_*.ini` |
| 7 | In keep list (exact) | **KEEP** | `sell_keep_exact.ini` + `valuable_exact.ini` |
| 8 | In junk list (exact) | **SELL** | `sell_always_sell_exact.ini` |
| 9 | Lore flag + protectLore | **KEEP** | `sell_flags.ini` |
| 10 | Quest flag + protectQuest | **KEEP** | `sell_flags.ini` |
| 11 | Collectible flag + protectCollectible | **KEEP** | `sell_flags.ini` |
| 12 | Heirloom flag + protectHeirloom | **KEEP** | `sell_flags.ini` |
| 13 | Total value >= maxKeepValue | **KEEP** | `sell_value.ini` |
| 14 | Value below minSellValue/minSellValueStack | **KEEP** | `sell_value.ini` |
| 15 | No match | **SELL** | — |

---

## Loot Decision Logic

The loot system evaluates items in this order. First match wins.

| # | Check | Result | Source |
|---|-------|--------|--------|
| 1 | Augment never-loot list (augments only) | **SKIP** | `loot_augment_skip_exact.ini` |
| 2 | Epic item + alwaysLootEpic | **LOOT** | `epic_items_*.ini` |
| 3 | Skip exact list | **SKIP** | `loot_skip_exact.ini` |
| 4 | Skip contains list | **SKIP** | `loot_skip_contains.ini` |
| 5 | Skip types list | **SKIP** | `loot_skip_types.ini` |
| 6 | Tribute override (tribute >= threshold) | **LOOT** | `loot_value.ini` |
| 7 | Always loot exact | **LOOT** | `loot_always_exact.ini` + `valuable_exact.ini` |
| 8 | Always loot contains | **LOOT** | `loot_always_contains.ini` + `valuable_contains.ini` |
| 9 | Always loot types | **LOOT** | `loot_always_types.ini` + `valuable_types.ini` |
| 10 | Value >= minLootValue/minLootValueStack | **LOOT** | `loot_value.ini` |
| 11 | Clicky + lootClickies (wearable only) | **LOOT** | `loot_flags.ini` |
| 12 | Quest + lootQuest | **LOOT** | `loot_flags.ini` |
| 13 | Collectible + lootCollectible | **LOOT** | `loot_flags.ini` |
| 14 | Heirloom + lootHeirloom | **LOOT** | `loot_flags.ini` |
| 15 | Attuneable + lootAttuneable | **LOOT** | `loot_flags.ini` |
| 16 | Has aug slots + lootAugSlots | **LOOT** | `loot_flags.ini` |
| 17 | No match | **SKIP** | — |

**Note:** Lore duplicate items are always skipped (hardcoded, not configurable). The macro checks both inventory and bank before attempting to loot lore items.

---

## List Format Rules

All item lists follow these conventions:

- **Delimiter:** Forward slash `/` separates items — `Item One/Item Two/Item Three`
- **Section:** All lists use the `[Items]` section header
- **Keys:** `exact`, `contains`, or `types` depending on match type
- **Case sensitivity:** All matching is case-sensitive
- **Chunking:** Lists longer than ~2000 characters are automatically split across keys (`exact`, `exact2`, `exact3`, etc.) to stay under MQ's 2048-character macro variable limit. ItemUI handles chunking transparently when reading and writing.
- **Invalid entries:** `null` and `nil` values are automatically filtered out
- **Item names:** Forward slashes and control characters are stripped from item names when added via ItemUI

### Example list file

```ini
[Items]
exact=Polished Crysolite/Fine Steel Rapier/Wrapped Presents
```

If the list is long enough to require chunking:

```ini
[Items]
exact=Item1/Item2/Item3/.../Item50
exact2=Item51/Item52/.../Item100
```

---

## Editing via ItemUI

Click the **Config** button in ItemUI to open the config window with three tabs:

### General & Sell Tab
- Toggle sell protection flags (NoDrop, NoTrade, Lore, Quest, Collectible, Heirloom, Epic)
- Set sell value thresholds (min sell value, min stack value, max keep value)
- Epic class selection (toggle per-class epic protection)

### Loot Rules Tab
- Toggle loot flags (clickies, quest, collectible, heirloom, attuneable, aug slots, epic)
- Set loot value thresholds (min loot value, min stack value, tribute override)
- Sorting options (enable sorting, weight sort, min weight)

### Item Lists Tab (Filters)
- Unified form to add items to any list
- Dropdown to select target list (keep exact, junk exact, always loot, never loot, etc.)
- Input field for item name/keyword/type
- **Add** button and **From Cursor** button (grabs item on cursor)
- Click **X** on any list entry to remove it
- Click an entry to edit it

---

## Per-Character Data

Character-specific data is stored in `Macros/sell_config/Chars/{CharName}/`:

- Bank snapshots (inventory data)
- Filter presets and last-used filters

This data is auto-generated and **never included in releases**. It persists across updates.
