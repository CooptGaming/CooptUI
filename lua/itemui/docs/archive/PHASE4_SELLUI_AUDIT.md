# Phase 4: SellUI Consolidation - Feature Audit

**Date**: 2026-01-31  
**Task**: Complete audit of SellUI vs ItemUI to identify unique features for migration

---

## Executive Summary

After comprehensive line-by-line analysis of both `lua/sellui/init.lua` (1943 lines) and `lua/itemui/init.lua` (5245 lines), I have identified the following key differences and migration requirements.

---

## Feature Comparison Matrix

| Feature | SellUI | ItemUI | Status | Notes |
|---------|--------|--------|--------|-------|
| **UI Architecture** |
| Tabbed interface | ✅ 7 tabs | ✅ Unified view | ✓ Equivalent | ItemUI uses context-aware view switching |
| Auto-open on merchant | ✅ Auto-open/close | ✅ Auto-open/close | ✓ Equivalent | Both have this feature |
| Window positioning | ✅ Align to merchant | ✅ Align to inventory | ⚠️ **Different** | SellUI aligns to merchant; ItemUI to inventory |
| Layout management | ❌ None | ✅ Full setup system | ✓ ItemUI superior | ItemUI has `/itemui setup` workflow |
| **Sell View Features** |
| Keep/Junk buttons | ✅ Inline buttons | ✅ Inline buttons | ✓ Equivalent | Both have action buttons |
| Auto Sell button | ✅ Top button | ✅ Top button | ✓ Equivalent | Both trigger sell macro |
| Sell individual items | ✅ Always works | ✅ Always works | ✓ Equivalent | Manual override in both |
| Status indicators | ✅ 5 colors | ✅ Similar colors | ✓ Equivalent | Slightly different color schemes |
| Search & filter | ✅ Text + checkbox | ✅ Enhanced filter service | ✓ ItemUI superior | ItemUI has Phase 3 filter system |
| Sort columns | ✅ Basic sorting | ✅ Multi-column sort | ✓ ItemUI superior | ItemUI has advanced sort caching |
| Right-click inspect | ✅ Opens item window | ✅ Opens item window | ✓ Equivalent | Both support item inspect |
| **Config Management** |
| Config tabs | ✅ 6 separate tabs | ✅ Unified config window | ⚠️ **Different** | SellUI has separate tabs; ItemUI has collapsing sections |
| Inline editing | ✅ Add/remove items | ✅ Add/remove items | ✓ Equivalent | Both support inline config editing |
| Shared valuable items | ✅ Separate tab | ✅ In config window | ✓ Equivalent | Both support shared config |
| Keep/Junk/Protected | ✅ Separate tabs | ✅ In config window | ✓ Equivalent | Both support all list types |
| Flags configuration | ✅ With window settings | ✅ In config window | ⚠️ **Minor diff** | SellUI mixes flags with UI settings |
| Value thresholds | ✅ Separate tab | ✅ In config window | ✓ Equivalent | Both support all value configs |
| Epic protection | ✅ Full class system | ✅ Full class system | ✓ Equivalent | Both use epic_classes.ini |
| **Performance** |
| Scan throttling | ✅ Basic | ✅ Advanced caching | ✓ ItemUI superior | ItemUI has Phase 1-3 improvements |
| Cache invalidation | ✅ Full rescan | ✅ Granular cache | ✓ ItemUI superior | ItemUI has intelligent cache |
| State management | ✅ Basic locals | ✅ Core/state.lua | ✓ ItemUI superior | ItemUI has Phase 2 architecture |
| **Other Features** |
| Bank view | ❌ Not supported | ✅ Full bank support | ✓ ItemUI superior | Bank is ItemUI-only |
| Loot view | ❌ Not supported | ✅ Full loot support | ✓ ItemUI superior | Loot is ItemUI-only |
| Snapshots | ❌ Not supported | ✅ Character snapshots | ✓ ItemUI superior | ItemUI has storage.lua |
| Macro progress | ❌ Basic wait | ✅ Progress tracking | ✓ ItemUI superior | ItemUI tracks sell_progress.ini |

---

## Unique SellUI Features Requiring Migration

### 1. Window Positioning: Align to Merchant Window ⚠️ **PRIORITY**

