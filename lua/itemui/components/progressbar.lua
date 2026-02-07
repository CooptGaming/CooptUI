--[[
    Progress Bar Component
    
    Part of ItemUI Phase 7: View Extraction & Modularization
    Reusable progress bar rendering for macro operations (sell, loot, etc.)
--]]

local mq = require('mq')
require('ImGui')

local ProgressBar = {}

--[[
    Render a progress bar with optional label and percentage
    
    Parameters:
        fraction: number between 0.0 and 1.0 representing progress
        size: ImVec2 for size (e.g., ImVec2(200, 0) for 200px wide, auto height)
        overlay: optional text to display over the progress bar
        showPercentage: optional boolean, if true appends percentage to overlay (default: true)
    
    Example usage:
        ProgressBar.render(0.75, ImVec2(200, 0), "Selling items", true)
        -- Shows: "Selling items (75%)"
--]]
function ProgressBar.render(fraction, size, overlay, showPercentage)
    if showPercentage == nil then showPercentage = true end
    
    local displayText = overlay or ""
    if showPercentage and overlay then
        local pct = math.floor(fraction * 100 + 0.5)
        displayText = string.format("%s (%d%%)", overlay, pct)
    elseif showPercentage then
        local pct = math.floor(fraction * 100 + 0.5)
        displayText = string.format("%d%%", pct)
    end
    
    ImGui.ProgressBar(fraction, size, displayText)
end

--[[
    Render a progress bar with current/total counts
    
    Parameters:
        current: current progress count (e.g., items sold)
        total: total items to process
        size: ImVec2 for size
        label: optional label (e.g., "Selling items")
    
    Example usage:
        ProgressBar.renderCounted(15, 20, ImVec2(200, 0), "Items sold")
        -- Shows: "Items sold: 15 / 20 (75%)"
--]]
function ProgressBar.renderCounted(current, total, size, label)
    local fraction = (total > 0) and (current / total) or 0
    local pct = math.floor(fraction * 100 + 0.5)
    
    local displayText
    if label then
        displayText = string.format("%s: %d / %d (%d%%)", label, current, total, pct)
    else
        displayText = string.format("%d / %d (%d%%)", current, total, pct)
    end
    
    ImGui.ProgressBar(fraction, size, displayText)
end

--[[
    Render a progress bar with elapsed time
    
    Parameters:
        current: current progress count
        total: total items to process
        elapsedMs: elapsed time in milliseconds
        size: ImVec2 for size
        label: optional label
    
    Example usage:
        ProgressBar.renderTimed(15, 20, 5000, ImVec2(200, 0), "Selling")
        -- Shows: "Selling: 15 / 20 (75%) - 5.0s"
--]]
function ProgressBar.renderTimed(current, total, elapsedMs, size, label)
    local fraction = (total > 0) and (current / total) or 0
    local pct = math.floor(fraction * 100 + 0.5)
    local elapsedSec = elapsedMs / 1000
    
    local displayText
    if label then
        displayText = string.format("%s: %d / %d (%d%%) - %.1fs", label, current, total, pct, elapsedSec)
    else
        displayText = string.format("%d / %d (%d%%) - %.1fs", current, total, pct, elapsedSec)
    end
    
    ImGui.ProgressBar(fraction, size, displayText)
end

--[[
    Render a progress bar with time estimation
    
    Parameters:
        current: current progress count
        total: total items to process
        elapsedMs: elapsed time in milliseconds
        size: ImVec2 for size
        label: optional label
    
    Example usage:
        ProgressBar.renderWithETA(15, 20, 5000, ImVec2(200, 0), "Selling")
        -- Shows: "Selling: 15 / 20 (75%) - ETA: 1.7s"
--]]
function ProgressBar.renderWithETA(current, total, elapsedMs, size, label)
    local fraction = (total > 0) and (current / total) or 0
    local pct = math.floor(fraction * 100 + 0.5)
    
    -- Calculate ETA
    local eta = 0
    if current > 0 and current < total then
        local avgTimePerItem = elapsedMs / current
        local remaining = total - current
        eta = (avgTimePerItem * remaining) / 1000  -- convert to seconds
    end
    
    local displayText
    if label then
        if eta > 0 then
            displayText = string.format("%s: %d / %d (%d%%) - ETA: %.1fs", label, current, total, pct, eta)
        else
            displayText = string.format("%s: %d / %d (%d%%)", label, current, total, pct)
        end
    else
        if eta > 0 then
            displayText = string.format("%d / %d (%d%%) - ETA: %.1fs", current, total, pct, eta)
        else
            displayText = string.format("%d / %d (%d%%)", current, total, pct)
        end
    end
    
    ImGui.ProgressBar(fraction, size, displayText)
end

--[[
    Render an indeterminate progress bar (spinning/pulsing effect)
    Useful when total count is unknown
    
    Parameters:
        size: ImVec2 for size
        label: optional label
    
    Example usage:
        ProgressBar.renderIndeterminate(ImVec2(200, 0), "Processing...")
        -- Shows: "Processing..." with animated progress bar
--]]
function ProgressBar.renderIndeterminate(size, label)
    -- Create pulsing effect using time
    local time = mq.gettime() / 1000  -- convert to seconds
    local fraction = (math.sin(time * 2) + 1) / 2  -- oscillate between 0 and 1
    
    local displayText = label or "Processing..."
    ImGui.ProgressBar(fraction, size, displayText)
end

--[[
    Render a simple spinner (no progress bar)
    Useful for very quick operations or when space is limited
    
    Parameters:
        radius: spinner radius in pixels (default: 8)
        thickness: spinner line thickness (default: 2)
    
    Example usage:
        ProgressBar.renderSpinner(10, 3)
--]]
function ProgressBar.renderSpinner(radius, thickness)
    radius = radius or 8
    thickness = thickness or 2
    
    -- Get current time for animation
    local time = mq.gettime() / 1000
    local angle = time * 4  -- rotation speed
    
    local pos = ImGui.GetCursorScreenPosVec()
    local centerX = pos.x + radius
    local centerY = pos.y + radius
    
    -- Draw arc (simplified - full circle for now, could be enhanced)
    local drawList = ImGui.GetWindowDrawList()
    if drawList then
        local color = ImGui.GetColorU32(ImVec4(0.4, 0.75, 0.4, 1))
        -- ImGui.ImDrawList.AddCircle(drawList, ImVec2(centerX, centerY), radius, color, 12, thickness)
        -- Note: MQ2's ImGui binding may not have AddCircle, fallback to ProgressBar
        ImGui.ProgressBar(0.0, ImVec2(radius * 2, radius * 2), "")
    end
    
    -- Reserve space for spinner
    ImGui.Dummy(ImVec2(radius * 2, radius * 2))
end

return ProgressBar
