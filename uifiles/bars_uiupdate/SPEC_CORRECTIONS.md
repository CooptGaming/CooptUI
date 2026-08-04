# Bars-UI spec — corrections verified against the repo

Companion to `IMPLEMENTATION_PROMPT.md`. Every item below was read out of the source on
branch `review/first-pass` (identical to `master` for all files named here) and then
adversarially re-checked. Line numbers are real.

The spec is unusually accurate for a document written from mockups — the render entrypoint,
the `bit32.bor` idiom, the `mq.event` + `doevents()` phase-10 pump, `mq.TLO.Window(…).DoOpen()`,
the deferred-queue discipline, the plugin's `setText`/`setChecked`, the 18 Command Center
buttons and the packaging glob all check out exactly as described. What follows is the
delta — the places where building to the letter of the spec would produce broken code.

---

## 1. Blockers — following the spec literally produces a bug

### 1.1 `ImGui.GetIO().DisplaySize` does not exist in this binding

Spec §3 and §4 rule 1 build slot measurement and work-area reservation on it, citing
`views/native_hover.lua` as precedent. **`DisplaySize` appears nowhere in the repo.**
`native_hover.lua:150-154` reads `GetIO()` only for `io.WantCaptureMouse` and `io.KeyShift`.

Use `ImGui.GetMainViewport()` instead — proven in the bundled MQ demo at
`Patcher_FreshInstall/lua/examples/imgui_demo/init.lua:451-454, 499-501`:

```lua
local vp = ImGui.GetMainViewport()
ImGui.SetNextWindowPos(vp.WorkPos)      -- or vp.Pos to ignore other reservations
ImGui.SetNextWindowSize(vp.WorkSize)    -- .x / .y on each
```

`WorkSize` is also the correct input for `utils/dock_layout.lua`'s work-area maths.

### 1.2 Draw order does not pin the bars behind companion windows

Spec §3: *"Draw them **before** `MainWindow.render` so companion windows overlay them, never
the reverse."* Dear ImGui z-order is the focus-ordered display list, not intra-frame `Begin`
order. Any click on a bar focuses it and lifts it above every companion — precisely the case
the spec says is impossible. The flag list at §3 omits the one flag that fixes it.

Add `ImGuiWindowFlags.NoBringToFrontOnFocus` to the bar flag set. The repo already does this
for exactly this reason at `views/native_hover.lua:89-91` — copy that combination.

Drawing first is still right, but for a different reason: `MainWindow.render` early-outs at
`views/main_window.lua:316` when the hub and all companions are closed, so the bars must not
live inside it.

### 1.3 Spec §8's INI design does not survive contact with the persistence layer

Three separate problems.

**(a) There is no `[Settings]` section.** `constants.lua:219-220` defines
`LAYOUT_INI = "itemui_layout.ini"` and `LAYOUT_SECTION = "Layout"`. The layout INI has four
sections — `[Defaults]`, `[Layout]`, `[ColumnVisibilityDefaults]`, `[ColumnVisibility]` —
plus `[Debug]` and `[Sound]` written by other modules. Runtime keys go in **`[Layout]`**.

**(b) Unknown keys inside `[Layout]` are erased on the next save.** `[Layout]` is not merged,
it is *regenerated* from 93 hardcoded `f:write("Key=" …)` calls at
`utils/layout.lua:226-340`, after the strip loop at `:209-224` deletes the old body.
So `ZoneAssign_<moduleId>` and `Attach_<moduleId>` cannot simply be dropped in — they would
vanish 600 ms after the user's next click.

Follow the `PinnedWindows` precedent instead — the codebase's one existing dynamic keyset:
`f:write("PinnedWindows=" .. registry.getPinnedCSV())` at `layout.lua:264`, read back at
`:449` / `:584` via `registry.setPinnedFromCSV`, with the pair implemented at
`core/registry.lua:212-224`. Collapse the zone and attach maps into one CSV key each.

**(c) Each new key needs five edit sites, not one.** In order:

