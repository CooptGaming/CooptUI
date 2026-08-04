# CoOpt UI — windows pass handoff

For a Claude Code session working in `lua/itemui` on branch `feature/windows-pass`.
Design is complete. Everything below is specified; none of it needs a design decision.

**Design sources** (open in the Omelette project, not this repo):

| File | What it holds |
|---|---|
| `CoOpt UI Master Sheet.dc.html` | **Start here.** Per-window board, both bars, all seven items, menu matrix, sizing deltas, corrections ledger. |
| `CoOpt UI Windows.dc.html` | Every window drawn in final state, one consistent scene. Use as the visual target. |
| `CoOpt UI Build Spec.dc.html` | The seven items in full, with every degradation. |
| `CoOpt UI Geometry.dc.html` | Sizing argument, zone map, small-width behaviour. |
| `CoOpt UI Canon.dc.html` | Per-window reasoning. Rationale, not spec. |

`IMPLEMENTATION_PROMPT_WINDOWS.md`, `HANDOFF_TURN29_FRAMES.md`, `IMPLEMENTATION_PROMPT.md`
and `SPEC_CORRECTIONS.md` are superseded — ignore them.

---

## Binding rules

1. **ASCII only** in every rendered string. Glyphs are `\xNN` escapes.
   `test_ascii_strings.lua` enforces this.
2. **The separator is a period with a space each side** — `" . "`. Never a middot.
   Matches `context_menu.lua`'s existing `"Bag %s . Slot %s"`.
3. **Never author X/Y.** `window_zones.tick` recomputes position every frame from the work
   rect and writes `layoutConfig` X/Y itself. Sizes and zones are yours; positions are not.
   (One exception already in the file: `EquipmentWindowX/Y` is the classic-mode seed. Keep it.)
4. **Numbers reconcile.** The same character, session and bags across every window and the bar.
   Two pairs that are easy to conflate and must not be: the Bags band's **total inventory value**
   is strictly greater than the bar's **sell-waiting value** (the rules hold items back, and one
   of them is a 2,900p mythical); and the AA window's **unspent** figure is not the bar's
   **total ever earned**. Four numbers, four meanings.
5. **No selection state anywhere.** Right-click acts on the row under the cursor.
6. **A windowed list says so — and counts the right set.** Whenever a list shows fewer rows
   than exist, put a truncation row in `TextFurniture` at the end nearest the missing rows:
   `... 13 more sold above`, `... 36 more`. This fires whether or not the window's own band
   prints a count — Bags' band states a *value* (`22,180p 4g total`) and its table still needs
   `... 36 more`, because 47 items exist and 11 are drawn. Without it the visible rows read as
   the whole set. **A filtered list is different**: its rows are all the matches, so the hidden
   count belongs beside the filter that hid them, not above the results — Chat's `1,279 hidden`
   sits next to `clear`, because `... 1,279 earlier` would claim there are more matching lines
   when there are none.
7. **The dim is the cross-window signal for "on the cursor", not a shared column.** Windows
   name an item's position differently — Bags has `Bag`, Bank has `Bag`+`Slot`, Reroll has
   `Status`+`Location`, Aug Utility has neither — so do not expect one phrase to appear
   everywhere. What must be consistent is the 45% dim: every row whose item is on the cursor
   renders dimmed, in every open window, and no window claims the item is still in its slot.
   **One carve-out:** a completed-run log (Loot's `done` list, Sell's sold rows) records what
   happened and does not dim — it makes no claim about where anything is now.
8. **A progress bar is a second encoding of its label — derive it, never author it.**
   Every fill must be computed from the same two numbers the label prints, and each bar's
   subject must be the counter beside it: the Loot *window* bar is items on this corpse
   (3/7), the *lane* bar is corpses in the run (4/11). Hardcoding a percentage is how a
   label and its bar end up telling different stories after a number changes.
