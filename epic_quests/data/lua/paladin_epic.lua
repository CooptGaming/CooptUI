-- PALADIN Epic Quest: Fiery Defender
-- Auto-generated from structured quest data

local paladin_epic = {
    class = "paladin",
    quest_name = "Fiery Defender",
    reward_item = "Fiery Defender",
    start_zone = "Plane of Fear",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Irak Altil",
        location = {
        zone = "Plane of Fear",
        description = "Wandering skeleton (once Fetid Fiend). Indifferent skeleton who wanders Plane of Fear. Has emote occasionally.",
        },
    },
    },
    zones = {
        "Plane of Fear",
        "Erudin",
        "Plane of Hate",
        "North Kaladim",
        "The Hole",
        "West Freeport",
        "Nektulos Forest",
        "Felwithe",
    },
    steps = {
        {
            step_number = 1,
            step_type = "quest",
            description = "Complete quest for The Fiery Avenger (prerequisite)",
            section = "Prerequisites",
            notes = "Must acquire Soulfire, convert it into Fiery Avenger. Includes quest for SoulFire and camping (or questing) Ghoulbane. Recommended to complete before starting epic quest.",
        },
        {
            step_number = 2,
            step_type = "talk",
            description = "Talk to Irak Altil in Plane of Fear",
            section = "Quest Start",
            npc = {
                name = "Irak Altil",
                location = {
                        zone = "Plane of Fear",
                },
            },
        },
        {
            step_number = 3,
            step_type = "kill",
            description = "Kill Thought Destroyer in Plane of Hate",
            section = "Gleaming Crested Breastplate",
            mob = {
                name = "Thought Destroyer",
                level = 55,
                location = {
                        zone = "Plane of Hate",
                        description = "Level 55 hag who randomly spawns out of corpse of A Scorn Banshee in Plane of Hate",
                },
                notes = "Random spawn",
            },
            loot_item = "Tainted Darksteel Breastplate",
        },
        {
            step_number = 4,
            step_type = "talk",
            description = "Talk to Jark in North Kaladim",
            section = "Gleaming Crested Breastplate - Pure Crystal",
            npc = {
                name = "Jark",
                location = {
                        zone = "North Kaladim",
                        description = "Mines (take right as go in, across bridge)",
                },
            },
        },
        {
            step_number = 5,
            step_type = "talk",
            description = "Talk to Nella Stonebraids in North Kaladim",
            section = "Gleaming Crested Breastplate - Pure Crystal",
            npc = {
                name = "Nella Stonebraids",
                location = {
                        zone = "North Kaladim",
                        x = 675,
                        y = 115,
                        description = "Temple area, by small pool of water across from door to cleric guild. Spawned by talking to Jark",
                },
            },
            receive_item = "Cold Plate of Beef and Bread",
        },
        {
            step_number = 6,
            step_type = "give",
            description = "Give Cold Plate of Beef and Bread to Jark",
            section = "Gleaming Crested Breastplate - Pure Crystal",
            npc = {
                name = "Jark",
                location = {
                        zone = "North Kaladim",
                },
            },
            give_item = "Cold Plate of Beef and Bread",
            receive_item = "Pure Crystal",
            notes = "Identifies as 'blessed by compassion'",
        },
        {
            step_number = 7,
            step_type = "give",
            description = "Give Tainted Darksteel Breastplate and Pure Crystal to Reklon Gnallen in Erudin",
            section = "Gleaming Crested Breastplate",
            npc = {
                name = "Reklon Gnallen",
                location = {
                        zone = "Erudin",
                        description = "Paladin on patio of paladin guild in Temple of Quellious",
                },
            },
            give_items = {
                "Tainted Darksteel Breastplate",
                "Pure Crystal",
            },
            receive_item = "Gleaming Crested Breastplate",
            notes = "Identifies as 'glowing with a bright light'",
        },
        {
            step_number = 8,
            step_type = "kill",
            description = "Kill Keeper of the Tombs in The Hole",
            section = "Gleaming Crested Sword",
            mob = {
                name = "Keeper of the Tombs",
                level = 55,
                location = {
                        zone = "The Hole",
                        description = "Ruins of Old Paineel",
                },
                spawn_time = "7-10 days long",
                notes = "Will have to do lot of waiting for this part unless lucky",
            },
            loot_item = "Tainted Darksteel Sword",
        },
        {
            step_number = 9,
            step_type = "talk",
            description = "Talk to A Peasant Woman in West Freeport",
            section = "Gleaming Crested Sword - Bucket of Pure Water",
            npc = {
                name = "A Peasant Woman",
                location = {
                        zone = "West Freeport",
                        x = -200,
                        y = -730,
                        description = "Near monk guild. Post-revamp, brother Joshua located elsewhere in West Freeport near entrance to sewers at -250, -700",
                },
            },
            receive_item = "Bucket of Water",
            notes = "Identifies as 'bucket of aqueduct water'. Peasant woman slumps to floor and begins to breathe shallowly, in short harsh gasps",
        },
        {
            step_number = 10,
            step_type = "give",
            description = "Give Bucket of Water to Joshua in West Freeport",
            section = "Gleaming Crested Sword - Bucket of Pure Water",
            npc = {
                name = "Joshua",
                location = {
                        zone = "West Freeport",
                        x = -245,
                        y = -710,
                        description = "Back of bakery. Post-revamp near entrance to sewers at -250, -700",
                },
            },
            give_item = "Bucket of Water",
            receive_item = "Bucket of Pure Water",
            notes = "Identifies as 'blessed by sacrifice'",
        },
        {
            step_number = 11,
            step_type = "give",
            description = "Give Tainted Darksteel Sword and Bucket of Pure Water to Reklon Gnallen",
            section = "Gleaming Crested Sword",
            npc = {
                name = "Reklon Gnallen",
                location = {
                        zone = "Erudin",
                },
            },
            give_items = {
                "Tainted Darksteel Sword",
                "Bucket of Pure Water",
            },
            receive_item = "Gleaming Crested Sword",
            notes = "Identifies as 'glowing with a bright light'",
        },
        {
            step_number = 12,
            step_type = "kill",
            description = "Kill Kirak Vil in Nektulos Forest",
            section = "Gleaming Crested Shield",
            mob = {
                name = "Kirak Vil",
                level = 55,
                location = {
                        zone = "Nektulos Forest",
                },
                spawn_time = "7-10 days",
                notes = "Level 55 guard. Takes many people to kill because absolutely resistant to all spells. Just need lot of tanks and lot of clerics",
            },
            loot_item = "Tainted Darksteel Shield",
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give Tainted Darksteel Shield to Elia the Pure in Felwithe",
            section = "Gleaming Crested Shield",
            npc = {
                name = "Elia the Pure",
                location = {
                        zone = "Felwithe",
                        description = "By water just before enter inner city zone",
                },
            },
            give_item = "Tainted Darksteel Shield",
            receive_item = "Gleaming Crested Shield",
            notes = "Identifies as 'glowing with a bright light'. Light of clean spirit isn't object - it's literal 'clean spirit' of Elia the Pure",
        },
        {
            step_number = 14,
            step_type = "give",
            description = "Give three Gleaming Crested items to Reklon Gnallen",
            section = "Mark of Atonement",
            npc = {
                name = "Reklon Gnallen",
                location = {
                        zone = "Erudin",
                },
            },
            give_items = {
                "Gleaming Crested Breastplate",
                "Gleaming Crested Sword",
                "Gleaming Crested Shield",
            },
            receive_item = "Mark of Atonement",
            notes = "Identifies as 'Mark of Peace'. Symbol of strength and purity refers to Fiery Avenger",
        },
        {
            step_number = 15,
            step_type = "give",
            description = "Give Mark of Atonement and Fiery Avenger to Irak Altil in Plane of Fear",
            section = "Fiery Defender",
            npc = {
                name = "Irak Altil",
                location = {
                        zone = "Plane of Fear",
                },
            },
            give_items = {
                "Mark of Atonement",
                "Fiery Avenger",
            },
            receive_item = "Fiery Defender",
        },
    },
}

return paladin_epic