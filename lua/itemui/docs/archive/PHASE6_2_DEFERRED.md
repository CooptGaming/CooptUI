# Phase 6.2: Workflow-Oriented Reorganization - DEFERRED

**Status**: ⏸️ DEFERRED until after Phase 7  
**Date**: January 31, 2026  
**Reason**: Strategic decision to extract config to separate module first

---

## Decision Rationale

Working on a 5500-line `init.lua` file to reorganize 320+ lines of config tab content proved complex and error-prone. Better approach:

1. **Phase 7 First**: Extract config window to `views/config.lua` (~700 lines)
2. **Then Phase 6.2**: Reorganize in the clean, dedicated module
3. **Much Cleaner**: Working in focused 700-line file vs 5500-line monolith

---

## Phase 6.1 Status: ✅ COMPLETE

The following improvements from Phase 6.1 are **KEPT** and working:

### 1. Tab Names Improved
- "ItemUI" → "General & Sell" (clearer scope)
- "Auto-Loot" → "Loot Rules" (more descriptive)
- "Filters" → "Item Lists" (indicates content)

### 2. Enhanced Tooltips
- All window behavior settings have detailed 3-line tooltips with examples
- Better explanations of snap behavior, sync options, suppression logic

### 3. "Open Config Folder" Button
- Quick access to INI files via Windows Explorer
- Located next to "Reload from files" button
- Helpful for manual editing and backups

### 4. Improved Numeric Inputs
- Currency formatting with `formatCurrency()` helper
- Shows readable values (e.g., "5p 3g 2s 1c" instead of just "5321")
- Decimal-only input validation
- Better tooltips with examples and edge cases
- Wider inputs (120px) for better readability

---

## Phase 6.2 Plan: To Be Implemented After Phase 7

Once config is extracted to `views/config.lua`, implement this structure:

### Tab 1: General
- Window Behavior (snap settings, suppress loot.mac)
- Layout & Appearance (Initial Setup, Capture/Reset Default)
- [Future] Performance Settings (collapsible advanced)

### Tab 2: Sell Rules
- How sell rules work (collapsible)
- Auto Sell button (quick action)
- Sell Protection Flags (7 flags)
- Sell Value Thresholds (3 inputs with currency formatting)
- Sell Filter Lists (Keep, Always Sell, Protected Types)

### Tab 3: Loot Rules
- How loot rules work (collapsible)
- Auto Loot button (quick action)
- Loot Flags (7 flags)
- Loot Value Thresholds (3 inputs)
- Loot Sorting Settings
- Loot Filter Lists (Always Loot, Skip)

### Tab 4: Shared
- Explanation of shared settings
- Valuable Items (affects both sell and loot)
- Epic Class Filter (affects both sell and loot)

### Tab 5: Statistics
- Sell Statistics (from macro_bridge)
- Loot Statistics (from macro_bridge)
- Reset Statistics button

---

## Benefits of This Approach

### For Phase 7 Extraction:
- Clean baseline to extract from
- Phase 6.1 improvements make config more user-friendly already
- No partial/broken work to migrate

### For Phase 6.2 Implementation:
- Working in focused `views/config.lua` module (700 lines)
- Easier to test and validate changes
- Cleaner git diffs and code review
- Better separation of concerns

---

## Handoff Notes for Future Work

When resuming Phase 6.2 after Phase 7:

1. **Reference files to review**:
   - `lua/itemui/docs/SETTINGS_INVESTIGATION.md` - Full analysis of current structure
   - `lua/itemui/docs/PHASE6_1_QUICK_WINS_COMPLETE.md` - What's already done
   - Plan file section on Phase 6 (lines 318-381)

2. **Key functions in config window**:
   - `renderConfigWindow()` - Main config window render
   - `renderFiltersSection()` - Filter lists (Sell, Valuable, Loot sub-tabs)
   - `renderFilterSection()` - Reusable filter UI component
   - Various helper functions for conflict detection and list management

3. **Important state variables**:
   - `filterState.configTab` - Current tab (1-3 currently, will be 1-5)
   - `filterState.filterSubTab` - Sub-tab in Item Lists (Sell, Valuable, Loot)
   - Config caches: `configSellFlags`, `configSellValues`, `configLootFlags`, etc.

4. **Cache invalidation calls needed**:
   - `invalidateSellConfigCache()` - When sell settings change
   - `invalidateLootConfigCache()` - When loot settings change
   - Both called when epic classes or valuable items change

---

## Current File State

After revert, `init.lua` is back to:
- ✅ Phase 6.1 improvements (tab names, tooltips, Open Config button, currency formatting)
- ✅ Clean, working 3-tab structure
- ✅ Ready for Phase 7 extraction

---

**Next Action**: Proceed with Phase 7 (Config Extraction) then return to Phase 6.2
