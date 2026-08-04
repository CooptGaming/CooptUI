# CoOpt UI — Bars UI implementation prompt **v2**

> **Status: phases 1–6 shipped.** The top and bottom bars, chat window and layout presets are
> built. The next pass — the middle windows, the context-menu overhaul and window pairing —
> is `IMPLEMENTATION_PROMPT_WINDOWS.md` (v3). This file stays as the record of how the bars
> were specified; §2's "do not touch the middle windows" no longer applies, v3 supersedes it.

Supersedes v1. Read together with `SPEC_CORRECTIONS.md` (in this folder) — that file is a
line-verified review of v1 against the repo, and **where the two disagree, SPEC_CORRECTIONS
wins**. Everything below already folds its findings in.

Design mockups: `CoOpt UI In-Game.dc.html`. Option ids (`12a`, `13c`, `10a`…) refer to it.

---

## 0. Ground rules

1. `git checkout -b feature/bars-ui` off `master`. Nothing lands on `master`.
2. Snapshot the current UI to **`backup/pre-bars/`** at the **repo root** (root `/*` is already
   gitignored, and packagers stage explicit allowlists, so nothing there can ship). Do **not**
   put the snapshot under `lua/itemui/` — `generate_manifest.py` walks the working tree and
   would package it. No `.gitignore` edit is needed.
3. Runtime escape hatch: `UIMode = classic | bars` (INI key in `[Layout]`, default `classic`
   until phase 5). `classic` must render exactly what `master` renders today.
4. Follow existing patterns: views in `views/`, services in `services/`, helpers in `utils/`,
   shared widgets in **`components/`** (this directory exists — `components/ui_common.lua`,
   `components/character_stats.lua`).
5. Colours: use `theme`'s 21 exported helpers (`TextMuted`, `TextWarning`, `TextError`,
   `TextSuccess`, `RenderProgressBar`, `SectionBreak`, `Push*Button`…) rather than hand-rolled
   `PushStyleColor` pairs — then zero colour literals get written. Amber for
   "under 5 minutes" / "bags over 90%" is `Colors.Warning`. Require it as
   `require('itemui.utils.theme')` to match every other itemui file.
