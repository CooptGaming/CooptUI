-- SHAMAN Epic Quest: Spear of Fate
-- Auto-generated from structured quest data

local shaman_epic = {
    class = "shaman",
    quest_name = "Spear of Fate",
    reward_item = "Spear of Fate",
    start_zone = "Various",
    recommended_level = 46,
    start_npc = {
    npc = {
        name = "A Lesser Spirit",
        location = {
        zone = "Various",
        description = "Spawns after killing one of: Capt Surestout (Ocean of Tears +800, -5400), Blinde the Cutpurse (Rathe Mountains +3087, +1302), Peg Leg (Butcherblock Mountains +260, +1650), An Iksar Manslayer (Field of Bone - marauder cave)",
        },
    },
    },
    zones = {
        "Ocean of Tears",
        "Rathe Mountains",
        "Butcherblock Mountains",
        "Field of Bone",
        "North Freeport",
        "Erud's Crossing",
        "West Karana",
        "Emerald Jungle",
        "Mistmoore",
        "City of Mist",
        "The Hole",
        "Plane of Fear",
    },
    steps = {
        {
            step_number = 1,
            step_type = "kill",
            description = "Kill one of the trigger mobs to spawn A Lesser Spirit",
            section = "Beginning the Quest",
            mob = {
                name = "Capt Surestout / Blinde the Cutpurse / Peg Leg / An Iksar Manslayer",
                level = 20,
                location = {
                        zone = "Various",
                        description = "Capt Surestout: Ocean of Tears +800, -5400. Blinde: Rathe Mountains +3087, +1302. Peg Leg: Butcherblock Mountains +260, +1650. An Iksar Manslayer: Field of Bone marauder cave",
                },
            },
        },
        {
            step_number = 2,
            step_type = "talk",
            description = "Talk to A Lesser Spirit",
            section = "Beginning the Quest",
            npc = {
                name = "A Lesser Spirit",
                location = {
                        zone = "Various",
                },
            },
            receive_item = "Tiny Gem",
        },
        {
            step_number = 3,
            step_type = "give",
            description = "Give Tiny Gem to Bondl Felligan in North Freeport",
            section = "The Drunken Shaman",
            npc = {
                name = "Bondl Felligan",
                location = {
                        zone = "North Freeport",
                        x = 304,
                        y = 431,
                        description = "Sewers in northwestern part of town (In river on way to WFP). Little ways in on inside of collapsed wall. May spawn in sewers, or may spawn at +30, +480 and path to inn",
                },
            },
            give_item = "Tiny Gem",
        },
        {
            step_number = 4,
            step_type = "talk",
            description = "Talk to A Greater Spirit in Jade Tiger's Den",
            section = "The Drunken Shaman",
            npc = {
                name = "A Greater Spirit",
                location = {
                        zone = "North Freeport",
                        description = "Jade Tiger's Den, second floor, middle room",
                },
            },
        },
        {
            step_number = 5,
            step_type = "talk",
            description = "Talk to A Greater Spirit in other room",
            section = "The Drunken Shaman",
            npc = {
                name = "A Greater Spirit",
                location = {
                        zone = "North Freeport",
                        description = "Other room in Jade Tiger's Den",
                },
            },
            receive_item = "Opaque Gem",
        },
        {
            step_number = 6,
            step_type = "give",
            description = "Give Opaque Gem to Ooglyn in Erud's Crossing",
            section = "Test of Patience",
            npc = {
                name = "Ooglyn",
                location = {
                        zone = "Erud's Crossing",
                        x = -900,
                        y = 1600,
                        description = "Female ogre shaman on island",
                },
                spawn_time = "2 hours",
            },
            give_item = "Opaque Gem",
            notes = "Ooglyn says 'Ooooh, it you, shaman. Me's been waitin for you cuz our frenz say you comin an need da test. So's I gib you da test. Hmm, now where me put it? Ooglyn been waiting for sign for so long dat me forget where me put test. Keep your eyes out for sign while me look for test. Oh, hey, shaman, they gib you gem? I need dat gem, please, heheh.' After giving gem: 'Ahhh, tank you, now me can...OH LOOK!! DA SIGN!!!! Oh, sorry you missed it. Sign show you where to wait for da test. Follow me...I like you so I take you there. We goin for a swim, shaman!' Follow Ooglyn. Will swim past ruined boat and eventually end up at bottom of ocean at location -1600, +4200. If accidentally lose her, just go to location. Might be waiting there and might not. Either way, doesn't matter. Summon pet if plan to fight sharks or cast Invisibility/Invisibility versus Animals if want to try and avoid them. Note some killer sharks see through invisibility. Neither strategy necessary as long as stay on sea floor at location. Hung out there whole time with pet up and didn't catch any agro, despite killer shark swimming directly above. Also worth mentioning: Some of following NPC's will tell you to follow them, and then swim away. DO NOT. They are trying to trick you into leaving your spot in your 'Test of Patience.' Just be patient, as Shaman should be. 'Ok, here is place for you to for waiting. Hab fun shaman!'",
        },
        {
            step_number = 7,
            step_type = "wait",
            description = "Wait at location -1600, +4200 in Erud's Crossing",
            section = "Test of Patience",
            notes = "During course of this event many NPC's will spawn, asking you to follow them. Do NOT move from this spot or will have to start over. Do not actually have to talk to any NPC's, just have to wait. Four minutes later, Srafen the Soaked will appear. Three minutes after Srafen appears, Dillon the Drowned will appear. 11 minutes after Dillon appears, Srafen will speak. 3 minutes after Srafen speaks, he will say this and depart. 3 minutes later, Froham the Forgotten appears. Froham will not respond to any more attempts at conversation. 6 minutes after he appears, he will depart. 5 minutes later, Abe the Abandoned will appear. 4 minutes after he appears, Abe will say something. 3 minutes later, Abe will depart. 3-4 minutes later greater spirit will spawn. Only one shaman can benefit from Test of Patience at a time",
        },
        {
            step_number = 8,
            step_type = "give",
            description = "Give Broken Arrow to A Greater Spirit (if received from Abe)",
            section = "Test of Patience",
            npc = {
                name = "A Greater Spirit",
                location = {
                        zone = "Erud's Crossing",
                        x = -1600,
                        y = 4200,
                },
            },
            receive_item = "A Small Gem",
            notes = "As for broken arrow, there is no use for it in P99 but has been used much later in EQ live",
        },
        {
            step_number = 9,
            step_type = "give",
            description = "Give A Small Gem to A Wandering Spirit in West Karana",
            section = "Test of Wisdom",
            npc = {
                name = "A Wandering Spirit",
                location = {
                        zone = "West Karana",
                        x = -500,
                        y = -5300,
                        description = "Looks exactly like wisp but little brighter/bigger. Probably best to get tracker to help. If don't have one, can stand at -500, -5300 and spirit will wander by. Can take up to 30 minutes. Once spotted, run up to him and hail at close range to get him to stop moving",
                },
            },
            give_item = "A Small Gem",
        },
        {
            step_number = 10,
            step_type = "kill",
            description = "Kill Glaron the Wicked in Rathe Mountains",
            section = "Test of Wisdom",
            mob = {
                name = "Glaron the Wicked",
                level = 32,
                location = {
                        zone = "Rathe Mountains",
                        x = 2900,
                        y = -1900,
                        description = "#17 on Rathe Mountains map",
                },
                notes = "Both men have lost sight of their true cause and instead spend all their energy trying to spite other",
            },
        },
        {
            step_number = 11,
            step_type = "kill",
            description = "Kill Tabien the Goodly in Rathe Mountains",
            section = "Test of Wisdom",
            mob = {
                name = "Tabien the Goodly",
                level = 32,
                location = {
                        zone = "Rathe Mountains",
                        x = 6300,
                        y = 1550,
                        description = "#2 on Rathe Mountains map",
                },
            },
            loot_item = "Marr's Promise",
        },
        {
            step_number = 12,
            step_type = "give",
            description = "Give Envy, Woe, and Marr's Promise to A Wandering Spirit in West Karana",
            section = "Test of Wisdom",
            npc = {
                name = "A Wandering Spirit",
                location = {
                        zone = "West Karana",
                        description = "Generally between Qeynos hills and bandit camp in mountains",
                },
            },
            give_items = {
                "Envy",
                "Woe",
                "Marr's Promise",
            },
        },
        {
            step_number = 13,
            step_type = "give",
            description = "Give Sparkling Gem to Spirit Sentinel in Emerald Jungle",
            section = "Test of Might",
            npc = {
                name = "Spirit Sentinel",
                location = {
                        zone = "Emerald Jungle",
                        x = 1250,
                        y = 300,
                        description = "Cylinder shaped building",
                },
            },
            give_item = "Sparkling Gem",
        },
        {
            step_number = 14,
            step_type = "kill",
            description = "Kill An Advisor in Mistmoore",
            section = "Test of Might - Black Dire",
            mob = {
                name = "An Advisor",
                location = {
                        zone = "Mistmoore",
                        description = "Library of castle. Check map - advisor in room #19.a. Can be reached by going into Castle Entrance foyer (Entry Hall #8), up stairs 'B' and then through double doors. Take first right, then left (which passes #19 Library). At end of short hall is door on right leading to unmarked room. To right is 19.a. Easier to take this path as less mobs to clear/deal with when pulling or killing advisor",
                },
                spawn_time = "Every four hours since last time of death",
                notes = "Minimum level 5 to zone into Mistmoore",
            },
            spawns_mob = "Black Dire",
        },
        {
            step_number = 15,
            step_type = "kill",
            description = "Kill Black Dire in Mistmoore",
            section = "Test of Might - Black Dire",
            mob = {
                name = "Black Dire",
                location = {
                        zone = "Mistmoore",
                        description = "Back of canyon where blood hounds are at #4 on map. He and four wolf guardians will not attack until hail him. Know that hailing him is not required and actually not recommended",
                },
                notes = "Will want several 55+ characters and at minimum tank and healer (ideally Cleric or Shaman with Torpor). Damage dealer would speed things along though not necessary as strong tank and healer can complete as duo. Black Dire is Shadow Knight based creature and will perform normal line of Shadow Knight spells. To increase chances of success or efficiency, attack as soon as possible to avoid buffing itself. Before killing advisor, consider removing four Blood Hounds in canyon first. This way can avoid potential aggro/social assistance they might give Black Dire depending on puller's level. However provided wolf guardians consider green to all in party, can pull/fight Black Dire without them aggroing",
            },
            loot_item = "Black Dire Pelt",
        },
        {
            step_number = 16,
            step_type = "give",
            description = "Give Black Dire Pelt to Spirit Sentinel in Emerald Jungle",
            section = "Test of Might - Black Dire",
            npc = {
                name = "Spirit Sentinel",
                location = {
                        zone = "Emerald Jungle",
                        x = 1250,
                        y = 300,
                },
            },
            give_item = "Black Dire Pelt",
        },
        {
            step_number = 17,
            step_type = "kill",
            description = "Collect 6 reports from City of Mist",
            section = "City of Mist Reports",
            mob = {
                name = "Skeletons / Golems / Goos / Spectral Courier",
                location = {
                        zone = "City of Mist",
                        description = "Five of six messages drop from skeletons, golems, and goos at zone in. Student's Log only found on Spectral Courier (level 34). Courier is rare spawn in western half of stables. On City of Mist map, courier spawn is #6. Best to just clear stables over and over again until get all pages",
                },
            },
            notes = "Turn in is KINDLY or better",
        },
        {
            step_number = 18,
            step_type = "craft",
            description = "Combine 6 reports in Booklet",
            section = "City of Mist Reports",
            receive_item = "Completed Report",
        },
        {
            step_number = 19,
            step_type = "give",
            description = "Give Completed Report to Spirit Sentinel in Emerald Jungle",
            section = "City of Mist Reports",
            npc = {
                name = "Spirit Sentinel",
                location = {
                        zone = "Emerald Jungle",
                        x = 1250,
                        y = 300,
                },
            },
            give_item = "Completed Report",
        },
        {
            step_number = 20,
            step_type = "kill",
            description = "Kill Lord Ghiosk in City of Mist",
            section = "Three Books of Lord Ghiosk",
            mob = {
                name = "Lord Ghiosk",
                location = {
                        zone = "City of Mist",
                        description = "At #1 on map. To get into castle, need rogue to picklock door open",
                },
                notes = "Need about 3 groups of level 55 or equivalent. (This is not quite accurate; killed him without too much trouble with one group in low 50's and most were not geared. Healer was 45. Highest level [54] and best geared [rogue epic])",
            },
            notes = "All in language of Lizardman. NOTE: DO NOT give 3 books to Spirit Sentinel near CoM, this is NOT right npc. Correct 'Spirit Sentinel' at bottom of pond in Emerald Jungle, located at +3685, -640",
        },
        {
            step_number = 21,
            step_type = "give",
            description = "Give three books to Spirit Sentinel in pond in Emerald Jungle",
            section = "Three Books of Lord Ghiosk",
            npc = {
                name = "Spirit Sentinel",
                location = {
                        zone = "Emerald Jungle",
                        x = 3685,
                        y = -640,
                        description = "Bottom of pond in Emerald Jungle. NOT the one near CoM",
                },
            },
            give_items = {
                "Historic Article",
                "Head Housekeeper's Log",
                "Crusades of the High Scale",
            },
        },
        {
            step_number = 22,
            step_type = "loot",
            description = "Obtain Icon of the High Scale from City of Mist",
            section = "Icon of the High Scale",
            loot_item = "Icon of the High Scale",
        },
        {
            step_number = 23,
            step_type = "give",
            description = "Give Icon of the High Scale to High Scale Kirn in The Hole",
            section = "High Scale Kirn",
            npc = {
                name = "High Scale Kirn",
                location = {
                        zone = "The Hole",
                        description = "Tower beyond city. Check map. Kirn is #3. Respawn time is four hours. As far as getting to Kirn, there are two options. Option 1: Yael drop down. Method should take about 20-30 minutes. Drop down from Paineel into Yaels pit. Some people able to survive fall, others not. If drop down and immediately run into water won't agro surrounding mobs. From here follow tunnel up to undead tower. Kill roaming golem / elementals and then IVU up to flat before Kirn. Option 2: Work way through city. Method can take up to 2 hours. Eventually come to open area with tower off in distance. Open area has 2 spawns - rock golem and elemental. Kill those, move up. Have 6 minutes. Open area faces tower and dips down, flattening in bottom before rising again towards tower. In this area before tower come across few roamers. Destination is ahead. Work way to base of tower. In front of castle are two spawns - revenant/wanderers. Now have choice: 1) Invisibility versus Undead - Keeper of Tomb in left hand courtyard of revenant tower will eat 2-3 groups alive if agro him. Good news is Invisibility versus Undead works in tower (even though some revenants will scowl at you, they will not attack). Go through gate, run through middle main doors of tower and to back where single door opens to stairs leading upward. Follow this up couple flights to Kirn himself, then drop invisibility in his room. Disadvantage is can be messy if couple raid members have invisibility drop on them and die. Make SURE everybody knows before hand to let people die if get attacked - just drag corpses up and rez them once situated. 2) Kill way through (be wary of Keeper). Pull to flat to prevent continuously fighting 6 minute respawns at top. May be tough as attract all roamers from Master Yael tunnel. If have been tearing through mobs previously, should be no problem progressing and moving up tower. However, if not killing very fast probably should not pull inside of tower for one or two rotations. Split up spawn from this area first. Next, wait until two revenants at doorway spawn and then kill them. Then have 6 minutes to kill around 3 revenants in first room of tower. Trick here is move inside. Do not try to pull great portion of tower to outside; respawn rate and number of mobs likely to be too high. Work way up to Kirn. Once get to High Scale Kirn, kill three revanants in aggro range. Since Kirn is indifferent should not be using area effect spells of any kind",
                },
            },
            give_item = "Icon of the High Scale",
            spawns_mob = "High Scale Kirn (hostile)",
        },
        {
            step_number = 24,
            step_type = "kill",
            description = "Kill High Scale Kirn",
            section = "High Scale Kirn",
            mob = {
                name = "High Scale Kirn",
                location = {
                        zone = "The Hole",
                },
                notes = "Need about 1 groups of level 60's. Killed him with 1 cleric, 1 warrior, 1 enchanter and 1 monk. Enchanter had elemental capturer as pet. Was super easy",
            },
            loot_item = "Engraved Ring",
            notes = "Identifies as 'Promise Ring of Neh`Ashiir'",
        },
        {
            step_number = 25,
            step_type = "give",
            description = "Give Engraved Ring to Neh'Ashiir in City of Mist",
            section = "Final Steps",
            npc = {
                name = "Neh'Ashiir",
                location = {
                        zone = "City of Mist",
                        description = "Final platform. Check map. Pull Black Reaver, which is 100% magic immune. After Black Reavers killed, chance that another will spawn directly afterwards on spot. In this way, up to 50 or more reavers can spawn in row, although high numbers like this very rare. After all Black Reavers done, Neh`Ashiir will spawn. She is non-KoS, but will attack immediately after give her ring, so following conversation will fly by",
                },
            },
            give_item = "Engraved Ring",
            spawns_mob = "Neh'Ashiir (hostile)",
        },
        {
            step_number = 26,
            step_type = "kill",
            description = "Kill Neh'Ashiir",
            section = "Final Steps",
            mob = {
                name = "Neh'Ashiir",
                location = {
                        zone = "City of Mist",
                },
            },
            loot_item = "Neh`Ashiir's Diary",
        },
        {
            step_number = 27,
            step_type = "give",
            description = "Give Neh'Ashiir's Diary to Spirit Sentinel in pond in Emerald Jungle",
            section = "Final Steps",
            npc = {
                name = "Spirit Sentinel",
                location = {
                        zone = "Emerald Jungle",
                        x = 3685,
                        y = -640,
                        description = "Bottom of pond",
                },
            },
            give_item = "Neh`Ashiir's Diary",
        },
        {
            step_number = 28,
            step_type = "kill",
            description = "Kill Dread, Fright, or Terror in Plane of Fear",
            section = "Final Steps",
            mob = {
                name = "Dread / Fright / Terror",
                location = {
                        zone = "Plane of Fear",
                        description = "Three personal guards of Cazic Thule",
                },
                notes = "Proceed to Plane of Fear with raid force and slay either Dread, Fright, or Terror. After kill one of them, 'Iksar Broodling' will spawn by corpse. She is only level one and not KoS. Kill her and loot tear. If guild not powerful enough to raid Plane of Fear, try to tag along with another raid. Ask beforehand if anybody will be needing tear; if nobody does you are in luck",
            },
            spawns_mob = "Iksar Broodling",
        },
        {
            step_number = 29,
            step_type = "kill",
            description = "Kill Iksar Broodling",
            section = "Final Steps",
            mob = {
                name = "Iksar Broodling",
                level = 1,
                location = {
                        zone = "Plane of Fear",
                },
                notes = "Only level one, not KoS",
            },
            loot_item = "Child's Tear",
        },
        {
            step_number = 30,
            step_type = "give",
            description = "Give Child's Tear to Lord Rak'Ashiir in City of Mist",
            section = "Final Steps",
            npc = {
                name = "Lord Rak'Ashiir",
                location = {
                        zone = "City of Mist",
                        description = "End of any Black Reaver 'cycle', as explained above with Neh'Ashiir. Means can be found at any place where Black Reavers spawn. When people killing Reavers, often leave without killing Rak'Ashiir (as have no reason to and he is rather nasty). Check around with tracker and might find him without having to kill Reavers",
                },
            },
            give_item = "Child's Tear",
            spawns_mob = "Lord Rak'Ashiir (hostile)",
        },
        {
            step_number = 31,
            step_type = "kill",
            description = "Kill Lord Rak'Ashiir",
            section = "Final Steps",
            mob = {
                name = "Lord Rak'Ashiir",
                location = {
                        zone = "City of Mist",
                },
            },
            loot_item = "Iksar Scale",
        },
        {
            step_number = 32,
            step_type = "give",
            description = "Give Iksar Scale to Spirit Sentinel in pond in Emerald Jungle",
            section = "Spear of Fate",
            npc = {
                name = "Spirit Sentinel",
                location = {
                        zone = "Emerald Jungle",
                        x = 3685,
                        y = -640,
                        description = "Bottom of pond. AGAIN: Because this happens more often than people think: THE FINAL TURN IN IS TO THE DOG IN THE WATER! NOTE: DO NOT give scale to Spirit Sentinel near CoM, this is NOT right npc",
                },
            },
            give_item = "Iksar Scale",
            receive_item = "Spear of Fate",
        },
    },
}

return shaman_epic