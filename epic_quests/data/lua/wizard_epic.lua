-- WIZARD Epic Quest: Staff of the Four
-- Auto-generated from structured quest data

local wizard_epic = {
    class = "wizard",
    quest_name = "Staff of the Four",
    reward_item = "Staff of the Four",
    start_zone = "Temple of Solusek Ro",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "Solomen",
        location = {
        zone = "Temple of Solusek Ro",
        x = 425,
        y = 80,
        z = 29,
        description = "Left side of temple between two undead knights (one room from Lord Searfire). Entrance is in Lavastorm location +800, +228",
        },
    },
    },
    zones = {
        "Temple of Solusek Ro",
        "Erudin",
        "Halas",
        "Felwithe",
        "Kedge Keep",
        "Karnor's Castle",
        "Butcherblock Mountains",
        "Plane of Fear",
        "Old Sebilis",
    },
    steps = {
        {
            step_number = 1,
            step_type = "talk",
            description = "Talk to Solomen in Temple of Solusek Ro",
            section = "The Beginning (Optional)",
            npc = {
                name = "Solomen",
                location = {
                        zone = "Temple of Solusek Ro",
                        x = 425,
                        y = 80,
                        z = 29,
                },
            },
            receive_item = "Note to Camin",
            notes = "OPTIONAL - this exact step is not absolutely required. Identifies as 'I've found what we've been searching for!' Reads: 'Hello, old friend, I have made updated list and locations of items required for my research. Dragon bones- Plane of Fear Jet Black egg- Unknown Mistletoe powder- Old Sebilis Rune of Lost Thought- Unknown Contact me when you find them Solomen'",
        },
        {
            step_number = 2,
            step_type = "give",
            description = "Give Note to Camin to Camin in Erudin",
            section = "The Beginning (Optional)",
            npc = {
                name = "Camin",
                location = {
                        zone = "Erudin",
                        description = "Vasty Deep Inn. To find him, simply open front door and go up stairs to right. Go down hall and open first door on left. Camin will be behind door. On Truespirit faction (similar to Beta Neutral - no faction for killing him and starts non-KOS to all)",
                },
            },
            give_item = "Note to Camin",
        },
        {
            step_number = 3,
            step_type = "give",
            description = "Give 1000 Platinum to Camin",
            section = "The Beginning (Optional)",
            npc = {
                name = "Camin",
                location = {
                        zone = "Erudin",
                },
            },
        },
        {
            step_number = 4,
            step_type = "purchase",
            description = "Purchase Ro's Breath from Dargon in Halas",
            section = "Arantir Karondor",
            npc = {
                name = "Dargon",
                location = {
                        zone = "Halas",
                        x = 350,
                        y = 357,
                        description = "Female NPC vendor in front of Shaman guild",
                },
            },
            item = "Ro's Breath",
        },
        {
            step_number = 5,
            step_type = "give",
            description = "Give Ro's Breath to Camin",
            section = "Arantir Karondor",
            npc = {
                name = "Camin",
                location = {
                        zone = "Erudin",
                },
            },
            give_item = "Ro's Breath",
            receive_item = "Ro's Breath (used)",
        },
        {
            step_number = 6,
            step_type = "give",
            description = "Give used Ro's Breath to Dargon",
            section = "Arantir Karondor",
            npc = {
                name = "Dargon",
                location = {
                        zone = "Halas",
                        x = 350,
                        y = 357,
                },
            },
            give_item = "Ro's Breath (used)",
        },
        {
            step_number = 7,
            step_type = "talk",
            description = "Hail Arantir Karondor",
            section = "Arantir's Ring",
            npc = {
                name = "Arantir Karondor",
                location = {
                        zone = "Halas",
                        x = 350,
                        y = 357,
                },
            },
            receive_item = "Arantir's Ring",
            notes = "Actually ring called Arantir's Ring. Identifying it reveals: 'Item Lore: My love has no bounds.'",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Arantir's Ring to Challice in Felwithe",
            section = "Arantir's Ring",
            npc = {
                name = "Challice",
                location = {
                        zone = "Felwithe",
                        x = -13,
                        y = -263,
                        description = "Basement of Paladin Guild",
                },
            },
            give_item = "Arantir's Ring",
            receive_item = "Ring (returned)",
            notes = "Gets different version of ring back (identifies as 'I never could love man like you.'). Can hand it to either version of Arantir. Handing it into Dargon will spawn real version",
        },
        {
            step_number = 9,
            step_type = "give",
            description = "Give returned ring to Dargon/Arantir Karondor",
            section = "Arantir's Ring",
            npc = {
                name = "Dargon / Arantir Karondor",
                location = {
                        zone = "Halas",
                        x = 350,
                        y = 357,
                },
            },
            give_item = "Ring (returned)",
            receive_item = "Note from Arantir",
            notes = "Says 'Talk to him of other wizards and receive Note from Arantir. (Say 'Who is the gnome?' to skip to end of conversation)'",
        },
        {
            step_number = 10,
            step_type = "kill",
            description = "Kill Phinigel Autropos in Kedge Keep",
            section = "Sylen Tyrn - Blue Crystal Staff",
            mob = {
                name = "Phinigel Autropos",
                level = 50,
                location = {
                        zone = "Kedge Keep",
                },
                spawn_time = "Every 12 hours",
                notes = "Level 50 Wizard. Actually quite easy to kill. If have support, this part isn't hard to do. Surrounded by guards, that can be solo pulled by 60. Phinny can be done with one well structured group of level 58s plus. There are many tactics to killing Phinny. Most used and most reliable is single pulling guardians fast. They repop every 20 minutes so if don't go fast enough, will have to start over. Once dispatched, pull Phinny. He himself isn't very hard to kill. Helps to have someone to slow. If doing this with one group, need shaman, enchanter, warrior, cleric, yourself, and preferably damage meleer such as monk, rogue, or ranger. Trace of Sylen Tyrn can be found on Phinigel Autropos. Blue Crystal Staff is what need. It's one of Phinigel's rare drops so in for 'fun' camp",
            },
            loot_item = "Blue Crystal Staff",
        },
        {
            step_number = 11,
            step_type = "kill",
            description = "Kill Venril Sathir in Karnor's Castle",
            section = "Demunir Scry - Gnarled Staff",
            mob = {
                name = "Venril Sathir",
                level = 55,
                location = {
                        zone = "Karnor's Castle",
                },
                spawn_time = "68-72 hour spawn",
                notes = "55 Warrior with approximately 18,000 hitpoints. Hardly anything, but regeneration is amazing. Basically have to kill him within first 20 seconds, or else hard to win fight. Have to realize that 18khp is hardly anything. Has 2 personal clerics which heal him and never seem to run out of mana. Might be smart to have designated group that would kill these before helping other groups with Venril. Best type of spells to cast on him are cold and fire because doesn't have as strong resistances in those type of spells. Has 1000 lifetap punches which can be very dangerous also. Basically need strong guild to kill him and be able to loot staff, if drops. Item need is Gnarled Staff which can be found on Venril Sathir. It's his uncommon drop",
            },
            loot_item = "Gnarled Staff",
        },
        {
            step_number = 12,
            step_type = "give",
            description = "Give Note from Arantir to Kandin Firepot in Butcherblock Mountains",
            section = "The Gnome - Staff of Gabstik (Post-Revamp)",
            npc = {
                name = "Kandin Firepot",
                location = {
                        zone = "Butcherblock Mountains",
                        x = -1500,
                        y = 2800,
                        description = "Near ocean. -1491, +2843 by docks",
                },
            },
            give_item = "Note from Arantir",
            receive_item = "Golem Sprocket",
            notes = "This quest requires faction. Post-Revamp Method: There is now new way can get Staff of Gabstik and note to Arantir. Instead of handing Kandin note from Arantir, Hail him and say 'what oil?' and Kandin will give Golem Sprocket",
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give Golem Sprocket to A Broken Golem in Plane of Fear",
            section = "The Gnome - Staff of Gabstik (Post-Revamp)",
            npc = {
                name = "A Broken Golem",
                location = {
                        zone = "Plane of Fear",
                        x = -720,
                        y = -109,
                },
            },
            give_item = "Golem Sprocket",
            spawns_mob = "An Enraged Golem",
        },
        {
            step_number = 14,
            step_type = "kill",
            description = "Kill An Enraged Golem",
            section = "The Gnome - Staff of Gabstik (Post-Revamp)",
            mob = {
                name = "An Enraged Golem",
                level = 65,
                location = {
                        zone = "Plane of Fear",
                        x = -720,
                        y = -109,
                },
                notes = "Now in place of broken golem is enraged golem. Double hits for 400 and has around 150k hit points. Will need many tanks and clerics. Casters not necessary, but can sometimes put dent into hp. Does not cast so don't need to worry about resists. Says 'Error! Malfunction! Destroy!' 'Wizards like you always bring out worst in me.' This will be LONG fight",
            },
            loot_item = "Green Oil",
        },
        {
            step_number = 15,
            step_type = "give",
            description = "Give Green Oil to Kandin Firepot",
            section = "The Gnome - Staff of Gabstik (Post-Revamp)",
            npc = {
                name = "Kandin Firepot",
                location = {
                        zone = "Butcherblock Mountains",
                        x = -1500,
                        y = 2800,
                },
            },
            give_item = "Green Oil",
        },
        {
            step_number = 16,
            step_type = "kill",
            description = "Kill Cazic Thule in Plane of Fear",
            section = "The Gnome - Staff of Gabstik (Pre-Revamp)",
            mob = {
                name = "Cazic Thule",
                location = {
                        zone = "Plane of Fear",
                },
                notes = "Pre-Revamp method. Note: If have Cazic's Skin from before revamp, can still turn it into Kandin to get Kandin's Bag, which can turn into him to get note. Confirmed by Sesserdrix, 6/21/2023 on Blue",
            },
            loot_item = "Cazic's Skin",
        },
        {
            step_number = 17,
            step_type = "give",
            description = "Give Cazic's Skin to Kandin Firepot",
            section = "The Gnome - Staff of Gabstik (Pre-Revamp)",
            npc = {
                name = "Kandin Firepot",
                location = {
                        zone = "Butcherblock Mountains",
                        x = -1500,
                        y = 2800,
                },
            },
            give_item = "Cazic's Skin",
            receive_item = "Kandin's Bag",
            notes = "When identified, bag comes up with: 'Item Lore: Warning - Explosive!' Although is bag, cannot be opened. Don't worry about this, continue with quest",
        },
        {
            step_number = 18,
            step_type = "kill",
            description = "Kill Tolapumj in Old Sebilis",
            section = "The Gnome - Staff of Gabstik (Pre-Revamp)",
            mob = {
                name = "Tolapumj",
                location = {
                        zone = "Old Sebilis",
                },
            },
            loot_item = "Mistletoe Powder",
        },
        {
            step_number = 19,
            step_type = "give",
            description = "Give Mistletoe Powder to Kandin Firepot",
            section = "The Gnome - Staff of Gabstik (Pre-Revamp)",
            npc = {
                name = "Kandin Firepot",
                location = {
                        zone = "Butcherblock Mountains",
                        x = -1500,
                        y = 2800,
                },
            },
            give_item = "Mistletoe Powder",
            receive_item = "Staff of Gabstik",
        },
        {
            step_number = 20,
            step_type = "give",
            description = "Give Kandin's Bag back to Kandin Firepot",
            section = "The Gnome - Staff of Gabstik (Pre-Revamp)",
            npc = {
                name = "Kandin Firepot",
                location = {
                        zone = "Butcherblock Mountains",
                        x = -1500,
                        y = 2800,
                },
            },
            give_item = "Kandin's Bag",
            receive_item = "Note to Arantir",
            notes = "Identifies as 'Give him a fish!' Reads: 'The fish thank you for people you sent me! Oh also if you ever come across my lantern please let me know.'",
        },
        {
            step_number = 21,
            step_type = "give",
            description = "Give Note to Arantir to Dargon",
            section = "The Ending",
            npc = {
                name = "Dargon",
                location = {
                        zone = "Halas",
                        x = 350,
                        y = 357,
                },
            },
            give_item = "Note to Arantir",
        },
        {
            step_number = 22,
            step_type = "give",
            description = "Give Blue Crystal Staff, Gnarled Staff, and Staff of Gabstik to Arantir Karondor",
            section = "The Ending",
            npc = {
                name = "Arantir Karondor",
                location = {
                        zone = "Halas",
                        x = 350,
                        y = 357,
                },
            },
            give_items = {
                "Blue Crystal Staff",
                "Gnarled Staff",
                "Staff of Gabstik",
            },
            receive_item = "Magically Sealed Bag",
            notes = "Identifies as 'Godlike magic radiates from this bag'",
        },
        {
            step_number = 23,
            step_type = "give",
            description = "Give Magically Sealed Bag to Solomen",
            section = "Staff of the Four",
            npc = {
                name = "Solomen",
                location = {
                        zone = "Temple of Solusek Ro",
                        x = 425,
                        y = 80,
                        z = 29,
                },
            },
            give_item = "Magically Sealed Bag",
            receive_item = "Staff of the Four",
        },
    },
}

return wizard_epic