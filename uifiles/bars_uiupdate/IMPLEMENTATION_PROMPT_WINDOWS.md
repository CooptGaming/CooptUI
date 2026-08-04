# CoOpt UI — Windows & Menus implementation prompt (v3)

Phase 1–6 (the bars) shipped. This is the next pass: the middle windows, the context-menu
system, and the pairing that makes the bars a hub instead of a decoration.

**Read first:** `SPEC_CORRECTIONS.md` — still authoritative for the ImGui binding facts
(`GetMainViewport` not `DisplaySize`, `NoBringToFrontOnFocus`, the `[Layout]` INI regeneration
trap). Where this file and that one disagree, **SPEC_CORRECTIONS wins**.

**Design mockups:** `CoOpt UI In-Game.dc.html` (turns 17–28). Option ids like `21a`, `24b`
refer to it. Turns 1–13 are archived in `CoOpt-UI-In-Game-Turns-1-13.dc.html`.

**Where two mockups disagree, the higher turn number wins.** Turns 22b/22c are canonical for
*window placement*, but their bars predate turn 27 — build the bar from `26a` (top) and `27a`
(bottom). Specifically: there is no `Hub` chip on the bottom bar (it moved to the `CoOpt`
segment), the native-window menu is called **Native UI**, and every bottom-bar menu caret
points **up** because those menus expand upward.

---

## 0. Answer these three before writing code

They change what gets built, not just how.

1. **Item Display shows HP 1493 in the stat tile and 1764 twelve lines below** (also AC
   102/123, Mana 896/1077). One is the bare item, the other includes its three augments —
   the UI never says which. Find out which is which in `utils/item_compare.lua` /
   `utils/item_tooltip.lua`, then label them (`18a` uses `40` + `<span>+8</span>` for
   base + aug). **If they're the same number computed two ways, one is a bug — report it
   rather than designing around it.**
2. **`HEROIC` on an item with zero heroic stats** — the mockups show `—`. Confirm that's
   right rather than falling back to a plain stat total.
3. **Command Center** (`views/command_center.lua`) is now 100% duplication: the bars carry
   every launcher, Loot All, Auto Sell and every status it showed. Recommendation: keep the
   file, stop registering the window in `bars` mode, leave it as the `classic` surface. Get
   a yes/no before deleting anything.

---

## 1. Ground rules

1. Branch `feature/windows-pass` off the bars branch. Nothing on `master`.
2. `UIMode = classic | bars` still governs. `classic` renders exactly what it renders today —
   every change in this document is `bars`-only.
3. Existing structure: views in `views/`, services in `services/`, helpers in `utils/`,
   shared widgets in `components/`.
