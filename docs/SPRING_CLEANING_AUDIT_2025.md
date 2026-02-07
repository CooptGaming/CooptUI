# EQ UI Overhaul – Spring Cleaning Audit (January 2025)

**Purpose:** Comprehensive audit of the MacroQuest2 EQ UI overhaul project. Identifies outdated code, duplication, sync gaps, and provides recommendations for player experience and future improvements.

**Context:** Perky's Crew and similar private servers allow MQ2; this project targets a unified, performant item management UI for EverQuest players.

---

## 1. Executive Summary

The project has evolved into a solid **ItemUI-centric** architecture with ItemUI as the hub for inventory, bank, and sell workflows. Several areas need attention:

| Category | Status | Action |
|----------|--------|--------|
| **ItemUI sync** | ✅ Done | Ran sync.ps1; ItemUI now has readSharedListValue |
| **itemui_package** | ✅ Deprecated | Added deprecation notice in README_INSTALL.txt |
| **Dead code** | ✅ Done | Removed itemconfig; consolidated ImGuiFileDialog |
| **LootUI config** | ✅ Done | Migrated to itemui.config (readSharedListValue) |
| **BankUI deprecation** | ✅ Done | Redirect to ItemUI; added /bankui alias in ItemUI |
| **Backup folders** | ℹ️ Review | Archive or prune old backups |
| **master_items.json** | ✅ Fixed | Was corrupted (`i{` → `{`) |

---

## 2. Package & Sync Analysis

### 2.1 Source of Truth

- **`lua/itemui/`** – Main development source. Uses `readSharedListValue` (chunked list support for 2048-char MQ limit).
- **`ItemUI/`** – Deployment package. Synced via `ItemUI/sync.ps1` from `lua/itemui` and `Macros/`.
- **`itemui_package/`** – Older minimal package. **Out of sync**; uses `readSharedINIValue` (no chunked support).

### 2.2 Sync Gaps

| File/Area | lua/itemui (Source) | ItemUI (Deploy) | itemui_package |
|-----------|---------------------|-----------------|----------------|
| config.lua | Has `readSharedListValue` | Uses `readSharedINIValue` only | Same as ItemUI |
| init.lua | Uses `config.readSharedListValue` | Uses `readSharedINIValue` | Same as ItemUI |
| storage.lua | Present | Present | **Missing** |
| rules.lua | Uses readSharedListValue for list edits | Uses readSharedINIValue | Same as ItemUI |

**Impact:** ItemUI and itemui_package will fail or truncate lists when shared valuable lists exceed ~2000 chars (MQ macro buffer limit). Main `lua/itemui` handles chunked reads/writes correctly.

**Recommendation:**
1. Run `ItemUI/sync.ps1` to bring ItemUI up to date.
2. Deprecate `itemui_package` – add README stating it's obsolete; users should use main `lua/` and `Macros/` or the ItemUI deployment package.

---

## 3. Dead or Redundant Code

### 3.1 itemconfig (UNUSED)

- **Path:** `lua/itemconfig/lib/config_manager.lua`
- **Status:** Not required by any UI. ItemUI, SellUI, rules.lua all use `itemui.config`.
- **History:** IMPROVEMENTS_SUMMARY.md mentions it as "Shared Configuration Library" but implementation went into `itemui.config` instead.
- **Action:** Remove `lua/itemconfig/` or move to `lua/examples/` if kept for reference.

### 3.2 ImGuiFileDialog (DUPLICATED)

- **Paths:**
  - `lua/misclua/ImGuiFileDialog/ImGuiFileDialog.lua`
  - `lua/boxhud/utils/ImGuiFileDialog.lua`
- **Status:** Nearly identical copies. BoxHUD has its own; misclua has another.
- **Action:** Create shared `lua/mq/ImGuiFileDialog.lua` (or `lua/misclua/ImGuiFileDialog.lua`) and have boxhud `require` it. Update boxhud to use shared module.

### 3.3 ac_atk_helper (UTILITY – KEEP OR MOVE)

- **Paths:** `lua/ac_atk_helper.lua`, `lua/ac_atk_usage_example.lua`, `lua/test_ac_atk.lua`
- **Status:** Helper for AC/Attack/Weight from InventoryWindow. Only used by `ac_atk_usage_example.lua` (demo).
- **Action:** Move to `lua/examples/` or `lua/utils/` if useful for future ItemUI stats integration; otherwise keep as-is for developers.

### 3.4 eval.lua (MULTIPLE COPIES)

- **Paths:** `lua/eval.lua`, `lua/mq/eval.lua`, `lua/misclua/eval.lua`
- **Action:** Verify if these are identical or serve different purposes. Consolidate if possible.

---

## 4. UI Module Status

| Module | Status | Notes |
|--------|--------|-------|
| **itemui** | ✅ Active | Hub for inv/bank/sell; v1.5.0 |
| **sellui** | ✅ Active | Uses itemui.config; standalone sell window |
| **lootui** | ⚠️ Inconsistent | Uses own INI handling; should use itemui.config |
| **bankui** | ⚠️ Redundant | Replaced by ItemUI bank panel; no deprecation |
| **inventoryui** | ✅ Deprecated | Redirects to ItemUI |
| **epicquestui** | ✅ Active | Epic quest helper; separate domain |
| **boxhud** | ✅ Active | Boxing HUD |
| **buttonmaster** | ✅ Active | Button management |
| **lazbis** | ✅ Active | Loot distribution (need/greed) |

