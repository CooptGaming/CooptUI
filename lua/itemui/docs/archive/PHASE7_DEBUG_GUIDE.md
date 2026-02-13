# Phase 7: Bug Investigation - Debugging Guide

**Issue**: Inventory sort works once, then reverts to Name sort  
**Status**: DEBUG MODE ENABLED - Need trace logs  

---

## What I've Done

1. ✅ Added debug logging to `utils/layout.lua`
2. ✅ Enabled DEBUG mode (LayoutUtils.DEBUG = true)
3. ✅ Debug will trace:
   - When `scheduleLayoutSave()` is called
   - When `flushLayoutSave()` is called
   - What sort values are being saved
   - When loading from CACHE vs FILE
   - What sort values are loaded

---

## Your Debugging Steps

### Step 1: Fresh Start
1. Stop ItemUI: `/lua stop itemui`
2. Start ItemUI: `/lua run itemui`
3. Press `I` to open inventory

**Expected Console Output**:
```
[LayoutUtils DEBUG] Loading layout from FILE (cache miss or invalidated)
[LayoutUtils DEBUG] Loaded from FILE - InvSort: Name/1
```

---

### Step 2: Change Sort & Watch Logs
1. Click a column header (e.g., "Value") to change sort
2. **Watch console carefully** for debug messages

**Expected Console Output**:
```
[LayoutUtils DEBUG] scheduleLayoutSave() called - layoutDirty set to true
[LayoutUtils DEBUG] flushLayoutSave() called - layoutDirty: true
[LayoutUtils DEBUG] Saving layout - InvSort: Value/2, SellSort: Type/1, BankSort: Type/1
```

**If you DON'T see these messages**, the problem is the wrapper functions aren't being called!

---

### Step 3: Close and Reopen (First Time)
1. Close ItemUI (press `I` or type `/itemui`)
2. Reopen ItemUI (press `I` or type `/itemui`)

**Expected Console Output**:
```
[LayoutUtils DEBUG] Loading layout from FILE (cache miss or invalidated)
[LayoutUtils DEBUG] Loaded from FILE - InvSort: Value/2
```

**If it says "Loading from FILE" and shows Value**, the save/load cycle works!  
**If it says "Loading from CACHE"**, something is wrong with the reload flag.

---

### Step 4: Close and Reopen (Second Time) - THE CRITICAL TEST
1. Close ItemUI again
2. Reopen ItemUI again

**Expected Console Output (GOOD)**:
```
[LayoutUtils DEBUG] Loading layout from CACHE
[LayoutUtils DEBUG] Loaded from CACHE - InvSort: Value/2
```

**Or (ALSO GOOD)**:
```
[LayoutUtils DEBUG] Loading layout from FILE (cache miss or invalidated)
[LayoutUtils DEBUG] Loaded from FILE - InvSort: Value/2
```

**If it shows "InvSort: Name/1"**, the bug is confirmed and I know where to look!

---

## What to Report Back

Please copy/paste the **entire console log** for steps 1-4, including:
- All `[LayoutUtils DEBUG]` messages
- Any error messages
- What sort column you clicked on
- Whether the sort actually persisted or not

**Example Format**:
```
Step 2: Clicked "Value" column
Console showed:
[LayoutUtils DEBUG] scheduleLayoutSave() called - layoutDirty set to true
[LayoutUtils DEBUG] flushLayoutSave() called - layoutDirty: true
[LayoutUtils DEBUG] Saving layout - InvSort: Value/2, SellSort: Type/1, BankSort: Type/1

Step 3: Closed and reopened
Console showed:
[LayoutUtils DEBUG] Loading layout from FILE
[LayoutUtils DEBUG] Loaded from FILE - InvSort: Value/2
Result: Sort persisted! ✅

Step 4: Closed and reopened again
Console showed:
[LayoutUtils DEBUG] Loading layout from CACHE
[LayoutUtils DEBUG] Loaded from CACHE - InvSort: Name/1
Result: Sort reverted to Name! ❌ BUG CONFIRMED
```

---

## Additional Diagnostic

**If no debug messages appear at all**, the problem is that LayoutUtils.DEBUG isn't being set properly, which means the init() call might not be working.

**If schedule/flush messages appear but NO save message**, the save isn't happening (layoutDirty flag issue).

**If save message appears but shows wrong values**, the sortState table reference is broken.

---

## After Testing

Once you've gathered the logs, paste them in the chat and I'll:
1. Identify the exact failure point
2. Implement the fix
3. Re-test

---

**Status**: WAITING FOR DEBUG LOGS