4. New modules take `init(d)` and keep deps in one file-local. Do not add locals to `app.lua`
   (83 KB, and Lua's 200-local / 60-upvalue ceilings are live here).
5. Colours come from `theme`'s exported helpers, never hand-rolled `PushStyleColor` pairs.
   Two new entries are required — see §3.
6. Luacheck runs on the PR: no globals, no undefined variables, `local M = {} … return M`.
7. **No new INI keys until the config loaders are consolidated.** Phase 1 of the bars work
   was supposed to do this; verify it did. Section-state persistence (§6) adds ~8 keys and
   they will silently revert otherwise — that reads as a bug to users.

---

## 2. Non-negotiable — nothing loses functionality

| Behaviour | Where it lives | After |
|---|---|---|
| Left-click picks the item up | `services/item_ops.lua:804` `pickupFromSlot(bag, slot, source)`, via `ctx.pickupFromSlot` | unchanged |
| Shift+click banks / un-banks | `views/inventory.lua:252`, `views/bank.lua:295` (`ImGui.GetIO().KeyShift`) | unchanged |
| Right-click context menu | `components/ui_common.lua:168` `renderItemContextMenu`; seven popup ids (`ItemContextInv_`, `ItemContextBankIcon_`, `ItemContextSellIcon_`, `ItemContextEquip_<slotIndex>`, `ItemContextAugmentsIcon_`, `ItemContextMythIcon_`, + `reroll.lua:450`) | **rebuilt as one builder — §7. Every verb that exists today must still exist.** |
| Right-click a clicky fires it | `views/inventory.lua:296` `/itemnotify … rightmouseup` | unchanged |
| Hover stats tooltip | `utils/item_tooltip.lua`, `utils/tooltip_render.lua` | unchanged |
| Equipment slot click / swap | `views/equipment.lua:233,236` `/itemnotify <slotName> leftmouseup` | unchanged |
| Quantity picker, cursor bar, confirms | `main_window.lua`, `item_ops.lua`, `main_loop.lua` | unchanged |
| Columns: show/hide, reorder, resize, sort | `utils/columns.lua`, `layout_columns.lua`, `column_config.lua`, `app.lua:684 TABLE_FLAGS` | unchanged — **leave `TABLE_FLAGS` alone** |
| Esc LIFO close | `main_window.lua` + registry pinned ids | unchanged |

### The interaction model — read this twice

**There is no selection state anywhere in this UI.** No highlighted row, no checkbox column,
no ctrl+click, no "12 selected". An item is either on your cursor or it isn't. Do not
introduce a selection model; several mockups were corrected specifically to remove one.

- **Left-click picks up. That is how items move.** Not drag-and-drop — pick-up-then-place,
  the game's own idiom.
- A **2px `#4296fa` ring** on a row or slot means *this will take what's on your cursor*. It
  appears only while you are carrying something (`23a`, `23b`).
- The source row **dims to ~45%** while its item is on the cursor.
- **`#161b22` fill = hover**, the row under the pointer. Nothing else.
- Buttons like Aug Utility's `Insert` are shorthand for pick-up-then-place — they must go
  through the same `item_ops` path, not a separate mechanism.
- **Right-click is where most work happens.** §7 is therefore the highest-value item in this
  document, not the windows.

---

## 3. The kit — build this first (`21a`)

Nine decisions made once. Every window below is then assembly. Do not start a window before
this exists.

### 3.1 Palette — add exactly two entries to `coopui/utils/theme.lua`

`Colors.Muted = {0.5, 0.5, 0.55}` (#808088) is currently doing two jobs — labels you must
read and separators you must ignore. Split it:

```
TextContent   #a8a8b2   labels, secondary values, anything you read
TextFurniture #6e6e78   separators, hints, units, placeholder text
```

Then the full set, one meaning each:

| Fill | Meaning |
|---|---|
| `#0f0f0f` / border `#4b4b52` | window body |
| `#0f1c2e` | ImGui title bar — inherited, never restyled |
| `#161b22` | window header, and the row under the cursor (hover) |
| `#1b1b1b` | inset: stat strip, icon buttons, tray cells |
| `#2b2b30` | every divider; every disabled fill |
| `#ffffff` / `#a8a8b2` / `#6e6e78` | value / label / furniture |
| `#12161c` + 2px `#4296fa` | **on a bar**: this launcher's window is open |
| `#161b22` + 2px `#4296fa` | **inside a window**: this is the active tab |
| 2px `#4296fa` ring | this will take what's on your cursor |
| `#23456d` | action button — navigates or commits (Insert, Send, Open X) |
| `#1b3a1f` / `#338c40` / `#7fd98f` | go button |
| `#8c2b2b` solid, white label | **stop** button — interrupts a running job |
| `#3a1b1b` / `#8c2b2b` / `#e69090` | **destroy** button — destroys something you own |
| `#40bf59` / `#e6b333` / `#e64040` | good, gain, live / attention / loss, blocked |
| `#66bfff` | spell or effect name |
| `#c8a8e6` | mythic and ornament |
| `#161310` / `#0f1610` / `#1a1010` | bar segment wash: running / finished / stopped badly |

Two pairs must never be confused: open-state vs action blue, and solid vs outlined red.
A window that wants a colour outside this table doesn't get one.

### 3.2 Type — three registers, rasterised

MQ already loads Roboto 16, a 22px "Large" set, FontAwesome 14 and MaterialDesignIcons 16, and
binds them to Lua. There are **zero `PushFont` calls in 11,312 lines of `itemui`** — the whole
app runs at one size.

- **22px** — item name, window headings
- **16px** — body: labels, rows, buttons, bar text
- **13px mono** — number columns only. Makes stat strips and tables right-align for free.

**Verify on the EMU client before building:** that `ImGui.PushFont` accepts a size argument on
your pin (dynamic font sizing is an ImGui 1.92 feature; the pin is ~2 months behind master),
and that `GetEQImFont` / the Large set resolve at runtime. If the size argument isn't there:
push the existing 22px set for headings, leave body at 16px. Still an improvement.

### 3.3 Delete all six `SetWindowFontScale` call sites — this is the crispness fix

`SetWindowFontScale` stretches the rasterised 16px atlas bitmap. It is literally the blur.

- `views/item_display.lua:160` (1.15× on every tile value) and `:162` (its reset)
- `components/character_stats.lua:260` (0.95), `:386` (0.85), `:400` (0.95), `:402` (reset)

Replace with `PushFont` at a real size, or with no scaling at all. This is a deletion and it's
the change you notice from across the room. Do it first.

### 3.4 Vertical rhythm — four fixed heights, nothing else

| Element | Height |
|---|---|
| title bar | 22px (ImGui default) |
| window header | 26px |
| toolbar / tab strip | 24px |
| table row | 20px |

8px window padding, 8px between groups, 4px inside a group. Both bars are 30px.

### 3.5 Controls — flat and square, `FrameRounding = 0`

Four kinds, and that's the set: **go** (outlined green, starts something), **stop** (solid red,
interrupts a running job), **destroy** (outlined red, destroys something you own), **action**
(blue, navigates or commits). Disabled = `#2b2b30` **with the reason printed beside it, never
in a tooltip**.

Every green start button becomes its solid-red Stop **in place** — same slot, same width.

### 3.6 Header contract

`name → the one number the bar does NOT already show → icon actions → lock`

The bar owns: bag count, XP, buffs, session, loot and sell progress. **A window that restates
any of those loses the space instead.** Bags shows `7,399p 0g total · last scan 19:52:51`.
Equipment shows `3 upgrades in bags`. Effects shows `Buffs 16/30 · Songs 1 · Auras 1`.

### 3.7 Three rules that keep it clean as it grows

1. A stat tile, a table cell and a bar segment are **never scroll regions**. If content
   doesn't fit, the container is wrong. (`ITEM_DISPLAY_TILE_HEIGHT = 54` in `constants.lua`
   can't hold label + value + delta + 8px child padding at 16px text ≈ 58px, so every tile
   currently renders a scrollbar and clips its own delta. Kill the `BeginChild` per tile.)
