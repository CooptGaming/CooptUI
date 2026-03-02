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

**Backup / Restore** — In Settings → Advanced you can export or restore all your CoOpt UI settings.

**Updater (Patcher)** — Optional desktop app that updates CoOpt UI files without touching your config. Get it from the releases page if you want easy updates.

---

## What You Need

- **MacroQuest2** with Lua and ImGui (most MQ2 installs have this).
- **EverQuest** on an **emulator server**.
- **Windows.**

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

## Settings and list management

All sell, loot, and protection rules can be managed in the UI — no need to edit INI files unless you want to. Changes are saved immediately and used by the auto-sell and auto-loot macros on the next run.

**Open Settings** — Click the Settings (gear) button on the main window, or type `/itemui config`.

### Managing lists in the UI

- **From the main window (Sell view):** Right-click any item and use **Keep** or **Junk** to add it to your “never sell” or “always sell” list. You can also use the Keep/Junk buttons on each row when a merchant is open.
- **From Settings:** Use the **Sell Rules** and **Loot Rules** tabs to add or remove items by name. Choose the target list (e.g. Keep exact, Always sell, Always loot, Skip), type the item name or keyword, then click **Add**. Use **From Cursor** to add whatever is on your cursor.
- **Shared lists:** The **Shared** tab holds valuable-item and epic lists. These apply to both selling and looting — one list, one place. You can turn epic protection on or off per class (all 16 EQ classes).

### Settings tabs

| Tab | What you can do |
|-----|------------------|
| **General** | Window behavior (snap to merchant, suppress loot window), sell/loot toggles, layout setup, and **Revert to default layout**. |
| **Sell Rules** | Keep (never sell), always sell (junk), and never-sell-by-type lists. Add or remove entries; use From Cursor to add the item on your cursor. |
| **Loot Rules** | Always loot and skip (never loot) lists. Same add/remove and From Cursor options. |
| **Shared** | Valuable items (never sell, always loot) and epic class protection. |
| **Advanced** | Backup and restore all CoOpt UI config; debug channel toggles. |

Lists and options you set here are written to the INI files under `Macros/sell_config`, `Macros/shared_config`, and `Macros/loot_config`. You can still edit those files directly if you prefer; the UI and macros both read from them.

More detail: [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

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
