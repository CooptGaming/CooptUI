# CoOpt UI Developer Documentation

Start with [docs/COOPUI_OVERVIEW.md](COOPUI_OVERVIEW.md) for product scope and where to look. Historical phase and design docs are in `lua/itemui/docs/archive/`.

## Architecture Overview

### Entry Points

- **ItemUI**: `lua/itemui/init.lua` — loaded via `/lua run itemui`
- **ScriptTracker**: `lua/scripttracker/init.lua` — loaded via `/lua run scripttracker`
- **Auto Sell**: `Macros/sell.mac` — triggered via `/dosell` or `/macro sell`
- **Auto Loot**: `Macros/loot.mac` — triggered via `/doloot` or `/macro loot`

### Main Loop

`init.lua` sets up the MQ2 main loop:
1. Registers `/itemui`, `/inv`, `/inventoryui` bind commands
2. Initializes all modules via `init(deps)` pattern
3. Runs `mq.imgui.init('ItemUI', renderUI)` for the ImGui render callback
4. Main loop: checks for inventory fingerprint changes, flushes debounced saves, handles macro bridge status

### Module Map (36 Lua files)

#### ItemUI Core (`lua/itemui/`)

| File | Purpose |
|------|---------|
| `init.lua` | Entry point, main loop, command handler, module initialization |
| `config.lua` | INI read/write, list parsing, path helpers, chunked list I/O |
| `config_cache.lua` | Cached sell/loot config from INI, list add/remove APIs |
| `context.lua` | Context registry pattern (60-upvalue solution) |
| `rules.lua` | Sell and loot rule evaluation, epic item handling |
| `storage.lua` | Per-character persistence (bank snapshots, char folders) |

#### Core (`lua/itemui/core/`)

| File | Purpose |
|------|---------|
| `cache.lua` | Multi-tier caching with granular invalidation |
| `events.lua` | Event bus for decoupled module communication |
| `state.lua` | Unified state management |

#### Views (`lua/itemui/views/`)

| File | Purpose |
|------|---------|
| `inventory.lua` | Inventory table (gameplay view) |
| `sell.lua` | Sell view (merchant open) with keep/junk buttons |
| `bank.lua` | Bank slide-out panel (live + historic) |
| `loot.lua` | Live corpse loot evaluation |
| `config.lua` | Config window (3 tabs: General & Sell, Loot Rules, Item Lists) |
| `augments.lua` | Augmentation item display |

#### Services (`lua/itemui/services/`)

| File | Purpose |
|------|---------|
| `scan.lua` | Inventory scanning with fingerprinting and incremental updates |
| `filter_service.lua` | Unified filter system for item list management |
| `macro_bridge.lua` | `/dosell` and `/doloot` macro integration |
| `sell_status.lua` | Sell status computation and caching |
| `item_ops.lua` | Item operations (move, sell, bank transfer) |

#### Utils (`lua/itemui/utils/`)

| File | Purpose |
|------|---------|
| `layout.lua` | Window size, column visibility, sort persistence (INI-backed) |
| `theme.lua` | Color palette, button styling, text coloring |
| `columns.lua` | Column visibility, display text, autofit behavior |
| `column_config.lua` | Column configuration definitions |
| `sort.lua` | Sort value helpers and comparator builder |
| `icons.lua` | Icon constants and helpers |
| `item_helpers.lua` | Item data extraction and formatting |
| `item_tooltip.lua` | Rich item detail tooltip rendering |
| `window_state.lua` | Window open/close state management |
| `file_safe.lua` | Safe file I/O utilities |

#### Components (`lua/itemui/components/`)

| File | Purpose |
|------|---------|
| `searchbar.lua` | Search input component |
| `filters.lua` | Filter UI components |
| `progressbar.lua` | Progress bar variants (timed, indeterminate) |
| `character_stats.lua` | Character stat display (weight, slots, etc.) |

#### ScriptTracker (`lua/scripttracker/`)

