# Loot Session Findings — Phase 6 Integration, saveInventory Performance, Buffer Overflow

Date: 2026-03-03

---

## Section 1 — Plugin Status on the Loot Path

### Verdict: Plugin is ACTIVE for the Loot tab scan, but NOT connected to loot.mac

The plugin has two separate integration points and they have different statuses:

#### 1A. CoOpt UI Loot Tab (scan.lua → scanLootItems) — ACTIVE

When the CoOpt UI Loot tab opens (the ImGui "Corpse Loot" view), `loot.lua:26` calls `ctx.maybeScanLootItems(true)`, which calls `scan.lua:646 maybeScanLootItems()`, which calls `scan.lua:558 scanLootItems()`.

At `scan.lua:562-571`, the plugin fast path is attempted:

```lua
local coopui = tryCoopUIPlugin()
if coopui and coopui.scanLootItems then
    local ok, result = pcall(coopui.scanLootItems)
    if ok and result and type(result) == "table" and #result > 0 then
        for _, row in ipairs(result) do
            if type(row) == "table" then table.insert(lootItems, row) end
        end
        env.invalidateSortCache("loot")
        return
    end
end
```

`tryCoopUIPlugin()` at `scan.lua:16-25` calls `require("plugin.MQ2CoOptUI")` and caches the result. The top-level alias `mod["scanLootItems"]` was added to `CreateLuaModule()` in `MQ2CoOptUI.cpp:330`. The C++ function at `loot.cpp:50-58` calls `LootScanner::Instance().Scan()` and converts results to `sol::table`.

**This path is working.** When the plugin is loaded AND the loot window is open, the Loot tab uses the native C++ scanner.

#### 1B. `/cooptui scan loot` command — ACTIVE but requires loot window open

The command handler at `MQ2CoOptUI.cpp:257-266` calls `LootScanner::Instance().Scan(true)` and prints results. If the loot window is closed, `LootScanner::Scan()` returns empty (by design — `IsLootWindowOpen()` check at `LootScanner.cpp:148`).

**If `/cooptui scan loot` produced no visible output**, the most likely cause is that the loot window was not open at the time the command was typed. The loot window closes when the macro finishes a corpse, so the window may close before the user can type the command. The command requires the EQ loot window to be actively open.

#### 1C. loot.mac — NOT CONNECTED to the plugin

`loot.mac` is a pure MQ2 macro. It uses TLOs directly (`${Corpse.Item[N].ID}`, `${FindItem[=name]}`, etc.) and its own `EvaluateItem` subroutine for loot decisions. It does not call Lua, does not call the plugin, and does not use the native scanner. The plugin cannot accelerate the macro's per-item evaluation or the loot process itself.

The plugin accelerates the **CoOpt UI Loot tab** (the visual display), not the macro's autonomous looting process. These are separate systems.

#### 1D. No kill switches or feature flags

No `ENABLE_COOPHELPER_MONO`, `ENABLE_PLUGIN`, or equivalent kill switch exists anywhere in the codebase. The `tryCoopUIPlugin()` function is the only gate, and it simply checks whether `require("plugin.MQ2CoOptUI")` succeeds.

#### 1E. Diagnostic output

The plugin logs to `DebugSpew` at debug level 2+ (not to chat). At the default debug level (0), no diagnostic output appears in the MQ console when the plugin path is taken. The scan.lua plugin path also produces no visible output — it silently succeeds or falls back.

To confirm the plugin path is active, either:
- Set debug level: `/cooptui debug 2` (will emit DebugSpew messages)
- Run `/cooptui scan loot` with the loot window open (prints item count + time to chat)
- Check `/cooptui status` — the loot cache count will be >0 after a plugin loot scan

---

## Section 2 — saveInventory Performance (4111 ms for 211 items)

**Note:** This is unrelated to the loot scan path. saveInventory runs when the *inventory* is scanned and persisted (e.g. after opening the Inventory tab or when the persist timer fires). It has nothing to do with corpse/loot scanning or the plugin’s LootScanner.

### Root Cause: Lua serialization + disk write of ~80 fields per item

The profiler message `[CoOpt UI Profile] storage.saveInventory: 4111 ms (211 items)` comes from `storage.lua:210-211`. The function:

1. Calls `buildInventoryContent()` at `storage.lua:134-148` — serializes all 211 items into a Lua file
2. Each item goes through `serializeItem()` at `storage.lua:96-131` — 4 batched `string.format` calls for ~80 numeric fields, plus boolean and string fields
3. Writes the entire content via `file_safe.safeWrite()` at `file_safe.lua:11-37` — a single `io.open("w")` + `f:write(content)` + `f:close()`

**The bottleneck is NOT per-item /ini calls or shell process spawning.** The storage layer uses pure Lua `io.open`/`io.write` for a single file write. The 4-second time is the Lua serialization of ~80 fields x 211 items = ~16,880 field serializations, plus the disk write of the resulting ~200KB file.

This is not related to the plugin's native INI service. The plugin is not involved in `saveInventory()` at all — that function is Lua-only.

**Why it's slow:** The scan itself is fast (0 ms via plugin). The 4111 ms is the combined cost of:
- `computeAndAttachSellStatus(inventoryItems)` at `scan.lua:138` — evaluates sell rules for all 211 items via Lua
- `storage.saveInventory(inventoryItems)` — serializes 211 items with ~80 fields each
- `storage.writeSellCache(inventoryItems)` — writes a second INI file