2. **Zero is `—`.** Never `0.00`. Never a raw tick count where minutes exist (`600` → `10m`).
3. Sections remember open/closed **per window**, in one INI table. See §1.7.

---

## 4. ImGui features to use — you're hand-rolling most of these

Highest value first.

1. **`BeginTable`** with `Sortable | Resizable | Reorderable | ScrollY | RowBg` +
   `TableSetupScrollFreeze`. Replaces the hand-rolled column code and `column_config`'s manual
   sort. Sort-by-click, drag-resize, reorder and frozen headers come free, and the sort spec
   replaces your sort function.
2. **`BeginChild` with `ImGuiChildFlags_ResizeX`** — the `23a` splitter, persisted.
3. **`BeginItemTooltip`** — the effect/spell hover cards (`18a`, `22c`). Proper delay and
   positioning instead of a manual popup.
4. **`BeginPopupContextItem`** — anchors menus to the row, not the cursor. §7 depends on this.
5. **Docking** — *check whether your MQ pin has it enabled.* If yes, `23a`'s pair becomes a
   real dock node and layout presets become dock layouts for free. If no,
   `SetNextWindowPos` against `GetMainViewport().WorkSize` does the same job manually, which is
   what `22b`/`22c` assume. Report which you found before building §8.
6. `BeginDragDropSource/Target` — **only** as a convenience layer on top of pick-up-then-place,
   never as the primary mechanism, and never as the only way to do something.

---

## 5. Phase order

