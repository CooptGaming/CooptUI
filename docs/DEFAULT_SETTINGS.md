# Default Settings Baseline

This is the **record of what a fresh CoOpt UI install does out of the box**, and why. It is the reference for anyone asking "what does a new player get?" — support answers on Discord should match this page.

Defaults live in three layers:

1. **Code fallbacks** — what the Lua/macro code assumes when an INI key or file is missing entirely.
2. **`config_templates/`** — the INI files a new install receives. The patcher (and the in-game welcome flow) installs a template **only if the file does not already exist**. Existing user files are never overwritten.
3. **Settings UI** — everything below is changeable in-game (Settings button or `/itemui config`).

Templates and code fallbacks are kept in agreement for the safety-critical flags (see table notes). If you change a default, change the template **and** check the code fallback, then update this page.

---

## Design philosophy for a new player

- **Protect first.** Nothing irreplaceable should ever be vendored by automation: NoDrop/NoTrade gear, collectibles, heirlooms, epics, augments. A new player who runs Auto Sell on day one should lose nothing they'd miss.
- **Loot conservatively.** A value floor keeps bags from flooding with 2-copper junk during the first farm session. Special items (mythicals, valuables, epics) are always grabbed.
- **Everything is reversible.** Keep/Sell decisions are lists the player edits with one right-click; nothing here is a commitment.
- **Automation is opt-in.** Bag sorting, clicky looting, and aggressive selling all start OFF.

---

## Sell defaults (`sell_config/`)

### Protection flags (`sell_flags.ini`)

| Setting | Default | Why |
|---|---|---|
| `protectNoDrop` | **TRUE** | NoDrop gear can never be re-acquired from a vendor. Selling it is always a mistake. |
| `protectNoTrade` | **TRUE** | Same reasoning as NoDrop. |
| `protectLore` | FALSE | Lore just means "own one" — most lore drops are ordinary vendor fodder. |
| `protectQuest` | FALSE | On this server the Quest flag appears on plenty of junk; real quest pieces are protected via keep lists/epics instead. |
| `protectCollectible` | **TRUE** | Collectibles feed achievements; irreplaceable for collectors. |
| `protectHeirloom` | **TRUE** | Heirlooms are account progression items. |
| `protectAttuneable` | FALSE | Unattuned attuneables are ordinary tradeable loot; protecting them freezes half your drops. |
| `protectAugSlots` | FALSE | "Has an augment slot" describes most gear; protecting it would neuter Auto Sell. Slotted augs are protected by the augment safety check instead. |
| `protectEpic` | **TRUE** | Epic quest pieces are the flagship protection. Class-gated by `epic_classes.ini` (see below). Matches the code fallback — do not ship FALSE. |
| `sellMode` | `lua` | Native Lua sell: faster, no macro slot used, same rules. `legacy` runs sell.mac. |
| `sellVerboseLog` | FALSE | Console spam is a dev tool. |

### Value rules (`sell_value.ini`)

| Setting | Default | Why |
|---|---|---|
| `minSellValue` | 0 | No value floor — only explicit rules decide selling. A floor surprises new players ("why did it sell my 5g item?"). |
| `minSellValueStack` | 0 | Same. |
| `maxKeepValue` | 0 (off) | "Auto-sell anything cheap" is an expert opt-in. |
| `tributeKeepOverride` | 1000 | Items with ≥1000 tribute are kept even if marked junk — high-tribute junk is worth more donated than vendored. |
| `sellWaitTicks` / `sellRetries` / `sellMaxTimeoutSeconds` | 18 / 4 / 60 | Server-friendly pacing; slow merchants on a laggy night still complete. |

### Lists

| File | Default | Why |
|---|---|---|
| `sell_keep_types.ini` | **Augmentation** | Augments are progression items; Auto Sell never vendors them. Per-item exceptions: right-click an augment → "Augment Always sell". |
| `sell_protected_types.ini` | Food/Drink/Alcohol/Potion/Bandages/Arrow/Throwing/Key/Lockpicks/Compass | Consumables and tools you'd have to buy back. |
| `sell_keep_exact.ini` | Wrapped Presents, Charm of Lore | Event/collector items with vendor prices that lie about their value. |
| `sell_keep_contains.ini` | Heirloom / Heritage / Commemorative / Fragment of / Familiar / Illusion Benefit / Fabled / Globe of | Name families that are always special on EMU servers. |
| `sell_always_sell_*.ini` | empty | "Always sell" is personal taste; starts empty. |

---

## Loot defaults (`loot_config/`)

### Flags (`loot_flags.ini`)

