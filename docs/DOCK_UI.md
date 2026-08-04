# The bars — status and commands without a window

**Two thin strips instead of a hub full of buttons: one reports, one takes orders.**

New installs start with the bars on. Existing installs keep whatever UI they had — turn the
bars on in **Settings → General → Dock**, or with `/itemui dock`. Everything below only
applies once they're on; with them off, CoOpt UI is exactly what it has always been.

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
| **The middle — the work** | Anything with a table, a grid, or a paper doll stays a window: Inventory, Bank, Equipment, Item Display, Aug Utility, Effects, Clickies, AA, Reroll, Mythics, Scripts, Loot, Chat, Settings. |

**Nothing lives in both places.** If it's on a bar it isn't also a button inside a window —
one home per control, so there's never a "which one do I press".

---

## The top bar

Eight cells, left to right, in a fixed order. Each one is a **fixed width** — it reserves
room for the widest thing it could ever say, so content changing inside a cell never shoves
its neighbours sideways. That single decision is what makes the strip feel like part of the
game rather than something twitching on top of it. The one exception is the action lane,
which takes whatever width is left.

| Cell | Shows | Click / hover |
|---|---|---|
| **CoOpt** | A dot: green normally, amber without the plugin, red if something has errored. | Click opens the launcher list — every window, and where it is |
| **session** | How long you've been at it, what you've made, how many augs and mythics still need a call, and how many scripts you've collected. Scripts are a tally — you always keep them for turn-in, so there's no call to make on one. | Each of those is a door to the window that answers it |
| **bags** | Items / total slots. Amber past 90%. Weight too, once the game has told us. | — |
| **sell** | What your rules would sell right now, and for how much. Red if a keep-list item is somehow queued to sell. | Hover for the full breakdown — the popover carries **Sell**, **Full preview** and **Rules**; with no merchant open it says so instead of offering a button that would fail |
| **Loot All / Auto Sell** | Two buttons that never move. Auto Sell greys out with a reason when there's no merchant. | Each green start becomes its own solid-red **Stop**, in place |
| **action lane** | Whatever is running, and nothing when nothing is. The only cell that flexes. | The state's own buttons, where the state has any — **Take** / **Pass** / **Take + reroll** on a mythical, **Open Bags** when a run stops full |
| **buffs** | Buff / song / aura counts. Amber only when something is under five minutes. | What's expiring, with Recast |
| **XP** | XP %, AA total, and the AA sitting in your bags as scripts. | — |

Turn individual cells off in Settings → General → Dock. That list is **membership only** —
the order above is the bar's and never changes, so there are no reorder arrows and nothing
moves between states or between users. A cell that's off costs nothing (the bar only gathers
data something is actually displaying) and its width goes to the action lane. The same
membership lives in `itemui_layout.ini` as `DockSegments=` if you prefer editing a CSV.

Two things are not cells and cannot be turned off: the **action lane** and the **Loot All /
Auto Sell** pair. They are the bar's job surface, and the mythical decision rides the lane.

**The status bar itself is mandatory in bars mode.** The command bar depends on it — its
launcher row folds away assuming the CoOpt cell catches what it drops, and Loot All / Auto
Sell sit beside the lane that reports them.

### The action lane

One cell, one width, whichever of these it's in:

1. **idle** — `nothing running`, and where jobs will report.
2. **looting** — `corpse 4/9 · 7 taken`, with live progress.
3. **decision** — a mythical needs a call. The item, the time remaining, and three buttons:
   **Take**, **Pass**, and **Take + reroll** (takes it AND queues it for the reroll list).
   The Loot window doesn't need to be open.
4. **finished** — `looted 9 corpses · 1,208p`, and `3 skipped - see chat` when the run passed
   on anything. It holds for six seconds and then the lane returns to idle, so it reports the
   result without becoming something you have to dismiss.
5. **problem** — `stopped — bags full`, with **Open Bags** (and **Sell N now** if you're at a
   merchant with junk queued). It stays alert until you deal with it.
6. **selling** — a sell run's progress.
7. **turning in scripts** — a script turn-in's progress, with its **Stop** (the one job with
   no start button on the bar, so the lane carries its stop).

**Stop lives with the button that started it**, never in the lane — Loot All becomes the
Stop for looting, Auto Sell for selling. Script turn-in is the single exception above.

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

**Launchers only.** Chat on the left edge, a row of window buttons, then Native UI, Layouts
and Settings on the right. Every chip here opens or closes a window — **nothing on this bar
starts a job**. The verbs live on the status bar, beside the lane that reports them.

| Group | What's in it |
|---|---|
| **chat** (left edge) | A `chat` button with an unread count, or one line of the newest message with per-channel unread dots |
| **launchers** | One button per window, left to right: **Bags \| Bank** and **Item Display \| Augment Utility** as split pairs, then Equipment, Effects, Mythics, Reroll, Scripts, AA, Clickies. Reroll carries a pending count |
| **Native UI** | Inventory, Merchant, Actions, AA window, Bank, and the native panel — the game's own windows, opened through MQ |
| **Layouts** | Your layout presets (the active one is lit), **Re-tidy now**, and **Save current as…** |
| **Settings** | A toggle, not a menu — lit while the Settings window is open |

An entry that's already open is **lit**; clicking it again closes it. A companion you've
disabled in Settings simply isn't listed. Choose which launchers appear, and their order,
in Settings → General → Dock.

**Two menus were retired**, because each had a better home:

- **Hub** — the status bar's CoOpt cell already opens the same launcher list, and one home
  per control means it doesn't also live here.
- **Actions** — Loot All and Auto Sell belong beside the lane that reports their progress,
  not one bar away from it.

**The Command Center window is retired too.** Everything it did is here, so you can close it
for good. `/itemui center` now just makes sure this bar is on screen.

The Loot window isn't on the row by default, because it opens itself the moment a run starts
and the lane reports the run without it. Add it in Settings if you want it anyway.

**One home per control applies to the bars, not to the native panel.** With the plugin
loaded, the game's own Command Center panel (Native UI → Native panel) still carries its
launchers *and* its run buttons. That is deliberate: it's the surface for someone who lives
in EverQuest's own windows and doesn't want an overlay, and nothing the retired Command
Center offered was allowed to disappear with it. Between the two *bars*, though, the rule
holds absolutely — no verb is on both.

When the window gets narrow enough that chat would be squeezed under about 220px, the
**launcher row folds away** rather than shrinking — the CoOpt cell's list holds every one of
those launchers, and a squeezed chat line isn't recoverable from anywhere.

If you prefer the older shape, Settings → General → Dock switches this bar back to **hover
menus** instead of a launcher row.

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

A truly new install — no config file at all — comes up in bars mode, and the screen-use
question above is already answered that way when you see it. The *bundled default file* still
says classic, which is what keeps an existing install from being flipped by an upgrade or by
Revert to Default Layout. Upgrades keep whatever mode they had, and re-running setup won't
change your answer unless you change it.

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
no config edit, nothing lost. That switch is the way out: inside bars mode the status bar is
mandatory, so there is no turning both strips off to get the same effect.

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
