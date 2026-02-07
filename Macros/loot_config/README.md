# Loot Configuration System

This directory contains modular configuration files for the loot macro. Each file controls a specific aspect of the loot decision logic.

## File Structure

### `loot_always_exact.ini`
- **Purpose**: Exact item names that should ALWAYS be looted
- **Format**: INI file with `[Items]` section, `exact=Item1/Item2/Item3` format
- **Priority**: Highest (checked first after lore duplicate check)
- **Example**: `exact=Epic 1.0 Item/Epic 2.0 Item/Wrapped Presents`

### `loot_always_contains.ini`
- **Purpose**: Keywords that, if found in an item name, will cause it to ALWAYS be looted
- **Format**: INI file with `[Items]` section, `contains=Keyword1/Keyword2/Keyword3` format
- **Priority**: High (checked after exact names)
- **Example**: `contains=Epic/Legendary/Mythical` (will match "Epic Sword", "Epic 1.0 Item", etc.)

### `loot_always_types.ini`
- **Purpose**: Item types that should ALWAYS be looted
- **Format**: INI file with `[Items]` section, `types=Type1/Type2/Type3` format
- **Priority**: High (checked after contains keywords)
- **Example**: `types=Augmentation`

### `loot_value.ini`
- **Purpose**: Value thresholds for looting items
- **Format**: Key=Value pairs (INI-style)
- **Priority**: Medium (checked after always loot rules)
- **Settings**:
  - `minLootValue`: Minimum value for non-stackable items (in copper)
  - `minLootValueStack`: Minimum value for stackable items (in copper)
  - `tributeOverride`: Always loot if tribute value >= this (0 = disabled)

### `loot_flags.ini`
- **Purpose**: Flag-based rules for special item properties
- **Format**: INI file with `[Settings]` section, Key=Value pairs (TRUE/FALSE)
- **Priority**: Low (checked last)
- **Settings**:
  - `lootClickies`: Loot items with clicky effects (wearable only) - Default: TRUE
  - `lootQuest`: Loot quest items - Default: FALSE
  - `lootCollectible`: Loot collectible items - Default: FALSE
  - `lootHeirloom`: Loot heirloom items - Default: FALSE
  - `lootAttuneable`: Loot attuneable items - Default: FALSE
  - `lootAugSlots`: Loot items with augmentation slots - Default: FALSE

### `loot_sorting.ini`
- **Purpose**: Inventory sorting configuration after looting
- **Format**: Key=Value pairs (TRUE/FALSE and numeric values)
- **When Applied**: After all looting is complete
- **Settings**:
  - `enableSorting`: Master toggle for all sorting - Default: FALSE
  - `enableWeightSort`: Enable weight-based sorting - Default: FALSE
  - `minWeight`: Weight threshold for sorting (in tenths, 40 = 4.0 lbs)
- **Future Options**: Value sorting, type sorting, custom bag assignments, bag exclusions

## Decision Logic Priority

The loot macro evaluates items in this order:

1. **Lore Duplicate Check** (hardcoded - skip if lore item already owned)
   - Checks both inventory AND bank for existing lore items
   - If duplicate found, item is skipped gracefully (does not stop loot process)
   - Important: Attempting to loot a duplicate lore item will stop the loot window, so this check is critical
2. **Always Loot - Exact Names** (`loot_always_exact.ini`)
3. **Always Loot - Contains Keywords** (`loot_always_contains.ini`)
4. **Always Loot - Item Types** (`loot_always_types.ini`)
5. **Tribute Override** (`loot_value.ini` - if tribute value >= threshold)
6. **Value Checks** (`loot_value.ini` - if item value >= threshold)
7. **Flag Checks** (`loot_flags.ini` - clickies, quest, collectible, etc.)

If ANY check passes, the item is looted. If ALL checks fail, the item is skipped.

**Note**: After looting completes, if `enableSorting=TRUE` and `enableWeightSort=TRUE` in `loot_sorting.ini`, inventory will be sorted by weight (heavy items to front bags).

## File Format Rules

- All files are INI format (`.ini` extension)
- Lines starting with `;` are comments and will be ignored
- Empty lines are ignored
- For list files (exact, contains, types): Use `[Items]` section with values separated by `/`
  - Example: `exact=Item1/Item2/Item3`
- For config files (value, flags, sorting): Use `[Settings]` section with Key=Value format
- Case-sensitive matching (exact matches for exact names, case-sensitive contains for keywords)

## Editing Tips

1. **Always Loot Lists**: Add items you never want to miss, regardless of value
2. **Value Thresholds**: Adjust based on your needs - higher values = more selective
3. **Tribute Override**: Useful for items with high tribute value but low vendor value
4. **Flag Rules**: Enable/disable special item property checks

## Important Notes

### Lore Item Handling

Lore items can only be owned once per account (in inventory or bank). The macro:
- Checks both inventory AND bank before attempting to loot lore items
- Skips duplicate lore items gracefully without stopping the loot process
- **Critical**: Attempting to loot a duplicate lore item will cause the loot window to close, stopping all further looting

### Inventory Sorting

Inventory sorting is controlled by `loot_sorting.ini`:
- **Master Toggle**: `enableSorting` must be TRUE for any sorting to occur (Default: FALSE)
- **Weight Sorting**: `enableWeightSort` enables weight-based sorting (Default: FALSE)
  - When enabled: Heavy items (>minWeight) go to front bags (1-5), light items go to back bags (6-10)
- **Future Options**: Value sorting, type sorting, custom bag assignments, bag exclusions

## Future Enhancements

- Lua UI for managing these lists (planned)
- Custom bag assignments (specific items to specific bags)
- Bag exclusions (prevent items from going to certain bags)
- Skip lists (items to never loot)
- Zone-specific rules

## Migration from perky_config.ini

If migrating from the old `perky_config.ini` system:

- `valuableExact` → `loot_always_exact.ini` (format: `exact=Item1/Item2/Item3`)
- `valuableContains` → `loot_always_contains.ini` (format: `contains=Keyword1/Keyword2/Keyword3`)
- `valuableTypes` → `loot_always_types.ini` (format: `types=Type1/Type2/Type3`)
- `minLootValue`, `minLootValueStack`, `tributeOverride` → `loot_value.ini`
- `minWeight` → `loot_sorting.ini` (controlled by `enableSorting` and `enableWeightSort`)
- `lootClickies` → `loot_flags.ini`