| # | Site | What happens if you skip it |
|---|---|---|
| 1 | `layout_io.lua:70-84` `loadLayoutValue` type dispatch | **Silent data loss.** The fallthrough at `:83` is `tonumber(val) or default`, so a string key (`UIMode=bars`, `DockPosition=top`, `DockChat=peek`, `DockSegments=…`, `LayoutPreset=…`) writes correctly, appears in the file, and reads back as the default forever. Bool keys must join the chain at `:74-77`, strings at `:80-82`. |
| 2 | `layout.lua:226-340` `writeLayoutFile` | Key never persists |
| 3 | `layout.lua:413-544` `loadLayoutConfig` **cached** branch | Setting reverts whenever the layout is served from cache |
| 4 | `layout.lua:546-681` `loadLayoutConfig` **file** branch | Setting reverts on cold start |
| 5 | `state.lua:72-119` `layoutDefaults` (+ `layout_setup.lua` for Save Setup / Reset) | No default; `nil` reaches the render path |

Branches 3 and 4 are ~130 hand-duplicated lines and **have already drifted once** — see the
regression comment at `layout.lua:604-606` about Equipment geometry missing from the file
branch and defaults overwriting saved values. Factoring them into one shared local function
is worth doing as part of this work; adding ten keys twice by hand is a bug farm.

### 1.4 Presets in the layout INI get deleted by "Revert to Default"

Spec §8: *"Presets are INI sections so `defaultLayout.revertToBundledDefaultLayout()` keeps
working unchanged."* Half true, and the wrong half is load-bearing.

- The function needs no edit — `utils/default_layout.lua:161-163` tail-calls
  `applyBundledDefaultLayout()`, which knows nothing about sections. ✔
- Unknown *sections* do survive an ordinary layout save: the strip loop at
  `layout.lua:216-222` re-inserts any header that is not `[Layout]`/`[ColumnVisibility]`
  along with its body. `[Debug]` and `[Sound]` prove it. ✔
- But `applyBundledDefaultLayout` at `default_layout.lua:107-126` reads the bundled file and
  `safeWrite`s it over the whole user file. **Every `[Preset:*]` section is deleted**, along
  with `[Sound]` and `[Debug]`. A `.bak` is written first (`:117-125`, 7-day retention), so
  it is recoverable but not restored. ✘
- And nothing can *find* the presets anyway: `layout_io.lua:18-43` recognises four fixed
  section names and discards the rest (`else current = nil end`, `:32`). No section
  enumeration exists anywhere in the repo (`.Section(` appears only at `config.lua:67,86`).

**Recommendation:** put presets in their own file, `itemui_presets.ini`, which revert never
touches. It is cheaper than teaching `applyBundledDefaultLayout` to merge, and it fixes the
pre-existing `[Sound]`/`[Debug]` collateral loss for free. Either way a new
`parseSectionsMatching(pattern)` helper in `layout_io.lua` is required.

### 1.5 Phase 3's per-module keybinds do not exist

Spec phase 3 wants the four hover menus *"listing modules from the registry with their
keybind"*. There is exactly **one** keybind in the entire product: `layoutConfig.ItemUIToggleKey`
→ the single MQ custom bind `itemui_inv` (`utils/layout.lua:703-746`), which toggles the hub.
No module declares a keybind and no per-module bind mechanism exists.

The registry *would* pass a new field through — `register` returns
`setmetatable({…}, {__index = m.spec})` at `core/registry.lua:74-87` — but the data has to be
invented. Pick one: render rows without keybinds, show the single global hub key via
`ctx.getItemUIToggleKeyDisplay()` (already plumbed, used at `components/ui_common.lua:41`), or
add a `keybind` spec field plus per-module binds modelled on `layout.lua:713-735`.

If you add binds: the `/timed 1` wrapper on the `-down` command is **not stylistic**. The
comment at `layout.lua:707-712` records that MQ 3.1.4.9's mq2lua crashes
(`mq2lua.DLL+1C87`) when a Lua-bound command runs on the MQ2CustomBinds keyboard path. Any
second bind must use it too.

### 1.6 Section 7's Start/Stop bullet is not confined to `native_bridge.lua`

