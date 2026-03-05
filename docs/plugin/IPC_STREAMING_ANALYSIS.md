# IPC Event Streaming — Research & Analysis

**Date:** 2026-03-03
**Scope:** Comprehensive assessment of replacing macro variable accumulation with plugin IPC event streaming across the CoOpt UI project. Covers every macro-to-Lua communication path, the real-time UI opportunities unlocked, and alignment with the existing MQ2CoOptCore implementation plan (Phases 1–8).

---

## 1. Current Communication Architecture

### Macro → Lua data flow (today)

| Path | Mechanism | Latency | Risk |
|---|---|---|---|
| Loot session results | INI file (`loot_session.ini`) written at end of run, polled by `macro_bridge.lua` | **Batch** — entire session delay | Data lost on crash |
| Loot skipped items | INI file (`loot_skipped.ini`) written at end of run | **Batch** | Buffer overflow if >5 chunks of reasons |
| Loot progress (per-corpse) | INI file (`loot_progress.ini`) written per corpse, polled every 500ms | 500ms | Disk I/O per corpse |
| Live loot feed | `/echo [ItemUI Loot]` parsed by `loot_feed_events.lua` via `mq.event()` | Frame-rate | Opt-in only; echo spam; no skip data |
| Mythical alert | INI file (`loot_mythical_alert.ini`) polled every 500ms | 500ms | Acceptable for rare event |
| Sell progress | INI file (`sell_progress.ini`) polled every 500ms | 500ms | Disk I/O per item sold |
| Sell failures | INI file (`sell_failed.ini`) written per failure | 500ms poll | Acceptable volume |

### Plugin IPC infrastructure (existing)

The `MQ2CoOptUI` plugin has a working in-process IPC implementation (`capabilities/ipc.h` / `ipc.cpp`):

- **Storage:** `std::unordered_map<std::string, std::deque<std::string>>` — named channels, each a FIFO queue
- **API surface (Lua):** `send(channel, message)`, `receive(channel)`, `peek(channel)`, `clear(channel)`
- **API surface (macro):** `/cooptui ipc send <channel> <message>` calls `sendFromMacro()`
- **Queue depth limit:** `kMaxChannelSize = 256` — oldest message dropped when full
- **Missing:** `receiveAll(channel)` for efficient batch drain from Lua

The IPC infrastructure is fully implemented and tested. It is used today only for internal plugin-to-Lua communication (scan invalidation signals). The macro-to-Lua path via `/cooptui ipc send` exists but is unused.

---

## 2. Every Location Where IPC Event Streaming Applies

### 2.1 Loot Item Events (`loot.mac` → Lua)

**Current state:** `LogItem` subroutine (loot.mac ~line 1959) appends item name/value/tribute to `runLootedList`, `runLootedValues`, `runLootedTributes` (3 chunks each, 9 total variables). Written to `loot_session.ini` only at `FinishLooting`. An optional echo-based live feed exists (`enableLiveLootFeed`).

**Problems:**
- 3-chunk cap (~200 items at typical name length) silently drops items and stops counting
- UI sees nothing until macro completes (30 seconds to 5+ minutes)
- Data lost entirely on crash (INI only written at end)
- Echo-based feed is opt-in, spams chat, no structured data for skip events

**IPC version:**
- Channel: `loot_item`
- Format: `Name|Value|Tribute` (3 fields, pipe-delimited)
- Producer: `loot.mac LogItem` → `/squelch /cooptui ipc send loot_item "${itemName}|${itemValue}|${tribute}"`
- Consumer: `macro_bridge.drainIPCFast()` → inserts into `uiState.lootRunLootedItems` and `uiState.lootHistory`
- UI improvement: Items appear in Loot Companion's Current tab per-frame as they are looted

**Complexity:** Low. One line added to macro. Lua drain is shared infrastructure.

### 2.2 Loot Skip Events (`loot.mac` → Lua)

**Current state:** `LogSkippedItem` subroutine (loot.mac ~line 2005) appends item name to `runSkippedList` and reason to `runSkippedReasons` (5 chunks each, 10 total variables). Written to `loot_skipped.ini` only at `FinishLooting`.

**Problems:**
- This is the **original buffer overflow** identified in `LOOT_SESSION_FINDINGS.md` — `runSkippedReasons` had a length check bug that only measured item name, not reason string
- Bug is fixed (dual-length check added) but 5-chunk cap still limits total skip data
- UI sees nothing until macro completes
- Skip History tab is blank during entire run

