# Plugin Deep Dive — MQ2CoOptUI Architecture & Capability Analysis

> Produced: 2026-02-28. Based on full read of MQ EMU clone source, deployed binaries,
> all CoOpt UI Lua services, plugin source, build system, and deployment pipeline.

---

## Section 1 — Plugin Ecosystem Map

### 1.1 Deployed Plugin DLLs

The active deployment at `C:\MIS\E3NextAndMQNextBinary-main\plugins\` contains **99 plugin DLLs**.
All are **x86 (32-bit)**, matching the EMU target. The vast majority (98 of 99) are dated
2026-01-20 (the base E3Next distribution). MQ2CoOptUI.dll is the only DLL with a recent
timestamp (2026-02-28 6:21 PM), indicating it was manually deployed from a separate build.

### 1.2 Built-In Plugins (EMU Clone `src/plugins/`)

These compile as part of the MQ core build:

| Plugin | Purpose | Key Hooks | Lua Module | TLO |
|--------|---------|-----------|------------|-----|
| **MQ2Lua** | Lua scripting engine | Init, Shutdown, Pulse, OnUnloadPlugin | Consumes CreateLuaModule; registers built-in modules (mq, ImGui, ImPlot, actors, Zep, ImAnim) | `Lua` |
| **MQ2ItemDisplay** | Item Display window enhancement | Init, Shutdown, Pulse, CleanUI | No | `DisplayItem` |
| **MQ2AutoBank** | Auto-bank items | Init, Shutdown, Pulse, CleanUI, ReloadUI, SetGameState | No | — (commands only) |
| **MQ2Map** | Map window and spawn visualization | Init, Shutdown, Pulse | No | `MapSpawn` |
| **MQ2Bzsrch** | Bazaar search | Init, Shutdown, Pulse, SetGameState | No | `Bazaar` |
| **MQ2AutoLogin** | Auto-login and character switching | Init, Shutdown, Pulse | No | `AutoLogin` |
| **MQ2TargetInfo** | Target window info | Init, Shutdown, Pulse, CleanUI, ReloadUI | No | — |
| **MQ2XTarInfo** | Extended target window | Init, Shutdown, Pulse, CleanUI, ReloadUI | No | — |
| **MQ2HUD** | HUD elements | Init, Shutdown, SetGameState, Zoned | No | `HUD` |
| **MQ2ChatWnd** | MQ chat window | Init, Shutdown, Pulse | No | `ChatWnd` |
| **MQ2Labels** | Label text updates | Init, Shutdown | No | — |
| **MQ2Chat** | Chat handling | Init, Shutdown | No | — |
| **MQ2CustomBinds** | Custom keybinds | Init, Shutdown, SetGameState | No | — |
| **MQ2EQBugFix** | EQ client bug fixes | Init, Shutdown, Pulse | No | — |

### 1.3 Custom Plugins (EMU Clone `plugins/`)

| Plugin | Purpose | CreateLuaModule | TLO |
|--------|---------|-----------------|-----|
| **MQ2CoOptUI** | CoOpt UI native capabilities | **Yes** — only plugin in the entire build | `CoOptUI` |
| **MQ2Mono** | .NET/Mono scripting for E3Next | No | `MQ2Mono` |

### 1.4 Third-Party Plugins (Deployed Only, No Source in Clone)

83 additional DLLs from the E3Next distribution (MQ2Nav, MQ2DanNet, MQ2EQBC, MQ2MoveUtils,
MQ2Cast, MQ2Melee, MQ2Exchange, MQ2SQLite, MQ2Discord, etc.). These are prebuilt and shipped
with the E3Next zip; source is not available in the build environment.

### 1.5 Most Instructive Models for MQ2CoOptUI

| Model Plugin | Why It's Instructive |
|---|---|
| **MQ2Lua** | Definitive reference for the CreateLuaModule contract, sol2 binding patterns, module lifecycle, and how Lua states interact with plugin code. |
| **MQ2ItemDisplay** | Detours `CItemDisplayWnd` and `CSpellDisplayWnd`; demonstrates window hooking, Pulse-based lazy initialization, and safe window pointer management. Pattern for MQ2CoOptUI's window capability. |
| **MQ2AutoBank** | Hooks `CBankWnd::WndNotification`; demonstrates inventory enumeration, `OnPulse`-driven state machines, and window state tracking. Pattern for MQ2CoOptUI's items and window capabilities. |
| **MQ2Bzsrch** | Intercepts bazaar search results via `CBazaarSearchWnd`; demonstrates structured data extraction from EQ windows and delivery to TLO consumers. Pattern for batch data return. |

---

## Section 2 — CreateLuaModule Reference

### 2.1 Function Signature

```cpp
extern "C" PLUGIN_API bool CreateLuaModule(sol::this_state L, sol::object& outModule);
```

- **Parameters:** `sol::this_state L` (current Lua state), `sol::object& outModule` (output — set to the module table)
- **Return:** `true` on success; `false` signals failure (MQ2Lua raises a Lua error)
- **Export:** Must be exported from the DLL. MQ2Lua uses `GetProcAddress(hModule, "CreateLuaModule")`. The `PLUGIN_API` macro handles `__declspec(dllexport)` in the MQ build system.

### 2.2 How `require("plugin.MQ2CoOptUI")` Works — Full Call Path

1. **Lua script** calls `require("plugin.MQ2CoOptUI")`.
2. **LuaJIT** invokes registered package loaders in order.
3. **`LuaThread::PackageLoader`** in MQ2Lua (registered via `add_package_loader` during `Initialize()`) receives `pkg = "plugin.MQ2CoOptUI"`.
4. **Prefix check:** `ci_starts_with(pkg, "plugin.")` → `plugin_name = "MQ2CoOptUI"`.
5. **Plugin lookup:** `GetPlugin("MQ2CoOptUI")` → calls `GetCanonicalPluginName("MQ2CoOptUI")` which strips `MQ2` → canonical name `"CoOptUI"` → looks up in `s_pluginMap` → returns `MQPlugin*`.
6. **Proc lookup:** `GetPluginProc(ownerPlugin->szFilename, "CreateLuaModule")` → `GetProcAddress(hModule, "CreateLuaModule")` → function pointer.
7. **Loader push:** A closure is pushed onto the Lua stack. This closure is called when Lua actually loads the module.
8. **Deferred execution:** The closure re-resolves the plugin (safety: plugin may have been unloaded), calls `AddDependency(plugin)` to tie the Lua script's lifetime to the plugin, then calls `proc(L, out_module)`.
9. **Module return:** `out_module` (the sol2 table built by MQ2CoOptUI) is returned as the result of `require`.

### 2.3 Plugin Name Normalization

`GetCanonicalPluginName` strips:
1. `.dll` extension (case-insensitive)
2. Leading `MQ` or `mq` (2 chars)
3. Leading `2` after MQ (1 char)

Result: `"MQ2CoOptUI"` → `"CoOptUI"`. This means both `require("plugin.MQ2CoOptUI")` and `require("plugin.CoOptUI")` resolve to the same plugin.

### 2.4 sol2 Binding Patterns (from MQ2CoOptUI and MQ2Lua)

**Creating the module table:**
```cpp
sol::state_view lua(L);
sol::table mod = lua.create_table();
```

**Adding sub-tables (capability namespaces):**
```cpp
sol::table ipc_table = lua.create_table();
// ... populate with functions ...
mod["ipc"] = ipc_table;
```

**Binding C++ functions to Lua:**
```cpp
table["functionName"] = [](args...) -> returnType { ... };
// or:
table.set_function("functionName", &cppFunction);
```

**Returning structured data (tables as Lua arrays):**
```cpp
sol::table items = lua.create_table();
for (int i = 0; i < count; ++i) {
    sol::table item = lua.create_table();
    item["name"] = name;
    item["id"] = id;
    // ...
    items.add(item);  // 1-based Lua array
}
return items;
```

### 2.5 Lifetime and Thread Safety Rules

| Rule | Detail |
|------|--------|
| **Single-threaded** | Lua runs on the main EQ thread. OnPulse, CreateLuaModule, and all Lua callbacks execute on the same thread. No synchronization needed for plugin↔Lua data access. |
| **No Lua state access outside CreateLuaModule** | The `sol::this_state` is only valid during the call. Do not cache it. |
| **Dependency tracking** | MQ2Lua calls `AddDependency(plugin)` when a Lua script requires a plugin module. If the plugin is unloaded, MQ2Lua terminates dependent Lua scripts via `OnUnloadPlugin`. |
| **Zone transitions** | MQ TLOs may return nil/invalid during zone transitions. Guard all TLO access. The same applies to window pointers — they may become invalid during zone changes, UI reloads, or character selection. |
| **Data delivery pattern** | For OnPulse-produced data that Lua needs: store in module-level C++ state, expose via bound Lua functions that return the current snapshot. Lua calls these functions from its frame loop. No callbacks from C++ into Lua outside the Lua execution context. |

### 2.6 Built-In vs Plugin Module Factories

| Type | Signature | Registration |
|------|-----------|-------------|
| **Built-in** (mq, ImGui, etc.) | `sol::object (*)(sol::this_state)` | `GetLuaModuleRegistry().Register(name, factory)` in MQ2Lua |
| **Plugin** (MQ2CoOptUI) | `bool (*)(sol::this_state, sol::object&)` | Exported from DLL; discovered via `GetProcAddress` |

The difference: plugin factory uses an out-parameter and returns success/failure. This allows error reporting without throwing across DLL boundaries.

---

## Section 3 — CoOpt UI Capability Gap Analysis

### 3.1 Capability 1: IPC — Macro Bridge Replacement

**Current Lua implementation** (`macro_bridge.lua`, 624 lines):
- File-based IPC via INI files: `sell_progress.ini`, `sell_failed.ini`, `loot_progress.ini`, `loot_session.ini`
- Each read = 3-4 TLO dereferences (`TLO.Ini.File(path).Section(s).Key(k).Value()`)
- Polled at 500ms intervals; progress bar updates read from file every 150ms when fallback active
- Protocol versioning via `[Protocol] Version=1` header in each INI
- Event emission for `sell:started`, `sell:progress`, `sell:complete`, `loot:started`, `loot:complete`

**Cost of current approach:**
- ~12-16 TLO calls per poll cycle (4 per INI key × 3-4 keys)
- 500ms minimum latency for state changes
- File I/O on every write (sell.mac writes progress after each item)
- Race conditions possible: Lua reads while macro writes (no locking)
- INI values truncated at 2048 chars (macro buffer limit)

**Plugin replacement design:**
```lua
-- Lua API (from require("plugin.MQ2CoOptUI").ipc)
ipc.send("sell_progress", "10,5,5")     -- channel, message
ipc.peek("sell_progress")                -- returns latest message or nil
ipc.receive("sell_progress")             -- returns and clears message
ipc.clear("sell_progress")               -- clear channel
```

**C++ implementation:** In-memory `std::unordered_map<std::string, std::string>` keyed by channel name. No file I/O, no size limits, no race conditions (single-threaded). Macros write via `/cooptui ipc send channel message` (slash command). Lua reads via bound functions.

**Implementation complexity:** Low. ~50 lines of C++. No EQ internals needed — pure data storage.

**User-facing impact:** Eliminates sell progress bar flicker; reduces poll latency from 500ms to per-frame (~33ms); removes file I/O during sell/loot operations.

**Lua side readiness:** Complete. `macro_bridge.lua` already checks `pluginShim.ipc()` at every IPC call site (lines 181, 211, 249, 456).

---

### 3.2 Capability 2: Synchronous Window Operations

**Current Lua implementation** (`augment_ops.lua`, `sell_batch.lua`):
- Window clicks via `/notify WindowName ControlName leftmouseup` (string command, processed next frame)
- Window open checks via `mq.TLO.Window(name).Open()` (TLO dereference)
- Window close via `/invoke ${Window[name].DoClose}` (string command)
- Delays: `mq.delay(INSERT_DELAY_MS)`, `mq.delay(REMOVE_OPEN_DELAY_MS)`, `mq.delay(200)` for click settle

**Cost of current approach:**
- Each `/notify` is a string command parsed and executed by MQ — no return value, no error checking
- No way to verify a click was delivered to the correct control
- `mq.delay()` calls block the Lua coroutine, adding ~200-800ms of dead time per augment operation
- Window name resolution requires iterating `DisplayItem(1..6)` with pcall guards

**Plugin replacement design:**
```lua
-- Lua API (from require("plugin.MQ2CoOptUI").window)
window.isWindowOpen("MerchantWnd")                    -- bool, instant
window.click("MerchantWnd", "MW_Sell_Button")         -- direct CXWnd click
window.getText("MerchantWnd", "MW_SelectedItemLabel") -- string
window.waitOpen("ItemDisplayWindow", 500)              -- poll up to 500ms, return bool
window.inspectItem(bag, slot, source)                  -- open Item Display for item
```

**C++ implementation:** Use `FindMQ2Window(name)` and `CXWnd::WndNotification` for clicks. `GetWindowText` for label reads. No `/notify` string parsing, no frame delay for command execution. Augment ops that currently take 3-5 frames (with delays) can execute in a single call.

**Implementation complexity:** Medium. ~120 lines. Requires understanding of MQ2's window system (`FindMQ2Window`, `CXWnd`, `CButtonWnd`, `CSidlScreenWnd`). MQ2ItemDisplay and MQ2AutoBank provide working reference implementations.

**User-facing impact:** Augment insert/remove becomes near-instant (no delay gaps). Sell batch state machine transitions faster. Window state checks are reliable (no TLO nil during zone transitions).

**Lua side readiness:** Complete. `augment_ops.lua` (lines 70-79, 131-135, 198-203) and `sell_batch.lua` (lines 251-256) already check `pluginShim.window()`.

---

### 3.3 Capability 3: Structured Item Data / Batch Scan

**Current Lua implementation** (`scan.lua`, `item_helpers.lua`, `item_tlo.lua`):
- Full inventory scan iterates 10 bags × up to 10 slots each
- Per item: ~15 TLO calls for core fields (Name, ID, Value, Stack, Lore, Quest, Collectible, Heirloom, Attuneable, Type, WornSlots, AugSlots, Clicky, NoDrop, Tribute, Container)
- Plus lazy-loaded stats (AC, HP, Mana, etc.) — additional ~20 TLO calls per item on first access
- Bank scan adds another 24 slots × similar per-item cost
- `buildItemFromMQ` in `item_helpers.lua` constructs each item from individual TLO reads
- Fingerprinting: additional pass to build per-bag fingerprints (ID+Stack per slot)

**Cost of current approach:**
- Full inventory scan: ~1,500-2,000 TLO calls (100 items × 15-20 fields)
- Full bank scan: ~3,000-5,000 TLO calls (24 bags × up to 10 slots × 15 fields)
- Each TLO call crosses the Lua→C++ boundary, resolves a string member name, and returns a typed value
- Profiling shows scans take 10-50ms depending on inventory size
- Fingerprint check (per frame when throttle allows): ~200 TLO calls (10 bags × ~10 slots × 2 fields)
- Incremental scan reduces cost but still does per-item TLO iteration for changed bags

**Plugin replacement design:**
```lua
-- Lua API (from require("plugin.MQ2CoOptUI").items)
local items = items.scanInventory()
-- Returns: Lua table (array of tables), each with all item fields pre-populated
-- { { name="Sword", id=12345, bag=1, slot=3, value=100, stack=1, lore=false, ... }, ... }

