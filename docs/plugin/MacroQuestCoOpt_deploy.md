# MacroQuestCoOpt Deployment

**Location:** `C:\MQ-Deploy\MacroQuestCoOpt`

A 32-bit (Win32) MacroQuest deployment that combines the EMU clone build with E3Next and CoOpt UI. Built 2025-02-28.

## What It Is

- **MQ EMU clone** — MQ2Main, imgui, eqlib, MQ2Lua, MQ2CoOptUI, MacroQuest.exe
- **E3Next** — Bot framework (mono)
- **CoOpt UI** — ItemUI, ScriptTracker, macros

The MQ2CoOptUI plugin provides `require("plugin.MQ2CoOptUI")` with CreateLuaModule support.

## Build & Deploy

1. Build the EMU clone (see `mq-plugin-build-gotchas.mdc` and `dev_setup.md`)
2. Run `C:\MQ-Deploy\MacroQuestCoOpt\assemble_deploy.ps1`
3. Run `E3NextMQ\MacroQuest.exe`

## Documentation

- **BUILD_NOTES.md** — Full build process, gotchas applied, potential issues for future builds
- **README.md** — Quick start

## Plugin Source

The MQ2CoOptUI plugin in the EMU clone was copied from the Live clone's `plugins/MQ2CoOptUI`. The dev_setup.md references a symlink to `E3NextAndMQNextBinary-main/plugin/MQ2CoOptUI` — that folder may not exist in this repo; use the copy from the Live clone if needed.
