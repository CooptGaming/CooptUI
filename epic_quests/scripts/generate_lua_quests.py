#!/usr/bin/env python3
"""
Generate Lua quest data files from JSON structured data
Creates individual quest files and a master index
"""

import json
import os
from typing import Dict

def escape_lua_string(s: str) -> str:
    """Escape string for Lua"""
    return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')

def generate_location_lua(location: Dict) -> str:
    """Generate Lua table for location"""
    lines = ["        location = {"]
    lines.append(f"            zone = \"{escape_lua_string(location.get('zone', ''))}\",")
    
    if location.get('x') is not None:
        lines.append(f"            x = {location['x']},")
    if location.get('y') is not None:
        lines.append(f"            y = {location['y']},")
    if location.get('z') is not None:
        lines.append(f"            z = {location['z']},")
    if location.get('description'):
        lines.append(f"            description = \"{escape_lua_string(location['description'])}\",")
    
    lines.append("        },")
    return "\n".join(lines)

def generate_npc_lua(npc: Dict) -> str:
    """Generate Lua table for NPC"""
    lines = ["        npc = {"]
    lines.append(f"            name = \"{escape_lua_string(npc.get('name', ''))}\",")
    
    if 'location' in npc:
        lines.append(generate_location_lua(npc['location']).replace('        ', '            '))
    
    if npc.get('spawn_time'):
        lines.append(f"            spawn_time = \"{escape_lua_string(npc['spawn_time'])}\",")
    if npc.get('placeholder'):
        lines.append(f"            placeholder = \"{escape_lua_string(npc['placeholder'])}\",")
    if npc.get('faction_notes'):
        lines.append(f"            faction_notes = \"{escape_lua_string(npc['faction_notes'])}\",")
    
    lines.append("        },")
    return "\n".join(lines)

def generate_mob_lua(mob: Dict) -> str:
    """Generate Lua table for mob"""
    lines = ["        mob = {"]
    lines.append(f"            name = \"{escape_lua_string(mob.get('name', ''))}\",")
    
    if mob.get('level'):
        lines.append(f"            level = {mob['level']},")
    
    if 'location' in mob:
        lines.append(generate_location_lua(mob['location']).replace('        ', '            '))
    
    if mob.get('spawn_time'):
        lines.append(f"            spawn_time = \"{escape_lua_string(mob['spawn_time'])}\",")
    if mob.get('placeholder'):
        lines.append(f"            placeholder = \"{escape_lua_string(mob['placeholder'])}\",")
    if mob.get('notes'):
        lines.append(f"            notes = \"{escape_lua_string(mob['notes'])}\",")
    
    lines.append("        },")
    return "\n".join(lines)

