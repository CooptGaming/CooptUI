# Plugin Expansion Design Memo: Moving ItemUI Behavior onto MQ2CoOptUI

**Date:** 2026-03-04
**Scope:** Evaluate candidates for moving Lua+TLO item behavior into the C++ plugin for consistency, reliability, speed, and snappy presentation.

---

## Executive Summary

The plugin currently provides fast native scanning (inv, bank, loot, sell) with core item fields, but scan results are plain tables that **lack the `__index` metatable** from `buildItemFromMQ`. This means the plugin path produces items missing ~48 stat fields, ~16 descriptive fields, wornSlots, augType/augRestrictions, and 4 of 5 spell effect IDs (only Clicky is populated). Tooltips, stat columns, augment compatibility, and sorting all degrade silently when the plugin path is active.

The highest-impact change is closing this data gap. Cursor and window stubs are lower priority but straightforward wins.

**Implementation status:** Phases A, B, C, and D are **complete** (verified post-implementation).

---

## Current Data Gap: Plugin Path vs TLO Path

| Field group | Count | Plugin path today | TLO path today | Impact of gap |
|---|---|---|---|---|
| Core (id, name, type, value, flags, icon, etc.) | ~17 | Populated | Populated | None |
| Clicky spell ID | 1 | Populated | Populated (lazy) | None |
| Proc, Focus, Spell, Worn spell IDs | 4 | **Missing (0)** | Lazy-loaded via getItemSpellId | Columns show "No" for all; sort broken for these; tooltip effects section empty |
| wornSlots | 1 | **Empty string** | Lazy-loaded from WornSlot(N) | Equipment-slot column blank; augment worn-slot compatibility fails |
| augType, augRestrictions | 2 | **Missing (nil)** | Lazy-loaded from AugType(), AugRestrictions() | Augment compatibility/ranking broken for aug items |
| Stat fields (AC, HP, STR, heroics, resists, etc.) | 48 | **Missing (nil)** | Lazy-loaded batch from TLO | Stat summary empty; tooltip stats section empty; augment ranking returns 0 |
| Descriptive fields (tribute, class, race, deity, etc.) | 16 | **Missing (nil)** | Lazy-loaded batch from TLO | Tooltip class/race/deity/req-level blank; tribute column zero |
| willSell, sellReason, willLoot, lootReason | 4 | Populated (Phase 5+) | Populated | None |

**Key insight:** The lazy-loading system in `buildItemFromMQ` uses a `__index` metatable that calls `getItemTLO` on first access. Plugin scan results are plain `sol::table` objects — they have no metatable, so any field not explicitly set is `nil`. The UI silently degrades rather than erroring.

---

## Capture-All Determination: Collect Every Definition-Time Field

**Decision: Capture ALL item data that comes from `ItemDefinition` (and trivial `ItemPtr`) in the scan, not just the subset the current UI uses.**

**Cost:** The scanner already has `ItemDefinition* def` in hand for every item. Reading more struct members is just additional memory dereferences — no new allocations, no TLO calls, no I/O. Adding 30–50 more fields is on the order of tens of nanoseconds per item. For 140 items the extra cost is well under 0.1 ms. Memory per item grows by roughly 100–200 bytes (more ints, a few strings); for 400 items that’s under 80 KB. Scan time today is already sub-millisecond; the increase is unmeasurable in practice.

**Benefit:** (1) **Single source of truth** — no “this field isn’t in the plugin, fall back to TLO” edge cases. (2) **Future-proofing** — new columns, tooltips, filters, or rules can use any field without another C++ change. (3) **Debugging and tools** — an in-game “dump all item stats” or analytics is trivial when the data is already in the table. (4) **No repeated “add this field” cycles** — one pass to align with the MQ item datatype doc and eqlib, then done.

**Conclusion:** The utility of having the full definition-time dataset in the plugin outweighs the negligible scan cost. Not every field will be surfaced in the UI immediately; having it in the table is still valuable.

