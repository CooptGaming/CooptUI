# Changelog

All notable changes to CoOpt UI are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

---

## [0.8.5-alpha] — 2026-02-23

### Added
- **Default layout snapshot system** — Standalone `coopt_layout_capture.py` to capture a reference layout from an MQ folder; outputs `default_layout/` with normalized `itemui_layout.ini`, CoOpt UI-only `overlay_snippet.ini`, and `layout_manifest.json`
- **First-run default layout** — When no existing layout exists, CoOpt UI applies the bundled `lua/itemui/default_layout/` into `Macros/sell_config/` and merges overlay snippet into `config/MacroQuest_Overlay.ini`
- **Revert to Default Layout** — Settings window button with confirmation modal; applies bundled default, force-applies companion window positions/sizes for several frames so they reposition without closing the UI; main window position applies after restarting MacroQuest (documented in dialog)
- **DEFAULT_LAYOUT.md** — Documentation for capture, first-run, revert, patcher contract, and revert diagnostics/fixes

### Fixed
- Capture script: `[Window][Title]` key parsing now uses `index("]", 9)` so full window title is captured (was empty, so no `[Window]` blocks were in overlay_snippet.ini)
- Deploy merge: same key parsing fix when merging overlay snippet into existing MacroQuest_Overlay.ini
- Revert: companion windows now actually move/resize after revert by using `ImGuiCond.Always` for position/size for a few frames when `layoutRevertedApplyFrames > 0` (was only applying on first show via FirstUseEver)

---

## [0.8.0-alpha] — 2026-02-22

### Changed
- Version bump to 0.8.0-alpha
- Patcher: patch log (list of altered files) now remains visible after patching so players can scroll through it

---

## [0.7.1-alpha] — 2026-02-22

### Changed
- Version bump to 0.7.1-alpha

---

## [0.7.0-alpha] — 2026-02-22

### Changed
- Version bump to 0.7.0-alpha

---

## [0.4.2-alpha] — 2026-02-20

### Changed
- Version bump to 0.4.2-alpha

---

## [0.4.0-alpha] — 2026-02-16

### Changed
- Version bump to 0.4.0-alpha

---

## [0.3.0-alpha] — 2025-02-13

### Added
- Configuration reference documentation (`docs/CONFIGURATION.md`)
- Installation guide (`docs/INSTALL.md`)
- Developer documentation (`docs/DEVELOPER.md`)
- Troubleshooting guide (`docs/TROUBLESHOOTING.md`)

### Fixed
- Release workflow version prefix bug: zip name mismatch (`vv0.x` vs `v0.x`) that caused release asset upload to fail silently
- Build script now excludes dev-only files (`docs/`, `test_rules.lua`, `upvalue_check.lua`, `phase7_check.ps1`) from release zip

---

## [0.2.0-alpha] — Architecture overhaul

Major architectural redesign across 7 phases: performance optimization, unified filter system, SellUI consolidation, macro integration, layout management, and init.lua decomposition.

### Added
- **Instant open** — UI opens in ~15ms with cached data shown immediately (Phase 2)
- **Incremental scanning** — 2 bags per frame with per-bag fingerprinting; only changed bags rescan (Phase 2)
- **Unified filter system** — Item Lists tab with add/remove for all sell and loot lists (Phase 3)
- **SellUI consolidation** — All SellUI features merged into ItemUI; SellUI deprecated (Phase 4)
- **Macro bridge** — `/dosell` and `/doloot` integration with status feedback in UI (Phase 5)
- **Loot view** — Live corpse item evaluation when loot window is open (Phase 3)
- **Item tooltips on hover** — Rich item detail popups on mouseover (PR #3, #4)
- **Augments view** — Dedicated augmentation item display
- **Config window improvements** — Renamed tabs (General & Sell, Loot Rules, Item Lists), improved tooltips, Open Config Folder button (Phase 6.1)
- **Layout management** — `utils/layout.lua` module for window size, column visibility, sort persistence (Phase 7)
- **CoOpt UI shared core** — `lua/coopui/` with version, theme, events, cache, and state modules
- **Context registry pattern** — Single `refs` table via metatable proxy to stay under Lua's 60-upvalue limit
- **State consolidation** — `uiState`, `perfCache`, `sortState`, `filterState` tables to stay under 200-local limit
- **ScriptTracker auto-refresh** — Refreshes on inventory fingerprint change (PR #6)
- **init.lua decomposition** — 6 modules extracted: `window_state`, `item_helpers`, `icons`, `sell_status`, `item_ops`, `character_stats` (41% reduction, 2184 → 1293 lines)
- **Augment-specific lists** — Separate always-sell and never-loot lists for augmentation items
- **Never-loot sell integration** — Items on the never-loot list are also sold to clear inventory
- **Epic class filtering** — Per-class epic item protection via `epic_classes.ini`
- GitHub release workflow (`release.yml`) and build script (`build-release.ps1`)
- `DEPLOY.md` included in release zip

### Fixed
- Sell view keep/junk unchecking issue (PR #7)
- Bank drag save storm — debounced from 40+ saves to 1 save per drag (600ms debounce)
- Item slot parsing errors with augmentation nil values (PR #3)
- Duplicate sell list entries — atomic table replacement (PR #5)
- Sort state not persisting across close/reopen
- Column widths on first load (ImGui timing workaround)

### Changed
- **Performance** — 15ms UI open time (70% faster than 50ms target), 93% CPU reduction in macro polling
- Config tabs renamed: "ItemUI" → "General & Sell", "Auto-Loot" → "Loot Rules", "Filters" → "Item Lists"
- SellUI and LootUI deprecated — use ItemUI for all features
- Version bumped to 0.2.0-alpha

---

## [0.1.0-alpha] — Early alpha

First packaged release for early alpha testers.

### Added
- **ItemUI** — Unified inventory, bank, sell, and loot window (`/lua run itemui`, `/itemui`).
- **ScriptTracker** — AA script progress (Lost/Planar, etc.) via `/lua run scripttracker`.
- **Auto Sell** — `sell.mac` and `/dosell`; configurable keep/junk and epic protection.
- **Auto Loot** — `loot.mac` and `/doloot`; configurable filters and sorting.
- Config templates for sell_config, shared_config, and loot_config (first-time install).
- Epic item protection and class-specific epic lists in shared_config.
- ItemUI views: inventory, bank, sell, loot, config, augments; theme and layout support.

### Requirements
- MacroQuest2 with Lua (mq2lua) and ImGui.
