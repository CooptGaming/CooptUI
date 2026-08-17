--[[
    Clickies (Favorites) View - user-defined clicky lists as a pop-out window.

    Tabs per list (e.g. "Buffs", "Damage"); each row is an item added via the
    right-click "Clicky Lists" menu: icon (hover = stats), name, clicky effect
    with cooldown state, a Use button, and Remove. Items on any list are
    protected from selling and the Delete menu until removed here.
--]]

local mq = require('mq')
require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local context = require('itemui.context')
local registry = require('itemui.core.registry')
local windowHeader = require('itemui.components.window_header')

local FavoritesView = {}

local FAVORITES_WINDOW_WIDTH = 460
local FAVORITES_WINDOW_HEIGHT = 380

local newListName = ""
-- id -> live inventory item, rebuilt when the inventory scan changes identity.
local invCache = { key = nil, byId = {} }

local function getInvById(ctx)
    -- Mutation-generation key (see views/augments.lua): count or first-row identity
    -- alone miss targeted bag rescans - and this map feeds the Use button's
    -- /itemnotify address, so a stale row here clicks the wrong bag slot.
    local invItems = ctx.inventoryItems or {}
    local pc = ctx.perfCache
    local key = string.format("%d|%s|%s", #invItems,
        tostring(pc and pc.lastScanTimeInv or 0), tostring(pc and pc.invMutationGen or 0))
    if invCache.key ~= key then
        local byId = {}
        for _, it in ipairs(invItems) do
            local id = tonumber(it.id or it.ID)
            if id and not byId[id] then byId[id] = it end
        end
        invCache.key = key
        invCache.byId = byId
    end
    return invCache.byId
end

-- id -> { item, slotIndex } for WORN items (epics etc. live in worn slots).
-- Time-throttled: the equipment cache refresh is cheap when nothing changed
-- (~23 ID reads), but there is no identity key to invalidate on, so rebuild
-- at most once a second while the window renders.
local wornCache = { at = 0, byId = {} }

local function getWornById(ctx)
    local now = mq.gettime()
    if (now - wornCache.at) < 1000 then return wornCache.byId end
    wornCache.at = now
    if ctx.refreshEquipmentCache then ctx.refreshEquipmentCache() end
    local byId = {}
    local eq = ctx.equipmentCache or {}
    for slotIndex = 0, 22 do
        local it = eq[slotIndex + 1]
        local id = it and tonumber(it.id or it.ID)
        if id and not byId[id] then byId[id] = { item = it, slotIndex = slotIndex } end
    end
    wornCache.byId = byId
    return byId
end

