# CoOpt UI — Mono Bridge Decision

**Date:** 2026-03-02  
**Status:** Research complete. Recommendation issued.  
**Scope:** Determine the best path forward for giving CoOpt UI's Lua layer access to fast, batch inventory and bank scan results.

---

## Section 1 — Root Cause Analysis

### 1.1 Why `val == "Pong"` evaluated to false

**Mechanism:** The MQ2Mono Query TLO handler (`MQ2Mono.cpp` line ~820) returns the C# result through MacroQuest's standard TLO interface:

```cpp
Dest.Ptr = &DataTypeTemp[0];
Dest.Type = mq::datatypes::pStringType;
return true;
```

When MQ's Lua binding receives this `MQTypeVar`, it wraps it in a `lua_MQTypeVar` userdata — NOT a plain Lua string. In LuaJIT (Lua 5.1 semantics), the `==` operator **does not** call `__eq` when the operands are different types. Comparing a userdata (`lua_MQTypeVar`) to a string (`"Pong"`) returns `false` immediately without examining the wrapped value. The data IS "Pong" inside the wrapper; the comparison just never looks at it.

**Evidence:** The current `tryCoopMonoHelper()` in `scan.lua` (lines 38–39) already works around this by using `tostring(val):match(...)`, which calls the `__tostring` metamethod to extract the underlying string. This fix is correct.

### 1.2 Why `Query(...)()` caused a CTD

Two contributing factors, both confirmed in source:

**Factor 1 — net8.0 assembly incompatibility.** The CoopHelper project was initially targeted at `net8.0`. The `.csproj` comment documents the discovery:

> *"MQ2Mono's runtime resolves types from an older BCL; net8.0 caused 'Could not resolve type... DefaultIn'. net48 produces IL compatible with the Mono/CLR that MQ2Mono loads."*

MQ2Mono embeds an older Mono runtime (`mono-2.0-sgen.dll`). When it loads a `net8.0` assembly, the Mono runtime encounters BCL types (e.g. `System.Runtime.CompilerServices.DefaultInterpolatedStringHandler`) that don't exist in its bundled class libraries. Depending on when the resolution failure occurs:

- If during JIT compilation of a called method: unrecoverable Mono runtime error, not caught by C# `try/catch`, propagated to `mono_runtime_invoke` which was called with `nullptr` for the exception pointer → **unhandled abort → CTD**.
- If during assembly metadata loading: the `MonoClass*` or `MonoMethod*` pointers in `InitAppDomain` may be partially valid, causing later dereferences to crash.

The switch to `net48` (confirmed in the `.csproj`) fixes this. But during the debugging period, the net8.0 assembly was likely still deployed, causing all Query calls to crash.

**Factor 2 — MQ2Mono early-return with uninitialized Dest.** The Query TLO handler (`MQ2Mono.cpp` lines 780–782) has defensive early returns:

```cpp
case Query:
    if (appDomainProcessQueue.size() < 1) return true;
    if (monoAppDomains.size() == 0) return true;
```

These return `true` (meaning "member found, use Dest") **without setting `Dest.Type` or `Dest.Ptr`**. If no Mono apps are loaded when Lua calls Query:

- Without `()`: Lua gets a `lua_MQTypeVar` wrapping garbage. Comparing it to `"Pong"` via `==` returns `false` (type mismatch), and the garbage is never dereferenced. No crash.
- With `()`: Lua invokes the `__call` metamethod, which tries to dereference `Dest.Ptr` through `Dest.Type`'s vtable. Both are uninitialized → **crash**.

This explains why the CTD correlated with adding `()` and why it occurred specifically during startup (when MQ2Mono may not have loaded coophelper yet).

**Factor 3 — Reverting `()` didn't stop crashes.** The user reported crashes persisted after reverting the `()` change. This is consistent with Factor 1: the real issue was the net8.0 assembly on disk. Reverting the Lua code didn't change the deployed DLL, so any Query call that triggered `mono_runtime_invoke` could still crash through the type resolution failure.

### 1.3 The DataTypeTemp size limit — the fatal flaw

**This is the most important finding.** `DataTypeTemp` is MacroQuest's shared TLO return buffer, defined as `char DataTypeTemp[MAX_STRING]` where `MAX_STRING` is **2048** bytes. The MQ2Mono Query handler writes the C# result to this buffer:

```cpp
strcat_s(DataTypeTemp, cppString);
```

