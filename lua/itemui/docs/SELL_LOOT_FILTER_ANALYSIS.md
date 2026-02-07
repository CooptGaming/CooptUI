# SellUI & LootUI Filter Design — Expert Analysis

## Executive summary

The current setup is **conceptually sound** and matches how `sell.mac` and `loot.mac` work, but it’s harder than it needs to be for non-technical users. The main issues are **split UIs**, **inconsistent naming**, **missing sell lists in ItemUI Config**, and **no in-context “add from inventory/cursor.”** Below is a concise view of how things work, what hurts usability, and what to improve first.

---

## 1. How the macros actually use the data

### Sell side (sell.mac)

**Logic:** SELL everything UNLESS a KEEP rule matches. Some rules FORCE sell (override keep).

| Source | Files | Effect |
|--------|--------|--------|
| **Shared valuable** | `shared_config/valuable_exact.ini`, `valuable_contains.ini`, `valuable_types.ini` | Merged into “keep” → never sold |
| **Keep lists** | `sell_config/sell_keep_exact.ini`, `sell_keep_contains.ini`, `sell_keep_types.ini` | Never sold (merged with shared above) |
| **Always sell / Junk** | `sell_config/sell_always_sell_exact.ini`, `sell_always_sell_contains.ini` | Always sold; can override keep *keyword* matches |
| **Protected types** | `sell_config/sell_protected_types.ini` | Item types that are never sold |
| **Flags** | `sell_config/sell_flags.ini` | NoDrop, NoTrade, Lore, Quest, etc. → never sold |
| **Values** | `sell_config/sell_value.ini` | minSell, minStack, maxKeep, tribute |

Evaluation order in practice: flags → keep exact → always-sell exact → keep contains → always-sell contains → keep types → protected types → value rules.

### Loot side (loot.mac)

**Logic:** SKIP first, then “always loot” (shared + macro-specific). Rest depends on flags/values.

| Source | Files | Effect |
|--------|--------|--------|
| **Shared valuable** | Same `shared_config/valuable_*.ini` | Merged into “always loot” → always looted |
| **Always loot** | `loot_config/loot_always_exact/contains/types.ini` | Always looted (merged with shared) |
| **Skip** | `loot_config/loot_skip_exact/contains/types.ini` | Never looted (checked first) |
| **Flags** | `loot_config/loot_flags.ini` | e.g. loot clickies, quest, collectible |
| **Values** | `loot_config/loot_value.ini` | minLoot, minStack, tributeOverride |
| **Sorting** | `loot_config/loot_sorting.ini` | enableSorting, weightSort, minWeight |

So **one set of files** (`valuable_*.ini`) drives both “never sell” and “always loot.” That’s consistent; the UIs just need to say it clearly.

---

## 2. What already works well

