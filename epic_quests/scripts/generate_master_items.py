#!/usr/bin/env python3
"""
Generate master items list from epic quest data
Links items to quests and provides detailed information.
Adds loc/nav info (zone, x, y, z, nav_loc) for map and MQ2Nav use.
"""

import json
from collections import defaultdict
from typing import Dict, List, Set, Tuple, Any

def _loc_from_entity(entity: Dict) -> Dict[str, Any]:
    """Build nav/loc dict from npc or mob location. Returns {} if no coords."""
    loc = entity.get("location") or {}
    zone = loc.get("zone")
    x, y = loc.get("x"), loc.get("y")
    if zone is None or x is None or y is None:
        return {}
    out = {"zone": zone, "x": int(x), "y": int(y)}
    if loc.get("z") is not None:
        out["z"] = int(loc["z"])
    if loc.get("description"):
        out["description"] = loc["description"]
    out["nav_loc"] = f"{zone} {x} {y}"  # MQ2Nav /waypoint style
    return out

def _add_loc_to_item(item_entry: Dict, loc_dict: Dict, context: str, class_name: str, quest_name: str, step_num) -> None:
    """Append a unique loc to item's locs list."""
    if not loc_dict:
        return
    key = (loc_dict.get("zone"), loc_dict.get("x"), loc_dict.get("y"))
    if "locs" not in item_entry:
        item_entry["locs"] = []
    seen = {(l["zone"], l["x"], l["y"]) for l in item_entry["locs"]}
    if key in seen:
        return
    loc_dict = dict(loc_dict)
    loc_dict["context"] = context
    loc_dict["class"] = class_name
    loc_dict["quest"] = quest_name
    loc_dict["step"] = step_num
    item_entry["locs"].append(loc_dict)

def extract_items_from_quest(quest_data: Dict) -> Dict[str, Dict]:
    """Extract all items from a quest and their context"""
    items = {}
    class_name = quest_data.get('class', 'unknown')
    quest_name = quest_data.get('quest_name', 'Unknown')
    
    # Extract items from steps
    for step in quest_data.get('steps', []):
        # Items received
        if 'receive_item' in step:
            item_name = step['receive_item']
            if item_name not in items:
                items[item_name] = {
                    'name': item_name,
                    'quests': [],
                    'source_type': 'quest_reward',
                    'source_step': step.get('step_number'),
                    'source_section': step.get('section', ''),
                    'notes': []
                }
            items[item_name]['quests'].append({
                'class': class_name,
                'quest': quest_name,
                'step': step.get('step_number'),
                'section': step.get('section', ''),
                'context': 'received'
            })
            npc = step.get('npc') or {}
            loc = _loc_from_entity(npc)
            _add_loc_to_item(items[item_name], loc, 'received', class_name, quest_name, step.get('step_number'))
        
        # Items given
        if 'give_item' in step:
            item_name = step['give_item']
            if item_name not in items:
                items[item_name] = {
                    'name': item_name,
                    'quests': [],
                    'source_type': 'unknown',
                    'notes': []
                }
            items[item_name]['quests'].append({
                'class': class_name,
                'quest': quest_name,
                'step': step.get('step_number'),
                'section': step.get('section', ''),
                'context': 'given'
            })
            npc = step.get('npc') or {}
            loc = _loc_from_entity(npc)
            _add_loc_to_item(items[item_name], loc, 'given', class_name, quest_name, step.get('step_number'))
        
        # Multiple items given
        if 'give_items' in step:
            for item_name in step['give_items']:
                if item_name not in items:
                    items[item_name] = {
                        'name': item_name,
                        'quests': [],
                        'source_type': 'unknown',
                        'notes': []
                    }
                items[item_name]['quests'].append({
                    'class': class_name,
                    'quest': quest_name,
                    'step': step.get('step_number'),
                    'section': step.get('section', ''),
                    'context': 'given'
                })
            npc = step.get('npc') or {}
            loc = _loc_from_entity(npc)
            _add_loc_to_item(items[item_name], loc, 'given', class_name, quest_name, step.get('step_number'))
        
        # Items looted
        if 'loot_item' in step:
            item_name = step['loot_item']
            mob = step.get('mob', {})
            if item_name not in items:
                items[item_name] = {
                    'name': item_name,
                    'quests': [],
                    'source_type': 'drop',
                    'source_mob': mob.get('name', 'Unknown'),
                    'source_zone': mob.get('location', {}).get('zone', 'Unknown'),
                    'source_level': mob.get('level'),
                    'drop_rate': 'unknown',
                    'notes': []
                }
            items[item_name]['quests'].append({
                'class': class_name,
                'quest': quest_name,
                'step': step.get('step_number'),
                'section': step.get('section', ''),
                'context': 'looted',
                'mob': mob.get('name'),
                'zone': mob.get('location', {}).get('zone')
            })
            loc = _loc_from_entity(mob)
            _add_loc_to_item(items[item_name], loc, 'looted', class_name, quest_name, step.get('step_number'))
            
            # Add mob-specific notes
            if mob.get('notes'):
                items[item_name]['notes'].append(f"Mob notes: {mob['notes']}")
        
        # Items crafted
        if step.get('step_type') == 'craft':
            item_name = step.get('item', '')
            if item_name and item_name not in items:
                items[item_name] = {
                    'name': item_name,
                    'quests': [],
                    'source_type': 'crafted',
                    'notes': []
                }
            if item_name:
                items[item_name]['quests'].append({
                    'class': class_name,
                    'quest': quest_name,
                    'step': step.get('step_number'),
                    'section': step.get('section', ''),
                    'context': 'crafted'
                })
                if step.get('notes'):
                    items[item_name]['notes'].append(step['notes'])
    
    # Reward item
    reward_item = quest_data.get('reward_item', '')
    if reward_item:
        if reward_item not in items:
            items[reward_item] = {
                'name': reward_item,
                'quests': [],
                'source_type': 'epic_reward',
                'notes': []
            }
        items[reward_item]['quests'].append({
            'class': class_name,
            'quest': quest_name,
            'step': 'final',
            'section': 'Reward',
            'context': 'epic_reward'
        })
    
    return items