### 4.1 LootUI – Config Inconsistency

LootUI uses its own `readSharedINIValue` and does not use `itemui.config`. It will not benefit from:
- Chunked list reads (2048-char limit)
- Shared config path helpers
- Consistency with SellUI/ItemUI

**Recommendation:** Refactor LootUI to `require('itemui.config')` and use `readSharedListValue` / `writeSharedListValue` for shared valuable lists.

### 4.2 BankUI – Deprecation

PROJECT_ROADMAP states BankUI is "Replaced by ItemUI bank panel." BankUI is still fully functional. Add deprecation redirect like inventoryui:

```lua
-- bankui/init.lua
print("\ay[BankUI]\ax Deprecated. Use ItemUI (Bank button). Loading ItemUI...")
mq.cmd("/lua run itemui")
```

---

## 5. Config Architecture (Current – Correct)

```
Macros/
├── sell_config/          # ItemUI layout, sell lists, per-char data
├── shared_config/        # valuable_*.ini (loot + sell)
└── loot_config/          # loot_always_*, loot_skip_*, flags, values
```

All UIs and macros reference these paths. No duplication of config logic needed beyond `itemui.config`.

---

## 6. Backup Folders

- `Backup/2026-1-26/` – Large backup (300+ files)
- `Backup/2026-1-26_927/` – Similar snapshot
- `Backup/Macros/` – Older macro backups

**Recommendation:** Archive to external storage or zip; remove from repo to reduce clutter. Keep one recent backup if needed for rollback.

---

## 7. Macros – Obsolete or Test Files

| Macro | Status |
|-------|--------|
| `loot copy.mac` | Likely obsolete (duplicate of loot.mac?) |
| `Alctol.mac`, `ArrayTest.mac`, etc. | Test/example macros – consider moving to `Macros/examples/` |
| `Inventory.mac` | May be superseded by ItemUI – verify |

---

## 8. Player Experience & UI Context

### 8.1 What EverQuest Players Get Today

1. **ItemUI** – One window for inventory, bank, and sell. Context-aware (gameplay vs merchant). Bank slide-out. Config for sell + loot rules.
2. **SellUI** – Dedicated sell window when merchant open; more tabs for config.
3. **LootUI** – Loot config management.
4. **EpicQuestUI** – Epic quest step helper with loc/nav.
5. **BoxHUD** – Boxing character overview.
6. **Lazbis** – Need/greed loot distribution.

### 8.2 Strengths

- **Unified config** – shared_config for valuable items across loot and sell.
- **Performance** – Debounced saves, sort cache, spell cache, 33ms main loop.
- **Perky's Crew fit** – Epic quests, boxing, item management all supported.

### 8.3 Gaps

- **Multiple overlapping UIs** – ItemUI + SellUI + LootUI can confuse users.
- **No live Loot view in ItemUI** – LootUI stays separate (roadmap Phase 3).
- **BankUI still active** – Redundant with ItemUI bank panel.

---

## 9. Recommendations for Moving Forward

### 9.1 Immediate (This Sprint)

1. **Run `ItemUI/sync.ps1`** – Sync ItemUI package from lua/itemui.
2. **Deprecate itemui_package** – Add README; point users to main project or ItemUI.
3. **Fix master_items.json** – ✅ Done (was `i{`).
4. **Add BankUI deprecation** – Redirect to ItemUI like inventoryui.

### 9.2 Short-term (✅ Completed Jan 2025)

5. **Remove or relocate itemconfig** – ✅ Removed (dead code).
6. **Consolidate ImGuiFileDialog** – ✅ Created `lua/mq/ImGuiFileDialog.lua`; boxhud and misclua re-export.
7. **Migrate LootUI to itemui.config** – ✅ LootUI now uses readSharedListValue, readLootListValue, etc.
8. **Archive Backup folders** – ✅ Added `archive_backups.ps1`; added Backup/ to .gitignore.

### 9.3 Medium-term (Per PROJECT_ROADMAP)

9. **Loot view in ItemUI** – ✅ Done (v1.6.0): Live loot view when LootWnd open; Will Loot / Will Skip per item; same filters as loot.mac.
10. **Deprecate LootUI** – After ItemUI has loot view.
11. **SellUI consolidation** – Phase 5: Audit gaps, add missing features, deprecate.

### 9.4 Long-term (UI Overhaul Vision)

12. **Module split** – Extract itemui views into separate files (< 600 lines each).
13. **Theme consistency** – Shared theme.lua for ImGui colors (boxhud, itemui).
14. **EQ XML integration** – Explore MQUI_*.xml for native look/feel.
15. **EpicQuestUI integration** – Consider linking epic items to ItemUI (e.g., "Epic item" badge).

---

## 10. References

- `docs/MQ2_BEST_PRACTICES.md` – Lua and config conventions
- `docs/OPTIMIZATION_ROADMAP.md` – Performance checklist
- `lua/itemui/docs/PROJECT_ROADMAP.md` – Phases and vision
- `lua/itemui/docs/PERFORMANCE_IMPROVEMENTS_2025.md` – Recent optimizations
- MacroQuest docs: https://docs.macroquest.org
- Perky's Crew: https://perkycrewserver.com