Spec §7 says *"Only `native_bridge.lua` changes."* True for 16 of the 18 Command Center
buttons. `Coopt_CCStartBtn` and `Coopt_CCStopBtn` are owned by a different script —
`lua/coopt_launcher.lua:25-26`, handled at `:142-154` — whose entire reason to exist is to
keep working **after `/lua stop itemui`** (header `:3-7`). "Collapse Start/Stop CoOpt into a
running indicator + Restart" therefore requires editing `coopt_launcher.lua`, and it must
stay functional with itemui unloaded.

`native_bridge.lua`'s `CC_BUTTONS` table (`:73-90`) has 16 entries, not 18.

---

## 2. Wrong symbols and paths

| Spec says | Actually |
|---|---|
| `item_ops.beginPickup` (§2 row 1) | `item_ops.pickupFromSlot(bag, slot, source)` — `services/item_ops.lua:804`, command at `:816`. No `beginPickup` exists. Reached from views as `ctx.pickupFromSlot`. |
| `ui_common.renderItemContextMenu` (§2 row 3) | Real, but at `lua/itemui/components/ui_common.lua:168` — there is a **`components/`** directory the spec's "views/services/utils" placement rule never mentions. |
| popup id `ItemContextInv_<rid>` | One of seven. Also `ItemContextBankIcon_`, `ItemContextSellIcon_`, `ItemContextEquip_<slotIndex>`, `ItemContextAugmentsIcon_`, `ItemContextMythIcon_`, plus `reroll.lua:450`. |
| `services/scan.lua` results (§3) | `scan.lua` exports **functions only** (`:817`) and owns no data. It mutates tables handed to it via `init(env)`. Read `inventoryItems` / `bankItems` / `bankCache` / `sellItems` / `lootItems` from `state.lua:21,164,181`. |
| `layout_io.lua` for persistence (§0) | `layout_io.lua` is **read-only** — four functions, zero writes. Writing lives in `layout.lua:189-359` and `layout_setup.lua`. |
| "Loot All / Stop via macro bridge" (§2 row 11) | Bare `mq.cmd('/macro loot')` and `mq.cmd('/endmacro')` at `views/command_center.lua:103,110` — issued *inside the ImGui frame*. Only Auto Sell is deferred (`uiState.autoSellRequested`). |
| `registry.lua:60` comment: `displayOrder` / `layoutConfig.CompanionButtonOrder` | Neither is implemented anywhere. Toolbar order is bare registration order (`registry.lua:17,58,93`). Deterministic bar ordering must be built from scratch. |
| The §2 table has 13 rows | 14. All 14 verified. |

Also worth knowing: only **8 of the 12** registered companions are toggleable.
`views/config_general.lua:250-258` hardcodes an 8-entry list, and the enableKeys for
`mythicals`, `commandCenter`, `favorites`, `effects` are absent from `layoutDefaults`, the
writer, and both loader branches — so `ShowEffectsWindow=0` in the INI does nothing today.
Do not copy that hardcoded list into a bars-mode visibility surface.

---

## 3. Aspirations stated as facts

These are fine as rules for new dock code. They are not descriptions of `master`, so do not
try to verify them by grepping the whole render path, and do not "fix" the existing sites
while porting.

- **"No TLO calls in the render path."** Today: `main_window.lua:354` (`Window("InventoryWindow")`),
  `:155,175` (`Me.Grouped()`), `:590,600,813-814` (`Cursor.*`), `:920` (`Me.Name()`), and
  `native_hover.lua:115-117` (`Window(…)`, `EverQuest.LastMouseOver`) — the last on *every*
  frame. Scope the phase-1 acceptance check to the new dock files only.
- **"Nothing issues game commands inside the render callback."** Six existing sites:
  `command_center.lua:103,110`, `inventory.lua:296`, `equipment.lua:233,236`,
  `ui_common.lua:254,260`.
- **"Never write the INI from inside an ImGui frame."** Six existing sites:
  `inventory.lua:42,147,178`, `bank.lua:203,233`, `sell.lua:259` — all calling
  `flushLayoutSave` or `saveLayoutToFileImmediate` from button/sort handlers.