**SellUI Implementation** (lines 1642-1679):
```lua
-- Option to align window to merchant window
local alignToMerchantWindow = true  -- Option to align window to merchant window

-- Position window relative to merchant window if enabled
if alignToMerchantWindow then
    local merchantWnd = mq.TLO.Window("MerchantWnd")
    if merchantWnd and merchantWnd.Open() then
        local merchantX = tonumber(merchantWnd.X()) or 0
        local merchantY = tonumber(merchantWnd.Y()) or 0
        local merchantWidth = tonumber(merchantWnd.Width()) or 0
        local merchantHeight = tonumber(merchantWnd.Height()) or 0
        
        if merchantX > 0 and merchantY > 0 and merchantWidth > 0 then
            local gap = 10
            local sellUIX = merchantX + merchantWidth + gap
            local sellUIY = merchantY
            ImGui.SetNextWindowPos(ImVec2(sellUIX, sellUIY), ImGuiCond.Always)
            
            if merchantHeight > 0 then
                ImGui.SetNextWindowSizeConstraints(ImVec2(0, merchantHeight), ImVec2(999999, merchantHeight))
                ImGui.SetNextWindowSize(ImVec2(0, merchantHeight), ImGuiCond.Always)
            end
        end
    end
end
```

**ItemUI Implementation** (lines 4531-4543):
- ItemUI has `alignToContext` which aligns to **InventoryWindow**, not MerchantWnd
- This is less useful for sell view since merchant window is the relevant context

**Migration Plan**:
- Add new option: `alignToMerchant` (boolean, default false)
- When in sell view AND `alignToMerchant` is true, align to MerchantWnd instead of InventoryWindow
- Add checkbox in Config window under "Window Settings" section
- Preserve existing `alignToContext` behavior for inventory/bank views

---

### 2. Config UI: Tabbed Interface (vs Collapsing Sections)

**SellUI Implementation**:
- 7 separate tabs: Inventory, Shared Valuable, Keep Lists, Always Sell, Protected Types, Flags, Values
- User clicks tab button to switch between config sections
- Each tab renders its own dedicated UI with full vertical space

**ItemUI Implementation**:
- Single Config window with collapsing sections
- All config options in one scrollable window
- Sections can be expanded/collapsed with header clicks

**Analysis**:
- **Trade-off**: Tabs provide more visual separation but require clicking between sections
- **Trade-off**: Collapsing sections allow viewing multiple sections at once but can be cramped
- **Decision**: ⚠️ **NO MIGRATION NEEDED** - ItemUI's collapsing sections are more efficient and consistent with the unified UI philosophy. Users can expand multiple sections at once if needed.

---

### 3. Flags Tab: Combined with Window Settings

**SellUI Implementation** (lines 1135-1227):
- Flags tab includes:
  - Window positioning option (`alignToMerchantWindow` checkbox)
  - Protection flags (protectNoDrop, protectNoTrade, etc.)
- All in one tab for convenience

**ItemUI Implementation**:
- Window settings in main UI header (Lock UI, Sync Bank, etc.)
- Protection flags in Config window under "Flags" section
- Separated by function

**Analysis**:
- **Decision**: ⚠️ **NO MIGRATION NEEDED** - ItemUI's separation is cleaner. Window settings should remain in header; flags in config window.

---

### 4. Minor UX Differences

**Status Color Scheme**:
- SellUI uses slightly different colors for status indicators
- ItemUI colors are more consistent with overall UI theme
- **Decision**: Keep ItemUI colors (more refined)

**Button Visual States**:
- SellUI has explicit "active" state colors (bright green/orange when item in list)
- ItemUI has similar but uses different shading
- **Decision**: Keep ItemUI implementation (already has this feature)

**Auto-refresh Logic**:
- SellUI only rescans when item count INCREASES (not decreases)
- ItemUI uses fingerprint-based change detection (more robust)
- **Decision**: Keep ItemUI implementation (superior)

---

## Migration Implementation Plan

### Task 1: Add Merchant Window Alignment Option

**Files to Modify**:
1. `lua/itemui/init.lua` - Add state variable and positioning logic
2. `lua/itemui/init.lua` - Add config UI checkbox

**Changes**:

