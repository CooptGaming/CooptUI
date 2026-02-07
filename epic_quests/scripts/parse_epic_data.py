#!/usr/bin/env python3
"""
Parse epic quest data from fetched HTML and create structured JSON/Lua output
"""

import json
import re
from typing import Dict, List, Optional
from dataclasses import dataclass, asdict
from enum import Enum

class StepType(Enum):
    TALK = "talk"
    KILL = "kill"
    LOOT = "loot"
    GIVE = "give"
    PICKPOCKET = "pickpocket"
    TRAVEL = "travel"
    CRAFT = "craft"
    OTHER = "other"

@dataclass
class Location:
    zone: str
    x: Optional[float] = None
    y: Optional[float] = None
    z: Optional[float] = None
    description: Optional[str] = None

@dataclass
class NPC:
    name: str
    location: Location
    spawn_time: Optional[str] = None
    placeholder: Optional[str] = None
    faction_notes: Optional[str] = None

@dataclass
class Mob:
    name: str
    level: Optional[int] = None
    location: Location
    spawn_time: Optional[str] = None
    placeholder: Optional[str] = None
    notes: Optional[str] = None

@dataclass
class Item:
    name: str
    quests: List[str]  # Which quests use this item
    source_type: str  # "drop", "quest_reward", "crafted", "purchased", "ground_spawn", "pickpocket"
    source_mob: Optional[str] = None
    source_npc: Optional[str] = None
    source_zone: Optional[str] = None
    source_location: Optional[Location] = None
    drop_rate: Optional[str] = None  # "common", "uncommon", "rare", "very_rare"
    notes: Optional[str] = None

@dataclass
class QuestStep:
    step_number: int
    step_type: str
    description: str
    npc: Optional[NPC] = None
    mob: Optional[Mob] = None
    item: Optional[str] = None  # Item name
    location: Optional[Location] = None
    dialogue: Optional[str] = None
    requirements: Optional[List[str]] = None  # Other items needed, level requirements, etc.
    notes: Optional[str] = None

@dataclass
class EpicQuest:
    class_name: str
    quest_name: str
    reward_item: str
    start_zone: str
    start_npc: Optional[NPC] = None
    recommended_level: Optional[int] = None
    steps: List[QuestStep] = None
    items: List[Item] = None
    npcs: List[NPC] = None
    mobs: List[Mob] = None
    zones: List[str] = None
    
    def __post_init__(self):
        if self.steps is None:
            self.steps = []
        if self.items is None:
            self.items = []
        if self.npcs is None:
            self.npcs = []
        if self.mobs is None:
            self.mobs = []
        if self.zones is None:
            self.zones = []

def parse_coordinates(text: str) -> Optional[Location]:
    """Extract coordinates from text"""
    # Pattern for loc(x, y) or loc(x, y, z)
    loc_pattern = r'loc\(([+-]?\d+(?:\.\d+)?),\s*([+-]?\d+(?:\.\d+)?)(?:,\s*([+-]?\d+(?:\.\d+)?))?\)'
    match = re.search(loc_pattern, text, re.IGNORECASE)
    if match:
        return Location(
            zone="",  # Will be filled in separately
            x=float(match.group(1)),
            y=float(match.group(2)),
            z=float(match.group(3)) if match.group(3) else None
        )
    
    # Pattern for +x, -y format
    coord_pattern = r'([+-]?\d+(?:\.\d+)?)\s*,\s*([+-]?\d+(?:\.\d+)?)'
    match = re.search(coord_pattern, text)
    if match:
        return Location(
            zone="",
            x=float(match.group(1)),
            y=float(match.group(2))
        )
    
    return None

def extract_zone_name(text: str) -> Optional[str]:
    """Extract zone name from text"""
    # Common zone patterns
    zone_patterns = [
        r'in\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)',
        r'to\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)',
        r'from\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)',
    ]
    
    for pattern in zone_patterns:
        match = re.search(pattern, text)
        if match:
            zone = match.group(1)
            # Filter out common false positives
            if zone not in ['Kill', 'Give', 'Talk', 'Loot', 'Find']:
                return zone
    
    return None