- **"State lives outside ImGui's internal storage."** `app.lua:684` puts `SaveSettings` in
  `TABLE_FLAGS`, and `inventory.lua:90` / `bank.lua:134` deliberately delegate sort and
  column order to it. The `InvColumnOrder=` / `BankColumnOrder=` INI keys are a **dead
  round-trip** — written and read, but nothing ever assigns `sortState.invColumnOrder` from a
  user drag. Bars using `NoSavedSettings` is correct; leave `TABLE_FLAGS` alone.

---

## 4. Phase 1 segment data — what actually exists

Spec §3: *"segments read **cached** values only."* True for two of seven segments. The rest
need new aggregation on the dock tick.

| Segment | Status | Source |
|---|---|---|
| Loot progress (all 5 states of `12a`) | ✅ exists | `uiState.lootRunCurrentCorpse` / `lootRunTotalCorpses` / `lootRunLootedItems` / `lootRunTotalValue` / `lootRunFinished` / `lootMythicalAlert` / `lootMythicalDecisionStartAt` — every mockup state maps to a real field |
| Status / plugin | ✅ exists | `utils/coopui_plugin.lua`, `core/diagnostics.lua` |
| Sell offer | ⚠️ per-row cached, **aggregate is not** | `views/sell.lua:175-194` recomputes `sellCount`/`sellTotal`/`keepCount`/`protectCount` **every frame**. Move that exact pass into `dock_state.tick`; invalidate on `scanState.sellStatusAttachedAt` / `perfCache.sellConfigPendingRefresh` |
| Bags + weight | ❌ new | Free slots only via `itemOps.countFreeInvSlots()` (`item_ops.lua:593-608`) — an **uncached** walk of 10 packs with a TLO read per slot. Weight only inside `components/character_stats.lua:191-194`, read as native window text, which returns nil unless `InventoryWindow` is **open** — so a persistent bar shows "N/A" most of the time. Item counts (not free slots) are free from `ctx.inventoryItems` |
| Buffs / songs / aura | ❌ new | Only `views/effects.lua` (module-local `cache`, `:36`, `rescan()` `:100-128`), and it runs **only while the Effects window is open**. ~40-70 TLO reads per pass. Lift `rescan` into the shared tick so there is one walk, not two |
| XP / AA / scripts | ⚠️ computed, not exported | `components/character_stats.lua:167-168` (`Me.PctExp()`, `Me.AAPointsTotal()`) behind a 500 ms TTL in a module-local `cachedStats` that is not exported. Script counts are pure inventory aggregation, no TLO. Add a `getSnapshot()` getter — do not duplicate the `SCRIPT_AA_*` tables in a third place |
| Session total | ❌ **does not exist** | `lootRunTotalValue` is **per-run and zeroed at run start** (`main_loop.lua:271-278`, `macro_bridge.lua:476-488`). Sampling the live counter loses the previous run. A new accumulator must add at each run-*finish* edge (`main_loop.lua:281`) and from `sell_batch.recordSold` (`:156-165`) |

Cost discipline matters here: the codebase already chunks expensive work
(`SELL_STATUS_DRAIN_PER_TICK = 15`, `SESSION_MERGE_PER_TICK = 20`). A `dock_state.tick` that
in one tick walks buffs + songs + auras + 10 packs of free slots + a full `sellItems` pass is
exactly the stutter this codebase was refactored to remove. Stagger the sub-aggregations or
give each its own interval.

---

## 5. Things the spec omits that will cost time

1. **Two dependency tables, not one.** `ctx` (`context.init` refs, `app.lua:873-1109`) feeds
   the render path; `d` (`buildMainLoopDeps`, `app.lua:1259-1305`) feeds `main_loop`. They
   overlap but differ — `ctx` has `sellMacState` but not `lootMacState`/`scanState`. Wire
   `dock_state` into both. `context.build()` rebuilds the proxy per frame (`context.lua:17`).

2. **`uiState` is a metatable proxy.** `app.lua:86-175` reroutes whole key families to other
   modules: all `lootRun*`/`lootHistory`/`lootMythical*` → `LootUIView.getState()`,
   `cursorActionQueue`/`lastPickup`/`pendingQuantity*` → `itemOps.getState()`, reroll keys →
   `rerollService.getState()`, window-open keys → `registry`. So `rawget(uiState, k)` is wrong
   for those. Brand-new keys (`dockActionQueue`, `dock*`) fall through to `rawset` — fine; put
   plain defaults in `state.lua:42-69`.

