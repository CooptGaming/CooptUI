# CoOpt UI Plugin — Developer Setup

**Task:** 1.2 — Complete dev environment setup for building the MQ2CoOptUI plugin.

---

## Overview

This document describes the tools and steps required to build the CoOpt UI C++ plugin from a clean Windows machine. The **primary** path is a **32-bit** MQ build for **EMU**, used for day-to-day development and testing when an EQ Live instance is not available. An optional **64-bit** (Live) path is documented later for when you have Live access.

---

## Prerequisites

### Visual Studio 2022

- **Edition:** Community or Build Tools.
- **Workload:** "Desktop development with C++".
- **Component:** "C++ MFC for latest v143 build tools" (required by MacroQuest).
- Install from: [Visual Studio Downloads](https://visualstudio.microsoft.com/downloads/) or `winget install Microsoft.VisualStudio.2022.BuildTools` (with appropriate workload/components).

### Windows SDK

- Use the **Windows 10/11 SDK** installed with Visual Studio 2022. No separate version pin is required unless MQ’s CMake specifies one.

### CMake

- **Minimum version:** **3.30** (per MQ’s `cmake_minimum_required(VERSION 3.30)` in the root `CMakeLists.txt`).
- Install from [cmake.org](https://cmake.org/download/) or ensure it is on `PATH` for the build scripts.

### vcpkg

- **Do not** install vcpkg separately. Use the copy **inside the MQ repo**: `contrib/vcpkg`.
- After cloning MQ, run from the MQ repo root:
  - `contrib\vcpkg\bootstrap-vcpkg.bat`
- Set **`VCPKG_ROOT`** to the MQ repo’s vcpkg path (e.g. `C:\MQ-EMU-Dev\macroquest\contrib\vcpkg`) so that MQ’s CMake can find the toolchain file.

### Git

- Git for Windows with **submodule support** (standard install). Required to clone MacroQuest and run `git submodule update --init --recursive`.

---

## Build configuration (primary: 32-bit EMU)

- **Configuration:** Release.
- **Platform:** **Win32** (32-bit). Use `-A Win32` when running CMake. This matches EMU and is the primary target when you don’t have an EQ Live instance.
- **MSVC runtime:** Typically `/MD` for Release (MQ’s default). No need to override unless you are doing a custom build.

### EMU-specific environment considerations (PLUGIN_DEEP_DIVE §4.2)

| Factor | Impact |
|--------|--------|
| **32-bit (Win32)** | All pointers are 4 bytes. Struct layouts differ from 64-bit Live. Test with EMU-specific struct offsets when implementing item/window capabilities. |
| **eqlib EMU branch** | Item struct (ItemDefinition), character struct (CharacterBase), and window classes may have different member offsets than Live. Always build against the same eqlib branch your deployment uses. |
| **MQ version pinning** | The deployed MQ runtime (MQ2Main.dll, MQ2Lua.dll, etc.) **must** match what the plugin was built against. Deploy the full build output together (see `scripts/assemble_deploy.ps1` and PLUGIN_DEEP_DIVE §4.3). |
| **EQ client version** | EMU servers use older EQ clients. Some MQ APIs (e.g. Heirloom, Collectible item fields) may behave differently; test each field when implementing batch item scan. |

---

## Paths and layout

### MQ source location (primary: EMU clone)

- **Primary:** Use the **EMU** full clone at `C:\MQ-EMU-Dev\macroquest` (submodules and vcpkg already set up for Win32). This is the recommended path for building and testing against your EMU server.
- **Alternative:** Clone MQ yourself and build for Win32:
  - `git clone https://github.com/macroquest/macroquest.git C:\MQ-EMU-Dev\macroquest`
  - `cd C:\MQ-EMU-Dev\macroquest`
  - `git submodule update --init --recursive`
  - For EMU, ensure `eqlib` is on the EMU branch: `git -C src/eqlib checkout emu`
  - Run `.\contrib\vcpkg\bootstrap-vcpkg.bat`

### Plugin source location

- Plugin lives in the **CoOpt UI repo**: `plugin/MQ2CoOptUI/`.
- To build with MQ, use a **symlink** from the MQ clone’s `plugins` folder to the CoOpt UI plugin folder so CMake can discover it when `MQ_BUILD_CUSTOM_PLUGINS=ON`:
  - **EMU clone (primary):** From an elevated or developer command prompt:
    - `New-Item -ItemType SymbolicLink -Path "C:\MQ-EMU-Dev\macroquest\plugins\MQ2CoOptUI" -Target "C:\Projects\CoOptUI\plugin\MQ2CoOptUI"`
  - Or with `mklink /D` from cmd:  
    `mklink /D "C:\MQ-EMU-Dev\macroquest\plugins\MQ2CoOptUI" "C:\Projects\CoOptUI\plugin\MQ2CoOptUI"`
- Do **not** copy the plugin into the MQ tree; the symlink keeps a single source of truth in the CoOpt UI repo.

---

## Step-by-step: 32-bit (EMU) build and test (primary)

1. **Install** Visual Studio 2022 (with C++ desktop workload and MFC), CMake 3.30+, and Git.
2. **Use the EMU MQ clone** (e.g. `C:\MQ-EMU-Dev\macroquest`). Ensure vcpkg is bootstrapped there (`contrib\vcpkg\vcpkg.exe` exists).
3. **Set VCPKG_ROOT** (PowerShell, or add to your environment):
   - `$env:VCPKG_ROOT = "C:\MQ-EMU-Dev\macroquest\contrib\vcpkg"`
4. **Create the plugin symlink** (see “Plugin source location” above) so `plugins\MQ2CoOptUI` points at the CoOpt UI repo’s plugin folder.
5. **Configure** (from the EMU MQ clone root):
   - `cmake -B build/solution -G "Visual Studio 17 2022" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON`
   - If the plugin is not yet present, use `-DMQ_BUILD_CUSTOM_PLUGINS=OFF` for a first MQ-only build, then add the symlink and reconfigure with `ON`.
6. **Build**:
   - `cmake --build build/solution --config Release`
   - Or open `build/solution/MacroQuest.sln` in Visual Studio and build there.
7. **Run and test:** Run **MacroQuest.exe** from the build output (e.g. `build\solution\bin\release\MacroQuest.exe`). Use your EMU server instance to test the plugin; confirm MQ2CoOptUI loads, the `${CoOptUI}` TLO works, and `require("plugin.MQ2CoOptUI")` in Lua if you use it.

Build output layout for EMU (when using `-B build/solution` as above):

- `build/solution/bin/release/MacroQuest.exe` — launcher
- `build/solution/bin/release/plugins/MQ2CoOptUI.dll` — plugin

**If MacroQuest.exe is not in that folder:** If you used MQ’s `gen_solution.ps1` instead of `cmake -B build/solution`, the output is under `build\bin\release\` (not under `build\solution\`). Check there for `MacroQuest.exe`. Also ensure the launcher was built (use `-DMQ_BUILD_LAUNCHER=ON` or do not use `-SkipLauncher`).

You can copy the whole `bin/release` tree (and any `config`, `resources`, etc. your MQ setup expects) into a test folder or your EMU install for day-to-day testing.

---

## Optional: 64-bit (Live) build

Use when you have an EQ Live instance to test against.

- Use the **Live** full clone at `C:\MQ-Live-Dev\macroquest`, or your own clone with `-A x64`.
- Set `VCPKG_ROOT` to that clone’s `contrib\vcpkg`.
- Symlink the plugin to that clone’s `plugins\MQ2CoOptUI`.
- Configure: `cmake -B build/solution -G "Visual Studio 17 2022" -A x64 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON`
- Build: `cmake --build build/solution --config Release`
- Output is under `build/solution/bin/release/` (MacroQuest.exe and `plugins/MQ2CoOptUI.dll`).

## Using the MacroquestEnvironments full clones

If you have both clones at `C:\MQ-Environments` (each with submodules and vcpkg bootstrapped):

- **32-bit EMU (primary):**  
  `$env:VCPKG_ROOT = "C:\MQ-EMU-Dev\macroquest\contrib\vcpkg"`  
  From the EMU MQ clone root: `cmake -B build/solution -G "Visual Studio 17 2022" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON`

- **64-bit Live (optional):**  
  `$env:VCPKG_ROOT = "C:\MQ-Live-Dev\macroquest\contrib\vcpkg"`  
  From the Live MQ clone root: `cmake -B build/solution -G "Visual Studio 17 2022" -A x64 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON`

---

## Troubleshooting

- **vcpkg toolchain not found:** Ensure `VCPKG_ROOT` is set to the MQ clone’s `contrib\vcpkg` and that you have run `bootstrap-vcpkg.bat` there.
- **Plugin not built:** Ensure the plugin is at `MQClone\plugins\MQ2CoOptUI` (symlink or copy from `CoOptUIRepo\plugin\MQ2CoOptUI`) and CMake was run with `-DMQ_BUILD_CUSTOM_PLUGINS=ON`.
- **Launcher not built:** Add `-DMQ_BUILD_LAUNCHER=ON` to the cmake configure line.

### vcpkg / bzip2 (or other package) build failure

The MQ source **does** include vcpkg (under `contrib/vcpkg`): the scripts and port definitions are there. vcpkg then **downloads and compiles** dependencies (e.g. bzip2) the first time you configure or build; those built packages are not in the repo. If configure fails with errors like `Building package bzip2:x86-windows-static failed` (EMU) or `Building package bzip2:x64-windows-static failed` (Live), use the steps below.

1. **Bootstrap vcpkg first (required once per clone)**  
   From the MQ repo root (e.g. `C:\MQ-EMU-Dev\macroquest` or your `macroquest-clone`):
   ```powershell
   .\contrib\vcpkg\bootstrap-vcpkg.bat
   ```
   Confirm `contrib\vcpkg\vcpkg.exe` exists.

2. **Set VCPKG_ROOT** (same shell you use for CMake):
   ```powershell
   $env:VCPKG_ROOT = "C:\MQ-EMU-Dev\macroquest\contrib\vcpkg"   # or your MQ clone path
   ```

3. **Pre-install the failing package**  
   From the MQ repo root:
   ```powershell
   .\contrib\vcpkg\vcpkg install bzip2:x86-windows-static
   ```
   For 64-bit Live use: `.\contrib\vcpkg\vcpkg install bzip2:x64-windows-static`  
   If this succeeds, run CMake again. If it fails, continue to (4)–(5).

4. **Update vcpkg**  
   MQ’s vcpkg may be a submodule or a fixed copy. Update it so you get the latest bzip2 port:
   - If `contrib\vcpkg` is a git repo: `git -C contrib\vcpkg pull`
   - Then force MQ to re-run vcpkg: delete `contrib\vcpkg\vcpkg_mq_last_bootstrap.txt` (if it exists) and run step 3 again.

5. **Known bzip2 static + release-only issue**  
   Some vcpkg versions fail building bzip2 for static triplets because the port’s fixup looks for a debug lib even in release-only builds. Options:
   - Update vcpkg (step 4) and retry.
   - Or install the package with both configs so the debug lib exists:  
     `.\contrib\vcpkg\vcpkg install bzip2:x86-windows-static --debug` (to see the exact error), then try building MQ in both Debug and Release once so vcpkg has both libs.

6. **Clean and retry**  
   Remove vcpkg’s build artifacts for the failing port, then reinstall:
   ```powershell
   Remove-Item -Recurse -Force .\contrib\vcpkg\buildtrees\bzip2 -ErrorAction SilentlyContinue
   Remove-Item -Recurse -Force .\contrib\vcpkg\packages\bzip2_* -ErrorAction SilentlyContinue
   .\contrib\vcpkg\vcpkg install bzip2:x86-windows-static
   ```
   Then run CMake again. For Live (x64) use `x64-windows-static` instead.

If the error mentions a **different** package (e.g. `libzip`, `zlib`), replace `bzip2` with that package name and use the same triplet (`x86-windows-static` for EMU, `x64-windows-static` for Live) in the steps above.

### CMake 4.x: "Compatibility with CMake &lt; 3.5 has been removed"

If vcpkg fails when building bzip2 (or other ports) with:

```text
CMake Error at CMakeLists.txt:1 (cmake_minimum_required):
  Compatibility with CMake < 3.5 has been removed from CMake.
```

your **CMake is 4.x**, which dropped support for very old `cmake_minimum_required` values used by some vcpkg ports.

**Fix:** Use **CMake 3.30 or 3.31** (not 4.x) when building MQ and when running vcpkg:

1. Install CMake 3.30 or 3.31 from [cmake.org](https://cmake.org/download/) (e.g. "cmake-3.30.x-windows-x86_64.msi") and install it to a separate path (e.g. `C:\Program Files\CMake330`).
2. When running vcpkg or CMake for MQ, put that CMake **first** on `PATH`, for example (PowerShell):
   ```powershell
   $env:Path = "C:\Program Files\CMake330\bin;" + $env:Path
   cmake --version   # should show 3.30 or 3.31
   ```
   Then run `vcpkg install bzip2:x64-windows-static` and/or the MQ CMake configure from the same shell.
3. Alternatively, use the VS 2022 installer to install "CMake 3.30" (or 3.31) from the Individual components and ensure it is selected before any CMake 4.x component in the list, so the 3.x executable is found first on PATH.

### "detect_custom_plugins Function invoked with incorrect arguments"

If CMake fails at `CMakeLists.txt:153` with "Function invoked with incorrect arguments for function named: detect_custom_plugins", the second argument may be expanding to multiple values. In the MQ repo root, edit `CMakeLists.txt` line 153 and quote the second argument:

- Change: `detect_custom_plugins(MQ_CUSTOM_PLUGIN_SUBDIRS ${MQ_CUSTOM_PLUGINS_FILE})`
- To: `detect_custom_plugins(MQ_CUSTOM_PLUGIN_SUBDIRS "${MQ_CUSTOM_PLUGINS_FILE}")`

Then reconfigure. If it still fails, try configuring with `-DMQ_BUILD_CUSTOM_PLUGINS=OFF` to build MQ without the plugin, then add the plugin symlink and reconfigure with `ON` (or use a custom plugin list file).

### "Unknown CMake command vcpkg_install_empty_package"

If vcpkg fails when building the `loader` overlay port with "Unknown CMake command 'vcpkg_install_empty_package'", the MQ `src/loader/portfile.cmake` was written for a different vcpkg version. Edit the loader portfile in the MQ clone:

- Open `src/loader/portfile.cmake`
- Remove or comment out the line: `vcpkg_install_empty_package()`
- Keep the line: `set(VCPKG_POLICY_EMPTY_PACKAGE enabled)`

Then delete the build folder and run CMake again (so vcpkg re-runs from a clean state).

### "crashpad target already exists" (duplicate target)

If CMake fails with `_add_library cannot create target "crashpad" because another target with the same name already exists`, both `src/main` and `src/loader` call `find_package(crashpad)`, and the crashpad config creates the target each time. Edit the crashpad port in the MQ clone:

- Open `contrib/vcpkg-ports/crashpad-backtrace/crashpadConfig.cmake.in`
- Wrap the target creation in a guard: add `if(NOT TARGET crashpad)` before `add_library(crashpad INTERFACE)` and add `endif()` after the final `target_include_directories` line.

### MQ2Main linker errors: ImAnim / iam_* unresolved

If MQ2Main.dll fails to link with unresolved externals like `ImAnimDemoWindow`, `iam_update_begin_frame`, etc., the imgui CMakeLists is missing the imanim source files. Edit `src/imgui/CMakeLists.txt` in the MQ clone:

- Add to `imgui_SOURCES`: `imanim/im_anim.cpp`, `imanim/im_anim_demo.cpp`, `imanim/im_anim_doc.cpp`, `imanim/im_anim_usecase.cpp`
- Add to `imgui_HEADERS`: `imanim/im_anim.h`, `imanim/im_anim_internal.h`

### MQ2CoOptUI: sol::table redefinition / pCoOptUIType undeclared

If the plugin fails with `'sol::table': redefinition; different basic types` or `'pCoOptUIType': undeclared identifier`:

1. **sol::table:** The capability headers use `namespace sol { class table; }` which conflicts with sol2 (where `table` is a type alias). Replace that forward declaration with `#include <sol/forward.hpp>` in each of: `capabilities/window.h`, `capabilities/ipc.h`, `capabilities/items.h`, `capabilities/loot.h`, `capabilities/ini.h`.

2. **pCoOptUIType:** Move the declaration before the class: add `class MQ2CoOptUIType; static MQ2CoOptUIType* pCoOptUIType = nullptr;` before the `MQ2CoOptUIType` class definition, and remove the duplicate declaration after the class.

### Loader: curl-84 target not found

If the loader fails with `Target "MacroQuest" links to: curl-84::curl-84 but the target was not found`, the vcpkg curl-84 port exposes `CURL-84::libcurl`. Edit `src/loader/CMakeLists.txt` and change `curl-84::curl-84` to `CURL-84::libcurl`.

### Network.cpp: std::unordered_set::contains (C++20)

If `src/routing/Network.cpp` fails with `'contains': is not a member of 'std::unordered_set'`, the project uses C++17 but `contains()` is C++20. Replace `!m_selfHosts.contains(address)` with `m_selfHosts.find(address) == m_selfHosts.end()`.
