# Phase 2 Mono Integration — Technical Review

**Review date:** 2026-03-02  
**Reviewer:** Senior technical review (pre-implementation validation)  
**Scope:** Phase 2 of MONO_INTEGRATION_PLAN.md — Inventory & Bank Scanner  
**Status:** Root cause identified and fixed. Ready for in-game verification.

---

## Section 1 — Current State Assessment

### 1.1 What Phase 1 Delivered (and its state)

Phase 1 is **complete and verified working**:

| Component | Location | State |
|-----------|----------|-------|
| C# project scaffold | `csharp/coophelper/` | Present, builds successfully |
| CoopHelper.csproj | `csharp/coophelper/CoopHelper.csproj` | net8.0, builds to `bin/Release/net8.0/CoopHelper.dll` |
| Core.cs | `csharp/coophelper/Core.cs` | MonoCore.Core lifecycle (OnInit, OnQuery, OnPulse, OnStop) |
| QueryDispatcher.cs | `csharp/coophelper/QueryDispatcher.cs` | Dispatches Ping, ScanInventory, ScanBank, GetInventoryFingerprint |
| PingService.cs | `csharp/coophelper/Services/PingService.cs` | Returns "Pong" |
| Build script | `scripts/build-coophelper.ps1` | Builds and optionally deploys to `Mono/macros/coophelper/` |
| Lua integration | `lua/itemui/services/scan.lua` | `tryCoopMonoHelper()` checks `MQ2Mono.Query("coophelper,Ping()")` for "Pong" |
| Constants | `lua/itemui/constants.lua` | `MONO_HELPER_APP_NAME = "coophelper"` |

**Verification (from commit message):** "Verified: /mono load coophelper and UI (sell, bank, inventory) with no added latency."

### 1.2 What Phase 2 Attempted (and where it failed)

Phase 2 attempted to implement the Inventory & Bank Scanner:

| Component | Location | State |
|-----------|----------|-------|
| InventoryScanner.cs | `csharp/coophelper/Services/InventoryScanner.cs` | **Implemented** — ScanInventory(), ScanBank(), GetInventoryFingerprint() |
| MqBridge.cs | `csharp/coophelper/MqBridge.cs` | **Implemented** — `ParseTLO(string expr)` with `[MethodImpl(InternalCall)]` |
| Lua parser | `lua/itemui/services/scan.lua` | **Implemented** — `parseMonoItems()`, `monoQuery()`, full ScanInventory/ScanBank Mono paths |
| QueryDispatcher | `csharp/coophelper/QueryDispatcher.cs` | **Modified** — routes to InventoryScanner |

**Failure mode:** When Lua calls `ScanInventory()` or `ScanBank()`, the C# side returns `ERROR|...` (or empty), and Lua falls back to the TLO-based scan. The diagnostic messages in scan.lua (`monoDiagLogged`, `monoFallbackLogged`) indicate the previous agent observed this and added one-time logging.

### 1.3 Current Codebase State

**Branch:** `dev/C#Test` (ahead of `bea8354` Phase 1 commit)

**Uncommitted changes:**
- Modified: `QueryDispatcher.cs`, `README.md`, `lua/itemui/app.lua`, `lua/itemui/services/scan.lua`, `lua/itemui/utils/item_helpers.lua`
- Untracked: `MqBridge.cs`, `Services/InventoryScanner.cs`, `scripts/sync-to-deploytest.ps1`

**What is present:**
- Full Phase 1 (Ping) working
- Full Phase 2 C# implementation (InventoryScanner, MqBridge)
- Full Phase 2 Lua integration (parseMonoItems, Mono scan paths in scanInventory/scanBank)
- Graceful fallback: when C# returns ERROR or empty, Lua uses TLO-based scan

**What is broken:**
- `ScanInventory()` and `ScanBank()` return `ERROR|...` instead of item data
- Root cause: `MqBridge.ParseTLO(expr)` fails — the InternalCall is not registered by MQ2Mono

**What is partially implemented:**
- `GetInventoryFingerprint()` — same dependency on ParseTLO; not yet wired into Lua's fingerprint logic (Lua still uses `buildBagFingerprint` / `buildInventoryFingerprint`)

