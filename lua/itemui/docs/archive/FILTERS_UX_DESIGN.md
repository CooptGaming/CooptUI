# Filters Section UX Design

**Date:** January 29, 2026  
**Purpose:** UX design for consolidated Filters section in ItemUI Config, per lua-ux-dev principles.

---

## 1. Goals

1. **Consolidate** sell and loot filter lists into one "Filters" section.
2. **Unified add form** — one place to add items to any list: dropdown (target list) + input type + value + Add.
3. **Edit via remove** — removing an item populates the form so user can edit and re-add.
4. **Clarity** — plain-language labels; minimal cognitive load.
5. **Efficiency** — common actions (add, remove, edit) require few clicks.

---

## 2. UX Expert Principles (lua-ux-dev)

| Principle | Application |
|-----------|-------------|
| **Consistency** | Match spacing, padding, layout of existing itemui Config. Use same badge colors, button styles. |
| **Feedback** | Status message on add/remove; visual highlight when form is populated from remove. |
| **Affordance** | Add button looks clickable; X on list items looks removable; "From cursor" disabled when no item. |
| **Clarity** | "Add to list" dropdown shows full list names; input placeholder hints at format. |
| **Efficiency** | One form for all lists; From cursor for quick add; remove→populate for quick edit. |
| **Forgiveness** | Edit workflow (remove→populate→modify→add) supports corrections without losing context. |

---

## 3. Proposed Structure

### Config Tabs (revised)

| Tab | Contents |
|-----|----------|
| **ItemUI** | Window behavior, Layout Setup, Sell protection flags, Sell value thresholds |
| **Loot** | Loot flags, Loot values, Loot sorting |
| **Filters** | Unified add form + all filter lists (sell + loot) |

### Filters Section Layout

```
┌─ Filters ─────────────────────────────────────────────────────────────┐
│ Add to list: [Keep (never sell)        ▼]  [Full name ▼]  [___________] │
│             [Add] [From cursor]                                           │
│                                                                          │
│ Lists (click X to remove; form fills for edit):                          │
│ ┌──────────────────────────────────────────────────────────────────────┐│
│ │ [name] Valuable Sword                              X                  ││
│ │ [keyword] Epic                                       X                ││
│ │ [type] Weapon                                        X                ││
│ │ ...                                                                   ││
│ └──────────────────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────────┘
```

### Target List Options (dropdown)

| Option | Effect | Supports |
|--------|--------|----------|
| Keep (never sell) | sell_keep_* + shared | exact, keyword, type |
| Always sell | sell_always_sell_* | exact, keyword |
| Never sell by type | sell_protected_types | type only |
| Shared valuable | valuable_* (sell + loot) | exact, keyword, type |
| Always loot | loot_always_* | exact, keyword, type |
| Skip (never loot) | loot_skip_* | exact, keyword, type |

### Input Type (dropdown)

| Option | Hint | From cursor |
|--------|------|-------------|
| Full name | Must match whole item name | Uses Cursor.Name |
| Keyword | Name contains this text | Uses Cursor.Name |
| Item type | e.g. Armor, Weapon | Uses Cursor.Type |

### Remove → Populate Edit Workflow

1. User clicks X on list entry (e.g. `[keyword] Epic`).
2. Entry is removed from list and INI.
3. Form is populated: target list = "Keep", input type = "Keyword", value = "Epic".
4. User can modify value (e.g. change to "Epic Sword") and click Add to re-add.
5. Status: "Removed; form filled for edit."

---

## 4. Implementation Notes

- Reuse `renderUnifiedListSection` logic but refactor into a single `renderFiltersSection` that:
  - Renders one add form at top (list dropdown + type dropdown + input + Add + From cursor).
  - Renders one scrollable list with all entries from all lists, each with badge + X.
  - On X click: remove from list, write INI, set `filterEditTarget` state (listKey, typeKey, value) to populate form.
- List display: group by list (collapsible headers) or flat with list badge. Flat with list badge is simpler and matches "one form" philosophy.
- Badge colors: [name]=blue, [keyword]=cyan, [type]=yellow; list badge (Keep/Always sell/etc.) in muted color.

---

## 5. Deferred to UX Expert

- **Grouping:** Flat list vs grouped by target list? Flat is simpler; grouped may reduce visual clutter for users with many entries.
- **Drop zone:** ImGui drag-drop for "drop item here" — if MQ2 Lua ImGui supports it; otherwise "From cursor" button suffices.
- **Placeholder text:** Dynamic placeholder based on input type ("e.g. Rusty Dagger" vs "e.g. Epic" vs "e.g. Armor").
