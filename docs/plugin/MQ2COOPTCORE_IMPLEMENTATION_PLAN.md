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
.\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" -IncludePlugin
```

**Manual cmake + copy** (lowest level, when you want direct control):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" `
  --config Release --target MQ2CoOptUI
Copy-Item "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution\bin\release\plugins\MQ2CoOptUI.dll" `
  -Destination "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force
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
Copy-Item "...\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force
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
├── core/
│   ├── Config.h / Config.cpp      ← CoOptCore.ini (Phase 1)
│   ├── Logger.h / Logger.cpp     ← Log, ScopedTimer (Phase 1)
│   ├── ItemData.h                ← CoOptItemData struct (Phase 2)
│   └── CacheManager.h /.cpp       ← Singleton cache, throttle, dirty flags (Phase 2)
└── capabilities/
    ├── ini.h / ini.cpp      ← IMPLEMENTED: read, write, readSection, readBatch (Win32 API)
    ├── ipc.h / ipc.cpp      ← IMPLEMENTED: send, receive, peek, clear (in-process channels); Phase 9 adds receiveAll
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
  -DeployPath "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" `
  -PluginOnly -UsePrebuildDownload:$false
```

Or manually (without the script):

```powershell
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI
Copy-Item "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution\bin\release\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force
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

- [x] Plugin builds and loads cleanly
- [x] `/cooptui status` shows cache info (all empty but reserved)
- [x] CacheManager initializes and shuts down without leaks
- [x] Existing capabilities (ini, ipc, cursor) still work

**Phase 2 complete:** `core/ItemData.h`, `core/CacheManager.h/.cpp` added; lifecycle wired; status shows cache state (inv/bank/loot counts and reserves, dirty flags, sell count).

---

## Phase 3: Inventory Scanner

**Goal:** Replace the stub `items.scanInventory()` with a real native inventory scanner AND fix the two integration gaps so Lua actually discovers and calls the plugin.

### Steps

1. ~~**Fix Integration Gap 1 — Module name in `scan.lua`:**~~ **DONE** — `tryCoopUIPlugin()` now tries `plugin.MQ2CoOptUI` first with `CoopUIHelper` fallback.

2. ~~**Fix Integration Gap 2 — Add top-level aliases in `MQ2CoOptUI.cpp`:**~~ **DONE** — `CreateLuaModule()` adds `mod["scanInventory"]`, `mod["scanBank"]`, `mod["hasInventoryChanged"]` as top-level aliases.

3. ~~**Create `scanners/InventoryScanner.h` / `.cpp`:**~~ **DONE** — `InventoryScanner` walks `pLocalPC->GetCurrentPcProfile()->GetInventory()` bags 1-10, extracts all `ItemDefinition` fields via native C++ (zero TLO). Results stored in `CacheManager`.

4. ~~**Implement fingerprint-based change detection:**~~ **DONE** — FNV-1a 64-bit hash over `(itemId, stackCount)` pairs; scan skipped when fingerprint unchanged.

5. ~~**Replace the stub in `capabilities/items.cpp`:**~~ **DONE** — `scanInventory()` calls `InventoryScanner::Scan()` and converts to sol::table matching `buildItemFromMQ` field shape. `hasInventoryChanged()` returns scanner's `HasChanged()`.

### Validation

- [x] `scan.lua` `tryCoopUIPlugin()` tries `plugin.MQ2CoOptUI` first, then falls back to `CoopUIHelper`
- [x] `require("plugin.MQ2CoOptUI")` in-game returns the module table
- [x] `mod.scanInventory` exists at top level (alias works)
- [x] `/cooptui scan inv` forces an inventory scan and prints item count + elapsed ms
- [x] `/cooptui status` shows inventory cache populated (`inv=140/256`)
- [x] In-game: open inventory window → CoOpt UI Inventory tab shows items (plugin path)
- [x] Benchmark: `/cooptui scan inv` prints time 0 ms (vs Lua ~300ms) — **300x speedup**
- [x] Fingerprint detection works: repeated scans return cached result instantly
- [x] Scanner debug output goes to DebugSpew (by design, not chat window)

**Phase 3 complete:** `scanners/InventoryScanner.h/.cpp` added; native scan 0 ms vs Lua ~300ms; 140 items returned correctly; CacheManager shows live inv count after scan.

---

## Phase 4: Bank Scanner

**Goal:** Replace the stub `items.scanBank()` with a real native bank scanner. Includes snapshot persistence.

### Steps

1. ~~**Create `scanners/BankScanner.h` / `.cpp`:**~~ **DONE** — Walks `pLocalPC->BankItems` (24 slots); handles container bags (sub-slots) and single-item bank slots; `source = "bank"`.

2. ~~**Implement bank snapshot:**~~ **DONE** — `pBankWnd->IsVisible()` gates fresh scan; when closed, `Scan()` returns retained snapshot.

3. ~~**Replace the stub in `capabilities/items.cpp`:**~~ **DONE** — `scanBank()` calls `BankScanner::Scan()` and converts to sol::table.

4. **The Lua integration is automatic** (same as inventory — `scan.lua:341-369` already has the plugin hook).

### Validation

- [x] `/cooptui scan bank` forces a bank scan (when bank is open)
- [x] Bank data persists in memory after bank window closes (snapshot)
- [x] In-game: open bank → CoOpt UI Bank tab shows items (271 items, 0 ms)
- [x] Bank scan message uses ASCII only ("closed, showing snapshot") to avoid console encoding issues

**Phase 4 complete:** `scanners/BankScanner.h/.cpp` added; snapshot retained when bank closed; `/cooptui scan bank` and Lua `scanBank()` use native scan.

---

## Phase 5: Rules Engine (Sell & Loot)

**Goal:** Implement the sell and loot rules engine in C++ with native INI reading and O(1) lookups.

### Steps

1. ~~**Create `rules/RulesEngine.h` / `.cpp`:**~~ **DONE** — `GetPrivateProfileStringA` for INI reads; chunked list support (key, key2...key20); slash-delimited parsing into `unordered_set` (O(1)) and `vector` (contains); epic class filtering via `epic_classes.ini` + per-class files.

2. ~~**Mirror exact evaluation order** from `rules.lua`:**~~ **DONE** — `WillItemBeSold()` steps 0a-19; `ShouldItemBeLooted()` exact mirror; initialized from `gPathMacros`.

3. ~~**Add `/cooptui` subcommands:**~~ **DONE** — `/cooptui reloadrules`, `/cooptui eval sell <name>`, `/cooptui eval loot <name>`.

