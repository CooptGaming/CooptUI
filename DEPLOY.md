# CoopUI — Install / Update

## Requirements

- MacroQuest2 with Lua support (mq2lua) and ImGui.
- In-game: `/lua run itemui` and `/lua run scripttracker` must work.

## First-time install

1. Extract this zip into your **MacroQuest2 folder** (the folder that already contains `lua`, `Macros`, `config`). When prompted, choose to merge/overwrite so that the new `lua`, `Macros`, and `resources` folders merge with your existing ones.
2. If you do **not** already have `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config` with INI files inside, copy the contents of `config_templates/sell_config` into `Macros/sell_config`, `config_templates/shared_config` into `Macros/shared_config`, and `config_templates/loot_config` into `Macros/loot_config`.
3. In-game: run `/lua run itemui` and optionally `/lua run scripttracker`. Use `/itemui` and `/scripttracker` to toggle the windows.

## Updating

1. Extract the new zip into your MacroQuest2 folder.
2. Allow overwriting for: `lua/itemui`, `lua/scripttracker`, `lua/mq/ItemUtils.lua`, `Macros/sell.mac`, `Macros/loot.mac`, `Macros/shared_config/*.mac`, and `resources/UIFiles/Default/` (EQUI.xml, MQUI_ItemColorAnimation.xml, ItemColorBG.tga).
3. Do **not** overwrite your existing `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config` INI files (or the `Chars` folders inside sell_config). Your keep/junk lists and layout will be preserved.

## Commands

- `/itemui` or `/inv` — Toggle ItemUI window
- `/itemui setup` — Configure panel sizes
- `/scripttracker` — Toggle ScriptTracker (Lost/Planar script counts)
- `/dosell` — Run sell macro (sell marked items)
- `/doloot` — Run loot macro (auto-loot)