local function renderListRows(ctx, fav, list)
    local invById = getInvById(ctx)
    local wornById = getWornById(ctx)
    local hasCursor = ctx.hasItemOnCursor()
    if #list.items == 0 then
        ctx.theme.TextMuted("Empty. Right-click an item in the Inventory or Equipment Companion and use Clicky Lists > " .. list.name .. ".")
        return
    end
    if not ImGui.BeginTable("ClickyList_" .. list.name, 5, ctx.uiState.tableFlags or 0) then return end
    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 28, 0)   -- Icon
    ImGui.TableSetupColumn("Name", ImGuiTableColumnFlags.WidthStretch, 0, 1)
    ImGui.TableSetupColumn("Clicky", ImGuiTableColumnFlags.WidthStretch, 0, 2)
    ImGui.TableSetupColumn("Use", ImGuiTableColumnFlags.WidthFixed, 50, 3)
    ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 64, 4)   -- Remove
    ImGui.TableSetupScrollFreeze(0, 1)
    ImGui.TableHeadersRow()

    for i, entry in ipairs(list.items) do
        local item = invById[entry.id]
        local worn = (not item) and wornById[entry.id] or nil
        ImGui.TableNextRow()
        ImGui.PushID("clicky_" .. list.name .. "_" .. tostring(entry.id) .. "_" .. i)

        -- Icon (hover = full stats when the item is in bags or worn)
        ImGui.TableNextColumn()
        local iconItem = item or (worn and worn.item)
        if iconItem and ctx.drawItemIcon then
            ctx.drawItemIcon(iconItem.icon)
            if ImGui.IsItemHovered() then
                local src = item and "inv" or "equipped"
                local loc = item and { bag = item.bag, slot = item.slot } or { bag = 0, slot = worn.slotIndex }
                local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item or { bag = 0, slot = worn.slotIndex, source = "equipped" }, src)) or iconItem
                local opts = { source = src, bag = loc.bag, slot = loc.slot }
                local effects, tw, th = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                opts.effects = effects
                ItemTooltip.beginItemTooltip(tw, th)
                ImGui.Text("Stats")
                ImGui.Separator()
                ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                ImGui.EndTooltip()
            end
        else
            ctx.theme.TextMuted("-")
        end

        -- Name
        ImGui.TableNextColumn()
        if item then
            local dn = item.name or entry.name or ""
            if (item.stackSize or 1) > 1 then dn = dn .. string.format(" (x%d)", item.stackSize) end
            ImGui.Selectable(dn, false, ImGuiSelectableFlags.None, ImVec2(0, 0))
            if ImGui.IsItemHovered() and ImGui.IsMouseClicked(ImGuiMouseButton.Left) and not hasCursor then
                ctx.pickupFromSlot(item.bag, item.slot, "inv")
            end
        elseif worn then
            ImGui.Text((worn.item.name or entry.name or "") .. "  (worn)")
        else
            ctx.theme.TextMuted((entry.name or ("ID " .. tostring(entry.id))) .. "  (not in bags or worn)")
        end

        -- Clicky effect + cooldown state
        ImGui.TableNextColumn()
        local onCooldown = false
        local rowItem = item or (worn and worn.item)
        if rowItem then
            local cid = ctx.getItemSpellId(rowItem, "Clicky") or 0
            if cid > 0 then
                local spellName = ctx.getSpellName(cid) or "Unknown"
                local timerReady
                if item then
                    timerReady = ctx.getTimerReady(item.bag, item.slot)
                else
                    timerReady = ctx.getTimerReady(0, worn.slotIndex, "equipped")
                end
                onCooldown = (timerReady and timerReady > 0) or false
                if onCooldown then
                    ctx.theme.TextError(string.format("%s (%ds)", spellName, math.ceil(timerReady)))
                else
                    ctx.theme.TextSuccess(spellName)
                end
            else
                ctx.theme.TextMuted("no clicky")
            end
        else
            ctx.theme.TextMuted("-")
        end

        -- Use (right-click activate in-game; worn items activate from their slot)
        ImGui.TableNextColumn()
        local usable = rowItem ~= nil and not onCooldown
        ctx.theme.PushKeepButton(not usable)
        if ImGui.Button("Use", ImVec2(44, 0)) and usable then
            if item then
                mq.cmdf('/itemnotify in pack%d %d rightmouseup', item.bag, item.slot)
            else
                local slotName = ctx.getEquipmentSlotNameForItemNotify and ctx.getEquipmentSlotNameForItemNotify(worn.slotIndex)
                if slotName then mq.cmdf('/itemnotify %s rightmouseup', slotName) end
            end
        end
        ctx.theme.PopButtonColors()
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            if not rowItem then ImGui.Text("Item is not in your bags or worn.")
            elseif onCooldown then ImGui.Text("On cooldown.")
            elseif worn then ImGui.Text("Activate this worn item's clicky effect.")
            else ImGui.Text("Activate this item's clicky effect.") end
            ImGui.EndTooltip()
        end

        -- Remove from list
        ImGui.TableNextColumn()
        if ImGui.Button("Remove", ImVec2(58, 0)) then
            fav.removeItem(list.name, entry.id)
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Remove from this list (restores sell/delete once off ALL lists).")
            ImGui.EndTooltip()
        end

        ImGui.PopID()
    end
    ImGui.EndTable()
end

