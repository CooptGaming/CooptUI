# Filters Redesign: Separate Sell & Loot Sections

## Design Goals

1. **Separate Sell and Loot** — Two distinct sections with their own filters, not one unified list
2. **Clear mental model** — Sell: always sell unless qualified to keep. Loot: never loot unless qualified
3. **Similar form for each** — Same add UX (list, type, value, From cursor, Add) in both sections
4. **Default protect list** — Sensible defaults for items to never sell
5. **Exact match by default** — UI/Cursor adds exact match; keyword requires explicit selection in Filters

---

## Proposed Layout

### Filters Tab Structure

```
┌─────────────────────────────────────────────────────────────┐
│  Filters                                                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ▼ SELL FILTERS                                             │
│  ─────────────────────────────────────────────────────────  │
│  "Always sell unless a qualification is met"                │
│                                                             │
│  [List ▼] [Type ▼] [Value input...] [From cursor] [Add]     │
│  • Keep (never sell)                                        │
│  • Always sell                                              │
│  • Never sell by type                                       │
│                                                             │
│  [Load default protect list]                                 │
│                                                             │
│  List: [Show: All ▼]                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ List              │ Type   │ Value        │ Remove  │   │
│  │ Keep (never sell)  │ [name] │ Rusty Dagger │   X    │   │
│  │ ...                │        │              │        │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ▼ LOOT FILTERS                                             │
│  ─────────────────────────────────────────────────────────  │
│  "Never loot unless a qualification is met"                 │
│                                                             │
│  [List ▼] [Type ▼] [Value input...] [From cursor] [Add]     │
│  • Always loot                                              │
│  • Skip (never loot)                                        │
│                                                             │
│  List: [Show: All ▼]                                        │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ List          │ Type   │ Value        │ Remove       │   │
│  │ Always loot    │ [name] │ Epic Sword   │   X         │   │
│  │ ...            │        │              │            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Default Protect List (Never Sell)

**When user clicks "Load default protect list"**, populate:

| Category | Entries | Target |
|----------|---------|--------|
| **Keywords** (keep contains) | Legendary, Mythical, Script, Epic, Fabled, Heirloom | sell_keep_contains.ini |
| **Item types** (protected) | Food, Gem, Armor, Weapon, Shield, Container, Augment, Quest | sell_protected_types.ini |

**Rationale:**
- **Legendary, Mythical, Epic, Fabled** — High-tier/rare items (often in name)
- **Script** — Quest scripts
- **Heirloom** — Often in name; flag-based protect already exists
- **Food, Gem** — Commonly valuable (buff food, tradeskill gems)
- **Armor, Weapon, Shield** — Equipment (user can remove if too broad)
- **Container** — Bags
- **Augment** — Augment items
- **Quest** — Quest items (type)

**Note:** We append to existing lists; we don't overwrite. Or we could offer "Replace with defaults" vs "Add defaults to existing". Safer: "Add defaults" only adds entries that aren't already present.

---

## Add Behavior

| Source | Type | Target |
|--------|------|--------|
| **From cursor** | Exact (full name) | Selected list |
| **Keep/Junk buttons** (sell view) | Exact | Keep or Always sell |
| **Filters form** | User selects: Full name (default), Keyword, Item type | Selected list |

**Default Type = Full name** — When opening Filters, Type dropdown defaults to "Full name". User must explicitly switch to "Keyword" or "Item type" to add those.

---

## Shared Valuable — What to Do?

**Current:** "Shared valuable" is one list that affects both sell (never sell) and loot (always loot). Stored in `shared_config/valuable_*.ini`.

**Options:**
1. **Remove from UI** — User adds to Keep (sell) AND Always loot (loot) separately for items that should do both. Duplicate entries, but clear.
2. **Keep as optional** — In Loot section, when adding to "Always loot", add checkbox "Also never sell (valuable)" that writes to valuable_*.ini. One add, two effects.
3. **Keep as separate list** — "Valuable (never sell + always loot)" in a small "Shared" subsection. Adds complexity.

**Recommendation:** Option 1 for simplicity — separate sections means separate lists. Users who want both add to both. The valuable_* files stay for backward compatibility (macros still read them); we just don't expose a UI to add to them. Existing valuable entries continue to work.

---

## Concerns & Decisions

### 1. Default list — when to apply?
- **Option A:** "Load default protect list" button — User explicitly clicks. Safe, no surprise overwrites.
- **Option B:** On first run, if INI is empty, seed defaults. Risk: "first run" is hard to detect if user has existing config.
- **Decision:** Option A. Button only. Never auto-overwrite.

### 2. Protected types — might be too broad
- "Armor" and "Weapon" as default protected types means ALL armor/weapons are never sold. That could be too aggressive for some users (e.g., they want to sell vendor trash armor).
- **Mitigation:** Document that users can remove types they don't want. Or make the default list more conservative: only Food, Gem, Augment, Quest. Let user add Armor/Weapon if desired.
- **Revised default types:** Food, Gem, Augment, Quest (narrower). User adds Armor, Weapon, etc. if they want.

### 3. Loot "qualifications" — unchanged
- Current loot.mac: Skip first, then Always loot, then value/flags. So "never loot unless qualified" is already the model. No logic change.
- We're just reorganizing the UI.

### 4. Conflict checking — scope
- Sell: Keep vs Always sell (unchanged)
- Loot: Always loot vs Skip (unchanged)
- With separate sections, conflicts are within each section. No cross-domain conflicts (Keep vs Skip don't conflict).

### 5. Filter "Show: All" — per section or global?
- **Option A:** One "Show: All" per section — Sell section shows only sell lists; Loot section shows only loot lists.
- **Option B:** Global filter goes away; each section always shows its own lists.
- **Decision:** Each section shows only its lists. No "Show: All" needed — Sell section shows Keep, Always sell, Protected; Loot section shows Always loot, Skip. Could still have "Show: All" within section to collapse to one list view.

---

## Implementation Summary

1. **Split Filters tab** into two collapsible sections: Sell Filters, Loot Filters
2. **Sell section:** Lists = Keep, Always sell, Never sell by type. Same form. Add "Load default protect list" button.
3. **Loot section:** Lists = Always loot, Skip. Same form. Remove Shared valuable from UI.
4. **Default Type = Full name** (already 0). Ensure From cursor and Keep/Junk add exact.
5. **Default protect list:** Button writes keywords + types to INI (append, no duplicates).
6. **Conflict modal:** Only within section (Keep↔Always sell, Always loot↔Skip).
7. **State:** Separate filterTargetId per section? Or one with section-scoped targets. Simpler: sellFilterTargetId, lootFilterTargetId. Separate form state per section.

---

## Open Questions

1. **Default types** — Conservative (Food, Gem, Augment, Quest) or broader (add Armor, Weapon, Shield, Container)?
2. **Valuable** — Remove from UI entirely, or keep "Also never sell" checkbox when adding to Always loot?
3. **Collapsible** — Should Sell and Loot sections be collapsible (CollapsingHeader) or always visible?