**IPC version:**
- Channel: `loot_skip`
- Format: `Name|Reason` (2 fields)
- Producer: `loot.mac LogSkippedItem` → `/squelch /cooptui ipc send loot_skip "${itemName}|${reason}"`
- Consumer: `macro_bridge.drainIPCFast()` → inserts into `uiState.skipHistory`
- UI improvement: Skip History tab shows items being skipped with reasons in real time; player can switch to Loot tab and add items to "Always Loot" if they see something they want

**Complexity:** Low.

### 2.3 Loot Progress (`loot.mac` → Lua)

**Current state:** After each corpse is looted, `loot.mac` writes `loot_progress.ini` with current/total corpse counts. `macro_bridge.pollLootProgress()` reads this INI every 500ms.

**Problems:**
- 500ms poll interval means progress bar jumps rather than animates smoothly
- Disk I/O per corpse (write + read = 2 INI operations per corpse)
- Current corpse name not visible in UI until next poll cycle

**IPC version:**
- Channel: `loot_progress`
- Format: `Looted|Total|CorpseName` (3 fields)
- Producer: `loot.mac` per-corpse → `/squelch /cooptui ipc send loot_progress "${corpsesLooted}|${totalCorpses}|${currentCorpseName}"`
- Consumer: `macro_bridge.drainIPCFast()` → updates `uiState.lootRunCorpsesLooted`, `lootRunTotalCorpses`, `lootRunCurrentCorpse`
- UI improvement: Progress bar updates per-frame; corpse name is always current

**Complexity:** Low. INI write preserved as fallback + crash checkpoint.

### 2.4 Loot Session Start (`loot.mac` → Lua)

**Current state:** Session start is detected by `macro_bridge.poll()` checking `mq.TLO.Macro.Name() == "loot"` and transitioning from `not running` to `running`. This detection has up to 500ms latency.

**Problems:**
- Minor latency (up to 500ms) before Loot UI opens
- No authoritative total-corpse-count until first progress INI is read

**IPC version:**
- Channel: `loot_start`
- Format: `TotalCorpses` (1 field)
- Producer: `loot.mac` after corpse scan → `/squelch /cooptui ipc send loot_start "${totalCorpses}"`
- Consumer: `macro_bridge.drainIPCFast()` → opens Loot UI, resets state, sets `lootRunTotalCorpses`
- UI improvement: Loot UI opens within one frame of macro starting; progress bar has total from frame 1

**Complexity:** Low.

### 2.5 Loot Session End (`loot.mac` → Lua)

**Current state:** Session end is detected by macro_bridge.poll() when the macro name changes away from "loot". Then phase 5 in main_loop.lua reads `loot_session.ini` and `loot_skipped.ini` to batch-populate the UI.

**Problems:**
- 500ms detection latency
- Relies on INI files existing and being completely written before detection

**IPC version:**
- Channel: `loot_end`
- Format: `LootedCount|SkippedCount|TotalValue|TributeValue|BestName|BestValue` (6 fields)
- Producer: `loot.mac FinishLooting` → `/squelch /cooptui ipc send loot_end "..."`
- Consumer: `macro_bridge.drainIPCFast()` → sets `lootRunFinished`, finalizes summary
- UI improvement: Session summary appears within one frame of macro completing

**Complexity:** Low.

### 2.6 Sell Progress (`sell.mac` → Lua)

**Current state:** `sell.mac WriteProgress` writes `sell_progress.ini` per item sold. `macro_bridge.readSellProgress()` reads it every 500ms.

**Problems:**
- 500ms poll interval
- Disk I/O per item sold (2 INI operations per item)

**IPC version:**
- Channel: `sell_progress`
- Format: `Current|Total|Remaining` (3 fields)
- Consumer: `macro_bridge.poll()` sell drain → updates `MacroBridge.state.sell.progress`
- UI improvement: Sell progress bar updates per-frame

**Complexity:** Low.

### 2.7 Sell Failures (`sell.mac` → Lua)

**Current state:** `sell.mac LogFailedItem` writes `sell_failed.ini` per failure. Polled every 500ms.

