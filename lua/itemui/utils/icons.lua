--[[
    ItemUI - Icon Utilities
    EQ item icon texture loading and drawing.
    Part of CoOpt UI — EverQuest EMU Companion
--]]

local mq = require('mq')
require('ImGui')

local M = {}

local ITEM_ICON_OFFSET = 500
local ITEM_ICON_SIZE = 24
local itemIconTextureAnimation = nil

local function getItemIconTextureAnimation()
    if not itemIconTextureAnimation and mq.FindTextureAnimation then
        itemIconTextureAnimation = mq.FindTextureAnimation("A_DragItem")
    end
    return itemIconTextureAnimation
end

function M.drawItemIcon(iconId)
    local anim = getItemIconTextureAnimation()
    if not anim or not iconId or iconId == 0 then return end
    anim:SetTextureCell(iconId - ITEM_ICON_OFFSET)
    ImGui.DrawTextureAnimation(anim, ITEM_ICON_SIZE, ITEM_ICON_SIZE)
end

return M
