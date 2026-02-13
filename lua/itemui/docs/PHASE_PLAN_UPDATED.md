# ItemUI Overhaul - Updated Phase Plan

**Date**: January 31, 2026  
**Status**: Phases 1-5 Complete, Phase 6+ Planned

Implementation details for each phase are in `lua/itemui/docs/archive/`. This file and [PROJECT_ROADMAP.md](PROJECT_ROADMAP.md) are the source of truth for current status and next steps.

---

## Phase Overview

### ✅ Phase 1: State & Cache Refactor (Foundation) - COMPLETE
**Status**: ✅ COMPLETE  
**Files**: `core/state.lua`, `core/cache.lua`, `core/events.lua`  
**Achievement**: Reactive state management, granular cache invalidation

---

### ✅ Phase 2: Instant Open Performance (PRIORITY) - COMPLETE
**Status**: ✅ COMPLETE  
**Achievement**: **15ms UI open time** (70% faster than 50ms target!)  
**Features**: Snapshot-first loading, incremental scanning (2 bags/frame)

---

### ✅ Phase 3: Unified Filter System (UX) - COMPLETE
**Status**: ✅ COMPLETE  
**Files**: `services/filter_service.lua`, `components/filters.lua`, `components/searchbar.lua`  
**Features**: Advanced filtering, presets, persistence, debouncing

---

### ✅ Phase 4: SellUI Consolidation (Continuity) - COMPLETE
**Status**: ✅ COMPLETE  
**Achievement**: SellUI deprecated, all features consolidated, zero breaking changes  
**Documentation**: Migration guide, deprecation notice

---

### ✅ Phase 5: Macro Integration Improvement (Integration) - COMPLETE
**Status**: ✅ COMPLETE  
**Files**: `services/macro_bridge.lua`  
**Achievement**: **93% reduction** in macro polling overhead  
**Features**: Throttled polling (500ms), event-driven, statistics tracking

---

### ⏳ Phase 6: Settings & Configuration Overhaul (Usability) - NEW!
**Status**: ⏳ PLANNED  
**Reference**: `archive/SETTINGS_INVESTIGATION.md`  
**Effort**: 10-15 hours total

#### Phase 6.1: Quick Wins (1-2 hours)
- Rename config tabs for clarity
- Improve tooltips with examples
- Add "Open config folder" button
- Better numeric input validation
- Input masks for numbers

#### Phase 6.2: Workflow-Oriented Reorganization (4-6 hours)
- 5-tab structure: General, Sell, Loot, Shared, Statistics
- All sell settings in one place
- All loot settings in one place
- Breadcrumbs navigation
- Collapsible advanced sections

#### Phase 6.3: Statistics Panel (2-3 hours)
- Display macro_bridge statistics
- Sell stats: runs, items sold/failed, duration
- Loot stats: runs, duration
- Visual indicators (success rates, trends)
- Reset statistics button

#### Phase 6.4: Enhanced Features (3-4 hours)
- Export/import full config
- Config presets (Beginner, Conservative, Aggressive)
- Settings search/filter
- Per-section reset buttons

**Benefits**:
- Settings organized by workflow (no tab switching for one task)
- Statistics visible (leverages Phase 5 data)
- Improved discoverability (search, breadcrumbs, tooltips)
- Enhanced usability (presets, export/import)
- Template for future UIs

---

### ⏳ Phase 7: View Extraction (Maintainability) - UPDATED
**Status**: ⚠️ PARTIALLY COMPLETE (views exist, config not integrated)  
**Effort**: 4-6 hours remaining

**Completed**:
- ✅ `views/inventory.lua` - Extracted and integrated
- ✅ `views/sell.lua` - Extracted and integrated
- ✅ `views/bank.lua` - Extracted and integrated
- ✅ `views/loot.lua` - Extracted and integrated

**Remaining**:
- ⏳ Complete `views/config.lua` integration (~700 lines)
- ⏳ Create `components/itemtable.lua` (reusable table)
- ⏳ Create `components/progressbar.lua` (reusable progress bar)
- ⏳ Refactor `init.lua` to ~200 lines (currently 5400)
- ⏳ Extract layout to `utils/layout.lua`
- ⏳ Extract theme to `utils/theme.lua`

---

### ⏳ Phase 8: Advanced Features (Enhancements)
**Status**: ⏳ PLANNED  
**Priority**: Low (polish and innovation)

**Features**:
- Item comparison tooltips
- Drag-and-drop item management
- Bulk operations
- Smart suggestions
- Item value trending
- Search highlighting
- Keyboard shortcuts
- Theme system (color schemes)
- Accessibility (font size, contrast)

