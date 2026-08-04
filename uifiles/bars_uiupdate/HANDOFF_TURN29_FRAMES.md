# Turn 29 — build spec for the master frames

Everything here is measured off `CoOpt UI In-Game.dc.html`, turn 29. That file is the
reference; this document is the arithmetic so you can reproduce it without eyeballing.

Read alongside:
- `IMPLEMENTATION_PROMPT_WINDOWS.md` — the kit, the menu builder, the bar, the session strip
- `SPEC_CORRECTIONS.md` — ImGui binding facts, still authoritative
- Where two mockups disagree, **the higher turn number wins.**

---

## 0. Two findings from reading the repo — these change the plan

**Docking is not enabled and nothing uses it.** No `DockSpace`, no `ConfigFlags`, no dock node
anywhere in `itemui`. Do NOT add docking to build these frames. `services/window_zones.lua`
already does the job and does it better for this case:

- Zones `L1 L2 R1 R2 B1 B2` — a column plus a preference rank, relative to the hub
- `M.GAP = 6`, `M.MAGNET_PX = 12`, `M.DRIFT_PX = 8` (drift marks a window user-placed forever)
- Geometry keys per module are already mapped in `M.GEOM`
- Placement writes `layoutConfig` X/Y and raises `uiState.layoutRevertedApplyFrames`

Every frame below is therefore **a zone arrangement, not a dock layout**. The window pairs from
`23a`/`23b` are a placement convention plus a shared subject — not split dock nodes.

**Much of turns 24–28 already exists.** `components/context_menu.lua` already carries the
four-group anatomy and quotes Rule 3 in its header. `views/script_tracker.lua`,
`views/chat_window.lua`, `views/dock_top.lua`, `views/dock_bottom.lua`,
`components/hub_list.lua`, `services/layout_presets.lua`, `services/hints.lua` all exist.
Merchant and banker auto-open already work. **Extend these; do not rewrite them.**

Preset names: the bundled five in `layout_presets.lua` are `Bag session`, `Farming`,
`Merchant run`, `Gearing up`, `Raid - minimal`. The frames use those names. Keep them.

---

## 1. What "looks exactly like the mockup" means

Six things produce the look. Miss any one and it reads as a different design.

1. **No `SetWindowFontScale`, anywhere.** Six call sites remain (`views/item_display.lua:160`
   and `:162`; `components/character_stats.lua:260`, `:386`, `:400`, `:402`). Scaling a
   rasterised atlas is literally the blur. Delete them. This is the single biggest visual win.
2. **`FrameRounding = 0`.** Everything is square. No rounded buttons, no rounded frames.
3. **Three type registers only** — 22px item names and window headings, 16px body, **13px
   mono for every number**. The mono column is what makes stat strips and tables align
   without manual padding.
4. **Four fixed heights** — title bar 22, window header 26, toolbar/tab strip 24, table row
   20–24. Nothing else.
5. **8px window padding, 12px between windows, 12px screen margin.** Never 10, never 15.
6. **One meaning per colour** (§3). Two pairs must never blur: open-state blue vs action blue,
   and solid red (stop a job) vs outlined red (destroy a thing).

---

## 2. Frame geometry

Client **2554×1368**. Bars are 30px, screen margin 12px, so the work area is **y 42 → 1326**.
Each frame states its own column set; the only universal rules are 12px everywhere and
columns summing to the viewport.

### 29a — Farming

```
columns:  12 + 880 + 12 + 720 + 12 + (rest = game)
Inventory   12,  42   880 × 880
Chat        12, 934   880 × 392
Loot       904,  42   720 × 620
```

Chat sits directly under Inventory in the same L column; `chat_window.lua` already anchors to
the bar. Most of the screen stays game — correct for this activity.

**Loot is not a launcher.** No bottom-bar chip; it opens itself on a run. That is why the bar
shows only `Bags` lit while three windows are visible.

### 29b — Gearing up

```
columns:  12 + 620 + 12 + 980 + 12 + 906 + 12  = 2554
Equipment      12,  42   620 × 1284
Inventory     644,  42   980 × 636
Reroll        644, 690   980 × 636
Item Display 1636,  42   906 × 636
Aug Utility  1636, 690   906 × 636
```

Five windows, no game visible — correct, this job is done at a bench. The right column is the
linked pair: `🔗` in both headers, Item Display's slot 3 ringed, Aug Utility filtered to what
fits it. Equipment's Primary tile carries the same ring because it is what put the item there.