| Phase | What | Mockups | Why here |
|---|---|---|---|
| **7** | The kit: theme split, `PushFont`, delete the six `SetWindowFontScale` calls, `FrameRounding = 0`, four heights, header contract, shared 26px header widget in `components/` | `21a`, `17d` | everything else is assembly on top; phase 7 alone visibly sharpens the whole app |
| **8** | Item Display v2 — condensed layout, type-aware stat strip, hover cards, ornament slot, section memory | `17b`, `17c`, `18a`, `19a` | biggest single window win; already reviewed twice |
| **9** | One context-menu builder, seven contexts | `24a`, `24b` | highest usability win in the document |
| **10** | Bags + Bank merge into `Inventory`; Equipment paper-doll pass; Effects pass | `23a`, `19d` | needs phase 7's header + phase 9's menus |
| **11** | Item Display ↔ Aug Utility subject link; fold the Augments window into Aug Utility's `All` tab; pair chips on the bottom bar; Hub list | `23b`, `23c` | needs 8 and 10 done |
| **12** | Bank live/snapshot chip, Reroll tray, Aug Utility slot map | `20a`, `20b`, `20c` | independent; can slip |
| **13** | Top bar rebuild — new segment order, one action lane, sell + weight cells, all job states, every segment a toggle | `26a`, `25a`, `21c` | touches `dock_top.lua` only |
| **14** | Session strip — four counts, hover panels, the triage queue | `26b`, `26c`, `25b` | needs phase 9's menu builder |
| **15** | Script Tracker folded into ItemUI | `25c` | independent; can slip |

Each phase ships alone and `classic` keeps working throughout.

---

## 6. Section state persistence

Collapsibles remember open/closed **per window, per character**: `ALL STATS` open,
`SPELL DATA` closed, and they stay that way. One INI table under `[Layout]`, keys like
`Section_ItemDisplay_AllStats=1`. **Read §1.7 first** — if the config loaders are still
duplicated, consolidate them in this phase or the keys will revert.

---

## 7. The context-menu system (`24a`, `24b`) — the real overhaul

Today each view builds its own menu block and they have drifted. Same augment, right-clicked in
Bags vs Bank vs the slot map, offers different verbs. That drift is the bug users feel as
"the menu is different here."

**Build one menu builder.** Each row declares which contexts it appears in and what disables it.
Seven contexts share one skeleton: **item in bags, item in bank, equipped item, inserted
augment, ornament, empty aug slot, effect row.**

### Anatomy — fixed, in this order

```
[identity header]  icon · name · where it is
LOOK        →  open, compare, submenu for its effects
MOVE        →  send, equip, insert, swap
RULES       →  keep / reroll / never-sell, with ✓ showing current state
(no heading)→  destructive: sell, remove, destroy
```

### The eight rules

1. **Identity first, always.** Icon, name, and where it is. You right-clicked one row out of
   158 — confirm which before offering to destroy it.
2. **Four groups, fixed order.** Muscle memory works because position is stable even when
   contents differ. The destructive group has no heading, just a separator — it reads as
   "past here, be careful."
3. **Blocked entries stay in place and state why, in the row.** `Equip — wrong slot type`.
   Removing them shifts everything below and breaks rule 2; a tooltip hides the answer.
4. **Rules show state with a check, not a verb.** `✓ Keep — clicky list` tells you *why* it's
   protected. Toggling reads as a state change, not a command with an invisible result.
5. **Effects and augments get a submenu**, not a flattened list — and the submenu header
   re-states which effect (rule 1 again).
6. **Destroy always needs a modifier and the row says which** (`hold shift`). No confirmation
   dialog: faster to learn, impossible to click through by habit, doesn't steal the keyboard
   mid-fight.
7. **The same object offers the same menu in every window.** One definition, rows switched off
   by context.
8. **Anything you do constantly earns a place in the window** — Aug Utility's `Insert`,
   Equipment's `Equip all 3`. The menu keeps them too; that duplication is deliberate.

Destructive rows state their cost: `Remove it — uses 1 solvent`, `Sell now — 37p 5g`.

Copy style: every phrase is a question or a plain verb. "Anything better in my bags?" not
"Compare". "What fits here?" not "Filter compatible".

---

## 8. Window pairing (`23a`, `23b`, `23c`)

Three relationship kinds — don't apply the wrong one:

- **Merge** when you never use A to answer a question about B → **Bags + Bank become one
  `Inventory` window**: two panes, one header, one splitter, one toolbar. Bank keeps its own
  live/snapshot chip (that state is per-source).
- **Link** when they answer different questions about the same subject → **Item Display ↔ Aug
  Utility**, Equipment ↔ Item Display, Reroll ↔ Inventory. One selection bus: whatever you last
  clicked is the subject everywhere, shown as `🔗 <subject>` in the header, with a **pin** to
  freeze it.