function FavoritesView.render(ctx)
    if not registry.shouldDraw("favorites") then return end
    local fav = ctx.favoritesService
    if not fav then return end

    local layoutConfig = ctx.layoutConfig
    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local ax = layoutConfig.FavoritesWindowX or 0
    local ay = layoutConfig.FavoritesWindowY or 0
    if ax ~= 0 or ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end
    local w = layoutConfig.WidthFavoritesPanel or FAVORITES_WINDOW_WIDTH
    local h = layoutConfig.HeightFavorites or FAVORITES_WINDOW_HEIGHT
    if w > 0 and h > 0 then
        -- Size floor (handoff item 6): band + table header + three rows - below this the
        -- 26px band stat is the first casualty.
        ImGui.SetNextWindowSizeConstraints(ImVec2(300, 220), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Clickies##ItemUIClickies", registry.isOpen("favorites"), windowFlags)
    registry.setWindowState("favorites", winOpen, winOpen)
    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end
    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    -- The kit band carries the pin in bars; the legacy checkbox row stays for classic.
    if not barsOn and ctx.renderWindowLock then ctx.renderWindowLock(ctx, "favorites") end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthFavoritesPanel = cw
            layoutConfig.HeightFavorites = ch
        end
    end
    local px, py = ImGui.GetWindowPos()
    if px and py then
        if not layoutConfig.FavoritesWindowX or math.abs(layoutConfig.FavoritesWindowX - px) > 1 or
           not layoutConfig.FavoritesWindowY or math.abs(layoutConfig.FavoritesWindowY - py) > 1 then
            layoutConfig.FavoritesWindowX = px
            layoutConfig.FavoritesWindowY = py
            ctx.scheduleLayoutSave()
        end
    end

    -- 19d: the shared band. The stat is what this window alone knows -- how much of your
    -- inventory these lists are holding safe. That protection is the whole reason the
    -- window exists (a listed item cannot be sold or destroyed), and no bar cell shows it.
    if barsOn then
        local lists = fav.getLists() or {}
        local protected = 0
        for _, l in ipairs(lists) do protected = protected + #(l.items or {}) end
        windowHeader.render({
            id = "favorites", title = "Clickies",
            stat = string.format("%d list%s . %d item%s protected",
                #lists, (#lists == 1) and "" or "s", protected, (protected == 1) and "" or "s"),
            lock = windowHeader.registryLock("favorites", ctx),
        })
    end

    -- List management row
    ImGui.SetNextItemWidth(160)
    newListName, _ = ImGui.InputText("##NewClickyList", newListName or "")
    ImGui.SameLine()
    if ImGui.Button("Create List") then
        if fav.createList(newListName) then
            newListName = ""
        else
            ctx.setStatusMessage("List name is empty or already exists.")
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.Text("Create a named clicky list (e.g. Buffs, Damage). Add items via right-click > Clicky Lists.")
        ImGui.Text("Items on any list are protected from selling and deleting until removed.")
        ImGui.EndTooltip()
    end

    local favLists = fav.getLists()
    if #favLists == 0 then
        ImGui.Spacing()
        ctx.theme.TextMuted("No lists yet. Create one above, then right-click items and use Clicky Lists.")
        ImGui.End()
        return
    end

    ImGui.Separator()
    if ImGui.BeginTabBar("ClickyListsTabs") then
        for _, list in ipairs(favLists) do
            if ImGui.BeginTabItem(string.format("%s (%d)###ClickyTab_%s", list.name, #list.items, list.name)) then
                if #list.items == 0 then
                    if ImGui.Button("Delete this list") then
                        fav.deleteList(list.name)
                        ImGui.EndTabItem()
                        break
                    end
                    ImGui.SameLine()
                end
                renderListRows(ctx, fav, list)
                ImGui.EndTabItem()
            end
        end
        ImGui.EndTabBar()
    end

    ImGui.End()
end

registry.register({
    id          = "favorites",
    zone        = "B1",  -- window_zones placement column/slot (mockup 10a)
    label       = "Clickies",
    buttonWidth = 55,
    tooltip     = "Your clicky lists: one-click item activation, with sell/delete protection for listed items",
    layoutKeys  = { x = "FavoritesWindowX", y = "FavoritesWindowY" },
    enableKey   = "ShowFavoritesWindow",
    render      = function(refs)
        local ctx = context.build()
        FavoritesView.render(ctx)
    end,
})

return FavoritesView
