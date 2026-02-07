# Loot Macro Configuration - Analysis & Recommendations

## Current State Analysis

### Current Logic Flow (loot.mac v3.1)

The current loot macro uses a hierarchical decision system:

1. **Lore Duplicate Check** - Skip if lore item already owned (hardcoded)
2. **Tribute Override** - Loot if tribute >= threshold
3. **Valuable Exact Names** - Loot if exact match
4. **Valuable Contains** - Loot if name contains keyword
5. **Valuable Types** - Loot if type matches
6. **Value Checks** - Loot if value >= threshold (different for stackable)
7. **Flag Checks** - Loot if has clicky (wearable only)

### Current Configuration Issues

1. **Mixed with sell.mac**: Configuration shared in `perky_config.ini` creates coupling
2. **Hardcoded defaults**: Item names in macro code (lines 424-429)
3. **"Junk" lists unused**: Defined but not used in loot logic (only in sell.mac)
4. **Not modular**: All checks in one INI file, harder to manage
5. **Naming confusion**: "Valuable" vs "Always Loot" - unclear distinction

## Proposed Solution

### New Modular Structure

I've created separate configuration files for each check type:

```
Macros/
  loot_config/
    ├── loot_always_exact.txt      (exact item names)
    ├── loot_always_contains.txt   (keywords)
    ├── loot_always_types.txt      (item types)
    ├── loot_value.txt             (value thresholds)
    ├── loot_flags.txt             (flag-based rules)
    ├── loot_sorting.txt           (inventory sorting)
    └── README.md                  (documentation)
```

### Benefits

1. **Separation of Concerns**: Each file has one clear purpose
2. **Easy to Edit**: Simple text files, one entry per line
3. **No Hardcoding**: All item names in config files
4. **Future-Proof**: Easy to add new check types
5. **Lua UI Ready**: Simple format makes UI integration straightforward

## Recommendations

### 1. Keep These Features ✅

- **Value thresholds** (minLootValue, minLootValueStack) - Very useful
- **Tribute override** - Great for high-tribute items
- **Always loot lists** (exact and contains) - Essential
- **Item type filtering** - Useful for categories like Augmentation
- **Lore duplicate check** - **CRITICAL** - Prevents loot window from closing
- **Weight sorting** - Useful, now in separate file with master toggle (default FALSE)

### 2. Consider Simplifying/Removing ❓

- **Weight sorting** (`minWeight`) - ✅ Now in separate `loot_sorting.txt` file with master toggle (default FALSE)
- **Clicky flag check** - ✅ Kept, default TRUE
- **Junk lists** - Not used in loot logic, only in sell.mac (keep separate)

### 3. Potential Additions 🆕

- **Skip lists** (never loot these items) - Could be useful
- **Zone-specific rules** - Advanced feature
- **Quest item detection** - ✅ Added as optional flag (default FALSE)
- **Collectible detection** - ✅ Added as optional flag (default FALSE)
- **Heirloom detection** - ✅ Added as optional flag (default FALSE)
- **Attuneable detection** - ✅ Added as optional flag (default FALSE)
- **Augment slot detection** - ✅ Added as optional flag (default FALSE)
- **Custom bag assignments** - ✅ Added to `loot_sorting.txt` as future option
- **Bag exclusions** - ✅ Added to `loot_sorting.txt` as future option
- **Additional sorting criteria** - ✅ Structure in place for value, type, name sorting

## Decision Logic Recommendation

### Recommended Priority Order

```
1. Lore Duplicate Check (hardcoded - CRITICAL - checks inventory AND bank)
   ↓ SKIP if duplicate found (prevents loot window from closing)
2. Always Loot - Exact Names (loot_always_exact.txt)
   ↓
3. Always Loot - Contains Keywords (loot_always_contains.txt)
   ↓
4. Always Loot - Item Types (loot_always_types.txt)
   ↓
5. Tribute Override (loot_value.txt - if tribute >= threshold)
   ↓
6. Value Checks (loot_value.txt - if value >= threshold)
   ↓
7. Flag Checks (loot_flags.txt - clickies, quest, collectible, etc.)
   ↓
SKIP ITEM (no criteria met)
```

### Why This Order?

- **Lore check first**: CRITICAL - Attempting to loot duplicate lore item closes loot window
  - Must check BOTH inventory AND bank
  - Must skip gracefully without stopping loot process
- **Always loot rules next**: Ensures important items never missed
- **Value checks after**: Only evaluate value if not in always loot lists
- **Flag checks last**: Lowest priority, only if nothing else matches