def generate_master_items(epic_data: Dict) -> Dict:
    """Generate master items list from all epic quests"""
    master_items = {}
    
    for class_name, quest_data in epic_data.get('epic_quests', {}).items():
        quest_items = extract_items_from_quest(quest_data)
        
        # Merge items into master list
        for item_name, item_info in quest_items.items():
            if item_name not in master_items:
                master_items[item_name] = {
                    'name': item_name,
                    'quests': [],
                    'locs': [],
                    'source_type': item_info.get('source_type', 'unknown'),
                    'source_mob': item_info.get('source_mob'),
                    'source_npc': item_info.get('source_npc'),
                    'source_zone': item_info.get('source_zone'),
                    'source_location': item_info.get('source_location'),
                    'source_level': item_info.get('source_level'),
                    'drop_rate': item_info.get('drop_rate', 'unknown'),
                    'notes': item_info.get('notes', []).copy(),
                    'used_by_classes': set()
                }
            
            # Merge quest references
            master_items[item_name]['quests'].extend(item_info['quests'])
            # Merge locs (nav/map), dedupe by (zone,x,y)
            for loc in item_info.get('locs', []):
                key = (loc.get('zone'), loc.get('x'), loc.get('y'))
                if key[0] is None:
                    continue
                seen = {(l.get('zone'), l.get('x'), l.get('y')) for l in master_items[item_name]['locs']}
                if key not in seen:
                    master_items[item_name]['locs'].append(loc)
            
            # Track which classes use this item
            for quest_ref in item_info['quests']:
                master_items[item_name]['used_by_classes'].add(quest_ref['class'])
            
            # Merge source information (prefer more specific)
            if not master_items[item_name]['source_mob'] and item_info.get('source_mob'):
                master_items[item_name]['source_mob'] = item_info['source_mob']
            if not master_items[item_name]['source_zone'] and item_info.get('source_zone'):
                master_items[item_name]['source_zone'] = item_info['source_zone']
            if not master_items[item_name]['source_level'] and item_info.get('source_level'):
                master_items[item_name]['source_level'] = item_info['source_level']
    
    # Convert sets to lists for JSON serialization
    for item_name in master_items:
        master_items[item_name]['used_by_classes'] = sorted(list(master_items[item_name]['used_by_classes']))
    
    return master_items