local bankItems = items.scanBank()
-- Same structure, source="bank"

local item = items.getItem(bag, slot, source)
-- Single item lookup
```

**C++ implementation:** Direct access to `CharacterBase::GetItemByGlobalIndex` and `ItemDefinition` struct. Build the entire Lua table in one call, iterating the internal item array. No TLO resolution overhead — fields are read directly from the item struct members. Augment socket data, worn slot flags, clicky spell info — all available from the same struct without individual TLO calls.

**Implementation complexity:** High. ~300 lines. Requires understanding of `ItemGlobalIndex`, `ItemDefinition`, `CharacterBase` inventory accessors, and the MQ item struct layout. Must handle equipment, packs, bank, and augment slots correctly. MQ2AutoBank's inventory iteration and MQ2ItemDisplay's item data extraction are reference implementations.

**User-facing impact:** Scan time drops from 10-50ms to <1ms. Eliminates ~2,000 TLO calls per scan. Makes fingerprinting unnecessary — the plugin can detect inventory changes internally. Full bank scan with all augment data becomes instant.

**Lua side readiness:** Complete. `scan.lua` lines 100-112 (inventory) and 307-318 (bank) already check `pluginShim.items()` and accept the plugin return format.

---

### 3.4 Capability 4: Loot Window Event Hook

**Current Lua implementation** (`loot_feed_events.lua`, `main_loop.lua`):
- Uses `mq.event(EVENT_NAME, LINE_PATTERN, callback)` to catch `[ItemUI Loot] name|value|tribute` lines echoed by `loot.mac`
- Events processed via `mq.doevents()` in main_loop phase 5
- Depends on loot.mac formatting the echo correctly — any format change breaks parsing
- Current tab (loot items on corpse) populated only after macro completes (session INI read)
- Real-time feed only appends to Loot History (cumulative), not Current Loot (per-corpse)

**Cost of current approach:**
- Requires loot.mac cooperation (echo formatted strings)
- String pattern matching per chat line (mq.event scans all incoming chat)
- No structured data — name/value/tribute extracted from pipe-separated string
- Cannot detect looted items that loot.mac doesn't echo (e.g., coins, quest items)
- Loot window open/close not detectable in real-time (requires polling TLO)

**Plugin replacement design:**
```lua
-- Lua API (from require("plugin.MQ2CoOptUI").loot)
local events = loot.pollEvents()
-- Returns: array of loot events since last poll, or empty table
-- { { type="item_looted", name="Sword", id=12345, value=100, tribute=50, corpse="a gnoll" }, ... }
-- { { type="loot_window_opened", corpseId=67890 }, ... }
-- { { type="loot_window_closed" }, ... }
```

**C++ implementation:** Hook `CLootWnd::WndNotification` or use OnPulse to poll loot window state. When items are looted, capture item data from the loot slot before it's removed. Store events in a ring buffer; Lua polls and drains it.

**Implementation complexity:** Medium-High. ~150 lines. Requires understanding of `CLootWnd` and its notification messages. The loot window is simpler than merchant/bank — fewer controls, fewer states. MQ2AutoBank's `WndNotification` hook is the closest reference.

**User-facing impact:** Loot events arrive in real-time without depending on loot.mac echo format. Loot window open/close detection becomes event-driven (no polling). Current Loot tab can show items as they're looted, not just after macro completes.

**Lua side readiness:** Partial. `main_loop.lua` phase 5 checks `pluginShim.loot()` but the specific API shape isn't fully wired yet. `loot_feed_events.lua` would remain as a fallback for when the plugin is absent.

---

### 3.5 Capability 5: Native INI Service

**Current Lua implementation** (`config.lua`, 324 lines):
- Reads: `mq.TLO.Ini.File(path).Section(s).Key(k).Value()` — 4 TLO dereferences per read
- Writes: `/ini "path" "section" "key" "value"` — string command, no return value
- Chunked read/write for lists exceeding 2048 chars (up to 20 chunks)
- `safeIniValueByPath` wraps every read in pcall (TLO can be nil during zone transitions)
- 6 INI files across 3 config directories (sell_config, shared_config, loot_config)

**Cost of current approach:**
- ~4 TLO calls per INI read (each level of File→Section→Key→Value is a separate TLO dereference)
- Writes are fire-and-forget — no confirmation the value was written
- Chunked reads multiply the cost (20 keys × 4 TLO calls = 80 TLO calls for a single long list)
- Zone transition safety requires pcall wrapping and fallback defaults
- Loading sell config cache involves ~50-100 INI reads across multiple files

**Plugin replacement design:**
```lua
-- Lua API (from require("plugin.MQ2CoOptUI").ini)
local value = ini.read("path", "section", "key", "default")   -- single call, Win32 direct
ini.write("path", "section", "key", "value")                    -- direct write, returns bool
local section = ini.readSection("path", "section")              -- returns table of key=value
local batch = ini.readBatch("path", {                           -- returns table of results
    { section="Section1", key="Key1", default="" },
    { section="Section2", key="Key2", default="0" },
})
```

**C++ implementation:** `GetPrivateProfileStringA` and `WritePrivateProfileStringA` from Win32. No TLO chain, no macro buffer limits, no pcall needed (C++ handles errors internally). Batch read can process multiple keys in a single Lua→C++ round-trip.

**Implementation complexity:** Low. ~80 lines. Pure Win32 API calls — no EQ internals needed. Simplest capability to implement.

**User-facing impact:** INI reads become ~10x faster (direct Win32 vs 4-level TLO chain). Eliminates zone-transition nil crashes in INI reads. Batch reads reduce Lua→C++ boundary crossings.

**Lua side readiness:** Complete. `config.lua` lines 51-56 (read) and 125-131 (write) already check `pluginShim.ini()`.

---

### 3.6 Newly Identified Capabilities

#### 3.6.1 Cursor State Service

**Problem:** Multiple Lua modules (augment_ops, sell_batch, main_loop) poll `mq.TLO.Cursor.ID()` to detect cursor item presence. This requires a TLO call per frame per consumer.

**Plugin capability:** `cursor.hasItem()`, `cursor.getItemId()`, `cursor.getItemName()` — cached in OnPulse, single read per frame, multiple Lua consumers.

**Complexity:** Trivial. ~20 lines. Cache `pLocalPlayer->GetItemByGlobalIndex(eItemContainerCursor, 0)` in OnPulse.

**Impact:** Minor performance gain; major reliability gain during augment operations.

#### 3.6.2 Inventory Change Notification

**Problem:** `scan.lua` builds bag fingerprints by polling every item's ID and Stack count across all 10 bags every 600ms. This is purely for change detection — the actual data is re-read only when a change is detected.

**Plugin capability:** `items.hasInventoryChanged()` — returns true if any inventory slot changed since last call. Tracked in OnPulse by comparing a lightweight hash of the internal inventory array.

**Complexity:** Low. ~40 lines. Avoids 200 TLO calls per fingerprint check.

**Impact:** Reduces idle-state overhead by ~200 TLO calls per 600ms cycle.

#### 3.6.3 Merchant Window State

**Problem:** `sell_batch.lua` checks `deps.isMerchantWindowOpen()` every frame during sell. This is a TLO call (`Window("MerchantWnd").Open()`).

**Plugin capability:** `window.isMerchantOpen()` — cached bool updated in OnPulse.

**Complexity:** Trivial. Included in window capability with no extra effort.

---

## Section 4 — Implementation Recommendations

### 4.1 Prioritized Implementation Order

| Priority | Capability | Justification |
|----------|-----------|---------------|
| **1** | INI Service | Lowest complexity (~80 LOC). Pure Win32, no EQ internals. Immediately exercises the full CreateLuaModule→Lua pipeline. Proves the plugin works end-to-end. Many call sites — high coverage. |
| **2** | IPC (Macro Bridge) | Low complexity (~50 LOC). No EQ internals. Eliminates file I/O during sell/loot. Removes the most user-visible plugin gap (progress bar flicker). Requires slash command registration for macro→plugin writes. |
| **3** | Window Operations | Medium complexity (~120 LOC). Uses MQ window API (`FindMQ2Window`). Enables faster augment ops and sell batch. Pattern well-established by MQ2ItemDisplay and MQ2AutoBank. |
| **4** | Batch Item Scan | High complexity (~300 LOC). Requires deep MQ item struct knowledge. Highest performance impact (eliminates ~2000 TLO calls per scan). Should be attempted after the simpler capabilities prove the pipeline works. |
| **5** | Loot Event Hook | Medium-High complexity (~150 LOC). Requires CLootWnd understanding. Lower priority because loot_feed_events.lua (mq.event-based) already works adequately. |

### 4.2 EMU-Specific Environment Considerations

| Factor | Impact |
|--------|--------|
| **32-bit (Win32)** | All pointers are 4 bytes. Struct layouts differ from 64-bit Live build. Test with EMU-specific struct offsets. The MQ EMU clone handles this via the `eqlib` submodule on the `emu` branch. |
| **`eqlib` EMU branch** | Item struct (`ItemDefinition`), character struct (`CharacterBase`), and window classes may have different member offsets than Live. Always build against the same eqlib branch the deployment uses. |
| **MQ version pinning** | The deployed MQ runtime (MQ2Main.dll, MQ2Lua.dll from 2026-01-20) MUST match what the plugin was built against. See Section 4.3 for the ABI issue. |
| **EQ client version** | EMU servers run older EQ clients. Some MQ APIs (particularly newer item fields like Heirloom, Collectible) may behave differently. Test each field. |

### 4.3 Critical Issue: ABI Mismatch Between Deployed Plugin and Runtime

**Finding:** The deployed MQ runtime and the plugin were built from different MQ source states:

| Component | Deployed Size | Deployed Date | Build Output Size | Build Output Date |
|-----------|--------------|---------------|-------------------|-------------------|
| MQ2Main.dll | 7,035,392 | 2026-01-20 | 7,281,664 | 2026-02-28 |
| MQ2Lua.dll | 9,953,792 | 2026-01-20 | 11,683,840 | 2026-02-28 |
| MQ2CoOptUI.dll | 1,447,936 | 2026-02-28 | 1,411,072 | 2026-02-28 |

The size differences between deployed and build-output MQ2Main.dll (246KB difference) and MQ2Lua.dll (1.7MB difference) confirm these are different builds. If the MQ source changed between the two build dates, struct layouts and vtable offsets may differ, causing crashes or silent corruption.

**Diagnosis:** The deployed MQ2CoOptUI.dll was likely built against today's MQ source, but deployed alongside MQ2Main.dll from the January build. This is a potential ABI mismatch. The fact that the plugin appears to load (the TLO registers, exports are present) suggests the ABI may be compatible by luck (the plugin's limited API surface doesn't touch changed structs). However, this will become a hard crash when the items or window capabilities access EQ internal structs.

**Fix:** Deploy the COMPLETE build output together. Use `assemble_deploy.ps1` to build a consistent deployment from a single build. Never deploy just MQ2CoOptUI.dll without also deploying MQ2Main.dll, MQ2Lua.dll, and all other plugins from the same build.

### 4.4 Corrections to Previous Understanding

| Misunderstanding | Correction |
|------------------|-----------|
| **"Plugin source at `E3NextAndMQNextBinary-main\plugin\MQ2CoOptUI\`"** | This directory does not exist. Plugin source is directly in both clone directories (`MacroquestEMU/macroquest-clone/plugins/MQ2CoOptUI/` and `MacroquestLive/macroquest-clone/plugins/MQ2CoOptUI/`). The symlink described in docs was never created, or was created and later removed. |
| **"64-bit only distribution"** | The Plugin Master Plan states Option B (own distribution, 64-bit). But the actual build environment is 32-bit EMU (Win32), and all deployed DLLs are x86. The 32-bit path IS working — the "investigate Win32 viability" task (1.1) has been implicitly answered: yes, it works. |
| **"No other plugins implement CreateLuaModule"** | Correct — but this is important context. MQ2CoOptUI is pioneering the use of CreateLuaModule in this deployment. There are no in-tree examples to copy from. The contract must be understood from MQ2Lua's source, not from other plugins. |

### 4.5 Single Plugin vs Multiple Plugins

All five capabilities should remain in a single `MQ2CoOptUI.dll`:

- **Deployment simplicity:** One DLL to build, deploy, and version.
- **Shared OnPulse:** Inventory change detection, window state caching, and loot event polling all benefit from a single OnPulse handler that runs once per frame.
- **Single CreateLuaModule:** Returning one table with five sub-tables (`ipc`, `window`, `items`, `loot`, `ini`) is cleaner than five separate `require` calls.
- **Shared state:** The window capability needs to know if a sell batch is running; the items capability needs to know if a scan was triggered by a sell completion. Cross-capability coordination is simpler within one plugin.

---

## Section 5 — Open Questions

### 5.1 Requires Live Testing

| Question | How to Answer |
|----------|---------------|
| **Does MQ2CoOptUI actually load in the current deployment?** | Check MQ console output on startup. Look for `[MQ2CoOptUI] v1.0.0 loaded (API 1)`. If absent, check `/plugin list` for MQ2CoOptUI. |
| **Does `require("plugin.MQ2CoOptUI")` succeed?** | Run `/lua run itemui` and check for `[CoOpt UI] Plugin MQ2CoOptUI v1.0.0 loaded` (green) vs `CoOptUI TLO present but Lua module not found` (yellow) vs no mention at all. |
| **Is there an ABI crash on load?** | If MQ2CoOptUI appears in `/plugin list` but the Lua module fails, the ABI may be causing a crash during CreateLuaModule. Check MQ crash logs. If MQ2CoOptUI does NOT appear in `/plugin list`, it failed to load entirely. |
| **Do all TLO members work?** | From MQ console: `${CoOptUI.Version}`, `${CoOptUI.APIVersion}`, `${CoOptUI.MQCommit}`, `${CoOptUI.Debug}`. All should return values. |

### 5.2 Requires MQ API Verification

| Question | Detail |
|----------|--------|
| **Is `FindMQ2Window` available in the EMU build?** | It should be (it's in MQ2Main), but verify the function signature matches expectations. Used by window capability. |
| **What is the `ItemDefinition` struct layout in the EMU eqlib?** | The emu branch may have different field offsets than live. Before implementing batch scan, dump the struct layout from the EMU eqlib headers. |
| **Does `CLootWnd` exist and have the expected members in the EMU build?** | The loot window class must be available for the loot event hook. Check `eqlib/CLootWnd.h` or equivalent. |
| **Is `GetPrivateProfileStringA` accessible from the plugin?** | Should be (it's a Win32 API), but confirm no MQ sandbox restrictions. |

### 5.3 Requires Developer Decision

| Decision | Options |
|----------|---------|
| **Should `assemble_deploy.ps1` be the canonical deploy step?** | Currently, MQ2CoOptUI.dll appears to be manually copied. Using the assembly script ensures ABI consistency. Recommend: always use the script, add it to the build checklist. |
| **Should the plugin source live in this repo or the MQ clone?** | The Plugin Master Plan says this repo (`plugin/MQ2CoOptUI/` with symlink). But the source currently lives directly in both clones with no symlink. Recommend: create the symlink as documented, make this repo the single source of truth. |
| **Should stub capabilities return empty tables or nil?** | Currently, all `registerLua` stubs do nothing (don't add any functions to the table). The Lua side checks for specific function existence (e.g., `itemsMod.scanInventory`). This is correct — an empty table means "plugin loaded but capability not implemented yet," which correctly falls through to Lua fallback. No change needed. |
| **Should the plugin register a slash command for macro IPC?** | The IPC capability needs macros to write to channels. Options: (a) `/cooptui ipc send channel message`, (b) macros continue using INI files and the plugin reads them, (c) both. Recommend (a) for sell.mac/loot.mac that run under MQ. |
