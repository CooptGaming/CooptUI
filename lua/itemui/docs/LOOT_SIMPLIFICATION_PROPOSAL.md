# Loot Filter Simplification Proposal

## Current State (Why It's Confusing)

Today there are **3 loot-related lists** in the Filters tab:

| List | Files | Effect |
|------|-------|--------|
| **Shared valuable** | `shared_config/valuable_*.ini` | Never sell + Always loot (cross-domain) |
| **Always loot** | `loot_config/loot_always_*.ini` | Always loot (loot-only) |
| **Skip** | `loot_config/loot_skip_*.ini` | Never loot |

**The confusion:** Both "Shared valuable" and "Always loot" result in "always loot" — they're merged at evaluation time. Users have to choose between two lists that do the same thing for looting, with the only difference being whether the item is *also* never sold.

---

## Proposed Simplifications

### Option A: Two Loot Lists + "Also never sell" Checkbox (Recommended)

**Change:** Collapse "Shared valuable" and "Always loot" into a single **"Always loot"** list. When adding an item, show a checkbox:

- ☐ **Also never sell (valuable)** — When checked, writes to `valuable_*.ini` (affects both sell and loot). When unchecked, writes to `loot_always_*.ini` (loot only).

**Result:**
- Filters dropdown: 5 lists instead of 6 (Keep, Always sell, Never sell by type, **Always loot**, Skip)
- One mental model for loot: "Always loot" with optional "also never sell"
- No backend/macro changes — same INI files, same merge logic

**UI change:** Add a checkbox next to the Add form when "Always loot" is selected: "Also never sell (valuable)". Default unchecked (loot-only).

---

### Option B: Merge Into One "Always loot" List (Simpler UI, Less Flexible)

**Change:** Remove "Shared valuable" entirely. All "always loot" items go to `loot_always_*.ini`. Items that should also never sell get added to **Keep** (sell) as well — user adds to both lists manually.

**Result:**
- 5 lists (same as Option A)
- Simpler: no checkbox
- Trade-off: Duplicate entries for valuable items (in both Keep and Always loot). Or we could add to valuable when user adds to Keep with "Also always loot" — but that inverts the flow.

**Verdict:** Option A is cleaner — one place to add loot rules, with optional "also never sell."

---

### Option C: Keep Three Lists, Improve Labels & Grouping

**Change:** No structural change. Instead:
1. **Group** the Filters tab: "Sell" section (Keep, Always sell, Never sell by type) | "Loot" section (Always loot, Skip)
2. **Rename** "Shared valuable" → "Valuable (never sell + always loot)" with a tooltip explaining it's shared
3. **Add** a short note under the loot section: "Both 'Valuable' and 'Always loot' result in always loot; Valuable also keeps when selling."

**Result:**
- Same 6 lists, but clearer grouping and labels
- Lowest implementation effort
- Less reduction in cognitive load than Option A

---

### Option D: Single "Loot rules" With Two Buckets

**Change:** Replace the unified Filters list with a **Loot** sub-section that has only 2 lists:
- **Always loot** (merged display of valuable + loot_always; add target chosen by checkbox as in Option A)
- **Skip**

Sell lists stay in their own section. Filters tab structure: ItemUI | Loot | **Filters** (Sell: Keep, Always sell, Protected) + **Loot Filters** (Always loot, Skip).

**Result:**
- Clear separation: sell rules vs loot rules
- Loot section has only 2 lists
- More UI restructuring than Option A

---

## Recommendation: Option A

**Why Option A:**
1. **Reduces lists** from 6 to 5 (removes "Shared valuable" as a separate choice)
2. **Single "Always loot"** — one place to add loot rules
3. **Checkbox** handles the "also never sell" case without a separate list
4. **No macro changes** — same INI layout, same merge behavior
5. **Moderate implementation** — add checkbox to add form when Always loot is selected; route to valuable_* vs loot_always_* based on checkbox

**Implementation sketch:**
- When `filterTargetId == "always"`: show checkbox "Also never sell (valuable)" next to Type dropdown
- New state: `filterAlsoNeverSell = false`
- On Add (or From cursor): if checkbox checked, write to valuable_* (shared) instead of loot_always_*
- Remove "shared" from FILTER_TARGETS (or hide it from the dropdown)
- Conflict pairs: update to remove shared↔skip (skip would conflict with "always" which can now write to valuable)

---

## Migration Note

Existing "Shared valuable" entries stay in `valuable_*.ini`. They continue to work. New adds go through "Always loot" with the checkbox. Users can still edit/remove existing valuable entries — we'd need to show them in the "Always loot" list when displaying (merged view) and allow remove. The remove would need to detect which file the entry came from (valuable vs loot_always) and remove from the correct one. That requires either:
- Tagging entries in the merged display with their source (valuable vs loot_always), or
- On remove, try removing from both and see which had it

Simpler: when displaying "Always loot" list, merge valuable + loot_always. When removing, check both and remove from whichever contains it. When adding, use checkbox to pick target.
