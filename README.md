# CoOpt UI — EverQuest EMU Companion

**CoOpt UI** is a MacroQuest2 suite for EverQuest emulator servers. It ties together a **unified item UI**, **auto sell** and **auto loot** macros, **epic-aware config**, and **AA script tracking**—with one shared config model so the UI and macros always use the same rules.

<!-- SCREENSHOT: CoOpt UI Items Companion main window — e.g. inventory view with bank button visible. Suggested: docs/screenshots/itemui-main.png -->

---

## How it works together

| Part | Role |
|------|------|
| **ItemUI** | Central hub: one window for inventory, bank, sell, and loot. You view items, edit keep/junk and loot lists, and trigger sell/loot from here. All config is shared with the macros. |
| **sell.mac** | Auto sell: sells items marked as junk to the open merchant. Reads `sell_config/` and `shared_config/` (valuable & epic = never sell). |
| **loot.mac** | Auto loot: loots corpses using your rules. Reads `loot_config/` and `shared_config/` (valuable & epic = always loot). Lore check, optional sorting, mythical alert. |
| **shared_config/** | One place for **valuable** and **epic** item lists. Both sell and loot use it, so you don’t sell something you meant to always loot (or vice versa). |
| **ScriptTracker** | Separate Lua UI: tracks AA script progress (Lost/Planar) and AA value. |
| **epic_quests/** | Optional data and tooling: structured epic 1.0 quest data (JSON + Lua), master items list, and scripts to generate/maintain them. Runtime epic protection uses the INI lists in `shared_config/` (e.g. `epic_items_<class>.ini`). |

So: **one config, one UI, two macros.** Edit in ItemUI or the INI files; sell.mac and loot.mac follow the same lists and flags.

---

## Highlights

### One window, context-aware

**ItemUI** is the main surface. One window replaces separate inventory, bank, and sell UIs:

- **Inventory view** — Bags, slots, weight, flags; **quick bank** when the banker is open (hold **Shift** and left-click to move items to/from bank).
- **Sell view** — Switches when you open a merchant: keep/junk toggles, value, one-click **Sell** to run sell.mac.
- **Bank panel** — Slide-out; live when the bank is open, snapshot when closed.
- **Loot view** — See how each corpse item will be evaluated (loot/skip) before you loot; **Always Loot** / **Always Skip** to add items to your lists.

**Hover** any item for a rich tooltip. **Right-click** in inventory (or use Keep/Always sell in the sell view) to add or remove items from keep/junk lists without opening the config window.

<!-- SCREENSHOT: ItemUI with merchant open (sell view). Suggested: docs/screenshots/itemui-sell.png -->

### sell.mac & loot.mac integration

Trigger from ItemUI or by command:

- **Sell:** **Sell** button in the sell view or `/dosell` (or `/macro sell confirm`).
- **Loot:** **Loot** button in the loot view or `/doloot` (or `/macro loot`).

Both macros use the same shared config (keep/junk, valuable, epic) so your lists stay in sync.

### Epic quest items — protected by default

Per-class epic item lists in `shared_config/` (all 16 classes):

- **Never sell** epic items (optional class filter via `epic_classes.ini`).
- **Always loot** epic items when auto-looting.

<!-- SCREENSHOT (optional): Config "Item Lists" or epic_classes. Suggested: docs/screenshots/epic-config.png -->

---

## Components

| Component        | Type   | Command                    | What it does |
|------------------|--------|----------------------------|--------------|
| **ItemUI**       | Lua UI | `/lua run itemui`          | Unified inventory, bank, sell, loot; config editor |
| **ScriptTracker** | Lua UI | `/lua run scripttracker`   | AA script progress (Lost/Planar) |
| **Auto Sell**    | Macro  | `/dosell` or `/macro sell confirm` | Sell marked items (sell.mac) |
| **Auto Loot**    | Macro  | `/doloot` or `/macro loot` | Auto-loot corpses (loot.mac) |

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

- MacroQuest2 with Lua support (mq2lua) and ImGui
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
CoOpt UI repo/
├── lua/
│   ├── coopui/           # Shared core (version, theme, events, cache, state)
│   ├── itemui/           # ItemUI (unified window + config)
│   ├── scripttracker/    # ScriptTracker (AA scripts)
│   └── mq/                # Shared utilities (ItemUtils)
├── Macros/
│   ├── sell.mac           # Auto Sell
│   ├── loot.mac           # Auto Loot
│   ├── sell_config/       # Sell/keep lists, layout, per-char
│   ├── shared_config/     # Valuable & epic lists (used by sell + loot)
│   └── loot_config/       # Loot rules, flags, session/history
├── epic_quests/           # Optional: epic 1.0 data, master items, Python scripts
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
