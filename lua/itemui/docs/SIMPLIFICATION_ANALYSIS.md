# ItemUI Simplification & Root Cause Analysis

## Summary

This document analyzes recent changes, identifies potential causes of regressions, and proposes a simplification path to restore stability.

---

## 1. Keyboard Focus Issue – Root Cause

**Symptom:** When inventory closes, keyboard input stops working until user clicks the game screen.

**Root cause:** ImGui `InputText` widgets (Search boxes in Sell/Bank views, filter inputs in Config, etc.) capture keyboard focus. When ItemUI hides (`shouldDraw = false`), we return immediately from `renderUI` before any ImGui calls. ImGui never gets a chance to process "window closed" and release focus. The focus becomes "orphaned" – ImGui's overlay still thinks an input has focus, so it captures keystrokes, but the widget is no longer visible. Result: keystrokes go nowhere.

**Why it may have appeared "today":** The debounce logic changed *when* we hide. We now require 3 closed frames before auto-close. That changes timing – we might be hiding at different moments relative to ImGui's frame processing, or the user may have started using the Search box more (which gives ImGui focus).

**Proper fix (instead of /click workaround):** ImGui does *not* expose a direct "clear focus" API. `SetKeyboardFocusHere(-1)` sets focus to the previous widget, not "none". Options:
- **A)** When hiding, render one more minimal frame where we call `ImGui.Begin` and `ImGui.End` so ImGui can clean up (may help).
- **B)** UI pattern change: avoid having InputText focused when closing – e.g. add `ImGuiWindowFlags.NoFocusOnAppearing` so we don't steal focus on show; user could Tab out of Search before closing.
- **C)** Reproduction test: if you close *without* ever clicking in the Search box, does the keyboard issue still occur? If not, that confirms InputText focus is the cause.

The `/click left center` workaround simulates what the user does manually – it activates the game window. It's a workaround, not a root fix.

---

## 2. Changes Made Today (Rollback Candidates)

| Change | Purpose | Complexity | Revert? |
|--------|---------|------------|---------|
| **Debounce (invOpenFrames, invClosedFrames, invStableOpen/Closed)** | Fix "almost opens and closes immediately" | High – 4 new state vars, changed lastInventoryWindowState semantics | **Consider** – adds complexity; may have introduced timing quirks |
| **Loot suppress cooldown (lastLootClosedAt)** | Fix "won't open after loot macro" | Medium | **Consider** – edge case fix |
| **Deferred storage save (pendingInvSave)** | Avoid blocking scan path | Low | **Consider** – adds async flow; original sync save was simpler |
| **releaseFocusToGame (/click)** | Fix keyboard not working | Workaround | **Yes** – user doesn't want this |
| **Spell pre-warm removal** | Perf – 5 fewer TLO calls per item | None | **Keep** – clear perf win |
| **Filter null handling** | Defensive – filter out null/nil in lists | Low | **Keep** – defensive, no downside |
| **isLootWindowOpen fix** | Was checking Corpse instead of LootWnd | Critical bug fix | **Keep** – essential |
| **Loot Done button, column widths** | UX | Low | **Keep** – straightforward |

---

## 3. Simplification Recommendations

### Option A: Minimal Rollback (Conservative)

1. **Remove** `releaseFocusToGame` and all its calls.
2. **Investigate** proper ImGui focus release (Option A or B above).
3. **Keep** everything else for now.

### Option B: Moderate Rollback (Recommended)

1. **Remove** `releaseFocusToGame`.
2. **Revert debounce logic** – back to simple `invOpen` / `lastInventoryWindowState`:
   - Remove: `invOpenFrames`, `invClosedFrames`, `invStableOpen`, `invStableClosed`, `invWasStableOpen`
   - Restore: `lastInventoryWindowState = invOpen`
   - Restore: `invJustOpened = invOpen and not lastInventoryWindowState`
   - Restore: auto-close on `lastInventoryWindowState and not invOpen` (no debounce)
3. **Revert deferred save** – back to sync `storage.saveInventory` in `scanInventory`.
4. **Revert loot cooldown** – remove `lastLootClosedAt` and `lootCloseCooldown`.
5. **Keep:** spell pre-warm removal, filter null handling, isLootWindowOpen fix, Done button, column widths.

### Option C: Aggressive Rollback

Revert everything from today except:
- `isLootWindowOpen` fix (Corpse → LootWnd)
- Spell pre-warm removal
- Filter null handling

---

## 4. Structural Simplification (Longer Term)

If ItemUI still feels heavy after rollback:

1. **Reduce InputText usage** – Search boxes are convenient but each can hold focus. Consider making Search a toggle (click to expand) so it's not always in the layout.
2. **Lazy-load Config** – Don't load filter lists until Config tab is opened.
3. **Simplify main loop** – The loop has many branches (auto-show, auto-close, loot macro, bank, persist, etc.). Consider extracting into smaller functions.
4. **Profile** – Add simple timing around `scanInventory`, `loadLayoutConfig`, `storage.saveInventory` to see where time goes.

---

## 5. Next Steps

1. Choose rollback level (A, B, or C).
2. Implement rollback.
3. For keyboard focus: try `ImGui.SetKeyboardFocusHere(-1)` or equivalent when hiding; if not available, try rendering one more minimal frame on hide.
4. Test with Search box focused when closing – that's the scenario that triggers the bug.

---

## 6. Performance Profiling (Implemented)

Profiling was added to measure the three heavy operations:

- **init.lua:** `C.PROFILE_ENABLED`, `C.PROFILE_THRESHOLD_MS` (default 30ms)
- **loadLayoutConfig:** Logs when cached path or file-read path exceeds threshold
- **scanInventory:** Logs scan time, save time, and item count when either exceeds threshold
- **storage.lua:** `PROFILE_ENABLED`, `PROFILE_THRESHOLD_MS` – logs `saveInventory` when it exceeds threshold

To disable: set `C.PROFILE_ENABLED = false` in init.lua and `PROFILE_ENABLED = false` in storage.lua.
