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

--- Draw item icon at given size (default 24). Used for tooltip header (larger) and socket rows (24).
function M.drawItemIcon(iconId, size)
    local anim = getItemIconTextureAnimation()
    if not anim or not iconId or iconId == 0 then return end
    local s = (type(size) == "number" and size > 0) and size or ITEM_ICON_SIZE
    anim:SetTextureCell(iconId - ITEM_ICON_OFFSET)
    ImGui.DrawTextureAnimation(anim, s, s)
end

--- Reserve 24x24 space and draw a dark grey filled square for empty sockets (visible on black tooltip background).
--- Draw-list call wrapped in pcall; falls back to Dummy-only if binding lacks AddRectFilled.
function M.drawEmptySlotIcon()
    ImGui.Dummy(ImVec2(ITEM_ICON_SIZE, ITEM_ICON_SIZE))
    pcall(function()
        local drawList = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
        if not drawList then return end
        local minV = ImGui.GetItemRectMin and ImGui.GetItemRectMin()
        local maxV = ImGui.GetItemRectMax and ImGui.GetItemRectMax()
        if not minV or not maxV then return end
        local color = ImGui.GetColorU32 and ImGui.GetColorU32(ImVec4(0.22, 0.22, 0.25, 0.95))
        if not color then color = 0xFF38383F end
        if drawList.AddRectFilled then
            drawList.AddRectFilled(minV, maxV, color)
        elseif drawList.add_rect_filled then
            drawList.add_rect_filled(minV, maxV, color)
        end
    end)
end

return M
