# Changelog

All notable changes to CoOpt UI are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Native window strips (CoOpt skin)** — With the new CoOpt UI skin loaded (`/loadskin coopt`), CoOpt controls appear inside the game's **own windows**, driven by CoOpt UI through MacroQuest: the **Merchant window** gains Auto Sell, Preview (dry run), and a live status line (sell/keep/protected counts, macro progress); the **Loot window** gains **CoOpt Cur** (loot this corpse by your rules) and **CoOpt All** (run the loot macro for all nearby corpses) plus a status line; and the **Actions window** gains a **CoOpt tab** with launcher buttons for the CoOpt UI, Bank, Augments, Aug Utility, Reroll, and AA companions. Routine vendoring and looting no longer need the CoOpt window open. Master toggle under Settings → General ("Native window strips"); everything no-ops unless the skin is loaded. The skin ships in `uifiles/coopt` and only overrides those three windows — everything else stays your normal UI.
- **Opening a corpse can start Auto Loot** — New Settings → General option (off by default): with the CoOpt skin loaded, right-clicking a corpse open immediately runs the loot macro for all nearby corpses using your loot rules (ignored while the loot macro is already running).
- **Mythicals Companion** — New pop-out window (toolbar button + Actions-tab launcher) listing every Mythical item in your bags in the Augments Companion layout — Reroll button, icon, name, effects, value — for fast reroll-list triage.
- **Unusable-item indicator** — In the Augments and Mythicals Companions, items your character can't use render with a red name and show the reason (class/race/deity/level) on hover. Cached per item so it costs nothing per frame.
- **Unified "Add to Reroll"** — One action everywhere instead of separate aug-list / mythical-list buttons: the UI routes each item automatically (name starts with "Mythical" → mythical list, augments → aug list). Applies to the right-click item menu, the Augments Companion's per-row button, and the Reroll Companion's **Add to Reroll (from Cursor)** — which now adds to the correct list no matter which tab is active.
- **"Recently looted" in the Inventory Companion** — New hidden-by-default **Acquired** column tracks when each item was first seen (stamps survive stack moves and reshuffles), a **Newest** button next to search sorts newest-first (click again to restore Name), and items looted since UI start show a green **NEW** badge by their name.
- **Sell Preview (dry run)** — New **Preview** button next to Auto Sell opens a modal listing exactly what would be sold, with quantity, value, total, and the rule behind each decision — catch config mistakes before the macro runs.
- **Quick loot rules** — Right-click any item name in the Loot window's looted list, Loot History, or Skip History → **Always loot this** / **Never loot this** (or undo a never-loot). Rules apply immediately to the real loot lists.

