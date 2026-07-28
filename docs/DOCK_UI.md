# The bars — status and commands without a window

**Two thin strips instead of a hub full of buttons: one reports, one takes orders.**

The bars are off by default. Turn them on in **Settings → General → Dock**, or with
`/itemui dock`. Everything below only applies once they're on; with them off, CoOpt UI is
exactly what it has always been.

---

## Why bother

Most of what you open a CoOpt window for is a *question*: is anything running, how full am I,
what would selling actually get me. Answering those by opening a window and closing it again
is the tax the bars remove. They cost about 6% of a 1080p screen and buy back the Command
Center window, the hub's twelve-button row, and most of the reasons to open anything.

The split is deliberate and it never blurs:

| | |
|---|---|
| **Top bar — reports** | Things you read without clicking. Plugin state, bags, what a sale would fetch, live loot or sell progress, buffs, XP/AA, the session total. |
| **Bottom bar — commands** | Things you click on purpose. Every CoOpt window, the game's own windows, Settings, and chat. |
| **The middle — the work** | Anything with a table, a grid, or a paper doll stays a window: Inventory, Bank, Equipment, Item Display, Augments, Aug Utility, AA, Reroll, Mythics, Settings. |

**Nothing lives in both places.** If it's on a bar it isn't also a button inside a window —
one home per control, so there's never a "which one do I press".

---

## The top bar

Seven slots, left to right. Each one is a **fixed width** — it reserves room for the widest
thing it could ever say, so content changing inside a slot never shoves its neighbours
sideways. That single decision is what makes the strip feel like part of the game rather than
something twitching on top of it.

| Slot | Shows | Hover for |
|---|---|---|
| **CoOpt** | Green normally. Amber without the plugin, red if something has errored. | What the difference is |
| **bags** | Items / total slots. Amber past 90%. Weight too, while the game's Inventory window is open. | — |
| **sell offer** | What your rules would sell right now, and for how much. Red if a keep-list item is somehow queued to sell. | The full breakdown |
| **loot** | Idle, or live progress, or a decision, or the result, or a problem. | — |
| **buffs** | Buff / song / aura counts. Amber only when something is under five minutes. | What's expiring, with Recast |
| **XP** | XP %, AA total, and the AA sitting in your bags as scripts. | — |
| **session** | Everything this session has earned, looted and sold. | The split |

Turn individual slots off in Settings → General → Dock. A slot that's off costs nothing —
the bar only gathers data something is actually displaying.

### The loot slot has five moods

It's one slot, one width, whichever of these it's in:

1. **idle** — a single dormant word.
2. **looting** — `corpse 4/9 · 7 taken`, with **Stop**.
3. **decision** — a mythical needs a call. The item, a timer, **Take** and **Pass**. The Loot
   window doesn't need to be open.
4. **finished** — `looted 9 corpses · 1,208p · 3 skipped`, with **Review**.
5. **problem** — `stopped — bags full`, with **Bags** (and **Sell junk** if you're at a
   merchant). It stays alert until you deal with it.

### Hover popovers

Hovering a slot with a `ⓘ`-worthy story opens a small panel *under* it (or above, if the bar
is bottom-docked). It's a real panel, not a tooltip — you can move the mouse into it and click
things.

- **buffs** — what's about to fall off, soonest first, amber under five minutes and red under
  one. Each row offers **Recast** when an item in your bags actually casts that buff (matched
  by spell, not by name) and it's off cooldown; when it's cooling down you get the seconds
  instead. No item, no button.
- **sell offer** — your items grouped by *the rule that decided them*, with counts and totals.
  This is where you learn your own rules. **Sell** only appears when you're actually at a
  merchant; otherwise it says so, rather than offering a button that would fail.

Popovers close as soon as the mouse leaves. **Middle-click** a slot to pin one open — useful
mid-fight — and **Esc** closes a pinned one.

