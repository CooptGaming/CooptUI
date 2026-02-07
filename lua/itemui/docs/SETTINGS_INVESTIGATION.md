# Settings & Configuration Investigation

**Date**: January 31, 2026  
**Purpose**: Investigate current settings system, apply vision statement, propose improvements  
**Status**: 🔍 INVESTIGATION

---

## Vision Statement Alignment

**User's Vision for ItemUI**:
1. **Superior experience** to EQ's default inventory (runs alongside it)
2. **Opens instantly** with all data ready (<50ms target) ✅ Achieved
3. **Smart auto-loot/auto-sell** with safe, intuitive filters
4. **Persistent local caching** for speed
5. **Template for future EQ UI companions** (AA, Merchant, Crafting)
6. **Prioritizes usability and accessibility** above all else
7. **Keeps future XML-based MQUI transition possible** (low priority)

**Applied to Settings**:
- Settings should be **immediately understandable** (plain language, no jargon)
- Settings should be **organized logically** by workflow/context
- Settings should **persist intelligently** (per-character where needed, account-wide where appropriate)
- Settings should have **helpful tooltips** explaining impact
- Settings should **validate input** and prevent invalid states
- Settings should be **accessible during use** (don't hide behind complex menus)

---

## Current State Analysis

### Configuration Files (INI-based)

#### File Structure
```
Macros/
├── sell_config/
│   ├── itemui_layout.ini         # UI layout, window sizes, column widths
│   ├── sell_flags.ini            # Sell protection flags
│   ├── sell_value.ini            # Sell value thresholds
│   ├── sell_keep_exact.ini       # Keep exact item names
│   ├── sell_keep_contains.ini    # Keep items containing keywords
│   ├── sell_always_sell_exact.ini
│   ├── sell_always_sell_contains.ini
│   └── sell_protected_types.ini  # Item types to protect
├── shared_config/
│   ├── valuable_exact.ini        # Shared valuable items (exact)
│   ├── valuable_contains.ini     # Shared valuable items (keywords)
│   ├── valuable_types.ini        # Shared valuable item types
│   └── epic_classes.ini          # Epic class filter
└── loot_config/
    ├── loot_flags.ini            # Loot flags
    ├── loot_value.ini            # Loot value thresholds
    ├── loot_sorting.ini          # Loot sorting preferences
    ├── loot_always_exact.ini     # Always loot (exact)
    ├── loot_always_contains.ini  # Always loot (keywords)
    ├── loot_always_types.ini     # Always loot (types)
    ├── loot_skip_exact.ini       # Skip items (exact)
    ├── loot_skip_contains.ini    # Skip items (keywords)
    └── loot_skip_types.ini       # Skip items (types)
```

**Total**: 20+ INI files across 3 directories

---

### Config Window Structure

#### Current Tabs
1. **ItemUI** - Window behavior + Sell settings
2. **Auto-Loot** - Loot settings
3. **Filters** - Item lists (Keep, Junk, Valuable, etc.)

#### ItemUI Tab Sections

**1. "How sell rules work"** (Collapsible, default open)
- Educational content explaining rule evaluation order
- Good! Helps users understand the system

**2. Window behavior** (6 settings)
- ✅ Snap to Inventory
- ✅ Snap to Merchant (Sell View)
- ✅ Sync Bank Window
- ✅ Suppress when loot.mac running

**3. Layout Setup** (3 buttons)
- ✅ Initial Setup (wizard mode)
- ✅ Capture as Default
- ✅ Reset to Default

**4. Sell protection** (7 flags)
- ✅ Protect No-Drop
- ✅ Protect No-Trade
- ✅ Protect Lore
- ✅ Protect Quest
- ✅ Protect Collectible
- ✅ Protect Heirloom
- ✅ Protect Epic

**5. Epic class filter** (Collapsible)
- Class checkboxes for epic item filtering

**6. Sell value thresholds** (3 numeric inputs)
- ✅ Min value (single)
- ✅ Min value (stack)
- ✅ Max keep value

**7. Filter lists** (Link to Filters tab)
- Redirects to Filters tab

#### Auto-Loot Tab Sections

**1. "How loot rules work"** (Collapsible, default open)
- Educational content

**2. Loot protection flags** (7 flags)
- Similar to sell flags

**3. Loot value thresholds** (3 numeric inputs)
- Min loot value (single)
- Min loot value (stack)
- Tribute override threshold

**4. Loot sorting** (radio buttons)
- Sort order for loot evaluation

**5. Filter lists** (Link to Filters tab)
- Redirects to Filters tab

#### Filters Tab
- Managed by `renderFiltersSection()`
- Keep lists (exact, contains, types)
- Junk lists (exact, contains)
- Protected types
- Valuable (shared) lists
- Skip lists (loot)
- Always loot lists

---

## Settings Analysis

### Categorization by Type

#### A. UI Behavior Settings (Layout persistence)
| Setting | Current Location | Scope | Persistence | Notes |
|---------|------------------|-------|-------------|-------|
| Window size (Inventory) | itemui_layout.ini | Per-character | INI | ✅ Good |
| Window size (Sell) | itemui_layout.ini | Per-character | INI | ✅ Good |
| Window size (Inv+Bank) | itemui_layout.ini | Per-character | INI | ✅ Good |
| Bank window position | itemui_layout.ini | Per-character | INI | ✅ Good |
| Column visibility | itemui_layout.ini | Per-character | INI | ✅ Good |
| Column widths | itemui_layout.ini | Per-character | INI | ✅ Good |
| Sort preferences | itemui_layout.ini | Per-character | INI | ✅ Good |
| Snap to Inventory | itemui_layout.ini | Per-character | INI | ✅ Good |
| Snap to Merchant | itemui_layout.ini | Per-character | INI | ✅ Good |
| Sync Bank Window | itemui_layout.ini | Per-character | INI | ✅ Good |
| Suppress when loot.mac | itemui_layout.ini | Per-character | INI | ✅ Good |

**Assessment**: ✅ Well-designed. Per-character persistence appropriate for UI preferences.

#### B. Sell Rule Settings (Shared across characters)
| Setting | Current Location | Scope | Persistence | Notes |
|---------|------------------|-------|-------------|-------|
| Protect No-Drop | sell_flags.ini | Account | INI | ✅ Good |
| Protect No-Trade | sell_flags.ini | Account | INI | ✅ Good |
| Protect Lore | sell_flags.ini | Account | INI | ✅ Good |
| Protect Quest | sell_flags.ini | Account | INI | ✅ Good |
| Protect Collectible | sell_flags.ini | Account | INI | ✅ Good |
| Protect Heirloom | sell_flags.ini | Account | INI | ✅ Good |
| Protect Epic | sell_flags.ini | Account | INI | ✅ Good |
| Epic class filter | epic_classes.ini (shared) | Account | INI | ✅ Good |
| Min sell value (single) | sell_value.ini | Account | INI | ✅ Good |
| Min sell value (stack) | sell_value.ini | Account | INI | ✅ Good |
| Max keep value | sell_value.ini | Account | INI | ✅ Good |

**Assessment**: ✅ Well-designed. Account-wide persistence appropriate for sell rules.

#### C. Loot Rule Settings (Shared across characters)
| Setting | Current Location | Scope | Persistence | Notes |
|---------|------------------|-------|-------------|-------|
| Loot flags (7 flags) | loot_flags.ini | Account | INI | ✅ Good |
| Min loot value (single) | loot_value.ini | Account | INI | ✅ Good |
| Min loot value (stack) | loot_value.ini | Account | INI | ✅ Good |
| Tribute override | loot_value.ini | Account | INI | ✅ Good |
| Loot sorting order | loot_sorting.ini | Account | INI | ✅ Good |

**Assessment**: ✅ Well-designed. Account-wide persistence appropriate.

#### D. Filter Lists (Shared, can be character-specific)
| List Type | Files | Scope | Notes |
|-----------|-------|-------|-------|
| Keep (sell) | sell_keep_exact/contains/types | Account | ✅ Good |
| Always sell | sell_always_sell_exact/contains | Account | ✅ Good |
| Valuable (shared) | valuable_exact/contains/types | Account | ✅ Good |
| Always loot | loot_always_exact/contains/types | Account | ✅ Good |
| Skip loot | loot_skip_exact/contains/types | Account | ✅ Good |

**Assessment**: ✅ Well-designed. Account-wide with potential for per-character overrides.

---

## Pain Points & Issues

### 1. **Configuration Fragmentation** ⚠️ MODERATE

**Issue**: 20+ INI files spread across 3 directories
- Hard to backup/restore full config
- Hard to share config with others
- Hard to understand file structure
- Manual INI editing error-prone

**Impact**: Medium (mostly affects advanced users editing INIs manually)

**Recommendation**: 
- Keep current structure (macro compatibility)
- Add export/import feature for full config
- Add "Open config folder" button
- Document file structure in README

---

### 2. **Settings Discovery** ⚠️ MODERATE

**Issue**: Some settings hidden or unclear
- "Filters" tab is separate from "ItemUI" tab
- Unclear which settings affect sell vs loot vs both
- No search/filter for settings
- Some tooltips could be more detailed

**Impact**: Medium (users may miss useful settings)

**Recommendation**:
- Add breadcrumbs/context indicators
- Improve tooltip consistency
- Add "Related settings" links
- Consider collapsible sections with better labels

---

### 3. **Value Input Validation** ⚠️ MINOR

**Issue**: Numeric inputs accept any text, validate on blur
- Can enter invalid values temporarily
- No visual feedback during typing
- No range guidance (min/max)

**Impact**: Low (validation prevents bad saves)

**Recommendation**:
- Add input masks (numbers only)
- Show valid ranges in tooltip
- Add +/- buttons for common adjustments
- Consider presets (e.g., "Vendor trash only", "Valuable items", "Everything")

---

### 4. **Redundant Settings?** ✅ NONE FOUND

**Assessment**: All settings serve distinct purposes. No redundancy detected.

---

### 5. **Missing Settings** 💡 OPPORTUNITY

**Potential additions**:
- ⏳ **Performance**: Toggle incremental scanning on/off
- ⏳ **Performance**: Adjust bags-per-frame (currently hardcoded to 2)
- ⏳ **Performance**: Toggle profile logging
- ⏳ **Macro Bridge**: Toggle debug mode
- ⏳ **Macro Bridge**: Adjust poll interval (currently 500ms)
- ⏳ **Cache**: Adjust cache TTL
- ⏳ **Filter Presets**: Quick-select common filter combinations
- ⏳ **Themes**: Color scheme selection
- ⏳ **Accessibility**: Font size adjustment
- ⏳ **Statistics**: Show/hide sell/loot stats panel

**Recommendation**: Add "Advanced" section for power users

---

## Layout & Organization Analysis

### Current Organization (3 tabs)

```
ItemUI Tab
├── How sell rules work (collapsible)
├── Window behavior (4 settings)
├── Layout Setup (3 buttons)
├── Sell protection (7 flags + epic filter)
├── Sell value thresholds (3 inputs)
└── Filter lists (link to Filters tab)

Auto-Loot Tab
├── How loot rules work (collapsible)
├── Auto Loot button
├── Loot protection flags (7 flags)
├── Loot value thresholds (3 inputs)
├── Loot sorting (radio buttons)
└── Filter lists (link to Filters tab)

Filters Tab
├── Keep exact/contains/types
├── Always sell exact/contains
├── Protected types
├── Valuable (shared) exact/contains/types
├── Skip exact/contains/types
└── Always loot exact/contains/types
```

### Issues with Current Organization

1. **Tab naming inconsistency**
   - "ItemUI" is ambiguous (whole UI is ItemUI)
   - "Auto-Loot" vs just "Loot"
   - "Filters" is unclear (filters for what?)

2. **Settings split across tabs**
   - Sell flags in "ItemUI", sell lists in "Filters"
   - Loot flags in "Auto-Loot", loot lists in "Filters"
   - Must switch tabs to configure one workflow

3. **Mixed concerns in "ItemUI" tab**
   - Window behavior (UI)
   - Layout setup (UI)
   - Sell rules (logic)
   - Mix of UI and logic settings

---

## Proposed Improvements

### Option A: Workflow-Oriented Organization (RECOMMENDED)

**Rationale**: Group settings by user workflow, not by technical category

```
General Tab (UI behavior, layout, performance)
├── Window Behavior
│   ├── Snap to Inventory
│   ├── Snap to Merchant
│   ├── Sync Bank Window
│   └── Suppress when loot.mac
├── Layout & Appearance
│   ├── Initial Setup wizard
│   ├── Capture as Default
│   ├── Reset to Default
│   ├── Column visibility (quick access)
│   └── [Future: Theme, Font size]
└── Performance (collapsible, advanced)
    ├── Incremental scanning
    ├── Bags per frame
    ├── Poll interval
    └── Cache TTL

Sell Rules Tab (all sell-related settings)
├── How sell rules work (collapsible)
├── Quick Actions
│   └── Auto Sell button
├── Protection Flags
│   ├── Protect No-Drop
│   ├── Protect No-Trade
│   ├── ... (7 flags total)
│   └── Epic class filter (collapsible)
├── Value Thresholds
│   ├── Min sell value (single)
│   ├── Min sell value (stack)
│   └── Max keep value
└── Filter Lists
    ├── Keep (exact/contains/types)
    ├── Always sell (exact/contains)
    └── Protected types

Loot Rules Tab (all loot-related settings)
├── How loot rules work (collapsible)
├── Quick Actions
│   └── Auto Loot button
├── Protection Flags
│   └── ... (7 flags)
├── Value Thresholds
│   ├── Min loot value (single)
│   ├── Min loot value (stack)
│   └── Tribute override
├── Sorting
│   └── Loot evaluation order
└── Filter Lists
    ├── Always loot (exact/contains/types)
    └── Skip (exact/contains/types)

Shared Tab (settings affecting both sell and loot)
├── Valuable Items
│   ├── Explanation: "These items are always kept when selling and always looted"
│   ├── Exact names
│   ├── Keywords (contains)
│   └── Item types
└── Epic Items
    ├── Epic class filter
    └── [Shared between Sell protection and Loot "always loot epic"]

Statistics Tab (NEW - optional)
├── Sell Statistics
│   ├── Total runs: N
│   ├── Items sold: N
│   ├── Items failed: N
│   ├── Avg duration: Xs
│   └── Reset button
└── Loot Statistics
    ├── Total runs: N
    ├── Avg duration: Xs
    └── Reset button
```

**Benefits**:
- ✅ All sell settings in one place
- ✅ All loot settings in one place
- ✅ Shared settings clearly labeled
- ✅ UI settings separated from logic
- ✅ Advanced settings collapsible (not overwhelming)

---

### Option B: Simplified 2-Tab (Alternative)

**Rationale**: Reduce tab count, use collapsible sections

```
Settings Tab
├── General (collapsible)
│   └── Window behavior, layout, performance
├── Sell Rules (collapsible, default open)
│   └── Flags, values, lists
└── Loot Rules (collapsible)
    └── Flags, values, sorting, lists

Lists Tab (all filter lists in one place)
├── Sell
│   ├── Keep
│   └── Always sell
├── Loot
│   ├── Always loot
│   └── Skip
└── Shared
    └── Valuable items
```

**Benefits**:
- ✅ Fewer tabs (2 vs 3)
- ✅ All lists in one place
- ⚠️ Longer scroll on Settings tab

---

### Option C: Keep Current + Minor Refinements (Minimal Change)

**Rationale**: Don't break user familiarity, just improve labels and organization

**Changes**:
1. Rename "ItemUI" tab → "General & Sell"
2. Rename "Auto-Loot" tab → "Loot Rules"
3. Rename "Filters" tab → "Item Lists"
4. Add "Quick Links" sections to reduce tab switching
5. Add collapsible "Advanced" section to General tab

**Benefits**:
- ✅ Minimal disruption
- ✅ Clearer tab names
- ✅ Improved navigation
- ⚠️ Doesn't fully solve fragmentation

---

## Recommended Improvements (Prioritized)

### Phase 1: Quick Wins (1-2 hours)

1. **Rename tabs** for clarity
   - "ItemUI" → "General & Sell"
   - "Auto-Loot" → "Loot Rules"  
   - "Filters" → "Item Lists"

2. **Improve tooltips** - add missing tooltips, enhance existing ones

3. **Add "Open config folder" button** - quick access to INI files

4. **Add numeric input validation** - visual feedback, ranges

### Phase 2: Organization (4-6 hours)

5. **Implement Option A** (Workflow-Oriented Organization)
   - 5 tabs: General, Sell, Loot, Shared, Statistics
   - Group related settings together
   - Add collapsible sections

6. **Add breadcrumbs** - "You are here: General > Window Behavior"

7. **Add search/filter** - find settings by keyword

### Phase 3: New Features (6-8 hours)

8. **Statistics panel** - show sell/loot stats (data already tracked by macro_bridge)

9. **Export/Import config** - backup/restore full configuration

10. **Config presets** - "Beginner", "Conservative", "Aggressive", "Custom"

11. **Advanced settings** - performance tuning, debug options

### Phase 4: Polish (2-4 hours)

12. **Settings validation** - warn about conflicting settings

13. **Settings reset** - per-section reset to defaults

14. **Quick setup wizard** - guide new users through essential settings

---

## Vision Statement Compliance Check

| Vision Element | Current Status | Recommendations |
|----------------|----------------|-----------------|
| **Instantly accessible** | ✅ Config window opens quickly | Keep current performance |
| **Smart & intuitive** | ✅ Good flag/value organization | Improve tab organization |
| **Safe** | ✅ Input validation exists | Add conflict detection |
| **Persistent** | ✅ INI-based persistence works | Add export/import |
| **Usable** | ⚠️ Some settings hard to find | Workflow-oriented reorg |
| **Accessible** | ⚠️ No accessibility features | Add font size, themes |
| **Template for future UIs** | ⚠️ Settings code inline in init.lua | Extract to settings module |

---

## Next Steps

### Investigation Complete ✅

1. **Document current system** ✅ DONE
2. **Identify pain points** ✅ DONE
3. **Propose improvements** ✅ DONE

### Recommended Implementation Order

1. **Phase 1 Quick Wins** (high impact, low effort)
2. **Phase 2 Organization** (high impact, moderate effort)
3. **Phase 3 New Features** (medium impact, high effort)
4. **Phase 4 Polish** (nice-to-have)

### Decision Point

**Which option should we implement?**
- **Option A** (Workflow-Oriented) - Most comprehensive, best UX
- **Option B** (Simplified 2-Tab) - Simpler, faster to implement
- **Option C** (Minimal Change) - Safest, least disruption

**Recommendation**: **Option A** with **Phase 1-2 implementation**

---

## Conclusion

The current settings system is **well-designed** from a technical perspective:
- ✅ Proper separation of concerns (UI vs logic)
- ✅ Appropriate persistence scope (per-char vs account)
- ✅ No redundant settings
- ✅ Good input validation

The main **opportunities for improvement** are:
- 📊 **Organization**: Workflow-oriented tabs reduce tab switching
- 🔍 **Discovery**: Better labels, tooltips, search
- 📈 **Visibility**: Statistics panel, advanced settings section
- 💾 **Portability**: Export/import, config presets
- ♿ **Accessibility**: Font size, themes, contrast

**Next Action**: Decide on implementation approach and prioritize phases.

---

**Status**: 🔍 Investigation complete, awaiting decision on implementation