---

## 3. Palette — one meaning each

Add exactly two entries to `utils/theme.lua`. `Colors.Muted` currently does two jobs; split it:

```
TextContent    #a8a8b2   labels, secondary values, anything you read
TextFurniture  #6e6e78   separators, hints, units, placeholders
```

| Token | Where |
|---|---|
| `#0f0f0f` body, `#4b4b52` border | every window |
| `#0f1c2e` | ImGui title bar — inherited, never restyled |
| `#161b22` | window header, **and the row under the cursor** |
| `#1b1b1b` | inset: stat tiles, icon buttons, tray cells, paperdoll slots |
| `#2b2b30` | every divider; every disabled fill |
| `#12161c` + 2px `#4296fa` | **on a bar**: this window is open |
| `#161b22` + 2px `#4296fa` | **inside a window**: this is the active tab |
| 2px `#4296fa` ring | this will take what's on your cursor |
| `#23456d` | action button — navigates or commits |
| `#1b3a1f` / `#338c40` / `#7fd98f` | go button |
| `#8c2b2b` solid + white | **stop** — interrupts a running job |
| `#3a1b1b` / `#8c2b2b` / `#e69090` | **destroy** — destroys something you own |
| `#40bf59` good/gain · `#e6b333` attention · `#e64040` blocked | values |
| `#66bfff` | spell or effect name |
| `#c8a8e6` | mythic; `#8c6bab` for ornament labels |
| `#101a10` +3px `#40bf59` | verdict strip, good |
| `#161310` +3px `#e6b333` | verdict strip, running or caution |
| `#14120e` | (mockup only — stands in for the game) |

---

## 4. Window anatomy — every window, no exceptions

```
22px  ImGui title bar        "CoOpt UI <Name>"          inherited chrome
26px  header    #161b22      name · the one number the bar does NOT show · icons · lock
24px  tab strip (if any)     active tab = #161b22 + 2px underline
      body                   8px padding
24px  footer (if any)        input rules left, live state right
```

**Header contract.** The bar owns bag count, XP, buffs, session, loot and sell progress. **A
window that restates any of those loses the space instead.** Each window shows the one thing
the bar cannot:

| Window | Header line |
|---|---|
| Inventory | `7,399p total · last scan 19:52:51` |
| Equipment | `3 upgrades in bags` |
| Item Display | `🔗 drives Aug Utility` |
| Aug Utility | `🔗 Black Scythe` |
| Reroll | `9 of 10 loaded · 1 slot free` |
| Scripts | `38 in bags · worth 97 AA · last scan 19:52:51` |
| Loot | `corpse 4 of 11 · a decaying skeleton` |

**Verdict strip.** Windows with a headline answer open the body with one: a 3px left border,
tinted fill, the verdict in colour, the qualifier in `#a8a8b2`, actions right-aligned.
Examples: `▲ Upgrade … +48 dmg +8 heroic`, `97 AA waiting … Turn in all 38`,
`9 ready · costs 9 solvents · you have 34`.

---

## 5. Density — the rule that makes it look like the mockup

**Every window is drawn full.** The row counts in the mockup are the row counts that fit. A
window that is 40% empty is the wrong size or missing a section — in the client that reads as
unfinished, and it is the single most common way this will drift from the design.

Reference: Inventory at 880px tall = **33 rows at 22px** + a summary line. Equipment at 1284px
holds the 23-slot paperdoll at 66px per tile plus five sections beneath it.

Rules that follow from this:

- **A stat tile, a table cell and a bar segment are never scroll regions.** If content does
  not fit, the container is wrong. `ITEM_DISPLAY_TILE_HEIGHT = 54` in `constants.lua` cannot
  hold label + value + delta + child padding at 16px (needs ≈58), so every tile currently
  renders a scrollbar and clips its own delta. **Kill the `BeginChild` per tile.**
- **Zero is `—`.** Never `0.00`. Never a raw tick count where minutes exist (`600` → `10m`).
- When a window has spare height, add a section that answers a question the main content
  raises — never filler. Equipment's spare height became *ornaments worn* and *what is holding
  you back*; Reroll's became the run log that reveals **2 of 14 came out better**.

---

## 6. Numbers must reconcile across windows

Every number visible in two places must agree, and every total must equal its parts. This was
the most frequent defect in review and it will be the most frequent defect in the build.

Concrete invariants in these frames:

