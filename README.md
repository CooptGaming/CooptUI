# CoOpt UI — EverQuest EMU Companion Suite

**CoOpt UI** is a MacroQuest2 **suite of UI companions** for EverQuest emulator servers. One load gives you multiple companion windows that work together with a single shared config: **Inventory** (with integrated sell when a merchant is open), **Bank**, **Loot** (progress and history), **Settings**, **Augments**, and **AAs**—plus **ScriptTracker** for AA script progress, and **Auto Sell** / **Auto Loot** macros that use the same rules. Edit lists in the UI or INI; the macros follow.

---

## Key features

- **Suite of companions** — One ItemUI load opens the main **Inventory Companion** (inventory + sell in one window). From there you open only what you need: **Bank**, **Loot**, **Settings**, **Augments**, **AA**. ScriptTracker is a separate companion for AA scripts.
- **One config, macros included** — Keep/junk, valuable, and epic lists are shared. Edit in Settings or INI; `sell.mac` and `loot.mac` use the same lists. Never sell what you meant to always loot.
- **Epic quest protection** — Per-class epic item lists (all 16 classes). Epic items are never sold; optional “always loot” and class filter via `epic_classes.ini`.
- **Rich item tooltips** — Hover any item for full stats, slots, augments. Right-click or use Keep/Junk in the sell view to edit lists without opening Settings.
- **Loot Companion** — Separate window for loot macro progress, session summary, Loot History, and Skip History. Optional; can be suppressed during looting.
- **Bank Companion** — Separate window: live when the bank is open, snapshot when closed. Shift+click in the main window to move items when the banker is open.
- **Performance-first** — Snapshot-first open, debounced saves, macro bridge with minimal polling. Built for stability and low overhead.

---

## Screenshots

_Screenshots will be added here. Suggested images:_

| Screenshot | Description |
|------------|-------------|
| **Inventory Companion** | Main window: inventory or sell view (e.g. `docs/screenshots/itemui-main.png`) |
| **Sell view** | Main window with merchant open: keep/junk, Sell button (e.g. `docs/screenshots/itemui-sell.png`) |
| **Bank / Settings / Loot** | One or more companion windows (e.g. `docs/screenshots/companions.png`) |
| **Settings / Item lists** | Config window or epic classes (e.g. `docs/screenshots/epic-config.png`) |

---

## How it works together

| Part | Role |
|------|------|
| **ItemUI** | One load: main **Inventory Companion** (inventory + sell in one window), plus **Bank**, **Loot**, **Settings**, **Augments**, and **AA** companion windows. Open only what you use. |
| **sell.mac** | Auto sell: sells items marked as junk to the open merchant. Uses `sell_config/` and `shared_config/` (valuable & epic = never sell). |
| **loot.mac** | Auto loot: loots corpses using your rules. Uses `loot_config/` and `shared_config/` (valuable & epic = always loot). Lore check, optional sorting, mythical alert. |
| **shared_config/** | One place for **valuable** and **epic** item lists. Both sell and loot use it. |
| **ScriptTracker** | Separate companion: AA script progress (Lost/Planar) and AA value. Own window; `/lua run scripttracker`. |
| **epic_quests/** | Optional: structured epic 1.0 quest data (JSON + Lua), master items list. Runtime epic protection uses INI lists in `shared_config/`. |

---

## Components

| Component | Type | Command | What it does |
|-----------|------|---------|--------------|
| **ItemUI** | Lua UI | `/lua run itemui` then `/itemui` | Inventory Companion (inventory + sell) + Bank, Loot, Settings, Augments, AA companion windows |
| **ScriptTracker** | Lua UI | `/lua run scripttracker` then `/scripttracker` | AA script progress (Lost/Planar) |
| **Auto Sell** | Macro | `/dosell` or `/macro sell confirm` | Sell marked items (sell.mac) |
| **Auto Loot** | Macro | `/doloot` or `/macro loot` | Auto-loot corpses (loot.mac) |

---

## Quick start

```
/lua run itemui
/itemui          -- Toggle main Inventory Companion window
/itemui setup    -- Configure layout sizes
-- From the main window: Bank, Settings, Augments, AA open as separate companion windows.
-- Loot Companion opens when you run Loot current / Loot all (unless suppressed in Settings).
/dosell          -- Sell (or use Sell button in sell view)
/doloot          -- Loot (or use Loot button in Loot Companion)
```

ScriptTracker: `/lua run scripttracker` then `/scripttracker` to toggle.

---

## Requirements

- **MacroQuest2** with Lua support (mq2lua) and ImGui
- In-game: `/lua run itemui` and `/lua run scripttracker` must work

---

## Installation

1. Extract the release into your **MacroQuest2 root** (folder that contains `lua`, `Macros`, `config`). Merge/overwrite when prompted.
2. **First time:** Copy from `config_templates/` into `Macros/sell_config`, `Macros/shared_config`, and `Macros/loot_config`—or run ItemUI and use first-run default protection (Settings) if `sell_flags.ini` is missing.
3. In-game: `/lua run itemui` and optionally `/lua run scripttracker`.

Details: **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/INSTALL.md](docs/INSTALL.md) | Installation, updating, migration |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | All INI files and decision logic |
| [docs/DEVELOPER.md](docs/DEVELOPER.md) | Architecture, modules, build/release |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and diagnostics |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [DEPLOY.md](DEPLOY.md) | Quick install (in release zip) |
| [epic_quests/README.md](epic_quests/README.md) | Epic quest data and scripts |

---

## Project structure

```
CoOpt UI/
├── lua/
│   ├── coopui/           # Shared core (version, theme, events, cache, state)
│   ├── itemui/           # ItemUI: Inventory + Bank + Loot + Settings + Augments + AA companions
│   ├── scripttracker/    # ScriptTracker companion
│   └── mq/               # Shared utilities (ItemUtils)
├── Macros/
│   ├── sell.mac          # Auto Sell
│   ├── loot.mac          # Auto Loot
│   ├── sell_config/      # Sell/keep lists, layout, per-char
│   ├── shared_config/    # Valuable & epic lists (used by sell + loot)
│   └── loot_config/      # Loot rules, flags, session/history
├── epic_quests/          # Optional: epic 1.0 data, master items, scripts
├── resources/UIFiles/Default/
└── docs/
```

Config is shared: ItemUI companions, sell.mac, and loot.mac all use `sell_config/`, `shared_config/`, and `loot_config/`. Edit in the Settings window, from the main window (right-click, list buttons), or directly in the INI files.

---

## Philosophy

- **Stability over features**
- **Performance over visual complexity**
- **One config** — one set of rules for all companions and both macros

---

## Target audience

EverQuest emulator players who want a consistent **suite** of companions for inventory, bank, selling, loot, and AAs—without scattered configs or duplicate lists.