4. ~~**Integrate with CacheManager:**~~ **DONE** — `AttachSellStatus()` called after `/cooptui scan inv`; `/cooptui status` shows rules set sizes.

### Validation

- [x] `/cooptui reloadrules` reads INIs and prints counts (0 ms)
- [x] `/cooptui eval sell <name>` matches Lua (e.g. keep/KeepType, sell/Sell)
- [x] `/cooptui eval loot <name>` matches Lua (e.g. LOOT/AlwaysContains, skip/SkipExact)
- [x] `/cooptui scan inv` shows "(X will sell)" count
- [x] `/cooptui status` shows rules set sizes (keep, junk, alwaysLoot, skipLoot, epicSell)

**Phase 5 complete:** RulesEngine loads sell/loot INIs from gPathMacros; WillItemBeSold/ShouldItemBeLooted mirror rules.lua; AttachSellStatus after scan inv; eval commands and reloadrules working.

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

- [x] `/cooptui scan loot` works when loot window is open
- [x] Lore duplicates detected correctly
- [x] Rule evaluation matches Lua 100%
- [x] **Stress test:** 100+ item corpse scans < 5ms (0 ms observed in production)
- [x] Lua integration: `scanLootItems()` returns pre-evaluated table
- [x] No game freeze during loot (before: multi-second freeze)
- [x] Deploy + sync to test environment works

**Phase 6 complete (verified 2026-03):** `scanners/LootScanner.h/.cpp` added; `capabilities/loot.cpp` extended with `scanLootItems()` Lua function; `scan.lua` hook added at top of `scanLootItems()`; top-level alias `mod["scanLootItems"]` in `CreateLuaModule()`; `/cooptui scan loot` command added; native lore duplicate check via `FindItemByNamePred`; pre-evaluated `willLoot`/`lootReason` per item via `RulesEngine::ShouldItemBeLooted()`. Production: 70 corpses looted with no issues; `/cooptui scan loot` returns e.g. "5 items in 0 ms (3 will loot, loot window open)".

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

- [x] `/cooptui scan sell` produces correct sell list
- [x] sell_cache.ini written with correct chunking
- [x] 100% match with Lua sell results
- [x] Deploy works with new capability

**Phase 7 complete:** SellScanner, SellCacheWriter, scanSellItems() in items.cpp, plugin hook in scan.lua, /cooptui scan sell, top-level alias; sell_cache.ini chunked at 1700 chars; validated.

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

- [x] Scans trigger only when items change
- [x] Bank auto-scans on open
- [x] Zone change invalidates caches
- [x] `/cooptui status` shows scan counts over 60s idle = 0 unnecessary scans

**Phase 8 complete:** OnBeginZone/OnEndZone hooks, CacheManager InvalidateAll/InvalidateInventory, version counters, throttled OnPulse window-state detection (bank/loot auto-scan, inventory fingerprint); validated.

---

## Phase 9: IPC Event Streaming & Real-Time UI

**Goal:** Replace macro variable accumulation with plugin IPC event streaming. Eliminate buffer overflow risk in loot.mac, enable real-time UI updates in the Loot Companion during active macro runs, and reduce INI file I/O during loot/sell sessions. Every macro change has an explicit fallback so loot.mac and sell.mac work identically without the plugin.

**Research:** See `docs/plugin/IPC_STREAMING_ANALYSIS.md` for the complete analysis that produced this phase.

**Complexity estimate:** This is a large phase. It touches two macros, one C++ file, and three Lua files. The individual changes are simple (one IPC send call per event, one drain loop), but the integration surface is wide. Expect 2–3 days of implementation and 1–2 days of in-game validation across varied session lengths.

### 9.1 — IPC Event Protocol Design

Define the complete event protocol for macro-to-Lua communication via the plugin's IPC channels.

**Channel capacity change:** Increase `kMaxChannelSize` in `capabilities/ipc.cpp` from 256 to 1024. This handles 25+ seconds of Lua stall without message loss. Memory cost: ~25KB per channel. Add the new constant to `core/Config.h` so it can be overridden in `CoOptCore.ini` under `[IPC] ChannelCapacity=1024`.

**New IPC API: `receiveAll(channel)`:** Add to `capabilities/ipc.cpp` alongside existing `receive()`. Returns all queued messages as a `sol::table` (Lua array) and clears the channel in one call. This is more efficient than calling `receive()` in a loop — one C++ → Lua boundary crossing instead of N.

```cpp
table.set_function("receiveAll",
    [](const std::string& channel, sol::this_state ts) -> sol::table {
      sol::state_view L(ts);
      sol::table result = L.create_table();
      auto it = s_channels.find(channel);
      if (it != s_channels.end()) {
        int idx = 1;
        for (auto& msg : it->second) {
          result[idx++] = std::move(msg);
        }
        it->second.clear();
      }
      return result;
    });
```

**Serialization format:** Pipe-delimited positional fields. Chosen because:
- MQ macros have no JSON library; pipe-split is trivial in Lua (`string.gmatch`)
- Pipes are already used in the existing echo-based loot feed format
- Item names do not contain pipes (EQ item names contain spaces, apostrophes, colons — but not pipes)
- No quoting or escaping needed

**Protocol versioning:** The channel name implicitly defines the format. Version changes are handled by adding fields at the end (backward compatible). Lua consumers check field count: if fewer fields than expected, use defaults for missing fields. If more fields than expected, ignore extras. No explicit version number field is needed — field count is the version indicator.

**Channel definitions:**

| Channel | Direction | Message Format | Fields | Producer | Consumer |
|---|---|---|---|---|---|
| `loot_item` | macro → Lua | `Name\|Value\|Tribute` | 3 | loot.mac LogItem | main_loop drain → Current tab + History |
| `loot_skip` | macro → Lua | `Name\|Reason` | 2 | loot.mac LogSkippedItem | main_loop drain → Skip History |
| `loot_progress` | macro → Lua | `Looted\|Total\|CorpseName` | 3 | loot.mac per-corpse | main_loop drain → progress bar |
| `loot_start` | macro → Lua | `TotalCorpses` | 1 | loot.mac session start | main_loop drain → open Loot UI |
| `loot_end` | macro → Lua | `LootedCount\|SkippedCount\|TotalValue\|TributeValue\|BestName\|BestValue` | 6 | loot.mac FinishLooting | main_loop drain → session complete |
| `sell_progress` | macro → Lua | `Current\|Total\|Remaining` | 3 | sell.mac WriteProgress | macro_bridge drain → progress bar |
| `sell_failed` | macro → Lua | `ItemName` | 1 | sell.mac LogFailedItem | macro_bridge drain → failed list |
| `sell_end` | macro → Lua | `SoldCount\|FailedCount\|TotalValue` | 3 | sell.mac session end | macro_bridge drain → sell complete |