| Setting | Default | Why |
|---|---|---|
| `lootClickies` | FALSE | Clicky-hunting floods bags; opt-in for collectors. |
| `lootQuest` / `lootCollectible` / `lootHeirloom` / `lootAttuneable` / `lootAugSlots` | FALSE | Each of these turns a broad category into "always loot" — expert opt-ins. |
| `alwaysLootEpic` | **TRUE** | Epic pieces are grabbed even when other rules would skip them. Class-gated by `epic_classes.ini`. Matches the code fallback — do not ship FALSE. |
| `lootDelayTicks` | 2 | ~200 ms between loot actions; safe on slower systems. Drop to 1 for speed on a good connection. |
| `approachWaitTicks` | 8 | Time allowed to reach a corpse before skipping it. |
| `maxLoopIterations` | 1000 | Safety abort (~500+ corpses); prevents infinite loops on pathing failures. |
| `pauseOnMythicalNoDropNoTrade` | **TRUE** | NoDrop/NoTrade mythicals pause the run and ask — auto-looting one is a permanent decision. |
| `alertMythicalGroupChat` | TRUE | Tell the group when a mythical drops; farming crews want this. |
| `quietMode` | FALSE | New players should see what the looter is doing. |

### Value rules (`loot_value.ini`) — values are in **copper**

| Setting | Default | Why |
|---|---|---|
| `minLootValue` | 2000 (2 pp) | Non-stackable items under 2 pp are left on the corpse — the anti-bag-flood line. |
| `minLootValueStack` | 500 (5 gp) | Stackables accumulate, so the per-item floor is lower. |
| `tributeOverride` | 0 (off) | Tribute-based looting is an expert opt-in. |

Always-loot lists (`loot_always_*.ini`) start empty except the shared valuable lists below. Skip lists ship with a few known-worthless server drops (`Mutant finger bones`, `Terror sphere`, `Lump of Pus`).

### Sorting (`loot_sorting.ini`)

| Setting | Default | Why |
|---|---|---|
| `enableSorting` | FALSE | Automation that reorganizes your bags is opt-in — surprising a new player's bag layout is worse than a messy bag. |
| `enableWeightSort` | FALSE | Same. |

---

## Shared defaults (`shared_config/`)

| File | Default | Why |
|---|---|---|
| `valuable_types.ini` | Ornament / Augmentation / Universal Augment Solvent / Augmentation Remove Solvent | Always loot, never sell — augment economy items. |
| `valuable_contains.ini` | Legendary / Mythical / Heirloom / Heritage / Commemorative / Shard of / Fragment of / Familiar / Illusion Benefit / Script of | Name families that are always worth grabbing on this server. |
| `valuable_exact.ini` | Wrapped Presents | Event item. |
| `epic_classes.ini` | **all classes FALSE** | Epic checks scan a large item list; scanning all 16 classes for every item is wasted work. The first-run wizard asks you to enable your class(es) — do it, or epic protection/looting stays dormant. |
| `epic_items_<class>.ini` | full per-class epic item lists | Generated from `epic_quests/`; don't hand-edit. |

> **The one thing a new player must do:** enable their class in **Settings → Item Lists → Epic classes** (or during the first-run wizard). `protectEpic`/`alwaysLootEpic` are ON but only act on enabled classes.

---

## Layout / diagnostics defaults (`sell_config/itemui_layout.ini`)

The same values ship in `lua/itemui/default_layout/itemui_layout.ini`, which the first run
applies when there is no saved layout. **Keep the two files in step** — a value fixed in only
one of them still reaches players through the other.

| Key | Default | Why |
|-----|---------|-----|
| `[Debug] ItemOps` / `Scan` / `Loot` | **0 (off)** | Debug channels print to the MQ console *and* append to `logs/coopui_debug.log`. `Scan` and `ItemOps` sit in hot paths and `Loot` fires per looted item, so leaving them on costs every player console spam and log writes for output only a developer reads. `core/debug.lua` defaults an unset channel to `"0"` — the templates must not ship worse than the code fallback. Players turn channels on in **Settings → Advanced → Debug** when reporting a bug. |

---

## What is intentionally NOT templated

- `sell_cache.ini`, `loot_history.ini`, `loot_session.ini`, `loot_progress.ini`, `loot_skipped.ini`, `skip_history.ini`, `loot_mythical_alert.ini` — runtime state, created as needed.
- `epic_items_resolved.ini` — generated by the UI for the macros.
- `Chars/` — per-character snapshots.
- `sell_augment_always_sell_exact.ini`, `loot_augment_skip_exact.ini` — personal per-item lists; the UI creates them on first use.
- `coopui_onboarding.ini` ships with `onboarding_complete=FALSE` so every new install gets the first-run wizard.

## Maintainer note

`Macros/sell_config`, `Macros/loot_config`, and `Macros/shared_config` INIs in a working checkout are **personal, untracked config** (gitignored). The only INI defaults in the repo are `config_templates/` — change defaults there, then update this page and `CHANGELOG.md`.
