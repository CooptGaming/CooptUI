# CoOpt UI

**A suite of inventory, sell, loot, and augment companions for EverQuest EMU servers, built on MacroQuest2.**

`v0.9.0-beta` &nbsp;|&nbsp; Lua + ImGui &nbsp;|&nbsp; Windows &nbsp;|&nbsp; MacroQuest2

---

## What is CoOpt UI?

CoOpt UI replaces the scattered inventory, sell, loot, and item management workflows in EverQuest with a unified set of companion windows that share one configuration. Load it once and you get an Inventory Companion with integrated selling, a Bank window that works online and offline, automated loot and sell macros, augment management, AA browsing, and more — all reading from the same keep, junk, and protection lists. Edit a rule in the UI and the macros follow it on the next run.

It is designed for EverQuest emulator (EMU) server players who use MacroQuest2.

---

## Features

### Inventory Companion

The main window. Every item across all bags in a single sortable, filterable table. Columns include name, value, weight, type, bag, slot, clicky effects, augment slots, and more. Right-click any column header to show or hide columns, drag to reorder, and resize by dragging borders. Left-click an item to pick it up; Shift+click to move it to your bank (when the bank is open). Right-click any item for a context menu: inspect, move, add to keep or sell lists, or open in Item Display.

When a merchant window is open, the view switches to Sell mode. Each row gains Sell, Keep, and Junk action buttons, and a status column shows whether the item will be sold, kept, or protected based on your rules. A summary bar displays counts and total sell value. The Auto Sell button sells everything flagged as "Sell" in one pass.

### Bank Companion

A separate window showing bank contents. When the in-game bank is open, the view is live — Shift+click moves items between bank and inventory. When the bank is closed, the window shows a cached snapshot from your last visit with a timestamp. Same search, sort, and column customization as the Inventory view.

### Equipment Companion

A paper-doll grid displaying all 23 worn equipment slots. Hover any slot for full stats via tooltip. Included in the default window layout on first install.

### Item Display

A multi-tab stat sheet for any item. Right-click an item anywhere in CoOpt UI and choose "CoOp UI Item Display" to open a full stat breakdown. Multiple tabs let you compare items side by side. Toolbar actions include Can I Use, Source, and Locate.

### Augments Companion

Lists every augmentation item in your inventory with effects, type, and value at a glance. Search and sort the list; right-click to add items to the Augment or Mythical reroll lists.

### Augment Utility

Insert and remove augments from equipped or inventory items. Select a target item from the Item Display, pick an augment slot, browse compatible augments with search and tooltips, then click Insert or Remove. Operations run as non-blocking state machines — no UI freezes.

### AA Companion

Browse all Alternate Advancement abilities across four tabs: General, Archetype, Class, and Special. Search, sort, and view ability details. Train abilities and assign hotkeys directly. Export and import AA profiles for sharing between characters.

### Loot Companion

A dedicated window that opens during loot macro runs. Shows real-time progress as items are evaluated and picked up, session statistics (total looted, total value, items skipped), and loot history. If a mythical NoDrop or NoTrade item drops, the Loot Companion presents a take-or-pass prompt so you can decide before the macro continues.

### Reroll Companion

Manages server augment and mythical reroll lists. The companion parses `!auglist` and `!mythicallist` chat responses, tracks how many matching items you have in inventory and bank, and lets you add items from cursor, remove entries, or initiate a roll.

### Auto Sell (sell.mac v3.0)

A macro that sells items to the open merchant based on your rules. The sell decision evaluates 15 checks in order: augment lists, never-loot items, NoDrop/NoTrade/Lore/Quest/Collectible/Heirloom flag protection, epic item protection, keep and junk lists, value thresholds, and protected types. First match wins. Progress and failures are reported back to the UI in real time via IPC.

### Auto Loot (loot.mac v4.0)

A macro that loots corpses using your rules. It uses a two-pass approach: first it evaluates every item on the corpse, then it picks up the items that pass. The loot decision evaluates 17 checks covering augment skip lists, epic items, skip and always-loot lists (exact, contains, and type), value thresholds, tribute override, clicky effects, quest items, collectibles, and more. Lore items are checked against both inventory and bank before pickup. Optional post-loot weight sorting moves heavy items to preferred bags.

### Shared Configuration

