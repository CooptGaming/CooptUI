#!/usr/bin/env python3
"""
Add Rogue epic quest data to structured JSON file
"""

import json

rogue_epic = {
    "class": "rogue",
    "quest_name": "Ragebringer",
    "reward_item": "Ragebringer",
    "start_zone": "Qeynos Aqueducts",
    "start_npc": {
        "name": "Malka Rale",
        "location": {
            "zone": "Qeynos Aqueducts",
            "x": 380,
            "y": -210,
            "z": -80,
            "description": "In the 'Smuggler' area of the sewer. Spawns at 8PM game time, placeholder is 'a courier'"
        },
        "spawn_time": "8PM game time",
        "placeholder": "a courier"
    },
    "recommended_level": 46,
    "zones": [
        "Qeynos Aqueducts",
        "North Kaladim",
        "Neriak Third Gate",
        "Highpass Hold",
        "Lake Rathetear",
        "Steamfont Mountains",
        "Plane of Hate",
        "Kithicor Forest",
        "Western Plains of Karana",
        "Nagafen's Lair",
        "Lower Guk",
        "Everfrost Peaks",
        "Splitpaw",
        "Ocean of Tears"
    ],
    "steps": [
        {
            "step_number": 1,
            "section": "Stanos' Pouch",
            "step_type": "talk",
            "description": "Talk to Malka Rale in Qeynos Aqueducts",
            "npc": {
                "name": "Malka Rale",
                "location": {
                    "zone": "Qeynos Aqueducts",
                    "x": 380,
                    "y": -210,
                    "z": -80
                },
                "spawn_time": "8PM game time",
                "placeholder": "a courier"
            },
            "dialogue": ["Say 'I can help'"],
            "receive_item": "Stanos' Pouch",
            "notes": "Level 50 required. Can skip this step and go directly to Anson McBale if you have high faction."
        },
        {
            "step_number": 2,
            "section": "Stained Parchment Top",
            "step_type": "pickpocket",
            "description": "Pickpocket Stained Parchment Top from Founy Jestands",
            "npc": {
                "name": "Founy Jestands",
                "location": {
                    "zone": "North Kaladim",
                    "x": 520,
                    "y": 307,
                    "description": "Rogue guildmaster at the bank"
                },
                "spawn_time": "10AM game time",
                "notes": "Does not always have the piece - wait full day cycle if needed. If caught, run to zone."
            },
            "loot_item": "Stained Parchment Top"
        },
        {
            "step_number": 3,
            "section": "Stained Parchment Bottom",
            "step_type": "pickpocket",
            "description": "Pickpocket Stained Parchment Bottom from Tani N'Mar",
            "npc": {
                "name": "Tani N'Mar",
                "location": {
                    "zone": "Neriak Third Gate",
                    "x": 650,
                    "y": -1300,
                    "description": "Hall of the Ebon Mask (rogue's guild)"
                },
                "spawn_time": "Depops at 7PM, respawns at 8PM (3 minutes after despawning)",
                "notes": "Does not always have the piece. Failed pickpocket triggers all NPCs in room to assist - run to zone."
            },
            "loot_item": "Stained Parchment Bottom"
        },
        {
            "step_number": 4,
            "section": "Combined Parchment",
            "step_type": "give",
            "description": "Give both parchment pieces to Stanos Herkanor",
            "npc": {
                "name": "Stanos Herkanor",
                "location": {
                    "zone": "Highpass Hold",
                    "x": 10,
                    "y": 325,
                    "description": "Secret smugglers cave - jump into water near inn, swim to +10, +325, walk up narrow passage"
                },
                "spawn_notes": "Give Stanos' Pouch to Anson McBale to spawn Stanos, or say 'I need to see Stanos' if high faction. If Anson not in camp, kill placeholder 'a smuggler'"
            },
            "give_items": ["Stained Parchment Top", "Stained Parchment Bottom"],
            "receive_item": "Combined Parchment",
            "notes": "Can sneak to turn in if faction is low, but be careful of Anson and Stanos facing directions"
        },
        {
            "step_number": 5,
            "section": "Scribbled Parchment",
            "step_type": "give",
            "description": "Give Combined Parchment, 100pp, and 2 unstacked Bottles of Milk to Eldreth",
            "npc": {
                "name": "Eldreth",
                "location": {
                    "zone": "Lake Rathetear",
                    "x": 2600,
                    "y": -550,
                    "description": "Same tower as Cyanelle, at bookcase next to her"
                },
                "spawn_time": "Moderately rare spawn, can take up to 8 hours real time to respawn after hand-in",
                "notes": "Must have at least indifferent faction, or use sneak technique. Despawns after hand-in."
            },
            "give_items": ["Combined Parchment"],
            "give_currency": {"platinum": 100},
            "give_items_additional": ["Bottle of Milk", "Bottle of Milk"],
            "receive_item": "Scribbled Parchment",
            "notes": "Milk can be purchased from ogre vendors in zone. Must be unstacked."
        },
        {
            "step_number": 6,
            "section": "Book of Souls",
            "step_type": "ground_spawn",
            "description": "Pick up Book of Souls in Plane of Hate",
            "location": {
                "zone": "Plane of Hate",
                "x": -60,
                "y": 325,
                "z": 56,
                "description": "On nightstand on top floor of Maestro of Rancor's house"
            },
            "loot_item": "Book of Souls",
            "notes": "10 hour spawn time. Wandering mobs will pick it up if not collected. Undead see through sneak/hide and normal invis."
        },
        {
            "step_number": 7,
            "section": "Tattered Parchment",
            "step_type": "give",
            "description": "Give Scribbled Parchment to Yendar Starpyre",
            "npc": {
                "name": "Yendar Starpyre",
                "location": {
                    "zone": "Steamfont Mountains",
                    "description": "Wanders the zone, easily spotted wearing SMR. Short loop path: north from druid ring, past kobold tents, east around mountain stub, southeast down road towards Watchman Halv, then back"
                },
                "spawn_time": "Few hours respawn",
                "notes": "Say 'book' to stop him from running"
            },
            "give_item": "Scribbled Parchment",
            "receive_item": "Tattered Parchment",
            "notes": "Yendar despawns after this hand-in"
        },
        {
            "step_number": 8,
            "section": "Translated Parchment and Jagged Diamond Dagger",
            "step_type": "give",
            "description": "Give Tattered Parchment and Book of Souls to Yendar Starpyre (after respawn)",
            "npc": {
                "name": "Yendar Starpyre",
                "location": {
                    "zone": "Steamfont Mountains"
                }
            },
            "give_items": ["Tattered Parchment", "Book of Souls"],
            "spawns_mob": "Renux Herkanor",
            "notes": "Yendar despawns and Renux spawns in his place"
        },
        {
            "step_number": 9,
            "section": "Renux Herkanor",
            "step_type": "kill",
            "description": "Kill Renux Herkanor",
            "mob": {
                "name": "Renux Herkanor",
                "level": 50,
                "location": {
                    "zone": "Steamfont Mountains"
                },
                "notes": "Level 50 human rogue. Quad hits for 200, backstab for 200+. Casts clockwork poison (spinning stun). Does not attack pets. Can be feared and snared. Best strategy: pet kiting with fear. Can be duo'd by rogue if agro kited by caster."
            },
            "loot_items": ["Translated Parchment", "Jagged Diamond Dagger"],
            "notes": "Renux is Stanos' daughter. She will not attack until provoked. Can be duo'd if agro kited properly."
        },
        {
            "step_number": 10,
            "section": "Sealed Box",
            "step_type": "give",
            "description": "Give Translated Parchment to Stanos Herkanor",
            "npc": {
                "name": "Stanos Herkanor",
                "location": {
                    "zone": "Highpass Hold",
                    "x": 10,
                    "y": 325
                }
            },
            "give_item": "Translated Parchment",
            "receive_item": "Sealed Box"
        },
        {
            "step_number": 11,
            "section": "General's Pouch",
            "step_type": "give",
            "description": "Give Sealed Box to any dark elf in Kithicor Forest (at night)",
            "npc": {
                "name": "Dark Elf (any)",
                "location": {
                    "zone": "Kithicor Forest",
                    "x": 800,
                    "y": 2400,
                    "description": "Burned-out cabin during game night"
                },
                "notes": "IMPORTANT: Do NOT use hide or invisibility/IVU while turning in, but DO use sneak. Verify sneaking but not hidden, and mob cons indifferent before turn-in or may lose progress!"
            },
            "give_item": "Sealed Box",
            "spawns_mob": "General V'Ghera"
        },
        {
            "step_number": 12,
            "section": "General V'Ghera",
            "step_type": "kill",
            "description": "Kill General V'Ghera",
            "mob": {
                "name": "General V'Ghera",
                "level": 60,
                "location": {
                    "zone": "Kithicor Forest"
                },
                "notes": "Very hard level 60 being. Quad attacks for 275 quickly. Has 1500pt harm touch. Casts soul devour. Can summon mobs from zone to assist. Weak to: Wizard Lure Line, Poison Spells, Scent Line, Fire Based Spells. Extremely strong against magic based spells."
            },
            "loot_items": ["General's Pouch", "Cazic Quill"],
            "notes": "Cazic Quill is rare drop. If not obtained, must complete sub-quest."
        },
        {
            "step_number": 13,
            "section": "Cazic Quill Sub-Quest - Robe of the Kedge",
            "step_type": "kill",
            "description": "Kill Phinigel Autropos in Kedge Keep (if Cazic Quill not dropped)",
            "mob": {
                "name": "Phinigel Autropos",
                "level": 50,
                "location": {
                    "zone": "Kedge Keep"
                },
                "notes": "Very rare drop. Can also drop from Coercer Q'ioul in Kithicor Forest. Usually price is 4k for multiquest."
            },
            "loot_item": "Robe of the Kedge"
        },
        {
            "step_number": 14,
            "section": "Cazic Quill Sub-Quest - Robe of the Ishva",
            "step_type": "kill",
            "description": "Kill The Ishva Mal in Splitpaw (if Cazic Quill not dropped)",
            "mob": {
                "name": "The Ishva Mal",
                "level": 28,
                "location": {
                    "zone": "Splitpaw"
                },
                "spawn_time": "28 minute spawn with placeholders",
                "notes": "Not no drop, can be purchased for 300-500pp. Can also drop from Coercer Q'ioul and Advisor C'zatl in Kithicor Forest."
            },
            "loot_item": "Robe of the Ishva"
        },
        {
            "step_number": 15,
            "section": "Cazic Quill Sub-Quest - Shining Metallic Robes",
            "step_type": "kill",
            "description": "Kill Ghoul Archmagus in Lower Guk (if Cazic Quill not dropped)",
            "mob": {
                "name": "Ghoul Archmagus",
                "level": 30,
                "location": {
                    "zone": "Lower Guk",
                    "description": "Magi Room"
                },
                "spawn_time": "30 minute spawn",
                "placeholder": "Kor Ghoul Wizard or Dar Ghoul Knight",
                "notes": "Rare drop. Not no drop, can be purchased for 1.7-2k. Can also drop from Yendar Starpyre in Steamfont (much harder)."
            },
            "loot_item": "Shining Metallic Robes"
        },
        {
            "step_number": 16,
            "section": "Cazic Quill Sub-Quest - Robe of the Oracle",
            "step_type": "kill",
            "description": "Kill Oracle of K'Arnon in Ocean of Tears (if Cazic Quill not dropped)",
            "mob": {
                "name": "Oracle of K'Arnon",
                "level": 40,
                "location": {
                    "zone": "Ocean of Tears",
                    "description": "Directly straight forward from docks on Sister Isle"
                },
                "notes": "Level 40 wizard, hardly any hitpoints. Has level 40 paladin guardian. Root guardian out of healing range, kill Oracle, loot robe, teleport out. Can be purchased for 150-200pp."
            },
            "loot_item": "Robe of the Oracle"
        },
        {
            "step_number": 17,
            "section": "Cazic Quill Sub-Quest",
            "step_type": "give",
            "description": "Give all four robes to Vilnius the Small (if Cazic Quill not dropped)",
            "npc": {
                "name": "Vilnius the Small",
                "location": {
                    "zone": "Western Plains of Karana",
                    "x": 340,
                    "y": -6700,
                    "description": "Bandit camp"
                },
                "spawn_notes": "Kill bandit that runs from camp to top of hill until 'a brigand' spawns. Leave brigand alone, at 11PM game time Vilnius spawns in his place. Ultra-rare spawn. Don't try to spawn until you have all four robes."
            },
            "give_items": ["Robe of the Kedge", "Robe of the Ishva", "Shining Metallic Robes", "Robe of the Oracle"],
            "receive_item": "Cazic Quill"
        },
        {
            "step_number": 18,
            "section": "Jagged Diamond Dagger Sub-Quest - Fleshripper",
            "step_type": "kill",
            "description": "Kill Solusek kobold king in Nagafen's Lair (if Jagged Diamond Dagger not dropped)",
            "mob": {
                "name": "Solusek kobold king",
                "location": {
                    "zone": "Nagafen's Lair"
                }
            },
            "loot_item": "Fleshripper"
        },
        {
            "step_number": 19,
            "section": "Jagged Diamond Dagger Sub-Quest - Painbringer",
            "step_type": "kill",
            "description": "Kill Kobold champion in Nagafen's Lair (if Jagged Diamond Dagger not dropped)",
            "mob": {
                "name": "Kobold champion",
                "location": {
                    "zone": "Nagafen's Lair"
                }
            },
            "loot_item": "Painbringer"
        },
        {
            "step_number": 20,
            "section": "Jagged Diamond Dagger Sub-Quest - Mithril Two-Handed Sword",
            "step_type": "kill",
            "description": "Kill The froglok king in Lower Guk (if Jagged Diamond Dagger not dropped)",
            "mob": {
                "name": "The froglok king",
                "location": {
                    "zone": "Lower Guk",
                    "description": "Live side"
                }
            },
            "loot_item": "Mithril Two-Handed Sword"
        },
        {
            "step_number": 21,
            "section": "Jagged Diamond Dagger Sub-Quest - Gigantic Zweihander",
            "step_type": "kill",
            "description": "Kill Karg Icebear in Everfrost Peaks (if Jagged Diamond Dagger not dropped)",
            "mob": {
                "name": "Karg Icebear",
                "location": {
                    "zone": "Everfrost Peaks"
                }
            },
            "loot_item": "Gigantic Zweihander"
        },
        {
            "step_number": 22,
            "section": "Jagged Diamond Dagger Sub-Quest",
            "step_type": "give",
            "description": "Give all four blades to Vilnius the Small (if Jagged Diamond Dagger not dropped)",
            "npc": {
                "name": "Vilnius the Small",
                "location": {
                    "zone": "Western Plains of Karana",
                    "x": 340,
                    "y": -6700
                }
            },
            "give_items": ["Fleshripper", "Painbringer", "Mithril Two-Handed Sword", "Gigantic Zweihander"],
            "receive_item": "Jagged Diamond Dagger"
        },
        {
            "step_number": 23,
            "section": "Ragebringer",
            "step_type": "give",
            "description": "Give General's Pouch, Cazic Quill, and Jagged Diamond Dagger to Stanos Herkanor",
            "npc": {
                "name": "Stanos Herkanor",
                "location": {
                    "zone": "Highpass Hold",
                    "x": 10,
                    "y": 325
                }
            },
            "give_items": ["General's Pouch", "Cazic Quill", "Jagged Diamond Dagger"],
            "receive_item": "Ragebringer"
        }
    ]
}

if __name__ == '__main__':
    # Load existing data
    with open('../data/epic_quests_structured.json', 'r', encoding='utf-8') as f:
        data = json.load(f)
    
    # Add rogue epic
    data['epic_quests']['rogue'] = rogue_epic
    
    # Save updated data
    with open('../data/epic_quests_structured.json', 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print("Added Rogue epic quest data")
