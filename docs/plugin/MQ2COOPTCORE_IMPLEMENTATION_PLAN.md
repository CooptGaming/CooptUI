# MQ2CoOptUI — CoOptCore Scanning & Caching Implementation Plan

**Purpose:** Step-by-step plan for adding high-performance scanning, caching, and rules evaluation to the existing `MQ2CoOptUI` C++ plugin. Each phase is self-contained and can be handed to a Cursor agent. Every phase includes validation steps.

**Key decision:** We extend the **existing `MQ2CoOptUI` plugin** (at `plugin/MQ2CoOptUI/`) rather than creating a new plugin. The plugin name, symlink, build system, deploy pipeline, zip verification, `MacroQuest.ini` config (`MQ2CoOptUI=1`), TLO name (`${CoOptUI}`), and Lua module name (`plugin.MQ2CoOptUI`) all stay the same. We add new "core" capabilities (scanning, caching, rules) alongside the existing capabilities (ini, ipc, cursor, window, items, loot).

---

## Build & Deploy System Integration

### Existing System

The project has a build-and-deploy pipeline (`scripts/build-and-deploy.ps1`) that:

1. **Stage 1:** Builds MacroQuest (32-bit Win32 EMU) with `MQ2CoOptUI` and `MQ2Mono` using CMake 3.30
2. **Stage 2:** Builds E3Next (C#)
3. **Stage 3:** Deploys everything (MQ binaries, plugins, E3, CoOpt UI Lua/macros/resources, Mono runtime, configs) to a target folder
4. **Stage 4:** Optionally zips for distribution

The plugin source lives at `plugin/MQ2CoOptUI/` in this repo and is symlinked into the MQ clone at `plugins/MQ2CoOptUI/`. The build produces `MQ2CoOptUI.dll` in the MQ build output. The deploy step copies it alongside all other binaries.

### How Each Phase Uses the Build System

**Plugin-only build + deploy** (fastest — ~10 seconds, use during development):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
.\scripts\build-and-deploy.ps1 `
  -SourceRoot "C:\MIS\MacroquestEnvironments\CompileTest\Source" `
  -DeployPath "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI4" `
  -PluginOnly -UsePrebuildDownload:$false
```

This builds **only** the `MQ2CoOptUI` target (not all of MQ), copies the DLL + Lua/macros/resources to deploy, and skips E3Next, config, mono, README, and zip.

**Quick sync** (copy Lua/macros/resources + DLL without rebuilding):

```powershell
.\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2" -IncludePlugin
```

**Manual cmake + copy** (lowest level, when you want direct control):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" `
  --config Release --target MQ2CoOptUI
Copy-Item "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution\bin\release\plugins\MQ2CoOptUI.dll" `
  -Destination "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2\plugins\" -Force
```

**Full build + deploy** (complete system — use for release or first setup):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
.\scripts\build-and-deploy.ps1 `
  -SourceRoot "C:\MIS\MacroquestEnvironments\CompileTest\Source" `
  -DeployPath "C:\MIS\MacroquestEnvironments\CompileTest" `
  -UsePrebuildDownload:$false -CreateZip
```

**Verify a full zip** (after deploy + zip):

```powershell
.\scripts\list-zip.ps1 -ZipPath "C:\MIS\MacroquestEnvironments\CoOptUI-EMU-20260302.zip"
```

### Phase 0 Prerequisite: Verify Build Chain

Before starting any phase, confirm the existing plugin builds and deploys:

```powershell
# 1. Verify symlink exists
(Get-Item "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\plugins\MQ2CoOptUI").Target
# Should print: C:\MIS\E3NextAndMQNextBinary-main\plugin\MQ2CoOptUI

# 2. Build just the plugin
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" `
  --config Release --target MQ2CoOptUI

# 3. Verify DLL exists
Test-Path "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution\bin\release\plugins\MQ2CoOptUI.dll"

# 4. Copy to deploy test
Copy-Item "...\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2\plugins\" -Force
```

If step 2 fails, the MQ solution needs to be configured first. Run the full build-and-deploy or configure manually per `docs/plugin/dev_setup.md` and `.cursor/rules/mq-plugin-build-gotchas.mdc`.

---

## Current Plugin State (What Already Exists)

```
plugin/MQ2CoOptUI/
├── CMakeLists.txt           ← Working CMake, C++20, sol2/luajit linked
├── MQ2CoOptUI.cpp           ← Plugin lifecycle, TLO (${CoOptUI}), Lua module
├── MQ2CoOptUI.def           ← Export definitions
├── README.md
└── capabilities/
    ├── ini.h / ini.cpp      ← IMPLEMENTED: read, write, readSection, readBatch (Win32 API)
    ├── ipc.h / ipc.cpp      ← IMPLEMENTED: send, receive, peek, clear (in-process channels)
    ├── cursor.h / cursor.cpp ← STUB: hasItem, getItemId, getItemName (TODO in pulse)
    ├── window.h / window.cpp ← STUB: isWindowOpen, click, getText, isMerchantOpen
    ├── items.h / items.cpp   ← STUB: scanInventory(), scanBank() return empty tables
    └── loot.h / loot.cpp     ← STUB: pollEvents() returns empty table
```

The `items.cpp` stubs for `scanInventory()` and `scanBank()` are the functions we need to implement.

### Integration Gaps — RESOLVED

Two integration gaps existed between the plugin and `scan.lua`. Both have been fixed:

**Gap 1 (Module Name) — FIXED:** `scan.lua` `tryCoopUIPlugin()` now tries `require("plugin.MQ2CoOptUI")` first, with `"plugin.CoopUIHelper"` fallback for backward compatibility.

**Gap 2 (Function Path) — FIXED:** `CreateLuaModule()` now adds top-level aliases (`mod["scanInventory"]`, `mod["scanBank"]`, `mod["hasInventoryChanged"]`) alongside the nested `mod["items"]` sub-table, so `scan.lua` can call `coopui.scanInventory()` directly.

**Safety guard:** `scan.lua` now checks `#result > 0` before committing to the plugin path. If the plugin returns an empty table (e.g. stubs not yet replaced), Lua falls through to its TLO-based scan. No items are lost.

**Our job:** Replace the stubs with real implementations.

---

## Phase 1: Config, Logging, & Command Infrastructure

**Goal:** Add structured configuration (CoOptCore.ini), logging with performance timers, and `/cooptui core` subcommands. All subsequent phases depend on this.

### Steps

1. **Create `core/Config.h` / `core/Config.cpp`:**
   - Read `{MQPath}/config/CoOptCore.ini` using the existing `ini.cpp` `GetPrivateProfileString` pattern
   - Keys: `[General]` DebugLevel (0-3), `[Cache]` InventoryReserve (256), BankReserve (512), LootReserve (512), ScanThrottleMs (100), `[Rules]` AutoReloadOnChange (true)
   - Create default INI if missing
   - `Reload()` method for runtime re-read

2. **Create `core/Logger.h` / `core/Logger.cpp`:**
   - `Log(level, fmt, ...)` — `WriteChatf` for level 0 (always), `DebugSpew` for levels 1-3
   - `ScopedTimer` RAII class — logs elapsed ms on destruction (for profiling scans)
   - All messages prefixed `[MQ2CoOptUI]`

3. **Extend `/cooptui` command** in `MQ2CoOptUI.cpp` to support subcommands:
   - `/cooptui status` — print version, debug level, cache sizes/state
   - `/cooptui reload` — reload CoOptCore.ini
   - `/cooptui debug <0-3>` — set debug level at runtime
   - Keep existing `/cooptui ipc send` working

4. **Update `CMakeLists.txt`** to include new `core/` source files.

### Validation

- [ ] Plugin builds with new files (`cmake --build ... --target MQ2CoOptUI`)
- [ ] `/cooptui status` prints version and config values in-game
- [ ] `/cooptui reload` re-reads INI
- [ ] `/cooptui ipc send` still works (no regression)
- [ ] `CoOptCore.ini` created on first load if missing
- [ ] No `char[]` fixed buffers in any new code

### Quick rebuild + deploy command (use for all phases):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
.\scripts\build-and-deploy.ps1 `
  -SourceRoot "C:\MIS\MacroquestEnvironments\CompileTest\Source" `
  -DeployPath "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2" `
  -PluginOnly -UsePrebuildDownload:$false
```

Or manually (without the script):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI
Copy-Item "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution\bin\release\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2\plugins\" -Force
```

---

## Phase 2: Item Data Structures & Cache Manager

**Goal:** Define the C++ item data structure and build the central cache manager singleton with pre-reserved containers. No scanning yet — just the infrastructure.

### Steps

1. **Create `core/ItemData.h`** — Item struct matching the Lua `buildItemFromMQ` output:

   All text fields use `std::string`. No `char[]` anywhere. Fields match what `scan.lua` returns to the UI views.

   ```cpp
   struct CoOptItemData {
       int32_t id = 0;
       int32_t bag = 0;
       int32_t slot = 0;
       std::string source;     // "inv", "bank", "loot"
       std::string name;
       std::string type;
       int32_t value = 0;
       int32_t totalValue = 0;
       int32_t stackSize = 1;
       int32_t weight = 0;
       int32_t icon = 0;
       int32_t tribute = 0;
       bool nodrop = false;
       bool notrade = false;
       bool lore = false;
       bool attuneable = false;
       bool heirloom = false;
       bool collectible = false;
       bool quest = false;
       int32_t augSlots = 0;
       int32_t clicky = 0;
       std::string wornSlots;
       // Pre-evaluated rule results
       bool willSell = false;
       std::string sellReason;
       bool willLoot = false;
       std::string lootReason;
   };
   ```

2. **Create `core/CacheManager.h` / `core/CacheManager.cpp`** — Singleton:
   - Pre-reserve all vectors in `Initialize()` using config values
   - Dirty flags per cache type (inventory, bank, loot)
   - Timing: last scan time, scan count per type
   - `OnPulse()` — throttled check of dirty flags (respects `ScanThrottleMs`)
   - `GetInventory()`, `GetBank()`, `GetLoot()`, `GetSellItems()` — const ref accessors

3. **Wire into plugin lifecycle** in `MQ2CoOptUI.cpp`:
   - `InitializePlugin()` → `CacheManager::Instance().Initialize(config)`
   - `ShutdownPlugin()` → `CacheManager::Instance().Shutdown()`
   - `OnPulse()` → `CacheManager::Instance().OnPulse()` (after existing `cursor::updateFromPulse()`)

4. **Extend `/cooptui status`** to show cache sizes (reserved vs used) and dirty flags.

### Validation

- [ ] Plugin builds and loads cleanly
- [ ] `/cooptui status` shows cache info (all empty but reserved)
- [ ] CacheManager initializes and shuts down without leaks
- [ ] Existing capabilities (ini, ipc, cursor) still work

---

## Phase 3: Inventory Scanner

**Goal:** Replace the stub `items.scanInventory()` with a real native inventory scanner AND fix the two integration gaps so Lua actually discovers and calls the plugin.

### Steps

1. ~~**Fix Integration Gap 1 — Module name in `scan.lua`:**~~ **DONE** — `tryCoopUIPlugin()` now tries `plugin.MQ2CoOptUI` first with `CoopUIHelper` fallback.

2. ~~**Fix Integration Gap 2 — Add top-level aliases in `MQ2CoOptUI.cpp`:**~~ **DONE** — `CreateLuaModule()` adds `mod["scanInventory"]`, `mod["scanBank"]`, `mod["hasInventoryChanged"]` as top-level aliases.

3. **Create `scanners/InventoryScanner.h` / `.cpp`:**
   - Walk `pLocalPC` / `pCharData` inventory slots for bags 1-10 (pack1-pack10)
   - For each bag, iterate container slots using MQ's item access APIs
   - Extract item properties from `CONTENTS*` / `ItemDefinition*` (native access, zero TLO)
   - Populate `std::vector<CoOptItemData>` and store in CacheManager

4. **Implement fingerprint-based change detection:**
   - Build a fast hash from item IDs and stack counts per bag
   - Only rescan when hash changes
   - Store per-bag fingerprints in CacheManager

5. **Replace the stub in `capabilities/items.cpp`:**
   - `scanInventory()` now runs `InventoryScanner::Scan()`, stores results in CacheManager, and converts to sol::table for Lua
   - `hasInventoryChanged()` returns whether fingerprint changed since last scan
   - Keep `scanBank()` as stub for now (Phase 4)

6. **Sync Lua change to deploy test:**

   ```powershell
   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2"
   ```

### Validation

- [ ] `scan.lua` `tryCoopUIPlugin()` tries `plugin.MQ2CoOptUI` first, then falls back to `CoopUIHelper`
- [ ] `require("plugin.MQ2CoOptUI")` in-game returns the module table
- [ ] `mod.scanInventory` exists at top level (alias works)
- [ ] `/cooptui scan inv` forces an inventory scan and prints item count + elapsed ms
- [ ] `/cooptui status` shows inventory cache populated
- [ ] In-game: open inventory window → CoOpt UI Inventory tab shows items (plugin path)
- [ ] Compare: same items appear with and without plugin loaded
- [ ] Benchmark: `/cooptui scan inv` prints time < 5ms (vs Lua ~50-100ms)
- [ ] Scan only triggers when fingerprint changes (verify with `/cooptui debug 2`)
- [ ] Lua deploy synced (scan.lua change is in DeployTest)
- [ ] Full build-and-deploy still works:
  ```powershell
  .\scripts\build-and-deploy.ps1 -SourceRoot "...\Source" -DeployPath "...\CoOptUI2" -SkipE3Next -UsePrebuildDownload:$false
  ```

---

## Phase 4: Bank Scanner

**Goal:** Replace the stub `items.scanBank()` with a real native bank scanner. Includes snapshot persistence.

### Steps

1. **Create `scanners/BankScanner.h` / `.cpp`:**
   - Walk `pLocalPC` bank items for 24 bank bags
   - Handle container bags (with sub-slots) and single-item bank slots
   - Populate `std::vector<CoOptItemData>` with `source = "bank"`

2. **Implement bank snapshot:**
   - When bank window is open → scan and cache
   - When bank window closes → retain last scan in memory
   - Track `m_bankSnapshotTime` for "Historic" display

3. **Replace the stub in `capabilities/items.cpp`:**
   - `scanBank()` now runs `BankScanner::Scan()` and converts to sol::table

4. **The Lua integration is automatic** (same as inventory — `scan.lua:341-369` already has the plugin hook).

### Validation

- [ ] `/cooptui scan bank` forces a bank scan (when bank is open)
- [ ] Bank data persists in memory after bank window closes
- [ ] In-game: open bank → CoOpt UI Bank tab shows items
- [ ] Compare: same items with and without plugin
- [ ] Full deploy works and zip verifies

---

## Phase 5: Rules Engine (Sell & Loot)

**Goal:** Implement the sell and loot rules engine in C++ with native INI reading and O(1) lookups.

### Steps

1. **Create `rules/RulesEngine.h` / `.cpp`:**
   - `LoadSellConfig(mqPath)` — reads all sell_config, shared_config INI files using `GetPrivateProfileString` (Win32 API, same pattern as `capabilities/ini.cpp`)
   - `LoadLootConfig(mqPath)` — reads all loot_config INI files
   - Handle chunked INI values (read key, key2, key3... and concatenate)
   - Parse slash-delimited lists into `std::unordered_set<std::string>` (exact match) and `std::vector<std::string>` (contains match)

2. **Mirror exact evaluation order** from `rules.lua`:
   - `WillItemBeSold()` — Steps 0a through 19, same priority as `rules.lua:271-334`
   - `ShouldItemBeLooted()` — same order as `rules.lua:423-486`
   - Epic class filtering via `epic_classes.ini` and per-class `epic_items_*.ini`

3. **Add `/cooptui` subcommands:**
   - `/cooptui reloadrules` — reload all INI files
   - `/cooptui eval sell <itemname>` — print sell decision
   - `/cooptui eval loot <itemname>` — print loot decision

4. **Integrate with CacheManager:**
   - After inventory scan, auto-evaluate sell rules for all items
   - Store `willSell`/`sellReason` in each `CoOptItemData`

### Validation

- [ ] `/cooptui reloadrules` reads INIs and prints counts
- [ ] `/cooptui eval sell <name>` matches Lua `willItemBeSold()` result exactly
- [ ] `/cooptui eval loot <name>` matches Lua `shouldItemBeLooted()` result exactly
- [ ] 100% parity test: for every inventory item, C++ result == Lua result
- [ ] Benchmark: rules load < 2ms, 100 evaluations < 0.1ms

---

## Phase 6: Loot Scanner (Critical Path — Highest Priority)

**Goal:** Implement native corpse scanning with pre-evaluated loot rules and lore duplicate checking. This eliminates the #1 performance bottleneck identified in the audit.

### Steps

1. **Create `scanners/LootScanner.h` / `.cpp`:**
   - Walk loot window items via MQ's loot APIs
   - Extract all properties Lua needs
   - Pre-evaluate `ShouldItemBeLooted()` during scan
   - Native lore duplicate check using `FindItemByName()` in C++ (no TLO)
   - Pre-reserve output vector to 512

2. **Add `scanLootItems()` to `capabilities/items.cpp`** (or extend `capabilities/loot.cpp`):
   - Returns pre-evaluated table with `willLoot` and `lootReason` per item

3. **Add plugin hook in `scan.lua:scanLootItems()`** — this is the ONE Lua file change needed now:

   ```lua
   -- At the top of scanLootItems(), before the existing loop:
   local coopui = tryCoopUIPlugin()
   if coopui and coopui.scanLootItems then
       local ok, result = pcall(coopui.scanLootItems)
       if ok and result and type(result) == "table" then
           for _, row in ipairs(result) do
               if type(row) == "table" then table.insert(lootItems, row) end
           end
           env.invalidateSortCache("loot")
           return
       end
   end
   ```

4. **Scale protection:**
   - 300+ items: auto-resize with warning log
   - All operations O(1) or O(n)
   - Target: < 5ms for 300 items

### Validation

- [ ] `/cooptui scan loot` works when loot window is open
- [ ] Lore duplicates detected correctly
- [ ] Rule evaluation matches Lua 100%
- [ ] **Stress test:** 100+ item corpse scans < 5ms
- [ ] Lua integration: `scanLootItems()` returns pre-evaluated table
- [ ] No game freeze during loot (before: multi-second freeze)
- [ ] Deploy + sync to test environment works

---

## Phase 7: Sell Scanner & Cache Writer

**Goal:** Native sell item scanning and sell cache INI writing.

### Steps

1. **Create `scanners/SellScanner.h` / `.cpp`:**
   - Uses cached inventory from CacheManager
   - Applies sell rules to generate sell list (pure in-memory, no TLO)

2. **Create `storage/SellCacheWriter.h` / `.cpp`:**
   - Write `sell_cache.ini` using Win32 `WritePrivateProfileString`
   - Handle chunking: each key <= 1700 chars (matches Lua `SELL_CACHE_CHUNK_LEN`)

3. **Add `scanSellItems()` to `capabilities/items.cpp`**

4. **Add plugin hook in `scan.lua:scanSellItems()`** — same pattern as loot hook.

### Validation

- [ ] `/cooptui scan sell` produces correct sell list
- [ ] sell_cache.ini written with correct chunking
- [ ] 100% match with Lua sell results
- [ ] Deploy works with new capability

---

## Phase 8: Event-Driven Invalidation

**Goal:** Replace Lua's 600ms fingerprint polling with native MQ event hooks.

### Steps

1. **Add MQ event hooks** in `MQ2CoOptUI.cpp`:
   - `OnBeginZone()` → `CacheManager::InvalidateAll()`
   - `OnEndZone()` → `CacheManager::InvalidateInventory()`

2. **Detect inventory changes** in `OnPulse()`:
   - Lightweight hash of inventory item IDs (cheaper than full fingerprint)
   - Only invalidate if hash changes

3. **Detect window state** in `OnPulse()`:
   - Monitor bank/merchant/loot window visibility
   - Auto-scan on window open; snapshot on close

4. **Lua version counter:**
   - Each cache type has a version number
   - Lua polls the version; when it changes, Lua refreshes its view

### Validation

- [ ] Scans trigger only when items change
- [ ] Bank auto-scans on open
- [ ] Zone change invalidates caches
- [ ] `/cooptui status` shows scan counts over 60s idle = 0 unnecessary scans

---

## Phase 9: TLO Enhancements

**Goal:** Extend the existing `${CoOptUI}` TLO with cache/rules access for macros.

### Steps

1. **Add members to `MQ2CoOptUIType`** in `MQ2CoOptUI.cpp`:
   - `${CoOptUI.Inventory.Count}` — cached item count
   - `${CoOptUI.Loot.Count}` — loot item count
   - `${CoOptUI.Rules.Evaluate[sell,itemname]}` — sell decision
   - `${CoOptUI.Status}` — "Ready" / "Scanning" / "Loading"
   - Keep existing `Version`, `APIVersion`, `MQCommit`, `Debug` members

### Validation

- [ ] `/echo ${CoOptUI.Inventory.Count}` prints correct count
- [ ] `/echo ${CoOptUI.Rules.Evaluate[sell,Bone Chips]}` prints decision
- [ ] Existing TLO members still work (no regression)

---

## Phase 10: Lua Integration Patches (Final Pass)

**Goal:** Verify all plugin hooks are in place and add any remaining ones. The main integration gap fixes (`tryCoopUIPlugin()` name and top-level aliases) were done in Phase 3.

### Steps

1. **Verify `tryCoopUIPlugin()`** updated in Phase 3 — should already try `plugin.MQ2CoOptUI` first.

2. **Verify `scanLootItems()` hook** added in Phase 6 — plugin fallback should work.

3. **Verify `scanSellItems()` hook** added in Phase 7 — plugin fallback should work.

4. **Add `scanLootItems` top-level alias** in `CreateLuaModule()` if not done in Phase 6:

   ```cpp
   mod["scanLootItems"] = loot_table["scanLootItems"];
   ```

5. **Add `scanSellItems` top-level alias** in `CreateLuaModule()` if not done in Phase 7:

   ```cpp
   mod["scanSellItems"] = items_table["scanSellItems"];
   ```

6. **Full fallback test:** Unload MQ2CoOptUI, verify every scan works via pure Lua.

7. **Reload test:** Load MQ2CoOptUI mid-session, verify all scans switch to plugin path.

8. **Deploy all Lua changes:**

   ```powershell
   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2"
   ```

### Validation

- [ ] With plugin: all 4 scans (inv, bank, loot, sell) use plugin path
- [ ] Without plugin: all scans fall back to Lua
- [ ] All views show same data with/without plugin
- [ ] No errors during scan transitions
- [ ] Mid-session load/unload works cleanly
- [ ] `sync-to-deploytest.ps1` copies updated Lua files correctly

---

## Phase 11: Performance Metrics & Stress Testing

**Goal:** Built-in performance monitoring and stress tests.

### Steps

1. **Add perf counters** to CacheManager (scan count, avg/max time per type)
2. **`/cooptui perf`** — print all counters; `/cooptui perf reset`
3. **`/cooptui stress loot <count>`** — simulate N-item loot scan

### Benchmark Targets

| Operation | Target | Fail |
|---|---|---|
| Inventory scan (100 items) | < 2ms | > 10ms |
| Bank scan (240 items) | < 5ms | > 20ms |
| Loot scan (300 items) | < 5ms | > 20ms |
| Sell evaluation (100 items) | < 0.5ms | > 5ms |
| Rules load (all INIs) | < 2ms | > 10ms |

### Validation

- [ ] `/cooptui perf` shows counters
- [ ] `/cooptui stress loot 300` < 10ms
- [ ] No memory growth after 1000 scans
- [ ] Stable over 10-minute play session

---

## Phase 12: Deploy, Sync, & Zip Verification

**Goal:** Ensure the enhanced plugin works end-to-end in the full deploy pipeline.

### Steps

1. **Full build-and-deploy test:**

   ```powershell
   $env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
   .\scripts\build-and-deploy.ps1 `
     -SourceRoot "C:\MIS\MacroquestEnvironments\CompileTest\Source" `
     -DeployPath "C:\MIS\MacroquestEnvironments\CompileTest" `
     -UsePrebuildDownload:$false -CreateZip
   ```

2. **Verify zip contents:**

   ```powershell
   .\scripts\list-zip.ps1 -ZipPath "C:\MIS\MacroquestEnvironments\CoOptUI-EMU-20260302.zip"
   ```

   Must contain: `plugins/MQ2CoOptUI.dll`, and all standard entries.

3. **Sync with plugin DLL:**

   ```powershell
   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2" -IncludePlugin
   ```

   The `-IncludePlugin` flag copies `MQ2CoOptUI.dll` from the build output alongside Lua/macros/resources.

4. **Add `config/CoOptCore.ini` default** to config_templates/ if not already done.

5. **End-to-end test:**
   - Launch from deploy folder
   - `/plugin MQ2CoOptUI` confirms load message
   - `/cooptui status` shows all caches and config
   - Open inventory/bank/merchant/loot → verify all views work with plugin
   - Unload plugin → verify Lua fallback works

### Validation

- [ ] Full build-and-deploy succeeds
- [ ] `list-zip.ps1` passes all checks
- [ ] In-game end-to-end works from fresh deploy
- [ ] Plugin load/unload cycle works cleanly
- [ ] Lua fallback verified after unload

---

## File Structure (Final State)

```
plugin/MQ2CoOptUI/
├── CMakeLists.txt                       ← Updated with new source files
├── MQ2CoOptUI.cpp                       ← Extended: commands, cache manager wiring, events
├── MQ2CoOptUI.def
├── README.md
├── capabilities/                        ← EXISTING (preserved)
│   ├── ini.h / ini.cpp                  ← IMPLEMENTED (no changes)
│   ├── ipc.h / ipc.cpp                  ← IMPLEMENTED (no changes)
│   ├── cursor.h / cursor.cpp            ← STUB → will be completed
│   ├── window.h / window.cpp            ← STUB → will be completed
│   ├── items.h / items.cpp              ← STUB → REPLACED with real scanners (Phase 3-4)
│   └── loot.h / loot.cpp               ← STUB → EXTENDED with scanLootItems (Phase 6)
├── core/                                ← NEW (Phase 1-2)
│   ├── Config.h / Config.cpp            ← INI configuration reader
│   ├── Logger.h / Logger.cpp            ← Structured logging + ScopedTimer
│   ├── ItemData.h                       ← CoOptItemData struct
│   └── CacheManager.h / CacheManager.cpp ← Central cache singleton
├── scanners/                            ← NEW (Phase 3-7)
│   ├── InventoryScanner.h / .cpp        ← Native inventory scanning
│   ├── BankScanner.h / .cpp             ← Native bank scanning + snapshot
│   ├── LootScanner.h / .cpp             ← Native corpse scanning + lore check
│   └── SellScanner.h / .cpp             ← Sell list evaluation
├── rules/                               ← NEW (Phase 5)
│   └── RulesEngine.h / .cpp             ← Sell & loot rule evaluation
└── storage/                             ← NEW (Phase 7)
    └── SellCacheWriter.h / .cpp         ← Sell cache INI writer
```

---

## Lua Files Modified

| File | Change | Phase | Impact |
|---|---|---|---|
| `lua/itemui/services/scan.lua` | Fix `tryCoopUIPlugin()` — try `plugin.MQ2CoOptUI` first | **3** | Fixes module name mismatch |
| `lua/itemui/services/scan.lua` | Add plugin hook in `scanLootItems()` | 6 | Enables C++ loot scan |
| `lua/itemui/services/scan.lua` | Add plugin hook in `scanSellItems()` | 7 | Enables C++ sell scan |

The inventory and bank hooks **already exist** in `scan.lua:108-147` and `scan.lua:341-369` — the code paths already call `coopui.scanInventory()` and `coopui.scanBank()`. With the top-level aliases added in `CreateLuaModule()` (Phase 3), these existing hooks will "just work" once the stubs return real data.

### C++ Files Modified (Existing)

| File | Change | Phase | Impact |
|---|---|---|---|
| `plugin/MQ2CoOptUI/MQ2CoOptUI.cpp` | Top-level aliases in `CreateLuaModule()` | **3** | Fixes function path mismatch |
| `plugin/MQ2CoOptUI/MQ2CoOptUI.cpp` | Wire CacheManager, extend commands, add event hooks | 2, 8, 9 | Core infra |
| `plugin/MQ2CoOptUI/capabilities/items.cpp` | Replace stubs with real scanner calls | 3, 4, 7 | Real scanning |
| `plugin/MQ2CoOptUI/capabilities/loot.cpp` | Add `scanLootItems()` | 6 | Real loot scanning |

---

## Phase Dependencies

```
[Prerequisite: Verify existing build chain works]
        │
Phase 1 (Config/Logging) ────► Phase 2 (Data/Cache)
                                      │
                    ┌─────────────────┤
                    ▼                 ▼
          Phase 3 (Inv Scanner)   Phase 5 (Rules Engine)
                    │                 │
                    ▼                 │
          Phase 4 (Bank Scanner)     │
                    │                 │
                    ▼                 ▼
          Phase 6 (Loot Scanner) ◄───┘
                    │
                    ▼
          Phase 7 (Sell Scanner)
                    │
                    ▼
          Phase 8 (Event Hooks)
                    │
                    ▼
          Phase 9 (TLO Enhancements)
                    │
                    ▼
          Phase 10 (Lua Patches)
                    │
                    ▼
          Phase 11 (Stress Test)
                    │
                    ▼
          Phase 12 (Deploy/Zip Verify)
```

Phases 3-4 can run in parallel with Phase 5.
Phase 6 requires Phases 3+4+5 complete.
Phase 12 can start after the prerequisite (for deploy-only tests).

---

## Handoff Instructions

When handing a phase to a Cursor agent, include:

1. **"Read `docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md` first"**
2. **The specific phase number:** "Implement Phase N"
3. **Build environment context:**
   - Plugin source: `plugin/MQ2CoOptUI/` in this repo
   - Symlink: `CompileTest\Source\macroquest\plugins\MQ2CoOptUI` → this repo's `plugin/MQ2CoOptUI`
   - Quick rebuild: `cmake --build ...\build\solution --config Release --target MQ2CoOptUI`
   - Deploy: copy DLL to `DeployTest\CoOptUI2\plugins\`
4. **Rules:** Follow `.cursor/rules/mq-plugin-build-gotchas.mdc` and `.cursor/rules/plugin-build-cmake.mdc`
5. **Non-negotiable:** Zero fixed-size `char[]` buffers in new code, `std::string` everywhere, RAII, C++17 minimum (plugin uses C++20 currently)

### Example handoff prompt:

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md, then implement Phase 3
(Inventory Scanner).

Context: We are adding high-performance native scanning to the existing MQ2CoOptUI
plugin at plugin/MQ2CoOptUI/. The plugin already has stub scanInventory()/scanBank()
in capabilities/items.cpp that return empty tables. Replace the scanInventory() stub
with a real native scanner that walks pLocalPC inventory and returns a populated
sol::table. The Lua side (scan.lua) already calls this function via tryCoopUIPlugin()
— when we return real data, Lua will automatically use it.

Build: cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI
Deploy: Copy-Item "...\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2\plugins\" -Force

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Zero char[] buffers. Use std::string.
Verify all validation checkboxes in the plan before declaring complete.
```

---

## Build-and-Deploy Script: Improvements Made

The following improvements have been implemented in the build/deploy scripts:

1. **`-PluginOnly` switch (build-and-deploy.ps1):** Builds only `--target MQ2CoOptUI` (not all of MQ), copies just the DLL + Lua/macros/resources. Skips E3Next, reference copy, config, mono, README, and zip. Enables ~10-second iteration cycles during plugin development.

   ```powershell
   .\scripts\build-and-deploy.ps1 -SourceRoot "...\Source" -DeployPath "...\CoOptUI2" -PluginOnly -UsePrebuildDownload:$false
   ```

2. **`-IncludePlugin` switch (sync-to-deploytest.ps1):** Copies `MQ2CoOptUI.dll` from build output alongside the standard Lua/macros/resources sync. No rebuild — just file copy.

   ```powershell
   .\scripts\sync-to-deploytest.ps1 -Target "...\CoOptUI2" -IncludePlugin
   ```

3. **Stage 3e always runs in PluginOnly mode:** Lua/macros/resources are deployed even in plugin-only mode, ensuring Lua hook changes (from Phases 6/7/10) reach the test environment.

4. **Zip verification unchanged:** `list-zip.ps1` checks for `plugins/MQ2CoOptUI.dll` (name unchanged).

### Future improvements (when implementing phases):

- **Pre-flight: check CoOptCore.ini template exists** alongside existing vcpkg/symlink/CMake checks.
- **Optionally check `config/CoOptCore.ini` in zip verification.**

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| MQ API changes | Pin to specific MQ commit; use eqlib EMU branch |
| ABI mismatch | Always use full build output from build-and-deploy (gotcha #20) |
| Plugin crashes game | All scanner methods wrapped in try/catch; graceful degrade to empty table |
| Lua fallback broken | Every Lua patch preserves 100% original behavior when plugin absent |
| Large corpse overflow | Pre-reserve 512; auto-resize with warning; tested to 300+ |
| INI format changes | Versioned config; backward-compatible readers |
| Build env not set up | Prerequisite step validates entire chain before Phase 1 |
| Name confusion | We keep `MQ2CoOptUI` everywhere — no rename, no new plugin |