```lua
-- In uiState table (around line 79):
local uiState = {
    -- ... existing fields ...
    alignToContext = false,
    alignToMerchant = false,  -- NEW: Align to merchant window when in sell view
    -- ... rest of fields ...
}

-- In saveLayoutToFile() (around line 571):
f:write("AlignToMerchant=" .. (uiState.alignToMerchant and "1" or "0") .. "\n")

-- In loadLayoutFromFile() (around line 769):
uiState.alignToMerchant = loadLayoutValue(layout, "AlignToMerchant", false)

-- In renderUI() positioning logic (around line 4531):
-- Replace existing alignToContext block with:
if merchOpen and uiState.alignToMerchant then
    -- Align to merchant window when in sell view
    local merchantWnd = mq.TLO.Window("MerchantWnd")
    if merchantWnd and merchantWnd.Open() then
        local merchantX = tonumber(merchantWnd.X()) or 0
        local merchantY = tonumber(merchantWnd.Y()) or 0
        local merchantWidth = tonumber(merchantWnd.Width()) or 0
        local merchantHeight = tonumber(merchantWnd.Height()) or 0
        
        if merchantX > 0 and merchantY > 0 and merchantWidth > 0 then
            local gap = 10
            local itemUIX = merchantX + merchantWidth + gap
            ImGui.SetNextWindowPos(ImVec2(itemUIX, merchantY), ImGuiCond.Always)
            
            -- Store position for bank window syncing
            uiState.itemUIPositionX = itemUIX
            uiState.itemUIPositionY = merchantY
            
            -- Optional: match height
            if merchantHeight > 0 then
                ImGui.SetNextWindowSizeConstraints(ImVec2(0, merchantHeight), ImVec2(999999, merchantHeight))
            end
        end
    end
elseif uiState.alignToContext then
    -- Existing InventoryWindow alignment logic
    -- ... (keep existing code)
end

-- In Config Window (around line 4261):
-- Add checkbox after "Snap to Inventory":
ImGui.Spacing()
local prevAlignMerch = uiState.alignToMerchant
uiState.alignToMerchant = ImGui.Checkbox("Snap to Merchant (Sell View)", uiState.alignToMerchant)
if prevAlignMerch ~= uiState.alignToMerchant then 
    scheduleLayoutSave() 
end
ImGui.SameLine()
ImGui.TextColored(ImVec4(0.6, 0.6, 0.6, 1), "(Position ItemUI to the right of merchant window)")
```

**Testing**:
1. Open ItemUI config, enable "Snap to Merchant"
2. Open merchant window
3. Verify ItemUI positions to the right of merchant
4. Verify height matches merchant window (optional)
5. Close merchant, reopen - verify positioning persists

---

### Task 2: Add Deprecation Warning to SellUI

**File to Modify**: `lua/sellui/init.lua`

**Changes**:

```lua
-- Add at top of file (around line 26):
local DEPRECATED = true
local DEPRECATION_MESSAGE = [[
╔════════════════════════════════════════════════════════════════╗
║                   ⚠️  DEPRECATION NOTICE ⚠️                    ║
╠════════════════════════════════════════════════════════════════╣
║  SellUI has been consolidated into ItemUI for a unified        ║
║  inventory management experience.                              ║
║                                                                ║
║  🔹 ItemUI now includes all SellUI features:                   ║
║     • Sell view with Keep/Junk buttons                         ║
║     • Auto Sell button                                         ║
║     • Full configuration management                            ║
║     • Plus bank, loot, and snapshot features!                  ║
║                                                                ║
║  📋 Migration Steps:                                           ║
║     1. Run: /lua run itemui                                    ║
║     2. Your config files are already compatible!               ║
║     3. Optional: Enable "Snap to Merchant" in ItemUI config    ║
║                                                                ║
║  ⚠️  SellUI will be removed in a future update.                ║
║                                                                ║
║  Press Ctrl+C in console to continue using SellUI (not rec)   ║
╚════════════════════════════════════════════════════════════════╝
]]

-- In main() function (around line 1819):
local function main()
    if DEPRECATED then
        print(DEPRECATION_MESSAGE)
        print("\ay[SellUI]\ax Waiting 10 seconds before starting (Ctrl+C to exit)...")
        mq.delay(10000)
        print("\ay[SellUI]\ax Starting deprecated SellUI. Please migrate to ItemUI.")
    end
    
    print(string.format("\ag[SellUI]\ax Sell UI v%s loaded", VERSION))
    -- ... rest of main()
end
```