- **Standalone** when the subject is a list, not an item → Mythics, AA, Effects, Settings.
  No linkage; don't pretend.

**Bar synergy:** a pair is one chip split by a hairline (`Bags | Bank`,
`Item Display | Aug Utility`), and the open pair lights the whole chip. Standalone windows are
plain chips. **Hub** is the same launcher list vertically with shortcuts + layouts — not a
duplicate, the same list in a readable form.

**One consolidation:** the Augments window is deleted. Its 240 rows are Aug Utility's `All`
tab — the same list it filters when you pick a slot. One window, one shortcut.

---

## 9. Redundancy pass — delete these

- Item Display: the item name appears **4×** (tab, combo, card header, all-stats) → once.
  Location **3×** → once.
- Bags and Bank each had search / refresh / column menus → one toolbar in `Inventory`.
- Aug Utility restated the target item's identity → just `🔗 Black Scythe`, since Item Display
  is beside it.
- `RecoveryTime 0.00` / `RecastTime 0.00` printed as zeroes → `—`.
- `"Spell Info for … effect:"` prefix, six words per line → gone.
- Duration `600` → `10m`.
- Per-pane "how to use this" lines → one footer.
- Command Center → see §0.3.

---

## 10. Keybinds

The shortcuts in `23c` (`alt+i`, `alt+d`, `alt+m`, `alt+r`, `alt+e`, `alt+b`, `alt+a`,
`F1`–`F3`) are a **proposal, not a spec**. Before wiring any of them, audit what's already
taken across **MQ, the EQ client itself, and `config/MQ2CustomBinds.txt`**, then propose a set
from what's actually free. Every menu command needs a keyboard equal; nothing is
pointer-only.

---

## 11. Top bar rebuild (`26a`, `25a`)

### Segment order, left to right — fixed widths, nothing moves between states

| Segment | Width | Opens |
|---|---|---|
| `CoOpt` + status dot | 190 | Hub |
| session — money, augs, mythics, scripts | 470 | per value; see §12 |
| bags + weight | 230 | Inventory |
| sell — count + value | 200 | Inventory, sorted to what would sell |
| `Loot All` `Auto Sell` | 240 | — they start jobs, they never open windows |
| **the action lane** | flex (~712) | whichever window owns the running job; session log when idle |
| buffs / songs / aura | 270 | Effects |
| XP / AA | 240 | AA |

Fixed total 1840 at 2554px. **The lane is the only cell that flexes and the only cell that
may ellipsize.** Fixed cells never resize between states — that is what stops the bar
twitching while a job runs.

### One lane, two owners

Loot All and Auto Sell sit **together** and **never move**. Whichever run starts owns the lane;
the other button greys with its reason. **A green start button becomes its own solid-red Stop
in place — same slot, same width** — so the user's hand never moves.

