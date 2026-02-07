# EverQuest UI Overhaul - MacroQuest2

Item management UIs for EverQuest via MacroQuest2: inventory, bank, and merchant selling with configurable keep/junk lists.

## Quick Start

### Option A: ItemUI (Unified - Recommended)
Single window for inventory, bank, and sell. Context-aware: shows sell view when merchant open, bank panel when bank open.

```
/lua run itemui
/itemui          -- Toggle window
/itemui setup    -- Configure layout sizes
/dosell          -- Run sell.mac (sell marked items)
/doloot          -- Run loot.mac (auto-loot corpses)
```

### Option B: Standalone UIs
- **SellUI** – Merchant sell interface (auto-opens when merchant open)
- **BankUI** – Bank items (auto-opens when bank open)

```
/lua run sellui
/sellui           -- Toggle (alias: /sell)

/lua run bankui
/bankui           -- Toggle
```

## Project Structure (MacroQuest2 Best Practices)

```
MacroQuest2/
├── lua/                    # Lua scripts (MQ2 default: lua/)
│   ├── itemui/             # Unified ItemUI (inventory + bank + sell)
│   │   ├── init.lua
│   │   ├── config.lua
│   │   ├── rules.lua
│   │   └── storage.lua
│   ├── mq/
│   │   └── ItemUtils.lua   # Shared formatValue, formatWeight
│   ├── sellui/             # Standalone sell UI
│   ├── bankui/             # Standalone bank UI
│   └── lootui/             # Loot UI
├── Macros/
│   ├── sell_config/        # Sell/keep/junk lists, layout
│   │   ├── Chars/          # Per-character bank/inventory snapshots
│   │   └── itemui_layout.ini
│   ├── shared_config/      # Shared valuable items (loot + sell)
│   ├── loot_config/        # Loot filters
│   ├── sell.mac
│   ├── loot.mac
│   └── iteminfo.mac
└── resources/UIFiles/      # EQ XML UIs (MQUI_*.xml)
```

### Config Paths (MQ2 Convention)
- **Macros/sell_config/** – Sell keep/junk lists, layout, per-char data
- **Macros/shared_config/** – Shared valuable items (used by loot.mac and sell.mac)
- **Macros/loot_config/** – Loot filters

## Installation

1. Extract/copy into your MacroQuest2 root folder.
2. Ensure `lua/` and `Macros/` folders merge with existing structure.
3. Run `/lua run itemui` or `/lua run sellui` as desired.

### Release packaging and deployment
For building versioned zips, update-safe installs, and test-user distribution, see **[docs/RELEASE_AND_DEPLOYMENT.md](docs/RELEASE_AND_DEPLOYMENT.md)**. That document defines package structure, what to replace on update vs preserve, config templates, and user-facing DEPLOY.md text for release zips.

## Best Practices Applied

- **Local variables** – All module state uses `local` (Lua best practice)
- **Shared utilities** – `mq.ItemUtils` for formatValue/formatWeight (no duplication)
- **Cached config** – SellUI uses in-memory lists; no INI reads per item
- **Debounced saves** – ItemUI debounces layout saves (600ms) for snappy interaction
- **Main loop** – 33ms delay when UI visible, 100ms when hidden
- **Config location** – Macros/sell_config follows MQ2 convention for user-editable configs

## Development

- **lua/itemui/** – ItemUI source; package per [docs/RELEASE_AND_DEPLOYMENT.md](docs/RELEASE_AND_DEPLOYMENT.md) for distribution.