- **One shared list for “valuable”** used by both sell and loot keeps behavior in sync and avoids duplicate lists.
- **Exact / Contains / Types** gives flexibility (full name, keyword, or type) without overloading one box.
- **INI under Macros/** fits MQ2 norms and stays editable by power users.
- **ItemUI sell view** Keep/Junk buttons give in-context, per-item control for exact names and feel right.
- **ItemUI Config** having Flags + Values (and Loot lists) in one place is a step toward “one place to configure.”

---

## 3. Pain points for non-technical users

### 3.1 Too many UIs and tabs

- **SellUI:** Inventory + Shared Valuable + Keep + Always Sell + Protected Types + Flags + Values (7 tabs).
- **LootUI:** Shared Valuable + Always Loot + Skip + Flags + Values + Sorting (6 tabs).
- **ItemUI Config:** ItemUI (window + sell flags + sell values) and Loot (Flags, Values, Sorting, Lists).

Someone who cares about “what gets sold” and “what gets looted” has to mentally map:

- SellUI “Shared Valuable” / “Keep” / “Always Sell” / “Protected Types”
- LootUI “Shared Valuable” / “Always Loot” / “Skip”
- ItemUI Config “Loot filters → Lists → Shared valuable / Always loot / Skip”

and remember that “Shared valuable” is the same data for both. That’s a lot of mental overhead.

### 3.2 Naming is jargon-heavy

- **“Exact” vs “Contains”** — clearer as “Full item name” vs “Name contains (keyword).”
- **“Shared valuable”** — fine for experts; for others, “Keep & always loot (shared)” or “Valuable (never sell, always loot)” is clearer.
- **“Always sell” / “Junk”** — SellUI says “Always Sell”; ItemUI says “Junk.” One term (“Always sell” or “Junk”) used everywhere would help.
- **“Protected types”** — “Never sell these item types” is more explicit.

### 3.3 ItemUI Config is incomplete for sell

ItemUI Config today has:

- **ItemUI tab:** window behavior, sell protection flags, sell value thresholds. No lists.
- **Loot tab:** Flags, Values, Sorting, and Lists (Shared valuable, Always loot, Skip).

Missing from Config (so users must use SellUI or INI):

- Sell **Keep** lists (exact/contains/types) — only exact is editable via ItemUI sell view Keep button.
- Sell **Always sell / Junk** lists (exact/contains) — only exact via Junk button.
- **Protected types** (sell).

So “one config UI” doesn’t yet cover sell list management.

### 3.4 No “add from inventory” or “add from cursor” in list UIs

In SellUI/LootUI/ItemUI Config you **type** names/keywords/types. The only in-context add is ItemUI’s Keep/Junk on a row. For bulk or “this thing in my bag”:

- No “Add from cursor” in Config.
- No “Add selected from inventory” or “Add all visible” in list tabs.

That’s a missed opportunity for EQ players who think in terms of “this item” and “this bag.”

### 3.5 “Exact / Contains / Types” repeated everywhere

Every list section repeats the same three blocks (Exact, Contains, Types). That’s flexible but long and repetitive. A single “Rules for this list” area with a small selector (Full name / Keyword / Type) plus one input and one list could reduce clutter and feel simpler.

---

## 4. Recommendations (in order of impact)

### 4.1 Unify list management in ItemUI Config (high impact)

**Goal:** One place for all filter lists.

- **Sell tab (new or extended):**
  - **“Never sell (Keep)”** — one collapsible that holds:
    - Full item names (today’s keep exact)
    - Keywords (keep contains)
    - Item types (keep types)
  - **“Always sell (Junk)”** — full names + keywords (no “types” for junk in current macros).
  - **“Never sell by type”** — protected types (one list).
- Keep **“Valuable (shared)”** in one clear section used for both:
  - “Never sell (sell.mac)” and “Always loot (loot.mac),” with a one-line explanation.
- **Loot tab** stays: Flags, Values, Sorting, plus “Always loot,” “Skip,” and that shared “Valuable” section (or a link to it).

Use the same INI files and keys as today; only the UI and grouping change. SellUI/LootUI can stay as “advanced” or be deprecated later.

### 4.2 Use task-oriented, plain-language labels (high impact)

- **Exact** → “Full item name” (and in tooltips: “Must match the whole name.”)
- **Contains** → “Name contains” or “Keyword” (tooltip: “Matches if the item name contains this text.”)
- **Types** → “Item type” (tooltip: “e.g. Armor, Weapon, Quest.”)
- **Shared valuable** → “Valuable (never sell, always loot)” with a short note that it’s shared by sell and loot.
- **Keep** → “Never sell” or “Keep.”
- **Always sell / Junk** → pick one term (e.g. “Always sell”) and use it in Config, tooltips, and status text.
- **Protected types** → “Never sell these types” or “Protected types (never sell).”

### 4.3 Add “Add from cursor” in Config (medium impact)

In every list block (exact / contains / types) that accepts items:

- Add a button: **“Add from cursor”** (or “Add item on cursor”).
- On click: if `Cursor.ID()` exists, read `Cursor.Name()` (and type if needed), trim/sanitize, add to the right list, write INI, clear input if desired.
- Disable or gray out when cursor is empty; tooltip: “Pick up an item, then click to add it to this list.”

Same idea can later apply to “Add from selection” if you add inventory checkboxes.

### 4.4 Simplify the “three blocks” pattern (medium impact)

Instead of three big sections (Exact names, Contains, Types) per list:

- Use **one** “Add to this list” row: dropdown or tabs “Full name / Keyword / Type” plus one input and one “Add” button.
- Below that, **one** list control showing all entries for that list, with a small badge or column indicating “name,” “keyword,” or “type” so users can tell them apart.
- Back end can still use three INI keys (exact/contains/types) and merge for display; the UI feels like “one list, several ways to add.”

### 4.5 One-page “Quick rules” (lower priority)

A single scrollable “Quick rules” view for the user who wants to tweak without drilling tabs:

- Short bullet list: “Never sell: [link to Keep], [link to Protected types], [link to Flags].”
- “Always sell: [link to Junk].”
- “Valuable (shared): [link to Shared valuable].”
- “Loot: Always [link], Skip [link], Flags/Values [link].”

Each “[link]” jumps to the right tab/section in Config. No new data; just navigation and wording that match how people think (“never sell” / “always sell” / “always loot” / “skip”).

### 4.6 Keep macro behavior, improve docs (low effort)

Do **not** change evaluation order or INI layout in the macros unless necessary. Instead:

- Add a one-page “How sell rules work” (order of checks, what overrides what).
- In ItemUI Config, add one-line tooltips or short help under each section (e.g. “Checked after ‘never sell’ names; can override keyword-based keep.” for Always sell).

---

## 5. Is a full redesign worth it?

**No.** The current model (shared valuable + keep + always sell + protected types for sell; shared + always loot + skip for loot; flags/values/sorting) fits the macros and is flexible. The main wins are:

1. **Unifying list management in ItemUI Config** (including sell Keep/Junk/Protected).
2. **Clearer labels and tooltips** (exact/contains/types, “never sell,” “always sell,” “valuable”).
3. **“Add from cursor”** in Config for list management.
4. **Optional** single-list UX (one “Add” row + one list with type badges) to reduce repetition.

Doing (1)–(3) already gives a much better, non-technical-friendly experience without changing macros or INI layout.

---

## 6. Suggested order of work

1. **Extend ItemUI Config “ItemUI” tab** with sell list management: Never sell (Keep: full names, keywords, types), Always sell (Junk: full names, keywords), Never sell by type (Protected types). Reuse existing INI paths.
2. **Rename and add tooltips** in ItemUI Config (and optionally SellUI/LootUI): Exact/Contains/Types and Shared/Keep/Junk/Protected as above.
3. **Implement “Add from cursor”** for every list in ItemUI Config that stores item names or types.
4. **Optionally** refactor list UI to “one add row + one list per list kind” with name/keyword/type badges.
5. **Add a “Quick rules” or “How it works”** section that links to each part of Config.

This keeps the current architecture and macro behavior, and makes the system understandable and efficient for non-technical users.
