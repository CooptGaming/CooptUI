# ScriptTracker - Perky EQ AA Script Tracker

Tracks Lost and Planar scripts in inventory. Shows count per type and total AA value for turning them in.

## Script Types

| Type | Tiers | AA Each |
|------|-------|---------|
| Lost Memories | Normal, Enhanced, Rare, Epic, Legendary | 1, 2, 3, 4, 5 |
| Planar Power | Normal, Enhanced, Rare, Epic, Legendary | 1, 2, 3, 4, 5 |

## Usage

```
/lua run scripttracker
/scripttracker          -- Toggle window
/scripttracker show     -- Show window
/scripttracker hide     -- Hide window
/scripttracker refresh  -- Rescan inventory
```

## Features

- Pop-out window (NoCollapse, AlwaysAutoResize)
- **PIN checkbox**: When pinned, window cannot be closed (X button and Escape are ignored)
- Planar and Lost scripts of the same rarity combined in one row (same AA value)
- Table: Rarity | Count | AA (Normal, Enhanced, Rare, Epic, Legendary)
- Total AA value for turning in all scripts
- Refresh button to rescan inventory

## Planned

- Turn-in button: turn in all or selected amount to quest NPC