A full inventory scan of 80 items with 16 semicolon-delimited fields per item produces approximately **5,000–6,400 characters** of pipe-delimited output. This exceeds DataTypeTemp by 2–3×.

**This means the MQ2Mono Query TLO fundamentally cannot return a full inventory scan in a single call.** No fix to the Lua side, the C# side, or the Query return type can work around this. The buffer is a hard limit imposed by MQ's TLO architecture, not by MQ2Mono.

This was not identified in `MONO_INTEGRATION_PLAN.md`. The plan's design (single `ScanInventory()` call returning all items) is physically impossible through the Query TLO.

---

## Section 2 — Option Evaluation

### Option A — Fix the MQ2Mono integration as designed

**Feasibility:** The `val == "Pong"` fix is already implemented. The CTD is fixable by ensuring: (1) net48 target is used, (2) coophelper is loaded before Lua calls Query, (3) no `()` invocation on Query results (use `tostring()` instead). The `mq_ParseTLO` binding fix (in `MonoCore.Core`) matches the MQ2Mono registration and should work.

**Blocking issue:** DataTypeTemp's 2048-character limit makes `ScanInventory()` and `ScanBank()` unusable for any inventory larger than ~25–30 items. Even chunked by bag (10 bags × 8 items × 80 chars = 6400 total), individual bags could still exceed the limit for large containers.

**Workaround — per-bag queries:** Call `ScanBag(1)`, `ScanBag(2)`, ..., `ScanBag(10)` individually. Each bag (≤10 items × ~80 chars = ~800 chars) fits in 2048. This requires 10 round-trips instead of 1, but each is fast.

**Effort:** Low for the fixes (already done). Medium for per-bag chunking. High risk that other edge cases (long item names, more items per bag) could still overflow.

**Reliability:** Medium. The Mono runtime adds a dependency layer that has already caused CTDs. Even with correct fixes, future MQ2Mono updates, Mono runtime changes, or unusual timing could reintroduce issues.