3. **Loop cadence is gated on the hub, not the bars.** `phase10_loopDelay`
   (`main_loop.lua:1616`) picks `LOOP_DELAY_VISIBLE_MS` (33) vs `LOOP_DELAY_HIDDEN_MS` (100)
   from `getShouldDraw()`, which tracks the **hub**. A permanently visible bar with the hub
   closed would update its segments at 10 Hz. `getShouldDraw()` needs to account for
   `DockTop`/`DockBottom` being on.

4. **Dock views get no crash isolation for free.** `renderCompanions`
   (`main_window.lua:295-304`) wraps each module's render in `pcall`. Bars drawn before
   `MainWindow.render` sit outside that — wrap them yourself or one bar exception kills the
   whole frame. `NativeHover` is the existing precedent: `pcall(NativeHover.render, refs)` at
   `main_window.lua:315`.

5. **Two clocks, ~1000× apart.** `mq.gettime()` is **ms** and is what the loop uses
   everywhere (`now` is threaded in from `app.lua:1510` — don't re-call it inside a phase that
   was handed `now`). `os.time()` is **seconds** (`perfCache.lastBankCacheTime`). `os.clock()`
   is `macro_bridge`-only; don't spread it. Put the 250 ms interval in `constants.TIMING`
   beside `STATS_TAB_PRIME_MS = 250`.

6. **`scheduleLayoutSave` can be starved.** `layout.lua:181-186` resets
   `layoutSaveScheduledAt` on *every* call, so calling it per frame (e.g. while a bar is
   dragged) means the 600 ms debounce never fires. Existing views guard by only calling on an
   actual value change — `config_general.lua:83` is the pattern.

7. **The main-loop slot for `dockState.tick(now)`** is between `phase9_layoutSaveCacheCleanup`
   and `phase10_loopDelay` — after all state mutation, before the delay. But a
   `dockActionQueue` drain that issues commands or touches the cursor belongs where
   `phase0_cursorActionQueue` sits (early, after `phase1b`) so it observes the same activation
   guards. Note `M.tick` (`main_loop.lua:1821-1871`) does **not** run phases in numeric order,
   and `nativeBridge.tick(now)` is the closest template for a new service tick.

8. **Any dock action that picks up an item must set `uiState.lastPickup`** (or go through
   `cursorActionQueue`), or `phase1b_activationGuard` (`main_loop.lua:109-126`) sees an
   unknown-source cursor item and fires `/autoinv` on it.

9. **`chat_feed.lua` has no in-repo precedent for capture, only for parsing.** Clone
   `services/script_consume_events.lua` (33 lines — module-scope `EVENT_NAME`/`LINE_PATTERN`,
   one-arg handler, `pcall`-wrapped `mq.event` inside `init(d)`, `diagnostics.recordError` on
   failure). Register it in `main_loop.M.init` alongside `lootFeedEvents.init(d)` at
   `main_loop.lua:1814-1817` — nothing self-registers. Two details:
   - `mq.event` takes an optional 4th options table. `{ keepLinks = true }` is what preserves
     EQ item links; the default strips them (`examples/linkdetector.lua:43`).
   - A bare `#*#` fires on every chat line at ~30 Hz. Keep the handler allocation-light, and
     read the warning at `reroll_service.lua:320-331` first: a loose pattern there caused
     real data loss because a stray chat line wiped a cache that doubles as a sell/loot
     *protection* set. A broad-pattern handler must never mutate protection state, and any
     clearing branch needs a guard that runs before it.

10. **Ring buffer:** copy one of the two that exist, don't invent a third.
    `core/diagnostics.lua:24-26` (`while #t > MAX do table.remove(t,1) end`) or the
    `table.move` trim at `loot_feed_events.lua:58-63` for a hot buffer. Also copy
    `diagnostics.lua:30-34`'s habit of returning a **copy** to the view layer so a mid-render
    mutation can't shift indices under ImGui.