### 9.2 — Macro Side Changes (loot.mac)

**Plugin detection:** Add at the top of `Sub Main`, after the runtime variable declarations:

```
/declare pluginLoaded bool outer FALSE
/if (${Plugin[MQ2CoOptUI].Name.Length}) /varset pluginLoaded TRUE
```

**LogItem changes (loot.mac LogItem subroutine):**

After the existing `runLootedCount` increment and list append block, add:

```
| IPC: stream looted item to plugin for real-time UI (fallback: vars above still accumulate)
/if (${pluginLoaded}) /squelch /cooptui ipc send loot_item "${itemName}|${itemValue}|${tribute}"
```

The existing variable accumulation (`runLootedList`, `runLootedValues`, `runLootedTributes`) is **preserved**. The IPC send is additive. This means:
- Plugin present: Lua gets real-time events via IPC AND session data via INI at end
- Plugin absent: Lua gets session data via INI at end only (current behavior)

The `enableLiveLootFeed` echo line (`/echo [ItemUI Loot] ...`) is also preserved for backward compatibility but becomes redundant when the plugin is loaded. A future cleanup phase can remove it.

**LogSkippedItem changes (loot.mac LogSkippedItem subroutine):**

After the existing `runSkippedCount` increment and list append block, add:

```
| IPC: stream skipped item to plugin for real-time UI (fallback: vars above still accumulate)
/if (${pluginLoaded}) /squelch /cooptui ipc send loot_skip "${itemName}|${reason}"
```

**Per-corpse progress (mainlootloop, after corpsesLooted increment):**

After the existing INI write at line 471, add:

```
/if (${pluginLoaded}) /squelch /cooptui ipc send loot_progress "${corpsesLooted}|${totalCorpses}|${currentCorpseName}"
```

The INI write stays for non-plugin users and as a crash-recovery checkpoint.

**Session start (START LOOTING section, after progressRunning is set):**

```
/if (${pluginLoaded}) /squelch /cooptui ipc send loot_start "${totalCorpses}"
```

**Session end (FinishLooting, after all INI writes are done):**

```
/if (${pluginLoaded}) /squelch /cooptui ipc send loot_end "${runLootedCount}|${runSkippedCount}|${runTotalValue}|${runTributeValue}|${runBestItemName}|${runBestItemValue}"
```

**Total loot.mac changes:** 6 lines added (1 detection, 5 conditional sends). Zero existing lines modified. Zero risk of regression without the plugin.

### 9.3 — Macro Side Changes (sell.mac)

**Plugin detection:** Add at the top of `Sub Main`, after the runtime variable declarations:

```
/declare pluginLoaded bool outer FALSE
/if (${Plugin[MQ2CoOptUI].Name.Length}) /varset pluginLoaded TRUE
```

**WriteProgress changes (sell.mac WriteProgress subroutine):**

After the existing INI writes, add:

```
/if (${pluginLoaded}) /squelch /cooptui ipc send sell_progress "${soldCount}|${totalToSell}|${remaining}"
```

The INI writes stay for non-plugin users.

**LogFailedItem changes (sell.mac LogFailedItem subroutine):**

After the existing INI write, add:

```
/if (${pluginLoaded}) /squelch /cooptui ipc send sell_failed "${itemName}"
```

**Session end (at the end of Sub Main, before the final `/return`):**

After the progress INI reset block, add:

```
/if (${pluginLoaded} && ${doConfirm}) /squelch /cooptui ipc send sell_end "${sellCount}|${failedCount}|${totalValue}"
```

**Total sell.mac changes:** 4 lines added (1 detection, 3 conditional sends). Zero existing lines modified.

### 9.4 — Lua Event Drain Integration

**Location:** Inside `macro_bridge.lua`, integrated into the existing `MacroBridge.poll()` function. The drain runs every time `poll()` runs (every 500ms at the configured `pollInterval`). Additionally, a new `MacroBridge.drainIPCFast()` function runs every tick from `main_loop.lua` to drain high-frequency channels (loot_item, loot_skip) at frame rate even when the full poll is throttled.

**Plugin module access:** The drain uses `require("plugin.MQ2CoOptUI")` (same path as `scan.lua:tryCoopUIPlugin()`). If the require fails, no drain occurs — fallback to INI-only mode.

**New function in macro_bridge.lua:**

