# Sell Configuration System

This directory contains modular configuration files for the sell macro. Each file controls a specific aspect of the sell decision logic.

## File Structure

### `sell_keep_exact.ini`
- **Purpose**: Exact item names that should NEVER be sold
- **Format**: INI file with `[Items]` section, `exact=Item1/Item2/Item3` format
- **Priority**: High (checked early in decision logic)
- **Example**: `exact=Epic 1.0 Item/Epic 2.0 Item/Wrapped Presents`

### `sell_keep_contains.ini`
- **Purpose**: Keywords that, if found in an item name, will cause it to NEVER be sold
- **Format**: INI file with `[Items]` section, `contains=Keyword1/Keyword2/Keyword3` format
- **Priority**: High (checked after exact names)
- **Example**: `contains=Epic/Legendary/Mythical` (will match "Epic Sword", "Epic 1.0 Item", etc.)

### `sell_keep_types.ini`
- **Purpose**: Item types that should NEVER be sold
- **Format**: INI file with `[Items]` section, `types=Type1/Type2/Type3` format
- **Priority**: High (checked after contains keywords)
- **Example**: `types=Augmentation`

### `sell_always_sell_exact.ini`
- **Purpose**: Exact item names that should ALWAYS be sold
- **Format**: INI file with `[Items]` section, `exact=Item1/Item2/Item3` format
- **Priority**: High (checked after keep lists)
- **Example**: `exact=Polished Crysolite/Fine Steel Rapier`

### `sell_always_sell_contains.ini`
- **Purpose**: Keywords that, if found in an item name, will cause it to ALWAYS be sold
- **Format**: INI file with `[Items]` section, `contains=Keyword1/Keyword2/Keyword3` format
- **Priority**: High (checked after keep lists)
- **Example**: `contains=Rusty/Cracked/Ornament`

### `sell_protected_types.ini`
- **Purpose**: Item types that should NEVER be sold (sell-specific protected types)
- **Format**: INI file with `[Items]` section, `types=Type1/Type2/Type3` format
- **Priority**: Medium (checked after keep types)
- **Example**: `types=Food/Drink/Alcohol/Potion`

### `sell_flags.ini`
- **Purpose**: Flag-based protection rules
- **Format**: INI file with `[Settings]` section, Key=Value pairs (TRUE/FALSE)
- **Priority**: Medium (checked after type checks)
- **Settings**:
  - `protectNoDrop`: Never sell items with NoDrop flag - Default: TRUE
  - `protectNoTrade`: Never sell items with NoTrade flag - Default: TRUE
  - `protectLore`: Never sell items with Lore flag - Default: TRUE
  - `protectQuest`: Never sell items with Quest flag - Default: TRUE
  - `protectCollectible`: Never sell items with Collectible flag - Default: TRUE
  - `protectHeirloom`: Never sell items with Heirloom flag - Default: TRUE
  - `protectAttuneable`: Never sell items with Attuneable flag - Default: FALSE
  - `protectAugSlots`: Never sell items with augmentation slots - Default: FALSE
  - `sellMode`: Sell engine – `macro` = run sell.mac (default), `lua` = native Lua sell (faster). Use `/itemui sell legacy` to force sell.mac regardless.
  - `sellVerboseLog`: When using Lua sell, set to `TRUE` to print each sold item to the console (e.g. `[ItemUI] [LUA SELL] ItemName x1 (Value: 0) - Sell`). Default: FALSE.

### `sell_value.ini`
- **Purpose**: Value thresholds and lag handling for sell operations
- **Settings**:
  - `minSellValue`, `minSellValueStack`, `maxKeepValue`, `tributeKeepOverride` – Value-based rules
  - `sellWaitTicks` – Wait time (ticks, ~10/sec) before considering a sell failed. Default 30 = 3 sec. Increase to 50+ on laggy connections.
  - `sellRetries` – Retries when sell fails (e.g. lag). Default 4 = up to 5 total attempts per item.

## Decision Logic Priority

The sell macro evaluates items in this order:

1. **Unsellable Flags** (`sell_flags.ini` - NoDrop, NoTrade)
2. **Keep - Exact Names** (`sell_keep_exact.ini`)
3. **Always Sell - Exact Names** (`sell_always_sell_exact.ini`)
4. **Keep - Contains Keywords** (`sell_keep_contains.ini`)
5. **Always Sell - Contains Keywords** (`sell_always_sell_contains.ini`)
6. **Keep - Item Types** (`sell_keep_types.ini`)
7. **Protected Item Types** (`sell_protected_types.ini`)
8. **Protected Flags** (`sell_flags.ini` - Lore, Quest, Collectible, etc.)
9. **No match = SELL**

**Logic**: Items SELL unless a KEEP rule matches.

## Chunked Lists (2048 Character Limit)

MQ macro variables have a 2048 character limit. Long lists (e.g. many junk items) are automatically split across multiple keys (`exact`, `exact2`, `exact3`) when written by ItemUI or SellUI. The sell macro and validate_config read all chunks. You can safely add hundreds of items; the system handles chunking transparently.

## File Format Rules

- All files are INI format (`.ini` extension)
- Lines starting with `;` are comments and will be ignored
- Empty lines are ignored
- For list files (keep, always sell, protected types): Use `[Items]` section with values separated by `/`
- For config files (flags): Use `[Settings]` section with Key=Value format
- Case-sensitive matching (exact matches for exact names, case-sensitive contains for keywords)

## Editing Tips

1. **Keep Lists**: Add items you never want to sell, regardless of value
2. **Always Sell Lists**: Add items you always want to sell (overrides keep lists)
3. **Protected Types**: Add item types to never sell (e.g., Food, Potions)
4. **Flag Rules**: Enable/disable protection for special item properties

## Migration from perky_config.ini

If migrating from the old `perky_config.ini` system:

- `valuableExact` → `sell_keep_exact.ini` (format: `exact=Item1/Item2/Item3`)
- `valuableContains` → `sell_keep_contains.ini` (format: `contains=Keyword1/Keyword2/Keyword3`)
- `valuableTypes` → `sell_keep_types.ini` (format: `types=Type1/Type2/Type3`)
- `junkExact` → `sell_always_sell_exact.ini` (format: `exact=Item1/Item2/Item3`)
- `junkContains` → `sell_always_sell_contains.ini` (format: `contains=Keyword1/Keyword2/Keyword3`)
- `protectedTypes` → `sell_protected_types.ini` (format: `types=Type1/Type2/Type3`)
- `protectNoDrop`, `protectNoTrade`, etc. → `sell_flags.ini`