11. **Lua's 200-local / 60-upvalue ceilings are live constraints here.** `app.lua` is 83 KB,
    `main_loop.lua` 105 KB, and `scan.lua`'s header exists to explain the dependency-injection
    shape that works around them. New modules take a `deps` table in `init(d)` and store it in
    one file-local; don't add locals to `app.lua`.

12. **`Patcher_FreshInstall/lua/` is a complete, untracked, stale second copy** of both
    `itemui/` and `coopui/`. Repo-wide greps hit it and hand you wrong line numbers. Never
    edit it; always confirm your path starts with `lua/itemui/`. (Its `examples/` folder is
    genuinely useful, though — it's the only proof of the viewport API and `keepLinks`.)

13. **The Grep tool silently skips `.lua` files in this repo** unless you pass
    `glob: "*.lua"`. A bare content search returns "No matches found" for symbols that
    plainly exist.

---

## 6. Where the spec was right and a reviewer was wrong

Recorded so these don't get re-litigated:

- **`plugin.setText` / `setChecked` ship today.** `plugin/MQ2CoOptUI/capabilities/window.cpp`
  binds `getChecked` (:66), `setChecked` → `CButtonWnd::SetCheck` (:76-80), `setText` →
  `CXWnd::SetWindowText` (:86-90), `getMouseOverSlot` (:115). The tracked
  `release_manifest.json` ships the v0.9.8 DLL containing them. (A stale v0.9.7 DLL sits in
  `Patcher_FreshInstall/plugins/` — that folder is the patcher's install *destination*, not a
  source asset. Don't mistake it for what users get.)
- **`setText` works on Labels, not just EditBoxes.** `window.cpp:86-92` uses plain
  `findChild` + `SetWindowText` with no type gate (only `setChecked`/`click` gate on
  `WRT_BUTTON`). `native_bridge.lua:455` already writes the AA `Coopt_AAStatus` Label through
  the same `setStatus()` helper as the two EditBox status lines. The EditBox-only limitation
  in the header comment applies to the **TLO fallback path**, not the plugin path.
- **Packaging needs no action from the implementer.** `patcher/generate_manifest.py:41-49`
  walks all of `lua/itemui` excluding only `docs/` and `upvalue_check.lua`, so all 7 new files
  are picked up and hashed automatically. Regeneration + commit is an unconditional step of
  the release pipeline (`publish-release.ps1:147-151,191`; `Build-Smart.ps1:2468`), and
  `docs/DEVELOPER.md:275-277` explicitly forbids regenerating mid-development. Do **not** add
  them to `patcher/installer.py`'s `_CRITICAL_FILES` (`:319-325`) — that's a post-install
  probe, and listing anything not in the bundle false-fails every install.
- **§0 step 2's `backup/` is already handled.** Root `backup/` is ignored
  (`.gitignore:7` `/*`), and no packager reads `.gitignore` anyway — they all stage explicit
  allowlists, so nothing at the repo root can reach a release. The `.gitignore` edit is a
  no-op; skip it. (Do keep the snapshot at the **root**. Under `lua/itemui/` it would ship,
  because `generate_manifest.py` walks the working tree, not git.)
- **The luacheck gate does fire.** `.github/workflows/luacheck.yml` triggers on
  `pull_request: branches: [master]` — matched by the PR's *base*, so a PR from
  `feature/bars-ui` runs it. `max_line_length = false` and unused-arg (212) is ignored; what
  *is* enforced is 11x (accidental globals), 113 (undefined variable), 143 (undefined field of
  a global), 221 (local accessed but never set). So: `local M = {} … return M`, no accidental
  globals, no use-before-declaration. Expect the file counts in
  `docs/release-review/first-pass.md` §5 to move 91→98 and 94→101 — not a regression.
- **`theme` exports 21 symbols, not 2.** Prefer `theme.TextMuted` / `TextWarning` /
  `TextError` / `TextSuccess` / `RenderProgressBar` / `SectionBreak` over hand-rolled
  `PushStyleColor` pairs — then "no new hex values" is satisfied with zero colour literals
  written. `Colors.Warning = {0.9, 0.7, 0.2, 1}` is the amber the mockups use for
  under-5-minutes and bags-over-90%. Require it as `require('itemui.utils.theme')` (a 2-line
  re-export of the coopui module) to match every other itemui file.
