# Lore Item Duplicate Check - Implementation Guide

## Critical Importance

**Attempting to loot a duplicate lore item will cause the loot window to close immediately, stopping all further looting.** This check is CRITICAL and must be implemented correctly.

## Requirements

### 1. Check Both Inventory AND Bank

Lore items are account-wide - you can only have ONE per account, whether it's in:
- Your current character's inventory
- Your current character's bank
- Any other character's inventory or bank on the same account

**Implementation**: Use `FindItem[=ItemName]` which searches both inventory and bank.

### 2. Skip Gracefully

If a duplicate is found:
- Skip the item with `/return` (does not break the loot loop)
- Log clearly that it's skipping a duplicate
- Continue processing remaining items

**DO NOT**:
- Attempt to loot the duplicate (will close loot window)
- Stop the loot process
- Break the loot loop

### 3. Check Before Any Other Logic

The lore duplicate check should be the FIRST check in `EvaluateItem`, before:
- Always loot lists
- Value checks
- Flag checks
- Any other logic

## Current Implementation Review

From `loot.mac` lines 200-218:

```macro
| --- Check if we already have this lore item ---
/varset hasLoreItem FALSE
/declare foundItemID int local 0

/if (${isLore}) {
    /varset foundItemID ${FindItem[=${lootName}].ID}
    /if (${foundItemID} > 0) {
        /varset hasLoreItem TRUE
    }
}

/echo Evaluating: ${lootName} (Value: ${itemValue}, Type: ${lootType}, Lore: ${isLore})

| =========================================== |
| PRIORITY 0: LORE CHECK (HIGHEST PRIORITY)  |
| =========================================== |
/if (${isLore} && ${hasLoreItem}) {
    /echo Skipping LORE DUPLICATE: ${lootName}
    /return
}
```

### Analysis

✅ **Correct**: Uses `FindItem[=${lootName}]` which checks both inventory and bank  
✅ **Correct**: Skips with `/return` which doesn't break the loot loop  
✅ **Correct**: Checks before other logic  
✅ **Correct**: Logs clearly that it's skipping  

### Potential Improvements

1. **More Robust Error Handling**: Consider adding error handling if `FindItem` fails
2. **Clearer Logging**: Could add more detail about where the duplicate was found
3. **Verification**: Ensure the check works correctly if multiple lore items appear on the same corpse

## Recommended Implementation

```macro
sub EvaluateItem(int slot)
    | --- Cache item properties into variables ---
    /varset lootName ${Corpse.Item[${slot}].Name}
    /varset lootType ${Corpse.Item[${slot}].Type}
    /varset itemValue ${Corpse.Item[${slot}].Value}
    /varset itemTribute ${Corpse.Item[${slot}].Tribute}
    /varset isStackable ${If[${Corpse.Item[${slot}].StackSize}>1,TRUE,FALSE]}
    /varset isLore ${Corpse.Item[${slot}].Lore}
    /varset shouldLoot FALSE
    /varset skipItem FALSE

    | =========================================== |
    | PRIORITY 0: LORE DUPLICATE CHECK (CRITICAL) |
    | =========================================== |
    | Check if we already have this lore item (inventory OR bank)
    | CRITICAL: Attempting to loot duplicate lore item closes loot window
    /if (${isLore}) {
        /declare foundItemID int local 0
        /varset foundItemID ${FindItem[=${lootName}].ID}
        
        /if (${foundItemID} > 0) {
            /echo Skipping LORE DUPLICATE: ${lootName} (already owned - ID: ${foundItemID})
            /return
        }
    }

    /echo Evaluating: ${lootName} (Value: ${itemValue}, Type: ${lootType}, Lore: ${isLore})
    
    | Continue with other checks...
    | (Always Loot - Exact, Contains, Types, Value, Flags)
    
/return
```

## Testing Recommendations

1. **Test with lore item in inventory**: Should skip duplicate
2. **Test with lore item in bank**: Should skip duplicate
3. **Test with multiple lore items on corpse**: Should skip all duplicates gracefully
4. **Test with non-lore item**: Should process normally
5. **Test with unique lore item**: Should loot if not owned

## Error Scenarios

### Scenario 1: Duplicate Lore Item on Corpse
- **Expected**: Skip item, log message, continue looting other items
- **Current**: ✅ Handles correctly

### Scenario 2: Multiple Duplicate Lore Items
- **Expected**: Skip all duplicates, continue with other items
- **Current**: ✅ Should handle correctly (check runs for each item)

### Scenario 3: Loot Window Closes Unexpectedly
- **Expected**: Macro should detect and retry or continue to next corpse
- **Current**: Macro has retry logic in main loop

## Notes for Macro Update

When updating `loot.mac` to use the new config files:

1. **Keep the lore check hardcoded** - It's too critical to be configurable
2. **Ensure it's the first check** - Before any config-based checks
3. **Test thoroughly** - This is the most critical check in the macro
4. **Add clear logging** - Helps with debugging

## Summary

The lore duplicate check is **CRITICAL** and must:
- ✅ Check both inventory AND bank
- ✅ Skip gracefully without breaking the loot loop
- ✅ Be the first check in the evaluation logic
- ✅ Log clearly when skipping duplicates
- ✅ Never attempt to loot if duplicate found

The current implementation appears correct, but verify it works correctly when updating to the new config system.
