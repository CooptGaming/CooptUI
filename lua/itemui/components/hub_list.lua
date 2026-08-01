--[[
    hub_list.lua — the launcher list, once (23c).

    "Hub is the same list in vertical form with the shortcut for each... nothing in it is
    a duplicate of a launcher, it is the same launcher in a form you can read."

    That only stays true if there is ONE list. Two surfaces draw it — the command bar's
    Hub menu and the status bar's CoOpt panel — and if each owned its own copy they would
    drift the first time a window was added. So the entries and the row engine live here,
    and each bar contributes only its own window shell (anchoring, hover grace, pinning),
    which is genuinely different between them.

    REQUIRE DIRECTION MATTERS: this module takes `queue` as an ARGUMENT rather than
    requiring views/dock_top for it. dock_bottom already requires dock_top, so a
    dock_top -> hub_list -> dock_top require would close a cycle. It also registers
    nothing, which is what makes it safe to require at the top of a view (a view module's
    require-time registration order IS launcher-button order).
]]

local theme = require('itemui.utils.theme')
local registry = require('itemui.core.registry')
local keybinds = require('itemui.utils.keybinds')
require('ImGui')

local M = {}

--- The list itself. Both surfaces render exactly this.
M.ENTRIES = {
            { kind = "header", label = "ITEMS" },
            { kind = "hub",    label = "Bags" },
            { kind = "module", id = "bank" },
            { kind = "pair",   ids = { "itemDisplay", "augmentUtility" } },
            { kind = "module", id = "mythicals" },
            { kind = "module", id = "reroll" },
            { kind = "module", id = "favorites" },
            { kind = "header", label = "CHARACTER" },
            { kind = "module", id = "equipment" },
            { kind = "module", id = "effects" },
            { kind = "module", id = "aa" },
            -- Phase 15: a registry module now (views/script_tracker.lua), so it lights,
            -- toggles and Esc-closes like everything else — no more /lua run sidecar
            -- from the bars (the standalone script remains for classic/CC).
            { kind = "module", id = "scripttracker" },
            { kind = "header", label = "LAYOUTS" },
            { kind = "layouts_dynamic" },
        }

--- Label for a module entry, straight from the registry so it cannot drift from the hub's.
function M.moduleLabel(id)
    for _, mod in ipairs(registry.getEnabledModules()) do
        if mod.id == id then return mod.label or id end
    end
    return nil
end

-- Lazy requires (same reason as inventory.lua's bankView): both modules register
-- themselves at require time, and a top-level require here would move their registry
-- slot. By first bar frame app.lua has loaded them, so these are table lookups.
local ItemDisplayViewLazy, TooltipDataLazy
local function itemDisplayView()
    ItemDisplayViewLazy = ItemDisplayViewLazy or require('itemui.views.item_display')
    return ItemDisplayViewLazy
end
local function tooltipData()
    TooltipDataLazy = TooltipDataLazy or require('itemui.utils.tooltip_data')
    return TooltipDataLazy
end

--- 23c's pill: empty aug sockets on the item currently in Item Display. PEEK ONLY —
--- reads the tooltip cache entry ID's own render already built; a cache miss is nil (no
--- pill), never a TLO walk. The bar must stay read-cheap every frame.
function M.pairPillCount()
    local ok, n = pcall(function()
        local st = itemDisplayView().getState()
        local tabs = st.itemDisplayTabs or {}
        local idx = st.itemDisplayActiveTabIndex or 1
        local tab = tabs[idx]
        if not tab or not tab.item then return nil end
        local entry = tooltipData().getCachedTooltipEntry(tab.item,
            { source = tab.source, bag = tab.bag, slot = tab.slot })
        local lines = entry and entry.augLines
        if type(lines) ~= "table" then return nil end  -- augLines caches `false` for "none"
        local count = 0
        for _, l in ipairs(lines) do
            if l and l.augName == "empty" then count = count + 1 end
        end
        return count
    end)
    if not ok or not n or n <= 0 then return nil end
    return n
end

