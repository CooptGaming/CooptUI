# E3Next — ItemUI & ScriptTracker (MacroQuest2)

Item management and AA script tracking for EverQuest via MacroQuest2: unified inventory, bank, sell, and loot UI plus configurable keep/junk lists.

## Quick Start

**ItemUI** — Single window for inventory, bank, sell, and loot. Context-aware: shows sell view when merchant open, bank panel when bank open.

```
/lua run itemui
/itemui          -- Toggle window
/itemui setup    -- Configure layout sizes
/dosell          -- Run sell.mac (sell marked items)
/doloot          -- Run loot.mac (auto-loot corpses)
```

**ScriptTracker** — Track AA script progress (Lost/Planar, etc.).

```
/lua run scripttracker
/scripttracker   -- Toggle window
```

## Requirements

- MacroQuest2 with Lua support (mq2lua) and ImGui
- In-game: `/lua run itemui` and `/lua run scripttracker` must work

## Project Structure

```
MacroQuest2/
├── lua/
│   ├── itemui/             # Unified ItemUI (inventory + bank + sell + loot)
│   │   ├── init.lua
│   │   ├── config.lua
│   │   ├── rules.lua
│   │   ├── storage.lua
│   │   ├── components/, core/, services/, utils/, views/
│   │   └── README.md
│   ├── scripttracker/      # AA script tracker
│   │   ├── init.lua
│   │   └── README.md
│   └── mq/
│       └── ItemUtils.lua   # Shared formatValue, formatWeight
├── Macros/
│   ├── sell_config/        # Sell/keep/junk lists, layout
│   │   └── Chars/          # Per-character bank/inventory (local only)
│   ├── shared_config/      # Shared valuable items (epic, valuable lists)
│   ├── loot_config/        # Loot filters
│   ├── sell.mac
│   └── loot.mac
└── resources/UIFiles/Default/
    ├── EQUI.xml
    ├── MQUI_ItemColorAnimation.xml
    └── ItemColorBG.tga
```

### Config Paths (MQ2 convention)

- **Macros/sell_config/** — Sell keep/junk lists, layout, per-char data
- **Macros/shared_config/** — Shared valuable/epic items (used by loot and sell)
- **Macros/loot_config/** — Loot filters

## Installation

1. Extract or copy the release into your **MacroQuest2 root** (the folder that already contains `lua`, `Macros`, `config`). Merge/overwrite when prompted.
2. If you don’t have `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config`, copy the contents from `config_templates/` (see release zip) into those folders.
3. In-game: `/lua run itemui` and optionally `/lua run scripttracker`.

**Release packaging and deployment** — For versioned zips, update-safe installs, and test distribution, see **[docs/RELEASE_AND_DEPLOYMENT.md](docs/RELEASE_AND_DEPLOYMENT.md)**.

## Best Practices Applied

- **Local variables** — Module state uses `local` (Lua best practice)
- **Shared utilities** — `mq.ItemUtils` for formatValue/formatWeight
- **Cached config** — In-memory sell/loot lists; no INI read per item
- **Debounced saves** — ItemUI debounces layout saves for snappy interaction
- **Config location** — Macros/sell_config, shared_config, loot_config follow MQ2 convention

## Development

- **lua/itemui/** — ItemUI source; package per [docs/RELEASE_AND_DEPLOYMENT.md](docs/RELEASE_AND_DEPLOYMENT.md) for distribution.
- **lua/scripttracker/** — ScriptTracker source.
- This repository tracks only project files (ItemUI, ScriptTracker, macros, docs); see `.gitignore` and the release doc for scope.
