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

An entry that's already open is **lit**; clicking it again closes it. A companion you've
disabled in Settings simply isn't listed.

**The Command Center window is retired.** Everything it did is here, so you can close it for
good. `/itemui center` now just makes sure this bar is on screen.

### Chat

Three heights, and the strip's height is fixed for whichever one you pick:

- **hidden** — pure launcher. A `chat` button with an unread count brings it back.
- **one line** — the newest line from any channel, plus per-channel unread counts.
- **four lines** — channel tabs (Main / MQ / Other / CoOpt) and the last four lines.

CoOpt renders the lines, so channel colours and CoOpt's own messages stay consistent. **Typing
still goes through the game** — the **Type** button hands keyboard focus to EverQuest's own
chat input. That's the one thing an overlay should never try to replace.

---

## Commands

```
/itemui dock              toggle the bars on and off
/itemui dock top          status bar on the top edge (commands take the bottom)
/itemui dock bottom       status bar on the bottom edge (commands take the top)
/itemui dock off          back to the classic UI
/itemui center            make sure the command bar is on screen
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

Two things from the design this doesn't do:

- **Layout presets and zone placement.** Windows still open where they always did. The
  Layouts menu isn't drawn because there's nothing yet for it to list.
- **Consolidate.** The bags-full strip offers Bags and Sell junk. Actual bag consolidation
  doesn't exist in CoOpt yet, so there's no button pretending it does.