--- The Item Display + Aug Utility pair (23c): halves resolve through the registry, the
--- pair exists only when BOTH are enabled, and it opens/closes as a unit — "the open pair
--- lights the whole chip, because they travel together".
function M.pairModules()
    local a, b = M.moduleLabel("itemDisplay"), M.moduleLabel("augmentUtility")
    if a and b then return a, b end
    return nil, nil
end

function M.pairOpen()
    return (registry.isOpen("itemDisplay") or registry.isOpen("augmentUtility")) == true
end

--- Open both halves, or close both when the pair is already open. Queued, never a direct
--- registry write from the render callback.
local function togglePair(queue, ctx)
    if M.pairOpen() then
        -- Close whichever halves are open (toggle only the open ones).
        if registry.isOpen("itemDisplay") then
            queue(ctx, { kind = "window", id = "itemDisplay", toggle = true })
        end
        if registry.isOpen("augmentUtility") then
            queue(ctx, { kind = "window", id = "augmentUtility", toggle = true })
        end
    else
        -- Idempotent opens (non-toggle) for both.
        queue(ctx, { kind = "window", id = "itemDisplay" })
        queue(ctx, { kind = "window", id = "augmentUtility" })
    end
end

--- Is the hub (Bags) on screen? Bank is its OWN window again (the merge was rolled back),
--- so an open Bank must not light the Bags half — each half lights for its own window.
function M.hubOpen(ctx)
    local f = ctx and ctx.getShouldDraw
    return (f and f()) == true
end

-- 23c: "Hub is the same list in vertical form WITH THE SHORTCUT FOR EACH". Drawn at a
-- fixed column rather than a measured right-align on purpose — this menu is
-- AlwaysAutoResize, so GetWindowWidth reports LAST frame's width and a width-derived
-- offset oscillates as rows come and go. Every popover in dock_top uses fixed columns for
-- the same reason. Only draws when the bind actually exists: advertising a key that does
-- nothing is the dishonesty the bars already refuse elsewhere.
local SHORTCUT_COL = 250

local function shortcutHint(bindId)
    local combo = keybinds.display(bindId)
    if not combo then return end
    ImGui.SameLine(SHORTCUT_COL)
    if theme.TextFurniture then theme.TextFurniture(combo) else theme.TextMuted(combo) end
end

