--[[ tooltip_render.lua: ImGui rendering for item tooltips. Requires api from item_tooltip. ]]
require('ImGui')
local ItemUtils = require('mq.ItemUtils')
local M = {}

function M.renderItemDisplayContent(item, ctx, opts, api)
    if not item then return end
    opts = opts or {}
    local source = opts.source or (item and item.source) or "inv"
    local bag = item.bag ~= nil and item.bag or opts.bag
    local slot = item.slot ~= nil and item.slot or opts.slot
    -- Pre-warm lazy item fields when not using pre-built effects (so layout isn't affected by mid-draw TLO/cache)
    if not opts.effects and item and (bag ~= nil and slot ~= nil and source) then
        local _ = item.augSlots
        _ = item.wornSlots
        _ = item.ac
    end
    -- Every socket row: [24x24 icon area] + SameLine + text (replicate default UI layout).
    -- Filled: draw item icon; empty: draw reserved 24x24 so rows align. See AUGMENT_SOCKET_UI_DESIGN.md.
    local function drawSocketIcon(iconId)
        if iconId and iconId > 0 and ctx and ctx.drawItemIcon then
            pcall(function() ctx.drawItemIcon(iconId) end)
        elseif ctx and ctx.drawEmptySlotIcon then
            pcall(function() ctx.drawEmptySlotIcon() end)
        else
            ImGui.Dummy(ImVec2(24, 24))
        end
    end

    -- Resolve item TLO once per hover (quick); use for class/race/slot, ornament, and augment lines.
    local it = (bag ~= nil and slot ~= nil and source) and api.itemHelpers.getItemTLO(bag, slot, source) or nil
    local parentIt = it
    if it and opts.socketIndex and it.Item then
        local ok, sockIt = pcall(function() return it.Item(opts.socketIndex) end)
        if ok and sockIt then it = sockIt end
    end
    local itValid = it and it.ID and it.ID() ~= 0
    -- Link color for augment/ornament names (hover shows socketed item tooltip).
    local linkColor = ImVec4(0.4, 0.7, 1.0, 1.0)
    local effects = {}

    local function renderSpellInfoBlock(spellId, headerColor, headerText)
        if not spellId or spellId <= 0 or not ctx then return end
        ImGui.Spacing()
        ImGui.TextColored(headerColor, headerText)
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.65, 0.65, 0.7, 1.0))
        ImGui.Text("ID: " .. tostring(spellId))
        if ctx.getSpellDuration then
            local dur = ctx.getSpellDuration(spellId)
            if dur ~= nil then ImGui.Text("Duration: " .. tostring(dur)) end
        end
        if ctx.getSpellRecoveryTime then
            local rec = ctx.getSpellRecoveryTime(spellId)
            if rec ~= nil then ImGui.Text("RecoveryTime: " .. string.format("%.2f", rec)) end
        end
        if ctx.getSpellRecastTime then
            local rt = ctx.getSpellRecastTime(spellId)
            if rt ~= nil then ImGui.Text("RecastTime: " .. string.format("%.2f", rt)) end
        end
        if ctx.getSpellRange then
            local rng = ctx.getSpellRange(spellId)
            if rng ~= nil and rng ~= 0 then ImGui.Text("Range: " .. tostring(rng)) end
        end
        ImGui.PopStyleColor()
    end

    local effectKeys = {"Clicky", "Worn", "Proc", "Focus", "Spell"}
    local function addEffectsFromItem(ef, it, keys)
        if not ctx or not ctx.getItemSpellId or not ctx.getSpellName then return end
        for _, key in ipairs(keys) do
            local id = ctx.getItemSpellId(it, key)
            if id and id > 0 then
                local spellName = ctx.getSpellName(id)
                if spellName and spellName ~= "" then
                    local desc = (ctx.getSpellDescription and ctx.getSpellDescription(id)) or ""
                    local castTime = (key == "Clicky" and ctx.getSpellCastTime and ctx.getSpellCastTime(id)) or nil
                    local recastTime = (key == "Clicky" and ctx.getSpellRecastTime and ctx.getSpellRecastTime(id)) or nil
                    ef[#ef + 1] = { key = key, spellId = id, spellName = spellName, desc = desc, castTime = castTime, recastTime = recastTime }
                end
            end
        end
    end
    if opts.effects then
        effects = opts.effects
    elseif ctx and ctx.getItemSpellId and ctx.getSpellName then
        effects = {}
        addEffectsFromItem(effects, item, effectKeys)
        if parentIt and bag and slot and source and not opts.socketIndex and (item.augSlots or 0) > 0 then
            for socketIndex = 1, math.min(5, item.augSlots or 0) do
                local socketItem = api.getSocketItemStats(parentIt, bag, slot, source, socketIndex)
                if socketItem then addEffectsFromItem(effects, socketItem, effectKeys) end
            end
        end
    end

    local colW = (opts.tooltipColWidth and opts.tooltipColWidth > 0) and opts.tooltipColWidth or api.tooltip_layout.TOOLTIP_COL_WIDTH
    ImGui.Columns(2, "##TooltipCols", false)
    ImGui.SetColumnWidth(0, colW)
    ImGui.SetColumnWidth(1, colW)
    if ImGui.BeginChild then
        ImGui.BeginChild("##TooltipCol1", ImVec2(colW, 0), false)
    end

    -- ---- Column 1: Header (name, ID, type) then Class, Race, Slot, Deity, Ornament, Container, Item info, All Stats, Augmentation slots ----
    local nameColor = ImVec4(0.45, 0.85, 0.45, 1.0)
    if not api.canPlayerUseItem(item, source) then
        nameColor = ImVec4(0.95, 0.35, 0.35, 1.0)
    end
    local headerIconSize = 32
    if ctx and ctx.drawItemIcon and item.icon and item.icon > 0 then
        pcall(function() ctx.drawItemIcon(item.icon, headerIconSize) end)
        ImGui.SameLine()
    end
    ImGui.PushStyleColor(ImGuiCol.Text, nameColor)
    ImGui.TextWrapped(item.name or "—")
    ImGui.PopStyleColor()
    if item.id and item.id ~= 0 then
        ImGui.TextColored(ImVec4(0.55, 0.55, 0.6, 1.0), "ID: " .. tostring(item.id))
    end
    local typeLine = api.getTypeLine(item)
    if typeLine then ImGui.Text(typeLine) end
    if (item.stackSizeMax and item.stackSizeMax > 1) or (item.stackSize and item.stackSize > 1) then
        local stackStr = "Stack: " .. tostring(item.stackSize or 1)
        if item.stackSizeMax and item.stackSizeMax > 0 then stackStr = stackStr .. " / " .. tostring(item.stackSizeMax) end
        ImGui.Text(stackStr)
    end
    ImGui.Spacing()

    -- Class, Race, Slot, Deity, Ornament, Container, Item info, All Stats, Augmentation slots
    local cls, race, slotStr = "—", "—", ""
    if itValid then
        local ok, c, r, s = pcall(api.itemHelpers.getClassRaceSlotFromTLO, it)
        if ok then
            if c and c ~= "" then cls = c end
            if r and r ~= "" then race = r end
            if s and s ~= "" then slotStr = s end
        end
    else
        local ok, c, r, s = pcall(api.itemHelpers.getClassRaceSlotFromTLO, api.itemHelpers.getItemTLO(bag, slot, source))
        if ok then
            if c and c ~= "" then cls = c end
            if r and r ~= "" then race = r end
            if s and s ~= "" then slotStr = s end
        end
    end
    if cls == "—" and (item.class and item.class ~= "") then cls = item.class end
    if race == "—" and (item.race and item.race ~= "") then race = item.race end
    if (slotStr == "" or slotStr == "—") and (item.wornSlots and item.wornSlots ~= "") then slotStr = item.wornSlots end
    if cls and cls ~= "" and cls ~= "—" then ImGui.Text("Class: " .. tostring(cls)) end
    if race and race ~= "" and race ~= "—" then ImGui.Text("Race: " .. tostring(race)) end
    if item.deity and item.deity ~= "" then ImGui.Text("Deity: " .. tostring(item.deity)) end
    slotStr = api.slotStringToDisplay(slotStr)
    if slotStr and slotStr ~= "" and slotStr ~= "—" then ImGui.Text(slotStr) end
    -- Ornament first (match Item Display: IDW_Appearance_Socket_*). Same row layout: [24x24] + text. Name is a link when filled.
    if itValid then
        local ornament = api.getOrnamentFromIt(it)
        if ornament and ornament.name then
            ImGui.Spacing()
            ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Ornament")
            drawSocketIcon(ornament.iconId)
            ImGui.SameLine()
            if ornament.name ~= "empty" and parentIt and not opts.socketIndex then
                ImGui.TextColored(linkColor, ornament.name)
                if ImGui.IsItemHovered() then
                    local socketItem = api.getSocketItemStats(parentIt, bag, slot, source, api.ORNAMENT_SLOT_INDEX)
                    if socketItem then
                        local socketOpts = { source = source, bag = bag, slot = slot, socketIndex = api.ORNAMENT_SLOT_INDEX }
                        local nestEffects, nestW, nestH = api.prepareTooltipContent(socketItem, ctx, socketOpts)
                        socketOpts.effects = nestEffects
                        api.beginItemTooltip(nestW, nestH)
                        api.renderStatsTooltip(socketItem, ctx, socketOpts)
                        ImGui.EndTooltip()
                    end
                end
            else
                ImGui.Text(ornament.name)
            end
            ImGui.Spacing()
        end
    end
    if item.container and item.container > 0 then
        local capStr = item.sizeCapacity and item.sizeCapacity > 0 and (api.SIZE_NAMES[item.sizeCapacity] or tostring(item.sizeCapacity)) or nil
        ImGui.Text("Container: " .. tostring(item.container) .. " slot" .. (item.container == 1 and "" or "s") .. (capStr and (" (" .. capStr .. ")") or ""))
    end
    ImGui.Spacing()

    -- ---- Item info: in-game layout = Left (Size/Weight/Req/Skill) | Middle (AC/HP/Mana/End/Haste) | Right (Base Dmg, Delay, Dmg Bon) ----
    local colW1, colW2, colW3 = 145, 100, 110
    local L1, L2, L3 = "%-12s %s", "%-6s %s", "%-10s %s"
    local leftCol, midCol, rightCol = {}, {}, {}
    local wStr = (item.weight and item.weight ~= 0) and (item.weight >= 10 and string.format("%.1f", item.weight / 10) or tostring(item.weight)) or nil
    if api.formatSize(item) then leftCol[#leftCol + 1] = string.format(L1, "Size:", api.formatSize(item)) end
    if wStr then leftCol[#leftCol + 1] = string.format(L1, "Weight:", wStr) end
    if item.requiredLevel and item.requiredLevel ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Req Level:", tostring(item.requiredLevel)) end
    if item.recommendedLevel and item.recommendedLevel ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Rec Level:", tostring(item.recommendedLevel)) end
    if item.type and item.type ~= "" then leftCol[#leftCol + 1] = string.format(L1, "Skill:", tostring(item.type)) end
    if item.instrumentType and item.instrumentType ~= "" then leftCol[#leftCol + 1] = string.format(L1, "Instrument:", tostring(item.instrumentType) .. ((item.instrumentMod and item.instrumentMod ~= 0) and (" " .. tostring(item.instrumentMod)) or "")) end
    if item.range and item.range ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Range:", tostring(item.range)) end
    if item.charges and item.charges ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Charges:", (item.charges == -1) and "Unlimited" or tostring(item.charges)) end
    if item.skillModValue and item.skillModValue ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Skill Mod:", (item.skillModMax and item.skillModMax ~= 0) and (tostring(item.skillModValue) .. "/" .. tostring(item.skillModMax)) or tostring(item.skillModValue)) end
    if item.baneDMG and item.baneDMG ~= 0 then leftCol[#leftCol + 1] = string.format(L1, "Bane:", tostring(item.baneDMG) .. (item.baneDMGType and item.baneDMGType ~= "" and (" " .. item.baneDMGType) or "")) end
    if item.ac and item.ac ~= 0 then midCol[#midCol + 1] = string.format(L2, "AC:", tostring(item.ac)) end
    if item.hp and item.hp ~= 0 then midCol[#midCol + 1] = string.format(L2, "HP:", tostring(item.hp)) end
    if item.mana and item.mana ~= 0 then midCol[#midCol + 1] = string.format(L2, "Mana:", tostring(item.mana)) end
    if item.endurance and item.endurance ~= 0 then midCol[#midCol + 1] = string.format(L2, "End:", tostring(item.endurance)) end
    if item.haste and item.haste ~= 0 then midCol[#midCol + 1] = string.format(L2, "Haste:", tostring(item.haste) .. "%") end
    if item.purity and item.purity ~= 0 then midCol[#midCol + 1] = string.format(L2, "Purity:", tostring(item.purity)) end
    -- Weapon block: always show Base Dmg, Delay, Dmg Bon when item has weapon stats (match in-game Item Display)
    local isWeapon = (item.damage and item.damage ~= 0) or (item.itemDelay and item.itemDelay ~= 0) or (item.type and item.type ~= "" and (item.type:lower():find("piercing") or item.type:lower():find("slashing") or item.type:lower():find("1h") or item.type:lower():find("2h") or item.type:lower():find("ranged")))
    if isWeapon then
        rightCol[#rightCol + 1] = string.format(L3, "Base Dmg:", tostring(item.damage or 0))
        rightCol[#rightCol + 1] = string.format(L3, "Delay:", tostring(item.itemDelay or 0))
        rightCol[#rightCol + 1] = string.format(L3, "Dmg Bon:", tostring(item.dmgBonus or 0) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or ""))
    else
        if item.damage and item.damage ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Base Dmg:", tostring(item.damage)) end
        if item.itemDelay and item.itemDelay ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Delay:", tostring(item.itemDelay)) end
        if item.dmgBonus and item.dmgBonus ~= 0 then rightCol[#rightCol + 1] = string.format(L3, "Dmg Bon:", tostring(item.dmgBonus) .. (item.dmgBonusType and item.dmgBonusType ~= "" and item.dmgBonusType ~= "None" and (" " .. item.dmgBonusType) or "")) end
    end
    local hasItemInfo = #leftCol > 0 or #midCol > 0 or #rightCol > 0
    if hasItemInfo then
        -- Flat list in item-display order (row-major: each row = left, mid, right; use placeholder for empty)
        local placeholder = " "
        local maxRows = math.max(#leftCol, #midCol, #rightCol)
        local itemInfoFlat = {}
        for row = 1, maxRows do
            itemInfoFlat[#itemInfoFlat + 1] = leftCol[row] or placeholder
            itemInfoFlat[#itemInfoFlat + 1] = midCol[row] or placeholder
            itemInfoFlat[#itemInfoFlat + 1] = rightCol[row] or placeholder
        end
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Item info")
        ImGui.Spacing()
        ImGui.Columns(3, "##TooltipItemInfo", false)
        ImGui.SetColumnWidth(0, colW1)
        ImGui.SetColumnWidth(1, colW2)
        ImGui.SetColumnWidth(2, colW3)
        for i = 1, #itemInfoFlat do
            ImGui.Text(itemInfoFlat[i])
            ImGui.NextColumn()
        end
        ImGui.Columns(1)
        ImGui.Spacing()
        -- Restore 2-column layout so remaining column 1 content stays left
        ImGui.Columns(2, "##TooltipCols", false)
        ImGui.SetColumnWidth(0, colW)
        ImGui.SetColumnWidth(1, colW)
    end

    -- ---- All Stats: Primary (base+heroic), Resistances, Combat/utility ----
    local itemTypeLower = (item.type and tostring(item.type):lower()) or ""
    -- Shielding, DamShield, HPRegen come from batch in buildItemFromMQ (STAT_TLO_MAP); read from item table only (MASTER_PLAN 2.6).
    if rawget(item, "_statsPending") then
        if ctx and ctx.uiState then
            ctx.uiState.pendingStatRescanBags = ctx.uiState.pendingStatRescanBags or {}
            ctx.uiState.pendingStatRescanBags[item.bag] = true
        end
        ImGui.TextColored(ImVec4(0.7, 0.7, 0.5, 1.0), "Loading...")
    else
    local attrs = {
        api.attrLine(item.str, item.heroicSTR, "Strength"),
        api.attrLine(item.sta, item.heroicSTA, "Stamina"),
        api.attrLine(item.int, item.heroicINT, "Intelligence"),
        api.attrLine(item.wis, item.heroicWIS, "Wisdom"),
        api.attrLine(item.agi, item.heroicAGI, "Agility"),
        api.attrLine(item.dex, item.heroicDEX, "Dexterity"),
        api.attrLine(item.cha, item.heroicCHA, "Charisma"),
    }
    local function resistLine(b, h, label)
        b, h = b or 0, h or 0
        if b == 0 and h == 0 then return nil end
        if h > 0 then return string.format("%s: %d+%d", label, b, h) end
        return string.format("%s: %d", label, b)
    end
    local resists = {
        resistLine(item.svMagic, item.heroicSvMagic, "Magic"),
        resistLine(item.svFire, item.heroicSvFire, "Fire"),
        resistLine(item.svCold, item.heroicSvCold, "Cold"),
        resistLine(item.svDisease, item.heroicSvDisease, "Disease"),
        resistLine(item.svPoison, item.heroicSvPoison, "Poison"),
        resistLine(item.svCorruption, item.heroicSvCorruption, "Corruption"),
    }
    local function cl(val, label) if (tonumber(val) or 0) ~= 0 then return string.format("%s: %d", label, tonumber(val) or val or 0) end return nil end
    -- Prefer raw table values for augment stats (batch stores here; ensure we read same table)
    local sh = rawget(item, "shielding")
    local ds = rawget(item, "damageShield")
    local hr = rawget(item, "hpRegen")
    if sh == nil then sh = item.shielding end
    if ds == nil then ds = item.damageShield end
    if hr == nil then hr = item.hpRegen end
    -- Order combat stats to match in-game Item Display right column, then remaining
    local combat = {
        cl(item.attack, "Attack"),
        cl(hr, "HP Regen"),
        cl(item.manaRegen, "Mana Regen"),
        cl(item.enduranceRegen, "End Regen"),
        cl(item.combatEffects, "Combat Eff"),
        cl(ds, "Dmg Shield"),
        cl(item.damageShieldMitigation, "Dmg Shld Mit"),
        cl(item.accuracy, "Accuracy"),
        cl(item.strikeThrough, "Strike Thr"),
        cl(item.healAmount, "Heal Amount"),
        cl(item.spellDamage, "Spell Dmg"),
        cl(item.spellShield, "Spell Shield"),
        cl(sh, "Shielding"),
        cl(item.dotShielding, "DoT Shield"),
        cl(item.avoidance, "Avoidance"),
        cl(item.stunResist, "Stun Resist"),
        cl(item.clairvoyance, "Clairvoyance"),
        cl(item.luck, "Luck"),
    }
    local hasAnyStat = false
    for _, v in ipairs(attrs) do if v then hasAnyStat = true break end end
    for _, v in ipairs(resists) do if v then hasAnyStat = true break end end
    for _, v in ipairs(combat) do if v then hasAnyStat = true break end end
    -- Augments with only combat stats (e.g. Shielding, Dmg Shield, HP Regen): ensure we show them even if hasAnyStat missed
    local augmentSparseStats = itemTypeLower == "augmentation" and ((tonumber(sh) or 0) ~= 0 or (tonumber(ds) or 0) ~= 0 or (tonumber(hr) or 0) ~= 0)
    if augmentSparseStats and not hasAnyStat then hasAnyStat = true end
    if hasAnyStat then
        local placeholder = " "
        local a, r, c = api.tooltip_layout.compactCol(attrs), api.tooltip_layout.compactCol(resists), api.tooltip_layout.compactCol(combat)
        -- Only use single-column when literally only combat has content (so we don't hide attrs/resists on other items)
        local onlyCombat = (#a == 0 and #r == 0 and #c > 0)
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "All Stats")
        ImGui.Spacing()
        if onlyCombat then
            for _, line in ipairs(c) do ImGui.Text(line) end
        else
            local maxRows = math.max(#a, #r, #c)
            local statsFlat = {}
            for row = 1, maxRows do
                statsFlat[#statsFlat + 1] = a[row] or placeholder
                statsFlat[#statsFlat + 1] = r[row] or placeholder
                statsFlat[#statsFlat + 1] = c[row] or placeholder
            end
            ImGui.Columns(3, "##StatsCols", false)
            ImGui.SetColumnWidth(0, colW1)
            ImGui.SetColumnWidth(1, colW2)
            ImGui.SetColumnWidth(2, colW3)
            for i = 1, #statsFlat do
                if statsFlat[i] ~= placeholder then ImGui.Text(statsFlat[i]) end
                ImGui.NextColumn()
            end
            ImGui.Columns(1)
        end
        ImGui.Spacing()
        -- Restore 2-column layout so Augmentation slots and then column 2 stay correct
        ImGui.Columns(2, "##TooltipCols", false)
        ImGui.SetColumnWidth(0, colW)
        ImGui.SetColumnWidth(1, colW)
    end
    end

    -- ---- Augment item only: "This Augmentation fits in slot types" and Restrictions ----
    itemTypeLower = (item.type and tostring(item.type):lower()) or ""
    if itemTypeLower == "augmentation" then
        local at = item.augType or 0
        if at and at > 0 then
            local slotIds = api.itemHelpers.getAugTypeSlotIds(at)
            if slotIds and #slotIds > 0 then
                ImGui.Spacing()
                ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "This Augmentation fits in slot types")
                ImGui.Spacing()
                for _, sid in ipairs(slotIds) do
                    local name = api.AUG_TYPE_NAMES[sid] or ("Type " .. tostring(sid))
                    ImGui.Text(string.format("%d (%s)", sid, name))
                end
                ImGui.Spacing()
            end
        end
        -- AugRestrictions: single ID 1-15 (live EQ). If you see "Restriction N" for N>15 or N not in 1-15,
        -- or the default Item Display shows multiple restriction lines for one augment, add a bitmask decoder:
        -- loop bits 1..15, collect api.AUG_RESTRICTION_NAMES[i] for each set bit, then join with ", ".
        local ar = item.augRestrictions
        if ar and ar > 0 then
            local restrText = api.AUG_RESTRICTION_NAMES[ar] or ("Restriction " .. tostring(ar))
            ImGui.TextColored(ImVec4(0.85, 0.7, 0.4, 1.0), "Restrictions: " .. restrText)
            ImGui.Spacing()
        end
    end

    -- ---- Augmentation slots (own section in column 1: between All Stats and Item effects) ----
    local augLines = itValid and api.getAugmentSlotLinesFromIt(it, item.augSlots) or ((bag ~= nil and slot ~= nil and source) and api.getAugmentSlotLines(bag, slot, source, item.augSlots) or nil)
    if augLines and #augLines > 0 then
        ImGui.Spacing()
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Augmentation slots (standard)")
        ImGui.Spacing()
        local isItemDisplayWin = opts.isItemDisplayWindow and ctx and ctx.uiState
        for _, row in ipairs(augLines) do
            if type(row) == "table" and row.text then
                local prefix = row.prefix or ""
                local augName = (type(row.augName) == "string") and row.augName or ""
                local isEmpty = (augName == "empty" or augName == "")
                ImGui.PushID("AugSlot" .. tostring(row.slotIndex or 0) .. "_" .. tostring(bag or "") .. "_" .. tostring(slot or ""))
                drawSocketIcon(row.iconId)
                -- Icon hover and click (Item Display only): hover = tooltip; left-click = open Augment Utility to this socket (add or replace); filled right-click = remove
                if isItemDisplayWin and row.slotIndex and bag and slot and source and ctx.uiState then
                    if ImGui.IsItemHovered() then
                        if not isEmpty then
                            local socketItem = api.getSocketItemStats(parentIt, bag, slot, source, row.slotIndex)
                            if socketItem then
                                local socketOpts = { source = source, bag = bag, slot = slot, socketIndex = row.slotIndex }
                                local nestEffects, nestW, nestH = api.prepareTooltipContent(socketItem, ctx, socketOpts)
                                socketOpts.effects = nestEffects
                                api.beginItemTooltip(nestW, nestH)
                                api.renderStatsTooltip(socketItem, ctx, socketOpts)
                                ImGui.Spacing()
                                ImGui.TextColored(ImVec4(0.7, 0.6, 0.5, 1.0), "Left-click: open Augment Utility to this socket (replace augment)")
                                ImGui.TextColored(ImVec4(0.7, 0.6, 0.5, 1.0), "Right-click: remove augment")
                                ImGui.EndTooltip()
                            end
                        else
                            ImGui.BeginTooltip()
                            ImGui.Text((prefix ~= "" and prefix or ("Slot " .. tostring(row.slotIndex))) .. "Empty.")
                            ImGui.Text("Left-click to open Augment Utility and add an augment.")
                            ImGui.EndTooltip()
                        end
                    end
                    if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
                        ctx.uiState.augmentUtilitySlotIndex = row.slotIndex
                        ctx.uiState.augmentUtilityWindowOpen = true
                        ctx.uiState.augmentUtilityWindowShouldDraw = true
                    end
                    if not isEmpty and ctx.removeAugment and ImGui.IsItemClicked(ImGuiMouseButton.Right) then
                        ctx.removeAugment(bag, slot, source, row.slotIndex)
                    end
                end
                ImGui.SameLine()
                if prefix ~= "" then ImGui.Text(prefix); ImGui.SameLine() end
                if augName ~= "empty" and parentIt and not opts.socketIndex and row.slotIndex then
                    ImGui.TextColored(linkColor, augName)
                    if ImGui.IsItemHovered() then
                        local socketItem = api.getSocketItemStats(parentIt, bag, slot, source, row.slotIndex)
                        if socketItem then
                            local socketOpts = { source = source, bag = bag, slot = slot, socketIndex = row.slotIndex }
                            local nestEffects, nestW, nestH = api.prepareTooltipContent(socketItem, ctx, socketOpts)
                            socketOpts.effects = nestEffects
                            api.beginItemTooltip(nestW, nestH)
                            api.renderStatsTooltip(socketItem, ctx, socketOpts)
                            ImGui.EndTooltip()
                        end
                    end
                else
                    ImGui.Text(augName ~= "" and augName or row.text)
                end
                ImGui.PopID()
            else
                ImGui.Text((type(row) == "table" and row.text) or tostring(row))
            end
        end
        ImGui.Spacing()
    elseif item.augSlots and item.augSlots > 0 then
        ImGui.Spacing()
        ImGui.Text("Augment slots: " .. tostring(item.augSlots))
        ImGui.Spacing()
    end

    if ImGui.EndChild then ImGui.EndChild() end
    ImGui.NextColumn()
    if ImGui.BeginChild then
        ImGui.BeginChild("##TooltipCol2", ImVec2(colW, 0), false)
    end

    -- ---- Column 2: Item effects, Item information, Spell Info blocks, Value & Tribute ----
    local effectLabels = { Clicky = "Clicky", Worn = "Worn", Proc = "Proc", Focus = "Focus", Spell = "Spell" }
    local focusLabel = "Focus"
    local function formatRecastDelay(sec)
        if sec == nil or sec < 0 then return nil end
        local s = math.floor(sec + 0.5)
        if s < 60 then return s == 1 and "1 second" or (s .. " seconds") end
        local m = math.floor(s / 60)
        local r = s % 60
        if r == 0 then return m == 1 and "1 minute" or (m .. " minutes") end
        local ms = m == 1 and "1 minute" or (m .. " minutes")
        local rs = r == 1 and "1 second" or (r .. " seconds")
        return ms .. " and " .. rs
    end
    if #effects > 0 then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Item effects")
        ImGui.Spacing()
        for _, e in ipairs(effects) do
                local label
                if e.key == focusLabel then
                    label = "Focus Effect: " .. e.spellName
                else
                    label = "Effect: " .. e.spellName .. " (" .. effectLabels[e.key] .. ")"
                end
                ImGui.Text(label)
                if e.key == "Clicky" and (e.castTime ~= nil or (e.recastTime ~= nil and e.recastTime > 0)) then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.65, 0.65, 0.7, 1.0))
                    if e.castTime ~= nil then
                        local ct = e.castTime
                        local ctStr = (ct == math.floor(ct)) and tostring(math.floor(ct)) or string.format("%.1f", ct)
                        ImGui.Text("Casting Time: " .. ctStr)
                    end
                    -- Recast delay = max cooldown observed for this slot (countdown start); fallback to spell recast until we've seen it
                    local recastSec = (bag and slot and source and ctx and ctx.getMaxRecastForSlot) and ctx.getMaxRecastForSlot(bag, slot, source) or e.recastTime
                    if recastSec ~= nil and recastSec > 0 then
                        ImGui.Text("Recast Delay: " .. formatRecastDelay(recastSec))
                    end
                    ImGui.PopStyleColor()
                end
                if e.desc and e.desc ~= "" then
                    ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.65, 0.65, 0.7, 1.0))
                    ImGui.TextWrapped(e.desc)
                    ImGui.PopStyleColor()
                    ImGui.Spacing()
                end
        end
        ImGui.Spacing()
    end

    -- ---- Item information (blue block: section 2; Item ID, Icon ID, Value, Ratio, Lore, Timer) ----
    local infoBlue = ImVec4(0.45, 0.7, 1.0, 1.0)
    local infoGreen = ImVec4(0.4, 0.9, 0.4, 1.0)
    if not opts.socketIndex then
        ImGui.Spacing()
        ImGui.TextColored(infoBlue, "Item information")
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.6, 0.75, 0.95, 1.0))
        if item.id and item.id ~= 0 then ImGui.Text("Item ID: " .. tostring(item.id)) end
        if item.icon and item.icon ~= 0 then ImGui.Text("Icon ID: " .. tostring(item.icon)) end
        local val = item.totalValue or item.value
        if val and val ~= 0 then
            local valStr = (ItemUtils and ItemUtils.formatValue) and ItemUtils.formatValue(val) or tostring(val)
            ImGui.Text("Value: " .. valStr)
        end
        if item.damage and item.damage ~= 0 and item.itemDelay and item.itemDelay ~= 0 then
            local ratio = item.damage / item.itemDelay
            ImGui.Text("Ratio: " .. string.format("%.3f", ratio))
        end
        if itValid and ctx and ctx.getItemLoreText then
            local loreStr = ctx.getItemLoreText(it)
            if loreStr and loreStr ~= "" then ImGui.TextWrapped("Item Lore: " .. loreStr) end
        end
        if bag and slot and source and ctx and ctx.getTimerReady then
            local ready = ctx.getTimerReady(bag, slot, source)
            if ready == nil or ready == 0 then
                ImGui.PopStyleColor()
                ImGui.TextColored(infoGreen, "Item Timer: Ready")
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.6, 0.75, 0.95, 1.0))
            else
                ImGui.Text("Item Timer: " .. tostring(math.floor(ready + 0.5)) .. "s")
            end
        end
        ImGui.PopStyleColor()
        ImGui.Spacing()
    end

    -- ---- Spell Info blocks (sections 3-6): Clicky, Proc, Worn, Focus — only if effect present ----
    if #effects > 0 then
        local spellInfoOrder = { "Clicky", "Proc", "Worn", "Focus" }
        local spellInfoColors = {
            Clicky = ImVec4(0.4, 0.9, 0.4, 1.0),
            Proc   = ImVec4(0.9, 0.65, 0.2, 1.0),
            Worn   = ImVec4(0.9, 0.9, 0.4, 1.0),
            Focus  = ImVec4(0.5, 0.75, 1.0, 1.0),
        }
        for _, key in ipairs(spellInfoOrder) do
            for _, e in ipairs(effects) do
                if e.key == key and e.spellId and e.spellName then
                    renderSpellInfoBlock(e.spellId, spellInfoColors[key], "Spell Info for " .. key .. " effect: " .. e.spellName)
                    break
                end
            end
        end
    end

    -- ---- Value, Tribute ----
    local val = item.totalValue or item.value
    if val and val ~= 0 then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Value")
        local valStr = (ItemUtils and ItemUtils.formatValue) and ItemUtils.formatValue(val) or tostring(val)
        ImGui.Text(valStr)
    end
    if item.tribute and item.tribute ~= 0 then
        ImGui.TextColored(ImVec4(0.6, 0.8, 1.0, 1.0), "Tribute")
        ImGui.Text(tostring(item.tribute))
    end

    if ImGui.EndChild then ImGui.EndChild() end
    ImGui.Columns(1)
    end

return M
