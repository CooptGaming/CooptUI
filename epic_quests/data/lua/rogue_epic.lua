-- ROGUE Epic Quest: Ragebringer
-- Auto-generated from structured quest data

local rogue_epic = {
    class = "rogue",
    quest_name = "Ragebringer",
    reward_item = "Ragebringer",
    start_zone = "Qeynos Aqueducts",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Malka Rale",
        location = {
        zone = "Qeynos Aqueducts",
        x = 380,
        y = -210,
        z = -80,
        description = "In the 'Smuggler' area of the sewer. Spawns at 8PM game time, placeholder is 'a courier'",
        },
        spawn_time = "8PM game time",
        placeholder = "a courier",
    },
    },
    zones = {
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
        "Ocean of Tears",
    },
    steps = {
        {
            step_number = 1,
            step_type = "talk",
            description = "Talk to Malka Rale in Qeynos Aqueducts",
            section = "Stanos' Pouch",
            npc = {
                name = "Malka Rale",
                location = {
                        zone = "Qeynos Aqueducts",
                        x = 380,
                        y = -210,
                        z = -80,
                },
                spawn_time = "8PM game time",
                placeholder = "a courier",
            },
            receive_item = "Stanos' Pouch",
            dialogue = {
                "Say 'I can help'",
            },
            notes = "Level 50 required. Can skip this step and go directly to Anson McBale if you have high faction.",
        },
        {
            step_number = 2,
            step_type = "pickpocket",
            description = "Pickpocket Stained Parchment Top from Founy Jestands",
            section = "Stained Parchment Top",
            npc = {
                name = "Founy Jestands",
                location = {
                        zone = "North Kaladim",
                        x = 520,
                        y = 307,
                        description = "Rogue guildmaster at the bank",
                },
                spawn_time = "10AM game time",
            },
            loot_item = "Stained Parchment Top",
        },
        {
            step_number = 3,
            step_type = "pickpocket",
            description = "Pickpocket Stained Parchment Bottom from Tani N'Mar",
            section = "Stained Parchment Bottom",
            npc = {
                name = "Tani N'Mar",
                location = {
                        zone = "Neriak Third Gate",
                        x = 650,
                        y = -1300,
                        description = "Hall of the Ebon Mask (rogue's guild)",
                },
                spawn_time = "Depops at 7PM, respawns at 8PM (3 minutes after despawning)",
            },
            loot_item = "Stained Parchment Bottom",
        },
        {
            step_number = 4,
            step_type = "give",
            description = "Give both parchment pieces to Stanos Herkanor",
            section = "Combined Parchment",
            npc = {
                name = "Stanos Herkanor",
                location = {
                        zone = "Highpass Hold",
                        x = 10,
                        y = 325,
                        description = "Secret smugglers cave - jump into water near inn, swim to +10, +325, walk up narrow passage",
                },
            },
            give_items = {
                "Stained Parchment Top",
                "Stained Parchment Bottom",
            },
            receive_item = "Combined Parchment",
            notes = "Can sneak to turn in if faction is low, but be careful of Anson and Stanos facing directions",
        },
        {
            step_number = 5,
            step_type = "give",
            description = "Give Combined Parchment, 100pp, and 2 unstacked Bottles of Milk to Eldreth",
            section = "Scribbled Parchment",
            npc = {
                name = "Eldreth",
                location = {
                        zone = "Lake Rathetear",
                        x = 2600,
                        y = -550,
                        description = "Same tower as Cyanelle, at bookcase next to her",
                },
                spawn_time = "Moderately rare spawn, can take up to 8 hours real time to respawn after hand-in",
            },
            give_items = {
                "Combined Parchment",
            },
            receive_item = "Scribbled Parchment",
            notes = "Milk can be purchased from ogre vendors in zone. Must be unstacked.",
        },
        {
            step_number = 6,
            step_type = "ground_spawn",
            description = "Pick up Book of Souls in Plane of Hate",
            section = "Book of Souls",
            loot_item = "Book of Souls",
            notes = "10 hour spawn time. Wandering mobs will pick it up if not collected. Undead see through sneak/hide and normal invis.",
        },
        {
            step_number = 7,
            step_type = "give",
            description = "Give Scribbled Parchment to Yendar Starpyre",
            section = "Tattered Parchment",
            npc = {
                name = "Yendar Starpyre",
                location = {
                        zone = "Steamfont Mountains",
                        description = "Wanders the zone, easily spotted wearing SMR. Short loop path: north from druid ring, past kobold tents, east around mountain stub, southeast down road towards Watchman Halv, then back",
                },
                spawn_time = "Few hours respawn",
            },
            give_item = "Scribbled Parchment",
            receive_item = "Tattered Parchment",
            notes = "Yendar despawns after this hand-in",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Tattered Parchment and Book of Souls to Yendar Starpyre (after respawn)",
            section = "Translated Parchment and Jagged Diamond Dagger",
            npc = {
                name = "Yendar Starpyre",
                location = {
                        zone = "Steamfont Mountains",
                },
            },
            give_items = {
                "Tattered Parchment",
                "Book of Souls",
            },
            notes = "Yendar despawns and Renux spawns in his place",
            spawns_mob = "Renux Herkanor",
        },
        {
            step_number = 9,
            step_type = "kill",
            description = "Kill Renux Herkanor",
            section = "Renux Herkanor",
            mob = {
                name = "Renux Herkanor",
                level = 50,
                location = {
                        zone = "Steamfont Mountains",
                },
                notes = "Level 50 human rogue. Quad hits for 200, backstab for 200+. Casts clockwork poison (spinning stun). Does not attack pets. Can be feared and snared. Best strategy: pet kiting with fear. Can be duo'd by rogue if agro kited by caster.",
            },
            notes = "Renux is Stanos' daughter. She will not attack until provoked. Can be duo'd if agro kited properly.",
        },
        {
            step_number = 10,
            step_type = "give",
            description = "Give Translated Parchment to Stanos Herkanor",
            section = "Sealed Box",
            npc = {
                name = "Stanos Herkanor",
                location = {
                        zone = "Highpass Hold",
                        x = 10,
                        y = 325,
                },
            },
            give_item = "Translated Parchment",
            receive_item = "Sealed Box",
        },
        {
            step_number = 11,
            step_type = "give",
            description = "Give Sealed Box to any dark elf in Kithicor Forest (at night)",
            section = "General's Pouch",
            npc = {
                name = "Dark Elf (any)",
                location = {
                        zone = "Kithicor Forest",
                        x = 800,
                        y = 2400,
                        description = "Burned-out cabin during game night",
                },
            },
            give_item = "Sealed Box",
            spawns_mob = "General V'Ghera",
        },
        {
            step_number = 12,
            step_type = "kill",
            description = "Kill General V'Ghera",
            section = "General V'Ghera",
            mob = {
                name = "General V'Ghera",
                level = 60,
                location = {
                        zone = "Kithicor Forest",
                },
                notes = "Very hard level 60 being. Quad attacks for 275 quickly. Has 1500pt harm touch. Casts soul devour. Can summon mobs from zone to assist. Weak to: Wizard Lure Line, Poison Spells, Scent Line, Fire Based Spells. Extremely strong against magic based spells.",
            },
            notes = "Cazic Quill is rare drop. If not obtained, must complete sub-quest.",
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give General's Pouch, Cazic Quill, and Jagged Diamond Dagger to Stanos Herkanor",
            section = "Ragebringer",
            npc = {
                name = "Stanos Herkanor",
                location = {
                        zone = "Highpass Hold",
                        x = 10,
                        y = 325,
                },
            },
            give_items = {
                "General's Pouch",
                "Cazic Quill",
                "Jagged Diamond Dagger",
            },
            receive_item = "Ragebringer",
        },
    },
}

return rogue_epic