The profile timer at `scan.lua:141` includes all three operations. The serialization dominates because it runs ~16K `string.format` calls in a single Lua thread on MQ's game thread.

**Potential future optimization:** The plugin's C++ `RulesEngine::AttachSellStatus()` already mirrors the Lua sell evaluation. If `computeAndAttachSellStatus` were replaced with a plugin call, the sell-status attachment would drop from hundreds of ms to <1 ms. The serialization itself could also be moved to C++ in a future phase, but that would require a more invasive change.

---

## Section 3 — Buffer Overflow Root Cause and Fix

### Mechanism

`loot.mac` uses a chunking system for macro string variables, documented at line 64-73:

> MQ2 macro string vars are limited to 2048 chars; exceeding causes crash to desktop.

The system uses 3 chunks per list type: `runSkippedList`, `runSkippedList2`, `runSkippedList3` (item names, pipe-delimited) and `runSkippedReasons`, `runSkippedReasons2`, `runSkippedReasons3` (reasons, pipe-delimited). Each chunk is capped at `runListMaxLen = 1740` characters.

**The bug:** In `LogSkippedItem` (line 1985-2017), the length check only measures the *name* list length, not the *reasons* list length:

```
/declare addLen int local ${Math.Calc[1+${itemName.Length}]}
/if (${Math.Calc[${runSkippedList.Length}+${addLen}}} > ${runListMaxLen}) {
```

`addLen` is `1 + len(itemName)`. The chunk-full check compares `runSkippedList.Length + addLen` against `runListMaxLen`. But `runSkippedReasons` is appended in parallel with the *reason* string, which can be a different length than the item name.

**Example of the overflow:**
- Item name: "Raw Faycite Crystal" (19 chars)
- Reason: "Skipping (no criteria met): Raw Faycite Crystal" — this is much longer than the name
- The `runSkippedList` stays under 1740 because addLen uses `itemName.Length`
- But `runSkippedReasons` grows faster because each reason string is longer than the name
- Eventually `runSkippedReasons` exceeds 2048, and MQ's `ParseMacroData` buffer overflows

The error messages confirm this:
- `NewLength 15 was greater than Buffersize - addrlen 7` — early overflow detection
- `NewLength 2031 was greater than Buffersize - addrlen 2030` — one byte over the 2048 limit

### What runskippedReasons is used for

The variable is consumed in exactly one place: `FinishLooting` at line 1233-1255. It writes `loot_skipped.ini` in format `"itemName^reason"` per line:

```
/ini "${configPath}/loot_skipped.ini" Skipped ${j} "${runSkippedList.Token[${j},|]}^${runSkippedReasons.Token[${j},|]}"
```

The Loot Companion UI reads this at `main_loop.lua:264-281` — it parses each `name^reason` entry into `{ name = ..., reason = ... }` for the Skip History tab.

### The Fix

The `runSkippedReasons` variables need the same length-guarded chunking as `runSkippedList`. The bug is that `addLen` only accounts for the name, but the reason is appended to a separate variable without any length check.

**The correct fix** is to compute a separate `addLenReason` for the reasons variable and check *both* lists against `runListMaxLen` before choosing which chunk to append to. If either the name list or the reasons list would exceed the limit, overflow to the next chunk.

Additionally, when all 3 chunks are full, the current code silently drops the item (no count increment, no append). The count should still be incremented so the total is accurate, even if the details are lost.

The same bug pattern also exists in `LogLootedItem` (lines 1890-1920) where `runLootedValues` and `runLootedTributes` are appended without length checking. Those are numeric values (short strings), so overflow is much less likely there, but the pattern is still incorrect.

### Code change

See the implementation below — applied to `LogSkippedItem` in `loot.mac`.

---

## Section 4 — Plugin Enhancement Opportunity

### IPC Channel for Skip Reasons — Assessment

The plugin's IPC capability (`cooptui.ipc.send` / `cooptui.ipc.receive`) could theoretically replace the macro variable accumulation:

- **Macro side:** `/cooptui ipc send loot_skip "ItemName^Reason"` per skip
- **Lua side:** `coopui.ipc.receive("loot_skip")` drains the channel on each frame

**Advantages:**
- No macro variable buffer limit — IPC channels are in-memory std::deque with no 2048-char constraint
- No chunking logic needed in the macro
- Real-time: UI could show skip events as they happen, not just at end-of-run

**Disadvantages / Blockers:**
- Requires the plugin to be loaded; the macro currently works standalone
- IPC `send` from macro requires `/cooptui ipc send` command syntax — adds a command per skipped item during the loot loop, potentially adding latency
- The existing INI-file approach (`loot_skipped.ini`) is the contract between macro and UI — both sides would need updating
- If the plugin is unloaded mid-session, skip data would be lost

**Verdict:** Worth adding to the implementation plan as a Phase 8+ enhancement, but NOT a replacement for the buffer overflow fix. The fix must go into `loot.mac` immediately because the crash happens with or without the plugin loaded. The IPC enhancement would be additive — a faster, more robust channel for macro-to-UI communication that doesn't replace the INI fallback.

**Recommended approach if implemented:**
1. Macro sends `/cooptui ipc send loot_skip "name^reason"` per skip (if plugin loaded)
2. Macro ALSO accumulates in variables (as fallback for when plugin is absent)
3. UI checks IPC channel first, falls back to INI on macro finish
4. This provides real-time skip tracking in the UI while maintaining backward compatibility
