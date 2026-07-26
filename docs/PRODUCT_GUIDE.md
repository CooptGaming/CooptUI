# CoOpt UI — Player Guide

**Inventory, selling, looting, and item management for EverQuest EMU servers — one set of windows, one set of rules.**

You set what to keep, sell, and loot in a modern UI; the auto-sell and auto-loot systems follow those same rules. Everything is protected-by-default: a fresh install will never vendor your epics, augments, NoDrop gear, collectibles, or heirlooms.

---

## What you need

- **MacroQuest2 / MQNext** with Lua support (`/lua run` must work in-game)
- **EverQuest** on an EMU server, on **Windows**
- Optional but recommended: the **MQ2CoOptUI plugin** (included in releases) — fast native scanning, live loot feed, and the native-window integration. Everything falls back to Lua if it's not loaded.

Setting up from scratch? Use the prebuilt E3Next package first: [Getting started (EMU 32-bit)](https://github.com/RekkasGit/E3Next/wiki/1%29-Getting-started-EMU-32bit).

## Install

**Patcher (recommended):** download `CoOptUIPatcher.exe` from the [releases page](https://github.com/CooptGaming/CooptUI/releases), put it in your MacroQuest folder, run it. It installs or updates CoOpt UI and **never overwrites your settings** — config files are only created when missing. It can also perform a full fresh install if you point it at an empty folder.

**Zip:** download the release zip and extract into your MacroQuest folder (merge/overwrite when asked).

## First 10 minutes

1. In game: `/lua run itemui`
2. The **welcome screen** appears on first run. Click **Run Setup** — the 13-step wizard walks every window, lets you position and size things, and sets your sell/loot rules.
3. **Step 12 matters most: pick your class(es) for epic protection.** Epic protection and always-loot-epics are ON by default, but they only act on the classes you enable. (Later: Settings → General → "Enable Epic Loot and Protection".)
4. Optional: in **Settings → General → Features**, click **Install skin** and then `/loadskin coopt` — this adds CoOpt controls to the game's own windows (see "Native integration" below). Nothing touches your EQ folder unless you click it.
5. Toggle the UI anytime with `/itemui` (default keybind **Shift+Q**, changeable in Settings → General → Keybindings).

Skipped the wizard? Re-run it anytime with `/itemui setup`, or reopen the welcome with `/itemui onboarding`.

---

## The windows

Open companions from the buttons on the main window, the **Command Center**, or the native Actions window's **CoOpt tab** (skin required).

| Window | What it does |
|---|---|
| **Inventory Companion** (hub) | All bags in one sortable, searchable list. **Newest** button + NEW badge for fresh loot. Click to pick up, Shift+click to move to bank. Switches to Sell mode at a merchant. |
| **Sell view** | Every item shows Keep / Sell / Junk and *why* (Epic, NoDrop, Keep list, value...). **Preview** shows exactly what Auto Sell would do before you commit. |
| **Bank** | Live view when the bank is open; cached snapshot when it's not. |
| **Equipment** | Paper-doll of worn gear, full stat tooltips. |
| **Item Display** | Full stat sheet in tabs — compare items side by side. Right-click any item → "CoOp UI Item Display". |
| **Augments** | Every augment you own, with effects. Right-click → reroll lists, always-sell/never-loot rules. |
| **Augment Utility** | Insert or remove augments from gear: pick item, pick slot, pick augment. |
| **AA Browser** | Browse/search/train Alt Advancement by tab. **Export/Import** your whole AA build (see below). |
| **Effects** | All buffs, songs, and auras in one compact window — timers, hit counts, right-click to remove. |
| **Clickies** | Your clicky item lists: one-click activation, and listed items are protected from selling and deleting. |
| **Mythics** | Every mythical you own, with quick reroll-list actions. |
| **Reroll** | Works the server's `!auglist` / `!mythicallist`: see, add, sync, and roll. |
| **Loot UI** | Opens during loot runs: live progress, session totals, and Take/Pass prompts for special drops. |
| **Command Center** | One-stop panel: status, Loot All / Auto Sell / ScriptTracker buttons, and launchers for every window. |
| **ScriptTracker** | Tracks AA scripts (Lost Memories, Planar Power, ...) in your bags and their total AA value. `/st` to toggle. |

Every companion window has a **Lock** checkbox (top right): locked windows stay up through ESC, Shift+Q, and `/itemui hide` — close them with their own X.

---

## Selling

1. Open a merchant — the hub switches to Sell mode.
2. Mark items **Keep** or **Junk** with the row buttons (or right-click → add to lists). The Status column tells you what will happen and why.
3. **Preview** (dry run) shows the exact sell list. **Auto Sell** sells it.

What can never be sold (defaults): epics (your enabled classes), items on any Clicky list or reroll list, NoDrop/NoTrade, collectibles, heirlooms, augments, food/drink/potions/ammo and other tool types, and anything on your Keep lists. The full default ruleset with reasoning: [DEFAULT_SETTINGS.md](DEFAULT_SETTINGS.md).

`/dosell` does the same as the Auto Sell button.

## Looting

- **Loot All** (Command Center / native buttons) or `/doloot` loots every nearby corpse using your rules.
- Default rules: skip items under 2pp (stackables under 5gp each), always grab valuables (Legendary/Mythical/Script/etc.), always grab your classes' epics, never grab known junk.
- **Mythical NoDrop/NoTrade drops pause the run** and ask Take or Pass (5-minute timer, group alert if grouped) — nothing irreversible happens on autopilot.
- In the Loot UI's history, right-click any looted or skipped item → **always loot** / **never loot** rule on the spot.

## Reroll lists and Clickies

- **Reroll:** right-click an item → "Add to Reroll List" (auto-routes augment vs mythical), or add from cursor in the Reroll window. **Sync Pending** in the guild hall sends the adds and waits for server confirmation. Items on a reroll list are sell-protected and skipped by auto-loot's duplicate checks.
- **Clickies:** make lists of your clicky items (mounts, illusions, buffs). One click activates; listed items can't be sold or deleted until you remove them from the list.

## AA Export / Import

Rebuilding after a reset or trying a new spec:

- **Export** writes your current build to `Macros\aa_backups\aa_<Char>_<Classes>_<date>.ini`.
- **Import** (AA Browser buttons, or the native AA window's CoOpt buttons with the skin) first *reports* what it would train and the point cost, then a second click within 10 seconds actually starts. It buys in prerequisite order, verifies every rank against the server, offers a partial import when points run short, and writes `aa_import_report.txt` with anything it couldn't train.
- **File** button cycles through your backups, newest first.

## Native integration (the CoOpt skin)

Optional, and off until you opt in (Settings → General → Features → **Install skin**, then `/loadskin coopt`):

- **Merchant window** gets Auto Sell / Preview buttons and a status line — sell without any CoOpt window open.
- **Actions window** gets a **CoOpt tab** with launcher buttons for every window.
- **Native Command Center** (`/itemui center`): Start/Stop CoOpt, Loot All, Auto Sell, and launchers — works even before CoOpt UI is running (add `/lua run coopt_launcher` to your MQ autoexec to have it live at login).
- **Native AA window** gets Export / Import / File buttons.
- **Hover tooltips**: hovering slots in the game's own inventory shows the full CoOpt stat tooltip; Shift+Right-click a native slot opens the CoOpt item menu.

Go back anytime with `/loadskin default`. The skin stays current with CoOpt UI updates once installed.

---

## Commands

| Command | What it does |
|---|---|
| `/itemui` (or `/inv`) | Toggle the main window (default keybind Shift+Q) |
| `/itemui center` | Open the native Command Center (skin required) |
| `/itemui config` | Open Settings |
| `/itemui setup` | Run the 13-step setup wizard |
| `/itemui onboarding` | Show the first-run welcome again |
| `/itemui refresh` | Rescan inventory/bank/sell data |
| `/itemui sell legacy` / `lua` | Force a specific sell engine this run |
| `/dosell` | Auto Sell at the open merchant |
| `/doloot` | Auto-loot nearby corpses |
| `/st` | Toggle ScriptTracker |
| `/lua run coopt_launcher` | Native Command Center watcher (for autoexec) |
| `/itemui exit` | Unload CoOpt UI |

## Your data and settings

- All settings live under `Macros\sell_config`, `Macros\loot_config`, `Macros\shared_config` in your MQ folder — plain INIs, editable in Settings in-game. Updates **never** overwrite them.
- **Settings → Advanced → Backup** exports/restores everything in one file.
- Defaults reference: [DEFAULT_SETTINGS.md](DEFAULT_SETTINGS.md) · Full config reference: [CONFIGURATION.md](CONFIGURATION.md)

## When something goes wrong

- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) covers the common cases.
- **Settings → Advanced → Debug channels** turns on verbose logging (`logs/coopui_debug.log`); the Recent Errors panel shows recoverable errors.
- Report issues on Discord with your CoOpt UI version (shown at startup: `[ItemUI] Item UI vX.Y.Z loaded`) and what you clicked — screenshots of the Recent Errors panel help a lot.
