-- WARRIOR Epic Quest: Blades of Strategy & Tactics / Jagged Blade of War
-- Auto-generated from structured quest data

local warrior_epic = {
    class = "warrior",
    quest_name = "Blades of Strategy & Tactics / Jagged Blade of War",
    reward_item = "Blade of Strategy, Blade of Tactics, Jagged Blade of War",
    start_zone = "East Freeport",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Kargek Redblade / Wenden Blackhammer",
        location = {
        zone = "East Freeport",
        description = "Kargek Redblade standing under gazebo at -239, -566. Nearby is Dwarf named Wenden Blackhammer. To get to them, head in gate from North Ro and follow left wall",
        },
    },
    },
    zones = {
        "East Freeport",
        "Lake Rathetear",
        "Timorous Deep",
        "Dreadlands",
        "Frontier Mountains",
        "Plane of Fear",
        "Ocean of Tears",
        "Permafrost",
        "Chardok",
        "Feerrott",
        "East Karana",
        "Nagafen's Lair",
        "The Hole",
        "Skyfire Mountains",
        "Emerald Jungle",
        "Veeshan's Peak",
        "Plane of Hate",
        "Plane of Sky",
    },
    steps = {
        {
            step_number = 1,
            step_type = "loot",
            description = "Retrieve Unjeweled Dragon Head Hilt from Lake Rathetear",
            section = "Jeweled Dragon Head Hilt",
            loot_item = "Unjeweled Dragon Head Hilt",
        },
        {
            step_number = 2,
            step_type = "obtain",
            description = "Obtain Diamond, Black Sapphire, and Jacinth",
            section = "Jeweled Dragon Head Hilt",
            notes = "Drop in various zones (Sebilis, Planes) and can almost always be found for sale in Eastern Commonlands",
        },
        {
            step_number = 3,
            step_type = "give",
            description = "Give Unjeweled Dragon Head Hilt, Diamond, Jacinth, and Black Sapphire to Wenden Blackhammer",
            section = "Jeweled Dragon Head Hilt",
            npc = {
                name = "Wenden Blackhammer",
                location = {
                        zone = "East Freeport",
                },
            },
            give_items = {
                "Unjeweled Dragon Head Hilt",
                "Diamond",
                "Jacinth",
                "Black Sapphire",
            },
            receive_item = "Jeweled Dragon Head Hilt",
        },
        {
            step_number = 4,
            step_type = "loot",
            description = "Retrieve Severely Damaged Dragon Head Hilt from chessboard in Timorous Deep",
            section = "Finely Crafted Dragon Head Hilt",
            loot_item = "Severely Damaged Dragon Head Hilt",
        },
        {
            step_number = 5,
            step_type = "kill",
            description = "Kill A Mountain Giant Patriarch in Dreadlands",
            section = "Finely Crafted Dragon Head Hilt",
            mob = {
                name = "A Mountain Giant Patriarch",
                location = {
                        zone = "Dreadlands",
                        description = "Giant fort just west of Karnor's Castle",
                },
            },
            loot_item = "Giant Sized Monocle",
        },
        {
            step_number = 6,
            step_type = "give",
            description = "Give Giant Sized Monocle to Mentrax Mountainbone in Frontier Mountains",
            section = "Finely Crafted Dragon Head Hilt",
            npc = {
                name = "Mentrax Mountainbone",
                location = {
                        zone = "Frontier Mountains",
                        description = "Giant fort. Get inside. When get to very end of Mine will see giant named Mentrax Mountainbone",
                },
            },
            give_item = "Giant Sized Monocle",
            receive_item = "Rejesiam Ore",
        },
        {
            step_number = 7,
            step_type = "kill",
            description = "Kill Fright, Dread, or Terror in Plane of Fear",
            section = "Finely Crafted Dragon Head Hilt",
            mob = {
                name = "Fright / Dread / Terror",
                location = {
                        zone = "Plane of Fear",
                        description = "Named golems",
                },
            },
            loot_item = "Ball of Everliving Golem",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Severely Damaged Dragon Head Hilt, Rejesiam Ore, and Ball of Everliving Golem to Wenden Blackhammer",
            section = "Finely Crafted Dragon Head Hilt",
            npc = {
                name = "Wenden Blackhammer",
                location = {
                        zone = "East Freeport",
                },
            },
            give_items = {
                "Severely Damaged Dragon Head Hilt",
                "Rejesiam Ore",
                "Ball of Everliving Golem",
            },
            receive_item = "Finely Crafted Dragon Head Hilt",
            notes = "MQable",
        },
        {
            step_number = 9,
            step_type = "talk",
            description = "Talk to Denken Strongpick in Ocean of Tears",
            section = "Ancient Sword Blade",
            npc = {
                name = "Denken Strongpick",
                location = {
                        zone = "Ocean of Tears",
                        description = "Aviak Island",
                },
            },
        },
        {
            step_number = 10,
            step_type = "purchase",
            description = "Purchase Keg of Vox Tail Ale",
            section = "Ancient Sword Blade",
            item = "Keg of Vox Tail Ale",
            notes = "Bought from lot of vendors around world. Good place to buy one is sandfishers in North Ro or Freeport Port Authority",
        },
        {
            step_number = 11,
            step_type = "purchase",
            description = "Purchase two Rebreathers",
            section = "Ancient Sword Blade",
            item = "Rebreather",
            notes = "Tinkered by Gnomes with Tinkering Skill, Trivial 175. Expect to drop as much as 4k for getting two rebreathers",
        },
        {
            step_number = 12,
            step_type = "kill",
            description = "Kill Ice Giants in Permafrost",
            section = "Ancient Sword Blade",
            mob = {
                name = "Ice Giants",
                location = {
                        zone = "Permafrost",
                },
                notes = "While here, kill some goblin wizards until find frozen goblin heart -- need it later",
            },
            loot_item = "Block of Permafrost",
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give Block of Permafrost, Keg of Vox Tail Ale, and two Rebreathers to Denken Strongpick",
            section = "Ancient Sword Blade",
            npc = {
                name = "Denken Strongpick",
                location = {
                        zone = "Ocean of Tears",
                },
            },
            give_items = {
                "Block of Permafrost",
                "Keg of Vox Tail Ale",
                "Rebreather",
                "Rebreather",
            },
            receive_item = "Ancient Sword Blade",
        },
        {
            step_number = 14,
            step_type = "kill",
            description = "Kill Queen Velazul Di`zok in Chardok",
            section = "Ancient Blade",
            mob = {
                name = "Queen Velazul Di`zok",
                location = {
                        zone = "Chardok",
                },
                notes = "Bring along large group of friends",
            },
            loot_item = "Ancient Blade",
        },
        {
            step_number = 15,
            step_type = "talk",
            description = "Talk to Kargek Redblade in East Freeport",
            section = "Red Scabbard",
            npc = {
                name = "Kargek Redblade",
                location = {
                        zone = "East Freeport",
                        x = -239,
                        y = -566,
                        description = "Standing under gazebo",
                },
            },
            receive_item = "Wax Sealed Note",
        },
        {
            step_number = 16,
            step_type = "give",
            description = "Give Wax Sealed Note to Oknoggin Stonesmacker in Feerrott",
            section = "Red Scabbard",
            npc = {
                name = "Oknoggin Stonesmacker",
                location = {
                        zone = "Feerrott",
                        x = 800,
                        y = 1140,
                        description = "Between Stone Bridge and Fallen Totem",
                },
            },
            give_item = "Wax Sealed Note",
            receive_item = "Tiny Lute",
        },
        {
            step_number = 17,
            step_type = "give",
            description = "Give Tiny Lute to Kargek Redblade",
            section = "Red Scabbard",
            npc = {
                name = "Kargek Redblade",
                location = {
                        zone = "East Freeport",
                },
            },
            give_item = "Tiny Lute",
            receive_item = "Redblade's Legacy",
        },
        {
            step_number = 18,
            step_type = "give",
            description = "Give Redblade's Legacy to Tenal Redblade in East Karana",
            section = "Red Scabbard",
            npc = {
                name = "Tenal Redblade",
                location = {
                        zone = "East Karana",
                        x = -1765,
                        y = -6000,
                        z = 388,
                        description = "Next to tower on ramp to Highpass. Very end of canyon next to ramp to Highpass",
                },
            },
            give_item = "Redblade's Legacy",
            receive_item = "Totem of the Freezing War",
        },
        {
            step_number = 19,
            step_type = "kill",
            description = "Kill A Goblin Wizard in Permafrost",
            section = "Red Scabbard",
            mob = {
                name = "A Goblin Wizard",
                location = {
                        zone = "Permafrost",
                },
                notes = "While here getting Block of Permafrost, kill some goblin wizards until find frozen goblin heart",
            },
            loot_item = "Heart of Frost",
        },
        {
            step_number = 20,
            step_type = "give",
            description = "Give Totem of the Freezing War and Heart of Frost to Tenal Redblade",
            section = "Red Scabbard",
            npc = {
                name = "Tenal Redblade",
                location = {
                        zone = "East Karana",
                },
            },
            give_items = {
                "Totem of the Freezing War",
                "Heart of Frost",
            },
            receive_item = "Totem of Fiery War",
        },
        {
            step_number = 21,
            step_type = "kill",
            description = "Kill Lord Nagafen / Ragefire / Nortlav the Scalekeeper / Talendor for Red Dragon Scales",
            section = "Red Scabbard",
            mob = {
                name = "Lord Nagafen / Ragefire / Nortlav the Scalekeeper / Talendor",
                location = {
                        zone = "Nagafen's Lair / The Hole / Skyfire Mountains",
                        description = "Lord Nagafen in Nagafen's Lair, Ragefire in Nagafen's Lair, Nortlav the Scalekeeper in The Hole, Talendor in Skyfire Mountains",
                },
            },
            loot_item = "Red Dragon Scales",
        },
        {
            step_number = 22,
            step_type = "kill",
            description = "Kill Severilous / Hoshkar for Green Dragon Scales",
            section = "Red Scabbard",
            mob = {
                name = "Severilous / Hoshkar",
                location = {
                        zone = "Emerald Jungle / Veeshan's Peak",
                        description = "Severilous in Emerald Jungle, Hoshkar in Veeshan's Peak",
                },
            },
            loot_item = "Green Dragon Scales",
        },
        {
            step_number = 23,
            step_type = "give",
            description = "Give Totem of Fiery War, Red Dragon Scales, and Green Dragon Scales to Tenal Redblade",
            section = "Red Scabbard",
            npc = {
                name = "Tenal Redblade",
                location = {
                        zone = "East Karana",
                },
            },
            give_items = {
                "Totem of Fiery War",
                "Red Dragon Scales",
                "Green Dragon Scales",
            },
            receive_item = "Mark of the Sword",
        },
        {
            step_number = 24,
            step_type = "kill",
            description = "Kill Maestro in Plane of Hate",
            section = "Red Scabbard",
            mob = {
                name = "Maestro",
                location = {
                        zone = "Plane of Hate",
                        description = "Maestro of Rancor",
                },
                notes = "Need to loot hand, which is rare drop",
            },
            loot_item = "Hand of the Maestro",
        },
        {
            step_number = 25,
            step_type = "give",
            description = "Give Mark of the Sword and Hand of the Maestro to Tenal Redblade",
            section = "Red Scabbard",
            npc = {
                name = "Tenal Redblade",
                location = {
                        zone = "East Karana",
                },
            },
            give_items = {
                "Mark of the Sword",
                "Hand of the Maestro",
            },
            receive_item = "Tenal's note to Kargek",
        },
        {
            step_number = 26,
            step_type = "kill",
            description = "Kill Spiroc Lord in Plane of Sky",
            section = "Red Scabbard",
            mob = {
                name = "Spiroc Lord",
                location = {
                        zone = "Plane of Sky",
                        description = "Plane of Air",
                },
            },
            loot_item = "Spiroc Wingblade",
        },
        {
            step_number = 27,
            step_type = "give",
            description = "Give Tenal's note to Kargek and Spiroc Wingblade to Kargek Redblade",
            section = "Red Scabbard",
            npc = {
                name = "Kargek Redblade",
                location = {
                        zone = "East Freeport",
                },
            },
            give_items = {
                "Tenal's note to Kargek",
                "Spiroc Wingblade",
            },
            receive_item = "Red Scabbard",
        },
        {
            step_number = 28,
            step_type = "craft",
            description = "Combine both hilts and both blades in Red Scabbard",
            section = "Jagged Blade of War / Blades of Strategy and Tactics",
            receive_item = "Jagged Blade of War",
            notes = "Note: Combine Jagged Blade of War in Red Scabbard to receive Blade of Strategy and Blade of Tactics. Note: Combine Blade of Strategy and Blade of Tactics in Red Scabbard to get Jagged Blade of War again",
        },
    },
}

return warrior_epic