9. **One lane, one owner — and one interrupt.** Loot, sell and script turn-in are mutually
   exclusive; the lane has three owners and shows one at a time, and the bar greys the other
   start button while one runs. **The interrupt lives on the bar's start button, which becomes
   the Stop in place** — never in the lane, never duplicated into the job's own window. Loot
   All stops looting; Auto Sell stops selling. The sole exception is script turn-in: the
   Scripts window starts it, so there is no bar button to become its Stop and **its Stop
   lives in the lane**. Two visible Stops means two jobs are drawn running, which the design
   does not allow.
10. **List membership is data, not per-window judgement.** Keep, always-sell, reroll,
   always-loot, never-loot and the Clicky lists decide what appears in Sell's HELD BACK,
   Reroll's in-bags section, and every RULES check in the menu. One item's memberships must
   produce the same answer in every window that filters on them — a mythical held back in
   Sell is the same mythical Mythics counts and Reroll may list. **Clicky membership protects
   from selling AND destroying** (`favorites.lua:239`, `:266`, `:179` — "restores sell/delete
   once off ALL lists"), so a clicky item is a HELD BACK row *and* has two blocked menu rows,
   not just the blocked Destroy.
11. **Settled, do not revisit:** the palette; type registers and four heights; the 26px band and
   its header contract; `window_zones` rather than docking.

---

## Do these first — free, data already published

### 1. Session age on the bar
`dock_top.lua`, session cell (fixed 470px).

`startedAt` is set at `session_record.lua:276`, persisted as `StartedAt=` at `:125`,
reloaded at `:145`, published on the counts table at `:389`. Display only.

The cell's leading label becomes label + age, in `TextFurniture`, ahead of all four values:

```
under 60s   session just started
under 1h    session 14m
1h–24h      session 2h 14m
1d–7d       session 3d 4h
7d+         session 12d
```

- Cache the string; recompute at most once a second. Never format a date per frame.
- Age tooltip is the only place persistence is explained:
  `Started 19:41:02. Survives logout - Clear starts a new one.`
- **Overflow: the age drops whole.** Never ellipsize to `session 2h...`.
- **Degrades:** `startedAt` nil, or a negative/future delta → label alone, no age, no error.

### 2. Chat renderer note
`chat_window.lua:280-283`. The code already intends this — `:282` says the tradeoff
"is stated in the pill line below rather than left for the user to discover."

- String: `plain text - links are not clickable`
- Placement: pill line, right of the `N new` pill's slot — same row as the filter and time
  toggles that caused it.
- Colour: `TextFurniture`. **Never Attention amber** — this is a consequence of a choice the
  user just made, not a warning.
- Recovery in tooltip only: `Clear the filter and turn off times to get links back.`
- **Gate on `ownRenderer and chatUseZep` (the user's setting — **not** `zepAvailable()`, which only says the library loaded; a user with Zep available but switched off is on the plain renderer unconditionally and lost nothing).** Zep is opt-in and off by default
  (`:122`), so on a default install there is nothing to switch away from. Ungated, this note
  tells every default user they lost a feature they never had.
- **Degrades:** Zep unavailable → no note, ever, in any state. That is the common case.

### 3. Item Display classes/races
`item_display.lua`. Helper already exists: `itemHelpers.getClassRaceStringsFromTLO`
(`item_helpers.lua:31`, used at `:559`); `item_tooltip.lua:61` already renders the
pipe-delimited string as commas.

- Position: **last line of the identity card**, under flags and location. Not in ALL STATS —
  who can wear a thing is identity, not a stat.
- Base: `Usable by CLR, DRU, SHM . all races` — `Usable by` in `TextFurniture`, codes in
  `TextContent`.
- **Both ALL → omit the line entirely.**
- **Inversion rule:** above 8 of 16, state the exclusion — `Not usable by BRD, ROG, WAR`.
  With 16 classes and 16 races one side is always ≤8, so the line is **capped at one line by
  construction**. That is the density justification.
- **If you cannot use it:** this line already exists — `renderHeader:335` emits
  `You cannot use: <reason>` in `Error` red, positioned after the flags line, and the item's
  **name is coloured by usability** (`Success` green / `Error` red) at `:299`. So the
  classes/races addition needs **no red variant and no reordering** — do not build one. It is
  purely the informational bottom line of the identity card, omitted when both class and race
  are unrestricted.
- **The identity card's separator is a middot escape** (`\xc2\xb7`), not the band's ASCII
  period — `renderHeader` joins with `" \xc2\xb7 "` throughout. Match it; do not "fix" it to
  ` . `, which would make this one card disagree with itself.
- **`canUse == false` also suppresses the Upgrade chip.** An upgrade is a comparison against
  what you wear, so there is nothing to compare for an item you cannot equip — and a green
  Upgrade badge under a red cannot-use banner asserts a swap the game will refuse.
- Compute **on selection change only** — tab switch, new tab, socket resolve. Never per frame.
- **Degrades:** TLO unavailable or empty strings → omit. Never `Usable by unknown`, never a dash.

---

## Then — config and wiring

### 4. `[Defaults]` and `constants.VIEWS`
File: `lua/itemui/default_layout/itemui_layout.ini`, `[Defaults]` section only.
(The same file has a `[Layout]` section — a real saved arrangement. Do not touch it.)

**Add six windows missing from `[Defaults]`:**

| Window | Size | Note |
|---|---|---|
| Mythicals | 560×500 | in VIEWS, missing from INI |
| Clickies | 460×380 | in VIEWS, missing from INI |
| Effects | 340×480 | in VIEWS, missing from INI |
| Script Tracker | 460×400 | also add its two `layoutKeys` — see below |
| Chat | 560×400 | **also missing from `constants.VIEWS`** — add `WidthChatPanel=560`, `HeightChat=400` |
| Config | 620×620 | `WidthConfig=520` exists with no partner height |

Chat is the important one: `GEOM` references `WidthChatPanel`/`HeightChat` and nothing defines
them, so a wide-and-short window is being sized by the 340×420 Command Center nominal.

**Revise six sizes:**

```
Inventory     600x450 -> 800x560     (Height is SHARED with Sell)
Sell width    780     -> 800
Bank          520x600 -> 560x560
Item Display  760x520 -> 760x620
Aug Utility   520x480 -> 640x480
Loot          420x380 -> 480x520
```

Reasoning that matters: Inventory and Sell swap into the same frame and share the `Height` key,
so their widths must match too. Bank's height must match Inventory's because the hub-pair code
copies the hub's live height onto Bank — a default that already agrees makes the first open
seamless. Aug Utility widens because the row gained a why-column.

**Resolve first:** `WidthLoot=560` and `WidthLootPanel=420` both ship; `GEOM` reads the second.
Pick one and delete the other.

### 5. Zones
Twelve views already declare `zone` and it works. Two do not:

- `script_tracker` → `zone = "R2"`, and add the two `layoutKeys` it already reads and writes
  (`WidthScriptTrackerPanel`, `HeightScriptTracker`). Without them the placer cannot size it.
- `settings` → **no zone, permanently.** It persists no position and has no `GEOM` entry.
  Add a comment saying so, so the next reader does not file it as a gap.
- `loot` has no registry entry; its zone comes from `ZONE_FALLBACK`. Move `zone = "R2"` into
  its spec and delete the fallback table.

Note: a **nil** zone does not fall through to R1 — `zone and ZONES[zone] or (zone and ZONES.R1)`
is nil, `placeWindow` returns false, and the window is never auto-placed. Only an **unknown
string** degrades to R1.

Also stale: `registry.lua:302`'s comment says "Phase 4 (zone placement) is what consumes this;
nothing sets it yet." Twelve views set it. Fix the comment while you are there.

### 6. Size constraints
No companion window calls `SetNextWindowSizeConstraints` today; only two bar popups do. Every
window can be dragged to nothing and the 26px band is the first casualty.

```
Inventory / Sell            520x260
Item Display                460x300
Bank                        380x220
Aug Utility                 460x240
Reroll                      420x240
Equipment                   240x300
Effects / Clickies          300x220
Chat                        360x200
AA / Mythics / Scripts/Loot 400x240
```

Derivation, if you need to adjust: minimum width is where the band's stat string stops fitting
(title at 22px + stat + n icon buttons at 20px + 4px gaps + 8px padding a side). Minimum height
is band + table header + three rows.

### 7. The context menu — five rows, one context, two hosts
`components/context_menu.lua` already declares seven contexts and a full row table.
**Eleven hosts already reach it** through `ui_common.lua:159`, which delegates. Two do not:
`augment_utility` (no menu at all) and `loot_ui` (its own `LootRuleCtx`).

**Wire up:**
- `augment_utility` — no new context needed. Its candidate rows are real bag or bank items with
  real ids, so each passes `bags` or `bank` by the item's own source. Pure wiring.
- `loot_ui` — add a **new `lootRow` context**, RULES-only. Loot rows carry no bag/slot/id
  (macro_bridge row shape) so MOVE and destructive genuinely cannot address them; that
  constraint is real and stays.

**Add five rows:**

| Row | Context | Notes |
|---|---|---|
| `Take it off` | equipped | equipped has no MOVE row at all today — you can equip from bags but never take anything off |
| `Fill it - open Augment Utility` | augEmpty | `augEmpty` is declared in `M.CONTEXTS` and no row lists it — right-clicking an empty socket gives an identity line and nothing else |
| `Always loot this` | lootRow | |
| `Never loot this` | lootRow | replaces `loot_ui.lua:41`'s `Remove from Never-loot list`, which is a third row expressing the second row's state — under the shared builder it is one row with a check |
| `Item info` | lootRow | blocked, see below |

**`ornament` gets augInserted's full row set** — it is an augment in a socket. Today it gets only
`Item info`. Only difference: the identity line renders in `Mythic` tint and reads
`Ornament slot - appearance only`.

**Blocked text, exact, in the row:**

```
already built:
  Bank it - no banker nearby
  Take it out - no banker nearby
  Equip it - no slot takes it
  Destroy it - on a Clicky list
  Always sell it - on a Clicky list

new:
  Take it off - bags are full
  Item info - not in your bags yet
  Reroll it (Aug) - not in your bags yet
```

**Modifiers: shift only, on destructive rows only** (`Destroy it`, `Remove it - uses a
distiller`). No ctrl, no alt, anywhere, in any context. Ungated the row renders
`Destroy it - hold shift` and is disabled; held, it renders its normal label in `DestroyText`
and fires **with no confirm dialog** — the modifier is the confirmation. Effect removal is
deliberately ungated: shedding a buff is not destroying property.

**RULES rows show state as a check, never as a verb.** `✓ Keep it - never sold`, not
`Remove from keep list`.

---

## Then — the real spend

### 8. Bags kit band
`inventory.lua` has not adopted `components/window_header` and has **zero `barsOn` branches**.
Today it draws three stacked rows of chrome above the table: a toolbar (Search, X, Newest,
Refresh, `Last: 19:52:51`), a status row (`Items: 47 / 80`, `Total value:`), then two separators.

**Band stat:** `22,180p 4g total . last scan 20:13:04`

- The value clause is `ItemUtils.formatValue(invTotalValue)` **verbatim** — it emits the plat/gold
  pair. Do not hand-trim the gold: the same formatter feeds Sell and Bank, and trimming here
  makes two windows disagree about the same number.
- `last scan` is spelled out because `Last:` beside a Refresh button reads as "last refresh".

**What the band must NOT carry:** `Items: 47 / 80`. The bar's bags cell owns free slots and
weight. The band's whole contract is the one number the bar does not already show.

**Where today's chrome goes:**

| Today | Becomes |
|---|---|
| Refresh | band action, `GLYPHS.REFRESH`, keeps its tooltip and `messageBefore` |
| `Last: 19:52:51` | into the stat as `last scan 19:52:51` |
| Total value | into the stat; loses its tooltip, the word `total` does that work |
| Search + X | band action, `GLYPHS.SEARCH`, toggling a one-line search row between band and table. Row exists only while search is on — same rule as chat's filter, so no invisible mode hides items |
| Newest | **deleted as a button.** It sets a sort; sorts belong to column headers. Add `Acquired` as a real hideable column. Removes the two-click toggle whose second click silently restored Name sort |
| Lock | `windowHeader.registryLock(id, ctx)`, rightmost |
| Bank open hint | **footer strip**, not header: `Bank open - shift+click an item to move it`. Conditional chrome above a table shifts every row down the moment you walk up to a banker |

**Sections: none.** One flat sortable table — grouping fights the sort, and the sort is how
people find things here. The only window in the pass with no section state.

**Density:** `ROW_H` 20, one row per item. Columns as `column_config` defines them.

**Footer:** nothing of its own. The cursor bar, quantity picker and confirm paths are
`main_window`'s — do not duplicate them.

**`barsOn`: two branches only.** On → band, no toolbar. Off → today's toolbar unchanged
(in windows-only mode nothing else shows totals or scan age, so the band's omissions would
strand that user).

**Degrades:** `lastScanTimeInv` nil/0 → `22,180p 4g total . no scan yet`. `invTotalValue` nil →
drop the value clause and its separator, keep the scan clause. Both nil → no stat, band renders
the title alone (legal — Settings ships that way).

**Sell's Status column takes raw reason tokens**, not prose: `RerollList`, `ClickyList`,
`Keep`, `Mythical`, em-dash when there is none — `ui_common.formatSellStatus:85` renames
`Epic` to `EpicQuest` and `Favorites` to `ClickyList` and does nothing else. Row name colour
is sell status, not item family (`getSellStatusNameColor:54`): red will sell, green is kept.
Run state (sold / selling now / queued) is a **separate column this pass adds** — Status
cannot carry both a reason and a run position.

### 9. Socket census, then the Aug Utility why-line

**This adds a sixth column.** The shipped table is `[icon] Rank / Name / Clicky [action]`
(`augment_utility.lua:476-481`) — there is no home for the census answer, so add `Fits` as a
sortable column between Name and Clicky. Tabs are `For this slot` / `All augments`
(`:174-181`), so "All tab only" below means the second one. Footer actions are
`Fill with best` (`:676`) and `Remove All` (`:648`).

Plan is in `WINDOWS_PASS.md`: demand-driven `dock_state` walk on its own `DOCK_SLOW_*` interval,
publishing `snap.wornSockets`, after which the render path is arithmetic via
`augment_helpers.augmentFitsSocket`. ~115 reads on a slow interval, **only while the window is
open** — against `DOCK_SLOW_BUFFS_MS` already doing 40–70 reads every 500ms in shipping code.

Replaces today's `getAugTypeSlotIds` output (`augment_helpers.lua:8` → `:132`):

```
today   types 1, 3              (states a property of the augment)
after   fits 3 of your slots    (answers the question that was asked)
```

- Singular stays parallel: `fits 1 of your slots`. A row that changes shape at n=1 is harder to
  scan down a column than one that reads slightly stiff.
- **`All augments` tab only.** On `For this slot` every candidate fits by construction, so the
  line is a tautology there — it is replaced by the augment's rank and stat.
- Hover names them: `Chest, Arms, Legs`. Only once the census has run — no tooltip before that.
- Zero-fit rows sort last within their rank group, render at `TextFurniture`, stay listed.
- **Degrades — before the census:** `types 1, 3`, exactly today's string. No spinner, no
  `counting...`, no dash. Each row upgrades in place the frame `snap.wornSockets` lands. A user
  who never notices the swap has lost nothing.
- **Degrades — zero:** `fits nothing you wear`. Not `fits 0 of your slots` — zero-of-something
  invites a recount; this is a conclusion.
- **Degrades — stale:** show the last known answer, no staleness marker. The window's Refresh
  already covers it.

### 10. Subject link, ring, dim
Nothing exists in code for the ring or dim. Two pieces you may think are missing are not:

- **Glyph: commit, zero risk.** `GLYPH_LINK = "\xEF\x83\x81"` is declared at
  `augment_utility.lua:34` and already renders in that band at `:142`. Promote it to
  `M.GLYPHS.LINK` and delete the local. No new escape, no new atlas entry. If it ever fails to
  rasterise it draws a box, the band still reads `[] Black Scythe`, and the pin's tooltip carries
  the words regardless.
- **Ring colour:** `theme.lua:85` already documents OpenBlue (`#4296fa`) as "open-state / active
  tab / cursor-target ring". The palette named this before the design did.

**Link marker** — Aug Utility's band only: `<link> Black Scythe`. Means: this window lists
candidates for that item. With no subject: `<link> no subject - open an item` (already shipping).
Appears nowhere else — one marker, one meaning.

**Pin** — a band action beside it, `GLYPHS.LOCKED`/`UNLOCK`. Pinned, the subject stops following
Item Display's selection. Tooltips are the whole explanation: `Following the item you open` /
`Pinned to Black Scythe`. **Distinct from the window lock** (`registryLock`, rightmost slot) —
the two never share a word.

**Ring — one meaning, everywhere, forever: _this will take what is on your cursor._**
Not selection, not focus, not validity in the abstract.

- **Appears** the frame an item lands on the cursor. **Every valid target rings at once**, across
  every open window — empty sockets accepting that aug type, empty equipment slots accepting its
  worn slots, free bag cells. Simultaneous is the point: the ring is a map of where this can go,
  not a hover response.
- **Disappears** the frame the cursor empties or a target stops qualifying. No fade — a fading
  ring on a slot you just filled reads as a pending action.
- **Slots, sockets and cells only. Never a table row.** Rows are a list of what you have; slots
  are destinations. Ringing a row promises a drop target that does not exist.
- **Draw as four `AddRectFilled` edges at 2px, not `AddRect`** — `window_header.lua:104` records
  that an outline is unproven in this binding and filled strips are what ships.
- A ringed cell that is also hovered **keeps the ring and drops the Header hover fill.** Two blues
  never stack; the ring outranks hover because it is rarer and more consequential.

**Dim — 45% on the source row.** Means: this row's item is not in that slot right now, it is on
your cursor. A statement about the world, which is why it is a dim and not a highlight.

- Identical frames to the ring. They are one state seen from two ends.
- **Source row only.** Scrolled out of view or in a closed window → nothing dims, nothing scrolls
  to find it.
- 45% alpha **on the row's text only** — background, stripe and separators stay full so the
  table's rhythm is unbroken and the row does not look deleted. And it is 45% **of the row's own
  colour**: a mythic row dims to faint mythic, never to grey, or the dim doubles as a category
  change.
- **Degrades:** no cursor state → no ring, no dim, design still works (the game's own cursor art
  shows what you are carrying). This is an accelerant, not a dependency. **Never draw a ring you
  are not sure about** — a ring on a slot that rejects the drop is worse than no ring.

---

## Small widths

The two bars behave differently as built, and **that asymmetry is correct — do not unify them.**

- **Bottom bar folds.** `CHAT_MIN_W = 220` (`dock_bottom.lua:119`), below which the launcher row
  collapses into the Hub menu. Fine: the bottom bar is *navigation*, and the launcher row and Hub
  menu are two routes to the same destinations, so folding one into the other loses a shortcut,
  not information.
- **Top bar must not fold.** 1840px of fixed cells + an 80px lane floor means **1920 is exactly
  where it stops fitting**. The top bar is *state* — every cell is the only place its number
  appears, so folding deletes information rather than rerouting it, and silently: the user cannot
  tell `0 augs need a call` from "the augs cell folded away."

**Below 1920, add no fold branch.** Settings says it instead, in the cell picker, when it is
relevant:

```
Your screen fits 6 of 8 cells. Turn two off, or use top bar only.
```

Six cells are already user-disableable (`DockSegments`: status, session, bags, sell, buffs, xp) —
the user chooses which two they lose. An automatic fold picks for them and hides that it picked.
`buttons` and `lane` are undroppable in both directions: they are the only cells that can strand
a running job.

Height never folds anything. A short viewport is a windows problem, and `clampToWork` plus the
spill columns already handle it.

---

## Band stat strings — verified from source

Already correct and already ASCII. Listed so you can check nothing drifts:

```
effects         Buffs %d/%d . Songs %d . Auras %d
favorites       %d list%s . %d item%s protected
equipment       %d/23 worn
reroll          on the server list: %d augs . %d mythics
script_tracker  %d in bags . worth %d AA . last scan %s
chat            %d line%s
aa              (statText)
mythicals       (statCache.text)
config          no stat — genuinely has no number; leave the space empty
```

`item_display` requires `window_header` for `iconButton` only — there is no `windowHeader.render`
call, and it should stay that way. Its identity card already carries name, type, value, flags and
location, which is exactly the band's contract. **Nothing is being removed.**

---

## Acceptance

1. Every rendered string is ASCII; `test_ascii_strings.lua` passes.
2. Bags shows a 26px band with `22,180p 4g total . last scan 20:13:04` and no `Items: 47 / 80`.
   The value is total inventory value — strictly greater than the bar's sell-waiting figure,
   which counts only what the rules will actually sell.
3. With bars off, Bags renders today's toolbar unchanged.
4. Session cell reads `session 2h 14m`; at 470px under pressure the age drops whole.
5. Chat's note appears only when Zep is available *and* the plain renderer is forced.
6. Right-clicking the same augment in bags, bank, Aug Utility and a socket gives the same menu,
   modulo context-disabled rows — with disabled rows stating why in the row.
7. An empty socket's menu has `Fill it - open Augment Utility`; an equipped item's has
   `Take it off`.
8. Picking up an augment rings every slot that accepts it, across every open window, and dims
   the row it came from — text only, its own colour, 45%.
9. Aug Utility's All tab reads `fits N of your slots`, and reads `types 1, 3` before the census
   lands rather than a spinner.
10. No window can be dragged small enough to truncate its band stat.
11. Opening a bundled layout preset places every window in a column, at any resolution.

---

## One open decision — not a design question

`layout_io.lua:27` records that `DockLaunchers` and `DockNative` "were written by phase 1 but
never consumed by anything," and `dock_bottom` reads neither. So launcher chip order is purely
`require` order: moving an import line silently reorders the bottom bar, and the saved
`DockLaunchers=bags,bank,equipment,augments,reroll,aa` is inert.

`registry.lua:305` documents `displayOrder` and `CompanionButtonOrder` as the intended mechanism;
neither is implemented.

**Either implement the key or delete it.** A persisted setting that does nothing is worse than
neither. If implementing: the Hub's `hub_list.ENTRIES` order (ITEMS / CHARACTER / LAYOUTS) is the
intended order and the launcher row should match it.

---

## Also worth an eye, unrelated to this pass

- **Three BUILT windows are unreachable from the Hub.** `hub_list.ENTRIES` (`:28-46`) lists
  six ITEMS entries, four CHARACTER, then `layouts_dynamic` — and contains no `chat`, no
  `loot` and no `settings`. Chat has a launcher chip on the bottom bar, so it is reachable
  in two-bar mode; in **top-bar-only mode the pinned status list is the only launcher**, so
  all three become unreachable. `drawEntries:152` even carries a `loot` special case that
  no entry reaches. Decide per window: add to `ENTRIES`, or document where Settings is
  reached instead.

- **Zep's teardown crashes the client on script stop** (`chat_window.lua:122` — the reason Zep is
  opt-in and off by default). A feature whose teardown crashes the client deserves its own
  conversation; the UI note above is an accommodation, not a fix.
- The saved `[Layout]` block has `DockSegments=status,bags,sell,loot,buffs,xp,session`. `loot` is
  not in `CELL_ORDER` — it predates the lane replacing the loot panel. Harmless today, but it
  will read as a supported value to whoever writes the Settings cell picker.
