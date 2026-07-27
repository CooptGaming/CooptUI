# CoOpt UI — Pre-Release Review, First Pass

**Branch:** `review/first-pass` (from `master` @ `e947565`)
**Date:** 2026-07-27
**Version under review:** 0.9.8
**Reviewer:** first of two passes. A second independent review follows. **This is not release approval.**

---

## 1. Summary

The architecture is sound and there is clear evidence of prior hardening — atomic writes, readiness
guards, and comments that record *why* a defence exists. Both static gates were already green
before I touched anything, and the release manifest matched the committed tree exactly.

The defects cluster into one shape: **the code is more careful than the things around it.** Guards
exist but are wired to the wrong table; protections exist but the shipped config disables them;
atomic writes exist but the install path that uses them is not gated; a build cache decides what
to ship from an incomplete list of inputs.

Ten commits. The five I would not ship without:

- **The reroll protection lists could be destroyed three different ways** — including one that
  triggers on any start before the character resolves, and one that triggers when a player types
  `!auglist` in chat. These ids are a *sell and loot protection set*, so losing them silently
  un-protects the user's items.
- **The "don't delete an item the player is wearing" guard had never executed.** It read
  `d.equipmentCache`, which was only ever wired into the UI context table. Added by the previous
  review; wired to the wrong object.
- **The patcher would start writing over a live MacroQuest install.** Its guard is a process-*name*
  check and MQ's tray runs under a randomised name; Fresh Install had no guard at all. The overlay
  then aborts on the first locked binary having already written everything before it — the exact
  "failed the first time, worked on retry" report that prompted this review.
- **A GitHub rate limit could silently downgrade a working install** to a foreign MacroQuest family
  and disable the plugin, then report success.
- **The build cache could publish a stale bundle.** Editing a skin file or the launcher left the
  stage hash unchanged, so the release reused the previous zip. I reproduced this against the
  pre-fix script and confirmed the fix.

**Highest-risk item I did not change:** the default sell configuration (§3.1). Six template values
all push the same direction, `willItemBeSold`'s terminal branch is `return true, "Sell"`, and epic
protection ships dormant. Every value is individually documented and deliberate; the *combination*
is what needs a second opinion. It is a product decision, not a bug.

**Method note.** I ran a 10-dimension review fan-out (96 agents: 10 finders, each finding then
independently attacked by a verifier told to refute it). 21 findings were refuted and discarded;
65 survived. I did **not** take the survivors at face value — I re-verified every one I acted on,
and §3.6 records two places where the agents' framing was wrong and I corrected it.

**Readiness:** Ready for second review with known risks. Conditions in §9.

---

## 2. Changes made

| # | Commit | Area | Severity |
|---|--------|------|----------|
| 1 | `d6dd50a` | Patcher: block installs over a live MacroQuest | **High** |
| 2 | `2bde598` | Patcher: correct inverted base-bundle docs | Low |
| 3 | `1a7783f` | Skin: install impossible without `lfs`; swap could delete a file | **High** |
| 4 | `63a9b51` | Repo: actually untrack personal config INIs | Medium |
| 5 | `a595f4f` | AA: warn when rank data is unavailable | **High** |
| 6 | `c46dd42` | Defaults: ship debug channels OFF | Medium |
| 7 | `5cbc69a` | Reroll: three ways the protection lists were destroyed | **High** |
| 8 | `78cf599` | Stale-bundle build cache · silent MQ downgrade · AA path injection | **High** |
| 9 | `7528c4e` | Release: missing plugin asset must not read as success | **High** |
| 10 | `120009a` | Tests: drop hardcoded toolchain path; a skip is not a pass | Low |

Full problem/evidence/fix/validation for each is in its commit message. Below is what a reviewer
needs to decide whether to trust the change.

---

### 2.1 — `d6dd50a` The patcher starts writes over a live MacroQuest install · **High**

`is_macroquest_running()` runs `tasklist /FI "IMAGENAME eq MacroQuest.exe"`. MacroQuest's tray
relaunches itself as a **randomly-named copy** of `MacroQuest.exe` inside the install folder, so
the check reports a clean machine while the tray still holds `MQ2Main.dll` / `imgui.dll` mapped.
Separately, `show_fresh_install()` called `smart_install()` with **no guard at all** — the only
write path without one — and Fresh Install accepts any folder from a directory picker.

Either way `overlay_bundle`'s `os.replace` raises on the first locked binary, after the loop has
already written every earlier file, and the user saw a bare `WinError 5`.

**Root cause:** the guard tests *process identity* when what matters is *file availability*.

**Fix.** `find_locked_files()` probes the MQ binaries with `open(path, "r+b")` — Windows refuses to
open a mapped image for writing, so it detects a live install regardless of process name.
`preflight_blockers()` fronts both checks; all three write paths call it. A permission `OSError`
mid-overlay now says the install stopped part-way and that re-running completes it.

**Validation.** Unit test (6 assertions) plus a **mapped-image test**: copied a real DLL to
`<tmp>/MQ2Main.dll`, loaded it with `ctypes.WinDLL`, confirmed the probe reports it locked *only
while mapped*. Not exercised: the real GUI, a real MQ tray.

**Remaining risk.** A false positive blocks updating. Sources are narrow (a genuinely locked or
read-only binary — both of which fail the install anyway), the message names the file, Retry is one
click. **Test 15 in §7 is the negative test for this** and is the single most important check of
this pass.

---

### 2.2 — `2bde598` Inverted base-bundle precedence in comments · Low

`smart_install()`'s docstring and `show_fresh_install()`'s comment said fresh install downloads the
**stock** E3 bundle as primary with CoOpt's EMU zip as fallback. The code has done the opposite
since `e947565`. That distinction decides whether `MQ2CoOptUI` is enabled or force-disabled — the
plugin path versus the Lua fallback path. Comments only.

---

### 2.3 — `1a7783f` Native skin: install impossible without `lfs`; swap could delete a file · **High**

Three defects in `skin_sync.lua`:

1. It was the **only** module in the codebase requiring LuaFileSystem, and required it for the one
   thing with no fallback: creating `<EverQuest>\uifiles\coopt`. Every other directory-creating
   module uses `os.execute mkdir`. Without `lfs`, "Install skin" created no folder, every write then
   failed, and Settings reported *"check that MQ and EQ paths are available"* — never the real
   cause. The entire native stack depends on that skin.
2. `os.remove(dst)` then `os.rename(tmp, dst)` (Lua's `os.rename` cannot replace on Windows). On
   rename failure it removed the tmp too, leaving the destination **missing** — the next
   `/loadskin coopt` silently drops that window's CoOpt controls.
3. Unwritable files were skipped with no record, so a partial sync looked like a clean no-op.

**Fix.** `makeDir()` falls back to the repo's standard `os.execute mkdir` and confirms with a marker
write. Rename failure falls back to writing the payload straight to the destination. `sync()`
returns a user-facing reason as a second value, which Settings reports and `app.lua` prints and
records in diagnostics.

**Validation.** `scripts/tests/test_skin_sync.lua` on the **vcpkg LuaJIT MQ links** — 20 assertions
passing. It forces the no-`lfs` path and simulates a failing `os.rename`. **Confirmed it fails
against the pre-fix file (7 failures)**, so it pins the fix rather than the code shape.

**Remaining risk.** `os.execute` briefly flashes a console window in-game — the established idiom
in four other modules here, and it runs at most once per install.

---

### 2.4 — `63a9b51` Personal config INIs were never actually untracked · Medium

Commit `27de2f0` states 41 personal config INIs were untracked. **It modified 7 files and deleted
none** — `git rm --cached` was never staged. 40 files were still published, including
`sell_keep_exact.ini` (~30 named items from the maintainer's characters) and
`coopui_onboarding.ini`. `Build-Smart.ps1`'s own staging comment asserts these are *"untracked in
git for the same reason"* — true only as of this commit.

**No player impact, verified rather than assumed:** absent from both manifests, and Build-Smart
copies only the macros and `config_templates/**/*.ini` — FullBundle staging additionally *replaces*
any Macros config INI with the template default.

---

### 2.5 — `a595f4f` AA export/import degrade to a rank source the code says is wrong · **High**

`aa_transfer.lua`'s own comments state the TLO Rank read inflates on partially-trained lines and
*"fooled both planning ('nothing missing' with 417 pts of holes) and per-buy verification"*.
Nothing gated on the plugin's owned-ranks store being available, so `curRankFor()` silently fell
back to it: `planImport()` skips ranks the character does not have, and `plan.ranks == 0` reports
*"Nothing to import — all exported AAs already trained"*. This is a shipped configuration —
`0230661` force-disables `MQ2CoOptUI` on stock-MacroQuest installs, which is the fresh-install
fallback base.

**Fix — deliberately proportionate.** Not disabling the feature: on an untrained character the TLO
read is usually right, so the common "fresh alt" case works. What was wrong was the false
confidence. `hasRankTruth()` drives a warning in the AA view, and `startImport()` appends the same
caveat to the status line because the **native** AA window renders only `getStatusLine()`.

**Remaining risk.** The inaccuracy is unchanged — this makes it visible. See §3.2.

---

### 2.6 — `c46dd42` Three debug channels shipped ON · Medium

Both files seeding a new install's layout shipped `[Debug] ItemOps=1 Scan=1 Loot=1` —
`config_templates/sell_config/itemui_layout.ini` (patcher + zip) and
`lua/itemui/default_layout/itemui_layout.ini` (applied on first run). `core/debug.lua:35` defaults
an unset channel to `"0"`, so the templates shipped **worse than the code fallback** — the same
class of regression as `protectEpic` last pass. `debug.channel()` writes to the MQ console *and*
appends to `logs/coopui_debug.log`; `Scan`/`ItemOps` are hot paths and `Loot` fires per looted item.

Set to `0` in both, and added the missing `[Debug]` row to `docs/DEFAULT_SETTINGS.md` with a note
that the two layout files must be kept in step.

---

### 2.7 — `5cbc69a` Three ways the reroll protection lists were destroyed · **High**

The aug/mythical reroll ids are a **sell and loot protection set** (`rules.lua:292,443`) and are
pushed into the C++ plugin. Losing them does not just lose a list — it un-protects the user's items.

1. **Init before the character exists.** `rerollService.init()` runs in app.lua's *module body*
   (`app.lua:567`), before `main()` waits for `Me.Name()`. At character select or mid-zone the
   per-character path resolves to nil, `loadFromFile()` no-ops, and init treats "could not load" as
   "the list is empty" — firing `!auglist`/`!mythicallist` into the void. `main()` then blocks until
   the character resolves, so the **first** tick is already past the 6s window:
   `checkListRequestTimeout` calls `saveToFile()`, the path now resolves, and four empty tables
   overwrite the user's real cache. Reachable via the native Command Center's Start button.
2. **Listeners registered after the request was sent.** Benign in practice (the server round-trip
   dwarfs the gap) but the wrong order, in the same function.
3. **A stray chat line could wipe a list.** `onRerollListLine` ran its header branch — which does
   `augList = {}` — *before* the parse-window guard, against very loose patterns. Typing `!auglist`
   directly in chat (a command the README tells players about) made the server echo its header
   outside any window: the list was cleared, the replacement lines were then rejected, and the empty
   list was persisted and pushed to the plugin. Refresh restored it — "broke once, fine after retry".
4. **The equipped-item guard had never worked.** `main_loop.lua:1375` reads `d.equipmentCache` to
   avoid deleting a pending entry the user is wearing; `equipmentCache` was only ever wired into the
   UI context table, so it read nil and Sync deleted worn items as *"Not owned — cleared from
   pending"*. The previous review added this guard, wired to the wrong object.

**Fix.** `loadFromFile()` reports whether the character was known; `saveToFile()` refuses to write
until a load has succeeded — "unknown" is never treated as "empty". Init defers the load and the
request to the first tick where the path resolves, and registers listeners first. The parse-window
test now precedes the header branch. `equipmentCache`/`refreshEquipmentCache` are wired into the
main-loop deps (split across both builder halves to stay clear of LuaJIT's 60-upvalue limit), Sync
refreshes worn slots once per run, and deletion additionally requires `sync.equipKnown` — an entry
is only removed when bags, bank **and** worn slots have all actually been read.

**Validation.** `scripts/tests/test_reroll_service.lua` on the vcpkg LuaJIT — 16 assertions passing.
It stubs the mq host, models the real timeline, and asserts the cache file is byte-identical.
**Confirmed it fails against the pre-fix file (9 failures)**, including *"user cache is NOT
overwritten by the first tick after the character resolves"* — so it pins the data loss itself. It
also pins that a normal Refresh still resets, refills and persists.

**Note:** luacheck caught a use-before-declaration in my first draft of this change. The gate works.

---

### 2.8 — `78cf599` Stale-bundle build cache · silent MQ downgrade · AA path injection · **High**

1. **`Get-CoOptUISourceHash` ignored files it ships.** No entry for `uifiles\coopt` or
   `lua\coopt_launcher.lua`, and `lua\itemui` filtered to `*.lua` (so its `default_layout\*.ini`,
   `layout_manifest.json` and `overlay_snippet.ini` were invisible). Editing a skin XML left the
   hash identical: Stage 4 printed *"[SKIP] Output already exists"*, the build reported *"Changed:
   none (all cached)"*, and `-Release` uploaded the **previous** zip. This is how `uifiles/coopt`
   went missing from the v0.9.7 EMU zip.
   **Demonstrated, not assumed:** with the pre-fix script, touching
   `uifiles\coopt\EQUI_TipWnd.xml` still reported the same hash (`cdef8061efe2…`) and reused the
   stale zip. With the fix the same edit re-stages, while an unchanged rebuild still correctly
   skips — caching is not broken.
2. **A rate limit could downgrade a working install.** The stock-E3 fallback is a *different*
   MacroQuest family; overlaying it replaces every `.exe`/`.dll` and forces `MQ2CoOptUI=0`, then
   reports success. No failed download is even needed — `get_latest_release_zip_url()` returns an
   error on a GitHub API 403/429, reachable from a shared/CGNAT address on the unauthenticated
   60/hr quota. `_has_coopt_install()` now refuses the fallback when there is a CoOpt install to
   lose, leaving the target untouched. A folder with no CoOpt still gets the fallback.
3. **Command injection via `AABackupPath`.** `ensureDir` built `mkdir "<path>" 2>nul` for
   `os.execute` with no escaping, from free text in `itemui_layout.ini` (EMU communities pass config
   bundles around). Inside double quotes cmd protects `& | < > ^`, so the exploit needs a literal
   quote to break out. `pathIsShellSafe()` rejects `"`, `%`, CR and LF — the only characters that can
   escape a quoted cmd argument — and falls back to the default folder with a message. Rejecting `%`
   costs nothing real: Lua's `io.open` never expands `%VAR%`.

---

### 2.9 — `7528c4e` A missing plugin asset must not read as a successful update · **High**

`Build-Smart -Release` pushes the manifest commit to master (`:2142`) and only afterwards runs
`gh release create … --draft` (`:2166`). For that window — and while the release stays a draft —
raw master serves a manifest whose `plugins/MQ2CoOptUI.dll` entry points at an asset that does not
exist. `patch()` treated every 404 as "removed from repo, skip", then returned success. Clients got
the new Lua, silently failed to get the new DLL, and were told *"Update complete."*

Repo-path 404s keep the skip semantics; entries carrying an explicit `url` (only the release-asset
DLL) now stop the patch and tell the user to retry shortly. Build-Smart additionally warns when a
release would publish a manifest with **no** plugin entry at all (which `-Target CoOptOnly` /
`-SkipPlugin` silently do).

**Deliberately not fixed here:** the pipeline ordering itself. See §3.4.

---

### 2.10 — `120009a` Test runner hygiene · Low

The runner hardcoded this machine's Build-Smart output directory as the first place to look for
LuaJIT — exactly the machine-specific value that should not be committed. Now discovered via
`$env:COOPT_LUAJIT`, `luajit` on PATH, or any Build-Smart output tree up to two levels under a drive
root. **A SKIPPED test now exits non-zero**: this gates a release, and "I could not run" must not
look like "everything passed". Verified by running with no arguments on a clean shell.

---

## 3. Unresolved findings

The fan-out produced 65 verified findings; 10 are fixed above. The rest are below — the ones that
matter individually, then the full inventory.

### 3.1 — Default sell configuration is aggressive, and epic protection is dormant

**Severity: High risk / product decision — potential release blocker. Not changed.**

Every template-vs-code-default difference pushes the same way:

| Key | Code fallback | Template ships | Effect |
|-----|---------------|----------------|--------|
| `minSellValue` | 50 | 0 | no value floor |
| `minSellValueStack` | 10 | 0 | no stack floor |
| `maxKeepValue` | 10000 | 0 | no high-value keep |
| `protectLore` | TRUE | FALSE | lore items sellable |
| `protectQuest` | TRUE | FALSE | quest items sellable |

`rules.lua:willItemBeSold` step 19 is `return true, "Sell"` and `sell_batch.lua:108` sells
everything with `willSell == true`. With no floor and no ceiling, any droppable item no explicit
rule protects is sold. Separately `epic_classes.ini` ships **all 16 classes FALSE**, so
`epicItemSet` is empty and `protectEpic=TRUE` does nothing until the player enables their class.

**Concretely:** `epic_items_warrior.ini` contains **droppable** components — Diamond, Black
Sapphire, Jacinth, Green/Red Dragon Scales, Block of Permafrost, Rejesiam Ore, Tiny Lute. None are
in any shipped keep list. A player who skips the wizard, opens a merchant and clicks Auto Sell
vendors them.

**Mitigations that exist:** `protectNoDrop`/`protectNoTrade` TRUE cover most epic *gear*; curated
keep lists; a Preview button; the wizard ships enabled. **This is documented and deliberate**
(`docs/DEFAULT_SETTINGS.md:106,109` — *"do it, or epic protection/looting stays dormant"*), which is
why I did not change it three weeks from release.

**Recommended next action.** Decide one of: (a) accept as-is; (b) make the wizard's epic-class step
unskippable, or default the player's current class to TRUE on first run; (c) have Auto Sell refuse
to run — once, with an explanation — while `protectEpic=TRUE` and zero classes are enabled. **(c) is
the smallest change that closes the gap without altering anyone's saved config.**

---

### 3.2 — Plugin-less AA import is still inaccurate, only now it says so

**Severity: High (magnitude unproven). Partially addressed in §2.5.**

The warning is honesty, not a fix. On a partially-trained character without the plugin, import
still plans against inflated ranks. I could not quantify the error — that needs the game.

**Decide:** ship a *warned-but-inaccurate* import, or disable Export/Import when `hasRankTruth()`
is false. I judged disabling too blunt (it works for the common fresh-alt case), but it is a close
call and I would not argue against the stricter choice.

---

### 3.3 — `sell_cache.ini` is the whole protection contract between the UI and `sell.mac`

**Severity: High. CONFIRMED. Not changed — the obvious fix is riskier than the bug.**

Three findings converge here:

- **`storage.lua:230`** — when the UI decides nothing should be sold it writes `count=0`, and
  `sell.mac:123-125` sets `useSellCache` from `count > 0`. So "nothing to sell" is indistinguishable
  from "no cache", and the macro falls through to its own legacy ladder (`sell.mac:364-470`), which
  knows nothing about reroll ids, favorites ids, or keep entries beyond chunk 1.
- **`storage.lua:232`** — the cache identifies items by **name only**, so ID-based reroll/favorites
  protection cannot protect a same-name different-ID item (common on EMU servers).
- **`sell.mac:342`** — cache mode bypasses the protection rules entirely (by design: the UI already
  decided), and `sell_cache.ini` is never invalidated, never character-scoped, and never deleted
  after a run.

**Why I did not fix it.** The natural fix — an explicit `[Meta] valid=1` authority marker — was
examined by the verifier and rejected: `sell_cache.ini` is rewritten from several paths
(`main_loop.lua:1148`, `item_ops.lua:218,999`), so the marker latches and never clears, converting a
fail-open bug into a fail-closed one. That trade needs in-game testing I cannot do.

**Mitigating context:** `sellMode` ships as `lua`, so the macro sell path is not the default. That
lowers the exposure but does not remove it — `runSellMacroLegacy` still exists and users can switch.

**Recommended next action:** second pass decides between (a) making `count=0` unambiguous with a
marker *plus* clearing it at every rewrite, or (b) removing the legacy fallback so the macro refuses
to sell without a valid cache rather than substituting its own rules.

---

### 3.4 — The release pipeline publishes the manifest before the assets exist

**Severity: High. CONFIRMED. Client half fixed (§2.9); build half deliberately not.**

`Build-Smart.ps1:2142` pushes the manifest commit, then `:2166` creates the release **as a draft**.
Two further confirmed issues sit in the same stage:

- **`:2109`** — `-Release` bumps `version.lua` *after* the zips are built, so a bundle cut with an
  explicit `-Version` reports the previous version inside while being named with the new one.
- **`:2120`** — the manifest is generated from the working tree with no clean-tree requirement, so
  hashes can describe files GitHub will never serve.

**Why not fixed:** reordering a release pipeline needs an end-to-end release to verify, and I cannot
cut one. A naive reorder also breaks tag semantics (`gh release create` would tag the wrong commit).

**Recommended next action, in this order:** (1) require a clean tree before generating manifests;
(2) bump `version.lua` before Stage 3 computes the source hash, or assert after staging that the
staged `version.lua` matches `$Version`; (3) publish the release and its assets **before** pushing
the manifest commit, keeping the tag pinned to the release commit.

---

### 3.5 — Plugin `RulesEngine` diverges from the Lua ladder and never reloads

**Severity: Medium. CONFIRMED. Not changed — C++, and I could not build or test the plugin.**

- **`RulesEngine.cpp:366`** — `WillItemBeSold` has **no favorites protection**, and evaluates
  never-loot / augment-sell triggers **before** NoDrop/NoTrade/Epic/Keep. The Lua ladder
  (`rules.lua:288-352`) does the opposite, deliberately. So sell/loot decisions differ depending on
  whether the plugin is loaded — a perfect "works for me, not for them" generator.
- **`MQ2CoOptUI.cpp:509` / `RulesEngine.cpp:322`** — rules load once at plugin init and never
  reload; the `AutoReloadOnChange` setting is read but never acted on. Loot Loot/Skip decisions are
  frozen at client-start state, so rule changes made during a session are ignored until restart.

**Recommended next action:** treat the Lua ladder as the specification and bring the C++ into line,
or have the plugin defer the sell decision to Lua entirely. Needs the plugin toolchain; second pass
or post-release.

---

### 3.6 — Corrections to the fan-out's own findings

Recording these so the second reviewer does not re-derive them, and as a calibration note.

1. **"Macros read only chunk 1 of every list, so long lists are silently truncated"** (reported as
   High, twice) — **overstated.** I checked: the Lua UI never writes `exact2`/`contains2` for keep
   lists at all; chunking there is a *manual* convention the macro itself suggests
   (`sell.mac:982`). And the epic list, which the UI *does* chunk automatically, is consistent —
   `rules.lua` writes `chunk1..chunk4` and `sell.mac:785-790` reads `chunk1..chunk4`. The real
   defect is narrower: `sell.mac` reads `exact2`/`exact3` for **Always-Sell** lists but only `exact`
   for **Keep** lists, so a power user who splits a keep list following the macro's own advice
   silently loses protection on chunks 2+. **Medium, not High.**
2. **The `config_templates/config/CoOptCore.ini` omission from `default_config_manifest.json`** is
   harmless — `core/Config.cpp:CreateDefaultIfMissing()` writes byte-identical defaults on first
   load. Not a finding.

---

### 3.7 — Full inventory of remaining verified findings

53 further findings survived verification. Not reproduced in full here — each has complete evidence,
failure scenario, proposed fix and an independent verifier's reasoning in the workflow journal:

```
C:\Users\jtlat\.claude\projects\C--Claude-CooptUI\8e7a4d27-6786-4424-8b5f-9ff7e071ac3a\subagents\workflows\wf_b1368079-63e\journal.jsonl
```

The ones I would look at first, by theme:

**False success / unverified completion (async-timing, all PLAUSIBLE — need in-game confirmation)**
- `main_loop.lua:1759` — equip FSM treats "still on cursor after 250 ms" as a displaced item, stows
  it, and reports "Equipped".
- `main_loop.lua:570` — script-item consume treats a 500 ms timeout as success, and the optimistic
  stack decrement is persisted to disk.
- `main_loop.lua:526` — quantity picker sets the slider and clicks Accept in the same frame; the
  destroy FSM in the same file inserts a 100 ms settle between the identical two notifies.
- `sell_batch.lua:296` — merchant-selection wait is a fixed frame count, not elapsed time, and the
  timeouts are tuned for a LAN/local server.
- `scan.lua:285` — post-loot incremental scan can overwrite a concurrent full scan with a 5-frame-old
  snapshot, and the plugin version counter then prevents correction.

**Patcher robustness**
- `patcher.py:486` — the Update path installs `MQ2CoOptUI.dll` but never wires `[Plugins]` in
  `MacroQuest.ini`, so "I already have MacroQuest" + Update reports success while nothing loads.
- `updater.py:336` — `install_default_config()` writes non-atomically; an interrupted write leaves a
  truncated file treated as installed forever.
- `updater.py:200` — every network failure collapses to one message, and the patcher writes no log
  file at all. This is why tester reports are vague; **fixing it would improve every future report.**
- `installer.py:111` — `ensure_plugin_keys()` rewrites the preserved `MacroQuest.ini`
  non-atomically and re-encodes it, corrupting non-ASCII EQ paths and server names.
- `installer.py:305` — its failure is discarded, so an unwritable ini yields an install that reports
  complete with no plugins enabled.

**C++ plugin (crash risk — I changed no C++ and could not build it)**
- `InventoryScanner.cpp:37` (High, PLAUSIBLE) — `OnPulse` dereferences
  `pLocalPC->GetCurrentPcProfile()` with no null check or game-state guard: a client crash during
  zone or character handoff.
- `InventoryScanner.cpp:109` — `catch(...)` blocks publish partial results as complete, and cannot
  catch the access violations they were written to contain.

**First-run / config**
- `layout_io.lua:73` — clearing the toggle keybind never persists; an empty stored value is
  discarded on load and `shift+q` is re-bound every restart.
- `config_filters_actions.lua:113` — filter add/remove rewrites the whole list from a possibly stale
  cache, deleting entries written by another running client.
- `app.lua:1422` — first launch after upgrading on a character with no legacy marker may overwrite a
  customised shared layout with the bundled default.

**Dead / ineffective code**
- `main_loop.lua:1048` — the post-loot incremental scan is dead (deps omit
  `startIncrementalScan`/`processIncrementalScan`), so every loot run ends with a full blocking
  scan. *Same root cause as the equipmentCache bug I fixed: a deps table that silently tolerates
  missing keys.* See §4.
- `native_bridge.lua:209` — the native AA status line is a Label, which `Window.SetText` cannot
  write, so the arm-then-confirm Import flow gives no on-screen feedback.
- `commands.lua:88` — `/itemui center` silently opens the stock Tip of the Day when the skin is not
  loaded.
- `.github/workflows/luacheck.yml:29` — the CI gate skips two Lua payloads that ship
  (`scripttracker`, `coopt_launcher.lua`).
- `build/build.py:52` — a documented release path still omits `uifiles/coopt` and
  `coopt_launcher.lua`.

---

## 4. Process findings

Two patterns caused several of the defects above. Both are cheap to close and would pay for
themselves.

**(a) The main-loop deps table fails silently.** `main_loop.lua` reads `d.<key> or {}` /
`if d.<key> then`, so a missing key degrades to a no-op instead of an error. That is how the
equipped-item guard (§2.7) and the incremental scan (§3.7) both became dead code without anyone
noticing — including the review that *added* the guard. **Recommend:** assert at
`mainLoop.init(deps)` that every key main_loop consumes is present, listing any that are not. ~15
lines, and it converts a class of silent bugs into a startup error.

**(b) Nothing checks templates against code defaults.** I ran that comparison mechanically for this
review (extract every `readINIValue(file, section, key, default)` from `lua/`, compare against
`config_templates/`). It found exactly the six intentional differences in §3.1 and nothing
unexpected — a clean signal. The `[Debug]` keys escaped it only because they are read through a
constant (`LAYOUT_INI`) rather than a string literal, which is why they survived until now. I also
diffed the two layout files: 0 value conflicts, 7 keys present only in `default_layout`, all
consistent. **Recommend:** fold this into `scripts/tests/` extended to resolve constant-named INI
paths. It would have caught `c46dd42` *and* the previous pass's `protectEpic` automatically.

---

## 5. Validation results

Everything below was actually run. Nothing is marked passed that I did not execute.

| Check | Result |
|-------|--------|
| `luacheck lua/itemui lua/coopui` — baseline | **PASSED** — 0/0, 91 files |
| `luacheck` — after all changes | **PASSED** — 0/0, 91 files |
| LuaJIT compile sweep over `lua/` — baseline | **PASSED** — 94 files, 0 failures |
| LuaJIT compile sweep — after all changes | **PASSED** — 94 files, 0 failures (this is also the 60-upvalue gate the new deps entries could have breached) |
| `python -m compileall patcher build scripts` | **PASSED** |
| `scripts/tests/run-tests.ps1 -All` | **PASSED** — 4 passed, 0 failed, 0 skipped |
| `test_skin_sync.lua` (vcpkg LuaJIT) | **PASSED** — 20/20 |
| ↳ same test vs **pre-fix** code | **FAILED as intended** — 7 failures |
| `test_reroll_service.lua` (vcpkg LuaJIT) | **PASSED** — 16/16 |
| ↳ same test vs **pre-fix** code | **FAILED as intended** — 9 failures, incl. the cache being overwritten |
| `test_patcher_preflight.py` | **PASSED** — preflight + downgrade-guard assertions |
| Mapped-image lock probe (`ctypes.WinDLL`) | **PASSED** — detected only while mapped |
| `Build-Smart.ps1` AST parse | **PASSED** — 0 errors |
| `Build-Smart.ps1 -Target CoOptOnly` | **PASSED** — `CoOptUI-v0.9.8.zip`, 487 KB, 156 files |
| Build cache behaviour (4 runs, fixed) | **PASSED** — cold re-stages; no-change skips; skin edit re-stages |
| ↳ same 4 runs vs **pre-fix** script | **REPRODUCED THE BUG** — skin edit left hash `cdef8061efe2…` and reused the stale zip |
| Zip content audit (final build) | **PASSED** — 156 files: `uifiles/coopt` (4), `coopt_launcher.lua`, 40 templates, **0** personal `Macros/*.ini`; `[Debug]` reads `ItemOps=0 Scan=0 Loot=0` in **both** layout files; `onboarding_complete=FALSE` |
| `release_manifest.json` integrity | **PASSED at baseline** — 111 entries, 0 missing, 0 stale, 0 hash drift |
| `default_config_manifest.json` integrity | **PASSED** — all 43 `repoPath`s resolve |
| Template vs code-default sweep | **PASSED** — 6 differences, all documented (§3.1) |
| Layout-file cross-diff | **PASSED** — 0 value conflicts |
| Secret scan (tracked files) | **PASSED** — no matches |
| Machine-path scan (tracked source) | **PASSED** — no matches |
| Final-diff scan (debug leftovers / machine paths / secrets) | **PASSED** — none introduced |
| Machine-path scan (tracked docs) | **FINDING** — §3.7 / developer docs only |

### Not executed, and why

| Check | Why |
|-------|-----|
| `Build-Smart.ps1 -Target FullBundle` | ~19 min cold; self-clones MacroQuest/Mono/E3. `CoOptOnly` exercises the CoOpt staging path my changes touch. **The second pass must run a FullBundle build** — I changed files it stages differently. |
| Plugin DLL build | Needs CMake 3.30 + pinned MSVC 14.44.35207 and a warm vcpkg tree. I changed no C++ — which is also why every C++ finding in §3.5/§3.7 is unaddressed. |
| Anything in-game | Cannot launch the client. All such items are in §7. |
| A real patch/release against GitHub | Would hit the live release and write to a real install. The `updater.py` 404 change (§2.9) is reasoned from code, not executed. |

### Manifest state — action required before release

`release_manifest.json` matched the committed tree **exactly** at baseline. My changes leave these
manifest-listed files hash-drifted: `lua/itemui/app.lua`, `lua/itemui/services/skin_sync.lua`,
`lua/itemui/services/reroll_service.lua`, `lua/itemui/services/main_loop.lua`,
`lua/itemui/services/aa_transfer.lua`, `lua/itemui/views/aa.lua`,
`lua/itemui/views/config_general.lua`, `lua/itemui/default_layout/itemui_layout.ini`.

This is normal — manifests regenerate at release, never mid-development, because clients fetch them
from raw `master`. **Do not regenerate now.** Regenerate at release, then re-run the integrity check.

---

## 6. Second-review handoff

### Challenge these assumptions of mine

1. **That `lfs` may be absent in MQ2Lua.** I could not confirm either way; `skin_sync` was its only
   consumer and its author hedged. If `lfs` is always present, §2.3 Problem 1 was latent rather than
   live — the fix is still correct and Problem 2 is real regardless.
   **Check:** `print(pcall(require,'lfs'))` on a real MQ2Lua. **Expect:** `true <table>` if present.
2. **That the randomised MQ tray holds `MQ2Main.dll`/`imgui.dll` mapped.** My probe assumes it.
   **Check:** start the tray with no game running, call `find_locked_files(<mq root>)`.
   **Expect:** a non-empty list. If empty, the probe still catches an injected client but misses the
   tray-only case, and §2.1 is only half-fixed.
3. **That plugin-less AA import materially under-imports.** Traced, not measured. **Check:** with
   the plugin unloaded, export from a partially-trained character and import onto one missing ranks
   in the same lines. **Expect:** fewer ranks bought than the file contains, with no error shown.
4. **That `sellMode=lua` makes §3.3 secondary.** I inferred this from the shipped template.
   **Check:** confirm no shipped path still calls `runSellMacroLegacy` by default.

### Riskiest changes from this pass

1. **`preflight_blockers()` gating all three write paths** (`d6dd50a`). A false positive blocks
   updating entirely. **Verify it does not trigger on a clean, closed install** — §7 test 15.
2. **`reroll_service` deferred init** (`5cbc69a`). Lists now stay empty until the character
   resolves. If `getRerollListStoragePath` could *never* resolve for some user, they would get no
   reroll lists at all rather than wrong ones. **Check:** normal login shows populated lists on the
   first Reroll Companion open.
3. **Reroll deletion now requires `sync.equipKnown`** (`5cbc69a`). If `refreshEquipmentCache` ever
   throws, entries are never auto-cleared and pending accumulates. Deliberate (fail toward keeping
   user data), but confirm Sync still clears genuinely-not-owned entries — §7 test 25.
4. **`skin_sync.sync()` returns a second value** (`1a7783f`), and `app.lua` wraps it in `pcall`,
   which shifts return positions. Re-read `app.lua:1345`.
5. **`updater.py` 404-on-`url` is now fatal** (`7528c4e`). If a release legitimately ships without
   the DLL asset while the manifest lists it, updates now fail instead of partially succeeding.
   That is the intent, but it makes release ordering (§3.4) load-bearing.
6. **`ctx.theme.TextWarning` in the AA view** (`a595f4f`). Symbol verified to exist; not rendered.
   **Check:** open the AA tab with the plugin unloaded.

### Rerun these

- `scripts/tests/run-tests.ps1 -All` — **expect 4 passed, 0 failed, 0 skipped**. It now exits
  non-zero on a skip; a skip is not a pass.
- The §5 manifest integrity check, **after** regenerating manifests at release.
- A **FullBundle** build, then audit the EMU zip for: `uifiles/coopt`, `coopt_launcher.lua`,
  `config\e3 Macro Inis` seeds, `[Debug]` channels reading `0` in the staged
  `Macros/sell_config/itemui_layout.ini`, and `onboarding_complete=FALSE`.

### Verified sound — no need to re-derive

- **Sell-rule precedence** (`rules.lua:288-352`): reroll → favorites → NoDrop → NoTrade → Epic →
  Keep-exact all precede every sell trigger. The invariant holds **on the Lua path**. (The C++ path
  does not — §3.5.)
- **Plugin AA reads are live**: `getOwnedRanks` reads `pLocalPC->GetCurrentPcProfile()` with no C++
  cache; Lua caches 100 ms. No cross-character staleness.
- **Plugin zone handling**: `OnBeginZone` → `InvalidateAll()`, `OnEndZone` → `InvalidateInventory()`.
- **`CoOptCore.ini`'s absence from the default-config manifest is harmless** — the plugin writes
  byte-identical defaults on first load.
- **The keybind fix reaches existing installs**: `MQ2CustomBinds.txt` is create-if-missing only, but
  `ensureItemUIBindExists()` re-issues `/custombind set … /timed 1 /inv` every startup.
- **`ItemUIToggleKey` defaults to `shift+q` in code**, matching the README.
- **Epic list chunking is consistent** — 4 chunks written, 4 read (§3.6).

### Suspicions I could not prove

- **`NativeHover.render` runs on every frame from frame one**, deliberately above
  `main_window.lua:316`'s early-out and `pcall`-wrapped, i.e. before `loadLayoutConfig()`. I believe
  it is safe; confirm hovering a native slot during startup does nothing odd.
- **`charName == ""` after the 30 s timeout** skips `ensureCharFolderExists()` *and* the entire
  first-run layout block (`app.lua:1408-1435`). Reachable only at character select; nothing
  autostarts itemui (`ingame.cfg` is just `/mono e3`), so I rate it low.
- **`coopui_plugin.getPlugin()` caches `false` permanently.** `/plugin MQ2CoOptUI load` *after*
  starting itemui leaves the session in Lua fallback. Correct as designed; useful when diagnosing
  "it works after I restart the script".
- **AA Import's first click is a deliberate no-op** when the AA scan has not run
  (`aa_transfer.lua:521`). Handled and visible, but it *is* a first-attempt-fails shape and may be
  exactly what a tester reported. Confirm the message is visible in both windows.

### Largest unreviewed surface

`Macros/loot.mac` (2017 lines) and `Macros/sell.mac` (1176 lines). I verified the Lua-side rule
precedence and spot-checked the chunking claims (§3.6), but did **not** line-by-line audit
macro/Lua parity. `/doloot` still runs `loot.mac` on the default path.

---

## 7. Manual validation checklist

For a human tester with the game. Each item states the expected result.

### Clean install and first launch
1. **Fresh Install into an empty folder.** Completes; summary reports files written, CoOpt applied,
   config preserved; no `WinError`.
2. **First `/lua run itemui`.** Version banner, toggle-key line, and the **welcome / setup wizard**.
3. **Console is quiet.** **No** `[CoOpt Debug: Scan|ItemOps|Loot]` lines during normal play.
   *(Regression check for `c46dd42` — broken before this pass.)*
4. **`Macros/logs/coopui_debug.log`** stays absent or empty during normal play.
5. **Shift+Q toggles the window.** No crash. *(Guards `fe94976`.)*
6. **Complete the wizard including the epic-class step**, then confirm `epic_classes.ini` has your
   class `=TRUE`. *(§3.1.)*
7. **On a second clean install, skip the wizard**, open a merchant, click **Preview** (not Auto
   Sell). Record whether gems or epic components appear as "will sell". *(§3.1 — this is the
   evidence the second pass needs to decide.)*

### Native skin
8. **Settings → General → "Install skin (optional)".** Expect *"CoOpt skin installed…"*. If it
   fails, the message must name the **real** cause (folder could not be created / files could not be
   written), **not** "check that MQ and EQ paths are available". *(Regression check for `1a7783f`.)*
9. **`/loadskin coopt`**, then check Merchant (Auto Sell + Preview), Actions (CoOpt tab),
   `/itemui center`, native AA (Export/Import). All present.
10. **Make `<EQ>\uifiles\coopt` read-only, restart itemui.** Expect a printed warning that the skin
    could not be updated — **not** silence.

### Upgrade over an existing install
11. **Patcher → Update** on an install with customised keep lists and a saved layout. "All files
    verified"; `Macros/*_config/*.ini` and `itemui_layout.ini` **unchanged**; ScriptTracker settings
    preserved.
12. **Run the patcher twice.** The second run reports "Up to Date" and writes nothing.

### Live-install guard *(the §2.1 fix — most important new behaviour)*
13. **Start MacroQuest, leave the tray running, close the game**, then Patcher → Update. **Blocked
    before any write**, message naming a locked file. *(The case the name-only check missed.)*
14. **Same, but via Fresh Install** pointed at that install. **Blocked.** *(Previously unguarded.)*
15. **With everything closed**, run Update. **NOT blocked.** *(False-positive check — the most
    important negative test of this pass.)*

### Interruption and recovery
16. **Kill the patcher mid-download.** Relaunch detects remaining work and completes; no corrupt
    files.
17. **Kill the patcher mid-write.** Re-running completes the install, and the failure message says
    it stopped part-way and that re-running finishes it.
18. **Disconnect the network, then Update.** Expect a clear failure and **no** "Update complete".
    *(Relates to §2.9 and the §3.7 logging gap.)*

### Reroll protection *(the §2.7 fixes — data loss)*
19. **Add items to the aug and mythical reroll lists**, then `/lua stop itemui` and
    `/lua run itemui`. Lists still populated.
20. **Start CoOpt at character select** (or via the native Command Center Start button before
    logging in), then log in. **Reroll lists must still be populated** and
    `Macros/sell_config/Chars/<name>/reroll_lists.lua` unchanged. *(This is the data-loss case.)*
21. **Type `!auglist` directly in chat** (not the Refresh button). **The CoOpt aug list must not
    empty.** *(This is the second data-loss case.)*
22. **Click Refresh in the Reroll Companion.** The list still repopulates correctly — the fix must
    not have broken the legitimate path.
23. **Add a mythical to the reroll list, equip it, then Sync in the guild hall.** Expect *"Equipped
    — unequip to sync"* and the entry **kept**. *(Previously deleted as "not owned".)*
24. **Same with an augment socketed into worn gear.** Known residual gap — record what happens.
25. **Add an item, destroy or sell it, then Sync.** Expect it to be cleared as "not owned" —
    confirming the stricter guard did not disable legitimate cleanup.

### Invalid / missing config
26. **Delete `sell_flags.ini` and restart.** Safe defaults — note the code fallback is *stricter*
    than the template.
27. **Truncate an INI mid-line and restart.** No crash; fallback to defaults; an entry in
    Settings → Advanced → Recent Errors.
28. **Make `Macros/sell_config/` read-only and change a setting.** A visible failure, not a silent
    one.

### AA transfer
29. **With `MQ2CoOptUI` unloaded, open the AA tab.** Expect the warning *"AA rank data unavailable
    — Export/Import may be incomplete"* with a tooltip. *(New in `a595f4f`.)*
30. **With the plugin loaded**, expect **no** warning.
31. **Set `AABackupPath` to a path containing a `"` character**, then open AA Export. Expect it
    ignored with a message and the default folder used — **and no command executed**. *(Regression
    check for the injection fix.)*
32. **Export, then import onto an alt.** Compare the AA window before/after against the file.
    *(§3.2.)*
33. **Click Import immediately after `/lua run itemui`.** Expect *"Scanning AA tables — click Import
    again in a moment"*, then success on the second click. Confirm it is visible in **both** the
    ImGui and native windows.

### Restart / rollback
34. **Restart the client** after all of the above. Layout, settings and reroll lists persist.
35. **Restore a settings backup.** Settings return and the UI reflects them without a restart.

---

## 8. Deferred improvements

| Item | Benefit | Risk of leaving | Scope | When |
|------|---------|-----------------|-------|------|
| Decide the §3.1 sell-default posture | Closes the one data-loss path I could construct end to end | High if a player hits it | Product decision + possibly a small guard | **Second pass — blocking decision** |
| Assert main-loop deps completeness (§4a) | Kills a whole class of silent dead-guard bugs; two already found | Medium — it has recurred | ~15 lines | **Second pass** |
| Template-vs-code-default check in `scripts/tests/` (§4b) | Catches automatically the bug class that has shipped twice | Medium | ~40 lines | **Second pass** |
| Fix release ordering (§3.4) | Clients stop seeing manifests before assets | High at each release | Pipeline reorder + clean-tree gate | **Second pass — before cutting the release** |
| Resolve the `sell_cache` contract (§3.3) | Removes the fail-open legacy fallback | Medium (mitigated by `sellMode=lua`) | Needs in-game testing | Second pass |
| Align C++ `RulesEngine` with the Lua ladder (§3.5) | Removes plugin-vs-Lua behaviour divergence | Medium–High | Needs the plugin toolchain | Second pass or post-release |
| Patcher log file + specific network errors (§3.7) | **Would make every future tester report actionable** | Medium | Small | Second pass |
| Null-guard `InventoryScanner::OnPulse` (§3.7) | Client crash on zone/character handoff | High if real, unproven | Small, but C++ | Second pass |
| Disable AA Export/Import without the plugin (§3.2) | Removes a known-inaccurate path | Medium | Small; `hasRankTruth()` exists | Second pass |
| ScriptTracker PIN persistence, or delete the dead INI | Removes a phantom setting and two pointless protections | Low | Small | Post-release |
| Record `[Sound]` defaults | Completes the defaults record | Low | Doc only | Post-release |
| Purge old machine paths from developer docs | Contributors can follow them | Low | Doc only, ~5 files | Post-release |
| Audit `loot.mac`/`sell.mac` parity with `rules.lua` | Largest unreviewed surface | Medium–High, unmeasured | ~3200 lines of macro | Post-release |

---

## 9. Conclusion

**Ready for second review with known risks.**

Conditions:

1. **§3.1 (default sell posture + dormant epic protection) is an open decision, not a finding I
   closed.** It is the one plausible path to player data loss I could construct end to end. The
   second pass should decide explicitly rather than inherit it.
2. **The release pipeline (§3.4) must be fixed before cutting the release.** I fixed the client half
   only. Publishing the manifest before the assets exist is a live problem at every release.
3. **Manifests must be regenerated at release** and the §5 integrity check re-run. Eight shipped
   files are hash-drifted by this pass; that is expected and must not be "fixed" now.
4. **A FullBundle build has not been run.** I ran only `-Target CoOptOnly`, and I changed files
   FullBundle stages differently. Run one and audit the zip per §6.
5. **Nothing in this pass was verified in-game.** Every fix is backed by static analysis, unit tests
   on the game's own LuaJIT, or mechanical repo checks — never by running the client. §7 is not
   optional, and tests 15, 20, 21 and 25 are the ones I would run first.
6. **No C++ was reviewed by execution.** The plugin findings in §3.5 and §3.7 — including a possible
   client crash — are unaddressed because I could not build or run the plugin.

No single finding in this pass is a hard release blocker in my judgement. The §3.1 combination could
become one depending on the decision taken, and §3.4 will bite at release time if left alone.