They never appear on their own, and they're suppressed entirely while a mythical decision is
on screen. A panel that can be clicked also *absorbs* clicks, and covering the game world at
the exact moment you're being asked to press Take would be the worst possible time.

---

## The bottom bar

Four menus, chat, and Settings. Hover a menu to open it, click to pin it, Esc to close.

| Menu | What's in it |
|---|---|
| **Items** | Bags (the hub), Bank, Item Display, Augments, Aug Utility, Mythics, Reroll |
| **Character** | Equipment, Effects, Clickies, AA, ScriptTracker |
| **Actions** | Loot All, Stop (only while something runs), Auto Sell (greyed with a reason when there's no merchant), Loot window, Command Center |
| **Game windows** | Inventory, Merchant, Actions, AA window, Bank, and the native panel — the game's own windows, opened through MQ |
| **Layouts** | Your layout presets (the active one is lit), **Re-tidy now**, and **Save current as…** |

An entry that's already open is **lit**; clicking it again closes it. A companion you've
disabled in Settings simply isn't listed.

**The Command Center window is retired.** Everything it did is here, so you can close it for
good. `/itemui center` now just makes sure this bar is on screen.

### Chat

The strip itself only ever shows a launcher, in two heights:

- **hidden** — a `chat` button with an unread count.
- **collapsed** — one line: the newest message from any channel, plus per-channel unread
  badges. Click the line (or the badges) to open the real window.

Everything else — tabs, scrollback, typing — lives in the **Chat window**, a normal companion
with its own zone, size and position (so it opens and stays where you put it, the same as
Bank or Effects). It has five tabs (**All / Main / MQ / Other / CoOpt**) with their own unread
counts, cleared as you view them; **All** clears every badge at once because it shows
everything.

Where the plugin build includes MacroQuest's console widget, the window is a real scrolling
console: every line stays in scrollback (not just the last handful), and **item, spell,
player and achievement links are clickable** — they open exactly as they would in the game's
own chat window. Where that widget isn't available, the window falls back to a plain
scrolling list with links stripped to plain text, so a line at least reads clean instead of
showing raw link tag soup.

**You can type.** The input row at the bottom runs whatever you type as a command if it
starts with `/`, or sends it as `/say` otherwise — press Enter or click **Send**. While that
field has keyboard focus, EverQuest doesn't see your keystrokes (the same tradeoff every
other focusable CoOpt window makes); click back into the game to type there again.

---

## Windows place themselves

In bars mode, opening a window doesn't drop it wherever it last was. Each companion has a
**zone** around the hub — Equipment to the left, Bank and Item Display to the right, Effects
and Clickies below, and so on — and opening one takes the **first free slot** in its zone,
clamped to the screen with the bars subtracted. Nothing opens off-screen, nothing opens on
top of another window, and it works the same at 1080p and 1440p.

Three rules make it feel deliberate rather than bossy:

- **Move once, keep it.** The moment you drag a window it becomes *user placed* and stops
  auto-slotting — until you press **Re-tidy** (Layouts menu, Settings, or `/itemui retidy`),
  which puts every open window back into its zone and forgets the hand placements.
- **Magnet edges.** Drop a window within 12px of the hub or another window and it snaps
  flush with a small gutter — and *stays attached*: drag the hub and its satellites travel
  with it; close a window in a snapped column and the ones below slide up. Hold **Alt**
  while dragging to ignore the magnets for that drag.
- **The dock is never covered.** Its strips are subtracted from the placement area before
  anything is computed.

### Layout presets

A preset is *which windows are open, in which zone, at what size*. Five ship out of the box —
**Bag session**, **Farming**, **Merchant run**, **Gearing up**, **Raid — minimal** — all
zone-driven, so they lay themselves out for whatever screen you're on. **Save current as…**
captures your exact arrangement, positions and all.

Switching a preset closes what isn't in it (pinned windows stay), opens what is, and places
anything the preset doesn't position. Apply one from the bottom-bar **Layouts** menu,
Settings → General → Layouts, or `/itemui layout <name>`.