def _escape_lua(s: str) -> str:
    if s is None:
        return ""
    return str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

def generate_lua_items_table(master_items: Dict) -> str:
    """Generate Lua table for master items (includes loc/nav for map and MQ2Nav)"""
    lines = [
        "-- Master Items List for All Epic Quests",
        "-- Auto-generated from epic quest data; includes loc/nav for map and MQ2Nav",
        "",
        "local master_items = {"
    ]
    
    for item_name, item_data in sorted(master_items.items()):
        lines.append(f"    [\"{_escape_lua(item_name)}\"] = {{")
        lines.append(f"        name = \"{_escape_lua(item_name)}\",")
        lines.append(f"        source_type = \"{item_data['source_type']}\",")
        
        if item_data.get('source_mob'):
            lines.append(f"        source_mob = \"{_escape_lua(item_data['source_mob'])}\",")
        if item_data.get('source_zone'):
            lines.append(f"        source_zone = \"{_escape_lua(item_data['source_zone'])}\",")
        if item_data.get('source_level'):
            lines.append(f"        source_level = {item_data['source_level']},")
        if item_data.get('drop_rate') and item_data['drop_rate'] != 'unknown':
            lines.append(f"        drop_rate = \"{item_data['drop_rate']}\",")
        
        # Loc/nav info for map and MQ2Nav (zone, x, y, z?, description?, nav_loc)
        if item_data.get('locs'):
            lines.append("        locs = {")
            for loc in item_data['locs']:
                lines.append("            {")
                lines.append(f"                zone = \"{_escape_lua(loc.get('zone',''))}\",")
                lines.append(f"                x = {loc.get('x', 0)},")
                lines.append(f"                y = {loc.get('y', 0)},")
                if loc.get('z') is not None:
                    lines.append(f"                z = {loc['z']},")
                if loc.get('description'):
                    lines.append(f"                description = \"{_escape_lua(loc['description'])}\",")
                lines.append(f"                nav_loc = \"{_escape_lua(loc.get('nav_loc',''))}\",")
                if loc.get('context'):
                    lines.append(f"                context = \"{_escape_lua(loc['context'])}\",")
                if loc.get('class'):
                    lines.append(f"                class = \"{_escape_lua(loc['class'])}\",")
                if loc.get('quest'):
                    lines.append(f"                quest = \"{_escape_lua(loc['quest'])}\",")
                if loc.get('step') is not None:
                    lines.append(f"                step = {loc['step']},")
                lines.append("            },")
            lines.append("        },")
        
        # Quest references
        lines.append("        quests = {")
        for quest_ref in item_data['quests']:
            lines.append("            {")
            lines.append(f"                class = \"{quest_ref['class']}\",")
            lines.append(f"                quest = \"{quest_ref['quest']}\",")
            lines.append(f"                step = \"{quest_ref.get('step', 'unknown')}\",")
            lines.append(f"                section = \"{quest_ref.get('section', '')}\",")
            lines.append(f"                context = \"{quest_ref.get('context', 'unknown')}\",")
            if quest_ref.get('mob'):
                lines.append(f"                mob = \"{quest_ref['mob']}\",")
            if quest_ref.get('zone'):
                lines.append(f"                zone = \"{quest_ref['zone']}\",")
            lines.append("            },")
        lines.append("        },")
        
        # Used by classes
        if item_data['used_by_classes']:
            lines.append("        used_by_classes = {")
            for class_name in item_data['used_by_classes']:
                lines.append(f"            \"{class_name}\",")
            lines.append("        },")
        
        # Notes
        if item_data.get('notes'):
            lines.append("        notes = {")
            for note in item_data['notes']:
                lines.append(f"            \"{note}\",")
            lines.append("        },")
        
        lines.append("    },")
    
    lines.append("}")
    lines.append("")
    lines.append("return master_items")
    
    return "\n".join(lines)

