# Epic Protection Disabled (Temporary)

**Date:** 2026-01-31  
**Status:** Epic protection temporarily disabled  
**Reason:** Buffer overflow issues, needs better implementation

---

## Changes Made

### 1. Fixed Duplicate Declaration Bug
**Error:** `/declare 'flagsFile' failed. Name already in use.`

**Cause:** `flagsFile` was declared twice in the LoadConfig subroutine (lines 603 and 837).

**Fix:** Removed duplicate declaration at line 837, kept the first one.

### 2. Disabled Epic Item Protection

Epic item protection has been **completely disabled** until a better implementation can be designed.

**Files Modified:** `Macros/sell.mac`

**Changes:**
1. Set `protectEpic = FALSE` at start of LoadConfig (line 604)
2. Commented out epic item loading from INI file (lines 634-646)
3. Commented out epic checks in EvaluateItem subroutine (lines 289-305)
4. Commented out protectEpic INI loading (lines 879-883)
5. Initialize epic variables as empty strings

---

## Impact

### What Still Works
✅ All other protection filters (NoDrop, NoTrade, Lore, Quest, etc.)  
✅ Keep exact name lists  
✅ Keep contains/keywords lists  
✅ Protected item types  
✅ Value thresholds  
✅ Sell macro runs without crashing  

### What Is Disabled
❌ Epic quest item protection  
❌ Items like "Ancient Sword Blade", "Celestial Fists", etc. are NOT protected  
❌ Epic items can now be accidentally sold if not in keep lists  

---

## Workaround for Users

If you need to protect epic items until this is fixed:

### Option 1: Manual Keep List
Add specific epic items you own to `sell_keep_exact.ini`:

```ini
[Items]
exact=Ancient Sword Blade/Celestial Fists/Fiery Avenger/your epic items here
```

### Option 2: Use Lore Protection
Many epic quest items are Lore. Enable Lore protection in `sell_flags.ini`:

```ini
protectLore=TRUE
```

This will protect many (but not all) epic quest items.

### Option 3: Use Quest Flag Protection
Some epic items have the Quest flag. Enable in `sell_flags.ini`:

```ini
protectQuest=TRUE
```

---

## Why Epic Protection Was Disabled

### Technical Issue
The epic items list is **extremely large** (~500+ items, split into 4 chunks of ~2000 characters each).

### Previous Attempt (Failed)
Tried to:
1. Load all 4 chunks separately
2. Check each chunk individually in EvaluateItem

### Problems:
1. **Buffer overflow risk** - Even separated, the chunks are at the 2048-char limit
2. **Performance** - 4 separate checks per item evaluation
3. **Complexity** - Hard to maintain and debug

---

## TODO: Better Implementation Needed

### Possible Solutions

**Option A: Use Lua Instead of Macro**
- Lua has better data structures (tables/arrays)
- No 2048-character string limit
- Can use ItemUI's existing epic item logic

**Option B: External Epic Check**
- Create a separate subroutine that checks epic status
- Call only when needed (not every item)
- Return boolean result

**Option C: Hash-Based Lookup**
- Generate a simple hash or ID from item name
- Store only the hash (much shorter)
- Check against hash list instead of full names

**Option D: Selective Epic Protection**
- Only protect epic items for your class
- Much smaller list (~50-80 items vs 500+)
- Load from `epic_items_<class>.ini` instead of master list

---

## Testing

After these changes:

1. ✅ Sell macro starts without errors
2. ✅ No "flagsFile already in use" error
3. ✅ Items can be sold normally
4. ✅ Other protections still work
5. ⚠️ Epic items are NOT protected

---

## Recommendation

For now:
1. **Use the workaround** - Add your specific epic items to keep list
2. **Enable Lore/Quest protection** - Catches most epic items
3. **Review before selling** - Use `/macro sell` (preview) before `/macro sell confirm`
4. **Plan better solution** - Discuss with team which option to implement

---

## Code Status

✅ No syntax errors  
✅ No linter errors  
✅ Macro runs successfully  
✅ No crashes  
⚠️ Epic protection disabled (temporary)  

The sell macro is now functional and safe to use, but users should be aware that epic quest items are not automatically protected.