def parse_bard_epic() -> EpicQuest:
    """Parse Bard epic quest from known data"""
    quest = EpicQuest(
        class_name="bard",
        quest_name="Singing Short Sword",
        reward_item="Singing Short Sword",
        start_zone="Dreadlands",
        recommended_level=46,
        start_npc=NPC(
            name="Baldric Slezaf",
            location=Location(zone="Dreadlands", x=773, y=9666)
        )
    )
    
    # Add zones
    quest.zones = [
        "Dreadlands", "Western Karana", "Misty Thicket", "Southern Desert of Ro",
        "Lake Rathetear", "South Karana", "Solusek's Eye", "The Estate of Unrest",
        "Rathe Mountains", "Burning Woods", "Skyfire Mountains", "Ocean of Tears",
        "Butcherblock Mountains", "Steamfont Mountains", "Kedge Keep",
        "Plane of Fear", "Karnor's Castle", "Old Sebilis"
    ]
    
    # Step 1: Maestro's Symphony Page 24 Top
    quest.steps.append(QuestStep(
        step_number=1,
        step_type=StepType.TALK.value,
        description="Talk to Konia Swiftfoot in Western Karana",
        npc=NPC(
            name="Konia Swiftfoot",
            location=Location(zone="Western Karana", x=-516, y=-2434)
        ),
        dialogue="Say 'I would like to participate' then 'I am ready'",
        item="Torch of Misty"
    ))
    
    # Continue with more steps...
    # This is a template - will be populated with full data
    
    return quest

def create_lua_output(quest: EpicQuest) -> str:
    """Convert quest data to Lua table format"""
    lua_lines = [
        f"-- {quest.class_name.upper()} Epic Quest: {quest.quest_name}",
        f"local {quest.class_name}_epic = {{",
        f"    class = \"{quest.class_name}\",",
        f"    quest_name = \"{quest.quest_name}\",",
        f"    reward_item = \"{quest.reward_item}\",",
        f"    start_zone = \"{quest.start_zone}\",",
        f"    recommended_level = {quest.recommended_level or 'nil'},"
    ]
    
    # Add start NPC
    if quest.start_npc:
        lua_lines.append("    start_npc = {")
        lua_lines.append(f"        name = \"{quest.start_npc.name}\",")
        lua_lines.append(f"        zone = \"{quest.start_npc.location.zone}\",")
        if quest.start_npc.location.x is not None:
            lua_lines.append(f"        x = {quest.start_npc.location.x},")
        if quest.start_npc.location.y is not None:
            lua_lines.append(f"        y = {quest.start_npc.location.y},")
        lua_lines.append("    },")
    
    # Add zones
    lua_lines.append("    zones = {")
    for zone in quest.zones:
        lua_lines.append(f"        \"{zone}\",")
    lua_lines.append("    },")
    
    # Add steps
    lua_lines.append("    steps = {")
    for step in quest.steps:
        lua_lines.append("        {")
        lua_lines.append(f"            step_number = {step.step_number},")
        lua_lines.append(f"            step_type = \"{step.step_type}\",")
        lua_lines.append(f"            description = \"{step.description}\",")
        if step.npc:
            lua_lines.append(f"            npc = \"{step.npc.name}\",")
        if step.mob:
            lua_lines.append(f"            mob = \"{step.mob.name}\",")
        if step.item:
            lua_lines.append(f"            item = \"{step.item}\",")
        lua_lines.append("        },")
    lua_lines.append("    },")
    
    lua_lines.append("}")
    lua_lines.append(f"return {quest.class_name}_epic")
    
    return "\n".join(lua_lines)

if __name__ == '__main__':
    # Example usage
    bard_quest = parse_bard_epic()
    lua_output = create_lua_output(bard_quest)
    print(lua_output)
