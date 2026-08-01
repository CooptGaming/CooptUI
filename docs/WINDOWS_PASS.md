# Windows pass — decisions and kit contract

Working notes for `feature/windows-pass` (spec: `uifiles/bars_uiupdate/IMPLEMENTATION_PROMPT_WINDOWS.md`,
corrections win where they disagree). Phase numbers below are the spec's — v3 as re-synced
2026-07-31 (turns 25/26 added; phases run 7–15; acceptance moved §11→§14).

---

# HANDOFF — read this first (2026-08-01, second pass)

**State: every spec phase 7–15 is BUILT, plus §10 keybinds, 20b, and now the three
remaining mockups — 19d (the last six windows' kit bands), 19b (bottom bar v2) and 19c
(chat window v2). 19 suites / 888 asserts green, luacheck 0/0 across 111 files. Branch
`feature/windows-pass`, ~58 commits ahead of `master`, UNPUSHED, no upstream. Working tree
clean except the untracked `uifiles/bars_uiupdate/` design folder (untracked by design).**

**No mockup in `CoOpt UI In-Game.dc.html` is unbuilt now.** What remains is in the ranked
list below, and it is verification and three named deferrals — not unstarted design.

Deployed to `C:\Claude_External\CoOptDeploy\test1` via
`scripts/sync-to-deploytest.ps1 -Target "C:\Claude_External\CoOptDeploy\test1"`.

## How to verify anything (do this before believing a claim)

```
# 19 suites, headless, the exact LuaJIT MQ2Lua links (also enforces the 60-upvalue cap)
LJ="C:/MQ/TestClaudedeploy/.mq-source/macroquest/build/solution/vcpkg_installed/x86-windows-static/tools/luajit/luajit.exe"
for t in scripts/tests/test_*.lua; do "$LJ" "$t"; done
"$LJ" scripts/tests/compile-sweep.lua <files...>
# luacheck (Lua 5.4 + lfs, prebuilt):
#   C:/Users/jtlat/AppData/Local/Temp/claude/C--Claude-CooptUI/bbd6a3db-.../scratchpad/run-luacheck.ps1
```

## The five traps that have each cost real time here

1. **Grep silently skips `.lua`** in this repo unless you pass `glob:"*.lua"`. Use bash
   grep or always pass the glob, or you will "prove" a symbol does not exist.
2. **`Patcher_FreshInstall/lua/` is a stale untracked SECOND COPY** of the whole tree.
   Never read or cite it. Only `lua/itemui/`, `lua/coopui/`, `lua/scripttracker/` are real.
3. **Stack balance is safety-critical.** Any unbalanced ImGui pair raises a C++
   `ImGuiException` that Lua `pcall` CANNOT catch; MQ2Lua answers by killing the script,
   and stopping a script in that state has crashed the EQ client. **A pcall goes INSIDE
   the pair, never around it** — this applies to Begin/End, BeginChild, BeginTable,
   BeginPopup, and every Push/Pop.
4. **Binding return-order traps.** `Selectable` returns `(selected, pressed)` — selected
   FIRST. `MenuItem` returns `(activated, value)` — the OPPOSITE order. `Begin` returns
   `(open, shouldDraw)` — draw on the second. `GetItemRectMin`/`CalcTextSize`/
   `GetWindowSize`/`GetContentRegionAvail` return TWO FLOATS, not a vec.
5. **`cond and nil or X` CANNOT yield nil** — `true and nil` is nil, so the `or` fires and
   hands back X. This broke two toggles here (one of them pre-existing and years old).
   Use an explicit `if`. Same family: `f and f(t) or g(t)` truncates a multi-value call.

Two more that bit this pass and are now guarded by tests:

- **A container has to pay for what it draws.** A segment child is EXACTLY one text line
  tall, so a sized `Button` under `FramePadding.y=1` (lineHeight+2) clips, and a
  `BeginChild` with `border=true` pays 8px WindowPadding and clips its own label. Both
  shipped. `test_dock_render` now asserts requested Button and ProgressBar heights.
- **MQ's ImGui does not render source as UTF-8.** A middle dot arrives as mojibake, and an
  editor round-trip DOUBLE-encodes it (which silently destroyed two FontAwesome glyph
  literals). `test_ascii_strings.lua` fails on any non-ASCII byte in a rendered literal;
  glyphs must be `\xNN` escapes.

## Where things live (the non-obvious ones)

| What | Where |
|---|---|
| The launcher list, ONCE (both bars draw it) | `components/hub_list.lua` — takes `queue` as an ARG to avoid a require cycle |
| Bar cell widths / order | `constants.UI.DOCK_CELL_W`, `CELL_ORDER` in `views/dock_top.lua` |
| Session record + the counting rule | `services/session_record.lua` |
| Keybinds (11, one CSV key) | `utils/keybinds.lua` |
| AA script definitions, shared | `utils/script_defs.lua` |
| Window alignment / pairing | `services/window_zones.lua` (bank's `zone="R1"` IS the alignment) |
| **The chip + count pill + the 26px band + the pin + the glyphs** | `components/window_header.lua` — `chip / pill / render / registryLock / GLYPHS`. Bars, chat's tab strip and every window band draw the SAME control. |
| Bottom-bar groups (chat, launchers, commands, identity) | `views/dock_bottom.lua` — `MENUS[].group` is `"left"` or `"right"` |
| Chat send targets | `services/chat_console.lua` `SEND_TARGETS` (+ `sendInput(text, mq, targetId, name)`) |

## WHAT'S NEXT — ranked, with why

**1. In-game verification is the real gate.** Everything below is secondary to walking
the bars. Specifically unverified: the 11 keybinds actually firing, the reroll tray
against a real 10-item roll, the session triage against a real loot run, and Bank's
zone alignment when the hub is dragged. **New and unverified from the second pass:** the
`\xEF\x86\x92` (U+F192 dot-circle) Hub glyph and `\xEF\x81\xBB` (U+F07B folder) actually
rasterising from the merged atlas; the bottom bar's narrow-viewport fold at a real
resolution; the send-to picker's popup taking focus the way every other focusable CoOpt
window does; and whether Zep-vs-plain-renderer switching (timestamps or a filter force the
plain one) reads as a surprise in the field.

**2. Decide `ctrl+shift+K`.** Bank's bind is an ADDITION beyond the ten the user signed
off (the audited set assumed the Bags+Bank merge, which was rolled back). Flagged in
`utils/keybinds.lua`. Keep or drop — one line either way.

**3. The why-line's Tier 1** — "fits 3 of your slots" instead of today's honest-but-thin
"types 1, 3 augment". Needs a socket-type census of all 23 equipped items (~115 TLO
reads); socket TYPES are cached nowhere (the tooltip cache holds them only inside
formatted strings, and only after a hover). Belongs on a demand-driven `dock_state` walk
with its own `DOCK_SLOW_*` interval publishing `snap.wornSockets`; the render path is then
pure arithmetic via `augment_helpers.augmentFitsSocket`. Full plan in the scout notes.

**4. Keyboard triage in the session panel** (26b's `↑↓ / K / R / J / Z`). Blocked on a
focusable surface: the bars refuse keyboard focus BY DESIGN, so this needs the docked form
of the list, not the hover panel.

**5. Equipment's "N upgrades in bags"** — still the honest `worn n/23`, deferred since
phase 13 for the same reason as Tier 1 (needs a compare walk that does not exist).

**6. Push the branch.** 55 commits, no upstream, and `github.md` still reports master
lacking all bars work.

## Second pass — 19d / 19b / 19c, 2026-08-01 (commits 104c7a8, 1d6d645, d57c1d8)

The three mockups the first pass never reached. **23c's Hub-panel question is settled and
gone from the open list** — field pass 5 put the launcher LIST on the top bar's CoOpt cell,
and this pass put the lit `◉ Hub` CHIP in the bottom bar's right group, which is exactly
where 23c's and 19b's own bar renders draw it. No duplication: both surfaces call
`hub_list.drawEntries` on the same `ENTRIES`.

- **104c7a8 — 19d, the last six windows.** Bank, Mythics, Reroll, Clickies, AA and Settings
  now draw the shared band in bars (classic is `if barsOn then band else <old header
  verbatim> end` in all six). Stats are the header contract's, never a restatement of the
  bar: Bank = holdings, Mythics = what you hold and what it is worth, Reroll = the two
  SERVER list sizes (*not* the tray's "N of 10 ready", which each tab already shouts, and
  not the bar chip's pending count), Clickies = lists + items protected, AA = **unspent**
  (the XP/AA cell reports `AAPointsTotal`, i.e. everything ever earned), Settings = none,
  because it genuinely has no number. Two helpers instead of six copies:
  `window_header.registryLock(id, ctx)` and `window_header.GLYPHS`.
- **1d6d645 — 19b, bottom bar v2.** Four things were wrong and are now right: an open
  window was filled with `Keep.Normal` (the GO-green — a launcher reading as an action
  button) and is now the product's open pair, OpenWash + a 2px OpenBlue accent on the chip
  edge that FACES the screen; counts moved out of labels into their own clickable pills;
  chat owns the left edge in BOTH styles (it used to be drawn after the menu row, putting
  the one flexible cell between two fixed ones); and the launcher row now FOLDS itself away
  below a 220px chat budget — dropped, not squeezed, because the Hub menu already holds
  every one of those launchers and a squeezed chat line is not recoverable from any menu.
  Unread badges became four dots (`AddCircleFilled`, one `InvisibleButton` each, so they
  still hover for the count and click through to their tab). Right group is
  `◉ Hub | Layouts | Settings`, with Layouts drawing the SAME `layouts_dynamic` entry the
  Hub list draws. Settings became a real toggle.
- **d57c1d8 — 19c, chat v2.** Channel picker (six targets, persisted as `ChatSendTo`;
  a leading `/` still outranks it; `/tell` degrades to `/say` rather than emitting a
  nameless command), a time column stamped at CAPTURE (`ChatTimestamps`), a filter whose
  row exists only while it is on, an "N new" catch-up pill that only appears while you are
  scrolled away, tabs as kit chips. Two hint lines recovered — the band and the picker say
  what they said.

### What the second pass learned (add these to the trap list)

- **A window with no body containment is one throw from killing the script.** chat_window
  had none — `pcall` the whole body so `ImGui.End()` is unconditional (item_display got
  this in aec75c0). The new suite's injected `SmallButton` throw is what found it; a
  reading of the file would not have.
- **The stub was hiding whole classes of bug.** `GetWindowDrawList` returned **nil**, so
  every `if not dl then return end` short-circuited and no draw-list primitive was ever
  exercised — "the status dot is a square" and "the lit chip has no accent" were both
  invisible to 810 asserts. It records now, `PushStyleColor` records WHICH colour, and the
  viewport size is overridable. New helpers: `stub.draws / drewColor / pushedColor /
  colorOf`, plus `M.inputText` (scripted typing) and `M.scroll`.
- **A clickable item inside a click-target child double-fires.** The chat dots sit in a
  child that itself opens chat; without the queue-length guard the dot's open and the
  line's toggle both run and the window opens and shuts in one frame. Same guard the top
  bar's cells use for their inner buttons.
- **Adding a `[Layout]` key is still 3 sites + STRING_KEYS** (`ChatTimestamps` numeric,
  `ChatSendTo` string). Neither goes in `layout_setup`'s capture/reset — same rule as
  `ChatUseZep`: these are preferences, not arrangement.

## Open product questions (do NOT guess these)

- Does the session end at logout? Currently NO — it persists until `Clear`. Design's own
  recommendation, adopted; trivially reversible.
- The 20a suggestion to flip more Bank columns on by default — Status is now on for Bank
  only; the rest untouched because classic must render as master does (acceptance §14.1).

## Field pass + phase 16 — 2026-07-31 late (commits e183e9b..b6ff41d)

First in-game look landed, and the merge did not survive it.

- **e183e9b — two field bugs.** The Loot All / Auto Sell pair clipped: a segment child is
  EXACTLY one text line tall (`barHeight = lineHeight + DOCK_BAR_PADDING_Y*2`, child =
  minus that padding), so a sized `ImGui.Button` under `FramePadding.y = 1` measures
  lineHeight+2 and loses its bottom edge and kit border to the clip rect. Every other bar
  control is a SmallButton, which forces `FramePadding.y = 0`; this pair could not be,
  because it must hold identical widths across job states. Fix is both halves —
  `FramePadding.y = 0` AND an explicit one-line height (`barButtonSize`). The stub now
  records requested Button sizes and the suite requires an explicit positive height ≤ one
  line (h=0 auto would pass a naive check while measuring taller — the actual bug).
  Also: `AddCircleFilled` IS bound (lua_ImGuiUserTypes.cpp:399), so the status dot is a
  dot again; the square was a stand-in from when only AddRectFilled was proven.
- **980cc2f — THE MERGE IS ROLLED BACK.** User verdict: bags and bank are used together
  often, but you do not always want the bank on screen, and one window cannot express
  that. Replacement is ALIGNMENT, and the mechanism was already built and merely switched
  off — bank's registry spec has always carried `zone = "R1"`, which IS "flush against the
  hub's right edge, same Y". It was inert only because `classicOnly` made bank unopenable
  in bars, so window_zones could never see it open. **Deleting that one flag re-arms
  placement, magnets, hub-follow and the close-edge slide-up with no new placement code.**
  Added: main_window's one-shot (0,0) seed also matches bank's height to the hub's (`hubH`
  was computed and unused), and `placeWindow` records the hub attachment itself so the
  pair survives the first hub drag. That auto-attach exposed a real gap — Alt-drag skipped
  snapping but never RELEASED an attachment; it does now, because Alt is the "I am placing
  this myself" gesture. KEPT from phase 10: the toolbar/table splits, resolveList/
  renderTable, the pcall-inside-BeginTable containment, and the 20a chip (moved into the
  standalone Bank header, where it supersedes Online/Offline outright).
- **b6e4c49 — keybinds wired**, eleven of them, `ctrl+shift+<key>`. The design's proposal
  (alt+letter, F1-F3) collided with NINE live binds; the audit's ctrl+shift set is what
  shipped. Bank's `ctrl+shift+K` is an ADDITION beyond the signed-off ten, caused by the
  rollback (the audited set assumed ctrl+shift+I covered both) — flagged in source.
  One CSV key, not eleven string keys, for the silent-revert reason. Every `-down` command
  is `/timed 1` wrapped and the suite parses the emitted commands to prove it.
  Load order verified: `loadLayoutConfig()` (app.lua:1568) precedes `applyAll()` (:1590),
  and the CSV read sits in `applyLayoutSection`, which both loader branches call.
- **44bf124 — 20b tray.** Ten slots holding the items a roll would actually consume, bags
  then bank, stacks per unit. The 10 is a CLIENT convention: `augRoll()` takes no
  arguments, guards nothing, and the server's answer is never parsed — so the view is the
  only place that can honestly say what a roll takes. Roll's reason prints inline and
  names the FIX. Also surfaced the per-item sync failure reasons that `main_loop` has
  always recorded and NOTHING rendered. Redundancy collapse landed here as planned.
- **b6ff41d — deferrals.** Triage right-click could NOT be opened inside the panel: the
  popover lives on a 250ms hover grace refreshed via `IsWindowHovered(ChildWindows)`, and
  an ImGui popup is a separate TOP-LEVEL window, not a child — entering the menu would
  expire the panel and take the menu with it. It gets an independent zero-footprint host
  (the native_hover pattern) drawn outside `renderPopover`. Live entries re-link by
  `acquiredSeq` (identity; bag/slot is only position); departed entries get a synthetic
  row so location verbs do not apply rather than lie. The why-line ships its free,
  always-true half (the aug's own accepted socket types, from an `augType` captured at
  record time and persisted as an 11th field).

**(RESOLVED 2026-08-01, see the second-pass section above — the list went on the top bar's
CoOpt cell in field pass 5, and the lit `◉ Hub` chip went into the bottom bar's right
group in 19b/23c's own arrangement. Both draw one `hub_list.ENTRIES`. The paragraph below
is the reasoning as it stood.)**
**STILL OPEN — one product decision, not a build task: 23c's Hub panel on the top bar.**
Do not build it without a call, for three reasons found while scoping it: (1) in 23c's own
bar render the lit `◉ Hub` chip sits in the RIGHTMOST group beside Layouts and Settings —
the "identity cell" framing came from this doc's earlier deferral note, not the mockup;
(2) this doc said the bottom bar "carries it for now", which reads as REPLACE, not ADD;
(3) a second launcher list violates the product's own "one home per control" (13d, quoted
in dock_bottom's header), and on the 190px status cell it would stack three meanings —
hover = list, click = toggle hub, lit = hub open. Options: replace the bottom bar's Hub
menu with a top-bar panel, add it as a distinct cell, or leave it where it is.

**Also deferred, with reasons:** the why-line's Tier 1 ("fits 3 of your slots") needs a
socket-type census of all 23 equipped items — ~115 TLO reads, and socket TYPES are cached
nowhere (the tooltip cache holds them only inside formatted strings, and only after a
hover). It belongs on a demand-driven `dock_state` walk with its own `DOCK_SLOW_*`
interval, publishing `snap.wornSockets`. Session-panel keyboard triage still waits on a
focusable docked form of the list — the bar windows refuse focus by design.

## Autonomous stretch 2026-07-31 evening — phases 10, 11(remainder), 13, 14, 15 BUILT

Commits 9f4386c (10+20a), e9fa082 (11 pair chips + Hub list), cc21bfe (13 bar rebuild),
29b9810 (15 Script Tracker), cc898f3 (14 session strip). 15 suites / 708 asserts,
luacheck 0/0. Detail per phase in the sections + commit messages; the short map:

- **10**: hub hosts the merged two-pane Inventory in bars (`renderMergedContent`);
  bank classicOnly; `InventoryBankSplitX` at 7 INI sites; 20a chip lives in the pane;
  NEW INVARIANT: extracted tables pcall their body INSIDE BeginTable/EndTable.
- **11 rest**: Bags|Bank + ItemDisplay|AugUtility split chips (buttons style), hub-open
  lighting, empty-socket pill (peek-only from tooltip cache); menus fold to ONE Hub menu
  (ITEMS/CHARACTER/LAYOUTS). Shortcut labels wait on the keybind proposal.
- **13**: the bar is a fixed grid (constants.UI.DOCK_CELL_W; 26a supersedes 22a/25a);
  DockSegments = enable SET (order canonical, `loot` id retired — the lane replaced it
  and can't be disabled; config_general picker = checkboxes); fixed Loot All/Auto Sell
  pair transforms to its own Stop in place; the lane owns every job state; every cell a
  toggle (hub toggle semantics in the drain); done-state decays after
  DOCK_LANE_DONE_HOLD_MS (6s).
- **15**: Scripts companion (`views/script_tracker.lua`) — counts from the SHARED
  inventory list; SCRIPT_DEFS → `utils/script_defs.lua` (standalone tool requires the
  same module); turn-in = the EXISTING consume FSM (right-click from bags + chat
  verification — NO NPC; the spec's open question was answerable from code) surfaced as
  the lane's third owner with its Stop IN the lane (it has no bar start button).
- **14**: `services/session_record.lua` — §12 counting rule + pre-emption at record
  time (reroll list / keep rule / junk rule / NoDrop → SORTED, never amber; scripts
  auto-sort), per-char persistent record (survives logout; Clear ends it — design's
  recommendation adopted, user can reverse), four-value session cell (zero muted+inert,
  values are doors), hover triage panel with Keep/Reroll/Junk chips + Undo last.

**Deferred, in one place:** 20b reroll tray (spec says "can slip"); 23c Hub shortcut
labels + ALL keybind wiring (proposal unapproved); session-panel keyboard triage
(bar windows refuse focus by design — belongs to a docked/focused form of the list);
row right-click via the §7 builder from the triage panel; the "fits N of your slots"
why-line (needs a bags-vs-equipment compare walk that doesn't exist — same class as
Equipment's deferred "N upgrades in bags" stat); identity-cell Hub PANEL popover
(23c's vertical list on the top bar — the bottom bar's Hub menu carries it for now);
20a's "flip Bank's Status column on by default" (shared defaults would change classic).

**In-game verification owed on all of it** (same list as phases 7/8/9 still owed) —
plus one new hazard to check live: ImGuiChildFlags.ResizeX splitter behavior (bound,
zero repo precedent before phase 10).

## §0 answers (settled before code was written)

1. **HP 1493 vs 1764 is NOT a bug — it's base vs base+augs, unlabeled.** The verdict-card
   tiles read the item's own raw fields (`item_compare.lua` `buildStatRows` — pure module,
   no augment awareness by design), while the "All stats & effects" block adds the summed
   contributions of every filled aug socket (`tooltip_data.lua` builds `augStats`;
   `tooltip_render.lua` `sv(field) = item[field] + augStats[field]`, commented as matching
   the in-game "Augmented" display). Same table, same frame, two formulas. Phase 8 labels
   them per mockup `18a`: tiles show base with a `+N` aug suffix, and the verdict compares
   as-is totals (base+augs on both sides) so it states what actually happens on swap.
2. **HEROIC on a zero-heroic item shows `—`. Confirmed.** Heroics don't flow through
   `item_compare` at all today (no row, no aggregate), so there is no "plain stat total"
   to fall back to — and kit rule §3.7 (“zero is `—`”) makes the em-dash the only honest
   render. The phase-8 type-aware strip adds the HEROIC aggregate with `—` for zero.
3. **Command Center: kept, gated, nothing deleted.** `classicOnly = true` on its
   registration; `registry.isEnabled` + `applyEnabledFromLayout` hide it (launchers,
   render, tick) while `UIMode=bars` and close it live on a mode flip. The file stays as
   the `classic` surface. Reversal is deleting one spec flag.

## Font capability verdict (§3.2, source-verified on pin b659319)

- `ImGui.PushFont(font, size)` sized overload **is bound** (`lua_ImGuiCore.cpp:566-573`),
  along with `GetDefaultFont` and `ImGui.ConsoleFont` (Lucida Console baked at 13px,
  `lua_ImGuiCustom.cpp:39`). `GetEQImFont` also bound.
- Dynamic rasterisation is real on the EMU client: **both** the DX9 and DX11 backends set
  `ImGuiBackendFlags_RendererHasTextures` (`ImGuiBackendDX9.cpp:391`), so a 22px push is
  crisp glyphs, not a scaled bitmap.
- FontAwesome 14 + MaterialDesignIcons 16 are merged into the **default** font
  (`ImGuiUtils.cpp`), so icon glyphs render at the body register with no push.
- Runtime fallback anyway: `utils/fonts.lua` probes the sized overload once inside the
  first frame; on failure heading degrades to body and mono to one-arg
  `PushFont(ConsoleFont)`. In-game smoke of the happy path still owed.

## The kit (phase 7) — what exists now

- `theme.Colors.TextContent` (#a8a8b2, things you read) / `TextFurniture` (#6e6e78,
  things you ignore) + matching text helpers. `Muted` stays for legacy call sites and
  gets retired surface-by-surface as windows rebuild.
- `theme.Kit` — the full §3.1 fill palette, one meaning per entry, with the two
  never-confuse pairs documented (open-blue vs action-blue; solid vs outlined red).
- Kit buttons: `PushGoButton / PushStopButton / PushDestroyButton / PushActionButton /
  PushKitDisabledButton / PushIconButton`, all `FrameRounding=0`, all popped by
  `PopKitButton` (5 colors + 2 vars). Disabled reason is printed beside the control by
  the caller — never a tooltip.
- `constants.UI.KIT`: FONT_HEADING 22 / FONT_BODY 16 / FONT_MONO 13, HEADER_H 26,
  TOOLBAR_H 24, ROW_H 20, PAD 8, GAP_INNER 4. Four heights, nothing else.
- `utils/fonts.lua`: `pushHeading() / pushMono() / pop()`, degrade-safe, stack-balanced
  under every failure the stub can inject.
- `components/window_header.lua`: the 26px band. Contract enforced by shape:
  `title → spec.stat (the one number the bar doesn't show) → icon actions → lock`.
- **All six `SetWindowFontScale` sites are deleted** (item_display tile value ×1.15;
  character_stats 0.95/0.85/0.95/1.0). The scripts mini-table now uses the mono register.
  `grep -rn SetWindowFontScale lua/ --include=*.lua` finds only doc comments.
- Stub: `PushFont/PopFont/GetDefaultFont/ConsoleFont` modeled with a `font` depth counter
  in `balanced()`; `FrameRounding`/`FrameBorderSize` style vars; `GetContentRegionAvail`
  tuple. Suite: `scripts/tests/test_kit.lua`.

## §1.7 verification (loader consolidation) — done, with one hole

Commit `31179bd` collapsed the cached/file loader branches into one `applyLayoutSection`
(`layout.lua:464-616`); both branches call it. Adding a `[Layout]` key is now 3 mandatory
sites (writeLayoutFile, applyLayoutSection, state defaults) + STRING_KEYS when non-numeric.
**Known hole:** `layout_setup.lua` capture/reset never learned the bars keys (chip filed
separately — not this branch's scope).

## Phase 9 — the context-menu system (built)

`components/context_menu.lua` is the one builder; `ui_common.renderItemContextMenu[Contents]`
are thin shells over it, so all seven legacy popup ids plus native_hover's contents-only
host and the Effects window's buff popup (§7's "effect row" context) ride the same
definition. The verb census (adversarially collected before the rebuild) confirmed every
pre-rebuild verb survives; notable census facts recorded for later phases:

- **Sell's `SellWhy_` status popup** carries the one verb that exists nowhere else —
  `Protect <Type>s` (`config_filters_ui.protectType`). It is a bars-phase-6 surface, not a
  context menu; left as-is.
- **Loot window's `LootRuleCtx`** (Always loot / Never loot / un-skip / add-to-reroll by
  name lookup) is loot-row shaped (no bag/slot/id) and stays its own small menu until the
  loot windows get their pass.
- **Reroll redundancy, preserved on purpose:** a reroll row can offer both the instant
  "Reroll it ✓" toggle and the staged "On the reroll list" row (which routes through
  reroll.lua's inline confirm). Same end effect, two paths — today's behaviour, kept for
  parity; collapse it when the Reroll tray work (phase 12) touches that view.
- **Known pre-existing quirk (NOT introduced here):** in the default column order,
  right-clicking Inventory's Clicky cell both fires the clicky AND opens the row menu —
  the row-end `BeginPopupContextItem` attaches to the last-drawn column and the clicky
  handler triggers on the same release edge (census Part 4 has the full mechanics).
- **Rule-6 follow-up owed in phase 8:** the Item Display aug-socket right-click
  (`tooltip_render.lua` socket rows) removes an augment with NO confirmation and no
  modifier — it must become shift-gated with its cost stated when the sockets section is
  rebuilt.
- Deliberate change shipped: menu Destroy is shift-gated, dialog-free (rule 6). The old
  `main_window` confirm block and the Settings skip-confirm checkbox still exist for any
  non-menu destroy path; retire them if those paths die later.

## Phase 8 — Item Display v2 (built)

- **§0.1 landed as convergence:** `item_compare.compare(item, equipped, opts)` takes
  `augStats`/`equippedAugStats` (tooltip_data's cached socket sums) — tiles, verdict and
  summary are aug-inclusive totals, the same quantity the dump shows. One number
  everywhere; the AUGMENTS section itemizes the contributions.
- **Type-aware strip:** weapons (damage>0, delay>0) → DMG · DELAY (betterWhenLower) ·
  RATIO (.1f) · DPS · PROC · ATTACK · HP; everything else → HP · MANA · END · AC · HASTE ·
  REGEN · AUGS; HEROIC rank (7 primary heroics summed) always last, `—` at zero (Q2).
  Weapon verdict = DPS sign, tie → stat sum; attack scores without a tile (values, not
  rows, feed the verdict).
- **View:** identity card owns name/type/value/flags/location (once each); draw-list
  tiles, no per-tile BeginChild (§3.7.1), 22px values; five remembered sections
  (`services/section_state.lua`, per-char `Chars/<name>/sections.ini`, CSV of
  deviations-from-default only); icon toolbar (recents popup ⟲, locate ⌖, refresh ⟳,
  lock glyph = the registry pin); socket rows with left-click-to-open/insert and the
  shift-gated, cost-stated Remove via the augInserted menu context (rule-6 debt paid —
  the confirmation-free icon right-click is unreachable now); ornament slot cached as
  `ornamentLine`, mythic-tinted.
- **§9 shared fixes in tooltip_render:** "Spell Info for X effect:" prefix gone,
  Recovery/Recast zeroes → `—`, `formatSeconds` humanizes durations (600 → 10m) — these
  improve the hover tooltip too.
- **Known deferrals:** BeginItemTooltip is NOT bound on this pin (§4.3) — hover cards use
  IsItemHovered+BeginTooltip; effect-card "Open in Effects/Copy id" actions not built
  (tooltips can't click; the effect rows' menu can host them later); classes/races line
  omitted from the identity card (needs a TLO iteration the item table doesn't carry).

## Phase 10 merge — BUILT 2026-07-31 (plan below kept for the seam map)

What shipped, against the plan:
- `inventory.lua` split into `renderToolbar` / `renderTable` (+ `renderInvTableInner`);
  `render` composes the identical classic pair. `renderMergedContent(ctx, bankOpen)` is
  the bars two-pane host: one toolbar (its search mirrors into `searchFilterBank` — one
  search, both panes, §9), Bags child with `ImGuiChildFlags.Borders|ResizeX` +
  `ImGuiWindowFlags.NoSavedSettings`, Bank child with the 20a chip line (live green /
  `snapshot · <age>` amber + `read-only — open a bank to refresh`), snapshot table dimmed
  via Alpha 0.55 pushed/popped OUTSIDE the pcall'd body. Carrying an item rings the Bags
  pane (accent border, 2px) — bank keeps its no-drop asymmetry, per plan.
- `bank.lua`: `resolveList` + `renderTable` (+ `renderBankTableInner`) extracted; the
  classic window calls them and is otherwise byte-identical. Registration gains
  `classicOnly = true` (CC precedent).
- **Table containment (new invariant, found by the suite):** both extracted tables pcall
  their body INSIDE BeginTable/EndTable — a body throw that skips EndTable is a C++
  ImGuiException (uncatchable, script-killing). Same class as aec75c0's window bodies.
- `InventoryBankSplitX` (numeric, 0 = auto 55%): state default, applyDefaultsFromParsed,
  writeLayoutFile, applyLayoutSection, layout_setup capture + [Defaults] write + reset —
  all seven touch points. Persist fires only when measured width ≠ passed width (a real
  drag), so no auto-width lock-in and no debounce starvation.
- Splitter clamps to ≥220px per pane; regions too narrow for both minimums halve instead.
- main_window's `renderInventoryContent` routes bars → merged, classic → unchanged.
  Merchant-open still swaps the whole content to Sell in both modes.
- bank launcher/menu entries vanish in bars automatically (moduleLabel → nil for
  disabled modules). Hub-chip lighting + the split Bags|Bank pair chip = phase 11 work.
- Suite: `test_inventory_merge.lua` (37 checks; stub grew BeginTable/clipper modeling,
  BeginChild arg recording, geometry overrides). 13 suites / 623 asserts green;
  luacheck 0/0 across 112 files.
- Deferred, needs a user call: 20a's "flip Bank's Status column on by default" — column
  defaults are shared with classic, and classic must render exactly as master (§14.1).

## Phase 10 merge — original seam map (mapped 2026-07-30; built above)

Line-verified seam map (agent-audited at HEAD aec75c0). **Architecture: the merged
two-pane Inventory IS the hub** (`main_window.lua`) — Bags already is the hub, it's the
zone anchor and never zoned, and `main_window.lua:544-552` already drops the button row
in bars mode. No new registry module, no `barsOnly` concept needed.

- **Inventory pane:** `InventoryView.render(ctx, bankOpen)` is already chrome-free.
  Extract `renderTable` = inventory.lua:90-353; toolbar/status (21-88) hoists into the
  merged single toolbar. Non-negotiables verbatim: shift+click at :252, pickup/drop
  :251-277, per-row PushID :229/:348 + one menu call :347.
- **Bank pane:** bank.lua is ONE function (Begin→End) — the risky extraction. New
  `renderTable(ctx, list, bankOpen)` = :149-359 + pre-filter :121-148; live/snapshot
  resolve (:25-27) hoists; un-bank shift+click at :295. Bank has NO drop-on-click branch
  — asymmetry is real behavior, do not "fix". Keep both panes' column namespaces,
  sort keys, perfCache namespaces, placeholder-repair paths SEPARATE.
- **Registry:** `classicOnly = true` on bank's spec (CC precedent). Bank-pane visibility
  reads `layoutConfig.ShowBankWindow` directly (isEnabled is structurally false in bars).
  Leave window_zones GEOM.bank alone (inert, harmless).
- **Splitter:** `BeginChild(id, size, ImGuiChildFlags.ResizeX, ...)` — new-format int
  overload IS bound (lua_ImGuiCore.cpp:438-457) and `ImGuiChildFlags.ResizeX` enum'd
  (lua_ImGuiEnums.cpp:77); zero repo precedent, needs in-client smoke. MUST pair with
  `ImGuiWindowFlags.NoSavedSettings` (ResizeX autosaves to ImGui's own ini otherwise);
  read width back per frame → new numeric key `InventoryBankSplitX`, FOUR sites (state
  defaults, applyLayoutSection, writeLayoutFile, **layout_setup.lua capture/revert**).
- **Chip glue:** merged Bags|Bank chip lights via hub-open OR registry.isOpen("bank")
  (loot special-case at dock_bottom.lua:146 is the one precedent; the OR is defensive —
  bank is classicOnly so effectively hub-only in bars).
- **DECISIONS RESOLVED (user, 2026-07-31):** (1) header Lock glyph = CLOSE-SURVIVAL pin
  everywhere (the registry pin — what Item Display/Effects/Equipment/Aug Utility bands
  already do); resize-prevention stays the existing global uiLocked toggle (the native
  UI's alt+L LOCK_WINDOWS analog) — two controls, two names, no shared word. (2) Bank:
  proceed as planned (classicOnly; pinned classic Bank goes inert in bars).
- **(superseded) DECISIONS NEEDED (user):** (1) the merged header's single Lock: hub's resize-lock
  (`uiState.uiLocked`) vs registry's close-survival pin — two unrelated meanings share
  the word today; (2) accept that a pinned classic Bank window goes inert in bars mode.
- Trivia: `saveLayoutForView`'s dead `bankPanelW` param (layout.lua:724-739) is a relic
  of a PRIOR merged design that was un-done — don't resurrect it; fresh save path.

## §6 section-state design (adopted from the audit)

Per-character section memory goes in **its own file** (`itemui_sections.ini`), one
`[Char:<name>]` section per character read via the existing
`layoutIO.parseSectionsMatching`, storing one CSV key (`SectionsCollapsed=Window.Section,…`)
— the `layout_presets.lua` + `PinnedWindows` precedents combined. Zero `[Layout]` edit
sites touched; revert-to-default can never wipe it (same reason presets live outside the
layout INI). The layout INI is shared across characters (`Macros/sell_config/`), so
per-character means sections-in-file, not per-key.
