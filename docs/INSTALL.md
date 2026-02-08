# CoopUI Installation Guide

## Prerequisites

- **MacroQuest2** with Lua support (`mq2lua`) and **ImGui** plugin loaded
- **Windows** (MQ2 is Windows-only)
- **EverQuest** running on an emulator server (Hero's Journey, etc.)
- Verify: `/lua run` should be a recognized command in-game

## Downloading

Download the latest release zip from GitHub:

**https://github.com/CooptGaming/CoopUI/releases**

The zip is named `CoopUI_v<version>.zip` (e.g., `CoopUI_v0.2.0-alpha.zip`).

## First-Time Installation

### Step 1: Locate your MacroQuest2 root folder

This is the folder that already contains `lua/`, `Macros/`, `config/`, and `MacroQuest.exe`. Common locations:

```
C:\MQ2\
C:\MacroQuest\
C:\EQ\MacroQuest2\
```

### Step 2: Extract the zip

Extract `CoopUI_v<version>.zip` directly into your MQ2 root folder. When prompted, choose **merge/overwrite** so that the `lua/`, `Macros/`, and `resources/` folders merge with your existing ones.

### Step 3: Copy config templates (first time only)

If you do **not** already have config INI files, copy the templates:

```
config_templates/sell_config/    →  Macros/sell_config/
config_templates/shared_config/  →  Macros/shared_config/
config_templates/loot_config/    →  Macros/loot_config/
```

If you already have these folders with INI files inside (from SellUI or a previous install), **skip this step** — your existing configs are compatible.

### Step 4: Launch in-game

```
/lua run itemui            -- Start ItemUI
/lua run scripttracker     -- Start ScriptTracker (optional)
```

### Step 5: Verify

- Type `/itemui` — the ItemUI window should appear
- Type `/scripttracker` — ScriptTracker should appear
- Check the MQ2 console for the version message: `[ItemUI] Item UI v0.2.0-alpha loaded.`

## Updating

When a new version is released:

1. Download the new zip from the releases page
2. Extract into your MQ2 root folder, overwriting existing files

### What gets overwritten (safe)

- `lua/itemui/` — all Lua source code
- `lua/scripttracker/` — ScriptTracker source
- `lua/coopui/` — shared core modules
- `lua/mq/ItemUtils.lua` — shared utilities
- `Macros/sell.mac`, `Macros/loot.mac` — macro scripts
- `Macros/shared_config/*.mac` — shared macro includes
- `resources/UIFiles/Default/` — UI resource files

### What is preserved (never in the release zip)

- `Macros/sell_config/*.ini` — your sell configuration
- `Macros/sell_config/Chars/` — per-character bank/inventory data
- `Macros/shared_config/*.ini` — your valuable item lists
- `Macros/loot_config/*.ini` — your loot configuration
- `Macros/sell_config/itemui_layout.ini` — your window layout
- `Macros/sell_config/itemui_filter_presets.ini` — your saved filter presets

## Migrating from SellUI

If you were previously using SellUI, migration is seamless:

1. **Stop SellUI**: `/lua stop sellui`
2. **Start ItemUI**: `/lua run itemui`
3. **Optional**: Open Config (click Config button) and enable "Snap to Merchant" for SellUI-like positioning
4. **Done!** All your `sell_config/` INI files work as-is

### Feature mapping

| SellUI Feature | ItemUI Equivalent |
|----------------|-------------------|
| Inventory tab | Sell view (auto-switches when merchant opens) |
| Keep/Junk buttons | Same buttons in sell view |
| Auto Sell button | Same button at top of sell view |
| Config tabs | Config window (click "Config" button) |
| Align to merchant | "Snap to Merchant" option in config |
| Search & filter | Enhanced filter system in Item Lists tab |

LootUI is also deprecated — use ItemUI's Loot Rules tab for all loot configuration.

## Directory Structure

After installation, your MQ2 folder should look like:

```
MacroQuest2/
├── lua/
│   ├── itemui/                 # ItemUI source
│   │   ├── init.lua            #   Entry point
│   │   ├── config.lua          #   INI read/write
│   │   ├── config_cache.lua    #   Cached config APIs
│   │   ├── context.lua         #   Context registry
│   │   ├── rules.lua           #   Sell/loot rule evaluation
│   │   ├── storage.lua         #   Per-character persistence
│   │   ├── components/         #   UI components
│   │   ├── core/               #   Cache, events, state
│   │   ├── services/           #   Filter, macro bridge, scan
│   │   ├── utils/              #   Layout, theme, columns, sort, tooltips
│   │   └── views/              #   Inventory, bank, sell, loot, config, augments
│   ├── scripttracker/          # ScriptTracker source
│   │   └── init.lua
│   ├── coopui/                 # Shared core
│   │   ├── version.lua
│   │   ├── core/               #   Events, cache, state
│   │   └── utils/              #   Theme
│   └── mq/
│       └── ItemUtils.lua       # Shared utilities
├── Macros/
│   ├── sell.mac                # Auto Sell macro
│   ├── loot.mac                # Auto Loot macro
│   ├── sell_config/            # Sell configuration (your data)
│   │   ├── sell_flags.ini
│   │   ├── sell_value.ini
│   │   ├── sell_keep_exact.ini
│   │   ├── sell_always_sell_exact.ini
│   │   ├── ...                 # (other sell INI files)
│   │   └── Chars/              # Per-character data
│   ├── shared_config/          # Shared valuable/epic items
│   │   ├── valuable_exact.ini
│   │   ├── epic_classes.ini
│   │   ├── epic_items_*.ini
│   │   └── *.mac              # Shared macro includes
│   └── loot_config/            # Loot configuration
│       ├── loot_flags.ini
│       ├── loot_value.ini
│       ├── loot_sorting.ini
│       └── loot_always_exact.ini
└── resources/UIFiles/Default/
    ├── EQUI.xml
    ├── MQUI_ItemColorAnimation.xml
    └── ItemColorBG.tga
```

## Commands Quick Reference

### ItemUI

| Command | Description |
|---------|-------------|
| `/lua run itemui` | Load ItemUI |
| `/itemui` or `/inv` or `/inventoryui` | Toggle ItemUI window |
| `/itemui show` | Show window |
| `/itemui hide` | Hide window |
| `/itemui refresh` | Refresh inventory/bank/sell data |
| `/itemui setup` | Enter setup mode (resize panels) |
| `/itemui config` | Open config window |
| `/itemui exit` (or `quit`, `unload`) | Unload ItemUI |
| `/itemui help` | Show command help |

### ScriptTracker

| Command | Description |
|---------|-------------|
| `/lua run scripttracker` | Load ScriptTracker |
| `/scripttracker` | Toggle ScriptTracker window |

### Macros

| Command | Description |
|---------|-------------|
| `/dosell` | Run sell macro (sell marked items to merchant) |
| `/doloot` | Run loot macro (auto-loot corpses) |
| `/macro sell` | Run sell macro directly |
| `/macro loot` | Run loot macro directly |