| File | Purpose |
|------|---------|
| `init.lua` | ScriptTracker entry point, AA script progress tracking |

#### CoOpt UI Shared Core (`lua/coopui/`)

| File | Purpose |
|------|---------|
| `version.lua` | Single source of truth for all component versions |
| `core/events.lua` | Shared event bus |
| `core/cache.lua` | Shared caching infrastructure |
| `core/state.lua` | Shared state management |
| `utils/theme.lua` | Shared theme/color definitions |

#### Shared Utilities

| File | Purpose |
|------|---------|
| `lua/mq/ItemUtils.lua` | `formatValue()`, `formatWeight()` used across components |

#### Dev/Test Files (not shipped in releases)

| File | Purpose |
|------|---------|
| `upvalue_check.lua` | Upvalue count checker for build validation |

---

## Key Patterns

### Context Registry (60-Upvalue Solution)

Lua closures have a hard limit of 60 upvalues. With 30+ modules needing access to shared state, closing over individual variables would exceed this limit.

**Solution** (`context.lua`):
```lua
local refs = {}       -- single table holds ALL shared references
context.init(refs)    -- called once from init.lua

-- build() returns a metatable proxy:
function M.build()
    return setmetatable({}, { __index = refs })
end
```

Views call `context.build()` to get a proxy table. Accessing `ctx.scanInventory` routes through the metatable to `refs.scanInventory`. The closure only captures one upvalue (`refs`), not 60+.

### init(deps) Dependency Injection

Every module follows the same pattern:

```lua
local M = {}
local deps

function M.init(d)
    deps = d  -- store injected dependencies
end

-- Module functions use deps.xxx for external references
function M.doSomething()
    deps.scanInventory()
end

return M
```

`init.lua` calls each module's `init()` with the specific dependencies it needs. This avoids global state and makes dependencies explicit.

### Event Bus

`core/events.lua` provides pub/sub for decoupled communication:

```lua
events.emit(events.EVENTS.CONFIG_SELL_CHANGED)
events.on(events.EVENTS.CONFIG_SELL_CHANGED, function() ... end)
```

Key events: `CONFIG_SELL_CHANGED`, `CONFIG_LOOT_CHANGED`, `INVENTORY_CHANGED`, `BANK_CHANGED`.

### Config System (INI Chunking)

MQ macro variables have a 2048-character limit. `config.lua` handles this transparently:

- **Read**: `readListValue()` reads `key`, `key2`, `key3`, ... and concatenates with `/`
- **Write**: `writeListValue()` splits at `/` boundaries when over 2000 chars
- **Safety limit**: Max 20 chunks per key (prevents infinite loops from corrupt data)

### Scan System (Fingerprinting)

`services/scan.lua` uses per-bag fingerprinting to avoid rescanning unchanged bags:

1. Each bag gets a fingerprint (hash of item IDs + counts)
2. On scan, only bags with changed fingerprints are rescanned
3. Scanning is incremental: 2 bags per frame to avoid blocking the UI thread

### State Tables (200-Local Solution)

Lua has a 200-local limit per scope. Instead of 200 individual `local` variables, state is consolidated into tables:

- `uiState` — window visibility, setup mode, config open, etc.
- `perfCache` — performance metrics and timing
- `sortState` — sort column and direction per view
- `filterState` — active filter criteria

---

## Build & Release

### Prerequisites

Everything the from-source build needs is third-party and separately licensed, so **none of it
can be shipped with CoOpt UI** — it has to be installed from the vendor. All of it is free.

Check your machine before you start:

```powershell
.\Build-Smart.ps1 -CheckPrereqs
```

That reports what is missing, why it is needed and where to download it, then exits `0` (ready)
or `1` (something missing). It does not need `-OutputDir`, and it only checks what the selected
`-Target` actually uses. Add `-Target FullBundle -Release` to check the full release toolchain.

