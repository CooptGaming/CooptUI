# CoopUI — EverQuest EMU Companion (MacroQuest2)

A comprehensive UI companion for EverQuest emulator servers, built on MacroQuest2. CoopUI provides unified item management, AA script tracking, and automated loot/sell workflows — designed for stability during raids and minimal performance overhead.

## Components

| Component | Type | Command | What It Does |
|-----------|------|---------|-------------|
| **ItemUI** | Lua UI | `/lua run itemui` | Unified inventory, bank, sell, and loot interface |
| **ScriptTracker** | Lua UI | `/lua run scripttracker` | AA script progress tracking (Lost/Planar, etc.) |
| **Auto Sell** | Macro | `/dosell` | Sell marked items to merchant |
| **Auto Loot** | Macro | `/doloot` | Auto-loot corpses with configurable filters |

## Quick Start

### ItemUI

Single window for inventory, bank, sell, and loot. Context-aware: shows sell view when merchant is open, bank panel when banker is open.

```
/lua run itemui
/itemui          -- Toggle window
/itemui setup    -- Configure layout sizes
/dosell          -- Run sell.mac (sell marked items)
/doloot          -- Run loot.mac (auto-loot corpses)
```

**AA Window (optional):** Click the **AA** button in the ItemUI footer to open the Alt Advancement window. View and train AAs by category (General, Archetype, Class, Special), search, and use **Export** to save your current AA setup to a file and **Import** to restore it after a server AA reset. Backups are stored in `Macros/sell_config/` as `aa_CharacterName_YYYYMMDD_HHMMSS.ini`. The list is cached and refreshes on open, when you click Refresh, or after Train/Import. You can hide the AA button by setting `ShowAAWindow=0` in the layout INI.

### ScriptTracker

Track AA script progress (Lost/Planar, etc.).

```
/lua run scripttracker
/scripttracker   -- Toggle window
```

### Auto Loot & Auto Sell

These macros can be triggered from ItemUI buttons or run standalone:

```
/macro sell      -- Run sell macro directly
/macro loot      -- Run loot macro directly
```

## Requirements

- MacroQuest2 with Lua support (mq2lua) and ImGui
- In-game: `/lua run itemui` and `/lua run scripttracker` must work

## Installation

1. Extract or copy the release into your **MacroQuest2 root** (the folder that already contains `lua`, `Macros`, `config`). Merge/overwrite when prompted.
2. If you don't have `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config`, copy the contents from `config_templates/` (see release zip) into those folders.
3. In-game: `/lua run itemui` and optionally `/lua run scripttracker`.

For detailed step-by-step instructions, see **[docs/INSTALL.md](docs/INSTALL.md)**.

## Documentation

| Document | Description |
|----------|-------------|
| **[docs/INSTALL.md](docs/INSTALL.md)** | Installation, updating, and migration guide |
| **[docs/CONFIGURATION.md](docs/CONFIGURATION.md)** | Complete configuration reference (all INI files, decision logic) |
| **[docs/DEVELOPER.md](docs/DEVELOPER.md)** | Architecture, patterns, module map, build/release, contributing |
| **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** | Common issues, error messages, diagnostics |
| **[CHANGELOG.md](CHANGELOG.md)** | Version history and release notes |
| **[DEPLOY.md](DEPLOY.md)** | Quick install card (included in release zip) |

## Project Structure

```
MacroQuest2/
├── lua/
│   ├── itemui/             # CoopUI component: Unified ItemUI
│   │   ├── init.lua        #   Entry point (/lua run itemui)
│   │   ├── config.lua      #   INI read/write, config paths
│   │   ├── rules.lua       #   Sell/loot rule evaluation
│   │   ├── storage.lua     #   Per-character persistence
│   │   ├── components/     #   UI components (filters, searchbar, progressbar)
│   │   ├── core/           #   Cache, events, state management
│   │   ├── services/       #   Filter service, macro bridge, scan, aa_data
│   │   ├── utils/          #   Layout, theme, columns, sort, tooltips
│   │   ├── views/          #   Inventory, bank, sell, loot, config, augments, aa
│   │   └── README.md
│   ├── scripttracker/      # CoopUI component: ScriptTracker
│   │   ├── init.lua        #   Entry point (/lua run scripttracker)
│   │   └── README.md
│   └── mq/
│       └── ItemUtils.lua   # Shared utilities (formatValue, formatWeight)
├── Macros/
│   ├── sell.mac            # CoopUI component: Auto Sell
│   ├── loot.mac            # CoopUI component: Auto Loot
│   ├── sell_config/        # Sell/keep/junk lists, layout
│   │   └── Chars/          # Per-character bank/inventory (local only)
│   ├── shared_config/      # Shared valuable items (epic, valuable lists)
│   └── loot_config/        # Loot filters
└── resources/UIFiles/Default/
    ├── EQUI.xml
    ├── MQUI_ItemColorAnimation.xml
    └── ItemColorBG.tga
```

### Config Paths (MQ2 Convention)

- **Macros/sell_config/** — Sell keep/junk lists, layout, per-char data, AA backups (`aa_*.ini`)
- **Macros/shared_config/** — Shared valuable/epic items (used by loot and sell)
- **Macros/loot_config/** — Loot filters

Config files are shared between ItemUI, Auto Sell, and Auto Loot. Edit them from ItemUI's Config window or directly in the INI files.

## Best Practices Applied

- **Local variables** — Module state uses `local` throughout (Lua best practice)
- **Shared utilities** — `mq.ItemUtils` for formatValue/formatWeight across components
- **Cached config** — In-memory sell/loot lists; no INI read per item evaluation
- **Debounced saves** — ItemUI debounces layout saves for snappy interaction
- **Config location** — `Macros/sell_config`, `shared_config`, `loot_config` follow MQ2 convention
- **Modular architecture** — Views, services, and utilities are separated into individual modules
- **Stability first** — Graceful handling of zone transitions, server lag, and missing dependencies

## Development

CoopUI source lives in this repository:

- **lua/itemui/** — ItemUI source (main UI surface)
- **lua/scripttracker/** — ScriptTracker source
- **Macros/sell.mac, loot.mac** — Auto Sell and Auto Loot macros
- **docs/** — Design documents, deployment guide, class guides

This repository tracks only CoopUI project files; see `.gitignore` and [docs/DEVELOPER.md](docs/DEVELOPER.md) for scope and packaging.

## Target Audience

EverQuest emulator players (Hero's Journey, etc.) seeking reliable UI enhancement tools that prioritize stability and performance over feature bloat.

## Philosophy

- Stability over features
- Performance over visual complexity
- User experience over technical showcasing
- Maintainability over clever code

**Build it like a tool you'd trust during your own raids.**
