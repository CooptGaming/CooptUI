# CoopUI — ItemUI → Complete EverQuest UI Overhaul — Project Roadmap

**Document Version:** 1.0  
**Date:** January 29, 2026  
**Purpose:** Team lead analysis and logical next steps for modernizing ItemUI as it transitions into a complete UI overhaul for EverQuest using MacroQuest2.

---

## 1. Executive Summary

ItemUI (part of CoopUI) has evolved from a unified inventory/bank/sell interface into the **central hub** for item-related workflows in MQ2. It has already:

- **Replaced** `inventoryui` and `bankui` (both deprecated)
- **Consolidated** sell configuration (Keep/Junk/Protected) and loot configuration (Flags, Values, Sorting, Lists) into a single Config window
- **Integrated** with `sell.mac` and `loot.mac` via shared INI config paths
- **Implemented** most recommendations from the SELL_LOOT_FILTER_ANALYSIS document

The next phase is to **expand ItemUI into a full EverQuest UI overhaul** — a single, cohesive UI framework that covers inventory, bank, sell, loot, and future game systems.

---

## 2. Current State Assessment

### 2.1 What ItemUI Does Today (v1.2.0)

| Area | Features |
|------|----------|
| **Inventory** | Gameplay view (bag, slot, weight, flags); search; column visibility; shift+click to bank when bank open |
| **Sell** | Status, Keep/Junk buttons, Auto Sell, Show only sellable; same INI as SellUI |
| **Bank** | Separate window; Connected (live) vs Historic (snapshot); shift+click to move; right-click inspect |
| **Config** | ItemUI tab (window behavior, sell flags/values/lists) + Loot tab (flags, values, sorting, lists) |
| **Layout** | Setup mode; Capture as Default; Reset to Default; column widths; per-view lock states |

### 2.2 Related UIs (Ecosystem)

| UI | Status | Relationship to ItemUI |
|----|--------|------------------------|
| **inventoryui** | DEPRECATED | Replaced by ItemUI |
| **bankui** | Standalone | Replaced by ItemUI bank panel |
| **sellui** | Standalone | ItemUI sell view + Config replicate core features; SellUI has more tabs |
| **lootui** | Standalone | ItemUI Config Loot tab replicates core features |
| **epicquestui** | Separate | Epic quest helper; no direct integration |
| **boxhud** | Separate | Boxing HUD; different domain |
| **buttonmaster** | Separate | Button management; different domain |

### 2.3 Config Architecture

```
Macros/
├── sell_config/          # ItemUI layout + sell lists
│   ├── itemui_layout.ini  # Layout, column visibility, lock states
│   ├── sell_keep_*.ini
│   ├── sell_always_sell_*.ini
│   ├── sell_protected_types.ini
│   ├── sell_flags.ini
│   └── sell_value.ini
├── shared_config/         # Shared between sell + loot
│   ├── valuable_exact.ini
│   ├── valuable_contains.ini
│   └── valuable_types.ini
└── loot_config/           # Loot lists + flags/values/sorting
    ├── loot_always_*.ini
    ├── loot_skip_*.ini
    ├── loot_flags.ini
    ├── loot_value.ini
    └── loot_sorting.ini
```

### 2.4 Technical Debt & Gaps

1. **Monolithic init.lua** — ~3,400 lines in a single file; difficult to maintain and test.
2. **Undeclared globals** — `sellViewLocked`, `invViewLocked`, `bankViewLocked` are used but never declared with `local`.
3. **LootUI/SellUI still standalone** — Users can run both ItemUI and SellUI/LootUI; potential confusion and duplicate windows.
4. **No Loot view in ItemUI** — README notes: "LootUI stays separate; a future version may add a Loot/Config area." Config has Loot tab, but no live loot window.
5. **"Add from cursor"** — Implemented for exact lists only; not for contains/types (per SELL_LOOT_FILTER_ANALYSIS 4.3).
6. **Three-blocks pattern** — Each list still has separate Exact/Contains/Types sections; analysis recommended a unified "one add row + one list" UX.

---

## 3. SELL_LOOT_FILTER_ANALYSIS — Implementation Status

| Recommendation | Status | Notes |
|----------------|--------|-------|
| 4.1 Unify list management in ItemUI Config | ✅ Done | Sell tab has Keep, Junk, Protected; Loot tab has Shared, Always, Skip |
| 4.2 Plain-language labels | ⚠️ Partial | "Full item name", "Keyword", "Item type" used; some jargon remains |
| 4.3 Add from cursor | ✅ Done | Exact, contains, and types lists |
| 4.4 Simplify three-blocks pattern | ✅ Done | One Add row + merged list with badges |
| 4.5 Quick rules / How it works | ✅ Done | "How sell rules work" and "How loot rules work" in Config |
| 4.6 Keep macro behavior, improve docs | ✅ Done | "How sell rules work" and "How loot rules work" in Config |

---

## 4. Logical Next Steps (Prioritized)