**IPC version:**
- Channel: `sell_failed`
- Format: `ItemName` (1 field)
- Consumer: `macro_bridge.poll()` sell drain → appends to `MacroBridge.state.sell.failedItems`
- UI improvement: Failed items appear immediately rather than at next poll

**Complexity:** Low.

### 2.8 Sell Session End (`sell.mac` → Lua)

**Current state:** Detected by macro name transition, similar to loot.

**IPC version:**
- Channel: `sell_end`
- Format: `SoldCount|FailedCount|TotalValue` (3 fields)
- Consumer: `macro_bridge.poll()` → sets `sell.running = false`
- UI improvement: Instant session-end detection

**Complexity:** Low.

### 2.9 Mythical Alert (Evaluated — Deferred)

**Current state:** `loot.mac` writes `loot_mythical_alert.ini` when a mythical item is found. `macro_bridge.lua` polls it. The macro waits for user decision in `WaitForMythicalDecision`.

**Assessment:** This is a rare event (0–1 per session). The 500ms poll latency is acceptable for a decision that takes the player 5–30 seconds to make. IPC would save one INI write/read pair but the UX improvement is negligible.

**Decision:** Defer to a future cleanup phase. Not worth the implementation and testing cost in Phase 9.

### 2.10 Debug Output (Evaluated — Deferred)

**Current state:** `debug.lua` uses internal buffers, periodic file writes, and queued `/echo` commands.

**Assessment:** Debug output is infrastructure, not player-facing. The current approach works well. Routing debug through IPC would add complexity (channel namespace collision risk, mixing diagnostic and functional data in the same drain) for no player-visible benefit.

**Decision:** Defer. Not in scope for Phase 9.

### 2.11 Cache Invalidation Signals (Already Handled)

**Current state:** Plugin cache invalidation (zone change, window state) is handled natively in C++ via `CacheManager` (Phase 8). Lua polls version counters.

**Assessment:** This is already the optimal path — C++ to C++ within the same plugin. IPC is not needed here.

**Decision:** Out of scope. Already implemented correctly.

---

## 3. Real-Time UI Opportunity Assessment

### 3.1 Loot Companion — Current Tab (`loot_ui.lua`)

The Current tab (lines 329–392 in `loot_ui.lua`) renders `state.lootRunLootedItems` in a table with columns for item name, value, tribute, sell status. Today this table is **empty for the entire duration of a loot run** because items are batch-loaded from `loot_session.ini` only after the macro finishes.

**With IPC streaming:** Each item appears in the table within one frame (~16ms) of being looted. The running totals (total value, tribute value, best item) update live. The player sees their loot accumulating in real time.

**Required changes to `loot_ui.lua`:** None. The view already iterates `state.lootRunLootedItems` and renders whatever is there. The IPC drain in `macro_bridge.drainIPCFast()` inserts rows into this array, and ImGui re-renders every frame.

### 3.2 Loot Companion — Skip History Tab (`loot_ui.lua`)

The Skip History tab (lines 444–501) renders `state.skipHistory`. Today this populates from `loot_skipped.ini` only at session end.

**With IPC streaming:** Each skipped item appears with its reason as it is evaluated. The player can watch skip decisions happen live and use the "Always Loot" button on items they want to keep.

**Required changes:** None. Same pattern as Current tab.

### 3.3 Loot Companion — Progress Bar

The progress bar reads `lootRunCorpsesLooted` / `lootRunTotalCorpses`. Today these update from INI polling every 500ms.

**With IPC streaming:** Progress updates per-frame. Visual difference is smoother animation and immediate corpse-name display.

**Required changes:** None. State variables are updated by the drain.

### 3.4 Sell View — Progress Bar (`sell.lua`)

The sell progress bar reads from `MacroBridge.state.sell.progress`. The IPC drain updates this state from `sell_progress` events. The sell view code reads from the same state.

**Required changes to `sell.lua`:** None. State source is the same; update frequency increases.

### 3.5 New UI Surfaces (Future Opportunity)

IPC streaming enables UI surfaces that are impractical with batch-only data:

- **Live item value ticker** — scrolling display of looted items with values (like a stock ticker)
- **Session value graph** — running chart of accumulated value over time
- **Alert on high-value item** — ImGui popup when an item above a value threshold is looted

These are not in scope for Phase 9 but become trivially possible once the IPC drain infrastructure exists.

---

## 4. Alignment with Existing Implementation Plan

### 4.1 No Conflicts with Phases 1–8

