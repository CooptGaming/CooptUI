# Source Environment & Build Guide

Build MacroQuest EMU + MQ2Mono + MQ2CoOptUI + E3Next from source, deploy with CoOpt UI, and optionally produce a prebuilt zip.

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| **Visual Studio 2022** | Community or Build Tools | Workloads: "Desktop development with C++" (with C++ MFC), ".NET desktop development" (for E3Next). |
| **CMake** | **3.30** (not 4.x) | Install to `C:\Program Files\CMake`. The scripts put it first on PATH. |
| **Git** | Any recent | With submodule support (standard install). |
| **.NET Framework 4.8 Developer Pack** | Optional | Only needed if building E3Next from source. [Download](https://dotnet.microsoft.com/download/dotnet-framework/net48). |
| **Windows** | 10/11 | Developer Mode or elevated prompt recommended (for symlinks). |

---

## Quick Start

### 1. Assemble the source tree

```powershell
cd C:\Projects\CoOptUI
.\scripts\setup-source-env.ps1 -SourceRoot "C:\MQ-EMU-Dev"
```

This creates:

```
C:\MQ-EMU-Dev\
├── macroquest\                      # MQ clone (eqlib on EMU branch)
│   ├── src\eqlib\                   # EMU offsets
│   ├── contrib\vcpkg\               # bootstrapped vcpkg
│   ├── plugins\
│   │   ├── MQ2Mono\                 # MQ2Mono clone (if -MQ2MonoRepo provided)
│   │   └── MQ2CoOptUI\ -> ...      # symlink to this repo's plugin/MQ2CoOptUI
│   └── ...
└── E3Next\                          # E3Next C# solution
```

**Options:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SourceRoot` | `../MQ-EMU-Dev` (sibling of repo) | Root directory for all source trees. |
| `-CMakePath` | `C:\Program Files\CMake` | Path to CMake 3.30 installation. |
| `-MQRepo` | `https://github.com/macroquest/macroquest.git` | MacroQuest git URL. |
| `-EqLibBranch` | `emu` | Branch for eqlib (use `emu` for EMU, `main` for Live). |
| `-MQ2MonoRepo` | *(empty)* | MQ2Mono git URL. Required for E3Next support. |
| `-E3NextRepo` | `https://github.com/RekkasGit/E3Next.git` | E3Next git URL. |
| `-SkipE3Next` | | Skip cloning E3Next. |
| `-SkipGotchas` | | Skip applying build fixes. |
| `-Force` | | Re-clone MQ even if already present. |

### 2. Build and deploy

```powershell
.\scripts\build-and-deploy.ps1 -SourceRoot "C:\MQ-EMU-Dev" -DeployPath "C:\MQ\Deploy"
```

This:
1. Configures and builds MQ with CMake 3.30 (Win32, Release).
2. Builds E3Next (if source is present and MSBuild is available).
3. Deploys everything to `-DeployPath` with the full CoOpt UI layout.

**Options:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SourceRoot` | *(required)* | Path from setup-source-env.ps1. |
| `-DeployPath` | *(required)* | Target deploy folder. |
| `-CMakePath` | `C:\Program Files\CMake` | CMake 3.30 path. |
| `-Configuration` | `Release` | Build configuration. |
| `-E3NextBinaryPath` | | Path to pre-built E3Next binaries (skip building from source). |
| `-MonoFrameworkPath` | | Path to MQ2Mono-Framework32 (mono-2.0-sgen.dll + BCL). |
| `-SkipBuild` | | Skip all building, just deploy from existing output. |
| `-SkipMQBuild` | | Skip MQ build only. |
| `-SkipE3Next` | | Skip E3Next build. |
| `-CreateZip` | | Create a prebuilt zip after deploying. |
| `-ZipVersion` | `YYYYMMDD` | Version string for zip filename. |

### 3. Create a prebuilt zip (optional)

```powershell
.\scripts\build-and-deploy.ps1 -SourceRoot "C:\MQ-EMU-Dev" -DeployPath "C:\MQ\Deploy" -CreateZip -ZipVersion "20260302"
```

Output: `C:\MQ\CoOptUI-EMU-20260302.zip`

---

## Deploy Folder Structure

After `build-and-deploy.ps1`, the deploy folder contains:

```
Deploy/
├── MacroQuest.exe                   # MQ launcher
├── MQ2Main.dll                      # MQ core (injected into EQ)
├── mono-2.0-sgen.dll                # Mono runtime (32-bit, from -MonoFrameworkPath)
├── config/
│   ├── MacroQuest.ini               # mq2mono=1, MQ2CoOptUI=1
│   └── MQ2CustomBinds.txt           # /inv bind for itemui
├── plugins/
│   ├── MQ2Lua.dll
│   ├── MQ2Mono.dll
│   ├── MQ2CoOptUI.dll
│   └── ...                          # Other MQ plugins
├── Mono/
│   └── macros/
│       ├── e3/
│       │   ├── E3Next.dll
│       │   └── ...                  # E3Next dependencies
│       └── coophelper/
│           └── CoopHelper.dll       # Optional
├── Macros/
│   ├── sell.mac
│   ├── loot.mac
│   ├── sell_config/
│   │   ├── itemui_layout.ini
│   │   ├── sell_keep_exact.ini
│   │   └── ...
│   ├── shared_config/
│   │   ├── log_item.mac
│   │   ├── validate_config.mac
│   │   ├── valuable_exact.ini
│   │   └── ...
│   └── loot_config/
│       ├── loot_always_contains.ini
│       └── ...
├── lua/
│   ├── itemui/                      # CoOpt UI main app
│   ├── coopui/                      # Shared infra (cache, events, theme)
│   ├── scripttracker/               # AA script tracker
│   └── mq/
│       └── ItemUtils.lua
├── resources/
│   └── UIFiles/
│       └── Default/
│           ├── EQUI.xml
│           ├── MQUI_ItemColorAnimation.xml
│           └── ItemColorBG.tga
└── E3 Bot Inis/
    └── README.txt
```

---

## Iterative Development

After the initial deploy, use `sync-to-deploytest.ps1` to push Lua/Macro/resource changes without a full rebuild:

```powershell
.\scripts\sync-to-deploytest.ps1 -Target "C:\MQ-Deploy\CoOptUI2"
```

This copies:
- `lua/itemui`, `lua/coopui`, `lua/scripttracker`, `lua/mq/ItemUtils.lua`
- `Macros/sell.mac`, `Macros/loot.mac`, `Macros/shared_config/*.mac`
- `resources/UIFiles/Default/*`
- `CoopHelper.dll` (if built)

It does **not** overwrite config INIs (`sell_config/*.ini`, `shared_config/*.ini`, `loot_config/*.ini`).

---

## Build Gotchas

The setup script automatically applies known build fixes from `.cursor/rules/mq-plugin-build-gotchas.mdc`. To apply them manually:

```powershell
.\scripts\apply-build-gotchas.ps1 -MQClone "C:\MQ-EMU-Dev\macroquest"
```

Key fixes applied:
1. bzip2 `cmake_minimum_required` 3.0 → 3.5
2. Loader portfile: remove `vcpkg_install_empty_package()`
3. Crashpad duplicate target guard
4. curl-84 target name: `CURL-84::libcurl`
5. PostOffice.h: add `#include <windows.h>`
6. MQ2Lua: set C++20 standard
7. imgui: add imanim source files
8. Loader: add Windows link libraries
9. `detect_custom_plugins`: quote second argument
10. Network.cpp: `.contains()` → `.find()`
11. MQ2Mono: `#include <array>`, labelPtr → labelStr

All patches are idempotent. See the gotchas `.mdc` file for full details and symptoms.

---

## ABI Safety

**Never deploy only MQ2CoOptUI.dll** into a folder with different MQ2Main/MQ2Lua versions. The `build-and-deploy.ps1` script copies the complete build output from a single build, ensuring ABI consistency. If you need to update just the plugin, rebuild the entire MQ solution and redeploy.

---

## MQ2Mono and Mono Runtime

MQ2Mono requires:
1. **MQ2Mono source** cloned into `plugins/MQ2Mono/` (done by setup script if `-MQ2MonoRepo` is provided).
2. **Mono runtime** (`mono-2.0-sgen.dll`, 32-bit for EMU) placed in the deploy folder.

The Mono runtime is **not** built from source — it comes from a pre-built framework distribution (e.g. MQ2Mono-Framework32). Provide `-MonoFrameworkPath` to `build-and-deploy.ps1` to include it.

---

## E3Next

E3Next is a C# (.NET Framework 4.8) solution built separately from the MQ C++ tree.

- **Build from source:** Requires .NET Framework 4.8 Developer Pack + VS 2022.
- **Use pre-built:** Pass `-E3NextBinaryPath` to skip building and use existing binaries.
- **Skip entirely:** Use `-SkipE3Next` if you don't need E3Next.

If E3Next fails at runtime with type initializer exceptions, see gotcha #19b in `mq-plugin-build-gotchas.mdc`.

---

## Prebuilt Zip for End Users

To produce a distribution zip that users can download, extract, and run:

```powershell
.\scripts\build-and-deploy.ps1 `
    -SourceRoot "C:\MQ-EMU-Dev" `
    -DeployPath "C:\MQ\Deploy" `
    -MonoFrameworkPath "C:\MQ2Mono-Framework32" `
    -CreateZip -ZipVersion "1.0.0"
```

The zip contains the same layout as the deploy folder. Users extract it, configure their EQ path, and launch `MacroQuest.exe`.

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| CMake version errors | Ensure CMake 3.30 is first on PATH, not 4.x. |
| vcpkg bootstrap fails | Run `contrib\vcpkg\bootstrap-vcpkg.bat` manually in the MQ clone. |
| Symlink fails | Enable Developer Mode in Windows Settings, or run from elevated prompt. |
| E3Next build fails | Install .NET Framework 4.8 Developer Pack, or use `-E3NextBinaryPath`. |
| Plugin not built | Ensure symlink exists at `macroquest\plugins\MQ2CoOptUI` and configure used `-DMQ_BUILD_CUSTOM_PLUGINS=ON`. |
| MQ2Mono not found | Provide `-MQ2MonoRepo` to setup script, or clone manually into `plugins\MQ2Mono`. |
| Stale cmake 4.x build | Delete `macroquest\build\solution` and reconfigure. |
| Loader injection fails | See gotcha #14 — check eqgame.exe path and permissions. |