- Scripts: per-tier AA sums to the header total (`10+4+12+7+... = 97`), session subset = 33
- Reroll tray: 9 tile values sum to `320p 2g`; `9 loaded + 1 free = 10`
- Inventory search: `18 of 225` matches 18 rows and `the other 207`
- Aug Utility: 12 rows + `2 more` = the stated 14 candidates
- Item Display: 2 filled + 3 empty = `2/5`
- Equipment: the 18 tiles' aug counts sum to 30 = `slots filled 30 / 37`, and `30+5+2 = 37`
- Reroll log: **`became` is always the value the item carries now**, in every other window
- Loot: `taken` count + progress % agree with the top bar's lane

Bar and window must agree too: if the bar says `bags 274/300`, Inventory's row count and
footer must not say otherwise.

---

## 7. Interaction — read twice

**There is no selection state anywhere in this UI.** No highlighted row, no checkbox column,
no ctrl+click, no "12 selected". Do not introduce one.

- **Left-click picks up. That is how items move.** Not drag-and-drop — pick-up-then-place, the
  game's own idiom, through the existing `ctx.pickupFromSlot`.
- A **2px `#4296fa` ring** means *this will take what's on your cursor*. It appears only while
  you are carrying something.
- The **source row dims to ~45%** while its item is on the cursor.
- **`#161b22` fill = hover.** The row under the pointer. Nothing else.
- Buttons like Aug Utility's `Insert` are shorthand for pick-up-then-place and must go through
  the same `item_ops` path — not a second mechanism.
- **Right-click is where most of the work happens.** One menu builder, seven contexts, four
  groups in fixed order (LOOK → MOVE → RULES → destructive). Blocked rows stay in place and
  state why *in the row*. Destroy needs a modifier and the row says which.

Every bar segment is a **toggle**: click opens its window, click again closes it. Buttons
(`Loot All`, `Auto Sell`) are not segments — they start jobs and never open windows.

---

## 8. Build order

| Step | What | Why first |
|---|---|---|
| 1 | Delete the six `SetWindowFontScale` calls; `FrameRounding = 0`; theme split; `PushFont` at 22/16/13-mono | sharpens the whole app before anything is rebuilt |
| 2 | Shared window shell in `components/` — 22/26/24 chrome, header contract, verdict strip, footer | every frame is then assembly |
| 3 | Kill the per-tile `BeginChild` in Item Display; raise `ITEM_DISPLAY_TILE_HEIGHT` to 58 | removes the visible scrollbars |
| 4 | Rebuild Inventory, Equipment, Item Display, Aug Utility, Reroll, Loot, Scripts against §4 and §5 | the frames |
| 5 | Wire the subject link (`🔗` + pin) and the ring/dim cursor states | §7 |
| 6 | Zone rects for `Farming` and `Gearing up` in `layout_presets.lua` | §2 |

Each step ships alone. `UIMode=classic` must keep working throughout.

---

## 9. Acceptance

1. `grep -r SetWindowFontScale lua/itemui` returns nothing.
2. No scrollbar appears inside any stat tile, table cell or bar segment at 1920×1080 or
   2554×1368.
3. Applying `Gearing up` at 2554×1368 produces the five rects in §2 exactly.
4. Every window is ≥85% filled at its natural size — screenshot each and check for dead bands.
5. Every number in §6 reconciles. Walk the list.
6. No selection state exists: no ctrl+click handler, no `selected` table, no highlighted-row
   state outside hover.
7. Right-clicking the same augment in Inventory, Reroll, the slot map and Aug Utility produces
   the same menu, modulo context-disabled rows.
8. Clicking a lit bar segment closes its window.
9. `UIMode=classic` renders exactly what `master` renders. Diff a screenshot.
10. Luacheck clean.

---

## 10. Still open

- **1920×1080 and 4K frames** are not drawn yet. Same arithmetic against a different viewport
  — the zone placer already reads it. Build 2554 first.
- **`Merchant run` and the everything-open stress frame** are not drawn yet.
- **`augments` and `augmentUtility` are still two registered windows.** Turn 23c folds the
  first into the second's `All` tab: same 240 rows, one launcher, one shortcut. Confirm before
  deleting the view.
- **Command Center** is now fully duplicated by the bars. Recommendation: stop registering it
  in `bars` mode, keep the file as the `classic` surface. Get a yes/no before deleting.
- **Keybinds** in `23c`/`28b` are a proposal. Audit MQ, the EQ client and
  `config/MQ2CustomBinds.txt` for what is free before wiring any of them.