Presets live in their own file — `Macros\sell_config\itemui_presets.ini` — which **Revert to
Default Layout never touches**. Deleting a bundled preset is permanent; they only reseed if
the file itself is gone.

---

## The first run, and the bar that teaches itself

A fresh install gets **two questions**, not a thirteen-step tour: how careful CoOpt should be
with your stuff (Cautious / Balanced / Aggressive — each strictly *adds* protections; picking
a looser one later never deletes rules), and how much screen to use (Two bars + hub / Top bar
only / Windows only). A live strip shows what the current rules would sell right now. The old
wizard still exists at `/itemui setup --full`.

After that, five **hints** appear once each, at their own first real moment — first merchant,
first loot run, first mythical decision, first full bag, first rule edit. **Got it** dismisses
one forever; `/itemui hints` replays all five.

New installs start in bars mode. Upgrades keep whatever mode they had — and re-running setup
won't flip your answer unless you change it.

---

## When something's broken

One thin strip under the bar — never a modal — for the four conditions that used to surface
as a console line or nothing: `sell.mac` missing (macro mode only), no sell rules yet, bank
shown from a days-old snapshot, running without the plugin. Each says what's wrong, what it
costs you right now, and offers a fix that actually exists. **Hide for this session** does
exactly that.

One of them deserves its own sentence: **"no sell rules yet" is not safe**. With every list
empty, the default pipeline sells unmatched tradeable items above the value floor — the strip
says so and offers the rules screen.

And in the Sell view, **the status is a link, not a label**: click "Will sell" on any row to
see which rule decided that, with one-click **Keep this item** and **Protect \<type\>** fixes.

---

## The native windows

With the plugin loaded, the three native surfaces got the same honesty pass (without it, the
skin's static labels stand and everything keeps working as before):

- **Command Center** — launcher buttons stay *lit* while their window is open, so the panel
  doubles as a window list. The run buttons say what a click does right now: "Looting… stop"
  actually stops the run. The status line carries live progress instead of "Idle".
- **Merchant strip** — states the offer before you click (`2,412p | 8 protected by your
  rules`), becomes **Stop** with progress while a macro sell runs, admits the Lua batch has
  no stop, and reports the result — including failures — when it's done.
- **AA window** — Import tells you *which file*, *how many ranks*, and *what you have*
  before the confirming second click.

---

## Commands

```
/itemui dock              toggle the bars on and off
/itemui dock top          status bar on the top edge (commands take the bottom)
/itemui dock bottom       status bar on the bottom edge (commands take the top)
/itemui dock off          back to the classic UI
/itemui center            make sure the command bar is on screen
/itemui layout            list your layout presets (and which is active)
/itemui layout <name>     apply one
/itemui retidy            put every open window back into its zone
/itemui hints             replay the five bar hints
/itemui setup             the two-question first run
/itemui setup --full      the 13-step wizard
```

Every command you already use still works exactly as before.

---

## Going back

`UIMode` is a runtime switch, not a one-way door. **Settings → General → Dock → uncheck "Use
the bars UI"**, or `/itemui dock off`, and you're back to today's UI immediately — no reinstall,
no config edit, nothing lost. Turning both strips off inside bars mode does the same thing.

The setting lives in `Macros\sell_config\itemui_layout.ini` as `UIMode=classic|bars`, next to
the `Dock*` keys for the edge, the chat height and which slots you kept.

---

## Not here yet

- **Consolidate.** The bags-full strip offers Bags and Sell junk. Actual bag consolidation
  doesn't exist in CoOpt yet, so there's no button pretending it does.
- **Preset hotkeys and live drag guides.** Shift+1…5 preset switching and the yellow
  alignment guides from the mockups are deferred — EQ owns most function keys, and guides
  need per-window draw hooks. Snapping itself works; you just don't see lines while dragging.
- **Take/Pass hotkeys.** The decision buttons are buttons only: EQ binds F1/F2 to targeting,
  and an overlay can't safely steal them.