**Visual Output**:
```
╔════════════════════════════════════════════════════════════════╗
║                   ⚠️  DEPRECATION NOTICE ⚠️                    ║
╠════════════════════════════════════════════════════════════════╣
║  SellUI has been consolidated into ItemUI for a unified        ║
║  inventory management experience.                              ║
║                                                                ║
║  🔹 ItemUI now includes all SellUI features:                   ║
║     • Sell view with Keep/Junk buttons                         ║
║     • Auto Sell button                                         ║
║     • Full configuration management                            ║
║     • Plus bank, loot, and snapshot features!                  ║
║                                                                ║
║  📋 Migration Steps:                                           ║
║     1. Run: /lua run itemui                                    ║
║     2. Your config files are already compatible!               ║
║     3. Optional: Enable "Snap to Merchant" in ItemUI config    ║
║                                                                ║
║  ⚠️  SellUI will be removed in a future update.                ║
║                                                                ║
║  Press Ctrl+C in console to continue using SellUI (not rec)   ║
╚════════════════════════════════════════════════════════════════╝
```

---

### Task 3: Update Documentation

**Files to Modify/Create**:
1. `lua/itemui/README.md` - Add migration section
2. `lua/itemui/docs/SELLUI_MIGRATION_GUIDE.md` - NEW: Comprehensive guide
3. `lua/sellui/README.md` - Add deprecation notice at top

**Changes to `lua/itemui/README.md`** (add new section):

```markdown
## Migrating from SellUI

ItemUI now includes all SellUI features in a unified interface. Your existing configuration files are fully compatible.

### What Changed

- **Sell view** is now part of ItemUI (opens automatically when merchant window opens)
- **Config management** moved to ItemUI's unified Config window
- **Keep/Junk buttons** work the same way in ItemUI's sell view
- **New features** available: Bank view, Loot view, Snapshots, Advanced filtering

### Migration Steps

1. **Stop SellUI**: `/lua stop sellui` (if running)
2. **Start ItemUI**: `/lua run itemui`
3. **Optional**: Enable "Snap to Merchant" in ItemUI config for SellUI-like positioning
4. **Done!** All your config files (`sell_config/`) work as-is

### Feature Mapping

| SellUI Feature | ItemUI Equivalent |
|----------------|-------------------|
| Inventory tab | Sell view (auto-switches when merchant opens) |
| Keep/Junk buttons | Same buttons in sell view |
| Auto Sell button | Same button at top of sell view |
| Config tabs | Config window (click "Config" button) |
| Align to merchant | "Snap to Merchant" option in config |
| Search & filter | Enhanced filter system (Phase 3) |

### Why Consolidate?

- **Unified experience**: One UI for inventory, bank, sell, and loot
- **Better performance**: Shared caching and state management
- **More features**: Bank snapshots, loot evaluation, advanced filtering
- **Easier maintenance**: Single codebase with modular architecture
- **Future-ready**: Foundation for Phase 5-7 improvements

For detailed migration information, see [SELLUI_MIGRATION_GUIDE.md](docs/SELLUI_MIGRATION_GUIDE.md).
```

---

## Verification Checklist

After migration, verify the following:

- [ ] **Feature parity**: All SellUI features work in ItemUI
  - [ ] Sell view opens when merchant opens
  - [ ] Keep/Junk buttons work and update status immediately
  - [ ] Auto Sell button runs sell macro
  - [ ] Search and filter work
  - [ ] Sort columns work
  - [ ] Right-click inspect works
  - [ ] Config window manages all lists
  - [ ] Flags and values editable
- [ ] **New features work**:
  - [ ] "Snap to Merchant" option in config
  - [ ] Window positions to right of merchant when enabled
  - [ ] Height matches merchant window (optional)
- [ ] **Deprecation warning**:
  - [ ] SellUI shows deprecation message on load
  - [ ] Message is clear and helpful
  - [ ] 10-second delay gives user time to read
- [ ] **Documentation**:
  - [ ] ItemUI README has migration section
  - [ ] Migration guide is comprehensive
  - [ ] SellUI README has deprecation notice
- [ ] **Config compatibility**:
  - [ ] Existing sell_config/ files work unchanged
  - [ ] Keep/Junk lists from SellUI work in ItemUI
  - [ ] No data loss during migration

---

## Conclusion

**Summary**:
- SellUI has **1 unique feature** requiring migration: Align to Merchant Window
- All other SellUI features already exist in ItemUI (with superior implementations)
- Migration is **minimal** - just add merchant alignment option
- Deprecation warning ensures smooth user transition
- Config files are **fully compatible** - zero user data migration needed

**Recommendation**:
Proceed with Phase 4 implementation as outlined above. The migration is straightforward and low-risk.