States the lane must render (`21c`, `25a`): idle (name what it's for, don't sit empty),
running (label + progress + live counts + Stop), finished (hold the result 6s, say what it
*couldn't* do, then fall back to idle), blocked (keep the job, offer the way out inline),
stopped part-way (say what was **not** consumed), plugin-down.

Sell moved out of the lane on purpose: "34 items worth 2,110p" is true whether or not a run is
going, so it is a standing fact, not job output. The lane is *what is happening*; that cell is
*what is waiting*. It ticks down live during a sell run and reads `0 —` when empty.

### Every segment is a toggle

Click opens the window, click again closes it. The lit pair (`#12161c` + 2px `#4296fa`) already
means "this window is open" everywhere else, so no new vocabulary is needed. Buttons are not
segments.

---

## 12. Session strip and triage (`26b`, `26c`)

Four values: money, augments, mythics, scripts. Each is its own hover panel and its own click
target. Hovering shows what was picked up and when; a zero value renders muted and inert so the
strip never invites a dead click.

### The counting rule — this is the whole design

**The bar counts only what still needs a call, not what was looted.** So `3 augs` is a to-do,
not a trophy, and it can reach `0` on a long night. Counts render **amber** (`#e6b333`) while
they need a call, white when clear. Scripts stay white — there is no decision, only a turn-in.

**Nothing ever leaves the session.** A decided item drops into a collapsed `SORTED` section
grouped by what was chosen. The panel header carries the truth: `12 looted · 3 need a call ·
9 sorted`. Removing items would make it a queue; keeping them makes it a record — split the
number, not the list.

### Prior decisions pre-empt the queue — do not skip this

**An item only enters `NEEDS A CALL` if no existing decision already covers it.** If a looted
augment is already on the reroll list, already matches a keep rule or an always-junk rule, or is
NoDrop and therefore not sellable, it lands **straight in `SORTED`** with the reason shown, and
**never increments the amber count**. Evaluate against the existing rule sources — the reroll
list, the keep/clicky list, sell rules and protected types — at the moment the item is recorded,
not when the panel is opened.

This is what keeps the feature honest: the queue is *only* things genuinely not ruled on, so a
well-tuned rule set means most nights it sits at `0`. If it fills up with things the user
already decided months ago, they will stop looking at it within a week.

### Panel behaviour

- Rows sorted **by value, best first** — triage only pays if the top row is worth thinking about.
- Each row states **why it deserves attention**: "fits 3 of your slots" vs "fits nothing you
  own". Without that line the user is just reading names.
- Three inline chips cover the common calls (**Keep / Reroll / Junk**), with impossible ones
  greyed and the reason inline. **Right-click opens the same menu builder from §7** — a hover
  panel is just another place to open it.
- `↑↓` walks rows, `K`/`R`/`J` decide, `Z` undoes the last decision, `esc` closes.
- Hover must be forgiving: the panel survives the gap between bar and panel and stays while the
  pointer is inside it. Anything walkable by arrows must also be reachable without a mouse.
- Panels with **no per-item decision get no chips, no walkable list and no `SORTED` section** —
  money reports, scripts convert. If there is no decision to make, it does not need a queue.

**Open question for the user:** does the session end at logout? Recommendation is no — keep it
running until cleared, with a `Clear` in the panel header, so it is a small actionable loot log
rather than a counter that resets when the client crashes.

---

## 13. Script Tracker, folded in (`25c`)

Today it is `/lua run scripttracker` — a separate script with its own window, its own `PIN`
checkbox and its own 300ms inventory fingerprint scan. Fold it into ItemUI:

- It gets the shared 26px header, the suite's lock, a launcher and the session counter.
- **It stops scanning bags a second time** — `core/cache` already holds the item list it wants.
- `SCRIPT_DEFS` survives as-is (three families × five tiers, 1–5 AA) but stops being a hardcoded
  list in a standalone file: it becomes the thing that also teaches sell rules and the loot
  filter what a script is worth, so a Legendary can't get vendored by accident.
- Lost, Planar and Rebirthed are worth the same at a given tier, so they share a row — that is
  the existing tool's logic, kept.
- **Turn-in runs as a job in the lane** (§11) with a progress bar and a Stop; handing in 38 items
  one at a time is exactly what a user needs to be able to interrupt.

**Confirm before building:** is turn-in a click on the item, or does it need a merchant/NPC? The
mockup assumes consume-from-bags. If it needs an NPC, the lane's blocked state should read
`no turn-in NPC nearby` the same way Auto Sell reads `no merchant`.

---

## 14. Acceptance

1. `UIMode=classic` renders exactly what `master` renders. Diff a screenshot.
2. Every row in §2's table still works in `bars` mode. Walk them one at a time.
3. No `SetWindowFontScale` calls remain in `itemui`. `grep` proves it.
4. No scrollbar appears inside any stat tile, table cell or bar segment at 1920×1080 or
   2554×1368.
5. Right-clicking the same augment in Bags, Bank, the slot map and Aug Utility produces the
   same menu, modulo context-disabled rows.
6. No selection state exists: no ctrl+click handler, no `selected` table, no highlighted-row
   state outside hover.
7. Section open/closed survives a `/lua restart` and a relog.
8. Luacheck clean.
9. Both layouts in `22b` / `22c` reproduce at 2554×1368 with nothing overlapping and the
   centre band clear.
10. Bar cell widths are identical in every job state — screenshot idle and mid-run and diff the
    segment boundaries. Only the lane changes width.
11. Loot All and Auto Sell never change position, and each becomes its own Stop in place.
12. An augment already on the reroll list, looted fresh, appears in `SORTED` and does **not**
    increment the amber count. Same for a keep-rule match and for a NoDrop item.
13. Clicking a lit bar segment closes its window.