def generate_epic_items_ini(master_items: Dict) -> str:
    """Generate epic_items_exact.ini for sell protection (shared_config). Chunked to avoid 2048 limit."""
    items_list = sorted(master_items.keys())
    if not items_list:
        return "[Items]\nexact=\n"
    value = "/".join(items_list)
    max_chunk = 2000
    lines = ["[Items]"]
    if len(value) <= max_chunk:
        lines.append(f"exact={value}")
    else:
        pos = 0
        chunk_num = 1
        while pos < len(value):
            end = min(pos + max_chunk, len(value))
            chunk = value[pos:end]
            if end < len(value):
                last_slash = chunk.rfind("/")
                if last_slash > 0:
                    end = pos + last_slash + 1
                    chunk = value[pos:end]
            key = "exact" if chunk_num == 1 else f"exact{chunk_num}"
            lines.append(f"{key}={chunk}")
            pos = end
            chunk_num += 1
    return "\n".join(lines) + "\n"


def generate_epic_items_by_class(master_items: Dict) -> Dict[str, str]:
    """Generate per-class epic_items_<class>.ini files. Returns {class_name: ini_content}."""
    by_class = defaultdict(list)
    for item_name, item_data in master_items.items():
        for cls in item_data.get('used_by_classes', []):
            by_class[cls].append(item_name)
    result = {}
    for cls, items_list in sorted(by_class.items()):
        items_list = sorted(items_list)
        if not items_list:
            result[cls] = "[Items]\nexact=\n"
            continue
        value = "/".join(items_list)
        max_chunk = 2000
        lines = ["[Items]"]
        if len(value) <= max_chunk:
            lines.append(f"exact={value}")
        else:
            pos = 0
            chunk_num = 1
            while pos < len(value):
                end = min(pos + max_chunk, len(value))
                chunk = value[pos:end]
                if end < len(value):
                    last_slash = chunk.rfind("/")
                    if last_slash > 0:
                        end = pos + last_slash + 1
                        chunk = value[pos:end]
                key = "exact" if chunk_num == 1 else f"exact{chunk_num}"
                lines.append(f"{key}={chunk}")
                pos = end
                chunk_num += 1
        result[cls] = "\n".join(lines) + "\n"
    return result


if __name__ == '__main__':
    # Load epic quest data
    with open('../data/epic_quests_structured.json', 'r', encoding='utf-8') as f:
        epic_data = json.load(f)
    
    # Generate master items
    master_items = generate_master_items(epic_data)
    
    # Save to JSON
    with open('../data/master_items.json', 'w', encoding='utf-8') as f:
        json.dump(master_items, f, indent=2, ensure_ascii=False)
    
    # Generate Lua version
    lua_output = generate_lua_items_table(master_items)
    with open('../data/master_items.lua', 'w', encoding='utf-8') as f:
        f.write(lua_output)
    
    # Generate epic_items_exact.ini for sell protection (Protect Epic Items)
    import os
    shared_config_dir = os.path.join(os.path.dirname(__file__), '..', '..', 'Macros', 'shared_config')
    os.makedirs(shared_config_dir, exist_ok=True)
    epic_ini_path = os.path.join(shared_config_dir, 'epic_items_exact.ini')
    with open(epic_ini_path, 'w', encoding='utf-8') as f:
        f.write(generate_epic_items_ini(master_items))
    
    # Generate per-class epic_items_<class>.ini for class-filtered loot/sell
    by_class = generate_epic_items_by_class(master_items)
    for cls, content in by_class.items():
        cls_path = os.path.join(shared_config_dir, f'epic_items_{cls}.ini')
        with open(cls_path, 'w', encoding='utf-8') as f:
            f.write(content)
    
    print(f"Generated master items list with {len(master_items)} items")
    print("Files created:")
    print("  - ../data/master_items.json")
    print("  - ../data/master_items.lua")
    print(f"  - {epic_ini_path}")
    print(f"  - epic_items_<class>.ini for {len(by_class)} classes: {', '.join(sorted(by_class.keys()))}")
