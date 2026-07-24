--[[
    Native hover - CoOpt item tooltip over the game's OWN Inventory window.

    While the native Inventory window is open, hovering a worn equipment slot
    (InvSlot0..InvSlot22) shows the full CoOpt stats tooltip (same renderer as
    the Equipment Companion / Item Display), so MacroQuest-enriched data reads
    directly off the native UI.

    Detection: ${EverQuest.LastMouseOver} names the window under the cursor;
    a name matching InvSlot<N> is verified against the Inventory window's own
    child (MouseOver) so same-named controls elsewhere can't false-positive.
    Idle cost is one Window.Open check per frame while the tooltip is enabled;
    the slot pipeline only runs with the Inventory window open.

    v1 scope: worn slots only. Bag/bank slot contents are template-cloned
    controls without distinct names, so those need the plugin's help later.
--]]

local mq = require('mq')
require('ImGui')
local ItemTooltip = require('itemui.utils.item_tooltip')
local constants = require('itemui.constants')
local registry = require('itemui.core.registry')

local M = {}

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
    if uiState.nativeHoverTooltip == false then return end
    -- Never fight CoOpt's own ImGui tooltips: skip while the cursor is over ImGui.
    local overImGui = false
    pcall(function()
        local io = ImGui.GetIO and ImGui.GetIO()
        overImGui = (io and io.WantCaptureMouse) or false
    end)
    if overImGui then hover.key = nil; return end

    local idx = hoveredWornSlot()
    if not idx then hover.key = nil; return end
    local now = mq.gettime()

    -- Right-click on a worn slot: open the CoOpt Item Display for that slot
    -- instead of the native inspect (whose layout garbles on this server). We
    -- know the slot directly, so no DisplayItem TLO or window probing is needed;
    -- the native window that still pops is squashed by native_bridge via the
    -- nativeInspectSquashUntil flag.
    if uiState.nativeItemDisplayReplace == true and ImGui.IsMouseClicked(ImGuiMouseButton.Right) then
        local wornItem = ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip({ bag = 0, slot = idx, source = "equipped" }, "equipped")
        if wornItem and wornItem.name then
            -- Same call shape as the equipment context menu: a minimal loc table
            -- plus the "equipped" source, so the tab machinery does the full
            -- enrichment (augment slots, worn totals) itself.
            if ctx.addItemDisplayTab then
                ctx.addItemDisplayTab({ bag = 0, slot = idx, name = wornItem.name, type = wornItem.type }, "equipped")
            end
            if not registry.isOpen('itemDisplay') then registry.toggleWindow('itemDisplay') end
            uiState.nativeInspectSquashUntil = now + 1500
        end
    end

    local key = 'InvSlot' .. idx
    if hover.key ~= key then
        hover.key = key
        hover.since = now
        return
    end
    if (now - hover.since) < DWELL_MS then return end

    local it = mq.TLO.Me and mq.TLO.Me.Inventory and mq.TLO.Me.Inventory(idx)
    if not it or it() == nil then return end
    local okId, id = pcall(function() return it.ID() end)
    if not okId or not id or tonumber(id) == 0 then return end

    -- Same pipeline as the Equipment Companion's hover (stat prewarm + cache).
    local showItem = (ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip({ bag = 0, slot = idx, source = "equipped" }, "equipped")) or nil
    if not showItem or not showItem.name then return end
    local opts = { source = "equipped", bag = 0, slot = idx }
    local effects, tw, th = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
    opts.effects = effects
    ItemTooltip.beginItemTooltip(tw or (constants.UI and constants.UI.TOOLTIP_MIN_WIDTH) or 340, th or (constants.UI and constants.UI.TOOLTIP_MIN_HEIGHT) or 200)
    ImGui.Text("Stats")
    ImGui.Separator()
    ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
    ImGui.EndTooltip()
end

return M