Keep, junk, valuable, and epic item lists are shared between the UI and both macros. Edit in the Settings window or directly in the INI files — the macros read the same files. No duplicate lists to maintain.

### Epic Quest Item Protection

Per-class epic item lists covering all 16 EverQuest classes. Epic items are never sold and optionally always looted. You select which classes to protect in Settings; unselected classes fall back to a combined master list.

### Onboarding Wizard

A 14-screen guided setup that walks new users through every window: Inventory layout, Sell layout, Bank layout, companion window positioning, sell protection flags, loot rules, and epic class selection. Each step explains what the window does and lets you resize and configure it before moving on. Available on first run or anytime from Settings.

### ScriptTracker

A standalone companion (`/lua run scripttracker`) that scans your inventory for Lost Memories, Planar Power, and Rebirthed Memories AA scripts. Displays counts by rarity tier and total AA value. Refreshes automatically when your inventory changes.

### Backup and Restore

Export all configuration (sell, shared, and loot config folders) into a timestamped backup package with a manifest. Import restores from a backup, creating `.bak` copies of existing files before overwriting. Available in Settings > Advanced.

### Debug Framework

Named debug channels with INI-based enable/disable, buffered log file output with 1 MB rotation, and deferred echo drain. Useful for troubleshooting or development. Channel toggles are in Settings > Advanced.

### Patcher

A desktop application (Windows) that updates CoOpt UI files without replacing your configuration. It fetches a release manifest from GitHub, compares SHA256 hashes of local files, and downloads only what has changed. Missing default config files are created automatically; existing config is never overwritten. Available as `CoOptUIPatcher.exe` from the releases page.

---

## Requirements

- **MacroQuest2** with Lua support (`mq2lua`) and the **ImGui** plugin loaded
- **EverQuest** running on an **emulator server**
- **Windows** (MacroQuest2 is Windows-only)
- Verify: `/lua run` should be a recognized command in-game

---

## Installation

### Using the Patcher (recommended for updates)

