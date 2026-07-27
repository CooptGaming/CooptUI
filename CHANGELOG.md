# Changelog

All notable changes to CoOpt UI are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed
- **Fresh install restored to the proven layering** — the patcher's fresh install downloads the stock E3NextAndMQNextBinary bundle as the base again (full MacroQuest + Mono + E3 + the whole plugin ecosystem; a July change had pointed it at CoOpt's EMU zip, whose 16 from-source plugins left E3 missing MQ2AdvPath and friends on first boot), then applies CoOpt on top via the release manifest. Also survives Windows' 260-character path limit during extraction (the bundle's Mono tree exceeded it via the temp folder) and shows progress on GitHub's size-less zipball downloads.
- **MQ2CoOptUI plugin is disabled on stock-MQ installs** — the plugin links CoOpt's own MacroQuest build (MQ2Main/eqlib, statically embedded LuaJIT); loading it into the stock bundle's MQ corrupts the Lua runtime (crash in mq2lua when invoking a Lua-bound command like `/inv`; hard freeze on `/lua stop`). Fresh installs on the stock base now write `MQ2CoOptUI=0` and CoOpt UI runs fully in Lua/TLO fallback mode — every feature works, scans are just slower. Installs built on CoOpt's own MQ (the EMU bundle) keep the plugin on.
- **Toggle keybind routed through `/timed`** — MQ2CustomBinds executes bind commands on the keyboard-input path; deferring one tick onto the pulse path is harmless everywhere and avoids input-path re-entrancy on foreign MQ builds.

## [0.9.8] — 2026-07-26

