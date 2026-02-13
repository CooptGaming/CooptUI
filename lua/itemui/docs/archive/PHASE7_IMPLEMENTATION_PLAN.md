# Phase 7: View Extraction - Implementation Plan

**Date**: January 31, 2026  
**Status**: IN PROGRESS  
**Plan Reference**: `itemui_overhaul_plan_5c210c82.plan.md` - Phase 7

---

## Current Status

### ✅ Completed
1. **Views Already Extracted** (Phase 5):
   - `views/inventory.lua` - Inventory view
   - `views/sell.lua` - Sell view  
   - `views/bank.lua` - Bank view
   - `views/loot.lua` - Loot view
   - `views/config.lua` - Config window

2. **New Utility Modules Created** (Phase 7):
   - `utils/layout.lua` - Layout management (~500 lines extracted)
   - `utils/theme.lua` - Color palette and styling helpers (~200 lines)
   - `components/progressbar.lua` - Progress bar rendering (~150 lines)

### ❌ Remaining Work

**Problem**: init.lua is still **5,525 lines** (target: ~200 lines)

**Root Cause**: All the utility functions are still in init.lua:
- 113 local functions
- Scanning logic (~600 lines)
- Column management (~300 lines)
- Sort logic (~400 lines)
- Item helpers (~200 lines)  
- Config cache (~100 lines)
- Status messages, timers, etc. (~100 lines)

**Total extractable**: ~1,700+ lines of utility functions

---

## Revised Phase 7 Strategy

### Goal
Reduce `init.lua` from 5,525 lines to ~1,000-1,500 lines (realistic target)

**Note**: The 200-line target in the plan was aspirational. A more realistic target for a Lua ImGui app with this complexity is 1,000-1,500 lines of orchestration code.

### Approach

#### Option A: Aggressive Extraction (Original Plan)
Extract all utilities into focused modules:
- `utils/scan.lua` - All scanning logic (~600 lines)
- `utils/items.lua` - Item helpers (~200 lines)
- `utils/columns.lua` - Column management (~300 lines)
- `utils/sort.lua` - Sorting logic (~400 lines)

**Pros**: Maximum modularity, testability
**Cons**: High risk of breaking existing code, complex dependency injection

#### Option B: Pragmatic Integration (Recommended)
1. **Integrate existing modules** into init.lua (reducing ~200 lines)
   - Replace layout functions with `utils/layout.lua` calls
   - Update views to use `utils/theme.lua` for colors
   
2. **Extract high-value utilities** only:
   - Column management → `utils/columns.lua` (~300 lines saved)
   - Sort logic → `utils/sort.lua` (~400 lines saved)
   
3. **Leave scanning logic in init.lua** for now:
   - Tightly coupled to state variables
   - High risk of breakage
   - Can be extracted in future phase if needed

**Expected Result**: init.lua reduced to ~4,600 lines (net -900 lines, 16% reduction)

---

## Implementation Steps (Option B)

### Step 1: Integrate layout.lua
✅ Created `utils/layout.lua`  
❌ **TODO**: Update init.lua to use it

Changes needed:
1. Add `local layoutUtils = require('itemui.utils.layout')` to requires
2. Call `layoutUtils.init({...})` with state dependencies  
3. Replace all `getLayoutFilePath()` → `layoutUtils.getLayoutFilePath()`
4. Replace all `loadLayoutConfig()` → `layoutUtils.loadLayoutConfig()`
5. Replace all `saveLayoutToFile()` → `layoutUtils.saveLayoutToFile()`
6. etc. (15-20 function calls to update)
7. Delete ~500 lines of layout functions from init.lua

### Step 2: Integrate theme.lua in views
✅ Created `utils/theme.lua`  
❌ **TODO**: Update views to use it

Changes needed:
1. Add `local theme = require('itemui.utils.theme')` to each view
2. Replace hardcoded `ImVec4(0.2, 0.6, 0.2, 1)` → `theme.PushLootButton()`
3. Replace `ImGui.TextColored(ImVec4(...), text)` → `theme.TextSuccess(text)`
4. ~50-100 call sites across 5 views

### Step 3: Extract column management
❌ **TODO**: Create `utils/columns.lua`

Functions to extract (~300 lines):
- `initColumnVisibility()`
- `getVisibleColumns(view)`
- `getColumnKeyByIndex(view, index)`
- `autofitColumns(view, items, visibleCols)`
- Column width calculation logic

### Step 4: Extract sort logic
❌ **TODO**: Create `utils/sort.lua`

Functions to extract (~400 lines):
- `invalidateSortCache(view)`
- `getSortValByKey(item, colKey, view)`
- `getCellDisplayText(item, colKey, view)`  
- `isNumericColumn(colKey)`
- `makeComparator(getValFunc, col, dir, numericCols)`
- `getInvSortVal(item, col)`
- `getSellSortVal(item, col)`
- `getBankSortVal(item, col)`

---

## File Size Projections

| File | Current | After Phase 7 | Change |
|------|---------|---------------|--------|
| init.lua | 5,525 | ~4,600 | -925 (-17%) |
| utils/layout.lua | 0 | 500 | +500 (new) |
| utils/theme.lua | 0 | 200 | +200 (new) |
| utils/columns.lua | 0 | 300 | +300 (new) |
| utils/sort.lua | 0 | 400 | +400 (new) |
| **Total codebase** | **~10,000** | **~10,500** | **+500 lines** |

**Note**: Total lines increase because we're adding module boilerplate, but **init.lua complexity decreases** significantly.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Break existing functionality | Medium | High | Incremental changes, test after each step |
| Lua 200-local-variable limit | Low | Medium | Use dependency injection pattern |
| Performance regression | Low | Low | Modules are thin wrappers |
| Increased load time | Low | Low | MQ2 Lua require() is fast |

---

## Testing Checklist

After each integration step:
- [ ] ItemUI loads without errors
- [ ] Inventory view renders correctly
- [ ] Sell view renders correctly with merchant open
- [ ] Bank view renders correctly
- [ ] Config window opens and settings work
- [ ] Layout save/load works
- [ ] Column visibility toggles work
- [ ] Sorting works in all views
- [ ] Auto Sell button works
- [ ] No Lua errors in console

---

## Decision Point

**Question for User**: Which approach should we take?

**Option A**: Aggressive extraction (all utilities) - Higher risk, maximum modularity  
**Option B**: Pragmatic integration (layout + theme + columns + sort) - Lower risk, good improvement

**Recommendation**: Option B - Integrate what we've created, extract column/sort utils, leave scanning for later.

---

**Next Steps**: Await user decision, then proceed with implementation.
