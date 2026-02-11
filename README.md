# CoopUI — EverQuest EMU Companion

A comprehensive UI companion for EverQuest emulator servers, built on MacroQuest2. CoopUI gives you **one unified window** for inventory, bank, selling, and loot—with epic item protection and configurable auto sell/loot. Built for stability and minimal performance overhead.

<!-- SCREENSHOT: CoopUI ItemUI main window — e.g. inventory view with bank button visible. Suggested: docs/screenshots/itemui-main.png -->

---

## Highlights

### One window, context-aware

**ItemUI** is the heart of CoopUI. One window replaces separate inventory, bank, and sell UIs:

- **Inventory view** — Bags, slots, weight, flags; **quick bank moving** when the banker is open (hold **Shift** and left-click an item to move it to bank, or from bank to inventory).
- **Sell view** — Automatically switches when you open a merchant: keep/junk toggles, value, and one-click **Sell** to run the sell macro.
- **Bank panel** — Slide-out bank view; live when the bank is open, historic snapshot when it’s closed.
- **Loot view** — See how items on a corpse will be evaluated (loot / skip) before you loot.

**Hover any item** for a rich tooltip (stats, value, flags). **Right-click** items in the inventory (or use Keep/Always sell in the sell view) to add or remove them from keep/junk lists; in the **loot view**, use **Always Loot** / **Always Skip** to add items to your loot lists without opening the config window.

<!-- SCREENSHOT: ItemUI with merchant window open (sell view). Suggested: docs/screenshots/itemui-sell.png -->

### sell.mac & loot.mac integration

Auto Sell and Auto Loot are first-class: trigger them from ItemUI or by command.

- **Sell:** Use the **Sell** button in the sell view or run `/dosell` — sells items marked as junk to the open merchant.
- **Loot:** Use the **Loot** button in the loot view or run `/doloot` — auto-loots the current corpse using your loot rules.

Both macros share the same config (keep/junk, loot always/skip) with ItemUI, so your lists stay in sync.

### Epic quest items — protected by default

CoopUI knows about class epics. Per-class epic item lists in `shared_config/` (all 16 classes) mean:

- **Never sell** epic quest items, with optional class filtering via `epic_classes.ini`.
- **Always loot** epic items when auto-looting.
- Shared config keeps loot and sell behavior in sync so you don’t accidentally sell or skip a piece you need.

<!-- SCREENSHOT (optional): Config window "Item Lists" or epic_classes.ini. Suggested: docs/screenshots/epic-config.png -->

---

## Components

| Component        | Type   | Command                    | What it does |
|------------------|--------|----------------------------|--------------|
| **ItemUI**       | Lua UI | `/lua run itemui`          | Unified inventory, bank, sell, and loot |
| **ScriptTracker** | Lua UI | `/lua run scripttracker`   | AA script progress (Lost/Planar, etc.) |
| **Auto Sell**    | Macro  | `/dosell`                  | Sell marked items to merchant (sell.mac) |
| **Auto Loot**    | Macro  | `/doloot`                  | Auto-loot corpses (loot.mac) with configurable filters |

---

## Quick start

### ItemUI

```
/lua run itemui
/itemui          -- Toggle window
/itemui setup    -- Configure layout sizes
/dosell          -- Sell marked items (or use Sell button in sell view)
/doloot          -- Auto-loot corpses (or use Loot button in loot view)
```

### ScriptTracker

```
/lua run scripttracker
/scripttracker   -- Toggle window
```

### Auto sell & loot (standalone)

```
/macro sell      -- Run sell.mac directly
/macro loot      -- Run loot.mac directly
```

---

## Requirements

- MacroQuest2 with Lua support (mq2lua) and ImGui
- In-game: `/lua run itemui` and `/lua run scripttracker` must work

---

## Installation

1. Extract or copy the release into your **MacroQuest2 root** (folder that contains `lua`, `Macros`, `config`). Merge/overwrite when prompted.
2. **First time:** If you don’t have config INI files, copy from `config_templates/` into `Macros/sell_config`, `Macros/shared_config`, and `Macros/loot_config`. Alternatively, run `/lua run itemui` — on first run, if `sell_flags.ini` is missing, ItemUI will offer to load a default protection list (common keywords and types).
3. In-game: `/lua run itemui` and optionally `/lua run scripttracker`.

Detailed steps: **[docs/INSTALL.md](docs/INSTALL.md)**.

---

## Documentation

| Document | Description |
|----------|-------------|
| [docs/INSTALL.md](docs/INSTALL.md) | Installation, updating, migration |
| [docs/CONFIGURATION.md](docs/CONFIGURATION.md) | All INI files and decision logic |
| [docs/DEVELOPER.md](docs/DEVELOPER.md) | Architecture, modules, build/release, contributing |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues and diagnostics |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [DEPLOY.md](DEPLOY.md) | Quick install card (in release zip) |

---

## Project structure

```
MacroQuest2/
├── lua/
│   ├── itemui/           # ItemUI (unified window)
│   ├── scripttracker/    # ScriptTracker
│   └── mq/               # Shared utilities
├── Macros/
│   ├── sell.mac          # Auto Sell
│   ├── loot.mac          # Auto Loot
│   ├── sell_config/      # Sell/keep, layout, per-char
│   ├── shared_config/    # Valuable & epic item lists
│   └── loot_config/      # Loot filters
└── resources/UIFiles/Default/
```

Config is shared between ItemUI, Auto Sell, and Auto Loot. Edit via ItemUI’s Config window, right-click and list buttons in the views, or the INI files directly.

---

## Philosophy

- **Stability over features**
- **Performance over visual complexity**
- **One place for items** — one window, one set of rules

---

## Target audience

EverQuest emulator players seeking reliable UI tools for inventory, bank, selling, and loot—without bloat.
