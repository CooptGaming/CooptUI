# Implementation Prompt: Unified Source Environment + Deploy + Prebuilt Package

**Purpose:** Hand this prompt to an AI (e.g. Opus 4.6 or similar) to implement the full workflow we designed: a single “source” environment that assembles MacroQuest EMU, MQ2Mono, E3Next, and the MQ2CoOptUI plugin; builds with Visual Studio 2022 and CMake 3.30; deploys with configs and INIs in the correct locations; and optionally produces a prebuilt zip so users can download and run without building.

**Reference docs in this repo:** `docs/plugin/dev_setup.md`, `.cursor/rules/mq-plugin-build-gotchas.mdc`, `docs/ARCHITECTURE.md`, `docs/mono/BRIDGE_DECISION.md`. E3Next user flow: [E3Next Wiki — Getting started EMU 32bit](https://github.com/RekkasGit/E3Next/wiki/1)-Getting-started-EMU-32bit).

---

## Context

We have a CoOpt UI project (Lua + optional C# CoopHelper). We want to build and deploy the **C++ plugin (MQ2CoOptUI)** in an environment that also includes:

- **MacroQuest** built for EMU (32-bit Win32, eqlib on EMU branch).
- **MQ2Mono** (C++ plugin that loads the Mono runtime and C# assemblies like E3Next and CoopHelper).
- **E3Next** (C# automation) so the same deploy folder runs both CoOpt UI and E3Next.
- **MQ2CoOptUI** (our C++ plugin) built from this repo’s `plugin/MQ2CoOptUI/` (or the branch that contains it).

The problem we had: a pre-built “E3” binary distribution didn’t allow building our plugin because we didn’t control that build. The solution: **we build the whole stack from source** so the plugin is part of the same ABI-matched build. We also want **configs and INIs in the correct locations** so the deploy folder (and any prebuilt zip) “just works” like the E3Next getting-started flow.

---

## Goals

1. **Unified source folder**  
   One root directory (e.g. `Source/` or `MQ-EMU-Dev/`) that contains:
   - MacroQuest EMU source (with eqlib on EMU branch).
   - MQ2Mono plugin source at `plugins/MQ2Mono/` inside the MQ tree.
   - MQ2CoOptUI plugin at `plugins/MQ2CoOptUI/` inside the MQ tree (symlink or copy from this repo).
   - E3Next source as a sibling folder (e.g. `E3Next/`), since it’s a separate C# solution.

2. **Automated assembly**  
   A script (or set of scripts) that:
   - Clones or copies MacroQuest (and ensures eqlib EMU branch, submodules, vcpkg bootstrap).
   - Clones or copies MQ2Mono into the MQ tree at `plugins/MQ2Mono`.
   - Creates a symlink (or copy) from this repo’s `plugin/MQ2CoOptUI` to the MQ tree at `plugins/MQ2CoOptUI`.
   - Clones or copies E3Next into the sibling folder.
   - Applies the known gotchas from `.cursor/rules/mq-plugin-build-gotchas.mdc` to the MQ tree (e.g. loader portfile, crashpad guard, curl-84, bzip2 cmake_minimum_required, MQ2Lua C++20, imgui imanim, MQ2CoOptUI sol/pCoOptUIType, detect_custom_plugins, etc.).
   - Uses CMake **3.30** (not 4.x) and sets `VCPKG_ROOT` to the MQ clone’s `contrib/vcpkg`.

3. **Build**  
   - Configure MQ with: `-G "Visual Studio 17 2022" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=ON -DMQ_BUILD_LAUNCHER=ON -DMQ_REGENERATE_SOLUTION=OFF` (or per gotchas).
   - Build from that tree so the output includes MacroQuest.exe, MQ2Main.dll, MQ2Lua.dll, MQ2Mono.dll, MQ2CoOptUI.dll, and other plugins.
   - E3Next is built separately (C# with VS 2022 or `dotnet build`); its output is not part of the CMake solution.

4. **Deploy layout (configs and INIs in correct locations)**  
   The deploy target structure must match our reference layout (e.g. `C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI`). After build + deploy, the deploy folder must contain:
   - **Binaries:** MacroQuest.exe, plugins/*.dll (MQ2Main, MQ2Lua, MQ2Mono, MQ2CoOptUI, etc.).
   - **Mono runtime:** `mono-2.0-sgen.dll` (32-bit for EMU) and any required BCL — from MQ2Mono-Framework32 or the MQ2Mono repo; placed where MQ2Mono expects (e.g. next to MacroQuest.exe or in a `Mono` resource folder per MQ2Mono README).
   - **config/** — MacroQuest.ini with `mq2mono=1` and the plugin list including MQ2CoOptUI; other MQ config as needed.
   - **plugins/** — All built plugin DLLs.
   - **Mono/macros/e3/** — E3Next build output (E3Next.dll and dependencies).
   - **Mono/macros/coophelper/** — Optional: CoopHelper.dll if we ship it.
   - **Macros/sell_config/**, **Macros/shared_config/**, **Macros/loot_config/** — Default or template INIs for CoOpt UI (itemui_layout, sell/loot/shared configs).
   - **E3 Bot Inis/** — Folder for E3Next bot INIs (CharacterName_ServerShortName.ini); can be empty with a README.
   - **resources/** — Any required resources (e.g. mq2nav placeholder, UIFiles).
   - **lua/** — CoOpt UI Lua and scripttracker so the same deploy runs CoOpt UI.
   - **resources/** (UIFiles, etc.) and any other CoOpt UI assets.

   The deploy script must include the **latest release of CoOpt UI files**: Lua (`lua/itemui/`, `lua/coopui/`, `lua/scripttracker/`), resources (e.g. `resources/UIFiles/Default/`), Macros defaults (`Macros/sell_config/`, `Macros/shared_config/`, `Macros/loot_config/`), config templates, and C# CoopHelper DLL if released. “Latest release” means either the latest git tag or the latest GitHub Release of this repo (e.g. CoOptGaming/E3NextAndMQNextBinary or the canonical CoOpt UI repo); the script should fetch or copy from that release so the deploy folder gets the current user-facing CoOpt UI, not an arbitrary working tree. The deploy script must also copy (or merge) **config and INI templates** from that release into the deploy folder so that paths and contents are correct. Do not rely on the build output alone to provide these; have a single source of truth for “default config layout” and copy it during deploy.

5. **Single-command workflow**  
   Ideally one script (e.g. `scripts/setup-source-env.ps1` and `scripts/build-and-deploy.ps1`) that:
   - Assembles the source tree (if not already present).
   - Builds MQ (with MQ2Mono and MQ2CoOptUI).
   - Builds E3Next (C#).
   - Fetches or copies the **latest release of CoOpt UI files** (Lua, resources, Macros, config, CoopHelper DLL if applicable) from the CoOpt UI repo’s latest tag or GitHub Release.
   - Deploys everything—including those CoOpt UI release files—to a configurable target (e.g. `C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI`) with configs and INIs in the correct locations.

6. **Optional: prebuilt zip for end users**  
   Either:
   - **Option A:** A script that runs the full build + deploy, then zips the deploy folder into a release artifact (e.g. `CoOptUI-EMU-YYYYMMDD.zip`), so users can download, extract, and run (like [E3NextAndMQNextBinary main zip](https://github.com/RekkasGit/E3NextAndMQNextBinary/archive/refs/heads/main.zip) / [E3Next Getting started EMU 32bit](https://github.com/RekkasGit/E3Next/wiki/1)-Getting-started-EMU-32bit)).
   - **Option B:** A checked-in or CI-produced “distribution” folder that already has the correct structure (binaries + configs + INIs + Mono + E3Next + Lua); the zip is that folder. No user build step.

   The prebuilt package must have configs and INIs in the same locations as the deploy layout above so it “just works.”

---

## Constraints

- **CMake 3.30:** Use exactly 3.30 (not 4.x). Put it first on PATH when running any script that invokes CMake or vcpkg.
- **Visual Studio 2022:** Required for MQ C++ and for E3Next C#. Document the workload (Desktop development with C++, MFC).
- **ABI safety:** Never deploy only MQ2CoOptUI.dll into a folder that has different MQ2Main/MQ2Lua versions. Deploy the full build output from one build, or document that the prebuilt zip must be used as a whole.
- **EMU 32-bit:** Primary target is Win32 (eqlib EMU). Document any 64-bit (Live) path separately if needed.
- **This repo:** CoOpt UI Lua, C# CoopHelper, and plugin source live here. The “source” environment can live in a sibling or a configurable path; the script should not assume a fixed path like `C:\MIS\...` unless configurable (e.g. `-SourceRoot`, `-DeployPath`).

---

## Deliverables

1. **Script(s)** to assemble the unified source folder (clone/copy MQ, MQ2Mono, E3Next; symlink or copy MQ2CoOptUI; apply gotchas; bootstrap vcpkg).
2. **Script(s)** to build MQ (with MQ2Mono and MQ2CoOptUI) and E3Next, then deploy to a target folder with the full layout above. The deploy step **must include the latest release of CoOpt UI files** (Lua, resources, Macros defaults, config templates, and optionally CoopHelper.dll)—fetched from the repo’s latest tag or GitHub Release—so the deploy folder contains the current CoOpt UI release, not just the plugin. Config and INI templates from that release go into the correct locations.
3. **Documentation** (e.g. in `docs/plugin/`) that explains:
   - Prerequisites (VS 2022, CMake 3.30, Git, optional .NET for E3Next).
   - How to run the assembly script and the build-and-deploy script.
   - The target folder structure (matching the reference CoOptUI layout).
   - How to produce the prebuilt zip (if implemented).
4. **Default config/INI set** in the repo (e.g. under `config/`, `Macros/sell_config/`, etc.) that the deploy script copies so the deploy folder is preconfigured and matches the E3Next “just works” experience.

---

## Success Criteria

- A developer can run the assembly script (and optionally the build script) and get a deploy folder that:
  - Contains MQ + MQ2Mono + MQ2CoOptUI + E3Next + Mono runtime + **the latest release of CoOpt UI files** (Lua, resources, Macros, config, and optionally CoopHelper).
  - Has config and INIs in the correct locations so launching MacroQuest and running `/plugin MQ2Mono`, `/plugin MQ2CoOptUI`, `/mono e3`, and CoOpt UI works without manual path fixes.
- Optionally, an end user can download a zip, extract it, and use it without building anything, with the same layout and behavior.
- The plugin (MQ2CoOptUI) is built from the same MQ tree as MQ2Mono, so ABI is consistent and “creating the plugin” means editing source in `plugin/MQ2CoOptUI` and rebuilding that solution.

Implement the above in this repository. Prefer PowerShell for scripts; document any assumptions (e.g. Git in PATH, admin rights for symlinks). If a step is blocked by missing plugin source (e.g. MQ2CoOptUI only on a branch), document the branch and still implement the assembly and deploy layout so that when the plugin is present, the rest works.
