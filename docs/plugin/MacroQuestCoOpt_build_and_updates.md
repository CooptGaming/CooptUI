# MacroQuestCoOpt: Build Process and Updating CoOpt Features

This document describes how to build the MacroQuestCoOpt deployment and how to apply updates when you change CoOpt UI features (Lua, macros, config, or the MQ2CoOptUI plugin).

---

## 1. What MacroQuestCoOpt Is

- **Location:** `C:\MQ-Deploy\MacroQuestCoOpt`
- **Deploy folder:** `MacroQuestCoOpt\E3NextMQ` (run MacroQuest.exe from here)
- **Sources:**
  - **MQ build:** EMU clone at `C:\MQ-EMU-Dev\macroquest` (build output → deploy)
  - **CoOpt content:** This repo (`E3NextAndMQNextBinary-main`) — lua, Macros, config_templates, default_layout, mono, etc. are **merged** into the deploy by `assemble_deploy.ps1`

So the deploy is: **MQ build output** + **merge from this repo** + MQUI files + mono-2.0-sgen + optional plugins from MacroQuestEMU.

---

## 2. Full Build Process (Clean or First Time)

Do this when setting up a new machine, after pulling MQ clone changes that affect the build, or when you need a clean deploy.

1. **Environment** (PowerShell):
   ```powershell
   $env:Path = "C:\Program Files\CMake\bin;" + $env:Path
   $env:VCPKG_ROOT = "C:\MQ-EMU-Dev\macroquest\contrib\vcpkg"
   ```

2. **Build the EMU clone** (see `MacroQuestCoOpt\BUILD_NOTES.md` and `.cursor\rules\mq-plugin-build-gotchas.mdc`):
   ```powershell
   cd C:\MQ-EMU-Dev\macroquest
   # If you previously used CMake 4.x, delete build/solution first
   cmake -B build/solution -G "Visual Studio 17 2022" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON
   cmake --build build/solution --config Release
   ```

3. **Assemble the deploy:**
   ```powershell
   cd C:\MQ-Deploy\MacroQuestCoOpt
   .\assemble_deploy.ps1
   ```

4. **Run:** `E3NextMQ\MacroQuest.exe`

---

## 3. Updating When CoOpt Features Change

Use this table to decide what to rebuild and what to re-run.

| What you changed | Rebuild MQ clone? | Re-assemble deploy? | Notes |
|------------------|-------------------|----------------------|--------|
| **Lua** (itemui, scripttracker, coopui, etc.) | No | **Yes** | Assemble **overwrites** deploy's `lua\` with this repo's `lua\`. |
| **Macros** (sell, loot, shared_config) | No | **Yes** | Assemble overwrites deploy's `Macros\` with this repo's `Macros\`. |
| **resources**, **config_templates**, **default_layout** | No | **Yes** | Same: assemble merges from this repo. |
| **mono** (E3 bot content) | No | **Yes** | Assemble overwrites deploy's `mono\` with this repo's `mono\`. |
| **config** (INI/config files) | No | **Yes** | Assemble merges `config\` from this repo. |
| **MQ2CoOptUI plugin (C++)** | **Yes** | **Yes** | Rebuild clone (so the new plugin DLL is in build output), then reassemble. |
| **MQ2Mono** (C++) | **Yes** | **Yes** | Same as plugin: rebuild clone, then reassemble. |
| **Nothing in this repo** (only MQ core or other plugins in clone) | **Yes** | **Yes** | Rebuild clone, then reassemble to get new MQ binaries. |

### Quick reference

- **Lua/Macros/config/mono/resources only (CoOpt “content”):**  
  Just re-run **assemble** — no need to rebuild the EMU clone.
  ```powershell
   cd C:\MQ-Deploy\MacroQuestCoOpt
   .\assemble_deploy.ps1
  ```

- **MQ2CoOptUI or MQ2Mono (or any C++ in the clone):**  
  Rebuild the **EMU clone**, then **assemble**.
  ```powershell
   cd C:\MQ-EMU-Dev\macroquest
   cmake --build build/solution --config Release
   cd C:\MQ-Deploy\MacroQuestCoOpt
   .\assemble_deploy.ps1
  ```

---

## 4. Where CoOpt Plugin Source Lives

- **MQ2CoOptUI** is built from the **EMU clone**. Its source is under the clone’s `plugins\MQ2CoOptUI` (copy or symlink from this repo’s `plugin\MQ2CoOptUI` if that folder exists).
- When you change MQ2CoOptUI C++ in this repo, ensure the clone’s `plugins\MQ2CoOptUI` is updated (e.g. symlink target or copy), then rebuild the clone and reassemble.

---

## 5. Paths Summary

| Path | Purpose |
|------|--------|
| `E3NextAndMQNextBinary-main` | CoOpt UI repo (this repo); source for lua, Macros, config, mono, etc. |
| `MacroquestEnvironments\MacroQuestCoOpt` | MacroQuestCoOpt env: scripts + BUILD_NOTES + README. |
| `MacroQuestCoOpt\E3NextMQ` | Assembled deploy; run MacroQuest from here. |
| `MacroquestEnvironments\MacroquestEMU\macroquest-clone` | EMU MQ source + build; produces MQ2Main, MQ2Lua, MQ2CoOptUI, MQ2Mono, etc. |

---

## 6. References

- **Build gotchas:** `.cursor\rules\mq-plugin-build-gotchas.mdc`
- **MacroQuestCoOpt build notes:** `MacroQuestCoOpt\BUILD_NOTES.md` (in MacroquestEnvironments)
- **Plugin dev setup:** `docs\plugin\dev_setup.md`
- **Plugin implementation plan:** `docs\plugin\MQ2COOPTCORE_IMPLEMENTATION_PLAN.md`
