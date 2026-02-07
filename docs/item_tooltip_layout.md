# Item Tooltip Layout (On Hover)

When you hover over an item icon in Inventory, Bank, Sell, or Augments, the following tooltip is shown. Min width is 540px.

---

## Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Item Name                                                    (green text)   │
│  ID: 12345                                                                   │
│  Magic, Lore, No Drop, Augmentation        (type/flags; only if present)     │
│  Stack: 1 / 20                              (only if stackable)               │
├─────────────────────────────────────────────────────────────────────────────┤
│  Class: Warrior Berserker                                                    │
│  Race: All                                                                   │
│  Deity: Agnostic                        (only if set)                        │
│  Arms, Back, Chest, ...                 (worn slots)                          │
│  Augment slots: 2                       (only if > 0)                         │
│  Container: 10 slots (MEDIUM)          (only for containers)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Item info                                              (blue section header)│
│                                                                              │
│  Col 1 (~145px)      │  Col 2 (~100px)   │  Col 3 (~110px)                   │
│  Size: MEDIUM        │  AC: 25           │  HP: 50                           │
│  Weight: 2.5         │  Mana: 0          │  End: 0                            │
│  Req Level: 85       │  Rec Level: 85    │  Dmg: 20  (or Delay: 25)           │
│  Dmg Bon: 5          │  (empty)          │  (empty)                           │
│  Skill: 1H Slash     │  Haste: 25%        │  Charges: 10                       │
│  Range: 0            │  Skill Mod: 0     │  Bane: 0                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  All Stats                                               (blue section header)│
│                                                                              │
│  Col 1 (attrs)       │  Col 2 (resists)   │  Col 3 (combat/utility)           │
│  Strength: 15+5      │  Magic: 10         │  Attack: 25                        │
│  Stamina: 12         │  Fire: 8           │  HP Regen: 2                      │
│  Intelligence: 0     │  Cold: 0           │  Mana Regen: 0                    │
│  Wisdom: 0           │  Disease: 5        │  Spell Shield: 0                  │
│  Agility: 8          │  Poison: 0         │  ...                              │
│  Dexterity: 10        │  Corruption: 0      │  Accuracy: 15                     │
│  Charisma: 0          │  (empty)           │  Haste: 20                        │
│  (empty)              │  (empty)           │  Spell Dmg: 25                    │
│  ...                  │  ...               │  Heal Amt: 10                     │
│  (up to 20 rows; empty cells where that column has no value)                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  Item effects                                         (blue section header)  │
│                                                                              │
│  Effect: Focus Buff Name (Worn)                                             │
│  (optional wrapped description in gray)                                      │
│  Effect: Clickie Name (Clicky)                                              │
│  ...                                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│  Value                                                 (blue section header) │
│  1g 2s 3c                          (or raw number; only if value > 0)       │
│                                                                              │
│  Tribute                                                (blue section header)│
│  150                                (only if tribute > 0)                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Section summary

| Section          | Content |
|------------------|--------|
| **Header**       | Name (green), ID (gray), type line (Magic, Lore, etc.), Stack if stackable. |
| **Class/Race/Slot** | Class, Race, Deity, Worn slots, Augment slots, Container (each line only if present). |
| **Item info**    | 3 columns: Size/Weight/Req Level/Dmg Bon/Skill/Range \| AC/Mana/Rec Level/Haste/Skill Mod \| HP/End/Dmg or Delay/Charges/Bane. Only non-zero lines shown per cell. |
| **All Stats**    | 3 columns: Primary attributes (STR, STA, INT, WIS, AGI, DEX, CHA) \| Resistances (Magic, Fire, Cold, Disease, Poison, Corruption) \| Combat (Attack, HP Regen, Mana Regen, … through Purity). Row-by-row; empty cells where that column has no value (up to 20 rows). |
| **Item effects** | Clicky, Worn, Proc, Focus, Spell — each as "Effect: SpellName (Type)" or "Focus Effect: SpellName"; optional description below. |
| **Value / Tribute** | Formatted value and/or tribute amount. |

---

## Colors (approximate)

- **Item name:** `(0.45, 0.85, 0.45)` — green
- **ID:** `(0.55, 0.55, 0.6)` — gray
- **Section headers** (Item info, All Stats, Item effects, Value, Tribute): `(0.6, 0.8, 1.0)` — light blue
- **Effect descriptions:** `(0.65, 0.65, 0.7)` — gray

---

## Where it appears

The same tooltip is used when hovering an item in:

- **Inventory** (ItemUI)
- **Bank**
- **Sell** view
- **Augments** view

`opts.source` is `"inv"` or `"bank"` so Class/Race/Slot can be resolved from the correct TLO when not cached on the item.