```lua
local coopui_ipc = nil
local ipc_checked = false

local function getIPC()
    if ipc_checked then return coopui_ipc end
    ipc_checked = true
    local ok, mod = pcall(require, "plugin.MQ2CoOptUI")
    if ok and mod and mod.ipc and mod.ipc.receiveAll then
        coopui_ipc = mod.ipc
    end
    return coopui_ipc
end

function MacroBridge.drainIPCFast(uiState, getSellStatusForItem, LOOT_HISTORY_MAX)
    local ipc = getIPC()
    if not ipc then return end

    -- Drain loot_item events → Current tab + History
    local items = ipc.receiveAll("loot_item")
    if items and #items > 0 then
        if not uiState.lootRunLootedItems then uiState.lootRunLootedItems = {} end
        if not uiState.lootRunLootedList then uiState.lootRunLootedList = {} end
        if not uiState.lootHistory then uiState.lootHistory = {} end
        for _, msg in ipairs(items) do
            local name, valStr, tribStr = msg:match("^([^|]+)|([^|]+)|(.+)$")
            if name and name ~= "" then
                local value = tonumber(valStr) or 0
                local tribute = tonumber(tribStr) or 0
                local statusText, willSell = "—", false
                if getSellStatusForItem then
                    statusText, willSell = getSellStatusForItem({ name = name })
                    if statusText == "" then statusText = "—" end
                end
                table.insert(uiState.lootRunLootedList, name)
                table.insert(uiState.lootRunLootedItems, {
                    name = name, value = value, tribute = tribute,
                    statusText = statusText, willSell = willSell
                })
                table.insert(uiState.lootHistory, {
                    name = name, value = value,
                    statusText = statusText, willSell = willSell
                })
                while #uiState.lootHistory > LOOT_HISTORY_MAX do
                    table.remove(uiState.lootHistory, 1)
                end
                -- Running totals
                uiState.lootRunTotalValue = (uiState.lootRunTotalValue or 0) + value
                uiState.lootRunTributeValue = (uiState.lootRunTributeValue or 0) + tribute
                if value > (uiState.lootRunBestItemValue or 0) then
                    uiState.lootRunBestItemValue = value
                    uiState.lootRunBestItemName = name
                end
            end
        end
    end

    -- Drain loot_skip events → Skip History
    local skips = ipc.receiveAll("loot_skip")
    if skips and #skips > 0 then
        if not uiState.skipHistory then uiState.skipHistory = {} end
        for _, msg in ipairs(skips) do
            local name, reason = msg:match("^([^|]+)|(.+)$")
            if name and name ~= "" then
                table.insert(uiState.skipHistory, {
                    name = name, reason = reason or ""
                })
                while #uiState.skipHistory > LOOT_HISTORY_MAX do
                    table.remove(uiState.skipHistory, 1)
                end
            end
        end
    end

    -- Drain loot_progress events → progress bar
    local progress = ipc.receiveAll("loot_progress")
    if progress and #progress > 0 then
        local last = progress[#progress]  -- only latest matters
        local looted, total, corpse = last:match("^([^|]+)|([^|]+)|(.*)$")
        if looted then
            uiState.lootRunCorpsesLooted = tonumber(looted) or 0
            uiState.lootRunTotalCorpses = tonumber(total) or 0
            uiState.lootRunCurrentCorpse = corpse or ""
        end
    end

    -- Drain loot_start → open Loot UI
    local starts = ipc.receiveAll("loot_start")
    if starts and #starts > 0 then
        uiState.lootUIOpen = true
        uiState.lootRunFinished = false
        uiState.lootRunLootedItems = {}
        uiState.lootRunLootedList = {}
        uiState.lootRunTotalValue = 0
        uiState.lootRunTributeValue = 0
        uiState.lootRunBestItemName = ""
        uiState.lootRunBestItemValue = 0
    end

    -- Drain loot_end → session summary
    local ends = ipc.receiveAll("loot_end")
    if ends and #ends > 0 then
        local last = ends[#ends]
        local parts = {}
        for p in (last .. "|"):gmatch("([^|]*)|") do parts[#parts + 1] = p end
        if #parts >= 6 then
            uiState.lootRunTotalValue = tonumber(parts[3]) or uiState.lootRunTotalValue
            uiState.lootRunTributeValue = tonumber(parts[4]) or uiState.lootRunTributeValue
            if parts[5] ~= "" then uiState.lootRunBestItemName = parts[5] end
            uiState.lootRunBestItemValue = tonumber(parts[6]) or uiState.lootRunBestItemValue
        end
        uiState.lootRunFinished = true
    end
end
```

**Sell IPC drain (inside MacroBridge.poll):**

Add sell channel drains inside `MacroBridge.poll()`, after the existing sell macro state checks:

```lua
-- Drain sell IPC channels (supplements INI polling; higher priority)
local ipc = getIPC()
if ipc then
    local sp = ipc.receiveAll("sell_progress")
    if sp and #sp > 0 then
        local last = sp[#sp]
        local cur, tot, rem = last:match("^([^|]+)|([^|]+)|(.+)$")
        if cur then
            MacroBridge.state.sell.progress = {
                total = tonumber(tot) or 0,
                current = tonumber(cur) or 0,
                remaining = tonumber(rem) or 0
            }
            MacroBridge.state.sell.running = true
        end
    end
    local sf = ipc.receiveAll("sell_failed")
    if sf and #sf > 0 then
        for _, msg in ipairs(sf) do
            table.insert(MacroBridge.state.sell.failedItems, msg)
            MacroBridge.state.sell.failedCount = MacroBridge.state.sell.failedCount + 1
        end
    end
    local se = ipc.receiveAll("sell_end")
    if se and #se > 0 then
        MacroBridge.state.sell.running = false
    end
end
```

**main_loop.lua integration:** Add one line to `M.tick(now)`, immediately after the existing `macro_bridge.poll()` call:

```lua
if d.macroBridge and d.macroBridge.drainIPCFast then
    d.macroBridge.drainIPCFast(d.uiState, d.getSellStatusForItem, d.LOOT_HISTORY_MAX)
end
```

**Queue depth handling:** The drain calls `receiveAll()` which empties the channel in one shot. If events accumulate faster than they are consumed (theoretically impossible since drain runs every frame and produce rate is <50/second), the channel's 1024-message limit silently drops oldest events. No crash, no hang — just lost history entries. This is strictly better than the current behavior where overflow causes a CTD.

### 9.5 — Real-Time UI Updates

**Loot Companion — Current tab (`loot_ui.lua`):**

Before Step 9, the Current tab's looted items table (`loot_ui.lua:329–392`) is empty during a loot run and batch-populates from `loot_session.ini` after `loot:complete`. The table iterates `state.lootRunLootedItems`.

After Step 9, the IPC drain in 9.4 inserts rows into `state.lootRunLootedItems` per-frame as events arrive. The table renders them immediately. No changes to `loot_ui.lua` are needed — the view already renders whatever is in the array.

**Player experience — before:** Start loot macro → Loot Companion opens → progress bar advances → looted items table is blank for entire run (30 seconds to 5 minutes) → macro finishes → all items appear at once.

**Player experience — after:** Start loot macro → Loot Companion opens → progress bar advances → each looted item appears in the table within one frame of being looted → running totals (value, tribute, best item) update live → macro finishes → session summary finalizes.

**Loot Companion — Skip History tab (`loot_ui.lua`):**

Before Step 9, Skip History populates from `loot_skipped.ini` after `loot:complete`. The tab is blank during the run.

After Step 9, the IPC drain inserts skip entries into `state.skipHistory` per-frame. The Skip History tab shows items being skipped in real time with reasons.

**Player experience — before:** Skip History tab is blank during run → batch appears at end.

**Player experience — after:** Skip History tab shows each skipped item with reason as it is evaluated → player can switch to Loot tab and add items to Always Loot if they see something they want.

**Loot Companion — Progress bar:**

Before Step 9, progress updates every 500ms via INI polling. After Step 9, progress updates per-frame via IPC. The visual difference is smoother bar animation and immediate corpse-name updates.

**Sell View — Progress bar (`sell.lua`):**

The sell progress bar reads from `MacroBridge.state.sell.progress` via `macro_bridge.getSellProgress()`. The IPC drain in 9.4 updates this state from `sell_progress` events. The sell view code does not change — it already reads from the state that the drain now populates more frequently.

**Player experience — before:** Progress bar updates in 150–500ms steps. After: progress bar updates per-frame.

**Sell View — Failed items:**

Failed items now appear in `sellMacState.failedItems` as they occur, not at session end. The existing failed-items display in `main_loop.lua` phase 4 already reads from this state.