1. Download **CoOptUIPatcher.exe** from the [releases page](https://github.com/CooptGaming/CoopUI/releases).
2. Place it in your **MacroQuest2 root folder** (the folder containing `MacroQuest.exe`, `lua/`, `Macros/`).
3. Run `CoOptUIPatcher.exe`. It will validate the directory, check for updates, and download changed files. Missing default config files are created automatically.

### Manual Install (first time or full install)

1. Download the latest release zip from the [releases page](https://github.com/CooptGaming/CoopUI/releases).
2. Extract the zip into your **MacroQuest2 root folder**. Merge and overwrite when prompted — this places files into the existing `lua/`, `Macros/`, and `resources/` directories.
3. **First time only:** Either copy the contents of `config_templates/` into the matching `Macros/` folders (`sell_config`, `shared_config`, `loot_config`), or skip this step and let CoOpt UI create default config files on first launch.

### First Launch

1. In-game, run:
   ```
   /lua run itemui
   ```
2. The Welcome screen validates your environment (config folders, key INI files) and creates anything missing. Choose **Run Setup** to walk through the onboarding wizard, or **Skip** if you prefer to configure later.
3. Optionally load ScriptTracker:
   ```
   /lua run scripttracker
   ```

---

## Quick Start

After installation, these are the commands you will use most:

| Command | What it does |
|---------|--------------|
| `/itemui` or `/inv` | Toggle the main Inventory Companion window |
| `/dosell` | Run Auto Sell (merchant window must be open) |
| `/doloot` | Run Auto Loot (loots nearby corpses) |
| `/scripttracker` | Toggle the ScriptTracker window |
| `/itemui config` | Open the Settings window directly |
| `/itemui setup` | Re-run the onboarding wizard |

From the main window, companion windows (Bank, Equipment, Augments, AA, Reroll, Item Display, Settings) open via toolbar buttons. The Loot Companion opens automatically when you run `/doloot` (can be suppressed in Settings).

---

## Configuration

All configuration lives in INI files under three directories in `Macros/`:

| Directory | What it controls |
|-----------|-----------------|
| `sell_config/` | Sell protection flags, value thresholds, keep and junk lists, augment sell lists, layout, per-character data |
| `shared_config/` | Valuable item lists and epic item lists shared by both sell and loot |
| `loot_config/` | Loot flags, value thresholds, always-loot and skip lists, sorting options, session data |

You can edit these files directly or use the **Settings window** inside CoOpt UI, which has five tabs:

- **General** — Feature toggles, sell options (snap to merchant, sell mode), loot options, layout setup and revert
- **Sell Rules** — Keep (never sell), always sell, and never sell by type lists with add/remove and "From Cursor" support
- **Loot Rules** — Always loot and skip (never loot) lists with the same add/remove interface
- **Shared** — Valuable item lists and epic class protection (used by both sell and loot)
- **Advanced** — Debug channel toggles, backup and restore

Changes made in the Settings window are written to the INI files immediately and take effect on the next macro run.

For the full configuration reference, see [docs/CONFIGURATION.md](docs/CONFIGURATION.md).

---

## Components

| Component | Type | Load command | Toggle command |
|-----------|------|-------------|---------------|
| **ItemUI** | Lua UI | `/lua run itemui` | `/itemui` or `/inv` |
| **ScriptTracker** | Lua UI | `/lua run scripttracker` | `/scripttracker` |
| **Auto Sell** | Macro | — | `/dosell` |
| **Auto Loot** | Macro | — | `/doloot` |

---

## Project Structure

```
CoOpt UI/
├── lua/
│   ├── itemui/              # ItemUI: views, services, utils, core, components
│   │   ├── views/           #   UI windows (inventory, sell, bank, equipment, augments, aa, loot, reroll, settings, tutorial)
│   │   ├── services/        #   Backend logic (scan, sell, loot, augment ops, macro bridge, backup, reroll, filters)
│   │   ├── utils/           #   Helpers (layout, columns, sort, tooltips, theme, item helpers)
│   │   ├── core/            #   Infrastructure (registry, events, cache, debug, diagnostics, welcome validation)
│   │   ├── components/      #   Reusable UI components (search bar, filters, progress bar, character stats)
│   │   └── default_layout/  #   Bundled default window layout
│   ├── coopui/              # Shared core (version, theme, events, cache)
│   ├── scripttracker/       # ScriptTracker companion
│   └── mq/                  # Shared utilities (ItemUtils)
├── Macros/
│   ├── sell.mac             # Auto Sell macro
│   ├── loot.mac             # Auto Loot macro
│   ├── sell_config/         # Sell configuration (user data, preserved across updates)
│   ├── shared_config/       # Valuable and epic item lists (shared by sell + loot)
│   └── loot_config/         # Loot configuration (user data, preserved across updates)
├── config_templates/        # Default config files for first-time install
├── epic_quests/             # Epic 1.0 quest data (JSON + Lua) for all 16 classes
├── patcher/                 # Desktop patcher (Python source and build files)
├── resources/               # UI resource files (XML, TGA)
└── docs/                    # Documentation
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/INSTALL.md](docs/INSTALL.md) | Detailed installation, updating, and migration guide |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | Full INI file reference and sell/loot decision logic |
| [docs/DEVELOPER.md](docs/DEVELOPER.md) | Architecture, module map, and contributor guide |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Runtime architecture and data flow |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and diagnostics |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## Development

CoOpt UI is written in Lua using MacroQuest2's Lua scripting API and ImGui for rendering. The architecture uses a context registry pattern to manage dependencies within Lua's 60-upvalue limit, a 10-phase main loop for non-blocking operation, and event-based pub/sub for decoupled communication between services and views.

To set up a development environment:

1. Clone this repository into your MacroQuest2 root folder (or symlink `lua/`, `Macros/`, etc.).
2. Copy `config_templates/` contents into `Macros/` for initial config.
3. In-game: `/lua run itemui` to load. Changes to Lua files take effect after `/lua stop itemui` and `/lua run itemui`.

See [docs/DEVELOPER.md](docs/DEVELOPER.md) for the full module map, naming conventions, and contribution guidelines.

---

## Acknowledgements

- **[MacroQuest](https://www.macroquest.org/)** — The platform that makes this possible. CoOpt UI depends on MacroQuest2's Lua scripting, ImGui integration, and TLO data access.
- **[E3Next](https://github.com/RekkasGit/E3Next)** — Inspiration and foundation for multi-boxing automation workflows on EMU servers.
- **EverQuest emulator communities** — The server operators, developers, and players who keep classic EverQuest alive.
