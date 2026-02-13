# Phase 7: Layout Integration Testing Guide

**Date**: January 31, 2026  
**Integration**: utils/layout.lua → init.lua  
**Changes**: 427 lines reduced, 18 functions delegated to module

---

## Pre-Test Checklist

### Syntax Validation
- [ ] Lua syntax check passes (no parse errors)
- [ ] All require statements present
- [ ] layoutUtils.init() called with correct dependencies

### Quick Smoke Test
1. Load ItemUI: `/lua run itemui`
2. Check for Lua errors in console
3. If loads successfully, proceed to functional tests

---

## Functional Test Suite

### Test 1: Basic UI Load ⚡ CRITICAL
**Objective**: Verify ItemUI loads without errors

**Steps**:
1. Open EverQuest
2. Run: `/lua run itemui`
3. Observe console output

**Expected**:
```
[ItemUI] Item UI v1.6.0 loaded. /itemui or /inv to toggle. /dosell, /doloot for macros.
```

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 2: Window Display ⚡ CRITICAL
**Objective**: Verify main window renders

**Steps**:
1. Press `I` key or type `/itemui`
2. Observe if ItemUI window appears

**Expected**:
- ItemUI window opens
- Shows inventory items
- No blank/empty window

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 3: Layout Load from INI 🔧 HIGH PRIORITY
**Objective**: Verify layout settings load correctly

**Steps**:
1. Check if window size matches saved layout
2. Verify window position is correct
3. Check if UI is locked/unlocked as configured

**Expected**:
- Window opens at saved size
- Window at saved position
- Lock state matches config

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 4: Column Visibility 🔧 HIGH PRIORITY
**Objective**: Verify column visibility loads/saves

**Steps**:
1. Open ItemUI
2. Right-click column header
3. Toggle a column off/on
4. Close and reopen ItemUI
5. Verify column visibility persisted

**Expected**:
- Right-click menu shows columns
- Toggling works immediately
- Settings persist across reloads

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 5: Window Resize & Save 🔧 HIGH PRIORITY
**Objective**: Verify layout saving works

**Steps**:
1. Resize ItemUI window
2. Close ItemUI (`/lua stop itemui`)
3. Reopen ItemUI
4. Check if size persisted

**Expected**:
- Window remembers new size
- No errors on save/load

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 6: Setup Mode 🔧 MEDIUM PRIORITY
**Objective**: Verify setup mode still works

**Steps**:
1. Type `/itemui setup`
2. Click through setup steps
3. Save layouts for each view

**Expected**:
- Setup mode activates
- Can resize windows
- "Save Inventory Size" button works
- "Save Sell Size" button works
- "Save Inv+Bank Size" button works

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 7: Capture Default Layout 🔧 MEDIUM PRIORITY
**Objective**: Verify captureCurrentLayoutAsDefault works

**Steps**:
1. Open ItemUI config window
2. Go to "General" tab
3. Find "Capture Current as Default" button
4. Click it
5. Observe console for success message

**Expected**:
```
[ItemUI] Current layout configuration captured as default! (Window sizes, positions, column widths, column visibility, and all settings)
```

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 8: Reset to Default Layout 🔧 MEDIUM PRIORITY
**Objective**: Verify resetLayoutToDefault works

**Steps**:
1. Resize window to unusual size
2. Open config → General
3. Click "Reset to Default" button
4. Observe window returns to default size

**Expected**:
```
[ItemUI] Layout reset to default! (Window sizes, column visibility, and settings restored)
[ItemUI] Note: Column widths are saved separately by ImGui. Restart ItemUI to see column width changes.
```

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 9: Sorting Persistence 🔧 MEDIUM PRIORITY
**Objective**: Verify sort state saves/loads

**Steps**:
1. Click a column header to sort
2. Close ItemUI
3. Reopen ItemUI
4. Verify sort column and direction persisted

**Expected**:
- Sort indicator on correct column
- Sort direction correct
- Data sorted correctly

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 10: Bank Panel 🔧 LOW PRIORITY
**Objective**: Verify bank panel layout works

**Steps**:
1. Open bank in game
2. Click "Bank" button in ItemUI
3. Verify bank panel appears on right
4. Resize combined window
5. Close and reopen
6. Verify bank panel size persisted

**Expected**:
- Bank panel slides out
- Width saves correctly
- Position persists

**Actual**: _____________________

**Pass/Fail**: ⬜

---

### Test 11: Merchant View Layout 🔧 LOW PRIORITY
**Objective**: Verify sell view layout works

**Steps**:
1. Open merchant window
2. ItemUI switches to sell view
3. Resize window
4. Close merchant, reopen
5. Verify sell view size persisted

**Expected**:
- Switches to sell view automatically
- Sell view size independent of inv view
- Size persists

**Actual**: _____________________

**Pass/Fail**: ⬜

---

## Error Scenarios

### Test E1: Missing INI File
**Steps**:
1. Delete or rename `itemui_layout.ini`
2. Load ItemUI
3. Verify defaults applied, no crash

**Expected**:
- Uses default sizes
- No errors
- Creates new INI on first save

**Pass/Fail**: ⬜

---

### Test E2: Corrupted INI
**Steps**:
1. Add garbage text to `itemui_layout.ini`
2. Load ItemUI
3. Verify graceful handling

**Expected**:
- Falls back to defaults
- No crash
- May log warning

**Pass/Fail**: ⬜

---

## Performance Checks

### Load Time
- **Before**: _____ ms (if known)
- **After**: _____ ms
- **Change**: _____ ms

### Memory Usage
- Check for memory leaks during repeated open/close cycles
- **Status**: ⬜ OK / ⬜ Issue

---

## Critical Bugs Found

| # | Severity | Description | Status |
|---|----------|-------------|--------|
| 1 | | | |
| 2 | | | |
| 3 | | | |

---

## Test Summary

**Total Tests**: 13 (11 functional + 2 error scenarios)  
**Passed**: _____  
**Failed**: _____  
**Skipped**: _____  

**Overall Status**: ⬜ PASS / ⬜ FAIL / ⬜ PARTIAL

---

## Notes

_Add any observations, warnings, or additional information here_

---

## Sign-Off

**Tester**: _____________________  
**Date**: _____________________  
**Recommendation**: ⬜ Deploy / ⬜ Fix Issues / ⬜ Needs More Testing