**Session summary merge (`main_loop.lua` phase 5):**

The existing phase 5 session-read logic at `main_loop.lua:222–294` reads `loot_session.ini` and merges into `lootRunLootedItems`. When IPC events have already populated the items table during the run, the merge logic's `seen` deduplication (line 232) prevents duplicates. The phase 5 session read becomes a reconciliation pass — it adds any items that the IPC drain might have missed (e.g., if the plugin was unloaded mid-session) and sets authoritative summary totals.

No changes to phase 5 logic are needed. The existing merge is already designed to handle partial pre-population (it checks `seen[name]` before inserting).

### 9.6 — Buffer Overflow Elimination

**Complete audit of macro variables with overflow risk:**

| Variable | Macro | Chunks | Risk before 9 | Status after 9 |
|---|---|---|---|---|
| runSkippedList / Reasons | loot.mac | 5 each | **Fixed** (dual-length check) but 5-chunk cap drops details | **Mitigated**: IPC streams all events with no cap; vars still accumulate as fallback with existing fix |
| runLootedList / Values / Tributes | loot.mac | 3 each | **Active risk**: 3-chunk cap silently drops items and count | **Mitigated**: IPC streams all events; Lua accumulates from events with no limit |
| lootedNamesThisSession | loot.mac | 3 | Low risk (internal cache; items re-evaluated on miss) | **Unchanged**: internal optimization, not UI-facing |
| skippedNamesThisSession | loot.mac | 3 | Low risk (internal cache) | **Unchanged** |
| loreItemCache | loot.mac | 3 | Low risk (internal cache; FindItem fallback) | **Unchanged** |
| epicExact | loot.mac / sell.mac | 4 | Config-dependent; warning issued at load | **Unchanged**: config lists, not session-accumulating |
| sellCacheNames | sell.mac | 10 | Read-only input from Lua; buffer warning | **Unchanged**: not session-accumulating |
| alwaysSellExact / Contains | sell.mac | 3 each | Config-dependent; buffer warning | **Unchanged** |
| protectedTypes | sell.mac | 3 | Config-dependent; buffer warning | **Unchanged** |

**Key insight:** The IPC pattern eliminates overflow risk for the two variable groups that actually grow during a session: `runLootedList` (3 chunks) and `runSkippedList/Reasons` (5 chunks). Config-load variables (epicExact, alwaysSellExact, etc.) are bounded by config file size, not session length, and are not addressed here.

**Regression test procedure:**
1. Run a 100-corpse loot session with the plugin loaded. Verify all 100+ looted items appear in Current tab (exceeds the 3-chunk cap of ~200 items per name length).
2. Run the same session without the plugin. Verify the 3-chunk cap behavior is unchanged (items beyond cap are dropped, count stops incrementing when all chunks full).
3. Run a session where skip reasons are deliberately verbose (e.g., modify loot config to produce long reason strings). Verify skip events stream via IPC with no truncation.
4. Monitor `kMaxChannelSize` utilization: after a 100-corpse run, check that no channel exceeded 50% capacity during normal operation (indicates safe headroom).

### 9.7 — Crash Recovery

**Data recovery improvement:** Before Step 9, if MQ crashes during a loot session, all accumulated session data is lost — `loot_session.ini` and `loot_skipped.ini` are only written at `FinishLooting`, which never runs during a crash.

After Step 9, each loot/skip event is delivered to the plugin's in-memory IPC channel and drained into Lua state per-frame. The Lua side holds the data in `uiState.lootRunLootedItems` and `uiState.skipHistory`. These are in-memory Lua tables — they survive a macro crash (the macro crashes, Lua keeps running), but not a full MQ/game crash.

**Incremental persistence:** To survive full crashes, the Lua drain should periodically persist in-flight session data. The existing `phase2_periodicPersist` in `main_loop.lua` (line 98–124) already saves inventory every `PERSIST_SAVE_INTERVAL_MS`. A similar mechanism for loot session data:

- Every 10 seconds during an active loot session, write current `lootRunLootedItems` and `skipHistory` to `loot_session_inflight.ini` and `loot_skipped_inflight.ini`
- On next loot session start, check for inflight files and offer recovery in the Loot Companion UI
- On clean session end (loot_end event received), delete inflight files

**What is now recoverable that was previously lost:**

| Scenario | Before Step 9 | After Step 9 |
|---|---|---|
| Macro crashes, MQ stays running | All session data lost | All data preserved in Lua state; UI still shows it |
| Full MQ crash during session | All session data lost | Data up to last periodic persist (≤10 seconds old) recoverable from inflight files |
| Plugin unloaded mid-session | N/A (no plugin) | Events delivered before unload preserved; remaining events accumulate in macro vars and arrive via INI at session end |

**Implementation complexity:** The inflight persistence adds a periodic write loop and a startup recovery check. This is a Medium complexity addition. It can be deferred to a sub-phase (9.7b) if the core IPC streaming (9.1–9.5) needs to ship first. The primary crash recovery benefit — surviving macro crashes — is free with the IPC drain and requires no additional work.

### 9.8 — Fallback Contract

Every macro change in 9.2 and 9.3 is guarded by `${pluginLoaded}`. When the plugin is absent:

**loot.mac behavior without plugin:**
- `pluginLoaded = FALSE` — all `/cooptui ipc send` lines are skipped
- Variable accumulation in `runLootedList`, `runSkippedList`, etc. proceeds unchanged
- `FinishLooting` writes `loot_session.ini` and `loot_skipped.ini` as before
- The echo-based live feed (`enableLiveLootFeed`) continues to work
- `loot_progress.ini` is still written per corpse
- **No behavioral change whatsoever** for non-plugin users

**sell.mac behavior without plugin:**
- `pluginLoaded = FALSE` — all `/cooptui ipc send` lines are skipped
- `WriteProgress` writes `sell_progress.ini` as before
- `LogFailedItem` writes `sell_failed.ini` as before
- **No behavioral change whatsoever** for non-plugin users

**Lua behavior without plugin:**
- `macro_bridge.drainIPCFast()` calls `getIPC()` which returns `nil` (plugin not loaded)
- The function returns immediately — no drain, no state changes
- All data continues to arrive via INI polling through `macro_bridge.poll()`, `getLootSession()`, `pollLootProgress()` — exactly as today
- Phase 5 session read in `main_loop.lua` populates tables from INI files as before

**Plugin loaded mid-session:**
- If the plugin is loaded after loot.mac starts, `pluginLoaded` remains `FALSE` for that session (it was set at macro startup). Events do not stream. Data arrives via INI at session end. This is correct — partial-session IPC would create confusing data gaps.
- On the next macro run, `pluginLoaded` is re-evaluated and will be `TRUE`.