### Added
- **Effects and Clickies reachable from every launcher** — the ImGui Command Center, the NATIVE Command Center, and the Actions window's CoOpt tab all gained Effects and Clickies buttons, so the two newest companions open from anywhere like the rest.
- **Sell Failed sound** — the sound service now actually defines the "Sell Failed" event the README promised (double beep by default; per-event toggle and custom .wav in Settings → Advanced → Sound Notifications).
- **Player guide + defaults record** — new `docs/PRODUCT_GUIDE.md` (every feature, first-time setup, workflows, commands — the Discord onboarding doc) and `docs/DEFAULT_SETTINGS.md` (what a fresh install does out of the box, and why).
- **Native AA window: Export / Import your AAs (CoOpt skin)** — the game's own AA window (where AA visibility and purchasing already work perfectly) gains CoOpt **Export**, **Import**, and **File** buttons stacked below Train and Hotkey, with a word-wrapping status line above Done. **File** cycles through your exports (newest first) to pick which one Import restores. Exports live in their own **`Macros\aa_backups`** folder now (they historically landed in `sell_config`, a leftover from the sell-manager days) — existing files are moved over automatically the first time the folder is used, and a custom `AABackupPath` is still honored. "Rebirth \<Class\>" entries are recognized as server-granted class markers and skipped on import (they stay in the export as a record of the spec), and any purchases that fail get one automatic retry pass — simple prerequisite chains resolve themselves on the second sweep. **Export** writes every purchased AA to `aa_<Character>_<date>.ini`. **Import** — for after a reset — re-buys everything from your latest export: first click reports how many ranks and AA points it needs and **refuses to run if you don't have enough points** (exact per-rank costs read from the AA table via the plugin); clicking Import again within 10 seconds starts it. Every purchase is **verified** — the rank must actually increase before the next buy fires (with timeout, retry, and a failure summary) — replacing the old fire-and-forget trainer. The CoOpt AA Browser's Export/Import buttons run on the same engine, and an import keeps running with every CoOpt window closed.
- **Native window strips (CoOpt skin)** — With the new CoOpt UI skin loaded (`/loadskin coopt`), CoOpt controls appear inside the game's **own windows**, driven by CoOpt UI through MacroQuest: the **Merchant window** gains Auto Sell, Preview (dry run), and a live status line (sell/keep/protected counts, macro progress), and the **Actions window** gains a **CoOpt tab** with launcher buttons for the companions. Routine vendoring no longer needs the CoOpt window open. Master toggle under Settings → General ("Native window strips"); everything no-ops unless the skin is loaded. The skin ships in `uifiles/coopt` and only overrides those windows — everything else stays your normal UI. (A loot-window strip was trialed and removed: launching the loot macro from an open corpse window reliably missed that corpse, so rules-based looting stays on `/doloot` and the Command Center's Loot All.)
- **Mythicals Companion** — New pop-out window (toolbar button + Actions-tab launcher) listing every Mythical item in your bags in the Augments Companion layout — Reroll button, icon, name, effects, value — for fast reroll-list triage.
- **Unusable-item indicator** — In the Augments and Mythicals Companions, items your character can't use render with a red name and show the reason (class/race/deity/level) on hover. Cached per item so it costs nothing per frame.
- **Command Center** — New pop-out control panel (toolbar "Cmd" button): live status (plugin connection, sell/loot macro state, guild hall), process controls (Loot All / Stop Loot, Auto Sell, ScriptTracker), and launcher buttons for every CoOpt window — everything reachable without the hub open.
- **Native inventory hover tooltips** — With the game's own Inventory window open, hovering a worn equipment slot shows the full CoOpt stats tooltip (same renderer as the Equipment Companion). Settings → General toggle, on by default. **With the updated MQ2CoOptUI plugin, this now extends to bag and bank slot contents** — the plugin resolves the nameless native slot windows through the game's own slot manager, so hovering any real item slot (worn, bags, open bank) shows the CoOpt tooltip. Without the plugin it stays worn-only.
- **Plugin window API (MQ2CoOptUI)** — the plugin now drives native windows directly: `setChecked` (strip buttons un-latch via a silent state write — no synthetic clicks, no mouse-capture risk, no notification echo; the settle delay stays, since touching a button inside its click window re-toggles it), `setText` (status lines on any label, not just EditBoxes), `click` (dispatches a real click notification to a native button's handler), and `getMouseOverSlot` (the bag/bank hover above). The Lua side auto-detects the capability and falls back to the old paths on older plugin builds.
- **CoOpt right-click menu on native slots** — **Shift+Right-click** any native item slot (worn, bags, open bank — plugin required for bag/bank) to open the same right-click menu the companions use: Clicky Lists, Add to Reroll, Move to Bank, Delete, and the rest. Plain right-click keeps its native meaning (use item / inspect) — the game always processes its own clicks, so the modifier avoids drinking a potion while opening its menu. The hover tooltip shows a reminder hint.
- **Effects Companion — buffs, songs, and auras in ONE window** — the game splits your effects across three windows and RoF2's buff windows can't be extended (no EQTypes), so the new **Effects** companion replaces them: every buff, song, and aura in one compact list with spell icons, hit counters, and color-coded time remaining (yellow under 2 minutes, red under 30 seconds). Two modes: detailed rows, or a dense **icon grid** with tiny time labels. Hover any effect for slot, exact time, and hits left; right-click to remove it. Auras are display-only. Toolbar "Effects" button; close the native buff windows if you want it as your only buff UI.
- **NATIVE Command Center** — The Tip of the Day window (nobody will miss it) is repurposed by the CoOpt skin into a fully native control panel: Loot All / Stop Loot / Auto Sell / ScriptTracker plus launcher buttons for every CoOpt window and a live status line (plugin + macro state). Open it with `/itemui center`, the EQ menu's Tip of the Day entry, or the "Native Panel" button in the ImGui Command Center. Titlebar, ESC-close, sizable — because it IS a native window.
- **Equipped-item inspect redirects to the CoOpt Item Display** — This server's custom item data garbles the stock inspect window's layout. Right-clicking a worn slot in the game's own Inventory window now opens the CoOpt Item Display for that slot — with full equipped enrichment (augment slots, worn totals) — and squashes the native window that pops. Settings → General toggle, on by default. Bag items stay with the CoOpt Inventory Companion, which already handles them.
- **Clickies (Favorites) Companion** — Create named clicky lists ("Buffs", "Damage", …) in the new Clickies window, then right-click any item → **Clicky Lists** to toggle it onto a list. Each list is a tab of one-click activation rows: icon (hover = stats), name, clicky effect with live cooldown, **Use**, and **Remove**. Items on any list are **protected from selling** (new "Favorites" protection layer, shown in sell status/preview) and from the **Delete** menu until removed from their lists. Lists persist per character alongside the reroll lists.
- **Command Center opens itself, with Start/Stop CoOpt buttons** — A tiny always-on `coopt_launcher` script (auto-started by itemui; add `/lua run coopt_launcher` to your MQ autoexec for login-time availability) opens the native Command Center automatically and owns its new **Start CoOpt** / **Stop CoOpt** buttons — so starting itemui + ScriptTracker is one native click even when nothing CoOpt is running. Bonus: characters with tips enabled get the Command Center at every login, courtesy of the Tip window's own auto-show.
- **Lock a window open** — Every companion window (Clickies, Effects, Bank, Augments, Mythicals, Reroll, AA, Equipment, Item Display, Augment Utility, Command Center, Loot) now has a **Lock** checkbox at its top right. A locked window simply stays up while you play: ESC, the toggle keybind (default Shift+Q), `/itemui hide`, and the hub's X all leave it open. Close it with its own X, or untick Lock. Locks persist per character in the layout.
- **Unified "Add to Reroll"** — One action everywhere instead of separate aug-list / mythical-list buttons: the UI routes each item automatically (name starts with "Mythical" → mythical list, augments → aug list). Applies to the right-click item menu, the Augments Companion's per-row button, and the Reroll Companion's **Add to Reroll (from Cursor)** — which now adds to the correct list no matter which tab is active.
- **"Recently looted" in the Inventory Companion** — New hidden-by-default **Acquired** column tracks when each item was first seen (stamps survive stack moves and reshuffles), a **Newest** button next to search sorts newest-first (click again to restore Name), and items looted since UI start show a green **NEW** badge by their name.
- **Sell Preview (dry run)** — New **Preview** button next to Auto Sell opens a modal listing exactly what would be sold, with quantity, value, total, and the rule behind each decision — catch config mistakes before the macro runs.
- **Quick loot rules** — Right-click any item name in the Loot window's looted list, Loot History, or Skip History → **Always loot this** / **Never loot this** (or undo a never-loot). Rules apply immediately to the real loot lists.

### Changed
- **The EMU bundle ships the curated defaults, not the maintainer's config** — Build-Smart's staging used to copy the working tree's `Macros` config INIs (personal keep/sell/loot lists) into the full bundle; it now replaces every config INI with the `config_templates` baseline, so bundle users start exactly where patcher/zip users do.
- **New-install defaults curated for new players** — `config_templates` now ships `protectEpic=TRUE` and `alwaysLootEpic=TRUE` (matching the code's own fallbacks — the templates used to ship FALSE, giving fresh installs *worse* epic protection than having no file at all), keeps augments by default (`sell_keep_types=Augmentation`; per-item exceptions via the Augment Always Sell list), and ships `enableLiveLootFeed=TRUE` so macro-path looting feeds the Loot UI live.
- **Personal config removed from the repo** — the maintainer's own `Macros/sell_config`, `Macros/loot_config`, and `Macros/shared_config` INIs (41 files: personal keep/sell/loot lists, onboarding state, runtime markers) are untracked; `config_templates/` is the only defaults source, exactly as the gitignore always intended. Release zips and the patcher were already template-only, so shipped installs are unchanged.
- **AA Browser drops the "(Work in Progress)" title** — browsing, training, and Export/Import are done features.
- **Actions window CoOpt tab** now holds 8 launchers in two columns (adds Loot UI and Settings), and the window's default width grew 124→150 so the extra tab and grid fit cleanly.
- **C++ plugin now enforces reroll-list protection natively** in both sell and loot rule ladders (ids pushed live from the UI). Previously the plugin's loot decisions could mark reroll-staged items as lootable.
- **Bank view updates while the bank stays open** when the plugin is loaded (deposits/withdrawals by in-game drag were invisible until reopen).
- **Performance** — major per-frame cost reductions across the UI: hover tooltips no longer rebuild full stat tables every frame (~85 TLO reads per hovered augment socket per frame eliminated), equipment refresh only rebuilds changed slots (~5,000 TLO evals/sec → ~60 while visible), the uiState proxy no longer allocates tables on every access, augment/candidate/filter/sort pipelines are cached instead of rebuilt per frame, history tables use clippers, sell progress polling is throttled, and idle-tick TLO window checks are skipped.
- **Patcher hardening for public release** — removed a faulty auto-migration that corrupted the shared core on every install; network failures now show actionable errors instead of freezing; downloads write atomically; verification failures show as failures (with Retry) instead of green "complete"; user keybinds (`MQ2CustomBinds.txt`) and ScriptTracker settings are preserved; MacroQuest-running is detected before patching; full-install extraction shows progress and disk-space errors.

---

### Fixed
- **Command Center window grew forever** — the per-window Lock checkbox was placed at a fixed offset from the window's right edge; when the checkbox rendered wider than the offset (font-scale dependent), the AlwaysAutoResize Command Center re-fit to the overshoot every frame and widened without end (and other windows could inherit odd widths from the same overshoot during auto-fit). The lock now right-aligns by measured width and can never extend past the content edge.
- **Game crash right-clicking Script items and reroll books** — the shared context menu's "Script of ..." and "Book of Mythical Reroll" branches closed the popup themselves and then the calling code closed it again (a leftover from the menu-contents refactor); the double EndPopup corrupted ImGui's window stack ("Missing EndTable()", overlay pause, script death). One close per popup now.
- **AA export recorded inflated ranks** — export read the character TLO's Rank (known to overstate partially-trained lines) while import plans against the plugin's true owned-ranks store, so a backup could claim ranks you never owned and a later import would buy them. Export and the AA Browser's Cur/Max column now use the same owned-ranks truth as import.
- **AA import's prerequisite ordering was a no-op** — the AA table's "requires" field arrives as a group-ID string, which never matched the name-keyed plan queue, so prereq lines imported in file order (and the "prereq not met: 487 (have 0)" report named bare ids). The scan now translates required-group → name; ordering, the timeout diagnosis, and the row tooltip's "Requires:" line all work from it.
- **AA import hardening** — retries keep the original group id (scan-invisible lines like rebirth-class AAs no longer fall back to the lying TLO and silently vanish from the failure report); the whole import freezes while zoning/dead instead of draining the queue as "out of AA points"; the flood settle holds when the owned-ranks read is unavailable instead of reconciling against an empty map; exports write to a temp file and rename (no truncated, valid-looking backups); a short-parsed backup now refuses to import in both entry points; a custom AABackupPath folder is created before first use.
- **AA Browser served stale rows after training** — the sort/filter cache key only changed when a rebuild was *requested*, not when it completed, so freshly rebuilt ranks kept showing old Cur/Max until you changed tabs. The cache now invalidates on rebuild completion (any trigger, including the Refresh button), and the tab/search filter pass is cached too instead of re-running per frame.
- **Two quick reroll adds could revert a confirmed one** — the server-ack slot was single: a second "Add to Reroll" re-armed it before the first confirmation arrived, so the first add's 10s timeout rolled back an entry the server had actually accepted (losing its sell protection until a refresh). Acks are now tracked per item id.
- **Reroll Sync cleared equipped pending items** — the "not owned anywhere → clear from pending" self-heal only checked bags and bank; a pending mythical you'd equipped was dropped as "Not owned". Worn gear now counts, with an "Equipped — unequip to sync" reason.
- **Sell-settings edits didn't refresh visible statuses** — protection-flag toggles, epic class selection, and value-threshold edits wrote the INI and cache but skipped the change event, so open windows kept advertising the old Will Sell ruling until an unrelated rescan (Auto Sell itself was always correct). All those paths emit the event now.
- **ESC double-action with the quantity picker** — one ESC that cancelled the quantity picker also closed your newest companion window in the same frame.
- **Native-first features died when everything was closed** — with the hub and all companions closed, the render early-out also skipped native hover tooltips, the Shift+Right-click native menu, and the equipped-inspect redirect — exactly the "play with native windows only" scenario they exist for. They now run on every frame.
- **Layout fixes** — the Equipment window's saved position/size survives layout file re-parses (one load path skipped those keys, letting defaults overwrite your saved spot); the Effects window is now included in save-as-default / reset-to-default; window drags no longer rewrite the entire layout INI every frame (six windows flushed to disk continuously while dragging); windows parked at the screen's left or top edge (x=0 or y=0) restore their position again.
- **Native Command Center launcher phantom clicks** — the standalone `coopt_launcher` un-latched Start/Stop without the settle delay the main bridge uses, so a click-and-drag-off could re-toggle the button and fire a spurious Start — or Stop — of CoOpt. Same guards ported over.
- **Steady-state overhead trimmed** — the window registry rebuilt its draw caches every frame (every open companion re-dirtied them after Begin); the Command Center probed the ScriptTracker TLO every frame for a value only used on click; skin files now write atomically (a crash mid-copy can no longer leave a truncated EQUI xml for the next `/loadskin`).
- **Plugin hardening (MQ2CoOptUI)** — window-name lookups bound their input (an oversized name tripped a CRT abort in MQ core's fixed buffer — process death, no SEH); owned-AA slot reads clamp the table index to the proven-safe GetAAById range; `getOwnedRanks` gains the same AA-manager guard as its siblings (a faulted read could return an empty table that import would treat as "owns nothing"); `click` is restricted to real buttons (clicking a list child passed a null row index to the parent handler); item Class/Race display no longer shows "All" for most multi-class items (popcount, not raw-mask compare); the cursor scanner null-checks the profile during shroud/char handoff.
- **Docs and tooltips truth pass** — `/itemui setup` now actually starts the wizard (it toggled setup mode into a step that rendered nothing, printing "Step 0 of 8" for a 13-step wizard); the tutorial no longer promises a "re-open from Settings" option that doesn't exist (names the real commands), describes the Settings tabs as they are, and covers Effects/Clickies/Mythics/Command Center in the companions step; Auto Sell texts no longer tell Lua-mode users to run a macro; the epic-classes dropdown no longer reads "All classes (none selected)" when none selected means *inactive*; Clicky-list protection shows as "ClickyList" in sell status instead of the old "Favorites"; ScriptTracker docs say `/st` (the `/scripttracker` bind never existed); Loot UI "Suppress" note points at the real setting; keybind mentions show your actual configured key; plus a dozen smaller corrections across README/INSTALL and window texts.
- **The CoOpt skin now ships — as an optional install** — no release channel (patcher manifest, CoOpt UI zip, EMU deploy) actually included `uifiles\coopt` or the `coopt_launcher` script, so every native-window feature would have arrived dead for patched users. All three channels now carry them under the MacroQuest folder. Because EQ loads skins from its **own** uifiles folder (not MacroQuest's), the skin is **opt-in**: nothing touches your EQ client unless you click **Install skin (optional)** in Settings → General (or copy `uifiles\coopt` over yourself). Once installed, itemui keeps that copy current on startup — updating changed files and deleting retired ones (the trialed loot-window strip) so stale overrides with dead buttons can't linger. itemui also no longer tries to start `coopt_launcher` when the script isn't installed.
- **Worn clickies work with Clicky Lists** — right-clicking a worn item in the Equipment Companion never offered the Clicky Lists menu (the menu silently dropped id-keyed entries for equipped items), and the Clickies window treated anything not in bags as missing. Worn items now show in your lists with a "(worn)" tag, live cooldown, working stats hover, and a **Use** button that activates them in their equipment slot — so epics and other worn clickies are first-class list citizens.
- **Equipped-inspect redirect no longer dies with unrelated toggles** — turning off native hover tooltips silently disabled the redirect (they shared an early-out), and turning off the native-strips master toggle disabled the redirect's squash of the native window. Each feature now honors only its own setting.
- **AA Browser only lists abilities your character can actually see** — the full id-space scan surfaced every AA in the game's table, including other classes' lines (e.g. Rebirth for classes you don't have active) and unavailable Special entries (the "breath" line). With the updated plugin, the scan is filtered from the AA table itself: class lines must include your class in their class mask (the server maintains those per character, which is how multi-class actives surface), and granted-only (quest) abilities you don't own are hidden. Bonus: the filtered scan finishes near-instantly. Without the plugin it falls back to the old full scan.
- **AA Browser: an empty scan no longer loops** — a character with no visible AAs re-triggered the full id-space scan endlessly while the window was open ("Scanning AA tables..." forever). An empty result now counts as a completed scan and waits for a real change (zone/level/points) before rescanning.
- **Reroll Sync won't clear pending items blind** — the "not owned anywhere → clear from pending" self-heal now also requires actual bank knowledge (live window or cached contents), so a banked item on a character whose bank was never scanned can't be silently dropped from pending.
- **Buttons left visually "pushed in"** — a strip button whose un-latch state was wiped by window churn is now detected as stale on next sight and pops back out on its own.
- **loot.mac honors a pre-targeted corpse on its first pass** — opening a corpse flags it "looted" and `/hidecorpse looted` hides it from `/tar npccorpse`, so a corpse you'd already peeked at was skipped by loot runs. If you target a corpse before `/doloot`, the macro now loots it first (first pass only, so skipped-items corpses can't loop).
- **Reroll Sync self-heals bank/not-owned pending items** — a pending item that's in the bank now reports "In bank — move to bags to sync" instead of a generic failure, and one you no longer own anywhere (sold, rolled, consumed) is cleared from pending automatically instead of sticking forever. (The pending list's per-item Remove button remains for manual cleanup.)
- **AA Browser only showed General AAs** — the scan iterated AA ids 1–2000 and bailed after 50 consecutive empty ids, but the emu's class/archetype AA ids live far above that in a sparse id space. The scan now covers the full id range, chunked across main-loop ticks (no frame hitch, "Scanning AA tables..." shows while it runs), deduped by name, serving the old list until the rebuild completes.
- **AA Browser tabs now sort correctly** — tab placement used the Category *string*, which is a live-EQ database lookup that comes back empty on the emu, dumping everything into General. Tabs now use the numeric Type field — the same field the game's own AA window uses — so General/Archetype/Class/Special populate properly (and the Category column shows the derived name). With the full list correct, the existing **Export/Import** buttons in the AA Browser cover spec-swap workflows: Export snapshots your purchased AAs to a file, Import re-trains them one rank per frame.
- **The CoOpt toggle keybind (default Shift+Q) and `/itemui hide` close every CoOpt window again** — after companions became hub-independent, hiding the hub left them open; both paths (and the hub's X button) now LIFO-close all companion windows including the Loot UI.
- **ESC now closes CoOpt windows no matter how they were opened** — companions launched from the native Actions tab (or with the hub closed entirely) ignored Escape; the LIFO close handler now runs independently of the hub window, so ESC always closes the most recently opened CoOpt window first.
- **Native-strip toggles load as real booleans** — the layout loader returned them as numbers, and `0` is truthy in Lua, so off toggles behaved as on. (The auto-loot-on-corpse experiment this surfaced was later removed: closing the freshly opened corpse window mid-handshake fought the client, so rules-based looting stays on the loot window's CoOpt: Loot All button, which works reliably.)
- **Native launcher buttons only worked while the CoOpt hub was open** — companion windows (Bank, Augments, Mythicals, Reroll, AA, Settings, …) now render independently of the hub window, so the Actions-tab launchers open them any time.
- **Reroll Sync could leave items stuck "pending"** — items already on the server list are cleared from pending instead of being re-sent (the top stuck cause); late server confirmations now complete the bookkeeping even after the wait window; the wrong-item-on-cursor case is detected before sending; sync stops cleanly if you leave the guild hall; only one track can sync at a time; pickup/confirm timeouts raised (0.8s→1.5s, 5s→10s); and the pending list now shows each item with a **Remove** button for manual cleanup.
- **Augment Utility suggested augments your deity can't use** — the usability check trusted the game's CanUse property, which doesn't reflect the server's deity restrictions; deity is now always verified ("only show usable" and tooltips honor it).
- **Sell rules: protections now always win.** Items on the never-loot list that were also NoDrop, epic, or on your Keep list could be sold ("sell to clear inventory" ran before protections). Protections (NoDrop → NoTrade → Epic → Keep) now run first, matching sell.mac's canonical order.
- **Keep lists longer than ~2000 characters were silently truncated** for sell decisions (the UI showed items as Keep; the seller didn't). All keep/valuable/augment lists now read every chunk.
- **Stale sell cache could sell newly-kept items** — when everything became protected, the old cache file survived and sell.mac's cache mode (which skips all rule checks) still sold from it. An empty computed list now writes an empty cache.
- **Right-click item menu was dead with default columns** in Inventory and Bank (it only rendered when the hidden-by-default Icon column was enabled). The menu now works regardless of column setup.
- **Settings changes now take effect immediately** — the deferred sell-status refresh after config changes was a no-op (Status column stayed stale until an unrelated rescan); loot flag/value changes never invalidated the loot rules cache; list adds via right-click could be erased by a later Filters-tab removal (stale cache write-back).
- **Filter conflict dialog never opened** (ImGui popup ID scope) — adding a conflicting entry silently did nothing. The conflict-resolution dialog now appears.
- **Macros: standalone `/else` lines never execute in MQ2** — epic protection loaded zero items in sell.mac's fallback mode, and single-entry always-loot lists never matched in loot.mac. All six sites converted to valid brace syntax.
- **Loot receipts counted items that were never looted** (decisions were logged before the loot attempt; failed loots and lore-duplicate aborts inflated totals and history). Accounting now happens only after a verified pickup.
- **Aborted loot runs no longer wedge the UI** — a bags-full abort (or crash) left `running=1` in the progress file forever, freezing the Loot window state and blocking inventory persistence. The macro now writes a heartbeat and finishes cleanly on inventory-full; the UI treats a 30s-stale heartbeat as not-running.
- **UI can now be closed at the bank** — the X button and Escape were immediately overridden by the bank auto-show; also fixed the loot-window/bank flicker fight.
- **AA window: training no longer fires from stray input** — pressing Enter (e.g. to chat) or double-clicking anywhere could spend AA points; both now require the window focused and the row actually hovered.
- **Augment Utility "Fill with best" could stick at "Optimizing 0/0"** and re-run a stale plan against wrong slots after inventory changed; the plan is now copied, invalidated on completion, and the button disabled while running.
- **Equip auto-confirm only answers the attunement dialog for attuneable items** (it previously clicked Yes on any confirmation dialog that appeared during the equip window).
- **First launch on an alt no longer resets your customized layout** (the first-run marker is account-wide now, not per-character).
- **Item tooltips can no longer crash the game on a mid-render error** (ImGui child/columns are rebalanced if a stat load fails while zoning); item-validity guards no longer fail open on nil IDs.
- **Reroll list refresh no longer picks up stray guild chat** during the 6-second parse window ("meet at 5:30" could become a bogus list entry that then protected item ID 5).
- **Roll after bank moves waits for the last move to finish** (stacked items could trigger the roll before the server saw all 10 items).
- **Destroy now verifies the right item is on the cursor** before `/destroy` (a failed pickup could destroy whatever was actually held).
- **Loot decisions on the no-plugin path**: clicky and NoDrop detection used checks that never fired (`lootClickies` was dead; NoDrop never flagged). Also fixed `lootClickies` treating every item as a clicky on the live-loot feed, and aligned loot defaults (tribute override 1000, clickies on) with loot.mac.
- **Sound test button** reported valid sound files as missing when MQ's working directory wasn't the EQ root.
- **ScriptTracker** now notices stack-size changes (looted scripts merging into stacks, partial consumes) instead of only slot-count changes.
- **Layout round-trips**: Loot-view width survived cold starts, AA sort column persists, Settings remembers the Advanced tab, and layout files are written atomically (a crash mid-write can no longer blank your layout).
- **Welcome wizard**: the environment checklist now expands when something failed (it collapsed exactly when you needed it), gained a Re-check button, and default sell protection actually seeds on first run.

## [0.9.7] — 2026-06-16

### Added
- **Consumables list** — Right-click any item → **Add to Consumables**. Items on the list get **Use (consume one)** and **Use all (xN)** options that right-click/consume them in-game (e.g. "Book of Titles"). The list is the safety gate, so only items you flag ever show a consume option.
- **Patcher — Full Install / Repair** — Point the patcher at any folder (an empty one, a vanilla MacroQuest you downloaded, the E3 distribution, or an existing CoOpt install) and it downloads the complete bundle and installs everything needed, **preserving your config** (EQ path, server list, character data, sell/loot rules). Fresh-install and update now share this one preserve-aware installer.
- **CI** — luacheck static-analysis gate on every push/PR, catching undefined-global / use-before-declaration bugs before release.

### Fixed
- **E3 crash on launch** — The distributed bundle was *deleting* required E3 runtime files (e.g. `Saved Groups.ini`), so E3 died on load with "Error: Please reload. Terminating." Those files are now emptied, not deleted.
- **Reroll — Remove** no longer crashes the UI.
- **Reroll — Sync** now works per item: pick up → add → **wait for the server's confirmation** → put back, and confirmed items are removed from the to-be-synced list. (Previously items got stuck on the cursor and never confirmed.)
- **Equip attuneable items** — The attunement dialog is now auto-confirmed (items no longer bounce back to your bags).
- **Augment ranking** — Heroic stats are now scored correctly (were treated as base stats).
- **First-run onboarding** — New installs now correctly show the welcome/setup wizard.
- Several internal crash-class fixes (filters/searchbar helpers, layout reset) and companion-window render isolation so one window's error can't take down the whole UI.

### Build
- MacroQuest pinned to a known-good commit (upstream `master` regressed with a missing `eqlib/game/ClassInfo.h`).
- `E3.dll` is now packaged even when an auxiliary E3Next project (E3NextSysTray) fails to build.
- MSVC toolset pinned and additional from-source build fixes for a reliable clean build.

---

## [0.9.0-beta] — 2026-03-01

### Added
- **Patcher version tracking** — After a successful patch, the patcher writes the manifest version to `Macros/coopui_installed_version.txt` so support can see what version players have. Patcher UI shows "Installed: X · Available: Y" when updates are available and "Up to date (vX)" when current. ItemUI startup message uses this file when present so patcher users see the same version in-game.

---

## [0.8.9-alpha] — 2026-03-01

### Added
- **Script consume verification** — Right-click "Add to Alt Currency" on scripts now waits for the chat message `[timestamp] You gained 1 alternate currency.` (or 2s timeout) before sending the next click, so all consumes are confirmed and no scripts remain after refresh
- **script_consume_events.lua** — New module that listens for the alternate-currency chat line; main loop uses per-click confirmation

### Changed
- **Default layout** — Equipment Companion window included in bundled default (`ShowEquipmentWindow=1` and position/size), so new installs and "Revert to default" show the Equipment window by default
- **Release manifest** — Regenerated; script_consume_events and related files in RELEASE_AND_DEPLOYMENT.md

---

## [0.8.8-alpha] — 2026-03-01

### Changed
- **Release process** — Config templates in release zip now sourced from `config_templates/` (includes `itemui_layout.ini`); release rule and manifest steps documented
- **Patcher** — Skip files that return 404 (e.g. removed from repo) instead of failing the whole patch

---

## [0.8.7-alpha] — 2026-03-01

### Added
- **Phase E complete** — Debug framework (8.1), Welcome environment validation (8.2), Backup & Restore (8.3), Fresh install bootstrap readiness (8.4)
- **CoOpt UI branding** — UI text and tab labels aligned (Task 2.5)
- **Patcher migration** — `migrate_itemui_to_coopui.py` for itemui→coopui folder migration (Task 3.5)
- **Advanced Settings tab** — Debug channel toggles, Backup & Restore export/import
- **ARCHITECTURE.md** — Canonical architecture reference

### Changed
- Master at stable pause point; plugin work archived as inactive

---

## [0.8.5-alpha] — 2026-02-23

### Added
- **Default layout snapshot system** — Standalone `coopt_layout_capture.py` to capture a reference layout from an MQ folder; outputs `default_layout/` with normalized `itemui_layout.ini`, CoOpt UI-only `overlay_snippet.ini`, and `layout_manifest.json`
- **First-run default layout** — When no existing layout exists, CoOpt UI applies the bundled `lua/itemui/default_layout/` into `Macros/sell_config/` and merges overlay snippet into `config/MacroQuest_Overlay.ini`
- **Revert to Default Layout** — Settings window button with confirmation modal; applies bundled default, force-applies companion window positions/sizes for several frames so they reposition without closing the UI; main window position applies after restarting MacroQuest (documented in dialog)
- **DEFAULT_LAYOUT.md** — Documentation for capture, first-run, revert, patcher contract, and revert diagnostics/fixes

### Fixed
- Capture script: `[Window][Title]` key parsing now uses `index("]", 9)` so full window title is captured (was empty, so no `[Window]` blocks were in overlay_snippet.ini)
- Deploy merge: same key parsing fix when merging overlay snippet into existing MacroQuest_Overlay.ini
- Revert: companion windows now actually move/resize after revert by using `ImGuiCond.Always` for position/size for a few frames when `layoutRevertedApplyFrames > 0` (was only applying on first show via FirstUseEver)

---

## [0.8.0-alpha] — 2026-02-22

### Changed
- Version bump to 0.8.0-alpha
- Patcher: patch log (list of altered files) now remains visible after patching so players can scroll through it

---

## [0.7.1-alpha] — 2026-02-22

### Changed
- Version bump to 0.7.1-alpha

---

## [0.7.0-alpha] — 2026-02-22

### Changed
- Version bump to 0.7.0-alpha

---

## [0.4.2-alpha] — 2026-02-20

### Changed
- Version bump to 0.4.2-alpha

---

## [0.4.0-alpha] — 2026-02-16

### Changed
- Version bump to 0.4.0-alpha

---

## [0.3.0-alpha] — 2025-02-13

### Added
- Configuration reference documentation (`docs/CONFIGURATION.md`)
- Installation guide (`docs/INSTALL.md`)
- Developer documentation (`docs/DEVELOPER.md`)
- Troubleshooting guide (`docs/TROUBLESHOOTING.md`)

### Fixed
- Release workflow version prefix bug: zip name mismatch (`vv0.x` vs `v0.x`) that caused release asset upload to fail silently
- Build script now excludes dev-only files (`docs/`, `test_rules.lua`, `upvalue_check.lua`, `phase7_check.ps1`) from release zip

---

## [0.2.0-alpha] — Architecture overhaul

Major architectural redesign across 7 phases: performance optimization, unified filter system, SellUI consolidation, macro integration, layout management, and init.lua decomposition.

### Added
- **Instant open** — UI opens in ~15ms with cached data shown immediately (Phase 2)
- **Incremental scanning** — 2 bags per frame with per-bag fingerprinting; only changed bags rescan (Phase 2)
- **Unified filter system** — Item Lists tab with add/remove for all sell and loot lists (Phase 3)
- **SellUI consolidation** — All SellUI features merged into ItemUI; SellUI deprecated (Phase 4)
- **Macro bridge** — `/dosell` and `/doloot` integration with status feedback in UI (Phase 5)
- **Loot view** — Live corpse item evaluation when loot window is open (Phase 3)
- **Item tooltips on hover** — Rich item detail popups on mouseover (PR #3, #4)
- **Augments view** — Dedicated augmentation item display
- **Config window improvements** — Renamed tabs (General & Sell, Loot Rules, Item Lists), improved tooltips, Open Config Folder button (Phase 6.1)
- **Layout management** — `utils/layout.lua` module for window size, column visibility, sort persistence (Phase 7)
- **CoOpt UI shared core** — `lua/coopui/` with version, theme, events, cache, and state modules
- **Context registry pattern** — Single `refs` table via metatable proxy to stay under Lua's 60-upvalue limit
- **State consolidation** — `uiState`, `perfCache`, `sortState`, `filterState` tables to stay under 200-local limit
- **ScriptTracker auto-refresh** — Refreshes on inventory fingerprint change (PR #6)
- **init.lua decomposition** — 6 modules extracted: `window_state`, `item_helpers`, `icons`, `sell_status`, `item_ops`, `character_stats` (41% reduction, 2184 → 1293 lines)
- **Augment-specific lists** — Separate always-sell and never-loot lists for augmentation items
- **Never-loot sell integration** — Items on the never-loot list are also sold to clear inventory
- **Epic class filtering** — Per-class epic item protection via `epic_classes.ini`
- GitHub release workflow (`release.yml`) and build script (`build-release.ps1`)
- `DEPLOY.md` included in release zip

### Fixed
- Sell view keep/junk unchecking issue (PR #7)
- Bank drag save storm — debounced from 40+ saves to 1 save per drag (600ms debounce)
- Item slot parsing errors with augmentation nil values (PR #3)
- Duplicate sell list entries — atomic table replacement (PR #5)
- Sort state not persisting across close/reopen
- Column widths on first load (ImGui timing workaround)

### Changed
- **Performance** — 15ms UI open time (70% faster than 50ms target), 93% CPU reduction in macro polling
- Config tabs renamed: "ItemUI" → "General & Sell", "Auto-Loot" → "Loot Rules", "Filters" → "Item Lists"
- SellUI and LootUI deprecated — use ItemUI for all features
- Version bumped to 0.2.0-alpha

---

## [0.1.0-alpha] — Early alpha

First packaged release for early alpha testers.

### Added
- **ItemUI** — Unified inventory, bank, sell, and loot window (`/lua run itemui`, `/itemui`).
- **ScriptTracker** — AA script progress (Lost/Planar, etc.) via `/lua run scripttracker`.
- **Auto Sell** — `sell.mac` and `/dosell`; configurable keep/junk and epic protection.
- **Auto Loot** — `loot.mac` and `/doloot`; configurable filters and sorting.
- Config templates for sell_config, shared_config, and loot_config (first-time install).
- Epic item protection and class-specific epic lists in shared_config.
- ItemUI views: inventory, bank, sell, loot, config, augments; theme and layout support.

### Requirements
- MacroQuest2 with Lua (mq2lua) and ImGui.