---

## Section 2 — Root Cause of Phase 2 Failures

### 2.1 Primary Root Cause: ParseTLO Is Not Provided by MQ2Mono

The Phase 2 implementation assumes MQ2Mono exposes a native method for C# to evaluate TLO expressions. The implementation uses:

```csharp
// MqBridge.cs
[MethodImpl(MethodImplOptions.InternalCall)]
public static extern string ParseTLO(string expr);
```

An `InternalCall` requires the **native host (MQ2Mono)** to register it via `mono_add_internal_call()` when the assembly loads. The C# runtime does not provide this — it is a bridge that the embedding application must implement.

**Evidence:**
1. MONO_INTEGRATION_PLAN.md §2.1 says "Uses `mq_ParseTLO`" but does not cite MQ2Mono documentation or source confirming this API exists.
2. The CoopHelper README explicitly states: "If your MQ2Mono build does not register it, those commands return `ERROR|...` and Lua falls back to TLO-based scan."
3. No MQ2Mono source was found in this repo or in `c:\MIS` to verify what internal calls it registers.
4. Web search and MacroQuest docs do not document a `ParseTLO` or `mq_ParseTLO` API for MQ2Mono C# assemblies.

**Conclusion:** The plan assumed an API that was never verified. MQ2Mono may not expose TLO evaluation to C# at all. When `InventoryScanner` calls `MqBridge.ParseTLO(expr)`, the CLR fails to resolve the internal call (MissingMethodException or equivalent), the exception is caught, and the method returns `"ERROR|" + ex.Message`.

### 2.2 Secondary Contributing Factors

1. **No pre-Phase-2 verification step:** The plan should have included a spike to verify that C# can evaluate a single TLO expression (e.g. `Me.Name()`) before implementing the full scanner. Phase 1.2 verified Ping; there was no equivalent "ParseTLO spike" for Phase 2.

2. **Plan did not mandate MQ2Mono API research:** The plan says "Uses mq_ParseTLO" without specifying where this comes from, how to verify it, or what to do if it does not exist.

3. **Index convention:** The C# code uses 1-based slot iteration (`for (int slot = 1; slot <= container; slot++)`) for `Me.Inventory("packN").Item(slot)`. Per the macroquest-indexing rule, `item.Item(N)` is 1-based for "Nth slot" — this is correct. No indexing bug identified.

---

## Section 3 — Plan Validation

### 3.1 Executive Summary and Architecture (MONO_INTEGRATION_PLAN.md lines 1–76)