**Plugin unloaded mid-session:**
- IPC sends fail silently (the `/cooptui` command is unregistered; MQ2 ignores unknown commands with `/squelch`). No error, no crash.
- Variable accumulation continues in the macro. Data arrives via INI at session end.
- Events that were already delivered to Lua before unload remain in `uiState` and are visible in the UI.

### Validation

- [x] **loot.mac + plugin:** IPC events stream in real time; Loot Companion Current tab shows items appearing per-frame
- [x] **loot.mac − plugin:** Behavior identical to pre-Phase-9; Loot Companion populates from INI at session end
- [x] **sell.mac + plugin:** Progress bar updates per-frame; failed items appear immediately
- [x] **sell.mac − plugin:** Behavior identical to pre-Phase-9; progress bar updates via INI polling
- [x] **Long session (200+ items looted, 300+ skipped):** No buffer overflow, all items appear in UI
- [x] **IPC channel capacity:** `kMaxChannelSize = 1024` verified in `/cooptui status`
- [x] **receiveAll() API:** Returns correct table, clears channel in one call
- [x] **Plugin unload mid-session:** No crash, no error; remaining data arrives via INI
- [x] **Plugin load then loot:** Events stream; IPC drain populates tables; session read merges without duplicates
- [x] **Phase 5 session read merge:** Items from IPC are not duplicated when `loot_session.ini` is read at session end

**Phase 9 complete (with caveat):** IPC event protocol (9.1), macro-side sends (loot.mac, sell.mac), Lua drain (drainIPCFast, poll sell channels), and real-time UI behavior are implemented. Buffer overflow mitigation, fallback contract, and session merge behavior are in place. **Caveat:** IPC real-time operations (loot_item, loot_skip, sell_progress, channel capacity under load) should be tested in future in-game sessions to confirm end-to-end behavior under varied session lengths and load.

### Quick rebuild + deploy command:

```powershell
# Plugin change (ipc.cpp receiveAll, kMaxChannelSize):
$env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path
.\scripts\build-and-deploy.ps1 `
  -SourceRoot "C:\MIS\MacroquestEnvironments\CompileTest\Source" `
  -DeployPath "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" `
  -PluginOnly -UsePrebuildDownload:$false

# Lua + macro changes (no rebuild needed):
.\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7"
```

### Copyable handoff prompt — Phase 9 (IPC Event Streaming)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md Phase 9 and
docs/plugin/IPC_STREAMING_ANALYSIS.md first. Then implement Phase 9
(IPC Event Streaming & Real-Time UI).

Phase 9 has 8 sub-steps. Implement them in order:

9.1: In capabilities/ipc.cpp, increase kMaxChannelSize to 1024 and add
receiveAll(channel) that returns a sol::table of all queued messages and
clears the channel. Add top-level alias mod["ipc"]["receiveAll"] in
CreateLuaModule(). Optionally make capacity configurable via CoOptCore.ini
[IPC] ChannelCapacity.

9.2: In Macros/loot.mac, add pluginLoaded detection at Sub Main. Add
/squelch /cooptui ipc send calls in LogItem, LogSkippedItem, per-corpse
progress, session start, and FinishLooting. All guarded by pluginLoaded.
Do NOT remove any existing variable accumulation or INI writes.

9.3: In Macros/sell.mac, add pluginLoaded detection at Sub Main. Add
/squelch /cooptui ipc send calls in WriteProgress, LogFailedItem, and
session end. All guarded by pluginLoaded.

9.4: In lua/itemui/services/macro_bridge.lua, add drainIPCFast() that
uses receiveAll() on loot_item, loot_skip, loot_progress, loot_start,
loot_end channels. Populates uiState tables. Add sell channel drains
inside poll(). In lua/itemui/services/main_loop.lua, call
macroBridge.drainIPCFast() at the top of M.tick() after poll().

9.5-9.8: Verify real-time UI updates work, buffer overflow is mitigated,
crash recovery improved, fallback contract holds.

Build: cmake --build "...\build\solution" --config Release --target MQ2CoOptUI
Deploy: sync-to-deploytest.ps1 + IncludePlugin

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Zero char[] buffers.
Verify all Phase 9 validation checkboxes before declaring complete.
```

---

## Phase 10: TLO Enhancements

**Goal:** Extend the existing `${CoOptUI}` TLO with cache/rules access for macros.

### Steps

1. **Add members to `MQ2CoOptUIType`** in `MQ2CoOptUI.cpp`:
   - `${CoOptUI.Inventory.Count}` — cached item count
   - `${CoOptUI.Loot.Count}` — loot item count
   - `${CoOptUI.Rules.Evaluate[sell,itemname]}` — sell decision
   - `${CoOptUI.Status}` — "Ready" / "Scanning" / "Loading"
   - Keep existing `Version`, `APIVersion`, `MQCommit`, `Debug` members

### Validation

- [x] `/echo ${CoOptUI.Inventory.Count}` prints correct count
- [x] `/echo ${CoOptUI.Rules.Evaluate[sell,Bone Chips]}` prints decision
- [x] Existing TLO members still work (no regression)

### Copyable handoff prompt — Phase 10 (TLO Enhancements)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md first, then implement Phase 10 (TLO Enhancements).

Context: The MQ2CoOptUI plugin at plugin/MQ2CoOptUI/ exposes ${CoOptUI} via MQ2CoOptUIType in MQ2CoOptUI.cpp. Phase 10 adds new TLO members for macros: (1) ${CoOptUI.Inventory.Count} — cached inventory item count from CacheManager. (2) ${CoOptUI.Loot.Count} — cached loot item count. (3) ${CoOptUI.Rules.Evaluate[sell,itemname]} — sell decision (e.g. "sell" / "keep") via RulesEngine::WillItemBeSold. (4) ${CoOptUI.Status} — "Ready" / "Scanning" / "Loading" based on cache/scan state. Keep existing Version, APIVersion, MQCommit, Debug members unchanged.

Implement by extending the MQ2CoOptUIType class and its member registration. Use std::string for any new string returns; no char[] buffers. Validate: /echo ${CoOptUI.Inventory.Count}, /echo ${CoOptUI.Rules.Evaluate[sell,Bone Chips]}, and existing TLO members still work.

Build: cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI
Deploy: Copy-Item "...\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force; or .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" -IncludePlugin

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Verify all Phase 10 validation checkboxes before declaring complete.
```

---

## Phase 11: Lua Integration Patches (Final Pass)

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
   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7"
   ```