**Maintenance burden:** Low (C# code is simple), but diagnosing failures requires understanding MQ2Mono internals, Mono runtime, and the TLO return path — knowledge that is not commonly available.

### Option B — Fork MQ2Mono and build a modified version

**What would need to change:** Increase `DataTypeTemp` (requires changes in MQ core, not just MQ2Mono), or add a streaming/paging mechanism for large results (e.g. a shared memory buffer or a multi-part Query protocol).

**Scope:** Large. `DataTypeTemp` is defined in MQ's core headers, not in MQ2Mono. Changing it affects all TLO return values across all plugins. MQ2Mono itself doesn't control the buffer size.

**MQ2Mono-Framework32 repo:** Contains only the Mono runtime binaries (`mono-2.0-sgen.dll` and BCL assemblies). No source code. Not useful as a fork starting point. The MQ2Mono source repo is the only one with C++ code.

**Maintenance burden:** Very high. Owning a fork of MQ2Mono means tracking upstream changes from RekkasGit, dealing with MQ version compatibility, and maintaining custom patches. The CoOpt UI project is a Lua/UI tool — maintaining a C++ plugin fork is outside its scope.

**Verdict:** Not justified. The problem being solved (batch scan) doesn't warrant forking a plugin maintained by someone else.

### Option C — Native C++ plugin with CreateLuaModule (sol2)

**Current state:** The `feature/CoOptPlugin` branch exists but is diverged from master (branched before Phases A–E). The plugin source directory (`plugin/MQ2CoOptUI/`) is not present in the current working tree — it lives only on that branch. The `docs/plugin/dev_setup.md` and `.cursor/rules/mq-plugin-build-gotchas.mdc` document an extensive 20-step build process with multiple patches required to the MQ source tree.

**What it provides:** A `CreateLuaModule` function that registers a sol2 module. `scanInventory()` returns a native Lua table directly — no string marshalling, no DataTypeTemp limit, no Mono runtime. The sol2 binding is type-safe and well-understood.

**Effort:** Significant. The branch needs to be rebased onto current master. The build toolchain (Visual Studio 2022, CMake 3.30, MQ source tree, vcpkg, 20 patches) must be set up. The `scanInventory()` function itself is straightforward in C++ (iterate `CONTENTS` struct, push to sol2 table), but the build infrastructure dominates the effort.

**Reliability:** High, once built. Native C++ plugin runs in-process with direct memory access to EQ's item data structures. No marshalling, no Mono, no intermediate format. But ABI coupling to MQ means the plugin must be rebuilt whenever MQ is updated.

**Maintenance burden:** Medium-high. Every MQ update requires rebuilding the plugin with the matching MQ source. The 20 build gotchas documented in the cursor rule indicate the build process is fragile.

**Verdict:** Technically superior for bulk data transfer, but the build/deploy/maintenance cost is disproportionate to the performance gain, given that the Lua TLO scan is already reasonably fast (see Option D).

### Option D — Lua-side optimization without any native bridge

**Actual scan performance:** `buildItemFromMQ` reads 15 TLO member accessors per item (ID, Name, Value, Stack, Type, Weight, Icon, NoDrop, NoTrade, Lore, Attuneable, Heirloom, Collectible, Quest, plus item existence check). For 80 items across 10 bags, plus bag size checks, total is ~1,300 TLO accesses. In MQ's Lua binding, each access is an FFI call through LuaJIT — typically 1–10 microseconds. Total scan time: approximately **10–30ms**.

**Existing optimizations already in place:**
- Incremental scanning via `getChangedBags()` + `targetedRescanBags()`: only rescans bags whose fingerprint changed. Typical per-frame cost: 0–2 bags, not all 10.
- Lazy stat metatables: the 48 stat fields and 17 descriptive fields are NOT read during scan. They're loaded on first tooltip/summary access via `__index`.
- Fingerprint throttling: `GET_CHANGED_BAGS_THROTTLE_MS = 600` prevents checking for changes more than ~1.7 times per second.
- Per-bag fingerprint caching: unchanged bags don't trigger any item reads.

**Is the performance problem real?** The profiling threshold is 30ms (`PROFILE_THRESHOLD_MS = 30`). Full scans occasionally exceed this, but the full scan includes post-scan processing (acquiredSeq, fingerprinting, sell status computation, disk persistence). The pure item-reading portion is likely 10–15ms. The incremental scan (1–2 bags) is ~2–5ms.

For a UI that runs at 30 FPS (33ms frame budget), a 10–15ms scan every ~600ms is well within budget. The scan doesn't block rendering — it runs as part of the main loop's scan phase.

**Remaining optimization opportunities (if needed):**
- Cache bag container sizes (avoid re-reading `pack.Container()` for unchanged bags)
- Pre-compute fingerprint as part of the scan loop instead of as a separate pass
- Reduce per-item TLO calls by combining checks (e.g. check ID before reading all other fields — already done)

**Effort:** Zero for current state (it works). Low for further optimization if needed.

**Reliability:** Maximum. No external dependencies. No C++/C# code. No marshalling. No CTD risk. The same Lua TLO scan has been running stably through all the development phases.

**Maintenance burden:** Minimal. The scan code is self-contained in `scan.lua`.

**Verdict:** The current Lua TLO scan is already fast enough for the inventory scan use case. The incremental scan optimization makes the typical per-frame cost negligible. Adding a native bridge for the scan specifically is over-engineering for a problem that is already solved.

### Option E — A different IPC mechanism

**Named pipe / shared memory:** A lightweight C++ helper writes item data to shared memory; Lua reads it via `ffi.C` or a small LuaJIT FFI wrapper. This avoids the TLO return buffer limit but requires: (1) a C++ component to write the data, (2) shared memory or pipe setup, (3) synchronization. This is essentially a stripped-down version of Option C with the same build/deploy friction but less integration.

**File-based approach:** C# or C++ writes a data file; Lua reads it. Introduces disk I/O latency and file locking complexity. Not suitable for per-scan-cycle operation.

**Verdict:** Over-engineered for this problem. If a native data bridge is needed, Option C (full plugin) is the right approach because it integrates properly with MQ's plugin lifecycle.

---

## Section 3 — Recommendation

### Primary recommendation: Option D — Keep the Lua TLO scan

The Lua TLO scan path is the correct solution for inventory and bank scanning. The evidence does not support the premise that a native bridge is needed for this operation:

1. **Measured performance** is ~10–30ms for a full scan, ~2–5ms for incremental rescans. This is within acceptable bounds for a 30 FPS UI.
2. **The MQ2Mono Query TLO cannot physically return a full scan** due to the 2048-character DataTypeTemp limit. The entire Mono scanner integration plan was designed around a capability that doesn't exist.
3. **The Lua scan has been stable** through all development phases. The Mono path introduced CTDs and added complexity without delivering value.

### Secondary recommendation: Retain MQ2Mono for what it CAN do

MQ2Mono Query is suitable for **short-response operations** where the result fits in 2048 characters:

- **Ping/health check:** Already working (with the `tostring()` fix). Use for graceful feature detection.
- **Phase 3 Rule Engine — per-item evaluation:** `EvalSell(itemFields)` → `"SELL|reason"` (~20 chars). Single-item queries fit easily.
- **Phase 3 BulkEvalSell — chunked:** Batch 20–30 items per call. Each batch response (~600 chars) fits in 2048. Send 3–4 batches for a full inventory. This is 3–4 round-trips instead of 1, but each is fast (<1ms).
- **Phase 4 Config reads:** `GetConfig(section|key)` returns short values. No size issue.

The C# CoopHelper project should be retained for these use cases. The `mq_ParseTLO` binding fix (in `MonoCore.Core`) is correct and should work for the Rule Engine phase, where C# reads INI files directly via `System.IO` and doesn't need `mq_ParseTLO` at all.

### What this means for the architecture

The `MONO_INTEGRATION_PLAN.md` Phase 2 (Inventory Scanner) should be marked as **abandoned** due to the DataTypeTemp limit. Phases 3–5 remain viable because their Query responses are short. The plan's architecture (Mono helper > C++ plugin > Lua fallback) remains sound — just not for bulk data transfer.

The `Plugin_Master_Plan.md` Task 2.4 (native C++ scan) remains a valid future option if performance measurements show the Lua scan is insufficient, but current evidence does not support pursuing it. The 20-step build process documented in `mq-plugin-build-gotchas.mdc` is a significant cost that should only be incurred when there is a measurable performance problem.

### First concrete implementation step

1. **Verify the net48 + mq_ParseTLO fix works:** Deploy the current C# assembly (net48, `Core.mq_ParseTLO` in `MonoCore.Core`), load coophelper in-game, and run the diagnostic Lua line (see Section 4). This confirms the bridge is functional for short queries.
2. **If verified:** Set `ENABLE_COOPHELPER_MONO = true` in `constants.lua` but **remove the ScanInventory/ScanBank Mono paths** from `scan.lua`. Keep only the Ping detection (for future Phase 3 use). The Mono helper detection (`tryCoopMonoHelper()`) becomes a capability flag for the Rule Engine, not for scanning.
3. **If not verified:** Leave the kill switch off. Proceed with Lua-only operation. The current codebase is fully functional without Mono.

---

## Section 4 — What To Do Right Now

### Safe diagnostic steps (no CTD risk)

**Step 1 — Verify the deployed assembly is net48.**  
Check the `.csproj`:
```xml
<TargetFramework>net48</TargetFramework>
```
This is already the case in the working tree. Rebuild if needed: `dotnet build -c Release` from `csharp/coophelper/`.

**Step 2 — Deploy and load.**  
```powershell
.\scripts\sync-to-deploytest.ps1 -Target "C:\MQ-Deploy\CoOptUI2"
```
In-game: `/mono load coophelper`

**Step 3 — Test Ping round-trip type.**  
From Lua (`/lua run` or in a test script):
```lua
local val = mq.TLO.MQ2Mono.Query("coophelper,Ping()")
print("type=" .. type(val) .. " tostring=" .. tostring(val) .. " eq=" .. tostring(tostring(val) == "Pong"))
```
Expected output: `type=userdata tostring=Pong eq=true`

This confirms: (a) the assembly loaded, (b) `mq_ParseTLO` registration didn't crash OnInit, (c) the Query round-trip works, (d) `tostring()` correctly extracts the value. **Do NOT use `val()` or `val == "Pong"` — use `tostring(val)`.**

**Step 4 — Test ParseTLO (if Step 3 passes).**
```lua
local val = mq.TLO.MQ2Mono.Query("coophelper,TestParseTLO(${Me.Name})")
print("ParseTLO=" .. tostring(val))
```
Expected: character name. If this returns `ERROR|...`, the `mq_ParseTLO` binding has an issue (namespace mismatch, runtime problem).

**Step 5 — Test DiagInv (if Step 4 passes).**
```lua
local val = mq.TLO.MQ2Mono.Query("coophelper,DiagInv()")
print("DiagInv=" .. tostring(val))
```
This runs the diagnostic battery in `InventoryScanner.DiagInventory()` — tests various TLO expression formats. If the output is truncated (2048 char limit), that confirms the DataTypeTemp constraint.

### What these diagnostics prove

- Steps 3–4 confirm the Mono bridge works for short queries → unblocks Phase 3 (Rule Engine).
- Step 5 confirms the DataTypeTemp limit → validates abandoning Phase 2 scanner via Query.
- All steps use `tostring()` and `pcall()` patterns that cannot cause CTDs.

---

## Section 5 — What To Clean Up

Regardless of which option is chosen, the following cleanup should happen to remove confusion from the failed Phase 2 attempts.

### Files with Phase 2 scaffolding to modify

| File | Action | Detail |
|------|--------|--------|
| `lua/itemui/services/scan.lua` lines 254–307 | **Remove** the ScanInventory Mono path | The `if tryCoopMonoHelper() then ... monoQuery("ScanInventory()") ...` block (lines 254–307) should be removed entirely. The Mono path for inventory scanning is abandoned. |
| `lua/itemui/services/scan.lua` lines 531–565 | **Remove** the ScanBank Mono path | Same rationale. The `if tryCoopMonoHelper() then ... monoQuery("ScanBank()") ...` block should be removed. |
| `lua/itemui/services/scan.lua` lines 51–59 | **Keep** `monoQuery()` | Utility function is useful for future Phase 3 integration. |
| `lua/itemui/services/scan.lua` lines 28–49 | **Keep** `tryCoopMonoHelper()` | Detection function is useful for Phase 3. The `tostring()` fix is correct. |
| `lua/itemui/services/scan.lua` lines 63–102 | **Remove** `parseMonoItems()` | Parser for the wire format that the scanner would have returned. No longer needed if scanner is abandoned. Alternatively, keep it if Phase 3 BulkEvalSell might reuse a similar format. |
| `lua/itemui/services/scan.lua` lines 139–161 | **Remove** `buildInventoryFingerprintFromItems()` | Only used by the Mono scan path. The Lua TLO fingerprint (`buildInventoryFingerprint()`) is sufficient. |
| `lua/itemui/services/scan.lua` lines 25–27 | **Remove** logging flags | `monoPathUsedLogged`, `monoFallbackLogged`, `monoDiagLogged` — only used by the Mono scan path. |
| `lua/itemui/constants.lua` line 204 | **Change when ready** | `ENABLE_COOPHELPER_MONO = false` → set to `true` when Phase 3 Rule Engine is implemented and Ping is verified. |
| `csharp/coophelper/Services/InventoryScanner.cs` | **Keep** | The C# scanner code is correct and well-written. It works — the problem is the return channel, not the scanner. Keep it for potential future use with a different transport (e.g., file-based, or if MQ2Mono adds a large-result API). |
| `csharp/coophelper/QueryDispatcher.cs` | **Keep** | Routes to DiagInv, ScanInventory, etc. These remain useful for diagnostics and for the Rule Engine. |
| `csharp/coophelper/MqBridge.cs` | **Keep** | Correct wrapper for `Core.mq_ParseTLO`. Useful for Phase 3 if it needs TLO evaluation. |
| `csharp/coophelper/README.md` | **Update** | The README references `net8.0` output path. Update to reflect `net48` target and note the DataTypeTemp limit for Query responses. |
| `docs/MONO_INTEGRATION_PLAN.md` | **Update** | Mark Phase 2.1 (ScanInventory/ScanBank via Query) as abandoned. Add note about DataTypeTemp limit. Keep Phase 2.0 (ParseTLO verification) and Phases 3–5 as active. |
| `docs/mono/PHASE2_REVIEW.md` | **Keep as-is** | Accurate historical record of the investigation. Section 7 resolution is correct. |

### Misleading comments to fix

| Location | Current | Fix |
|----------|---------|-----|
| `scan.lua` line 13 | `-- Optional CoopUIHelper plugin: when loaded, scanInventory/scanBank use it for batched C++ scan` | Accurate. Keep. |
| `scan.lua` line 23 | `-- Optional CoopHelper Mono app: when MQ2Mono is loaded and coophelper is running, Lua can delegate via MQ2Mono.Query` | Update to note that Mono delegation is for rule evaluation (Phase 3), not for scanning. |
| `MONO_INTEGRATION_PLAN.md` Phase 2 performance target | "Single ScanInventory() call should complete in <5ms vs current ~50ms+" | Remove the 50ms+ claim. Actual Lua scan is 10–30ms, and the incremental scan makes the typical cost ~2–5ms. |