**Assessment:** Correct. The architecture (MQ2Mono loads C# DLL, Lua calls via Query TLO, fallback pattern) is sound. The dependency on MQ2Mono is explicit.

**Amendment needed:** Add an explicit warning that Phase 2 depends on MQ2Mono exposing TLO evaluation to C#, and that this must be verified before implementation.

### 3.2 Phase 1 (lines 78–131)

**Assessment:** Correct and complete. Phase 1 was executed successfully.

**No amendment needed.**

### 3.3 Phase 2.1 — C# Inventory Scanner (lines 141–156)

**Assessment:** The design (ScanInventory, ScanBank, GetInventoryFingerprint returning delimited strings) is correct. The **dependency** on `mq_ParseTLO` is the flaw.

**Amendment required:**

Replace:
> 1. Uses `mq_ParseTLO` to read all 10 inventory bags and their slots.

With:
> 1. **Prerequisite:** Verify that MQ2Mono exposes TLO evaluation to C# (see Phase 2.0 spike below). If not available, Phase 2.1 cannot be implemented as written; use Alternative B (Lua→C# data flow) or defer until MQ2Mono supports it.
> 2. Uses the verified TLO bridge (e.g. `MqBridge.ParseTLO` or equivalent) to read all 10 inventory bags and their slots.

Add new **Phase 2.0 — ParseTLO Verification Spike** before Phase 2.1:
- Create a minimal C# method that evaluates one TLO (e.g. `Me.Name()` or `Me.Inventory("pack1").Container()`).
- Use `[MethodImpl(InternalCall)]` or whatever API MQ2Mono documents.
- Deploy, load coophelper, call from Lua via a test query (e.g. `TestParseTLO("Me.Name()")`).
- **Success criteria:** Returns the character name (or a non-empty string). If it fails, do not proceed with Phase 2.1 until the API is confirmed or an alternative is chosen.

### 3.4 Phase 2.2 — Lua Parser + Integration (lines 158–174)

**Assessment:** Correct. The Lua side is fully implemented and works correctly when C# returns valid data.

**No amendment needed.**

### 3.5 Phase 2.3 — Optional Batch Stat Snapshot (lines 176–183)

**Assessment:** Same dependency on TLO evaluation. Blocked until ParseTLO is available.

**Amendment:** Add dependency note: "Requires Phase 2.0 ParseTLO verification to pass."

### 3.6 Build & Deploy (lines 336–368)

**Assessment:** Correct. Build script and deploy path are accurate.

**No amendment needed.**

### 3.7 Risk Register (lines 458–469)

**Assessment:** Risk M1 (MQ2Mono version incompatible) is relevant but does not cover "MQ2Mono does not expose ParseTLO."

**Amendment:** Add risk:
> **M8** | MQ2Mono does not expose TLO evaluation to C# (no ParseTLO/mq_ParseTLO) | High | High — Phase 2 blocked | Phase 2.0 spike verifies before implementation. If absent, use Alternative B (Lua sends item data to C# for rule eval) or contribute ParseTLO to MQ2Mono upstream.

---

## Section 4 — Missing Considerations

### 4.1 MQ2Mono API Surface — Not Researched

**What:** The plan never established what APIs MQ2Mono actually exposes to loaded C# assemblies.

**Why it matters:** Phase 2 implementation coded against an assumed API. If MQ2Mono only provides OnQuery (command dispatch) and not TLO evaluation, the scanner cannot work as designed.

**What to do:** Before any Phase 2 implementation:
1. Obtain MQ2Mono source (from E3Next build, MacroQuest plugins, or upstream).
2. Search for `mono_add_internal_call`, `InternalCall`, or any registration of C#-callable native methods.
3. Document the exact method signatures and names (e.g. `MonoCore.MqBridge::ParseTLO`).
4. If no TLO evaluation exists, document that and choose an alternative (see Section 5).

### 4.2 C# Assembly Deployment Path

**What:** The plan says deploy to `Mono/macros/coophelper/` but does not specify how this fits into the patcher, release zip, or sync script.

**Why it matters:** Users who install via patcher or release zip may not get CoopHelper.dll unless it is explicitly included.

**What to do:** Add to the plan: (a) Include `CoopHelper.dll` in the sync-to-deploytest script (already present per workspace rules). (b) Document whether the release zip/patcher includes the C# DLL or if it is optional (user builds and deploys manually).

### 4.3 Version Compatibility Between C# and Lua

**What:** If the C# wire format changes (e.g. field order, new fields), Lua's `parseMonoItems` may break.

**Why it matters:** Silent data corruption or parse failures.

**What to do:** Add a version or format marker: e.g. first field could be a format version. Lua validates before parsing. Document the compatibility contract in the plan.

### 4.4 Missing C# Assembly at Runtime

**What:** If CoopHelper.dll is missing from `Mono/macros/coophelper/`, `/mono load coophelper` fails. Lua's `tryCoopMonoHelper()` already handles this — Ping fails, fallback to Lua.

**Assessment:** Already handled. No change needed.

### 4.5 Mono Configuration Files

**What:** The plan does not mention `machine.config`, `mono/config`, or other Mono runtime config.

**Why it matters:** Some Mono embeddings require config for assembly resolution or BCL paths.

**What to do:** For MQ2Mono, this is the plugin's responsibility. Document in the plan: "MQ2Mono manages Mono config. If assembly load fails, check MQ2Mono documentation." No implementation change in CoopHelper.

---

## Section 5 — Corrected Phase 2 Implementation Plan

### Phase 2.0 — ParseTLO Verification Spike (NEW — MUST RUN FIRST)

**Goal:** Prove that C# can evaluate MQ2 TLO expressions before building the full scanner.

**Steps:**

1. **Research MQ2Mono API**
   - Locate MQ2Mono source (E3Next Mono folder, MQ plugins, or upstream).
   - Search for: `mono_add_internal_call`, `InternalCall`, `EvaluateData`, `ParseTLO`, `MQ.Query`, or similar.
   - Document: method name, signature, and registration pattern.
   - **If no TLO API exists:** Stop. Proceed to Alternative B (Section 5.1) or document as blocked.

2. **Implement minimal test**
   - Add `TestParseTLO(string expr)` to QueryDispatcher, returning the result of one TLO evaluation.
   - Use the exact API discovered in step 1 (e.g. `MqBridge.ParseTLO` with `[MethodImpl(InternalCall)]`).
   - Build, deploy, `/mono load coophelper`.

3. **Verify in-game**
   - From Lua: `mq.TLO.MQ2Mono.Query("coophelper,TestParseTLO(Me.Name())")()`.
   - **Success:** Returns character name.
   - **Failure:** Returns ERROR or empty. Do not proceed to Phase 2.1.

**Effort:** 2–4 hours (including research).

**Verification:** Lua receives a non-empty, non-ERROR string from `TestParseTLO("Me.Name()")`.

---

### Phase 2.1 — C# Inventory Scanner (REVISED)

**Prerequisite:** Phase 2.0 passed.

**Steps:**

1. Implement `InventoryScanner.ScanInventory()` using the verified TLO bridge.
2. Match the wire format exactly: `bag;slot;id;name;value;stackSize;type;weight;icon;nodrop;notrade;lore;attuneable;heirloom;collectible;quest|...`
3. Implement `ScanBank()` and `GetInventoryFingerprint()`.
4. Add format version or validation (e.g. field count check) for future compatibility.
5. Handle edge cases: empty inventory, null TLO returns, semicolons in item names (escape to comma per existing `EscapeName`).

**Verification:** In-game, with inventory open, `ScanInventory()` returns a non-empty pipe-delimited string. Lua `parseMonoItems` produces a table matching `buildItemFromMQ` shape. Item count matches game inventory.

---

### Phase 2.2 — Lua Parser + Integration (UNCHANGED)

Already implemented. Verify:
- `parseMonoItems` handles empty, ERROR, and valid input.
- Scan path uses `env.setLazyStatsMetatable` when present.
- Fingerprint from items: `buildInventoryFingerprintFromItems` is used when Mono path succeeds.

---

### Alternative B — If ParseTLO Does Not Exist

**Restructure Phase 2–3:** C# does not read TLO. Instead:

1. **Phase 2 deferred:** Scan stays in Lua (current behavior).
2. **Phase 3 (Rule Engine) first:** C# reads INI files from disk, parses rules, exposes `EvalSell`, `BulkEvalSell`, etc. Lua sends item data as a string (e.g. pipe-delimited) to C# for evaluation. C# returns `SELL|reason` or `KEEP|reason`. No TLO needed.
3. **Phase 4 (Config) same:** C# reads/writes INI via `System.IO`. No TLO needed.

This delivers the "biggest reliability win" (Phase 3) and "config I/O win" (Phase 4) without requiring MQ2Mono to expose ParseTLO. Phase 2 (scan) remains Lua until MQ2Mono gains TLO support or the C++ plugin path is revived.

---

## Section 6 — Open Questions

### Q1. Does MQ2Mono expose ParseTLO or equivalent?

**What:** Whether MQ2Mono registers any internal call for TLO evaluation.

**How to answer:** Inspect MQ2Mono source. Search for `mono_add_internal_call` and the method names it registers.

**Blocks:** Phase 2.1. Must be answered before implementation.

---

### Q2. Where is the MQ2Mono source for this E3Next build?

**What:** The exact path or repo containing the MQ2Mono plugin used by the E3Next distribution.

**How to answer:** Check E3Next repo structure, `Mono/` folder, or build scripts. The mq-plugin-build-gotchas rule says "clone into plugins/MQ2Mono" — implies it may be a separate add-on to the MQ build.

**Blocks:** Q1. Needed to answer Q1.

---

### Q3. What is the exact InternalCall registration signature?

**What:** If MQ2Mono does register a TLO eval method, the C# method must match the native registration exactly (namespace, class name, method name).

**How to answer:** From MQ2Mono source, find the `mono_add_internal_call` call and the string passed (e.g. `"MonoCore.MqBridge::ParseTLO"`).

**Blocks:** Phase 2.1 implementation. Can be answered in parallel with Phase 2.0 spike.

---

### Q4. Does the E3Next Mono runtime support .NET 8?

**What:** Phase 1 used net8.0 and verified. If the runtime is older Mono (e.g. 6.x), some .NET 8 features might cause issues.

**How to answer:** Phase 1.2 already verified Ping works. If Phase 2.0 fails, consider retrying with net48 or net6.0 to rule out runtime mismatch.

**Blocks:** Only if Phase 2.0 fails with net8.0.

---

### Q5. Should CoopHelper.dll be included in the sync-to-deploytest script?

**What:** The workspace rule says sync Lua, Macros, resources, and C# coophelper. The sync script exists but may not yet copy CoopHelper.dll.

**How to answer:** Read `scripts/sync-to-deploytest.ps1` and verify it deploys `CoopHelper.dll` to the target's `Mono/macros/coophelper/`.

**Blocks:** Developer workflow. Can be done in parallel.

---

## Summary

| Finding | Severity |
|---------|----------|
| ParseTLO not verified / not provided by MQ2Mono | **Critical** — blocks Phase 2.1 |
| No Phase 2.0 verification spike in plan | **High** — caused blind implementation |
| Plan assumed mq_ParseTLO without citation | **High** — architectural assumption unvalidated |
| Alternative B (defer scan, do rules first) not in plan | **Medium** — recovery path if ParseTLO absent |

**Recommendation:** Do not resume Phase 2 implementation until Phase 2.0 (ParseTLO verification spike) is complete and passes. If ParseTLO does not exist, adopt Alternative B and reorder phases to deliver Phase 3 (Rule Engine) and Phase 4 (Config) first.

---

## Section 7 — Resolution (2026-03-02)

### Root Cause Confirmed and Fixed

**MQ2Mono source located:** [RekkasGit/MQ2Mono](https://github.com/RekkasGit/MQ2Mono). The plugin **does** register TLO evaluation:

```cpp
mono_add_internal_call("MonoCore.Core::mq_ParseTLO", &mono_ParseTLO);
```

**The bug:** CoopHelper used `MqBridge.ParseTLO` with `[MethodImpl(InternalCall)]`. MQ2Mono registers the binding on **`MonoCore.Core::mq_ParseTLO`** — the method must live in the `Core` class with the exact name `mq_ParseTLO`, not in a separate `MqBridge` class as `ParseTLO`.

### Changes Applied

1. **Core.cs:** Added `mq_ParseTLO(string expr)` with `[MethodImpl(InternalCall)]` — matches MQ2Mono registration.
2. **MqBridge.cs:** Changed from extern to wrapper: `ParseTLO(expr) => Core.mq_ParseTLO(expr)`.
3. **QueryDispatcher.cs:** Added `TestParseTLO(expr)` for Phase 2.0 verification.
4. **MONO_INTEGRATION_PLAN.md:** Added Phase 2.0 spike, prerequisite notes, risk M8, deployment/sync note.

### Verification Required (User)

1. **Deploy** the updated CoopHelper to your DeployTest install:
   ```powershell
   .\scripts\sync-to-deploytest.ps1 -Target "C:\MIS\MacroquestEnvironments\DeployTest\CoOptUI2"
   ```
2. **In-game:** `/mono load coophelper` (or restart MQ if already loaded).
3. **Test ParseTLO:** From Lua console or `/lua`:
   ```lua
   print(mq.TLO.MQ2Mono.Query("coophelper,TestParseTLO(Me.Name())")())
   ```
   Expected: character name (e.g. "YourCharName").
4. **Test ScanInventory:** Open inventory, run itemui. Check console for "Using CoopHelper (Mono) for inventory scan". Items should populate.

If TestParseTLO returns the character name, Phase 2.0 passes. If ScanInventory populates items, Phase 2.1 is verified.