### Fixed
- **Native loot strip reworked after field testing** — the "CoOpt Cur" button is gone (looting the current corpse needs a target, which right-click-opening doesn't set); the strip is now a single full-width **CoOpt: Loot All**. Both the button and the auto-loot-on-corpse option now **close the corpse window before starting the loot macro**, so the macro runs its normal clean cycle and the Loot Companion gets one session covering the whole run instead of fragmenting per corpse. Strip buttons that were left visually "pushed in" (their un-latch state was wiped when the macro's window churn reset the surface) are now detected as stale and pop back out.
- **Auto-loot on corpse open waits for the window to settle** — triggering on the same tick as the open closed the corpse mid-handshake and left it lock-latched, so the loot macro's /loot failed on every corpse ("fires but loots nothing"). The trigger now waits 0.6s before the close-and-run handoff, with a 5s cooldown against rapid re-fires.
- **The CoOpt toggle keybind (default Shift+Q) and `/itemui hide` close every CoOpt window again** — after companions became hub-independent, hiding the hub left them open; both paths (and the hub's X button) now LIFO-close all companion windows including the Loot UI.
- **ESC now closes CoOpt windows no matter how they were opened** — companions launched from the native Actions tab (or with the hub closed entirely) ignored Escape; the LIFO close handler now runs independently of the hub window, so ESC always closes the most recently opened CoOpt window first.
- **"Opening a corpse starts Auto Loot" fired even when unchecked** — the layout loader returned the new toggles as numbers, and `0` is truthy in Lua; both native-strip settings now load as real booleans.
- **Native launcher buttons only worked while the CoOpt hub was open** — companion windows (Bank, Augments, Mythicals, Reroll, AA, Settings, …) now render independently of the hub window, so the Actions-tab launchers open them any time.
- **Reroll Sync could leave items stuck "pending"** — items already on the server list are cleared from pending instead of being re-sent (the top stuck cause); late server confirmations now complete the bookkeeping even after the wait window; the wrong-item-on-cursor case is detected before sending; sync stops cleanly if you leave the guild hall; only one track can sync at a time; pickup/confirm timeouts raised (0.8s→1.5s, 5s→10s); and the pending list now shows each item with a **Remove** button for manual cleanup.
- **Augment Utility suggested augments your deity can't use** — the usability check trusted the game's CanUse property, which doesn't reflect the server's deity restrictions; deity is now always verified ("only show usable" and tooltips honor it).
- **Sell rules: protections now always win.** Items on the never-loot list that were also NoDrop, epic, or on your Keep list could be sold ("sell to clear inventory" ran before protections). Protections (NoDrop → NoTrade → Epic → Keep) now run first, matching sell.mac's canonical order.
- **Keep lists longer than ~2000 characters were silently truncated** for sell decisions (the UI showed items as Keep; the seller didn't). All keep/valuable/augment lists now read every chunk.
- **Stale sell cache could sell newly-kept items** — when everything became protected, the old cache file survived and sell.mac's cache mode (which skips all rule checks) still sold from it. An empty computed list now writes an empty cache.
- **Right-click item menu was dead with default columns** in Inventory and Bank (it only rendered when the hidden-by-default Icon column was enabled). The menu now works regardless of column setup.
- **Settings changes now take effect immediately** — the deferred sell-status refresh after config changes was a no-op (Status column stayed stale until an unrelated rescan); loot flag/value changes never invalidated the loot rules cache; list adds via right-click could be erased by a later Filters-tab removal (stale cache write-back).
- **Filter conflict dialog never opened** (ImGui popup ID scope) — adding a conflicting entry silently did nothing. The conflict-resolution dialog now appears.
- **Macros: standalone `/else` lines never execute in MQ2** — epic protection loaded zero items in sell.mac's fallback mode, and single-entry always-loot lists never matched in loot.mac. All six sites converted to valid brace syntax.
- **Loot receipts counted items that were never looted** (decisions were logged before the loot attempt; failed loots and lore-duplicate aborts inflated totals and history). Accounting now happens only after a verified pickup.
- **Aborted loot runs no longer wedge the UI** — a bags-full abort (or crash) left `running=1` in the progress file forever, freezing the Loot window state and blocking inventory persistence. The macro now writes a heartbeat and finishes cleanly on inventory-full; the UI treats a 30s-stale heartbeat as not-running.
- **UI can now be closed at the bank** — the X button and Escape were immediately overridden by the bank auto-show; also fixed the loot-window/bank flicker fight.
- **AA window: training no longer fires from stray input** — pressing Enter (e.g. to chat) or double-clicking anywhere could spend AA points; both now require the window focused and the row actually hovered.
- **Augment Utility "Fill with best" could stick at "Optimizing 0/0"** and re-run a stale plan against wrong slots after inventory changed; the plan is now copied, invalidated on completion, and the button disabled while running.
- **Equip auto-confirm only answers the attunement dialog for attuneable items** (it previously clicked Yes on any confirmation dialog that appeared during the equip window).
- **First launch on an alt no longer resets your customized layout** (the first-run marker is account-wide now, not per-character).
- **Item tooltips can no longer crash the game on a mid-render error** (ImGui child/columns are rebalanced if a stat load fails while zoning); item-validity guards no longer fail open on nil IDs.
- **Reroll list refresh no longer picks up stray guild chat** during the 6-second parse window ("meet at 5:30" could become a bogus list entry that then protected item ID 5).
- **Roll after bank moves waits for the last move to finish** (stacked items could trigger the roll before the server saw all 10 items).
- **Destroy now verifies the right item is on the cursor** before `/destroy` (a failed pickup could destroy whatever was actually held).
- **Loot decisions on the no-plugin path**: clicky and NoDrop detection used checks that never fired (`lootClickies` was dead; NoDrop never flagged). Also fixed `lootClickies` treating every item as a clicky on the live-loot feed, and aligned loot defaults (tribute override 1000, clickies on) with loot.mac.
- **Sound test button** reported valid sound files as missing when MQ's working directory wasn't the EQ root.
- **ScriptTracker** now notices stack-size changes (looted scripts merging into stacks, partial consumes) instead of only slot-count changes.
- **Layout round-trips**: Loot-view width survived cold starts, AA sort column persists, Settings remembers the Advanced tab, and layout files are written atomically (a crash mid-write can no longer blank your layout).
- **Welcome wizard**: the environment checklist now expands when something failed (it collapsed exactly when you needed it), gained a Re-check button, and default sell protection actually seeds on first run.

### Changed
- **Actions window CoOpt tab** now holds 8 launchers in two columns (adds Loot UI and Settings), and the window's default width grew 124→150 so the extra tab and grid fit cleanly.
- **C++ plugin now enforces reroll-list protection natively** in both sell and loot rule ladders (ids pushed live from the UI). Previously the plugin's loot decisions could mark reroll-staged items as lootable.
- **Bank view updates while the bank stays open** when the plugin is loaded (deposits/withdrawals by in-game drag were invisible until reopen).
- **Performance** — major per-frame cost reductions across the UI: hover tooltips no longer rebuild full stat tables every frame (~85 TLO reads per hovered augment socket per frame eliminated), equipment refresh only rebuilds changed slots (~5,000 TLO evals/sec → ~60 while visible), the uiState proxy no longer allocates tables on every access, augment/candidate/filter/sort pipelines are cached instead of rebuilt per frame, history tables use clippers, sell progress polling is throttled, and idle-tick TLO window checks are skipped.
- **Patcher hardening for public release** — removed a faulty auto-migration that corrupted the shared core on every install; network failures now show actionable errors instead of freezing; downloads write atomically; verification failures show as failures (with Retry) instead of green "complete"; user keybinds (`MQ2CustomBinds.txt`) and ScriptTracker settings are preserved; MacroQuest-running is detected before patching; full-install extraction shows progress and disk-space errors.

---

## [0.9.7] — 2026-06-16

### Added
- **Consumables list** — Right-click any item → **Add to Consumables**. Items on the list get **Use (consume one)** and **Use all (xN)** options that right-click/consume them in-game (e.g. "Book of Titles"). The list is the safety gate, so only items you flag ever show a consume option.
- **Patcher — Full Install / Repair** — Point the patcher at any folder (an empty one, a vanilla MacroQuest you downloaded, the E3 distribution, or an existing CoOpt install) and it downloads the complete bundle and installs everything needed, **preserving your config** (EQ path, server list, character data, sell/loot rules). Fresh-install and update now share this one preserve-aware installer.
- **CI** — luacheck static-analysis gate on every push/PR, catching undefined-global / use-before-declaration bugs before release.

### Fixed
- **E3 crash on launch** — The distributed bundle was *deleting* required E3 runtime files (e.g. `Saved Groups.ini`), so E3 died on load with "Error: Please reload. Terminating." Those files are now emptied, not deleted.
- **Reroll — Remove** no longer crashes the UI.
- **Reroll — Sync** now works per item: pick up → add → **wait for the server's confirmation** → put back, and confirmed items are removed from the to-be-synced list. (Previously items got stuck on the cursor and never confirmed.)
- **Equip attuneable items** — The attunement dialog is now auto-confirmed (items no longer bounce back to your bags).
- **Augment ranking** — Heroic stats are now scored correctly (were treated as base stats).
- **First-run onboarding** — New installs now correctly show the welcome/setup wizard.
- Several internal crash-class fixes (filters/searchbar helpers, layout reset) and companion-window render isolation so one window's error can't take down the whole UI.

### Build
- MacroQuest pinned to a known-good commit (upstream `master` regressed with a missing `eqlib/game/ClassInfo.h`).
- `E3.dll` is now packaged even when an auxiliary E3Next project (E3NextSysTray) fails to build.
- MSVC toolset pinned and additional from-source build fixes for a reliable clean build.

---

## [0.9.0-beta] — 2026-03-01

### Added
- **Patcher version tracking** — After a successful patch, the patcher writes the manifest version to `Macros/coopui_installed_version.txt` so support can see what version players have. Patcher UI shows "Installed: X · Available: Y" when updates are available and "Up to date (vX)" when current. ItemUI startup message uses this file when present so patcher users see the same version in-game.

---

## [0.8.9-alpha] — 2026-03-01

### Added
- **Script consume verification** — Right-click "Add to Alt Currency" on scripts now waits for the chat message `[timestamp] You gained 1 alternate currency.` (or 2s timeout) before sending the next click, so all consumes are confirmed and no scripts remain after refresh
- **script_consume_events.lua** — New module that listens for the alternate-currency chat line; main loop uses per-click confirmation

### Changed
- **Default layout** — Equipment Companion window included in bundled default (`ShowEquipmentWindow=1` and position/size), so new installs and "Revert to default" show the Equipment window by default
- **Release manifest** — Regenerated; script_consume_events and related files in RELEASE_AND_DEPLOYMENT.md

---

## [0.8.8-alpha] — 2026-03-01

### Changed
- **Release process** — Config templates in release zip now sourced from `config_templates/` (includes `itemui_layout.ini`); release rule and manifest steps documented
- **Patcher** — Skip files that return 404 (e.g. removed from repo) instead of failing the whole patch

---

## [0.8.7-alpha] — 2026-03-01

### Added
- **Phase E complete** — Debug framework (8.1), Welcome environment validation (8.2), Backup & Restore (8.3), Fresh install bootstrap readiness (8.4)
- **CoOpt UI branding** — UI text and tab labels aligned (Task 2.5)
- **Patcher migration** — `migrate_itemui_to_coopui.py` for itemui→coopui folder migration (Task 3.5)
- **Advanced Settings tab** — Debug channel toggles, Backup & Restore export/import
- **ARCHITECTURE.md** — Canonical architecture reference

### Changed
- Master at stable pause point; plugin work archived as inactive

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
