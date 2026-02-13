# CoOpt UI — EverQuest EMU Companion

**CoOpt UI** is a MacroQuest2 suite for EverQuest emulator servers. One product, four components: **ItemUI** (unified inventory/bank/sell/loot UI), **ScriptTracker** (AA script progress), **Auto Sell**, and **Auto Loot**—with a single shared config so the UI and macros always use the same rules.

---

## Key features

- **One window for items** — ItemUI: inventory, bank, sell, and loot in one context-aware window. No switching between separate UIs.
- **One config, two macros** — Edit keep/junk, valuable, and epic lists in ItemUI or INI; `sell.mac` and `loot.mac` use the same lists. Never sell what you meant to always loot.
- **Epic quest protection** — Per-class epic item lists (all 16 classes). Epic items are never sold and can be set to always loot. Optional class filter via `epic_classes.ini`.
- **Rich item tooltips** — Hover any item for full stats, slots, augments. Right-click or use Keep/Junk in the sell view to edit lists without opening Config.
- **Loot view before you loot** — See how each corpse item will be evaluated (loot/skip). Add **Always Loot** / **Always Skip** from the UI; rules stay in sync with the loot macro.
- **Quick bank** — Shift+click items to move to/from bank when the banker is open. Bank panel: live when bank open, snapshot when closed.
- **AA script tracking** — ScriptTracker: Lost/Planar AA script progress and AA value in a separate window.
- **Performance-first** — Snapshot-first open, debounced saves, macro bridge with minimal polling. Built for stability and low overhead.

---

## Screenshots

_Screenshots will be added here. Suggested images:_

| Screenshot | Description |
|------------|-------------|
| **Main window** | ItemUI inventory view with bank button visible (e.g. `docs/screenshots/itemui-main.png`) |
| **Sell view** | ItemUI with merchant open: keep/junk toggles, Sell button (e.g. `docs/screenshots/itemui-sell.png`) |
| **Config / Item lists** | Config window, Item Lists or epic classes (e.g. `docs/screenshots/epic-config.png`) |

---

## How it works together

| Part | Role |
|------|------|
| **ItemUI** | Central hub: one window for inventory, bank, sell, and loot. View items, edit keep/junk and loot lists, trigger sell/loot. All config is shared with the macros. |
| **sell.mac** | Auto sell: sells items marked as junk to the open merchant. Uses `sell_config/` and `shared_config/` (valuable & epic = never sell). |
| **loot.mac** | Auto loot: loots corpses using your rules. Uses `loot_config/` and `shared_config/` (valuable & epic = always loot). Lore check, optional sorting, mythical alert. |
| **shared_config/** | One place for **valuable** and **epic** item lists. Both sell and loot use it. |
| **ScriptTracker** | Separate Lua UI: tracks AA script progress (Lost/Planar) and AA value. |
| **epic_quests/** | Optional: structured epic 1.0 quest data (JSON + Lua), master items list. Runtime epic protection uses INI lists in `shared_config/`. |

---

## Components

| Component      | Type   | Command                          | What it does |
|----------------|--------|----------------------------------|--------------|
| **ItemUI**     | Lua UI | `/lua run itemui` then `/itemui` | Unified inventory, bank, sell, loot; config editor |
| **ScriptTracker** | Lua UI | `/lua run scripttracker` then `/scripttracker` | AA script progress (Lost/Planar) |
| **Auto Sell**  | Macro  | `/dosell` or `/macro sell confirm` | Sell marked items (sell.mac) |
| **Auto Loot**  | Macro  | `/doloot` or `/macro loot`       | Auto-loot corpses (loot.mac) |

---

## Quick start

```
/lua run itemui
/itemui          -- Toggle window
/itemui setup    -- Configure layout sizes
/dosell          -- Sell (or use Sell button in sell view)
/doloot          -- Loot (or use Loot button in loot view)
```

ScriptTracker: `/lua run scripttracker` then `/scripttracker` to toggle.

---

## Requirements

- **MacroQuest2** with Lua support (mq2lua) and ImGui
- In-game: `/lua run itemui` and `/lua run scripttracker` must work

---

## Installation

1. Extract the release into your **MacroQuest2 root** (folder that contains `lua`, `Macros`, `config`). Merge/overwrite when prompted.
2. **First time:** Copy from `config_templates/` into `Macros/sell_config`, `Macros/shared_config`, and `Macros/loot_config`—or run ItemUI and use first-run default protection (Config window) if `sell_flags.ini` is missing.
3. In-game: `/lua run itemui` and optionally `/lua run scripttracker`.

Details: **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/COOPUI_OVERVIEW.md](docs/COOPUI_OVERVIEW.md) | One-page scope and where to look |
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
│   ├── itemui/           # ItemUI (unified window + config)
│   ├── scripttracker/    # ScriptTracker (AA scripts)
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

Config is shared: ItemUI, sell.mac, and loot.mac all use `sell_config/`, `shared_config/`, and `loot_config/`. Edit in ItemUI’s Config window, via right-click/list buttons in the views, or directly in the INI files.

---

## Philosophy

- **Stability over features**
- **Performance over visual complexity**
- **One config** — one set of rules for the UI and both macros

---

## Target audience

EverQuest emulator players who want a single, consistent setup for inventory, bank, selling, and loot—without scattered configs or duplicate lists.
