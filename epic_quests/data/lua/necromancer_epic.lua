-- NECROMANCER Epic Quest: Scythe of the Shadowed Soul
-- Auto-generated from structured quest data

local necromancer_epic = {
    class = "necromancer",
    quest_name = "Scythe of the Shadowed Soul",
    reward_item = "Scythe of the Shadowed Soul",
    start_zone = "Nektulos Forest",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Venenzi Oberzendi",
        location = {
        zone = "Nektulos Forest",
        x = -1070,
        y = -700,
        description = "Post-post-revamp location",
        },
    },
    },
    zones = {
        "Nektulos Forest",
        "Lake Rathetear",
        "East Freeport",
        "Najena",
        "Swamp of No Hope",
        "Chardok",
        "Timorous Deep",
        "Plane of Sky",
        "Plane of Hate",
        "Plane of Fear",
    },
    steps = {
        {
            step_number = 1,
            step_type = "talk",
            description = "Talk to Kazen Fecae in Lake Rathetear",
            section = "Symbol of the Apprentice",
            npc = {
                name = "Kazen Fecae",
                location = {
                        zone = "Lake Rathetear",
                        x = 340,
                        y = -1600,
                },
            },
        },
        {
            step_number = 2,
            step_type = "kill",
            description = "Kill Sir Edwin Motte",
            section = "Symbol of the Apprentice",
            mob = {
                name = "Sir Edwin Motte",
                level = 33,
                location = {
                        zone = "East Freeport",
                        description = "Docks in East Freeport. Spawns fairly frequently in inn. Easiest to catch here. Part of rotation with Tumpy, Groflah, and barbarian in leather. Found in 4 places throughout Norrath.",
                },
                notes = "Only level 33, should be easy to dispose of",
            },
            loot_item = "Head of Sir Edwin Motte",
        },
        {
            step_number = 3,
            step_type = "give",
            description = "Give Head to Kazen Fecae",
            section = "Symbol of the Apprentice",
            npc = {
                name = "Kazen Fecae",
                location = {
                        zone = "Lake Rathetear",
                        x = 340,
                        y = -1600,
                },
            },
            give_item = "Head of Sir Edwin Motte",
            receive_item = "Symbol of the Apprentice",
        },
        {
            step_number = 4,
            step_type = "give",
            description = "Give Symbol of the Apprentice to Venenzi Oberzendi in Nektulos Forest",
            section = "Symbol of the Serpent",
            npc = {
                name = "Venenzi Oberzendi",
                location = {
                        zone = "Nektulos Forest",
                        x = -1000,
                        y = -700,
                },
            },
            give_item = "Symbol of the Apprentice",
            receive_item = "Twisted Symbol of the Apprentice",
        },
        {
            step_number = 5,
            step_type = "kill",
            description = "Kill Najena (NPC) in Najena",
            section = "Symbol of the Serpent",
            mob = {
                name = "Najena (NPC)",
                location = {
                        zone = "Najena",
                },
                notes = "Fairly common drop. Alternatively can try to buy one from auction zone on server",
            },
            loot_item = "Flowing Black Robe",
        },
        {
            step_number = 6,
            step_type = "give",
            description = "Give Flowing Black Robe to Venenzi Oberzendi",
            section = "Symbol of the Serpent",
            npc = {
                name = "Venenzi Oberzendi",
                location = {
                        zone = "Nektulos Forest",
                        x = -1000,
                        y = -700,
                },
            },
            give_item = "Flowing Black Robe",
            receive_item = "Rolling Stone Moss",
        },
        {
            step_number = 7,
            step_type = "give",
            description = "Give Twisted Symbol of the Apprentice and Rolling Stone Moss to Emkel Kabae in Lake Rathetear",
            section = "Symbol of the Serpent",
            npc = {
                name = "Emkel Kabae",
                location = {
                        zone = "Lake Rathetear",
                        description = "By stone skeleton tower. Fazen's Apprentice",
                },
            },
            give_items = {
                "Twisted Symbol of the Apprentice",
                "Rolling Stone Moss",
            },
            receive_item = "Symbol of the Serpent",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Symbol of the Serpent to Ssessthrass in Swamp of No Hope",
            section = "Symbol of Testing",
            npc = {
                name = "Ssessthrass",
                location = {
                        zone = "Swamp of No Hope",
                        x = 3800,
                        y = 1600,
                        description = "In house in pass to go to Field of Bone. Named iksar herbalist",
                },
            },
            give_item = "Symbol of the Serpent",
            receive_item = "Scaled Symbol of the Serpent",
        },
        {
            step_number = 9,
            step_type = "kill",
            description = "Kill Grand Herbalist Mak'ha or Royal Sarnak Herbalist in Chardok",
            section = "Symbol of Testing",
            mob = {
                name = "Grand Herbalist Mak'ha / Royal Sarnak Herbalist",
                location = {
                        zone = "Chardok",
                        description = "Herb House in mines. Located North of Chardok Bank, behind waterfall and small stream. Alternately reached from Bridge Keeper or 'Ledge path' as descend into mines. 'A Dizok Herbalist' is placeholder for Grand Herbalist, always spawns in Herb House, guarded by many Chokidai and Apprentice Herbalists.",
                },
                notes = "Need 1-2 groups of level 54+. Grand Herbalist does not drop Manisi Herb every time - uncommon, possibly rare drop. Herb can be MQ'd, confirmed as of 5/1/22",
            },
            loot_item = "Manisi Herb",
        },
        {
            step_number = 10,
            step_type = "give",
            description = "Give Manisi Herb and Scaled Symbol of the Serpent to Ssessthrass",
            section = "Symbol of Testing",
            npc = {
                name = "Ssessthrass",
                location = {
                        zone = "Swamp of No Hope",
                        x = 3800,
                        y = 1600,
                },
            },
            give_items = {
                "Manisi Herb",
                "Scaled Symbol of the Serpent",
            },
            receive_item = "Refined Manisi Herb",
        },
        {
            step_number = 11,
            step_type = "give",
            description = "Give Refined Manisi Herb to Emkel Kabae",
            section = "Symbol of Testing",
            npc = {
                name = "Emkel Kabae",
                location = {
                        zone = "Lake Rathetear",
                },
            },
            give_item = "Refined Manisi Herb",
            receive_item = "Symbol of Testing",
        },
        {
            step_number = 12,
            step_type = "talk",
            description = "Tell Kazen Fecae about Symbol of Testing",
            section = "Symbol of Insanity",
            npc = {
                name = "Kazen Fecae",
                location = {
                        zone = "Lake Rathetear",
                        x = 340,
                        y = -1600,
                },
            },
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give Symbol of Testing to Kazen Fecae",
            section = "Symbol of Insanity",
            npc = {
                name = "Kazen Fecae",
                location = {
                        zone = "Lake Rathetear",
                        x = 340,
                        y = -1600,
                },
            },
            give_item = "Symbol of Testing",
        },
        {
            step_number = 14,
            step_type = "kill",
            description = "Kill A Bone Golem",
            section = "Symbol of Insanity",
            mob = {
                name = "A Bone Golem",
                level = 55,
                location = {
                        zone = "Lake Rathetear",
                        description = "Little inlet east of Emkel",
                },
                notes = "Spawns first",
            },
        },
        {
            step_number = 15,
            step_type = "kill",
            description = "Kill A Failed Apprentice",
            section = "Symbol of Insanity",
            mob = {
                name = "A Failed Apprentice",
                level = 53,
                location = {
                        zone = "Lake Rathetear",
                        description = "Little inlet east of Emkel",
                },
                notes = "Spawns second, blue to 53",
            },
        },
        {
            step_number = 16,
            step_type = "kill",
            description = "Kill A Tortured Soul",
            section = "Symbol of Insanity",
            mob = {
                name = "A Tortured Soul",
                level = 55,
                location = {
                        zone = "Lake Rathetear",
                        description = "Little inlet east of Emkel",
                },
                notes = "Spawns third. Both Bone Golem and Tortured Soul level 55. Hit for ~120, not overly difficult",
            },
            loot_item = "Symbol of Insanity",
        },
        {
            step_number = 17,
            step_type = "give",
            description = "Give Symbol of Insanity to Drendico Metalbones in Timorous Deep",
            section = "Gzallk in a Box",
            npc = {
                name = "Drendico Metalbones",
                location = {
                        zone = "Timorous Deep",
                        x = 6485,
                        y = 3829,
                        description = "Near dock that takes you to Overthere. Turn right from docks and climb onto stoney hill, see little gnome wandering around",
                },
            },
            give_item = "Symbol of Insanity",
            receive_item = "Journal",
        },
        {
            step_number = 18,
            step_type = "talk",
            description = "Speak to Jzil GSix in Plane of Sky",
            section = "Gzallk in a Box - Cloak of Spiroc Feathers",
            npc = {
                name = "Jzil GSix",
                location = {
                        zone = "Plane of Sky",
                        description = "Quest Room (use Key of Veeshan on portal pad to port into room)",
                },
            },
        },
        {
            step_number = 19,
            step_type = "kill",
            description = "Kill An azarack and other second isle monsters in Plane of Sky",
            section = "Gzallk in a Box - Cloak of Spiroc Feathers",
            mob = {
                name = "An azarack / other second isle monsters",
                location = {
                        zone = "Plane of Sky",
                        description = "Second isle",
                },
                notes = "Most commonly dropped off Azeracks",
            },
            loot_item = "Silver Disc",
        },
        {
            step_number = 20,
            step_type = "kill",
            description = "Kill A gorgalask and other third isle monsters in Plane of Sky",
            section = "Gzallk in a Box - Cloak of Spiroc Feathers",
            mob = {
                name = "A gorgalask / other third isle monsters",
                location = {
                        zone = "Plane of Sky",
                        description = "Third isle",
                },
                notes = "Spiroc Feathers dropped from Watchful Guardian on third isle. Level 53-55",
            },
            loot_item = "Spiroc Feathers",
        },
        {
            step_number = 21,
            step_type = "kill",
            description = "Kill Keeper of Souls in Plane of Sky",
            section = "Gzallk in a Box - Cloak of Spiroc Feathers",
            mob = {
                name = "Keeper of Souls",
                level = 60,
                location = {
                        zone = "Plane of Sky",
                        description = "Boss of fourth island",
                },
                notes = "60th level mob that death touches every 30 seconds. Hits for max 400. Cape does not drop every time. Bring many friends to kill him",
            },
            loot_item = "Black Silk Cape",
        },
        {
            step_number = 22,
            step_type = "give",
            description = "Give Silver Disc, Spiroc Feathers, and Black Silk Cape to Jzil GSix",
            section = "Gzallk in a Box - Cloak of Spiroc Feathers",
            npc = {
                name = "Jzil GSix",
                location = {
                        zone = "Plane of Sky",
                },
            },
            give_items = {
                "Silver Disc",
                "Spiroc Feathers",
                "Black Silk Cape",
            },
            receive_item = "Cloak of Spiroc Feathers",
        },
        {
            step_number = 23,
            step_type = "kill",
            description = "Kill Mini-Bosses (formerly Innoruuk) from Plane of Hate",
            section = "Gzallk in a Box",
            mob = {
                name = "Mini-Bosses / Lord of Ire / Lord of Loathing / Master of Spite",
                location = {
                        zone = "Plane of Hate",
                        description = "Post-revamp only. Eye of Innoruuk drops from Innoruuk minibosses",
                },
                notes = "Post-revamp only",
            },
            loot_item = "Eye of Innoruuk",
        },
        {
            step_number = 24,
            step_type = "kill",
            description = "Kill Cazic Thule (God) or golems from Plane of Fear",
            section = "Gzallk in a Box",
            mob = {
                name = "Cazic Thule (God) / Fright / Dread / Terror",
                level = 60,
                location = {
                        zone = "Plane of Fear",
                },
                notes = "Level 60. Said to be second hardest creatures in Plane of Fear. Needless to say want to bring few friends for this fight",
            },
            loot_item = "Slime Blood of Cazic Thule",
        },
        {
            step_number = 25,
            step_type = "give",
            description = "Give Cloak of Spiroc Feathers, Eye of Innoruuk, Slime Blood of Cazic Thule, and Journal to Drendico Metalbones",
            section = "Gzallk in a Box",
            npc = {
                name = "Drendico Metalbones",
                location = {
                        zone = "Timorous Deep",
                        x = 6485,
                        y = 3829,
                },
            },
            give_items = {
                "Cloak of Spiroc Feathers",
                "Eye of Innoruuk",
                "Slime Blood of Cazic Thule",
                "Journal",
            },
            receive_item = "Prepared Regents Box",
        },
        {
            step_number = 26,
            step_type = "give",
            description = "Give Prepared Regents Box to Kazen Fecae",
            section = "Gzallk in a Box",
            npc = {
                name = "Kazen Fecae",
                location = {
                        zone = "Lake Rathetear",
                        x = 340,
                        y = -1600,
                },
            },
            give_item = "Prepared Regents Box",
            receive_item = "Tome of Instruction",
        },
        {
            step_number = 27,
            step_type = "give",
            description = "Give 10 gold pieces to Thunder Spirit Princess in Plane of Sky",
            section = "Gzallk in a Box",
            npc = {
                name = "A Thunder Spirit Princess",
                location = {
                        zone = "Plane of Sky",
                        description = "Port-up isle (first island)",
                },
            },
        },
        {
            step_number = 28,
            step_type = "give",
            description = "Give Tome of Instruction to Gkzzallk in Plane of Sky",
            section = "Gzallk in a Box",
            npc = {
                name = "Gkzzallk",
                location = {
                        zone = "Plane of Sky",
                        description = "Third isle, in windmill on Island 3",
                },
            },
            give_item = "Tome of Instruction",
            receive_item = "Gkzzallk in a Box",
        },
        {
            step_number = 29,
            step_type = "give",
            description = "Give Gkzzallk in a Box to Kazen Fecae",
            section = "Scythe of the Shadowed Soul",
            npc = {
                name = "Kazen Fecae",
                location = {
                        zone = "Lake Rathetear",
                        x = 340,
                        y = -1600,
                },
            },
            give_item = "Gkzzallk in a Box",
            receive_item = "Scythe of the Shadowed Soul",
        },
    },
}

return necromancer_epic