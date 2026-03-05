# MQ2CoOptUI Plugin

This directory is the **single source of truth** for the MQ2CoOptUI C++ plugin. Builds are done from the MacroQuest clone with a **symlink** from the MQ clone’s `plugins/MQ2CoOptUI` to this folder.

## Symlink (required for build)

From an elevated PowerShell or Developer Command Prompt, create the symlink so MQ’s CMake can see the plugin when `-DMQ_BUILD_CUSTOM_PLUGINS=ON`:

**EMU clone (32-bit):**
```powershell
New-Item -ItemType SymbolicLink `
  -Path "C:\MQ-EMU-Dev\macroquest\plugins\MQ2CoOptUI" `
  -Target "C:\Projects\CoOptUI\plugin\MQ2CoOptUI"
```

**Live clone (64-bit):** Use the same pattern with the Live clone path and `plugins\MQ2CoOptUI`.

Do **not** copy the plugin into the MQ tree; the symlink keeps this repo as the single source of truth.

## Macro IPC (slash command)

Macros (.mac) can write to plugin IPC so Lua can read without INI files:

```
/cooptui ipc send sell_progress 10,5,5
/cooptui ipc send sell_failed item1|item2
```

Lua reads via `coopt.ipc.receive("sell_progress")` etc. If the plugin is not loaded, macros should fall back to existing `/ini` writes.

## Layout (when implemented)

- `MQ2CoOptUI.cpp` — InitializePlugin, ShutdownPlugin, OnPulse, CreateLuaModule
- `CMakeLists.txt` — plugin target, LuaPlugin.props
- `capabilities/` — ini, ipc, window, items, loot (each with .h/.cpp)

See **Implementation Plan** (`docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md`) and **PLUGIN_DEEP_DIVE** (`docs/plugin/PLUGIN_DEEP_DIVE.md`) for capability order and implementation details.

## Deploy

After building, deploy the **full** MQ build output (never only this plugin DLL) so ABI matches:

```powershell
.\scripts\assemble_deploy.ps1 -MQBuildDir "C:\...\macroquest-clone\build\solution\bin\release" -DeployDir "C:\MQ\Deploy"
```

See `docs/plugin/dev_setup.md` and `.cursor/rules/mq-plugin-build-gotchas.mdc` §17.
