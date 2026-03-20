# CoOpt UI

**Inventory, selling, looting, and item management for EverQuest — all in one place.**

For **EverQuest emulator** players using **MacroQuest2**. One set of windows, one set of rules. Set what to keep or sell in the UI, and the auto-sell and auto-loot macros use those same rules.

`v0.9.0-beta` · Windows · MacroQuest2

---

## What You Get

**Main window (Inventory Companion)** — See all your bags in one list. Sort, search, and filter. Click an item to pick it up; shift+click to move to bank when the bank is open. When you open a merchant, the same window switches to Sell mode: each item shows Sell / Keep / Junk buttons and whether it will be sold. One button sells everything marked as junk.

**Bank** — Separate window for your bank. Live when the bank is open (move items with shift+click). When the bank is closed, you still see your last snapshot.

**Equipment** — Paper-doll view of what you’re wearing. Hover for stats.

**Item Display** — Right-click any item → “CoOp UI Item Display” for full stats and to compare items in tabs.

**Augments** — List of all your augments; search, sort, and add to reroll lists. **Augment Utility** lets you insert or remove augments from gear (pick item, pick slot, choose augment).

**AA (Alternate Advancement)** — Browse and train AAs by tab (General, Archetype, Class, Special). Export/import profiles.

**Loot window** — Pops up when you run auto-loot. Shows what’s being looted, session totals, and asks you to take or pass on special (e.g. mythical) drops.

**Reroll** — Works with server reroll lists (`!auglist` / `!mythicallist`). See what you have, add from cursor, remove, or roll.

**Auto Sell** — At a merchant, one command sells everything that matches your “junk” rules. Your keep lists and epic/valuable protection are respected.

**Auto Loot** — Loots corpses using your rules (value, types, always-loot and never-loot lists). Lore items are checked so you don’t grab duplicates.

**ScriptTracker** — Separate small window that tracks AA scripts (Lost Memories, Planar Power, etc.) in your inventory and shows total AA value.

**First-time setup** — A short wizard walks you through the main windows and lets you set sell protection and loot rules. You can skip it and configure later in Settings.

**Open Settings** — Click the Settings button on the main window, or type `/itemui config`. Manage sell, loot, and shared lists, and pick settings to meet your preference.

**Sound Notifications** — Get audio feedback when sell completes, items fail to sell, or rare loot is found. Toggle per event, use system beep or custom .wav files. Configure in Settings → Advanced → Sound Notifications.

**Debug Console** — When troubleshooting, enable debug channels in Settings → Advanced. Each channel (Sell, Loot, MacroBridge, Layout, Scan, ItemOps, Augment) logs verbose messages to the MQ console and `logs/coopui_debug.log`. A Recent Errors panel shows any recoverable errors.

**Backup / Restore** — In Settings → Advanced you can export or restore all your CoOpt UI settings.

**Updater (Patcher)** — Optional desktop app that updates CoOpt UI files without touching your config. Post-update verification confirms file integrity. Get it from the releases page.

---

## What You Need

- **MacroQuest2** with Lua and ImGui (most MQ2 installs have this).
- **EverQuest** on an **emulator server**.
- **Windows.**
- **MQ2CoOptUI plugin** (optional, included in releases) — Native C++ plugin for fast inventory/bank/loot scanning, item cursor tracking, and sound playback. Falls back to Lua TLO if not loaded.

**Recommended:** If you’re setting up from scratch, use the prebuilt package and setup guide from the **E3Next** project: [Getting started (EMU 32-bit)](https://github.com/RekkasGit/E3Next/wiki/1%29-Getting-started-EMU-32bit). That package includes E3Next and MQNext already configured. Credit to **Rekkas** and the E3Next team for the binary distribution and EMU setup docs.

In-game, `/lua run` should work. If it doesn’t, CoOpt UI won’t run.

---

## Install

**Option A — Zip (first time or full install)**  
1. Download the latest release zip from the [releases page](https://github.com/CooptGaming/CoopUI/releases).  
2. Extract into your **MacroQuest2 folder** (the one with `MacroQuest.exe`, `lua`, `Macros`). Merge/overwrite when asked.  
3. First time? You can copy `config_templates` into the matching `Macros` folders, or just run the UI and let it create defaults.

**Option B — Patcher (updates)**  
1. Download **CoOptUIPatcher.exe** from the [releases page](https://github.com/CooptGaming/CoopUI/releases).  
2. Put it in your MacroQuest2 folder and run it. It only updates CoOpt UI files and won’t overwrite your settings.

**In-game**  
- Type: `/lua run itemui`  
- The welcome screen checks your setup and can run the setup wizard or skip.  
- Optional: `/lua run scripttracker` for the script tracker.

---

## Quick Commands

| Command | What it does |
|--------|----------------|
| `/itemui` or `/inv` | Open/close the main window |
| `/dosell` | Auto-sell at a merchant (merchant must be open) |
| `/doloot` | Auto-loot corpses |
| `/scripttracker` | Open/close ScriptTracker |
| `/itemui config` | Open Settings |
| `/itemui setup` | Run the setup wizard again |

Other windows (Bank, Equipment, Augments, AA, Reroll, Item Display, Settings) open from buttons on the main window. The Loot window opens automatically when you run `/doloot` (you can turn that off in Settings).

---

## More Help

| Link | What’s in it |
|------|----------------|
| [Install guide](docs/INSTALL.md) | Step-by-step install, updating, migrating from SellUI |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Common problems and fixes |
| [Changelog](CHANGELOG.md) | What changed in each version |

Contributors and technical details: [docs/DEVELOPER.md](docs/DEVELOPER.md).

---

## Thanks

- **[MacroQuest](https://www.macroquest.org/)** — The platform this runs on.  
- **[E3Next](https://github.com/RekkasGit/E3Next)** — Inspiration for EMU automation.  
- **EverQuest emulator communities** — For keeping classic EQ alive.