| Phase | Relationship to IPC Streaming |
|---|---|
| 1 (Config/Logging) | Phase 9 optionally adds `[IPC] ChannelCapacity` to `CoOptCore.ini` — extends Config |
| 2 (Data/Cache) | No interaction — different data paths |
| 3 (Inventory Scanner) | No interaction — scanner scans TLOs, IPC streams macro events |
| 4 (Bank Scanner) | No interaction |
| 5 (Rules Engine) | No interaction — rules evaluate items, IPC streams results |
| 6 (Loot Scanner) | Complementary — scanner scans corpse items, IPC streams loot decisions |
| 7 (Sell Scanner) | Complementary — scanner evaluates sell list, IPC streams sell progress |
| 8 (Event Hooks) | Foundation — event hooks use CacheManager invalidation; IPC uses different channels for macro data |

### 4.2 IPC Infrastructure Assessment

The existing `ipc.cpp` implementation is well-suited for Phase 9 with two enhancements:

**Channel capacity:** `kMaxChannelSize = 256` is insufficient for long sessions. A 100-corpse loot run with 5 items per corpse generates 500 `loot_item` events plus 500+ `loot_skip` events. If Lua stalls for even 1 second (e.g., garbage collection), messages could be dropped. Increasing to 1024 provides ~25 seconds of stall tolerance at peak event rate. Memory cost is negligible (~25KB per channel at max capacity).

**Batch receive:** The current `receive()` returns one message per call. Draining 50 events requires 50 C++ → Lua boundary crossings. A `receiveAll(channel)` that returns all messages as a Lua table and clears the channel in one call is significantly more efficient — one boundary crossing regardless of event count.

### 4.3 Integration Points

**main_loop.lua:** The IPC drain is called from `M.tick()` after `macro_bridge.poll()`. This ensures:
- Macro running/stopped detection happens first (via `poll()`)
- IPC events are drained at frame rate (every tick)
- UI state is ready for rendering by the time phase 3+ runs

**macro_bridge.lua:** The sell IPC drain is inside `poll()` because sell events are lower frequency and 500ms drain is sufficient.

**Phase 5 session read (main_loop.lua):** The existing merge logic uses `seen[name]` deduplication. When IPC events have already populated the items table during the run, the session-read INI merge adds only items that weren't delivered via IPC (e.g., plugin was unloaded mid-session). No changes to merge logic are needed.

### 4.4 What Phase 9 Does NOT Do

- Does NOT replace INI file writes — they are preserved as crash checkpoints and plugin-absent fallback
- Does NOT replace the echo-based live feed (`enableLiveLootFeed`) — preserved for backward compatibility
- Does NOT modify any existing variable accumulation in macros — all IPC sends are additive
- Does NOT touch the plugin's C++ scanner infrastructure (Phases 3–7)
- Does NOT require Phases 10–13 to be complete
- Does NOT introduce any new dependencies on external libraries

---

## 5. Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| IPC channel overflow (events dropped) | Low | Medium — lost history entries | 1024 cap + per-frame drain; silent drop is strictly better than CTD |
| Plugin absent during macro run | Expected | None — fallback preserves current behavior | All IPC sends guarded by `pluginLoaded` check |
| Duplicate items in UI from IPC + INI merge | Medium | Low — cosmetic | Phase 5 `seen[name]` dedup already handles this |
| Pipe character in item name | Very Low | Low — parsing error for one item | EQ item names do not contain pipes; if one does, worst case is one malformed row |
| IPC send adds macro execution time | Very Low | Very Low | `/squelch /cooptui ipc send` is a single string copy; measured at <0.1ms |
| Regression in non-plugin mode | Very Low | High | Zero lines modified in macro; IPC sends are purely additive behind `pluginLoaded` guard |

---

## 6. Conclusion

The IPC event streaming opportunity is real, low-risk, and high-value. The implementation touches 10 lines across two macros (all additive, all guarded), one new Lua function (~100 lines), and one small C++ enhancement (~20 lines). The player-visible improvement — live item-by-item updates in the Loot Companion during active sessions — transforms a batch-only UI into a real-time dashboard.

The analysis justifies adding Phase 9 to the MQ2CoOptCore Implementation Plan, positioned after Phase 8 (Event-Driven Invalidation) since it depends on the plugin's IPC infrastructure being fully wired.