function M.drawEntries(entries, ctx, s, queue)
    local drew = false
    for _, e in ipairs(entries) do
        if e.kind == "module" then
            -- The Loot window is uiState-managed rather than registry-registered, so it needs
            -- its own label; everything else takes the registry's.
            local label = (e.id == "loot") and "Loot" or M.moduleLabel(e.id)
            if label then
                drew = true
                local open = (e.id == "loot") and (ctx.uiState and ctx.uiState.lootUIOpen) or registry.isOpen(e.id)
                if open then
                    -- Lit = already open. Clicking again closes it.
                    ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header))
                end
                -- toggle: the entry is lit when open and says so, so clicking it again has to
                -- actually close the window. The status bar's buttons omit this flag on
                -- purpose -- clicking "Rules" twice should not close Settings.
                -- Selectable returns (selected, pressed) in this binding -- SELECTED first
                -- (lua_ImGuiWidgets.cpp:906). Testing the first return with `open` passed in
                -- meant every lit entry queued a close-toggle EVERY FRAME the menu was
                -- visible, slamming its window shut the moment the menu opened.
                local _, pressed = ImGui.Selectable(label .. "##dockmenu_" .. e.id, open == true)
                if pressed then
                    queue(ctx, { kind = "window", id = e.id, toggle = true })
                end
                shortcutHint(e.id)
                if open then ImGui.PopStyleColor() end
            end

        elseif e.kind == "hub" then
            drew = true
            local lit = M.hubOpen(ctx)
            if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
            -- Selectable returns (selected, pressed) — read the SECOND (see the module
            -- branch above for the bug the first return caused).
            local _, pressedHub = ImGui.Selectable(e.label .. "##dockmenu_hub", lit)
            if pressedHub then
                queue(ctx, { kind = "hub" })
            end
            shortcutHint("inventory")
            if lit then ImGui.PopStyleColor() end

        elseif e.kind == "header" then
            -- 23c group label: furniture, not a row. Never counts as `drew` on its own —
            -- a menu of nothing but headers is still "Nothing enabled here."
            if theme.TextFurniture then theme.TextFurniture(e.label) else theme.TextMuted(e.label) end

        elseif e.kind == "pair" then
            -- Item Display + Aug Utility as one row that travels together (23c). Only
            -- offered when both halves are enabled; the pill is the empty-socket count on
            -- ID's current subject, peeked from the tooltip cache.
            local a, b = M.pairModules()
            if a and b then
                drew = true
                local lit = M.pairOpen()
                local label = a .. " + " .. b
                local pill = M.pairPillCount()
                if pill then label = string.format("%s  %d", label, pill) end
                if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
                local _, pressedPair = ImGui.Selectable(label .. "##dockmenu_pair_idau", lit)
                if pressedPair then
                    togglePair(queue, ctx)
                end
                shortcutHint("pair_idau")
                if lit then ImGui.PopStyleColor() end
            end

        elseif e.kind == "scripttracker" then
            drew = true
            if ImGui.Selectable(e.label .. "##dockmenu_st") then
                queue(ctx, { kind = "scripttracker" })
            end

        elseif e.kind == "native" then
            drew = true
            -- These are game windows opened through MQ, not CoOpt windows. The bar is the one
            -- place that launches both kinds; there is no open/closed state to light, because
            -- MQ only gives us DoOpen.
            if ImGui.Selectable(e.label .. "##dockmenu_" .. e.window) then
                queue(ctx, { kind = "native", window = e.window })
            end

        elseif e.kind == "loot_all" then
            drew = true
            if ImGui.Selectable("Loot All##dockmenu_lootall") then
                queue(ctx, { kind = "loot_all" })
            end

        elseif e.kind == "loot_stop" then
            -- A verb only appears when it works: Stop exists only while something runs.
            if s.lootRunning or s.sellRunning then
                drew = true
                if ImGui.Selectable("Stop##dockmenu_stop") then
                    queue(ctx, { kind = s.lootRunning and "loot_stop" or "sell_stop" })
                end
            end

        elseif e.kind == "auto_sell" then
            drew = true
            -- Greyed until a merchant is open, and it says why. No dialog ever tells you to
            -- "open a merchant first" after you have already clicked.
            if s.merchantOpen then
                if ImGui.Selectable("Auto Sell##dockmenu_autosell") then
                    queue(ctx, { kind = "auto_sell" })
                end
            else
                theme.TextMuted("Auto Sell - no merchant")
            end

        elseif e.kind == "layouts_dynamic" then
            drew = true
            local lc = ctx.layoutConfig or {}
            local active = tostring(lc.LayoutPreset or "")
            local names = (ctx.uiState and ctx.uiState.dockPresetNames) or {}
            if active ~= "" then
                theme.TextMuted("layout: " .. active)
            else
                theme.TextMuted("layout: (none)")
            end
            if #names == 0 then
                theme.TextMuted("No presets yet.")
            end
            for presetIdx, name in ipairs(names) do
                local lit = (name == active)
                if lit then ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Header)) end
                local _, pressed = ImGui.Selectable(name .. "##dockpreset_" .. name, lit)
                if pressed then
                    queue(ctx, { kind = "preset", name = name })
                end
                -- Positional: the Nth preset carries the Nth F-key. Drawing it HERE, beside
                -- the name, is what makes a delete-induced shift visible rather than silent.
                if presetIdx <= 3 then shortcutHint("preset" .. presetIdx) end
                if lit then ImGui.PopStyleColor() end
            end
            ImGui.Separator()
            if ImGui.Selectable("Re-tidy now##dockmenu_retidy") then
                queue(ctx, { kind = "retidy" })
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Puts every open window back into its zone and forgets hand-placed positions.")
                ImGui.EndTooltip()
            end
            if ImGui.Selectable("Save current as...##dockmenu_presetsave") and ctx.uiState then
                ctx.uiState.dockPresetSavePrompt = true
            end
        end
    end
    if not drew then theme.TextMuted("Nothing enabled here.") end
end

return M
