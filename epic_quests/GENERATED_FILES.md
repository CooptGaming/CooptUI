# Generated Files Summary

All Lua files and master items list have been automatically generated from the structured JSON data. No Python required!

## Generated Files

### Quest Lua Files
- ✅ `epic_quests/data/lua/bard_epic.lua` - Complete Bard epic quest data
- ✅ `epic_quests/data/lua/rogue_epic.lua` - Complete Rogue epic quest data
- ✅ `epic_quests/data/lua/epic_quests_index.lua` - Master index file

### Master Items List
- ✅ `epic_quests/data/master_items.lua` - Complete master items list with cross-references

## Usage

### Load a Quest (require path uses `epic_quests.data.lua` when MQ root is in package.path)
```lua
local bard_epic = require("epic_quests.data.lua.bard_epic")
print(bard_epic.quest_name)  -- "Singing Short Sword"
```

### Load All Quests
```lua
local all_epics = require("epic_quests.data.lua.epic_quests_index")
local rogue_epic = all_epics["rogue"]
```

### Use Master Items List (includes loc/nav for map and MQ2Nav)
```lua
local master_items = require("epic_quests.data.master_items")
local item = master_items["Red Dragon Scales"]
print(item.source_mob)
if item.locs then
  for _, loc in ipairs(item.locs) do
    print(loc.nav_loc)  -- "zone x y" for /waypoint or MQ2Nav
  end
end
```

## File Structure

```
epic_quests/
├── data/
│   ├── epic_quests_structured.json  # Source data (JSON)
│   ├── master_items.lua             # ✅ Generated - Master items list
│   └── lua/                          # ✅ Generated - Quest Lua files
│       ├── bard_epic.lua            # ✅ Generated
│       ├── rogue_epic.lua           # ✅ Generated
│       └── epic_quests_index.lua    # ✅ Generated
```

## Loc / Navigation (map and MQ2Nav)

Master items and quest steps include **locs** where available: `zone`, `x`, `y`, `z?`, `description`, and `nav_loc` (e.g. `"Western Karana -516 -2434"`) for waypoints or MQ2Nav. The **EpicQuestUI** (`/lua run epicquestui`) shows these and offers “Copy nav_loc” for pasting into nav tools.

To regenerate with full loc/nav from the JSON:

- **Master items:** `python epic_quests/scripts/generate_master_items.py` (from repo root or from `epic_quests/scripts`)
- **All 14 class Lua files:** `python epic_quests/scripts/generate_lua_quests.py`

## Next Steps

When you add more epic quests to `epic_quests_structured.json`:
1. Manually create the Lua file following the same format, or
2. Run `generate_lua_quests.py` to auto-generate all class files.

Run `generate_master_items.py` to refresh the master items list (including loc/nav from NPC/mob locations in steps).

## Notes

- All files are ready to use in MacroQuest2
- No Python installation required - files were generated directly
- Data structure matches MacroQuest2 Lua conventions
- All items are cross-referenced to their quests and steps
