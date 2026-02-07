-- SHADOW_KNIGHT Epic Quest: Innoruuk's Curse
-- Auto-generated from structured quest data

local shadow_knight_epic = {
    class = "shadow_knight",
    quest_name = "Innoruuk's Curse",
    reward_item = "Innoruuk's Curse",
    start_zone = "The Overthere",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Kurron Ni",
        location = {
        zone = "The Overthere",
        description = "Overthere outpost",
        },
    },
    },
    zones = {
        "The Overthere",
        "Paineel",
        "Neriak Foreign Quarter",
        "The Hole",
        "Upper Guk",
        "Plane of Fear",
        "Plane of Sky",
        "Rathe Mountains",
        "Plane of Hate",
        "Qeynos Aqueducts",
        "City of Mist",
        "Toxxulia Forest",
        "Kerra Isle",
    },
    steps = {
        {
            step_number = 1,
            step_type = "talk",
            description = "Talk to Kurron Ni in The Overthere",
            section = "The Letter to Duriek (Optional)",
            npc = {
                name = "Kurron Ni",
                location = {
                        zone = "The Overthere",
                        description = "Overthere outpost",
                },
            },
        },
        {
            step_number = 2,
            step_type = "give",
            description = "Give Darkforge Breastplate, Darkforge Greaves, Darkforge Helm, and 900 Platinum to Kurron Ni",
            section = "The Letter to Duriek (Optional)",
            npc = {
                name = "Kurron Ni",
                location = {
                        zone = "The Overthere",
                },
            },
            give_items = {
                "Darkforge Breastplate",
                "Darkforge Greaves",
                "Darkforge Helm",
            },
            spawns_mob = "Kurron Ni (hostile)",
        },
        {
            step_number = 3,
            step_type = "kill",
            description = "Kill Kurron Ni",
            section = "The Letter to Duriek (Optional)",
            mob = {
                name = "Kurron Ni",
                level = 55,
                location = {
                        zone = "The Overthere",
                },
                notes = "Level 55 rogue. Highly resistant to immune to all spells but disease/poison DoTs and lure line. Approximate forces required: one 50+ group",
            },
            loot_item = "Letter to Duriek",
            notes = "Letter reads: 'Duriek, I have searched this godless pit for what seems to be an eternity with nothing to show for my efforts. I pray to Innoruuk that you have made some breakthrough in your research. Please update me as to your progress. In the meanwhile I have run into some unexpected expenses and will need some funds to carry on. An additional ten thousand should suffice. Regards, Karnett'",
        },
        {
            step_number = 4,
            step_type = "give",
            description = "Give Letter to Duriek to Duriek Bloodpool in Paineel",
            section = "The Dusty Tome (Optional)",
            npc = {
                name = "Duriek Bloodpool",
                location = {
                        zone = "Paineel",
                },
            },
            give_item = "Letter to Duriek",
        },
        {
            step_number = 5,
            step_type = "give",
            description = "Give 1000 Platinum to Smaka in Neriak Foreign Quarter",
            section = "The Dusty Tome (Optional)",
            npc = {
                name = "Smaka",
                location = {
                        zone = "Neriak Foreign Quarter",
                },
            },
            receive_item = "Cough Elixir",
        },
        {
            step_number = 6,
            step_type = "give",
            description = "Give Cough Elixir to Duriek Bloodpool",
            section = "The Dusty Tome (Optional)",
            npc = {
                name = "Duriek Bloodpool",
                location = {
                        zone = "Paineel",
                },
            },
            give_item = "Cough Elixir",
        },
        {
            step_number = 7,
            step_type = "kill",
            description = "Kill A Ratman Guard in The Hole",
            section = "The Dusty Tome (Optional)",
            mob = {
                name = "A Ratman Guard",
                level = 55,
                location = {
                        zone = "The Hole",
                        description = "Patrol jail area together with ratman warriors",
                },
                notes = "Level 55 warrior. Is not immune from any spells. Approximate forces required: two 50+ groups",
            },
            loot_item = "Dusty Tome",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Dusty Tome to Duriek Bloodpool",
            section = "The Dusty Tome (Optional)",
            npc = {
                name = "Duriek Bloodpool",
                location = {
                        zone = "Paineel",
                },
            },
            give_item = "Dusty Tome",
        },
        {
            step_number = 9,
            step_type = "kill",
            description = "Kill The Froglok Shin Lord in Upper Guk",
            section = "The Corrupted Ghoulbane",
            mob = {
                name = "The Froglok Shin Lord",
                location = {
                        zone = "Upper Guk",
                        description = "Ruins of Upper Guk",
                },
                notes = "Can also do via The Sword of Nobility (Ghoulbane) Quest",
            },
            loot_item = "Ghoulbane",
        },
        {
            step_number = 10,
            step_type = "kill",
            description = "Kill Cazic-Thule or Fear Golems in Plane of Fear",
            section = "The Corrupted Ghoulbane",
            mob = {
                name = "Cazic-Thule / Fright / Dread / Terror",
                location = {
                        zone = "Plane of Fear",
                },
                notes = "NOTE: Post Fear Revamp this now drops off Fear Golems (Fright, Dread, Terror). Cazic-Thule has ability to harmtouch (essentially kills anyone) anyone in zone, no matter how far they are. Pretty hard to kill unless have strong guild. Soul Leech is rare drop!",
            },
            loot_item = "Soul Leech, Dark Sword of Blood",
        },
        {
            step_number = 11,
            step_type = "kill",
            description = "Kill monsters in Plane of Sky",
            section = "The Corrupted Ghoulbane",
            mob = {
                name = "Various monsters",
                location = {
                        zone = "Plane of Sky",
                },
                notes = "Dropped by various mobs within Plane of Air",
            },
            loot_item = "Blade of Abrogation",
        },
        {
            step_number = 12,
            step_type = "kill",
            description = "Kill Rharzar in Rathe Mountains",
            section = "The Corrupted Ghoulbane - Decrepit Sheath",
            mob = {
                name = "Rharzar",
                level = 55,
                location = {
                        zone = "Rathe Mountains",
                },
                notes = "Level 55 cleric who heals himself. Need two full level 50-60 groups. Resistant to all magic based spells, so don't depend on stuns to interrupt heals, however 60 SK can land snare on him. 28.03.20 - Fairly easy solo for 60 shaman. Root/malosini/slow lands",
            },
            loot_item = "Drake Spine",
        },
        {
            step_number = 13,
            step_type = "kill",
            description = "Kill An Ashenbone Drake in Plane of Hate",
            section = "The Corrupted Ghoulbane - Decrepit Sheath",
            mob = {
                name = "An Ashenbone Drake",
                level = 51,
                location = {
                        zone = "Plane of Hate",
                },
                notes = "Level 51-53. Extremely resistant to magic. Look like miniature Dracholiche",
            },
            loot_item = "Decrepit Hide",
        },
        {
            step_number = 14,
            step_type = "craft",
            description = "Have enchanter make Enchanted Platinum Bar",
            section = "The Corrupted Ghoulbane - Decrepit Sheath",
            receive_item = "Enchanted Platinum Bar",
            notes = "Buy Platinum Bar and find enchanter to make Enchanted Platinum Bar",
        },
        {
            step_number = 15,
            step_type = "give",
            description = "Give Drake Spine, Decrepit Hide, and Enchanted Platinum Bar to Teydar in Qeynos Aqueducts",
            section = "The Corrupted Ghoulbane - Decrepit Sheath",
            npc = {
                name = "Teydar",
                location = {
                        zone = "Qeynos Aqueducts",
                        description = "Just north east of 8b on map. Evil guild area",
                },
            },
            give_items = {
                "Drake Spine",
                "Decrepit Hide",
                "Enchanted Platinum Bar",
            },
            receive_item = "Decrepit Sheath",
        },
        {
            step_number = 16,
            step_type = "give",
            description = "Give Ghoulbane, Soul Leech, Blade of Abrogation, and Decrepit Sheath to Duriek Bloodpool",
            section = "The Corrupted Ghoulbane",
            npc = {
                name = "Duriek Bloodpool",
                location = {
                        zone = "Paineel",
                },
            },
            give_items = {
                "Ghoulbane",
                "Soul Leech, Dark Sword of Blood",
                "Blade of Abrogation",
                "Decrepit Sheath",
            },
            receive_item = "Corrupted Ghoulbane",
        },
        {
            step_number = 17,
            step_type = "talk",
            description = "Talk to Knarthenne Skurl in Toxxulia Forest",
            section = "The Dark Shroud",
            npc = {
                name = "Knarthenne Skurl",
                location = {
                        zone = "Toxxulia Forest",
                        x = -5,
                        y = 1145,
                        description = "Near dock",
                },
            },
            receive_item = "Soulcase",
        },
        {
            step_number = 18,
            step_type = "talk",
            description = "OPTIONAL: Talk to Marl Kastane in Kerra Isle",
            section = "The Dark Shroud (Optional)",
            npc = {
                name = "Marl Kastane",
                location = {
                        zone = "Kerra Isle",
                        x = 115,
                        y = 2135,
                },
            },
            receive_item = "Seal of Kastane",
        },
        {
            step_number = 19,
            step_type = "give",
            description = "OPTIONAL: Give Seal of Kastane to Gerot Kastane in Paineel",
            section = "The Dark Shroud (Optional)",
            npc = {
                name = "Gerot Kastane",
                location = {
                        zone = "Paineel",
                        description = "Past elevator",
                },
            },
            give_item = "Seal of Kastane",
            receive_item = "Note to Marl",
        },
        {
            step_number = 20,
            step_type = "give",
            description = "OPTIONAL: Give Note to Marl to Marl Kastane",
            section = "The Dark Shroud (Optional)",
            npc = {
                name = "Marl Kastane",
                location = {
                        zone = "Kerra Isle",
                },
            },
            give_item = "Note to Marl",
        },
        {
            step_number = 21,
            step_type = "kill",
            description = "Kill A Mimic in The Hole",
            section = "The Dark Shroud",
            mob = {
                name = "A Mimic",
                location = {
                        zone = "The Hole",
                        description = "City section. Looks like chest",
                },
                notes = "Semi-common drop",
            },
            loot_item = "Cell Key",
        },
        {
            step_number = 22,
            step_type = "give",
            description = "Give Cell Key to Caradon in The Hole",
            section = "The Dark Shroud",
            npc = {
                name = "Caradon",
                location = {
                        zone = "The Hole",
                        description = "Jail cell",
                },
            },
            give_item = "Cell Key",
            notes = "Caradon says 'Kyrenna! We are free!' Then both attack",
        },
        {
            step_number = 23,
            step_type = "kill",
            description = "Kill Kyrenna (NOT Caradon if can be avoided)",
            section = "The Dark Shroud",
            mob = {
                name = "Kyrenna",
                level = 55,
                location = {
                        zone = "The Hole",
                },
                notes = "Level 55 cleric. Caradon is level 55 paladin. Two kill them both need two full level 50-60 groups. Caradon and Kyrenna both immune to any spells so need many tanks and many clerics (This is not true, see Wedar's Guide to The Hole for tips on fight)",
            },
        },
        {
            step_number = 24,
            step_type = "give",
            description = "Give Blood of Kyrenna to Marl Kastane",
            section = "The Dark Shroud",
            npc = {
                name = "Marl Kastane",
                location = {
                        zone = "Kerra Isle",
                },
            },
            give_item = "Blood of Kyrenna",
            receive_item = "Dark Shroud",
        },
        {
            step_number = 25,
            step_type = "give",
            description = "Give Dark Shroud to Ghost of Glohnor in The Hole",
            section = "Lhranc's Coin",
            npc = {
                name = "Ghost of Glohnor",
                location = {
                        zone = "The Hole",
                        description = "Ghost area. Rare spawn, might have to wait while",
                },
            },
            give_item = "Dark Shroud",
            spawns_mob = "Mummy of Glohnor",
        },
        {
            step_number = 26,
            step_type = "kill",
            description = "Kill Mummy of Glohnor",
            section = "Lhranc's Coin",
            mob = {
                name = "Mummy of Glohnor",
                level = 56,
                location = {
                        zone = "The Hole",
                        description = "Bottom of crypt in tower",
                },
                notes = "Level 56 warrior. Immune to all spells except Wizard Lure Spells. Need two level 50-60 groups (Single balanced group 54+ is fine, mummy hits around 288 max)",
            },
        },
        {
            step_number = 27,
            step_type = "give",
            description = "Give Head of Glohnor to Gerot Kastane",
            section = "Lhranc's Coin",
            npc = {
                name = "Gerot Kastane",
                location = {
                        zone = "Paineel",
                },
            },
            give_item = "Head of Glohnor",
            receive_item = "Head of the Valiant",
        },
        {
            step_number = 28,
            step_type = "give",
            description = "Give Glohnor Wrappings to Marl Kastane",
            section = "Lhranc's Coin",
            npc = {
                name = "Marl Kastane",
                location = {
                        zone = "Kerra Isle",
                },
            },
            give_item = "Glohnor Wrappings",
            receive_item = "Will of Innoruuk",
        },
        {
            step_number = 29,
            step_type = "craft",
            description = "Combine Heart of Kyrenna with Soulcase",
            section = "Lhranc's Coin",
            receive_item = "Heart of the Innocent",
        },
        {
            step_number = 30,
            step_type = "give",
            description = "Give Corrupted Ghoulbane, Heart of the Innocent, Head of the Valiant, and Will of Innoruuk to Lhranc in City of Mist",
            section = "Innoruuk's Curse",
            npc = {
                name = "Lhranc",
                location = {
                        zone = "City of Mist",
                        description = "Center room on other side of wall that surrounds castle moat. Ghost",
                },
            },
            give_items = {
                "Corrupted Ghoulbane",
                "Heart of the Innocent",
                "Head of the Valiant",
                "Will of Innoruuk",
            },
            receive_item = "Lhranc's Coin",
            spawns_mob = "Lhranc (hostile)",
        },
        {
            step_number = 31,
            step_type = "kill",
            description = "Kill Lhranc",
            section = "Innoruuk's Curse",
            mob = {
                name = "Lhranc",
                level = 63,
                location = {
                        zone = "City of Mist",
                },
                notes = "Level 63 Shadow Knight. Harmtouches many times during fight and has buttload of hitpoints. Impossible to mesmerize him, slow him, or any other debuffs so have many, many, many clerics ready to use all their many healing. Need around 5-6 full groups of level 50-60s. If wipe in fight, Lhranc won't despawn. Bring at least 2 groups",
            },
            loot_item = "Innoruuk's Curse",
            notes = "Upon killing Lhranc, Marl Kastane appears nearby. Says 'Alas, I cannot be one to carry sword back to my people as proof in fear they will kill me to possess it for their own. I think simple trade is in order, perhaps you have symbol or token of Lhranc's that I could take back to others to ease their worries?' Hand Lhranc's Coin to Marl Kastane. Says 'Very good, I will go deliver this right away.'",
        },
    },
}

return shadow_knight_epic