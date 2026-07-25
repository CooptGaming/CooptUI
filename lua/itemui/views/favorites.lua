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

local FavoritesView = {}

local FAVORITES_WINDOW_WIDTH = 460
local FAVORITES_WINDOW_HEIGHT = 380

local newListName = ""
-- id -> live inventory item, rebuilt when the inventory scan changes identity.
local invCache = { key = nil, byId = {} }

local function getInvById(ctx)
    local invItems = ctx.inventoryItems or {}
    local key = string.format("%d|%s", #invItems, tostring(invItems[1]))
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

local function renderListRows(ctx, fav, list)
    local invById = getInvById(ctx)
    local hasCursor = ctx.hasItemOnCursor()
    if #list.items == 0 then
        ctx.theme.TextMuted("Empty. Right-click an item in the Inventory Companion and use Clicky Lists > " .. list.name .. ".")
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
        ImGui.TableNextRow()
        ImGui.PushID("clicky_" .. list.name .. "_" .. tostring(entry.id) .. "_" .. i)

        -- Icon (hover = full stats when the item is in bags)
        ImGui.TableNextColumn()
        if item and ctx.drawItemIcon then
            ctx.drawItemIcon(item.icon)
            if ImGui.IsItemHovered() then
                local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(item, "inv")) or item
                local opts = { source = "inv", bag = item.bag, slot = item.slot }
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
        else
            ctx.theme.TextMuted((entry.name or ("ID " .. tostring(entry.id))) .. "  (not in bags)")
        end

        -- Clicky effect + cooldown state
        ImGui.TableNextColumn()
        local onCooldown = false
        if item then
            local cid = ctx.getItemSpellId(item, "Clicky") or 0
            if cid > 0 then
                local spellName = ctx.getSpellName(cid) or "Unknown"
                local timerReady = ctx.getTimerReady(item.bag, item.slot)
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

        -- Use (right-click activate in-game)
        ImGui.TableNextColumn()
        local usable = item ~= nil and not onCooldown
        ctx.theme.PushKeepButton(not usable)
        if ImGui.Button("Use", ImVec2(44, 0)) and usable then
            mq.cmdf('/itemnotify in pack%d %d rightmouseup', item.bag, item.slot)
        end
        ctx.theme.PopButtonColors()
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            if not item then ImGui.Text("Item is not in your bags.")
            elseif onCooldown then ImGui.Text("On cooldown.")
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
    if ax ~= 0 and ay ~= 0 then
        ImGui.SetNextWindowPos(ImVec2(ax, ay), condPos)
    end
    local w = layoutConfig.WidthFavoritesPanel or FAVORITES_WINDOW_WIDTH
    local h = layoutConfig.HeightFavorites or FAVORITES_WINDOW_HEIGHT
    if w > 0 and h > 0 then
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
            ctx.flushLayoutSave()
        end
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