---

## Implementation Timeline

### Immediate Priority
1. ✅ **Phases 1-5 Complete** - Foundation solid, performance excellent
2. ⏳ **Phase 6 Next** - Settings overhaul aligns with vision (usability)
3. ⏳ **Phase 7 After** - Complete view extraction
4. ⏳ **Phase 8 Future** - Polish and enhancements

### Effort Estimates
- **Phase 6**: 10-15 hours (settings overhaul)
- **Phase 7**: 4-6 hours (complete view extraction)
- **Phase 8**: 15-20 hours (advanced features)

**Total Remaining**: ~30-40 hours for full overhaul completion

---

## Why Phase 6 Added?

**User Request**: "Investigate settings UI and apply vision statement"

**Rationale**:
1. **Vision Alignment**: Settings must be as intuitive as the rest of the UI
2. **Statistics Ready**: Phase 5 macro_bridge tracks data, but no UI to display it
3. **Usability Gap**: Settings split across tabs, hard to configure workflows
4. **Template Value**: Well-designed settings become template for future UIs
5. **Accessibility**: Settings should support different user skill levels

**Perfect Timing**:
- Follows Phase 5 (statistics data available)
- Before Phase 7 (config view extraction will be easier after reorganization)
- Leverages all prior infrastructure (events, cache, services)

---

## Success Criteria (Updated)

### Phase 1-5 (Achieved)
✅ 15ms UI open time (target: <50ms)  
✅ 93% reduction in macro polling  
✅ Rich filtering with presets  
✅ SellUI consolidated  
✅ Zero breaking changes  

### Phase 6 (New Targets)
🎯 All sell settings in one tab  
🎯 All loot settings in one tab  
🎯 Statistics panel showing macro data  
🎯 Settings search functional  
🎯 Export/import working  
🎯 Config presets available  

### Phase 7-8 (Future)
🎯 init.lua < 200 lines  
🎯 All views < 700 lines  
🎯 Theme system implemented  
🎯 Advanced features delivered  

---

## Phase Dependency Chart

```
Phase 1 (State/Cache)
    ↓
Phase 2 (Performance) ← Foundation for all
    ↓
Phase 3 (Filters) ← Uses Phase 1 infrastructure
    ↓
Phase 4 (SellUI) ← Consolidation
    ↓
Phase 5 (Macro Bridge) ← Events + Statistics
    ↓
Phase 6 (Settings) ← Uses Phase 5 stats, prepares for Phase 7
    ↓
Phase 7 (View Extraction) ← Completes modularization
    ↓
Phase 8 (Advanced) ← Polish on solid foundation
```

---

## Updated TODO List

### Current Sprint (Phase 6)
- [ ] 6.1: Quick wins (rename tabs, tooltips, validation)
- [ ] 6.2: Workflow-oriented reorganization (5 tabs)
- [ ] 6.3: Statistics panel (display macro_bridge data)
- [ ] 6.4: Enhanced features (export/import, presets, search)

### Next Sprint (Phase 7)
- [ ] 7.1: Complete config view integration
- [ ] 7.2: Create reusable components (itemtable, progressbar)
- [ ] 7.3: Refactor init.lua to orchestrator
- [ ] 7.4: Extract utils (layout, theme)

### Future (Phase 8)
- [ ] 8.1: Item comparison tooltips
- [ ] 8.2: Drag-and-drop
- [ ] 8.3: Bulk operations
- [ ] 8.4: Smart suggestions
- [ ] 8.5: Theme system
- [ ] 8.6: Accessibility features

---

## Documentation Status

### Completed
- ✅ `PHASE1_INSTANT_OPEN_IMPLEMENTATION.md`
- ✅ `PHASE2_STATE_CACHE_IMPLEMENTATION.md`
- ✅ `PHASE3_FILTER_SYSTEM_IMPLEMENTATION.md`
- ✅ `PHASE4_IMPLEMENTATION_SUMMARY.md`
- ✅ `PHASE5_IMPLEMENTATION_SUMMARY.md`
- ✅ `PHASES_1_TO_5_COMPLETE_SUMMARY.md`
- ✅ `SETTINGS_INVESTIGATION.md` (NEW!)

### Planned
- ⏳ `PHASE6_SETTINGS_IMPLEMENTATION.md` (after Phase 6 complete)
- ⏳ `PHASE7_VIEW_EXTRACTION_SUMMARY.md` (after Phase 7 complete)
- ⏳ `PHASE8_ADVANCED_FEATURES.md` (after Phase 8 complete)

---

**Status**: Phase 6 added to plan, ready for implementation!
