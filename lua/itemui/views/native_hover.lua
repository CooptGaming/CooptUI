--[[
    Native hover - CoOpt item tooltip over the game's OWN windows.

    Hovering a native item slot shows the full CoOpt stats tooltip (same
    renderer as the companions / Item Display), so MacroQuest-enriched data
    reads directly off the native UI.

    Slot detection has two tiers:
      - MQ2CoOptUI window API present: EVERY real inv slot resolves - worn,
        bag, and bank contents - via plugin.window.getMouseOverSlot(), which
        reads CInvSlotMgr directly. Bag/bank slot windows are nameless
        template clones (invisible to the Window TLO), but each is registered
        with the slot manager and carries its item location.
      - Fallback (no plugin): worn slots only. ${EverQuest.LastMouseOver}
        names the window under the cursor; a name matching InvSlot<N> is
        verified against the Inventory window's own child (MouseOver) so
        same-named controls elsewhere can't false-positive.

    Also hosts the equipped-inspect redirect (right-click a worn slot opens
    the CoOpt Item Display; native_bridge squashes the native window). The
    tooltip (nativeHoverTooltip) and the redirect (nativeItemDisplayReplace)
    are independent toggles - either works with the other disabled. The
    redirect stays worn-only: bag items belong to the Inventory Companion.
--]]

local mq = require('mq')
require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')
local registry = require('itemui.core.registry')
local coopuiPlugin = require('itemui.utils.coopui_plugin')

local M = {}

-- One-shot capability detection (same pattern as the plugin loader).
local pwCache
local function plugWindow()
    if pwCache ~= nil then return pwCache or nil end
    local w = coopuiPlugin.getWindow()
    pwCache = (w and type(w.getMouseOverSlot) == 'function') and w or false
    return pwCache or nil
end

local DWELL_MS = 250
local hover = { key = nil, since = 0 }

local function hoveredWornSlot()
    local w = mq.TLO and mq.TLO.Window and mq.TLO.Window('InventoryWindow')
    if not w or w() == nil or not (w.Open and w.Open()) then return nil end
    local eq = mq.TLO.EverQuest
    local lm = eq and eq.LastMouseOver
    if not lm or lm() == nil then return nil end
    local ok, name = pcall(function() return lm.Name() end)
    if not ok or type(name) ~= 'string' then return nil end
    local idxStr = name:match('^InvSlot(%d+)$')
    if not idxStr then return nil end
    local idx = tonumber(idxStr)
    if not idx or idx > 22 then return nil end
    local c = w.Child and w.Child(name)
    if not c then return nil end
    local okOver, over = pcall(function() return c.MouseOver() end)
    if not okOver or over ~= true then return nil end
    return idx
end

function M.render(ctx)
    local uiState = ctx.uiState
    -- Two independent features share the worn-slot detection: the hover stats
    -- tooltip and the inspect redirect. Each honors only its own toggle -
    -- turning tooltips off must not silently kill the redirect (or vice versa).
    local tooltipOn = uiState.nativeHoverTooltip ~= false
    local redirectOn = uiState.nativeItemDisplayReplace == true
    if not tooltipOn and not redirectOn then return end
    -- Never fight CoOpt's own ImGui tooltips: skip while the cursor is over ImGui.
    local overImGui = false
    pcall(function()
        local io = ImGui.GetIO and ImGui.GetIO()
        overImGui = (io and io.WantCaptureMouse) or false
    end)
    if overImGui then hover.key = nil; return end
    local now = mq.gettime()

    -- Resolve the hovered native slot to (source, bag, slot). Plugin tier:
    -- worn + bags + bank. Fallback tier: worn only. Top-level inv/bank slots
    -- (slot 0: loose items, the bags themselves) can't resolve through the
    -- item TLO pipeline, so they are skipped.
    local src, bag, slotIdx
    local pw = plugWindow()
    if pw then
        local s = pw.getMouseOverSlot()
        if s and s.source then
            if s.source == "equipped" then
                src, bag, slotIdx = "equipped", 0, s.slot
            elseif (s.slot or 0) > 0 then
                src, bag, slotIdx = s.source, s.bag, s.slot
            end
        end
    else
        local idx = hoveredWornSlot()
        if idx then src, bag, slotIdx = "equipped", 0, idx end
    end
    if not src then hover.key = nil; return end

    -- Right-click on a worn slot: open the CoOpt Item Display for that slot
    -- instead of the native inspect (whose layout garbles on this server). We
    -- know the slot directly, so no DisplayItem TLO or window probing is needed;
    -- the native window that still pops is squashed by native_bridge via the
    -- nativeInspectSquashUntil flag.
    if redirectOn and src == "equipped" and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
        local wornItem = ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip({ bag = 0, slot = slotIdx, source = "equipped" }, "equipped")
        if wornItem and wornItem.name then
            -- Same call shape as the equipment context menu: a minimal loc table
            -- plus the "equipped" source, so the tab machinery does the full
            -- enrichment (augment slots, worn totals) itself.
            if ctx.addItemDisplayTab then
                ctx.addItemDisplayTab({ bag = 0, slot = slotIdx, name = wornItem.name, type = wornItem.type }, "equipped")
            end
            if not registry.isOpen('itemDisplay') then registry.toggleWindow('itemDisplay') end
            uiState.nativeInspectSquashUntil = now + 1500
        end
    end
    if not tooltipOn then hover.key = nil; return end

    local key = src .. '_' .. tostring(bag) .. '_' .. tostring(slotIdx)
    if hover.key ~= key then
        hover.key = key
        hover.since = now
        return
    end
    if (now - hover.since) < DWELL_MS then return end

    -- Same pipeline as the companions' hover (stat prewarm + cache). An empty
    -- or unresolvable slot yields no name and renders nothing.
    local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip({ bag = bag, slot = slotIdx, source = src }, src)) or nil
    if not showItem or not showItem.name then return end
    local opts = { source = src, bag = bag, slot = slotIdx }
    local effects, tw, th = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
    opts.effects = effects
    ItemTooltip.beginItemTooltip(tw or (constants.UI and constants.UI.TOOLTIP_MIN_WIDTH) or 340, th or (constants.UI and constants.UI.TOOLTIP_MIN_HEIGHT) or 200)
    ImGui.Text("Stats")
    ImGui.Separator()
    ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
    ImGui.EndTooltip()
end

return M