### Validation

- [ ] With plugin: all 4 scans (inv, bank, loot, sell) use plugin path *(in-game)*
- [ ] Without plugin: all scans fall back to Lua *(in-game)*
- [ ] All views show same data with/without plugin *(in-game)*
- [ ] No errors during scan transitions *(in-game)*
- [ ] Mid-session load/unload works cleanly *(in-game)*
- [x] `sync-to-deploytest.ps1` copies updated Lua files correctly
- [x] tryCoopUIPlugin() tries plugin.MQ2CoOptUI first (scan.lua)
- [x] scanLootItems() and scanSellItems() hooks use plugin when available (scan.lua)
- [x] Top-level aliases mod["scanLootItems"] and mod["scanSellItems"] present in CreateLuaModule()

### Copyable handoff prompt — Phase 11 (Lua Integration Patches)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md first, then implement Phase 11 (Lua Integration Patches — Final Pass).

Context: Phases 3, 6, and 7 added plugin hooks and top-level aliases. Phase 11 verifies and completes the integration: (1) Confirm tryCoopUIPlugin() in scan.lua tries plugin.MQ2CoOptUI first. (2) Confirm scanLootItems() and scanSellItems() hooks exist and use the plugin when available. (3) Add scanLootItems and scanSellItems as top-level aliases in CreateLuaModule() in MQ2CoOptUI.cpp if not already present (mod["scanLootItems"] = loot_table["scanLootItems"]; mod["scanSellItems"] = items_table["scanSellItems"];). (4) Run full fallback test: unload MQ2CoOptUI, verify every scan (inv, bank, loot, sell) works via pure Lua. (5) Run reload test: load MQ2CoOptUI mid-session, verify all scans switch to plugin path. (6) Deploy Lua via .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7".

No new C++ sources required unless aliases are missing. Focus on verification and any missing alias registration. Validate all Phase 11 checkboxes.

Follow .cursor/rules/deploy-test-sync.mdc for sync command. Verify all Phase 11 validation checkboxes before declaring complete.
```

---

## Phase 12: Performance Metrics & Stress Testing

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

### Copyable handoff prompt — Phase 12 (Performance Metrics & Stress Testing)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md first, then implement Phase 12 (Performance Metrics & Stress Testing).

Context: The MQ2CoOptUI plugin at plugin/MQ2CoOptUI/ has CacheManager and scanners (Inventory, Bank, Loot, Sell). Phase 12 adds: (1) Perf counters in CacheManager — scan count and avg/max time per type (inv, bank, loot, sell, rules load). (2) /cooptui perf — print all counters; /cooptui perf reset to zero them. (3) /cooptui stress loot <count> — simulate N-item loot scan for benchmarking. (4) Benchmark targets: inventory 100 items < 2ms, bank 240 < 5ms, loot 300 < 5ms, sell eval 100 < 0.5ms, rules load < 2ms; fail thresholds 10ms/20ms/5ms/10ms as in the plan.

Wire counters into existing scanner and CacheManager paths. Use existing Logger/ScopedTimer where appropriate. Validate: /cooptui perf shows data, stress loot 300 under 10ms, no memory growth after 1000 scans, stable over 10-minute session.

Build: cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI
Deploy: .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" -IncludePlugin

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Verify all Phase 12 validation checkboxes before declaring complete.
```

---

## Phase 13: Deploy, Sync, & Zip Verification

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
   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" -IncludePlugin
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

### Copyable handoff prompt — Phase 13 (Deploy, Sync, & Zip Verification)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md first, then execute Phase 13 (Deploy, Sync, & Zip Verification).

Context: Phase 13 is a verification and release-readiness pass — no new feature code. Steps: (1) Run full build-and-deploy: $env:Path = "C:\MIS\CMake-3.30\bin;" + $env:Path; .\scripts\build-and-deploy.ps1 -SourceRoot "C:\MIS\MacroquestEnvironments\CompileTest\Source" -DeployPath "C:\MIS\MacroquestEnvironments\CompileTest" -UsePrebuildDownload:$false -CreateZip. (2) Verify zip: .\scripts\list-zip.ps1 -ZipPath "C:\MIS\MacroquestEnvironments\CoOptUI-EMU-YYYYMMDD.zip" — must contain plugins/MQ2CoOptUI.dll and standard entries. (3) Sync with plugin: .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7" -IncludePlugin. (4) Ensure config/CoOptCore.ini default exists in config_templates/ if not already. (5) End-to-end test: launch from deploy folder, /plugin MQ2CoOptUI, /cooptui status, open inventory/bank/merchant/loot and verify all views work; unload plugin and verify Lua fallback.

Document any failures or missing zip entries. Validate all Phase 13 checkboxes before declaring complete.
```

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
│   ├── ipc.h / ipc.cpp                  ← IMPLEMENTED; Phase 9 adds receiveAll(), increases channel cap
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
| `lua/itemui/services/macro_bridge.lua` | Add `drainIPCFast()`, sell IPC drain in `poll()`, `getIPC()` helper | **9** | Real-time IPC event consumption |
| `lua/itemui/services/main_loop.lua` | Call `macroBridge.drainIPCFast()` in `M.tick()` | **9** | Frame-rate IPC drain |

The inventory and bank hooks **already exist** in `scan.lua:108-147` and `scan.lua:341-369` — the code paths already call `coopui.scanInventory()` and `coopui.scanBank()`. With the top-level aliases added in `CreateLuaModule()` (Phase 3), these existing hooks will "just work" once the stubs return real data.

### C++ Files Modified (Existing)

| File | Change | Phase | Impact |
|---|---|---|---|
| `plugin/MQ2CoOptUI/MQ2CoOptUI.cpp` | Top-level aliases in `CreateLuaModule()` | **3** | Fixes function path mismatch |
| `plugin/MQ2CoOptUI/MQ2CoOptUI.cpp` | Wire CacheManager, extend commands, add event hooks | 2, 8, 10 | Core infra |
| `plugin/MQ2CoOptUI/capabilities/ipc.cpp` | Increase `kMaxChannelSize` to 1024, add `receiveAll()` | **9** | IPC streaming |
| `plugin/MQ2CoOptUI/capabilities/items.cpp` | Replace stubs with real scanner calls | 3, 4, 7 | Real scanning |
| `plugin/MQ2CoOptUI/capabilities/loot.cpp` | Add `scanLootItems()` | 6 | Real loot scanning |

### Macro Files Modified

| File | Change | Phase | Impact |
|---|---|---|---|
| `Macros/loot.mac` | Add `pluginLoaded` detection + 5 IPC send calls (guarded) | **9** | Real-time loot/skip/progress streaming |
| `Macros/sell.mac` | Add `pluginLoaded` detection + 3 IPC send calls (guarded) | **9** | Real-time sell progress streaming |

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
          Phase 9 (IPC Event Streaming)
                    │
                    ▼
          Phase 10 (TLO Enhancements)
                    │
                    ▼
          Phase 11 (Lua Patches)
                    │
                    ▼
          Phase 12 (Stress Test)
                    │
                    ▼
          Phase 13 (Deploy/Zip Verify)
```