6. New modules take `init(d)` and keep deps in one file-local. Do not add locals to `app.lua`
   (`app.lua` is 83 KB and Lua's 200-local / 60-upvalue ceilings are live constraints here).
7. Luacheck runs on the PR: no accidental globals, no undefined variables, `local M = {} … return M`.

---

## 1. Scope

**Build:** a top status bar, a bottom command bar (launchers + native launchers + presets +
chat), and zone-based window placement with named layout presets. Then first-run, degraded
states and "why" surfaces.

**Do not touch:** the middle windows' internals. Inventory, Bank, Equipment, Item Display,
Augments, Aug Utility, AA, Reroll, Mythics and Settings keep their current tables, columns,
tooltips and context menus.

Mockups: top bar `12a` / `12b`, bottom bar `13b` + `13c` **option B (four hover menus)**,
placement `10a` `10b` `10c` `10e`, in-situ `13a`, first run `14c`, degraded states `14d`,
"why" `14e`, native cleanup `8a`–`8c`.

---

## 2. Non-negotiable — nothing loses functionality

Verified symbols (corrected from v1):

| Behaviour | Where it lives now | After |
|---|---|---|
| Left-click picks the item up | `services/item_ops.lua:804` **`pickupFromSlot(bag, slot, source)`** (command at `:816`), reached from views as `ctx.pickupFromSlot` | unchanged |
| Shift+click banks / un-banks | `views/inventory.lua:252`, `views/bank.lua:295` (`ImGui.GetIO().KeyShift`) | unchanged |
| Right-click context menu (and Item Display) | **`components/ui_common.lua:168`** `renderItemContextMenu`; **seven** popup ids: `ItemContextInv_`, `ItemContextBankIcon_`, `ItemContextSellIcon_`, `ItemContextEquip_<slotIndex>`, `ItemContextAugmentsIcon_`, `ItemContextMythIcon_`, plus `reroll.lua:450` | unchanged |
| Right-click a clicky fires it | `views/inventory.lua:296` `/itemnotify … rightmouseup` | unchanged |
| Hover stats tooltip | `utils/item_tooltip.lua`, `utils/tooltip_render.lua` | unchanged |
| Equipment slot click / swap | `views/equipment.lua:233,236` `/itemnotify <slotName> leftmouseup` | unchanged |
| Quantity picker, cursor bar, confirms | `main_window.lua`, `item_ops.lua`, `main_loop.lua` | unchanged |
| Columns: show/hide, reorder, resize, sort | `utils/columns.lua`, `layout_columns.lua`, `column_config.lua`, ImGui `SaveSettings` in `app.lua:684 TABLE_FLAGS` | unchanged — **leave `TABLE_FLAGS` alone**; bars use `NoSavedSettings`, tables keep theirs |
| Sell / Keep / Junk per row | `views/sell.lua` | unchanged |
| Mythical Take / Pass | `views/loot_ui.lua` + callbacks in `main_window.lua` | window unchanged; bar mirrors state, adds F1/F2 |
| Loot All / Stop | `views/command_center.lua:103,110` — bare `mq.cmd` **inside the frame** today | bar routes through `uiState.dockActionQueue` instead (see §6.8) |
| Auto Sell | `uiState.autoSellRequested` (already deferred) | same |
| Companion launchers | `main_window.lua` toolbar + `command_center.lua` | move to the bottom bar in `bars` mode |
| Esc LIFO close | `main_window.lua` + registry pinned ids | unchanged; bars never enter the stack |
| Shift+Q, `/itemui`, `/dosell`, `/doloot` | `app.lua` binds, `utils/layout.lua:703-746` | unchanged |

**Acceptance:** with `UIMode=bars` and both bars disabled, behaviour is identical to `classic`.

---

## 3. Corrected feasibility notes

- **Viewport, not DisplaySize.** `ImGui.GetIO().DisplaySize` does **not** exist in this binding.
  Use `ImGui.GetMainViewport()` → `vp.WorkPos` / `vp.WorkSize` (proven in
  `Patcher_FreshInstall/lua/examples/imgui_demo/init.lua:451-454, 499-501`). `WorkSize` is also
  the input for `utils/dock_layout.lua`'s work-area maths.
- **Z-order needs a flag, not draw order.** ImGui z-order is focus-ordered. Add
  **`ImGuiWindowFlags.NoBringToFrontOnFocus`** to the bar flag set — the repo already does this
  at `views/native_hover.lua:89-91`; copy that combination. Still draw the bars *before*
  `MainWindow.render`, because `main_window.lua:316` early-outs when the hub and all companions
  are closed.
- **Wrap each bar in `pcall`.** Bars sit outside `renderCompanions`' per-module `pcall`
  (`main_window.lua:295-304`). Precedent: `pcall(NativeHover.render, refs)` at `main_window.lua:315`.
- **Popovers are windows, not tooltips** (tooltips can't hold buttons): borderless,
  `NoFocusOnAppearing | NoNav | NoBringToFrontOnFocus | AlwaysAutoResize`, opened on hover,
  closed when neither segment nor popover has been hovered for ~250 ms, middle-click pins.
- **Chat capture:** clone `services/script_consume_events.lua` (33 lines) — module-scope
  pattern, one-arg handler, `pcall`-wrapped `mq.event` inside `init(d)`,
  `diagnostics.recordError` on failure. Register it in `main_loop.M.init` next to
  `lootFeedEvents.init(d)` (`main_loop.lua:1814-1817`); nothing self-registers. Pass
  `{ keepLinks = true }` as `mq.event`'s 4th arg to preserve item links
  (`examples/linkdetector.lua:43`). A bare `#*#` fires ~30 Hz: keep the handler
  allocation-light, and **never let it mutate protection state** — read the warning at
  `reroll_service.lua:320-331` first.
- **Ring buffer:** reuse `core/diagnostics.lua:24-26` or the `table.move` trim at
  `loot_feed_events.lua:58-63`. Return a **copy** to the view layer (`diagnostics.lua:30-34`)
  so a mid-render mutation can't shift indices.
- **Native windows** open via `mq.TLO.Window('<name>').DoOpen()` (`command_center.lua`).
- **Two dep tables:** `ctx` (`app.lua:873-1109`, rebuilt per frame by `context.build()`) and
  `d` (`buildMainLoopDeps`, `app.lua:1259-1305`). Wire `dock_state` into both.
- **`uiState` is a metatable proxy** (`app.lua:86-175`) — `lootRun*`, cursor and reroll keys are
  rerouted to other modules, so `rawget` is wrong for those. New `dock*` keys fall through to
  `rawset`; put their defaults in `state.lua:42-69`.
- **Clocks:** `mq.gettime()` is ms and is what the loop threads through as `now` — don't
  re-call it inside a phase that was handed `now`. Put the 250 ms dock interval in
  `constants.TIMING` beside `STATS_TAB_PRIME_MS`.
- **Loop cadence:** `phase10_loopDelay` picks 33 ms vs 100 ms from `getShouldDraw()`, which
  tracks the **hub only**. Extend it to account for `DockTop`/`DockBottom`, or a visible bar
  updates at 10 Hz with the hub closed.
- **`scheduleLayoutSave` can be starved** (`layout.lua:181-186` resets the timer on every
  call). Only call it on an actual value change — pattern at `config_general.lua:83`.
- **Repo gotchas:** `Patcher_FreshInstall/lua/` is a stale second copy — never edit, and
  distrust line numbers from it. Grep needs `glob: "*.lua"` in this repo.

---

## 4. Design deltas forced by the review

These change the mockups slightly. Build the corrected version.

| Mockup said | Build instead | Why |
|---|---|---|
| Top bar shows `wt 140/931` | Show **bags used / total** always; show weight **only while the game's Inventory window is open**, otherwise omit the sub-segment (slot stays reserved) | Weight is read as native window text (`components/character_stats.lua:191-194`) and is nil when `InventoryWindow` is closed |
| Bags segment shows free slots | Item count from `ctx.inventoryItems` on the fast path; free slots refreshed on a **slow** sub-tick | `itemOps.countFreeInvSlots()` walks 10 packs with a TLO read per slot, uncached |
| Bottom-bar menus list a keybind per module | List modules **without** per-module keybinds; show the one global hub key via `ctx.getItemUIToggleKeyDisplay()` | Only one keybind exists (`itemui_inv`). If you later add per-module binds, the `/timed 1` wrapper at `layout.lua:707-712` is **mandatory** — MQ 3.1.4.9's mq2lua crashes without it |
| "Session total" on the bar | New accumulator, added at each loot-run **finish** edge (`main_loop.lua:281`) and from `sell_batch.recordSold` (`:156-165`) | `lootRunTotalValue` is per-run and zeroed at run start |
| Presets as `[Preset:*]` sections in the layout INI | Own file **`itemui_presets.ini`** | `applyBundledDefaultLayout` (`default_layout.lua:107-126`) overwrites the whole layout file — it would delete every preset (and already collaterals `[Sound]`/`[Debug]`). Needs a new `parseSectionsMatching(pattern)` in `layout_io.lua` either way |
| `ZoneAssign_<id>` / `Attach_<id>` as one key per module | **Two CSV keys**, `ZoneAssign=` and `WindowAttach=` | `[Layout]` is regenerated from 93 hardcoded writes (`layout.lua:226-340`); unknown keys are erased on the next save. Follow the `PinnedWindows` precedent (`layout.lua:264`, `registry.lua:212-224`) |
| §7 "only `native_bridge.lua` changes" | 16 of 18 buttons, yes. `Coopt_CCStartBtn` / `Coopt_CCStopBtn` live in **`lua/coopt_launcher.lua:25-26,142-154`** and must keep working after `/lua stop itemui` | That launcher's whole purpose is to survive itemui being stopped |
| "No TLO calls in the render path" as a global rule | Scope the acceptance check to **new dock files only** | Six existing sites already do it (`main_window.lua:354,155,175,590,600,813-814,920`, `native_hover.lua:115-117`). Don't "fix" them in this work |

---

## 5. INI keys — corrected

Section is **`[Layout]`** in `itemui_layout.ini` (`constants.lua:219-220`). There is no
`[Settings]` section.

```
UIMode=classic|bars           (string)
DockTop=1|0                   (bool)
DockBottom=1|0                (bool)
DockPosition=top|bottom       (string)
DockChat=hidden|collapsed|peek(string)
DockSegments=status,bags,sell,loot,buffs,xp,session   (CSV string)
DockLaunchers=bags,bank,equipment,augments,reroll,aa  (CSV string)
DockNative=inventory,merchant                          (CSV string)
ZoneAssign=inventory:C,bank:R1,itemDisplay:R2,…        (CSV string)
WindowAttach=itemDisplay:hub:right:top,…               (CSV string)
LayoutPreset=Bag session      (string)
```

Presets live in **`itemui_presets.ini`**, one `[Preset:<name>]` section each.

**Every new key needs five edit sites** — skipping any one causes a silent revert:

1. `layout_io.lua:70-84` `loadLayoutValue` type dispatch — bools join `:74-77`, **strings join
   `:80-82`**. The fallthrough at `:83` is `tonumber(val) or default`, so a string key writes
   fine, appears in the file, and reads back as the default forever.
2. `layout.lua:226-340` `writeLayoutFile`.
3. `layout.lua:413-544` `loadLayoutConfig` **cached** branch.
4. `layout.lua:546-681` `loadLayoutConfig` **file** branch.
5. `state.lua:72-119` `layoutDefaults` (+ `layout_setup.lua` for Save Setup / Reset).

Branches 3 and 4 are ~130 hand-duplicated lines and have already drifted once
(`layout.lua:604-606`). **Factor them into one shared local as part of this work** before
adding ten keys twice by hand.

---

## 6. Files

**New**

```
lua/itemui/services/dock_state.lua      -- staggered aggregation on the main-loop tick
lua/itemui/services/chat_feed.lua       -- mq.event capture + ring buffer (clone script_consume_events)
lua/itemui/services/window_zones.lua    -- zone table, occupancy, placement, re-tidy, snapping
lua/itemui/services/layout_presets.lua  -- itemui_presets.ini: list/save/apply/delete
lua/itemui/utils/dock_layout.lua        -- slot widths (CalcTextSize, cached) + WorkSize maths
lua/itemui/views/dock_top.lua           -- status bar + popovers
lua/itemui/views/dock_bottom.lua        -- menus, native launchers, presets, chat
```

All seven are picked up by `patcher/generate_manifest.py:41-49` automatically — **do not**
regenerate the manifest mid-development (`docs/DEVELOPER.md:275-277`), and **do not** add them
to `installer.py`'s `_CRITICAL_FILES`.

**Changed:** `app.lua` (render both bars inside the existing `mq.imgui.init` callback, each in
`pcall`, before `MainWindow.render`; init the new services; new binds) · `main_loop.lua`
(`dockState.tick(now)` between phase 9 and phase 10; `dockActionQueue` drain early, where
`phase0_cursorActionQueue` sits, so it observes the same activation guards; `getShouldDraw`
accounts for the bars; `chatFeed.init(d)` beside `lootFeedEvents.init(d)`) ·
`core/registry.lua` (additive `zone` field + `getZone`; **deterministic bar ordering must be
built — `displayOrder` and `CompanionButtonOrder` in the comment at `:60` are not implemented**)
· `views/main_window.lua` (hide the companion toolbar in `bars` mode only) ·
`views/config_general.lua` (Dock section — and **do not** copy its hardcoded 8-entry
companion list at `:250-258`; four modules' enableKeys are missing from the writer and both
loader branches today) · `views/settings.lua` (Layouts section) · `utils/layout.lua` +
`layout_io.lua` (the five sites, plus `parseSectionsMatching`) · `commands.lua`
(`/itemui dock|layout|retidy|hints`) · `views/tutorial.lua` (phase 5) ·
`services/native_bridge.lua` + `lua/coopt_launcher.lua` (phase 7 cleanup).

### 6.8 Dock actions must not bypass the cursor guard

Any dock action that picks an item up must set `uiState.lastPickup` or go through
`cursorActionQueue` — otherwise `phase1b_activationGuard` (`main_loop.lua:109-126`) sees an
unknown-source cursor item and fires `/autoinv` on it.

---

## 7. Phase 1 segment data — what exists, what you must build

| Segment | State | Source / work |
|---|---|---|
| Loot progress (all 5 states of `12a`) | ✅ exists | `uiState.lootRunCurrentCorpse`, `lootRunTotalCorpses`, `lootRunLootedItems`, `lootRunTotalValue`, `lootRunFinished`, `lootMythicalAlert`, `lootMythicalDecisionStartAt` |
| Status / plugin | ✅ exists | `utils/coopui_plugin.lua`, `core/diagnostics.lua` |
| Sell offer | ⚠️ per-row cached, aggregate is not | `views/sell.lua:175-194` recomputes counts/totals every frame — move that exact pass into `dock_state.tick`, invalidate on `scanState.sellStatusAttachedAt` / `perfCache.sellConfigPendingRefresh` |
| Bags (+ weight) | ❌ new | Item count free from `ctx.inventoryItems`; free slots via `item_ops.lua:593-608` on a slow sub-tick; weight only while `InventoryWindow` is open |
| Buffs / songs / aura | ❌ new | Lift `views/effects.lua rescan()` (`:100-128`, ~40-70 TLO reads) into the shared tick so there is one walk, not two — today it runs only while the Effects window is open |
| XP / AA / scripts | ⚠️ computed, not exported | Add `getSnapshot()` to `components/character_stats.lua` (500 ms TTL `cachedStats` at `:167-168`); do not duplicate the `SCRIPT_AA_*` tables |
| Session total | ❌ new | Accumulate at run-finish (`main_loop.lua:281`) and `sell_batch.recordSold` (`:156-165`) |

**Stagger the sub-aggregations.** One tick that walks buffs + songs + auras + 10 packs of free
slots + a full `sellItems` pass is exactly the stutter this codebase was refactored to remove
(`SELL_STATUS_DRAIN_PER_TICK = 15`, `SESSION_MERGE_PER_TICK = 20` are the precedents). Give each
sub-aggregation its own interval.

---

## 8. Phases and acceptance

1. **Top bar.** Viewport-anchored, fixed height, fixed slots, `bars` mode only, `pcall`-wrapped,
   `NoBringToFrontOnFocus`. Segments per §7, loot segment cycling all five `12a` states from real
   state. *Accept:* no slot ever changes width; no TLO calls **in the new dock files**; classic
   mode byte-identical; frame time unchanged with bars on.
2. **Popovers.** Buffs (expiring + recast + grid) and sell (grouped by reason). *Accept:* no
   focus steal, never opens during a loot decision, Esc closes a pinned one.
3. **Bottom bar.** Four hover menus from the registry (no per-module keybinds), native
   launchers, Layouts, Settings, chat at three heights with per-channel unread. *Accept:* every
   window reachable in ≤2 clicks; Command Center window closable for a whole session;
   `/itemui center` focuses the bar.
4. **Zones, snapping, presets.** `zone` per module, first-free-slot placement inside `WorkSize`
   minus the bars, drag marks user-placed, Re-tidy, 12 px magnets stored as relationships,
   five bundled presets in `itemui_presets.ini`. *Accept:* all 12 windows open with no overlap
   and nothing off-screen at 1920×1080 and 2560×1440; revert-to-default leaves presets intact.
5. **First run.** Two questions + live dry-run count, then five contextual hints; `/itemui hints`
   replays. Flip default to `bars` for new installs only. Keep the 13-step wizard behind
   `/itemui setup --full` until this ships.
6. **Degraded states + "why".** `14d` strips (no plugin, missing `sell.mac`, stale bank, no
   rules) and `14e` explanations (status hover-explain, skip reasons with fixes, live hit counts,
   `verb · item · because` chat lines).

## 9. Testing

`UIMode=classic` first — must match `master`. Then `bars`: merchant + `/dosell`, `/doloot` with
a mythical drop, bags full, open/close all 12 windows, switch presets, resize the game window,
`/loadskin coopt` and back, `/lua stop itemui` (launcher Start/Stop must still work). Watch
`logs/coopui_debug.log` with Layout and Scan channels on: no per-frame spam, no INI write storms.

## 10. Deliverables

Branch `feature/bars-ui`, one commit per phase; `docs/DOCK_UI.md` in the voice of
`docs/PRODUCT_GUIDE.md`; `CHANGELOG.md` entry; no changes to `master`, to user config files, or
to `uifiles/coopt/*.xml`.