def generate_quest_lua(quest_data: Dict) -> str:
    """Generate complete Lua file for a quest"""
    class_name = quest_data.get('class', 'unknown')
    quest_name = quest_data.get('quest_name', 'Unknown')
    
    lines = [
        f"-- {class_name.upper()} Epic Quest: {quest_name}",
        "-- Auto-generated from structured quest data",
        "",
        f"local {class_name}_epic = {{"
    ]
    
    # Basic info
    lines.append(f"    class = \"{class_name}\",")
    lines.append(f"    quest_name = \"{escape_lua_string(quest_name)}\",")
    lines.append(f"    reward_item = \"{escape_lua_string(quest_data.get('reward_item', ''))}\",")
    lines.append(f"    start_zone = \"{escape_lua_string(quest_data.get('start_zone', ''))}\",")
    
    if quest_data.get('recommended_level'):
        lines.append(f"    recommended_level = {quest_data['recommended_level']},")
    
    # Start NPC
    if 'start_npc' in quest_data:
        lines.append("    start_npc = {")
        start_npc_lines = generate_npc_lua(quest_data['start_npc']).split('\n')
        lines.extend([line.replace('        ', '    ') for line in start_npc_lines])
        lines.append("    },")
    
    # Zones
    if quest_data.get('zones'):
        lines.append("    zones = {")
        for zone in quest_data['zones']:
            lines.append(f"        \"{escape_lua_string(zone)}\",")
        lines.append("    },")
    
    # Steps
    lines.append("    steps = {")
    for step in quest_data.get('steps', []):
        lines.append("        {")
        lines.append(f"            step_number = {step.get('step_number', 0)},")
        lines.append(f"            step_type = \"{step.get('step_type', 'unknown')}\",")
        lines.append(f"            description = \"{escape_lua_string(step.get('description', ''))}\",")
        
        if step.get('section'):
            lines.append(f"            section = \"{escape_lua_string(step['section'])}\",")
        
        if 'npc' in step:
            npc_lines = generate_npc_lua(step['npc']).split('\n')
            lines.extend([line.replace('        ', '            ') for line in npc_lines])
        
        if 'mob' in step:
            mob_lines = generate_mob_lua(step['mob']).split('\n')
            lines.extend([line.replace('        ', '            ') for line in mob_lines])
        
        if step.get('give_item'):
            lines.append(f"            give_item = \"{escape_lua_string(step['give_item'])}\",")
        if step.get('give_items'):
            lines.append("            give_items = {")
            for item in step['give_items']:
                lines.append(f"                \"{escape_lua_string(item)}\",")
            lines.append("            },")
        if step.get('receive_item'):
            lines.append(f"            receive_item = \"{escape_lua_string(step['receive_item'])}\",")
        if step.get('loot_item'):
            lines.append(f"            loot_item = \"{escape_lua_string(step['loot_item'])}\",")
        if step.get('item'):
            lines.append(f"            item = \"{escape_lua_string(step['item'])}\",")
        
        if step.get('dialogue'):
            if isinstance(step['dialogue'], list):
                lines.append("            dialogue = {")
                for line in step['dialogue']:
                    lines.append(f"                \"{escape_lua_string(line)}\",")
                lines.append("            },")
            else:
                lines.append(f"            dialogue = \"{escape_lua_string(step['dialogue'])}\",")
        
        if step.get('requirements'):
            lines.append("            requirements = {")
            for req in step['requirements']:
                lines.append(f"                \"{escape_lua_string(req)}\",")
            lines.append("            },")
        
        if step.get('notes'):
            lines.append(f"            notes = \"{escape_lua_string(step['notes'])}\",")
        
        if step.get('spawns_mob'):
            lines.append(f"            spawns_mob = \"{escape_lua_string(step['spawns_mob'])}\",")
        
        lines.append("        },")
    
    lines.append("    },")
    lines.append("}")
    lines.append("")
    lines.append(f"return {class_name}_epic")
    
    return "\n".join(lines)

def generate_master_index(epic_data: Dict, output_dir: str) -> str:
    """Generate master index file that loads all quests"""
    lines = [
        "-- Master Epic Quest Index",
        "-- Auto-generated index file that loads all epic quest data",
        "",
        "local epic_quests = {}"
    ]
    
    for class_name in sorted(epic_data.get('epic_quests', {}).keys()):
        lines.append(f"epic_quests[\"{class_name}\"] = require(\"epic_quests.data.lua.{class_name}_epic\")")
    
    lines.append("")
    lines.append("return epic_quests")
    
    return "\n".join(lines)

if __name__ == '__main__':
    # Load epic quest data
    with open('../data/epic_quests_structured.json', 'r', encoding='utf-8') as f:
        epic_data = json.load(f)
    
    # Create output directory
    output_dir = '../data/lua'
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate individual quest files
    for class_name, quest_data in epic_data.get('epic_quests', {}).items():
        lua_content = generate_quest_lua(quest_data)
        output_file = os.path.join(output_dir, f"{class_name}_epic.lua")
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write(lua_content)
        print(f"Generated {output_file}")
    
    # Generate master index
    index_content = generate_master_index(epic_data, output_dir)
    index_file = os.path.join(output_dir, 'epic_quests_index.lua')
    with open(index_file, 'w', encoding='utf-8') as f:
        f.write(index_content)
    print(f"Generated {index_file}")
    
    print(f"\nGenerated {len(epic_data.get('epic_quests', {}))} quest files")