### Lore Check Implementation Notes

**CRITICAL REQUIREMENT**: The lore duplicate check must:
1. Check both inventory AND bank (account-wide restriction)
2. Use `FindItem[=ItemName]` which searches both locations
3. Skip the item gracefully with `/return` (does not stop loot loop)
4. Log clearly that it's skipping a duplicate
5. Never attempt to loot if duplicate found (would close loot window)

**Current Implementation Review**:
- Uses `FindItem[=${lootName}]` which checks both inventory and bank ✅
- Skips with `/return` which is correct ✅
- Should verify it doesn't break the loot loop if multiple lore items appear ✅

## File Format Recommendations

### Text Files (exact, contains, types)
- One entry per line
- Comments with `;`
- Empty lines ignored
- Simple and easy to parse

### Config Files (value, flags)
- Key=Value format (INI-style)
- Comments with `;`
- Easy to read and edit
- Compatible with future Lua UI

## Lua UI Integration Recommendations

### For Future Lua UI Development

1. **File Structure**: Current structure is perfect for UI
   - Each file = one tab/section in UI
   - Simple format = easy to parse and display

2. **UI Features to Consider**:
   - Add/Remove items from lists
   - Search/filter within lists
   - Import/Export lists
   - Validation (check for duplicates, invalid entries)
   - Live preview (test item against rules)

3. **Integration Points**:
   - Use same file format (text files)
   - Read/write directly to config files
   - Real-time updates (reload config in macro)

4. **Suggested UI Layout**:
   ```
   [Always Loot - Exact] [Always Loot - Contains] [Always Loot - Types]
   [Value Settings] [Flag Settings] [Advanced]
   
   Each tab shows:
   - List of items/rules
   - Add button
   - Remove button
   - Search box
   - Save button
   ```

## Migration Path

### From Current System

1. **Extract from perky_config.ini**:
   - `valuableExact` → `loot_always_exact.txt`
   - `valuableContains` → `loot_always_contains.txt`
   - `valuableTypes` → `loot_always_types.txt`
   - `minLootValue`, etc. → `loot_value.txt`
   - `lootClickies` → `loot_flags.txt`

2. **Update loot.mac**:
   - Remove hardcoded defaults
   - Add file reading functions
   - Update decision logic to use new files

3. **Keep sell.mac separate**:
   - sell.mac can keep using perky_config.ini
   - Or migrate sell.mac to similar structure later

## Questions to Consider

1. **Skip Lists**: Do you want "never loot" lists? (Currently not in loot logic)
2. **Weight Sorting**: ✅ Moved to separate `loot_sorting.txt` file with master toggle (default FALSE)
3. **Additional Flags**: ✅ Added Quest, Collectible, Heirloom, Attuneable, AugSlots (all default FALSE)
4. **Zone-Specific Rules**: Different rules per zone? (Future enhancement)
5. **Character-Specific Rules**: Different rules per character? (Future enhancement)
6. **Custom Bag Assignments**: ✅ Added to `loot_sorting.txt` as future option
7. **Bag Exclusions**: ✅ Added to `loot_sorting.txt` as future option
8. **Additional Sorting**: ✅ Structure in place for value, type, name sorting

## Next Steps

1. ✅ Created modular config file structure
2. ⏭️ Update loot.mac to read from new files
3. ⏭️ Test with existing item lists
4. ⏭️ Create Lua UI (future enhancement)
5. ⏭️ Consider skip lists and additional features

## Summary

The new modular structure provides:
- ✅ Simple, easy-to-edit configuration
- ✅ No hardcoded item names
- ✅ Clear separation of concerns
- ✅ Future-proof for Lua UI
- ✅ Maintainable and extensible
- ✅ Separate sorting configuration file (default disabled)
- ✅ Multiple flag options (all default FALSE for safety)
- ✅ Robust lore duplicate checking (critical for preventing loot window closure)

### Key Implementation Notes

1. **Lore Check**: Must check both inventory AND bank, skip gracefully
2. **Sorting**: Moved to separate `loot_sorting.txt` file with master toggle (default FALSE)
   - Master toggle: `enableSorting` must be TRUE
   - Weight sorting: `enableWeightSort` for weight-based sorting
   - Future: Value, type, name sorting, custom bag assignments, bag exclusions
3. **Flag Options**: All new flags default to FALSE - users can enable as needed
4. **Future Expansion**: Structure supports multiple sorting criteria and bag management

The format is simple enough for manual editing but structured enough for programmatic access via Lua UI.
