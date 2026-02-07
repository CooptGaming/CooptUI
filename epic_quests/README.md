# EverQuest Epic Quest Data Repository

This repository contains comprehensive data for all EverQuest class epic quests (1.0), structured for use with MacroQuest2 and other EverQuest automation tools.

## Overview

This project scrapes and structures epic quest information from:
- [Project 1999 Wiki - Class Epic Quest List](https://wiki.project1999.com/Class_Epic_Quest_List)
- [Almar's Guides - Epic Quests](https://www.almarsguides.com/eq/epics/)

## Data Structure

### Epic Quest Data
Each epic quest includes:
- **Basic Information**: Class, quest name, reward item, start zone/NPC
- **Quest Steps**: Detailed step-by-step instructions with:
  - Step type (talk, kill, loot, give, pickpocket, travel, craft)
  - NPCs with locations and coordinates
  - Mobs with levels, locations, and spawn information
  - Items required/received
  - Dialogue triggers
  - Special notes and requirements
- **Zones**: All zones visited during the quest
- **NPCs**: Complete NPC list with spawn times and faction notes
- **Mobs**: All mobs that must be killed with detailed information

### Master Items List
A comprehensive list of all items used across all epic quests, including:
- Item name
- Source type (drop, quest_reward, crafted, purchased, ground_spawn, pickpocket)
- Source mob/NPC/zone
- Drop rates (where applicable)
- Which quests use the item
- Which classes need the item
- Detailed notes and context

## File Structure

```
epic_quests/
├── data/
│   ├── epic_quests_structured.json    # Complete structured quest data (JSON)
│   ├── master_items.json              # Master items list (JSON)
│   ├── master_items.lua               # Master items list (Lua)
│   └── lua/                            # Individual quest Lua files
│       ├── bard_epic.lua
│       ├── cleric_epic.lua
│       ├── druid_epic.lua
│       ├── ...
│       └── epic_quests_index.lua      # Master index file
├── scripts/
│   ├── scrape_epics.py                # Web scraper (initial version)
│   ├── parse_epic_data.py             # Data parser
│   ├── generate_master_items.py       # Master items generator
│   └── generate_lua_quests.py          # Lua file generator
└── docs/
    └── README.md                       # This file
```

## Usage

### Loading Quest Data in Lua (MacroQuest2)

```lua
-- Load a specific epic quest
local bard_epic = require("epic_quests.data.bard_epic")

-- Access quest information
print(bard_epic.quest_name)  -- "Singing Short Sword"
print(bard_epic.start_zone)  -- "Dreadlands"

-- Iterate through steps
for _, step in ipairs(bard_epic.steps) do
    print(string.format("Step %d: %s", step.step_number, step.description))
    if step.npc then
        print(string.format("  NPC: %s at %s (%d, %d)", 
            step.npc.name, 
            step.npc.location.zone,
            step.npc.location.x or 0,
            step.npc.location.y or 0))
    end
    if step.mob then
        print(string.format("  Mob: %s (Level %d) in %s", 
            step.mob.name,
            step.mob.level or 0,
            step.mob.location.zone))
    end
end

-- Load master items list
local master_items = require("epic_quests.data.master_items")

-- Find items used by a specific class
for item_name, item_data in pairs(master_items) do
    for _, class_name in ipairs(item_data.used_by_classes) do
        if class_name == "bard" then
            print(string.format("%s: %s", item_name, item_data.source_type))
        end
    end
end

-- Load all quests via index
local all_epics = require("epic_quests.data.epic_quests_index")
local rogue_epic = all_epics["rogue"]
```

### Using Master Items List

The master items list allows you to:
1. **Find all items needed for a specific class epic**
2. **Track item sources** (which mob drops it, where to get it)
3. **Cross-reference items** used by multiple epics
4. **Build item checklists** for epic quest completion

Example:
```lua
local master_items = require("epic_quests.data.master_items")

-- Find where an item comes from
local item = master_items["Red Dragon Scales"]
if item then
    print(string.format("%s drops from %s in %s", 
        item.name, 
        item.source_mob or "Unknown",
        item.source_zone or "Unknown"))
    
    -- See which quests use it
    for _, quest_ref in ipairs(item.quests) do
        print(string.format("  Used by %s epic (step %s)", 
            quest_ref.class, 
            quest_ref.step))
    end
end
```

## Data Format

### Quest Step Structure
```lua
{
    step_number = 1,
    section = "Maestro's Symphony Page 24 Top",
    step_type = "talk",  -- talk, kill, loot, give, pickpocket, travel, craft
    description = "Talk to Konia Swiftfoot in Western Karana",
    npc = {
        name = "Konia Swiftfoot",
        location = {
            zone = "Western Karana",
            x = -516,
            y = -2434,
            description = "Inside guard tower #4"
        }
    },
    dialogue = {
        "Say 'I would like to participate'",
        "Say 'I am ready'"
    },
    receive_item = "Torch of Misty"
}
```

### Item Structure
```lua
{
    name = "Red Dragon Scales",
    source_type = "drop",  -- drop, quest_reward, crafted, purchased, ground_spawn, pickpocket
    source_mob = "Lord Nagafen",
    source_zone = "Nagafen's Lair",
    source_level = 55,
    drop_rate = "common",  -- common, uncommon, rare, very_rare
    quests = {
        {
            class = "bard",
            quest = "Singing Short Sword",
            step = 27,
            section = "Mystical Lute Body",
            context = "looted"
        }
    },
    used_by_classes = {"bard"},
    notes = {}
}
```

## Generating Data Files

### From JSON to Lua
```bash
cd epic_quests/scripts
python generate_lua_quests.py
python generate_master_items.py
```

### Updating Quest Data
1. Edit `data/epic_quests_structured.json` with new quest information
2. Run the generation scripts to update Lua files
3. Master items list is automatically regenerated

## Future Enhancements

### Planned Features
1. **Quest Progress Tracking**: Track which steps have been completed
2. **Item Inventory Checking**: Verify if player has required items
3. **Waypoint Generation**: Create navigation waypoints for quest steps
4. **UI Integration**: Create a visual quest guide interface
5. **Quest Automation**: Generate macros for specific quest steps
6. **Multi-Epic Support**: Add 1.5 and 2.0 epic quests

### Suggestions for Improvement
- **Coordinate Validation**: Verify coordinates are accurate
- **Spawn Timer Tracking**: Track spawn times for rare mobs
- **Faction Requirements**: Detailed faction information
- **Group Requirements**: Note which steps require groups/raids
- **Alternative Paths**: Document alternative quest paths
- **Quest Prerequisites**: Track required pre-quests or items

## Contributing

When adding or updating quest data:
1. Ensure all coordinates are accurate
2. Include all dialogue triggers
3. Note any faction requirements
4. Document spawn times and placeholders
5. Include drop rates where known
6. Add notes for special mechanics

## Data Sources

- **Project 1999 Wiki**: Primary source for detailed walkthroughs, dialogue, and coordinates
- **Almar's Guides**: Secondary source for checklist format and additional details

## License

This data is compiled from publicly available sources and is intended for use with EverQuest and MacroQuest2. Please respect the terms of service of both games.

## Notes

- Coordinates are based on Project 1999 server locations
- Spawn times are in-game time (72 minutes = 1 real hour)
- Some mobs have placeholders - check notes for details
- Faction requirements vary by race/deity - check notes
- Some steps are optional - marked in quest data

## Support

For issues or questions:
1. Check the data files for accuracy
2. Verify coordinates in-game
3. Report discrepancies with source material
4. Suggest improvements to data structure