### Phase 1: Stabilization & Code Quality (Short-term)

**Goal:** Reduce technical debt and improve maintainability before adding features.

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 1.1 | Declare `sellViewLocked`, `invViewLocked`, `bankViewLocked` as `local` at top of init.lua | ✅ Done | Fixes implicit globals |
| 1.2 | Extract config load/save logic into a `config.lua` module | ✅ Done | Reusable, testable |
| 1.3 | Extract sell/loot rule evaluation into `rules.lua` | ✅ Done | Shared by macros and UI |
| 1.4 | Add unit tests for rule evaluation (keep/junk/protected) | ✅ Done | Prevents regressions |

### Phase 2: UX Polish (Medium-term)

**Goal:** Complete the SELL_LOOT_FILTER_ANALYSIS recommendations and improve usability.

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 2.1 | Add "Add from cursor" for contains and types lists | ✅ Done | Per analysis 4.3 |
| 2.2 | Add "Quick rules" / "How it works" section in Config | ✅ Done | Per analysis 4.5 |
| 2.3 | Simplify list UX: one "Add" row + one list with type badges | ✅ Done | Per analysis 4.4 |
| 2.4 | Standardize terminology: "Always sell" vs "Junk" everywhere | ✅ Done | Per analysis 4.2 |

### Phase 3: Loot Integration (Medium-term)

**Goal:** Bring LootUI functionality into ItemUI so users have one window for all item workflows.

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 3.1 | Add Loot view/tab to ItemUI — live loot window when LootWnd open | ✅ Done (v1.6.0) | Shows corpse items with Will Loot / Will Skip; same filters as loot.mac |
| 3.2 | Deprecate LootUI with migration message (like inventoryui) | S | Clear upgrade path |
| 3.3 | Add loot.mac integration (e.g., "Auto Loot" button, status) | M | Parity with sell.mac |

### Phase 4: Modular Architecture (Long-term)

**Goal:** Split init.lua into modules for maintainability and extensibility.

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 4.1 | Create `itemui/` package: `init.lua`, `config.lua`, `rules.lua`, `views/` | L | Clean separation |
| 4.2 | Extract `views/inventory.lua`, `views/sell.lua`, `views/bank.lua`, `views/config.lua` | L | Each view < 500 lines |
| 4.3 | Create shared `itemui/theme.lua` for ImGui colors/spacing | M | Consistency with boxhud |
| 4.4 | Document module API for future contributors | S | Onboarding |

### Phase 5: SellUI Consolidation (Long-term)

**Goal:** Fully replace SellUI with ItemUI; single source of truth.

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 5.1 | Audit SellUI features not in ItemUI | S | Gap analysis |
| 5.2 | Add any missing SellUI features to ItemUI Config | M | Parity |
| 5.3 | Deprecate SellUI with migration message | S | Clear upgrade path |

### Phase 6: EverQuest UI Overhaul Vision (Future)

**Goal:** ItemUI becomes the foundation for a broader EQ UI overhaul.

| # | Task | Effort | Impact |
|---|------|--------|--------|
| 6.1 | Define "UI Overhaul" scope: which EQ systems to cover | — | Planning |
| 6.2 | Consider integration with EQ XML UIFiles (MQUI_*.xml) | L | Native look/feel |
| 6.3 | Explore plugin vs Lua architecture for performance-critical UIs | — | Technical decision |
| 6.4 | EpicQuestUI, BoxHUD, ButtonMaster: integrate or federate? | — | Architecture |

---

## 5. Immediate Action Items (This Sprint)

1. **Fix undeclared globals** — Add `local sellViewLocked, invViewLocked, bankViewLocked = true, true, true` near line 40 in init.lua.
2. **Update itemui_package** — Ensure itemui_package contains the latest init.lua and docs; add PROJECT_ROADMAP.md to package.
3. ~~**Document "How sell rules work"**~~ — ✅ Done. "How sell rules work" and "How loot rules work" collapsible sections in Config.
4. ~~**Add "Add from cursor" for contains/types**~~ — ✅ Done. sellListRow and renderListSection now support cursor-add for contains (keyword) and types (item type).

---

## 6. Success Metrics

- **User consolidation:** Users run CoopUI components (ItemUI for items, ScriptTracker for AAs); SellUI/LootUI deprecated into ItemUI.
- **Code quality:** init.lua split into modules; no file > 600 lines.
- **Config completeness:** All sell and loot list management in ItemUI Config; no need to edit INI by hand.
- **Documentation:** README, PROJECT_ROADMAP, and "How it works" section in Config.

---

## 7. References

- `lua/itemui/README.md` — User-facing documentation
- `lua/itemui/docs/SELL_LOOT_FILTER_ANALYSIS.md` — Expert analysis and recommendations
- `.cursor/agents/lua-ux-dev.md` — UX continuity guidelines
- `.cursor/agents/mq2-macro-dev.md` — Macro/Lua integration patterns
- `Macros/sell.mac`, `Macros/loot.mac` — Macro behavior and config format
