# Shared Configuration System

This directory contains configuration files that are shared between multiple macros (loot.mac and sell.mac).

## Purpose

Instead of duplicating valuable item lists in both loot and sell configs, we use shared configs that both systems reference. This ensures consistency and makes management easier.

## File Structure

### `valuable_exact.ini`
- **Purpose**: Exact item names that are valuable
- **Used by**: `loot.mac` (always loot), `sell.mac` (never sell)
- **Format**: INI file with `[Items]` section, `exact=Item1/Item2/Item3` format

### `valuable_contains.ini`
- **Purpose**: Keywords that indicate valuable items
- **Used by**: `loot.mac` (always loot), `sell.mac` (never sell)
- **Format**: INI file with `[Items]` section, `contains=Keyword1/Keyword2/Keyword3` format

### `valuable_types.ini`
- **Purpose**: Item types that are valuable
- **Used by**: `loot.mac` (always loot), `sell.mac` (never sell)
- **Format**: INI file with `[Items]` section, `types=Type1/Type2/Type3` format

## Priority

When both shared configs and macro-specific configs exist:
1. **Shared configs are checked first** (higher priority)
2. Macro-specific configs are checked second

This allows you to:
- Set global valuable items in shared configs
- Override with macro-specific rules if needed

## Migration

If you have existing configs in `loot_config/` or `sell_config/`, you can:
1. Move common items to shared configs
2. Keep macro-specific items in their respective configs
3. Both systems will check both locations
