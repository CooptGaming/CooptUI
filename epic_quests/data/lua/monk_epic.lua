-- MONK Epic Quest: Celestial Fists
-- Auto-generated from structured quest data

local monk_epic = {
    class = "monk",
    quest_name = "Celestial Fists",
    reward_item = "Celestial Fists",
    start_zone = "Erudin",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Tomekeeper Danl",
        location = {
        zone = "Erudin",
        description = "Second floor of library (three story building in center of Erudin's courtyard nearest Tox forest)",
        },
    },
    },
    zones = {
        "Erudin",
        "Skyfire",
        "Timorous Deep",
        "Southern Karana",
        "Rathe Mountains",
        "Nagafen's Lair",
        "Lower Guk",
        "Dreadlands",
        "Chardok",
        "Karnor's Castle",
        "Trakanon's Teeth",
        "Lavastorm Mountains",
        "Plane of Sky",
        "Mines of Nurga",
        "Lake Rathetear",
        "The Overthere",
        "Lake of Ill Omen",
    },
    steps = {
        {
            step_number = 1,
            step_type = "kill",
            description = "Kill any named mob in Skyfire to get Immortals book",
            section = "First Book",
            mob = {
                name = "Guardian of Felia / A Lava Walker / A Wandering Wurm / Black Scar",
                location = {
                        zone = "Skyfire",
                },
            },
            loot_item = "Immortals",
        },
        {
            step_number = 2,
            step_type = "give",
            description = "Give Immortals to Tomekeeper Danl in Erudin",
            section = "First Book",
            npc = {
                name = "Tomekeeper Danl",
                location = {
                        zone = "Erudin",
                        description = "Second floor of library",
                },
            },
            give_item = "Immortals",
            receive_item = "Danl's Reference",
        },
        {
            step_number = 3,
            step_type = "quest",
            description = "Complete Monk Sash Quests to obtain Red Sash of Order",
            section = "Robe of the Lost Circle - Prerequisites",
            receive_item = "Red Sash of Order",
            notes = "Must complete before Robe of the Lost Circle sub-quest",
        },
        {
            step_number = 4,
            step_type = "quest",
            description = "Complete Monk Headband Quests to obtain Purple Headband",
            section = "Robe of the Lost Circle - Prerequisites",
            receive_item = "Purple Headband",
            notes = "Must complete before Robe of the Lost Circle sub-quest",
        },
        {
            step_number = 5,
            step_type = "kill",
            description = "Kill Targin the Rock in Nagafen's Lair",
            section = "Robe of the Lost Circle",
            mob = {
                name = "Targin the Rock",
                location = {
                        zone = "Nagafen's Lair",
                        description = "King room",
                },
            },
            loot_item = "Code of Zan Fi",
        },
        {
            step_number = 6,
            step_type = "kill",
            description = "Kill Raster of Guk in Lower Guk",
            section = "Robe of the Lost Circle",
            mob = {
                name = "Raster of Guk",
                location = {
                        zone = "Lower Guk",
                },
                notes = "Cannot MQ the idol and sash to Brother Zephyl",
            },
            loot_item = "The Idol",
        },
        {
            step_number = 7,
            step_type = "give",
            description = "Give Purple Headband and Code of Zan Fi to Brother Qwinn in Southern Karana",
            section = "Robe of the Lost Circle",
            npc = {
                name = "Brother Qwinn",
                location = {
                        zone = "Southern Karana",
                },
            },
            give_items = {
                "Purple Headband",
                "Code of Zan Fi",
            },
            receive_item = "Needle of the Void",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Red Sash of Order and The Idol to Brother Zephyl in Rathe Mountains",
            section = "Robe of the Lost Circle",
            npc = {
                name = "Brother Zephyl",
                location = {
                        zone = "Rathe Mountains",
                },
            },
            give_items = {
                "Red Sash of Order",
                "The Idol",
            },
            receive_item = "Rare Robe Pattern",
        },
        {
            step_number = 9,
            step_type = "craft",
            description = "Combine Shadow Wolf Pelt, Silk Swatch, and Spell: Gather Shadows in sewing kit",
            section = "Robe of the Lost Circle",
            receive_item = "Shadow Silk",
        },
        {
            step_number = 10,
            step_type = "craft",
            description = "Combine Shadow Silk, Needle of the Void, Rare Robe Pattern, and Song: Jonthan's Whistling Warsong in sewing kit",
            section = "Robe of the Lost Circle",
            receive_item = "Robe of the Lost Circle",
            notes = "Jan 2024 Edit - Apparent trivial of 64. Nov 2020 edit - now requires skillcheck over 48 Tailoring, but under 64. (June 15, 2000) Skill in tailoring is no longer required to craft.",
        },
        {
            step_number = 11,
            step_type = "kill",
            description = "Kill An Iksar Betrayer in Chardok",
            section = "Robe of the Whistling Fists",
            mob = {
                name = "An Iksar Betrayer",
                location = {
                        zone = "Chardok",
                },
            },
            loot_item = "A Metal Pipe (Fi)",
        },
        {
            step_number = 12,
            step_type = "kill",
            description = "Kill A Drolvarg Pawbuster in Karnor's Castle",
            section = "Robe of the Whistling Fists",
            mob = {
                name = "A Drolvarg Pawbuster",
                location = {
                        zone = "Karnor's Castle",
                },
            },
            loot_item = "A Metal Pipe (Zan)",
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give two pipes and Robe of the Lost Circle to Brother Balatin in Dreadlands",
            section = "Robe of the Whistling Fists",
            npc = {
                name = "Brother Balatin",
                location = {
                        zone = "Dreadlands",
                },
            },
            give_items = {
                "A Metal Pipe (Fi)",
                "A Metal Pipe (Zan)",
                "Robe of the Lost Circle",
            },
            receive_item = "Robe of the Whistling Fists",
        },
        {
            step_number = 14,
            step_type = "give",
            description = "Give Danl's Reference and Robe of the Whistling Fists to Lheao in Timorous Deep",
            section = "Celestial Fists Book",
            npc = {
                name = "Lheao",
                location = {
                        zone = "Timorous Deep",
                        description = "Hidden cove in hidden oasis",
                },
            },
            give_items = {
                "Danl's Reference",
                "Robe of the Whistling Fists",
            },
            receive_item = "Celestial Fists (book)",
            notes = "The Celestial Fists Book is illegible",
        },
        {
            step_number = 15,
            step_type = "talk",
            description = "Find A Fire Sprite in Lavastorm Mountains and say challenge phrase",
            section = "Fist of Fire",
            npc = {
                name = "A Fire Sprite",
                location = {
                        zone = "Lavastorm Mountains",
                },
            },
            spawns_mob = "Eejag",
        },
        {
            step_number = 16,
            step_type = "kill",
            description = "Kill Eejag in Lavastorm Mountains",
            section = "Fist of Fire",
            mob = {
                name = "Eejag",
                location = {
                        zone = "Lavastorm Mountains",
                        description = "Fire pit by entrances to Sol A and Sol B. Under middle smoke plume, about half way down. Iksar swimming in lava. Cannot be pulled - must fight where he is, in the lava.",
                },
                notes = "Eejag shouts: 'What imbecile dares challenges a Celestial Fist?! Do you even know who you are challenging? HA! You are nothing but an insect! I will enjoy crushing you, I have not charred the flesh of an idiot in decades! If you truly wish to fight me, the battle shall be held in my own element. Come, challenger, come down to the pits of flowing fire.'",
            },
            loot_item = "Charred Scale",
        },
        {
            step_number = 17,
            step_type = "give",
            description = "Give Charred Scale to A Presence on Dojorn's Island (Isle 1.5) in Plane of Sky",
            section = "Fist of Air",
            npc = {
                name = "A Presence",
                location = {
                        zone = "Plane of Sky",
                        description = "Noble Dojorn's island. In form of shadowman so only name is visible.",
                },
            },
            give_item = "Charred Scale",
            spawns_mob = "Gwan",
        },
        {
            step_number = 18,
            step_type = "kill",
            description = "Kill Gwan",
            section = "Fist of Air",
            mob = {
                name = "Gwan",
                location = {
                        zone = "Plane of Sky",
                        description = "Noble Dojorn's island",
                },
            },
            loot_item = "Breath of Gwan",
        },
        {
            step_number = 19,
            step_type = "give",
            description = "Give Breath of Gwan to A Sleeping Ogre in Mines of Nurga",
            section = "Fist of Earth",
            npc = {
                name = "A Sleeping Ogre",
                location = {
                        zone = "Mines of Nurga",
                },
            },
            give_item = "Breath of Gwan",
            spawns_mob = "Trunt",
        },
        {
            step_number = 20,
            step_type = "kill",
            description = "Kill Trunt",
            section = "Fist of Earth",
            mob = {
                name = "Trunt",
                level = 59,
                location = {
                        zone = "Mines of Nurga",
                },
                notes = "59th level KOS ogre. Immune to magic. Tougher fight than previous ones.",
            },
            loot_item = "Trunt's Head",
        },
        {
            step_number = 21,
            step_type = "give",
            description = "OPTIONAL: Give Trunt's Head to Deep in Lake Rathetear",
            section = "Fist of Water - Optional",
            npc = {
                name = "Deep",
                location = {
                        zone = "Lake Rathetear",
                        description = "Underwater caverns, dark elf named Deep who lives in lake",
                },
            },
            give_item = "Trunt's Head",
            receive_item = "Trunt's Head",
            notes = "OPTIONAL step - Deep despawns immediately",
        },
        {
            step_number = 22,
            step_type = "give",
            description = "Give Trunt's Head to Astral Projection (Overthere)",
            section = "Fist of Water",
            npc = {
                name = "Astral Projection (Overthere)",
                location = {
                        zone = "The Overthere",
                        x = 700,
                        y = 800,
                        description = "Bottom of scorpion chasm. Does not need to be fought.",
                },
            },
            give_item = "Trunt's Head",
            receive_item = "Eye of Kaiaren",
            notes = "Astral Projection despawns after giving Eye of Kaiaren",
        },
        {
            step_number = 23,
            step_type = "give",
            description = "Give Eye of Kaiaren to Astral Projection (LOIO) in Lake of Ill Omen",
            section = "Fist of Water",
            npc = {
                name = "Astral Projection (LOIO)",
                location = {
                        zone = "Lake of Ill Omen",
                        x = -1900,
                        y = -950,
                        description = "Along shore of lake between Windmill and Frontier Mountains zone. Not on platform, but on shore",
                },
            },
            give_item = "Eye of Kaiaren",
            notes = "Astral Projection despawns. Deep and Vorash both spawn, very much KOS. Deep procs Fist of Water, hits for 170ish. Vorash procs Fist of Mastery (DD and stun), hits around same as Deep. Both have no items.",
        },
        {
            step_number = 24,
            step_type = "kill",
            description = "Kill Vorash",
            section = "Fist of Water",
            mob = {
                name = "Vorash",
                location = {
                        zone = "Lake of Ill Omen",
                },
                notes = "Once killed, Vorash says: 'Foolish mortal! You think you have defeated me? Now, witness the true power of Rallos Zek!' Xenevorash will then spawn on platform, regardless of where Vorash dies.",
            },
            spawns_mob = "Xenevorash",
        },
        {
            step_number = 25,
            step_type = "kill",
            description = "Kill Xenevorash",
            section = "Fist of Water",
            mob = {
                name = "Xenevorash",
                location = {
                        zone = "Lake of Ill Omen",
                        description = "Spawns on platform regardless of where Vorash dies",
                },
                notes = "Procs Fist of Sentience which is 500DD and stun, hits for 250. Death message: Xenevorash's corpse shouts 'Grraaaagghhhh!! NOT.. POSSIBLE!'",
            },
            loot_item = "Demon Fangs",
        },
        {
            step_number = 26,
            step_type = "give",
            description = "Give Celestial Fists (book) to mad Kaiaren in Trakanon's Teeth",
            section = "Book Conversion",
            npc = {
                name = "Kaiaren (mad)",
                location = {
                        zone = "Trakanon's Teeth",
                        x = -1609,
                        y = -2679,
                        description = "Undead ruins near Sebilis",
                },
            },
            give_item = "Celestial Fists (book)",
            receive_item = "Celestial Fists (book)",
        },
        {
            step_number = 27,
            step_type = "give",
            description = "Give Celestial Fists (book) to sane Kaiaren",
            section = "Book Conversion",
            npc = {
                name = "Kaiaren (sane)",
                location = {
                        zone = "Trakanon's Teeth",
                        x = 305,
                        y = 2470,
                        description = "Spawns over by lake in empty hut after handing book to mad Kaiaren. Indifferent to all.",
                },
            },
            give_item = "Celestial Fists (book)",
            receive_item = "Book of Celestial Fists",
        },
        {
            step_number = 28,
            step_type = "give",
            description = "Give Book of Celestial Fists and Demon Fangs to sane Kaiaren",
            section = "Final Turn-in",
            npc = {
                name = "Kaiaren (sane)",
                location = {
                        zone = "Trakanon's Teeth",
                        x = 305,
                        y = 2470,
                },
            },
            give_items = {
                "Book of Celestial Fists",
                "Demon Fangs",
            },
            receive_item = "Celestial Fists",
        },
    },
}

return monk_epic