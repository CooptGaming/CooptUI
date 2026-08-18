# HANDOFF - Field Audit follow-through (2026-08-18)

For Jess, and for any Claude Code session running LOCALLY on the Windows machine
(read this whole file before acting - it replaces the cloud session's context).

## Where things stand

A full adversarially-verified review of the codebase ran on 2026-08-17
(45 confirmed findings; report: https://claude.ai/code/artifact/d639959b-1ab6-4c6f-8bad-ab9848276d27).
The top items were fixed and merged to master in PR #70 (merge commit 9220910):

| Fixed (file:line at time of review) | What it was |
|---|---|
| views/augment_utility.lua:328 | Preselect "consume" nil'd the view's own selection through the uiState proxy - every socket click snapped back to slot 1 |
| services/augment_ops.lua + services/main_loop.lua | advanceInsert's five silent kill paths now abort Fill-with-Best out loud; phase-7 pop clears the empty-queue husk |
| utils/table_cache.lua:143 | Incremental sort repair blessed fully-rebuilt lists; now gated by a ref-diff census |
| views/ augments, mythicals, favorites, reroll, augment_utility | Weak inventory-signature cache keys -> count + lastScanTimeInv + invMutationGen |
| views/augment_utility.lua:34 | Aug Utility scored against an empty equipment cache; now warms it and keys scores on an equipped-set fingerprint |
| views/aa.lua + views/dock_top.lua | Game text through printf-style ImGui.Text raised on '%'; now safeText/safeTextWrapped (+ the \a BEL literal) |

PR #70's body labels the queue-strand pair "F03 + F31"; F31 in the report is
actually the ornament-remove finding (item_display.lua:865, still open below).
Go by file:line, not by that label.

## Step 1 - sync to the test environment

```powershell
git pull origin master
.\scripts\sync-to-deploytest.ps1 -Target "C:\Claude_External\CoOptDeploy\test1"
```

The script copies lua/itemui, lua/coopui, lua/scripttracker, lua/mq/ItemUtils.lua,
the launcher, Macros, and resources; it skips config INIs so the test character's
settings survive. All merged fixes are Lua-only - no plugin rebuild, no -IncludePlugin
needed. Restart the Lua script in the test client afterwards.

## Step 2 - field-test checklist (what the fixes claim)

1. **Socket selection** (the critical one): open the Aug Utility, click each socket
   including the ornament (slot 5). The selection must STICK across frames; the
   candidate list must follow the selected socket; Insert must land in the selected
   socket; "Remove from slot N" must name the selected socket.
2. **Fill with Best on the Repository item** (the old hang): must either complete or
   print "Fill with Best aborted (<reason>) - N step(s) not done." Never a silent
   freeze at "Optimizing N/M", and no ghost resume after manually clearing the cursor.
3. **Sell/Bank staleness**: rescan with unchanged counts (e.g. reroll or consume a
   stacked item, or move items between bags) - Sell and Bank tables must show the
   post-scan rows.
4. **Aug Utility cold-open scores**: open it WITHOUT ever opening Equipment - scores
   must still account for worn gear ("already worn (higher)" notes print when true).
5. **AA window**: select an ability whose description contains a percent sign - no
   error spam, rail renders every frame.

If any of these fail in the field, the relevant fix needs another round - capture
the exact status line / behavior and file:line references above.

## Step 3 - the remaining backlog (36 confirmed findings, none fixed yet)

All adversarially verified against master @ 0b5c7ca (pre-merge line numbers; the
merged fixes shifted some lines a little - grep the titles' anchors if a line is off).
F-ids match the published report.

### High

- **F02** `loading` `lua/itemui/services/main_loop.lua:391` — End-of-run loot session merge reads a stale loot_session.ini on the plugin/IPC path when real-time feed is off
  - Fix sketch: In Phase A, treat 'ipcActive' alone as the gate for skipping the INI session read (or gate the getLootSession branch on 'not ipcActive'), mirroring the line-476 fix; never apply an INI-derived Summary when IPC delivered loot_end for this run.
- **F04** `loading` `lua/itemui/utils/item_helpers.lua:552` — Lazy wornSlots/augSlots commit empty values permanently when the item TLO is unavailable; the _tlo_unavailable flag they set is read by nothing
  - Fix sketch: Mirror the _statsPending convention: when `not it or it.ID() == 0`, return the default WITHOUT rawset (so the next access retries), or set _statsPending so the existing render-path rescan machinery picks it up; delete the write-only _tlo_unavailable flag.
- **F09** `loading` `lua/itemui/views/sell.lua:92` — Full inventory + sell scans run synchronously inside the ImGui draw callback, every frame, whenever the sell list is empty
  - Fix sketch: Replace the in-draw calls with the existing deferred flags (uiState.deferredScanNeeded.inventory / .sell or deferredInventoryScanAt) that runDeferredScans already consumes; additionally give maybeScanInventory/maybeScanSellItems an empty-result cooldown so an empty inventory is not re-scanned on every call.
- **F10** `lua/itemui/storage.lua:277` — Shared sell_cache.ini is last-writer-wins across characters, and sell.mac reads only the shared copy
  - Fix sketch: Have sell.mac read the per-character cache (Chars/${Me.CleanName}/sell_cache.ini) with the shared file as fallback, or stamp the cache with the character name and have sell.mac ignore a cache written by a different character.

### Medium

- **F11** `loading` `lua/itemui/app.lua:489` — loadConfigCache() runs once at require time with no in-game retry — starting mid-zone leaves the whole config cache at defaults
  - Fix sketch: Mirror the reroll fix: track a configCacheLoaded flag (or verify one sentinel INI key read back non-default) and retry loadConfigCache from main_loop until TLO.Ini answers, or simply call loadConfigCache() again in main() after the wait-for-character loop.
- **F12** `loading` `lua/itemui/app.lua:1597` — First post-upgrade launch on a never-run alt overwrites the customized shared layout with the bundled default
  - Fix sketch: When a layout file already exists, write the account marker WITHOUT applying the bundled default (treat an existing layout as proof this is not a first run).
- **F13** `loading` `lua/itemui/app.lua:1663` — Session floor stamped after a failed initial scan makes the entire inventory badge NEW and pollutes the session record
  - Fix sketch: Only stamp sessionStartAcquiredSeq after a scan that actually produced items (or when Me.Name resolved); re-stamp on the first successful scan otherwise - the same deferred-retry pattern reroll_service uses.
- **F14** `loading` `lua/itemui/config.lua:52` — getCharStoragePath is frozen at require-time: if MacroQuest.Path was empty at load, all per-character persistence is silently dead for the session
  - Fix sketch: Make getCharStoragePath resolve through getBasePath() at call time like the other helpers (CHARS_PATH becomes a derived value, not a load-time constant).
- **F15** `loading` `lua/itemui/services/aa_data.lua:90` — Truth-path fallback yields canTrain=true with nextIndex=0: green 'Can buy' rows whose Train silently no-ops
  - Fix sketch: In the else branch set rec.canTrain = false (or gate on a usable nextIndex), or have fireTrain surface a status message when nextIndex is 0 so the failure is at least loud.
- **F16** `loading` `lua/itemui/services/aa_data.lua:296` — Post-buy rescan fetches pre-ack truth but stamps a post-ack fingerprint, stranding stale ranks
  - Fix sketch: Delay arming the post-buy rescan by ~1s (or until AAPointsSpent changes / the aa_transfer 'Unable to train' event window closes), or capture the fingerprint at scan START so a mid-scan spend change re-triggers shouldRefresh.
- **F17** `loading` `lua/itemui/services/main_loop.lua:177` — Crash-recovery persist is dead on the plugin path: lastInventoryFingerprint never updates, so invChanged is permanently false
  - Fix sketch: On the plugin path, use the plugin version counter as the change key: record scanState.lastKnownInvVersion into a lastPersistedInvVersion in phase2, or bump a dirty flag/generation (perfCache.invMutationGen already exists) instead of comparing TLO fingerprints.
- **F18** `loading` `lua/itemui/services/main_loop.lua:485` — Skip-history INI read is not IPC-gated: every plugin-mode loot run re-appends a stale previous run's skip list
  - Fix sketch: Wrap the whole enableSkipHistory INI-read block in 'if not (macroBridge and macroBridge.isIPCAvailable and macroBridge.isIPCAvailable()) then ... end', same as the count read above it.
- **F19** `loading` `lua/itemui/services/main_loop.lua:806` — Closing the game's Item Display mid-insert/remove drops the completion flags without running the completion rescan — sockets and bags show stale data
  - Fix sketch: In the two not-itemDisplayOpen branches, treat it as step completion: call resolveAugmentQueueStep('optimize'/'removeAll') (cursor-guarded) instead of only clearing the flags.
- **F20** `loading` `lua/itemui/services/upgrade_scan.lua:46` — Stale walk results strand: buildKey misses same-count changes and the blocked row's remedy ('reopen Equipment to rescan') never actually rescans
  - Fix sketch: Invalidate (and abort any in-flight walk) when the Equipment window transitions to drawn; or include a cheap bag/slot/id fingerprint of inventory rows in buildKey; make invalidate() also set walk = nil.
- **F21** `loading` `lua/itemui/utils/item_helpers.lua:462` — getItemSpellId permanently caches spell id 0 when the item TLO resolves but the item is not in memory — the no-cache retry guard only covers a case that cannot occur
  - Fix sketch: Before caching, validate the resolved TLO the way buildItemFromMQ does: if `not slotItem or not slotItem.ID or (slotItem.ID() or 0) == 0` return 0 without rawset. Optionally also skip caching when spellObj resolves but the parent ID is 0.
- **F22** `loading` `lua/itemui/utils/item_tlo.lua:195` — Ornament socket type 21 is accepted by the Aug Utility probe but not by itemHasOrnamentSlot/getOrnamentFromIt — type-21 ornament sockets never render as ornaments
  - Fix sketch: Define one predicate isOrnamentType(t) = (t == 20 or t == 21) in item_tlo and use it in itemHasOrnamentSlot, getOrnamentFromIt, getAugmentSlotLinesFromIt's exclusion, and prepareTooltipContent's ornamentLine (carrying the real typ instead of literal 20).
- **F23** `loading` `lua/itemui/views/sell.lua:279` — Sell table body (and the loot/augments/mythicals/aa/reroll tables) lacks the in-pair pcall containment — any row-level throw skips EndTable and kills the whole script
  - Fix sketch: Extract each table body into a local function and pcall it between BeginTable/EndTable exactly as inventory.lua:477-481 and bank.lua:378-382 do (and record the error to diagnostics rather than discarding it).
- **F25** `lua/itemui/services/backup_service.lua:175` — hasRestoreBackup() always returns false, so the 'Restore Previous (from .bak)' button can never appear
  - Fix sketch: Probe for the manifest file instead: io.open(bakRoot .. '\\' .. MANIFEST_FILENAME, 'r') (importPackage always copies the manifest into the .bak folder at line 147), or list the folder with io.popen dir as restoreFromBackup already does.
- **F26** `lua/itemui/services/main_loop.lua:2311` — Equip FSM places whatever is on the cursor without verifying it is the queued item - stale bag/slot equips the wrong item
  - Fix sketch: In settle_pickup, after hasItemOnCursor, compare mq.TLO.Cursor.Name() (or ID captured at enqueue) against ea.name and abort with an honest status on mismatch, mirroring the reroll pickup verification.
- **F27** `lua/itemui/services/main_loop.lua:2491` — Post-loot incremental scan is dead code - every loot run ends in a full blocking scan on the main thread
  - Fix sketch: Add startIncrementalScan/processIncrementalScan to buildMainLoopDeps (or assert at mainLoop.init that every consumed dep key exists, as first-pass.md recommended - that would also have caught the maybeScanLootItems hole).
- **F28** `lua/itemui/services/upgrade_scan.lua:118` — Upgrade walk compares bare-item scores (no aug stats), so augmented worn gear produces false 'upgrade in bags' markers
  - Fix sketch: For the equipped phase, pass the cached tooltip augStats (or sum socket stats once per slot per walk) as opts.augStats; same for bag rows that have filled sockets.
- **F29** `lua/itemui/views/augment_utility.lua:417` — Fill-with-Best plan cache never invalidates on inventory changes, and the insert FSM picks up bag/slot blind — wrong augment can be socketed
  - Fix sketch: Include the same inv/bank signature candidateCache uses in optimizeCache's key; in advanceInsert's settle_pickup, verify mq.TLO.Cursor.ID() matches the planned augment id and abort the queue loudly on mismatch.
- **F31** `lua/itemui/views/item_display.lua:865` — Ornament has no working remove path: the context menu explicitly withholds onRemoveAugment for ornament rows, and the only alternative is dead
  - Fix sketch: Pass onRemoveAugment for ornament rows too (the FSM already routes slot 5 to the Appearance control).
  - Note: partially mitigated by the merged selection fix - with slot 5 now selectable, "Remove from slot 5" in the Aug Utility works; the Item Display context-menu path is still withheld.

### Low

- **F32** `loading` `lua/itemui/app.lua:1590` — io.open(nil) crashes main() at startup when MacroQuest.Path is unavailable
  - Fix sketch: Guard: if not firstLayoutMarkerPath then skip the first-run marker block (the existing line-1650 warning already covers messaging).
- **F33** `loading` `lua/itemui/services/main_loop.lua:1343` — Inventory-close save path still snapshots from sellItems (zeroed lazy stats, possibly stale rows) - the bug already fixed at the other two save sites
  - Fix sketch: Mirror the phase2/commands logic: computeAndAttachSellStatus(inventoryItems) + saveInventory(inventoryItems) when inventoryItems is non-empty, sellItems only as fallback; separately, either call loadSnapshotsFromDisk somewhere or delete it.
- **F34** `loading` `lua/itemui/utils/tooltip_data.lua:320` — Socket stat/effect merge iterates 1..augSlots (a count) instead of actual socket indices, skipping augments in non-contiguous sockets
  - Fix sketch: Walk fixed indices 1..4 (plus ornament 5) guarded by getSlotType(it, i) > 0, as getFilledStandardAugmentSlotIndices already does, in prepareTooltipContent's augStats loop, tooltip_render's fallback loop, and getAugmentSlotLinesFromIt.
- **F35** `loading` `lua/itemui/views/inventory.lua:479` — Bags and Bank table containment pcalls swallow the error silently — a persistent row bug renders a blank table forever with zero diagnostics
  - Fix sketch: Capture the pcall result and call diagnostics.recordError("Inventory"/"Bank", ..., err) like the other containment sites; optionally draw a one-line 'table error this frame' notice.
- **F36** `loading` `lua/itemui/views/reroll.lua:263` — Tray tooltip's minimal-fallback branch is unreachable; unresolvable slots show an empty stats card
  - Fix sketch: Have the tray treat a resolution failure as failure: e.g. require showItem.name and showItem ~= the request table before taking the rich path (or make getItemStatsForTooltipRef return nil on TLO failure for callers that pass a bare locator).
- **F37** `lua/itemui/components/context_menu.lua:433` — 'Cached on env for one open menu' is false - env is rebuilt every frame, so menu rows re-run their TLO probes per frame while open
  - Fix sketch: Persist the per-open cache outside the env literal (e.g. keyed by popupId on uiState, cleared when the popup closes), or have M.render own a stable env table per popupId.
- **F38** `lua/itemui/config_cache.lua:172` — isInLootSkipList / isInLootAlwaysList / isConsumable re-read and re-parse INI files every call, evaluated every frame while a context menu is open
  - Fix sketch: Make the membership checks read cache.loot.lists (already refreshed by loadConfigCache and kept in sync by the add/remove functions), falling back to file reads only when the cache is empty — the same pattern createAugmentListAPI already uses.
- **F39** `lua/itemui/services/scan.lua:505` — Offline bank pane with no saved bank file attempts a disk read every rendered frame
  - Fix sketch: Latch the load attempt (e.g. a bankCacheLoadTried flag reset when the bank opens) so a missing file is probed once per session.
- **F40** `lua/itemui/services/upgrade_scan.lua:104` — buildWornLines runs a full 46-read TLO walk at every walk start but its result is never consumed
  - Fix sketch: Either pass { context = { wornLines = walk.wornLines } } into the scoreForClass calls (making the walk genuinely set-aware) or delete buildWornLines and the published field.
- **F41** `lua/itemui/utils/augment_helpers.lua:239` — Ornament candidate rebuild TLO-probes every bag+bank row per search keystroke, and prints the probe-count console line on each empty rebuild
  - Fix sketch: Exclude the search string from the probe (probe once per slot/scan signature, filter the cached probe result by search), or memoize the probe by inv/bank signature; gate the diagnostic print to once per slot selection.
- **F42** `lua/itemui/utils/item_helpers.lua:336` — Spell cast/recast time unit heuristic misreads sub-second millisecond values as tenths, displaying 10-100x too long
  - Fix sketch: Pick one unit from the host and convert deterministically (ms/1000), or clamp: treat values in 10..999 as ms too unless the host is known to emit deciseconds.
- **F43** `lua/itemui/views/aa.lua:53` — hasRankTruthCached still runs one synchronous owned-ranks plugin walk inside the render callback
  - Fix sketch: Have aa_data record whether truth was obtained during the scan (it already fetched getOwnedRanks in the truth_owned phase) and expose that flag; derive hasRankTruth from it instead of re-walking in render.
- **F45** `lua/itemui/views/item_display.lua:416` — Identity card: 'req N' can never render (reads item.reqLevel, field is requiredLevel) and 'wt' prints raw tenths
  - Fix sketch: Use item.requiredLevel, and format weight with the same >=10 -> /10 rule tooltip_render uses.

## Conventions for continuing (for a local Claude session)

- Runtime is MQ2Lua / LuaJIT (Lua 5.1 semantics) inside a live game client; ImGui
  immediate-mode, redrawn every frame. TLO results can be nil or not-in-memory.
- Gates before any push - all three, in this order:
  1. `luacheck lua/itemui lua/coopui` (must be 0/0)
  2. `powershell -File .\scripts\tests\run-tests.ps1 -All` (the -All adds the LuaJIT
     compile sweep - the only gate that catches the 60-upvalue limit)
  3. field-relevant manual test in the test1 environment
- Commit style: conventional `fix(scope): lowercase summary` with a body that names
  the mechanism and the player-visible symptom (see PR #70's commits for the shape).
- Releases are local-only and go through the `/release` command (.claude/commands/release.md).
- The five test suites that fail on Linux (Windows path assumptions) pass on Windows;
  a suite reported SKIPPED because luajit was not found is a gate that did NOT run.
