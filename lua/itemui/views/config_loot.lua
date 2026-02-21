--[[
    Config Loot Rules tab - Always loot, Skip (never loot) lists.
    Part of ItemUI config view split (Task 07).
--]]

require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')

local ConfigLoot = {}

function ConfigLoot.render(ctx)
    ConfigFilters.renderBreadcrumb(ctx, "Loot Rules", "Item lists")
    ImGui.Spacing()
    ImGui.TextColored(ctx.theme.ToVec4(ctx.theme.Colors.Muted), "Always loot, Skip (never loot). Options are in General > Loot.")
    ImGui.Spacing()
    ConfigFilters.renderFiltersSection(ctx, 3, false)
end

return ConfigLoot
