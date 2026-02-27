--[[
    Config filters - Shared filter list infrastructure for Sell, Loot, and Shared (Valuable) tabs.
    Facade: delegates to config_filters_targets, config_filters_actions, config_filters_ui.
    Used by config_sell.lua, config_loot.lua, config_shared.lua. Exports refresh(ctx) and renderFiltersSection(ctx, forcedSubTab, showTabs).
    Part of Task 6.3: config_filters split.
--]]

local targets = require('itemui.views.config_filters_targets')
local ui = require('itemui.views.config_filters_ui')

local ConfigFilters = {}

function ConfigFilters.refresh(ctx)
    targets.refresh(ctx)
end

ConfigFilters.renderBreadcrumb = ui.renderBreadcrumb
ConfigFilters.classLabel = ui.classLabel
ConfigFilters.loadDefaultProtectList = ui.loadDefaultProtectList

function ConfigFilters.renderFiltersSection(ctx, forcedSubTab, showTabs)
    targets.refresh(ctx)
    ui.renderFiltersSection(ctx, forcedSubTab, showTabs)
end

return ConfigFilters