| Tool | Needed for | Notes |
|------|-----------|-------|
| **Git** | Stage 1 clones MacroQuest, MQ2Mono, MQ2Mono-Framework32 and E3Next | [git-scm.com/download/win](https://git-scm.com/download/win) |
| **CMake 3.x — *not* 4.x** | Configuring MacroQuest and its vcpkg dependencies | **This is the one that catches people.** CMake 4.x rejects the `cmake_minimum_required(<3.5)` still used by several vcpkg portfiles, so the dependency build cannot configure. Get 3.30.x from [cmake.org/download](https://cmake.org/download/) (under "Older Releases") or [the v3.30.5 release](https://github.com/Kitware/CMake/releases/tag/v3.30.5). The ZIP needs no install — extract it and pass `-CMakePath "…\bin\cmake.exe"`. A 4.x CMake elsewhere on PATH is fine; `-CMakePath` wins. |
| **Visual Studio 2022** with *Desktop development with C++* | MacroQuest, the MQ2CoOptUI plugin, all vcpkg ports | Community edition is enough: [visualstudio.microsoft.com/vs/community](https://visualstudio.microsoft.com/vs/community/). **VS 2026 / VS 18 alone is not sufficient** — see the toolset pin below. |
| **MSVC toolset `14.44.35207`** | The ABI pin | The build forces this exact toolset so vcpkg's port builds and the final link use the **same STL**. A newer toolset (e.g. 14.50 from VS 18) resolves symbols absent from the older `libcpmt.lib`, and the build dies at link time with `LNK1120` — long after the real cause, and looking like a source bug. Install via **Visual Studio Installer → Modify → Individual components → "MSVC v143 - VS 2022 C++ x64/x86 build tools (v14.44)"**. It installs alongside existing toolsets. |
| **.NET SDK** | E3Next and MQ2Mono (Stage 2b) | [dotnet.microsoft.com/download](https://dotnet.microsoft.com/download). The C++ workload does **not** include this. |
| **Python 3** | Release manifests (`patcher/generate_manifest.py`) and the PyInstaller patcher exe | [python.org/downloads/windows](https://www.python.org/downloads/windows/) — tick "Add python.exe to PATH". |
| **GitHub CLI (`gh`)**, authenticated | `-Release` only: tags, creates the release, uploads assets | [cli.github.com](https://cli.github.com/), then `gh auth login`. |
| *Developer Mode* (advisory) | Stage 1 symlinks `plugin\MQ2CoOptUI` into the MacroQuest clone | Settings → System → For developers. Without it the build falls back to a junction, which usually works — hence advisory, not blocking. |
| *.NET Framework 4.8 Dev Pack* (advisory) | Only `E3NextSysTray` | Without it that one project fails with `MSB3103`. **This is expected and tolerated** — `E3.dll` still builds and packages. |

`-Target CoOptOnly` needs **none** of the above: it only copies Lua/macros and zips them.

`-SkipPrereqCheck` runs the checks without stopping on them. Escape hatch only — the build will
almost certainly fail later.

### Build Script

`Build-Smart.ps1` (repo root) is the single entry point. It self-clones MacroQuest, MQ2Mono and
E3Next into `<OutputDir>\.mq-source`, so **keep `-OutputDir` outside the repo folder.**

```powershell
.\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy"                     # full EMU bundle
.\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy" -Target CoOptOnly   # Lua/macros only (fast)
.\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy" -Force              # ignore the stage cache
```

Stages: **0** prerequisites → **1** source environment → **2** MacroQuest + plugin → **2b** E3Next
→ **2c** patcher exe → **3** CoOpt source check → **4** assemble/zip → **5** release.

Incremental rebuilds hash each stage's inputs and skip unchanged work (`.build_state.json` in
`OutputDir`). If you change a shipped file and the build says "Changed: none (all cached)", the
stage hash is missing that file — see `Get-CoOptUISourceHash`.

The CoOpt payload is: `lua/itemui/`, `lua/scripttracker/`, `lua/coopui/`, `lua/mq/ItemUtils.lua`,
`lua/coopt_launcher.lua`, `uifiles/coopt/` (the native skin), `Macros/sell.mac`, `Macros/loot.mac`,
`Macros/shared_config/*.mac`, `config_templates/`, `resources/UIFiles/Default/`, `DEPLOY.md`,
`CHANGELOG.md`. Dev files excluded: `lua/itemui/docs/`, `upvalue_check.lua`.

`build/build.py` is an older Python build path, kept for reference — **not** current.

### Release Workflow

Releases are cut **locally**, not by CI:

```powershell
.\Build-Smart.ps1 -OutputDir "C:\MQ\Deploy" -Release
```

That regenerates manifests, commits, tags, pushes, and creates a **draft** GitHub release with the
EMU bundle, patcher zip, patcher exe and plugin DLL. Publish it with:

```powershell
gh release edit vX.Y.Z --title "CoOpt UI vX.Y.Z" --notes-file notes.md --draft=false --latest
```

`.github/workflows/release.yml` is **manual dispatch only** and builds *only* the patcher exe. It
is deliberately not tag-triggered: GitHub-hosted runners ship CMake 4.x and cannot build the
bundle. See the comment at the top of that file, and `docs/RELEASE_AND_DEPLOYMENT.md`.

> **Regenerate manifests only at release.** Clients fetch `release_manifest.json` from raw
> `master`, so a manifest regenerated mid-development advertises hashes for files that are not
> published yet.

### Release checklist (see .cursor/rules/release.mdc)

1. Update `lua/coopui/version.lua` (PACKAGE, ITEMUI).
2. Optionally update `CHANGELOG.md`.
3. Run `.\scripts\build-release.ps1 -Version "X.Y.Z-alpha"` to verify.
4. Commit, push, then `git tag vX.Y.Z-alpha && git push origin vX.Y.Z-alpha`.
5. Publish the draft release on GitHub.

### Versioning

Single source of truth: `lua/coopui/version.lua`

```lua
return {
    PACKAGE = "0.2.0-alpha",
    ITEMUI = "0.2.0-alpha",
    SCRIPTTRACKER = "0.1.0-alpha",
    SELL_MAC = "3.0",
    LOOT_MAC = "4.0",
}
```

---

## Testing

### Upvalue Check

`lua/itemui/upvalue_check.lua` — validates that `context.build()` stays under 60 upvalues. Run to ensure new code doesn't exceed Lua limits.

### Manual Testing

See `lua/itemui/docs/archive/PHASE7_TESTING_GUIDE.md` for a comprehensive functional test suite covering:
- UI load, window display, inventory rendering
- Sort persistence, column width saving
- Bank panel, sell view, config window
- Macro bridge integration

---

## Internal Dev Docs Index

Historical phase and design docs have been moved to `lua/itemui/docs/archive/`. For current scope and roadmap, see [docs/COOPUI_OVERVIEW.md](COOPUI_OVERVIEW.md) and [lua/itemui/docs/PROJECT_ROADMAP.md](lua/itemui/docs/PROJECT_ROADMAP.md).

---

## Contributing

### Branch Workflow

1. Create a feature branch from `master`: `feature/my-feature`
2. Make changes, test in-game
3. Open a PR to `master`

### Guidelines

- **init.lua size**: Keep under 1300 lines. Extract new modules rather than adding to init.lua.
- **New modules**: Follow the `init(deps)` pattern. Register dependencies explicitly.
- **Upvalue limit**: Run `upvalue_check.lua` after changes. If `context.build()` approaches 60 upvalues, consolidate into tables.
- **200-local limit**: Use state tables (`uiState`, etc.) instead of loose local variables.
- **Config changes**: Add new INI keys to both `config_cache.lua` (for ItemUI) and the corresponding macro (for sell.mac/loot.mac).
- **Testing**: Manual smoke test in-game for UI and sell/loot logic. Run `upvalue_check.lua` after changes that touch context.