**Definition vs runtime data:** We capture everything that describes the *item template* (from `ItemDefinition`, and from `ItemPtr` where it’s a simple property of the instance, e.g. stack count). We do *not* populate in the scan data that depends on **runtime context**: merchant state (BuyPrice, SellPrice, MerchQuantity), full-inventory aggregates (StackCount, Stacks, FreeStack, FirstFreeSlot), character state (CanUse), or cooldowns (TimerReady). Those remain TLO or a separate API if needed. Canonical reference: [MQ item datatype](https://docs.macroquest.org/reference/data-types/datatype-item/) and the `ItemDefinition` struct in eqlib for your build (EMU vs Live may differ).

---

## Candidate Area Assessments

### 1. Full Item Data from Plugin (Single-Item API + Scan Payload)

**Determination: WORTH DOING — Highest Priority**

**Benefit:** This is the single most impactful change. It closes every data gap in the table above. The `ItemDefinition` pointer that the scanner already holds contains every stat, descriptive, and spell field that Lua currently fetches via 50+ individual TLO calls per item. Reading them in C++ during the scan adds negligible cost (struct field reads, no API calls).

- **Consistency:** One source of truth. No more divergence between "scanned items" and "TLO-enriched items."
- **Reliability:** Eliminates the `_statsPending` / `_tlo_unavailable` failure mode where lazy TLO loading fails during zone transitions or window state changes, leaving items with permanently zeroed stats until the next scan.
- **Speed:** For 140 inventory items, lazy-loading stats on first tooltip hover requires ~48 TLO calls per item (~6,720 total if all items are hovered). With plugin data, this becomes 0. First hover is instant.
- **Snappy presentation:** Tooltips, stat columns, spell-effect columns, and augment compatibility all populate immediately on scan — no visual "pop-in" as lazy fields load.

**Risk assessment:**
- *Scope:* Medium. Adding ~70 fields to `CoOptItemData` and `ItemDataToTable` is mechanical but tedious. Mitigated by doing it in layers (see implementation outline).
- *Sync:* Field names must exactly match Lua's `STAT_TLO_MAP` keys and `DESCRIPTIVE_FIELDS` names. One-time alignment; a static_assert or test can guard it.
- *Memory:* Each `CoOptItemData` grows by ~300 bytes (mostly ints). For 400 items: ~120KB total — negligible.
- *Testing:* All views/tooltips/columns already work with these fields when populated by TLO. No behavior change, just different data source.

**Recommended approach — hybrid (scan extension + on-demand getItem):**

**Layer A+B (scan extension):** Add to scan results *all* definition-time fields: (1) everything the current UI uses (wornSlots, augType, augRestrictions, Proc/Focus/Spell/Worn spell IDs, STAT_TLO_MAP, DESCRIPTIVE_FIELDS), and (2) every other ItemDefinition/ItemPtr field from the MQ item datatype that is not runtime/context-dependent (see "Full field list" below). One scan-loop pass; one source of truth.

**Layer C (on-demand getItem):** Implement `items.getItem(bag, slot, source)` to return one item's full data from the live MQ item pointer, using the same populate helper as the scanners. Serves stale-cache refresh, cursor item details, etc.

---

### 2. Cursor Capabilities

**Determination: WORTH DOING — Low effort, good reliability win**

**Benefit:** `hasItemOnCursor()` is the most-called cursor check in the codebase (30+ call sites across 13 files). Today it calls `mq.TLO.Cursor()` each time. The plugin's `cursor::updateFromPulse()` already has the architecture to cache cursor state per-frame — the TODO just needs to be filled in with `pLocalPC->GetItemByGlobalIndex(eItemContainerCursor, 0)`.

- **Consistency:** Cursor state read from one authoritative source.
- **Reliability:** TLO.Cursor can return nil transiently (during item swaps, zone transitions). Plugin polling in OnPulse provides stable state.
- **Speed:** Frame-cached in `app.lua` already mitigates some overhead, but 4 files call `mq.TLO.Cursor` directly (reroll_service, config_filters_ui, main_loop, main_window) outside that cache.

**Risk:** Very low. `updateFromPulse` is 3 lines of MQ API. The Lua API (hasItem, getItemId, getItemName) is already registered — stubs just need real values. Lua call sites don't need to change immediately; they can migrate to `coopui.cursor.hasItem()` gradually.

**Implementation:** Fill in `updateFromPulse()` body, extend with `getItemType()` and `getItemLink()` (used by reroll_service). Done in one sitting.

---

### 3. Window Capabilities

**Determination: DO LATER — Partial benefit, complexity in action-oriented uses**

**Benefit:** Window state checks (`isWindowOpen` for BigBankWnd, MerchantWnd, LootWnd, InventoryWindow, QuantityWnd, ConfirmationDialogBox) appear in 28+ call sites. Moving `isWindowOpen` to the plugin avoids TLO calls and provides cached state.

However, the benefit is limited because:
- Window checks are **event-driven** (user opens bank, merchant arrives), not per-frame. They happen infrequently compared to item data access.
- The `window_state.lua` utility already centralizes the 4 main window checks. Migration requires changing only that file.
- **Complex uses can't easily move:** The sell state machine reads `MerchantWnd/MW_SelectedItemLabel` text to detect which item is selected. The destroy/move flows use `QuantityWnd` slider manipulation. The augment flow clicks `ConfirmationDialogBox` buttons. These require `getText`, `click`, and child-window interaction that are harder to implement reliably in C++ vs. MQ TLO/commands.

**Risk:** Medium. Simple `isWindowOpen` is trivial via `FindMQ2Window(name)->IsVisible()`. But `getText` and `click` on child windows require navigating CXWnd hierarchies, which is brittle if window XML changes. `/notify` commands are more resilient.

**Recommendation:** Defer to a later phase. The simple `isWindowOpen` for the 4 main windows could be done quickly but provides marginal benefit. The complex window interactions (getText, click) should stay as TLO/commands.

---

### 4. Augment Add/Remove, Delete, Alt Currency, Shift-Click from Bank

**Determination: NOT WORTH DOING NOW — High complexity, marginal benefit**

These are **action flows**, not data queries. They use getItemTLO for:
- Reading item properties before/during an action (augment_ops: 3 sites for Inspect)
- Getting augment socket info (augment_utility: 2 sites)
- Checking cursor state (augment_ops: 3 sites)

If `getItem` (Candidate 1 Layer C) and `cursor` (Candidate 2) are implemented, these flows would *naturally* benefit — they could call `coopui.items.getItem()` instead of `getItemTLO()` for data reads, and `coopui.cursor.hasItem()` instead of `mq.TLO.Cursor()` for cursor checks.

But the **actions themselves** (picking up items, placing augments, clicking confirmation dialogs, inspecting items) **must use MQ commands** (`/itemnotify`, `/notify`, Inspect()). Moving these to the plugin would mean reimplementing the entire state machines in C++, which is:
- High risk (behavior change in destructive operations)
- No speed benefit (actions are user-paced, not scan-paced)
- Maintenance burden (two implementations to keep in sync)

**Recommendation:** Let these flows naturally benefit from Candidates 1+2 for their data reads. Don't move the action logic itself.

---

### 5. Item Scanning Extension

**Determination: WORTH DOING — Part of Candidate 1**

This is the same as Candidate 1 Layers A+B. The remaining gap in scan results is per-item detail. Two approaches and their tradeoffs:

**Option A: Extend scan payload only.** All fields populated during scan. Pro: one read, all data available immediately. Con: slightly larger scan time (though still < 2ms for 140 items — struct field reads are nanoseconds).

**Option B: Lean scan + on-demand getItem.** Scans stay fast with core fields; tooltips/columns call `getItem(bag, slot, source)` for full data on first access. Pro: scan stays minimal. Con: still has a lazy-load boundary (C++ instead of TLO, but still a deferred load); Lua must implement the on-demand pattern; first access to any stat column triggers a C++ call per item.

**Option C: Both (recommended).** Extend scan results with all fields (Option A) for immediate availability. Also provide `getItem` (Option B) for cases where scan cache is stale or item isn't in a scan (cursor item, display item, item after augment insert). This gives the best of both worlds.

**Justification for including stats in scan results rather than deferring:**
- The `ItemDefinition*` pointer is already in hand during the scan loop. Reading 48 int fields from it costs ~0.1μs per item. For 140 items: ~14μs total. This is noise compared to the 0ms scan time reported in production.
- Every tooltip hover and every column render currently triggers 48+ TLO calls for the first item touched. Eliminating this entirely is worth the trivial scan overhead.
- Stat columns (AC, HP, etc.) are sortable. Sorting requires values for every item in the list. Without pre-populated stats, sorting a stat column triggers 48 TLO calls × 140 items = 6,720 TLO calls. With pre-populated stats: 0.

---

### 6. Other Areas Found

**mq.TLO.Spell for spell name/description/cast time/duration/range** (7 call sites in item_helpers.lua):

**Determination: NOT WORTH DOING**

These are already cached in Lua's L2 cache (by spell ID). Cache hit rate is very high because the same spells appear on multiple items. Moving spell lookups to C++ would eliminate TLO calls only on cache misses (rare). The implementation would require adding a `getSpellInfo(id)` API to the plugin and teaching Lua to call it — all for a few dozen cache misses per session. Not worth the complexity.

**mq.TLO.FindItem for lore duplicate check** (1 call site in scan.lua):

**Determination: ALREADY DONE**

The LootScanner (Phase 6) already does native lore duplicate checking via `FindItemByNamePred` in C++. The TLO.FindItem call in scan.lua only runs on the Lua fallback path (when plugin is absent). No action needed.

**mq.TLO.DisplayItem for augment ops** (1 call site in augment_ops.lua):

**Determination: NOT WORTH DOING**

Used once, for reading socket info from the item display window. Niche use case. Not worth a C++ API.

**mq.TLO.Me for character info** (item_tooltip.lua, app.lua):

**Determination: NOT WORTH DOING**

Character info (name, level, class) is read once at startup and rarely changes. No performance or reliability concern.

---

## Priority Order

| Priority | Area | Effort | Impact | Status |
|---|---|---|---|---|
| **P0** | **1A+B: Extend CoOptItemData and scan results** with all stat, descriptive, spell, wornSlots, augType, augRestrictions fields | Medium (2-3 days) | Closes all data gaps; eliminates ~6,700+ TLO calls per session; instant tooltips/columns | **Complete** |
| **P1** | **1C: Implement items.getItem(bag, slot, source)** returning full item data | Small (0.5 day) | On-demand fresh reads for augment ops, item refresh, cursor item | **Complete** |
| **P2** | **2: Implement cursor capabilities** (fill updateFromPulse, add getItemType/getItemLink) | Small (0.5 day) | Reliable cursor state; benefits reroll, config filters, main_loop | **Complete** |
| **P3** | **3: Simple window.isWindowOpen** for 4 main windows | Small (0.5 day) | Minor reliability win; only if time permits | **Complete** |

---

## Concrete Implementation Outline

### Phase A: Extend CoOptItemData and Scan Results (P0) — **COMPLETE**

**Full field list (definition-time only).** Use the [MQ item datatype](https://docs.macroquest.org/reference/data-types/datatype-item/) and eqlib `ItemDefinition` (and `ItemPtr` where applicable) as the canonical list. Below: what the memo already includes, plus **additional** definition-time fields to add so we capture everything.

| Category | Already in memo | Additional (capture all) |
|----------|-----------------|---------------------------|
| **Spell effect IDs** | Clicky, Proc, Focus, Spell (Scroll), Worn | **Focus2**, **Familiar**, **Illusion**, **Mount** |
| **Bools** | nodrop, notrade, lore, attuneable, heirloom, collectible, quest, norent, magic, prestige, tradeskills | **Stackable**, **LoreEquipped**, **NoDestroy**, **Summoned**, **Expendable** (if on def in eqlib) |
| **Numeric/string (definition)** | All STAT_TLO_MAP + DESCRIPTIVE_FIELDS + core | **ProcRate**, **OrnamentationIcon**, **LDoNCost**, **LDoNTheme** (string), **MaxLuck**, **MinLuck**, **WeightReduction**, **ContentSize**, **SlotsUsedByItem**, **Power**, **MaxPower**, **PctPower** (power source; float if needed), **Quality**, **Delay** (if distinct from ItemDelay in eqlib), **IDFile**, **IDFile2** (strings; icon/display), **RefCount** (if on def; else skip) |
| **Explicitly not in scan** (runtime/context) | — | BuyPrice, SellPrice, MerchQuantity (merchant); StackCount, Stacks, FreeStack, FirstFreeSlot (inventory aggregate); CanUse (character); TimerReady (cooldown); ItemSlot/ItemSlot2/InvSlot (we have bag/slot) |

Implementers must verify eqlib member names and presence per branch (EMU vs Live). Omit or guard fields that don’t exist on your target’s `ItemDefinition`/item struct.

**Step 1: Extend `core/ItemData.h`**

Add all missing fields to `CoOptItemData`, including the "Additional (capture all)" rows above. Group them to match Lua's field groups:

```cpp
struct CoOptItemData {
  // --- Existing core fields (unchanged) ---
  int32_t id = 0;
  int32_t bag = 0;
  int32_t slot = 0;
  std::string source;
  std::string name;
  std::string type;
  int32_t value = 0;
  int32_t totalValue = 0;
  int32_t stackSize = 1;
  int32_t weight = 0;
  int32_t icon = 0;
  int32_t tribute = 0;
  bool nodrop = false;
  bool notrade = false;
  bool lore = false;
  bool attuneable = false;
  bool heirloom = false;
  bool collectible = false;
  bool quest = false;
  int32_t augSlots = 0;
  int32_t clicky = 0;
  std::string wornSlots;
  bool willSell = false;
  std::string sellReason;
  bool willLoot = false;
  std::string lootReason;

  // --- NEW: Spell effect IDs (Proc, Focus, Spell, Worn) ---
  int32_t proc = 0;
  int32_t focus = 0;
  int32_t spell = 0;
  int32_t worn = 0;

  // --- NEW: Augment properties (for augmentation-type items) ---
  int32_t augType = 0;
  int32_t augRestrictions = 0;

  // --- NEW: Stat fields (match STAT_TLO_MAP keys exactly) ---
  int32_t ac = 0;
  int32_t hp = 0;
  int32_t mana = 0;
  int32_t endurance = 0;
  int32_t str = 0;
  int32_t sta = 0;
  int32_t agi = 0;
  int32_t dex = 0;
  int32_t _int = 0;  // "int" is reserved; Lua key is "int"
  int32_t wis = 0;
  int32_t cha = 0;
  int32_t attack = 0;
  int32_t accuracy = 0;
  int32_t avoidance = 0;
  int32_t shielding = 0;
  int32_t haste = 0;
  int32_t damage = 0;
  int32_t itemDelay = 0;
  int32_t dmgBonus = 0;
  std::string dmgBonusType;
  int32_t spellDamage = 0;
  int32_t strikeThrough = 0;
  int32_t damageShield = 0;
  int32_t combatEffects = 0;
  int32_t dotShielding = 0;
  int32_t hpRegen = 0;
  int32_t manaRegen = 0;
  int32_t enduranceRegen = 0;
  int32_t spellShield = 0;
  int32_t damageShieldMitigation = 0;
  int32_t stunResist = 0;
  int32_t clairvoyance = 0;
  int32_t healAmount = 0;
  int32_t heroicSTR = 0;
  int32_t heroicSTA = 0;
  int32_t heroicAGI = 0;
  int32_t heroicDEX = 0;
  int32_t heroicINT = 0;
  int32_t heroicWIS = 0;
  int32_t heroicCHA = 0;
  int32_t svMagic = 0;
  int32_t svFire = 0;
  int32_t svCold = 0;
  int32_t svPoison = 0;
  int32_t svDisease = 0;
  int32_t svCorruption = 0;
  int32_t heroicSvMagic = 0;
  int32_t heroicSvFire = 0;
  int32_t heroicSvCold = 0;
  int32_t heroicSvDisease = 0;
  int32_t heroicSvPoison = 0;
  int32_t heroicSvCorruption = 0;
  int32_t charges = 0;
  int32_t range = 0;
  int32_t skillModValue = 0;
  int32_t skillModMax = 0;
  int32_t baneDMG = 0;
  std::string baneDMGType;
  int32_t luck = 0;
  int32_t purity = 0;

  // --- NEW: Descriptive fields (match DESCRIPTIVE_FIELDS keys) ---
  // tribute already exists above
  int32_t size = 0;
  int32_t sizeCapacity = 0;
  int32_t container = 0;
  int32_t stackSizeMax = 0;
  bool norent = false;
  bool magic = false;
  bool prestige = false;
  bool tradeskills = false;
  int32_t requiredLevel = 0;
  int32_t recommendedLevel = 0;
  std::string instrumentType;
  int32_t instrumentMod = 0;
  std::string classStr;   // Lua key: "class"
  std::string raceStr;    // Lua key: "race"
  std::string deityStr;   // Lua key: "deity"

  // --- Capture-all: additional definition-time fields (MQ item datatype) ---
  int32_t focus2 = 0;
  int32_t familiar = 0;
  int32_t illusion = 0;
  int32_t mount = 0;
  bool stackable = false;
  bool loreEquipped = false;
  bool noDestroy = false;
  bool summoned = false;
  bool expendable = false;
  int32_t procRate = 0;
  int32_t ornamentationIcon = 0;
  int32_t ldoNCost = 0;
  std::string ldoNTheme;
  int32_t maxLuck = 0;
  int32_t minLuck = 0;
  int32_t weightReduction = 0;
  int32_t contentSize = 0;
  int32_t slotsUsedByItem = 0;
  int32_t power = 0;
  int32_t maxPower = 0;
  float pctPower = 0.f;
  int32_t quality = 0;
  int32_t delay = 0;
  std::string idFile;
  std::string idFile2;
  int32_t refCount = 0;  // only if on def in eqlib
};
```

**Step 2: Populate fields in scanners (InventoryScanner, BankScanner, LootScanner)**

In each scanner's scan loop, after the existing `ItemDefinition* def = item->GetItemDefinition()` line, add reads for the new fields. All reads are direct struct member access on `ItemDefinition` — no API calls, no TLO.

Key mappings (ItemDefinition member → CoOptItemData field):
- `def->AC` → `d.ac`
- `def->HP` → `d.hp`
- `def->Mana` → `d.mana`
- `def->Endurance` → `d.endurance`
- `def->STR` → `d.str`, etc. for all stats
- `def->HeroicSTR` → `d.heroicSTR`, etc.
- `def->SvMagic` → `d.svMagic`, etc.
- `def->SpellData.GetSpellId(ItemSpellType_Proc)` → `d.proc`
- `def->SpellData.GetSpellId(ItemSpellType_Focus)` → `d.focus`
- `def->SpellData.GetSpellId(ItemSpellType_Scroll)` → `d.spell`
- `def->SpellData.GetSpellId(ItemSpellType_Worn)` → `d.worn`
- `def->AugType` → `d.augType`
- `def->AugRestrictions` → `d.augRestrictions`
- `def->RequiredLevel` → `d.requiredLevel`
- `def->RecommendedLevel` → `d.recommendedLevel`
- `def->Size` → `d.size`
- `def->SizeCapacity` → `d.sizeCapacity`
- `def->Slots` (container capacity) → `d.container`
- `def->StackSize` (max stack) → `d.stackSizeMax`
- `def->NoRent` → `d.norent`
- `def->Magic` → `d.magic`
- `def->Prestige` → `d.prestige`
- `def->Tradeskills` → `d.tradeskills`

For wornSlots: iterate `def->EquipSlots` bitmask to build comma-separated slot names (same logic as Lua's `getWornSlotsStringFromTLO` but from the bitmask).

For class/race strings: iterate `def->Classes` and `def->Races` bitmasks to build "All" or space-separated class/race names.

For deity: iterate `def->Deity` (bitmask on EMU) to build deity string.

Capture-all additional fields: map from eqlib `ItemDefinition` (and `ItemPtr` where the property is on the instance) — e.g. `SpellData.GetSpellId(ItemSpellType_Focus2)`, `SpellData.GetSpellId(ItemSpellType_Familiar)`, etc., and the corresponding member names for ProcRate, LDoNTheme, Stackable, Power, MaxPower, PctPower, IDFile, IDFile2, etc. Confirm member names and presence in your target eqlib branch (EMU vs Live).

**Step 3: Extend `ItemDataToTable` in `capabilities/items.cpp`**

Add all new fields to the sol::table conversion. Use exact Lua key names:

```cpp
t["proc"] = d.proc;
t["focus"] = d.focus;
t["spell"] = d.spell;
t["worn"] = d.worn;
t["augType"] = d.augType;
t["augRestrictions"] = d.augRestrictions;
t["ac"] = d.ac;
t["hp"] = d.hp;
// ... all stat fields ...
t["int"] = d._int;  // C++ member name differs from Lua key
t["class"] = d.classStr;
t["race"] = d.raceStr;
t["deity"] = d.deityStr;
// ... all descriptive fields ...
// Capture-all: focus2, familiar, illusion, mount, stackable, loreEquipped, noDestroy,
// summoned, expendable, procRate, ornamentationIcon, ldoNCost, ldoNTheme, maxLuck, minLuck,
// weightReduction, contentSize, slotsUsedByItem, power, maxPower, pctPower, quality, delay,
// idFile, idFile2, refCount (use MQ item datatype key names for Lua).
```

**Step 4: Verify Lua compatibility**

No Lua changes needed for data consumption — views, columns, sort, tooltips, and augment helpers all read these fields by name from item tables. When the field exists on the table, the `__index` metatable (present only on TLO-path items) never fires.

The one thing to verify: items from the plugin path are plain tables without `__index`. If any code calls `rawget(item, "_descriptive_loaded")` or `rawget(item, "_statsPending")` to check lazy-load state, those checks return nil on plugin items (correct behavior — data is already loaded).

**Step 5: Handle the metatable gap on plugin items**

Plugin items don't have `buildItemFromMQ`'s `__index` metatable, so if a field is missing from the plugin (e.g., a new Lua field added later), the access returns nil rather than falling back to TLO. Two options:

- **Option A (simple):** Accept this. If a new Lua field is needed, add it to the plugin too. The plugin is the authoritative data source.
- **Option B (defensive):** In scan.lua, after receiving plugin results, set a lightweight metatable on each item that falls back to TLO for any missing key. This preserves backward compatibility but adds overhead.

Recommend Option A for clean architecture.

---

### Phase B: Implement items.getItem (P1) — **COMPLETE**

**Step 1:** In `capabilities/items.cpp`, replace the `getItem` stub:

```cpp
table.set_function("getItem", [rawL](int bag, int slot, const std::string& source) -> sol::optional<sol::table> {
  if (!pLocalPC) return sol::nullopt;
  sol::state_view sv(rawL);

  ItemPtr item = nullptr;
  if (source == "inv") {
    auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();
    int bagIdx = InvSlot_FirstBagSlot + bag - 1;
    ItemPtr bagItem = inv.GetItem(bagIdx);
    if (bagItem && bagItem->IsContainer()) {
      item = bagItem->GetHeldItems().GetItem(slot - 1);
    }
  } else if (source == "bank") {
    // Walk bank slot 'bag' (1-based), sub-slot 'slot' (1-based)
    item = pLocalPC->BankItems.GetItem(bag - 1);
    if (item && item->IsContainer() && slot > 0) {
      item = item->GetHeldItems().GetItem(slot - 1);
    }
  } else if (source == "equipped") {
    auto& inv = pLocalPC->GetCurrentPcProfile()->GetInventory();
    item = inv.GetItem(slot);  // 0-based equipment slot
  }
  // ... corpse source if needed ...

  if (!item) return sol::nullopt;
  ItemDefinition* def = item->GetItemDefinition();
  if (!def) return sol::nullopt;

  core::CoOptItemData d;
  // Populate all fields from def (same code as scanner)
  // ...
  return ItemDataToTable(sv, d);
});
```

**Step 2:** Extract the "populate CoOptItemData from ItemPtr+ItemDefinition" logic into a shared helper function so scanners and getItem use identical code:

```cpp
// In a new utility header or in ItemData.h:
void PopulateItemData(core::CoOptItemData& d, const ItemPtr& item,
                      const ItemDefinition* def, int bag, int slot,
                      const std::string& source);
```

---

### Phase C: Implement Cursor Capabilities (P2) — **COMPLETE**

**Step 1:** Fill in `cursor::updateFromPulse()`:

```cpp
void updateFromPulse() {
  if (!pLocalPC) {
    s_hasItem = false; s_itemId = 0; s_itemName.clear();
    return;
  }
  ItemPtr cursorItem = pLocalPC->GetItemByGlobalIndex(
      eItemContainerCursor, ItemIndex(0));
  if (cursorItem) {
    s_hasItem = true;
    s_itemId = cursorItem->GetID();
    ItemDefinition* def = cursorItem->GetItemDefinition();
    s_itemName = def ? def->Name : "";
  } else {
    s_hasItem = false; s_itemId = 0; s_itemName.clear();
  }
}
```

**Step 2:** Add `getItemType()` and `getItemLink()` to the Lua registration (used by reroll_service and config_filters_ui):

```cpp
table.set_function("getItemType", []() -> sol::optional<std::string> {
  if (!s_hasItem) return sol::nullopt;
  // Read type from cached def
  return sol::optional<std::string>(s_itemType);
});
```

**Step 3:** Lua migration (optional, can be gradual): In `reroll_service.lua`, `config_filters_ui.lua`, and `main_window.lua`, replace direct `mq.TLO.Cursor` calls with plugin cursor API calls (with TLO fallback).

---

### Implementation Order

```
Phase A (P0): Extend CoOptItemData + scan results — COMPLETE
  Step 1: ItemData.h fields
  Step 2: Scanner field population (shared helper)
  Step 3: ItemDataToTable extension
  Step 4: Verify Lua compatibility (no Lua changes needed)
  → Build + deploy + test tooltips, columns, augment compat

Phase B (P1): items.getItem — COMPLETE
  Step 1: Replace stub with real implementation
  Step 2: Extract shared populate helper
  → Build + deploy + test item refresh, augment ops

Phase C (P2): Cursor capabilities — COMPLETE
  Step 1: updateFromPulse implementation
  Step 2: Add getItemType/getItemLink
  Step 3: Optional Lua migration
  → Build + deploy + test reroll, cursor bar, config filters

Phase D (P3): Simple window.isWindowOpen — COMPLETE
  → isWindowOpen for 4 main windows; Lua can use coopui.window.isWindowOpen with TLO fallback
```

Phases A, B, and C are independent and can be done in parallel. Phase A has the highest impact and should be started first. All phases A–D are complete.

---

## What NOT to Do

1. **Don't move action flows (augment insert/remove, item destroy, bank shift-click) to C++.** These use MQ commands (`/itemnotify`, `/notify`) and state machines that are well-tested in Lua. The risk of behavior change in destructive operations outweighs any benefit.

2. **Don't move spell name/description lookups to C++.** Already cached effectively in Lua's L2 cache. Cache miss rate is very low.

3. **Don't implement full window capabilities (getText, click) in C++.** The CXWnd hierarchy navigation is brittle. MQ TLO/commands (`/notify`) are more resilient to UI XML changes.

4. **Don't add `__index` metatables to plugin items in C++.** Keep plugin items as plain tables. If a field is needed, add it to the plugin. This is cleaner than hybrid metatable approaches.

---

## Validation Checklist (for implementation agent)

After Phase A:
- [x] `/cooptui scan inv` returns items with all stat fields populated
- [x] Tooltip hover shows AC, HP, stats, class/race/deity without any TLO calls
- [x] Spell columns (Proc, Focus, Spell, Worn) show spell names, not "No"
- [x] Augment compatibility works (augType, augRestrictions, wornSlots populated)
- [x] Sorting by any stat column works correctly
- [x] Bank and loot scans also have full fields
- [x] Capture-all: item tables include all definition-time fields (focus2, familiar, illusion, mount, procRate, ldoNTheme, stackable, power, maxPower, etc.); optional: compare keys to MQ item datatype doc
- [x] No regression: unload plugin → TLO path still works identically
- [x] Scan time < 5ms for 140 items (should still be ~0ms)

After Phase B:
- [x] `coopui.items.getItem(1, 1, "inv")` returns full item table
- [x] `coopui.items.getItem(1, 1, "bank")` works when bank window closed (from snapshot)
- [x] Returns nil for empty slots
- [x] Field values match scan results for same item

After Phase C:
- [x] `coopui.cursor.hasItem()` returns true when item on cursor
- [x] `coopui.cursor.getItemId()` returns correct ID
- [x] `coopui.cursor.getItemName()` returns correct name
- [x] Cursor bar in main_window shows correct item (with or without plugin)

After Phase D:
- [x] `coopui.window.isWindowOpen("BigBankWnd")` (and MerchantWnd, LootWnd, InventoryWindow) returns correct visibility
- [x] No regression when plugin unloaded