Phases 3-4 can run in parallel with Phase 5.
Phase 6 requires Phases 3+4+5 complete.
Phase 9 requires Phase 8 complete (IPC infrastructure + event hooks).
Phase 9 touches macros and Lua only; it does NOT depend on Phases 10-11.
Phase 13 can start after the prerequisite (for deploy-only tests).

---

## Handoff Instructions

When handing a phase to a Cursor agent, include:

1. **"Read `docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md` first"**
2. **The specific phase number:** "Implement Phase N"
3. **Build environment context:**
   - Plugin source: `plugin/MQ2CoOptUI/` in this repo
   - Symlink: `CompileTest\Source\macroquest\plugins\MQ2CoOptUI` → this repo's `plugin/MQ2CoOptUI`
   - Quick rebuild: `cmake --build ...\build\solution --config Release --target MQ2CoOptUI`
   - Deploy: copy DLL to `DeployTest\CoOptUI7\plugins\`
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
Deploy: Copy-Item "...\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Zero char[] buffers. Use std::string.
Verify all validation checkboxes in the plan before declaring complete.
```

### Copyable prompt — Phase 7 (Sell Scanner & Cache Writer)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md first, then implement Phase 7 (Sell Scanner & Cache Writer).

Context: The MQ2CoOptUI plugin at plugin/MQ2CoOptUI/ already has InventoryScanner, BankScanner, LootScanner, and RulesEngine (sell/loot). Phase 7 adds: (1) SellScanner — uses cached inventory from CacheManager and RulesEngine::WillItemBeSold() to build a sell list in memory (no TLO). (2) SellCacheWriter — writes sell_cache.ini via Win32 WritePrivateProfileString with chunking (each key ≤ 1700 chars, match Lua SELL_CACHE_CHUNK_LEN). (3) scanSellItems() in capabilities/items.cpp that returns the sell list as a sol::table. (4) Plugin hook in scan.lua:scanSellItems() so the Sell tab can use the plugin path when available.

Lua scan.lua already has scanSellItems() and a reentrancy guard; add at the top the same pattern as scanLootItems(): tryCoopUIPlugin(), if coopui.scanSellItems then pcall and if ok and #result > 0 then populate env.sellItems and return. Add top-level alias mod["scanSellItems"] in CreateLuaModule() and /cooptui scan sell command. Update CMakeLists.txt for new sources (scanners/SellScanner.cpp, storage/SellCacheWriter.cpp).

Build: cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI -- /p:BuildProjectReferences=false
Deploy: Copy-Item "...\build\solution\bin\release\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force; .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7"

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Zero char[] buffers. Use std::string. Verify all Phase 7 validation checkboxes before declaring complete.
```

### Copyable prompt — Phase 8 (Event-Driven Invalidation)

```
Read docs/plugin/MQ2COOPTCORE_IMPLEMENTATION_PLAN.md first, then implement Phase 8 (Event-Driven Invalidation).

Context: The MQ2CoOptUI plugin at plugin/MQ2CoOptUI/ has CacheManager with dirty flags and OnPulse() throttled by ScanThrottleMs. Phase 8 adds: (1) MQ event hooks in MQ2CoOptUI.cpp — OnBeginZone() → CacheManager::InvalidateAll(), OnEndZone() (or equivalent) → CacheManager::InvalidateInventory(). (2) In OnPulse(), a lightweight hash of inventory item IDs (e.g. FNV over id+stack like InventoryScanner fingerprint); only set inventory dirty when the hash changes. (3) In OnPulse(), detect bank/merchant/loot window visibility and trigger auto-scan on open or snapshot-on-close behavior where applicable. (4) Optional: per-cache-type version numbers so Lua can poll and refresh only when version changes.

Ensure existing behavior is preserved: InventoryScanner/BankScanner/LootScanner already have their own fingerprint or window checks; wire events so that zone change and window state reduce unnecessary scans rather than replace scanner logic. Validate: zone change invalidates caches; bank open triggers scan; idle 60s shows no unnecessary scan count growth in /cooptui status.

Build: cmake --build "C:\MIS\MacroquestEnvironments\CompileTest\Source\macroquest\build\solution" --config Release --target MQ2CoOptUI -- /p:BuildProjectReferences=false
Deploy: Copy-Item "...\build\solution\bin\release\plugins\MQ2CoOptUI.dll" "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI7\plugins\" -Force

Follow .cursor/rules/mq-plugin-build-gotchas.mdc. Verify all Phase 8 validation checkboxes before declaring complete.
```

---

## Build-and-Deploy Script: Improvements Made

The following improvements have been implemented in the build/deploy scripts:

1. **`-PluginOnly` switch (build-and-deploy.ps1):** Builds only `--target MQ2CoOptUI` (not all of MQ), copies just the DLL + Lua/macros/resources. Skips E3Next, reference copy, config, mono, README, and zip. Enables ~10-second iteration cycles during plugin development.

   ```powershell
   .\scripts\build-and-deploy.ps1 -SourceRoot "...\Source" -DeployPath "...\CoOptUI7" -PluginOnly -UsePrebuildDownload:$false
   ```

2. **`-IncludePlugin` switch (sync-to-deploytest.ps1):** Copies `MQ2CoOptUI.dll` from build output alongside the standard Lua/macros/resources sync. No rebuild — just file copy.

   ```powershell
   .\scripts\sync-to-deploytest.ps1 -Target "...\CoOptUI7" -IncludePlugin
   ```

3. **Stage 3e always runs in PluginOnly mode:** Lua/macros/resources are deployed even in plugin-only mode, ensuring Lua hook changes (from Phases 6/7/11) reach the test environment.

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
| IPC channel overflow | Increased cap to 1024; receiveAll() drains per-frame; silent drop > crash |
| Macro runs without plugin | All IPC sends guarded by `pluginLoaded`; var accumulation + INI writes preserved |
| Duplicate items in UI | Phase 5 session-read merge uses `seen[name]` dedup; IPC items merge cleanly |
