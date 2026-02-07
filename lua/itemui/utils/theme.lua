--[[
    Theme & Styling Utilities
    
    Part of ItemUI Phase 7: View Extraction & Modularization
    Centralizes all ImGui colors, styles, and theming for consistent look & feel
    Designed to be shareable with other UIs (BoxHUD, etc.)
--]]

local Theme = {}

-- ============================================================================
-- Color Palette
-- ============================================================================

Theme.Colors = {
    -- Primary UI colors
    Header = {0.4, 0.8, 1, 1},
    HeaderAlt = {0.85, 0.85, 0.7, 1},
    
    -- Status colors
    Success = {0.4, 0.9, 0.4, 1},
    Warning = {0.9, 0.7, 0.2, 1},
    Error = {0.9, 0.5, 0.4, 1},
    EpicQuest = {0.75, 0.45, 0.95, 1},  -- purple for epic quest item status
    Info = {0.6, 0.85, 0.6, 1},
    Muted = {0.6, 0.6, 0.6, 1},
    
    -- Stat colors
    HP = {0.9, 0.3, 0.3, 1},
    MP = {0.3, 0.5, 0.9, 1},
    EN = {0.5, 0.7, 0.3, 1},
    AC = {0.8, 0.6, 0.2, 1},
    ATK = {0.8, 0.6, 0.2, 1},
    Haste = {0.6, 0.8, 0.6, 1},
    Speed = {0.6, 0.8, 0.6, 1},
    
    -- Action button colors
    Loot = {
        Normal = {0.2, 0.6, 0.2, 1},
        Hover = {0.3, 0.75, 0.3, 1},
        Active = {0.15, 0.5, 0.15, 1}
    },
    
    Skip = {
        Normal = {0.6, 0.2, 0.2, 1},
        Hover = {0.75, 0.3, 0.3, 1},
        Active = {0.5, 0.15, 0.15, 1}
    },
    
    Delete = {
        Normal = {0.8, 0.2, 0.2, 1},
        Hover = {0.9, 0.3, 0.3, 1},
        Active = {0.7, 0.1, 0.1, 1}
    },
    
    Keep = {
        Normal = {0.2, 0.7, 0.2, 1},
        Hover = {0.3, 0.8, 0.3, 1},
        Active = {0.1, 0.6, 0.1, 1},
        Disabled = {0.3, 0.5, 0.3, 1},
        DisabledHover = {0.4, 0.6, 0.4, 1},
        DisabledActive = {0.2, 0.4, 0.2, 1}
    },
    
    Junk = {
        Normal = {0.9, 0.6, 0.1, 1},
        Hover = {1, 0.7, 0.2, 1},
        Active = {0.8, 0.5, 0, 1},
        Disabled = {0.6, 0.5, 0.3, 1},
        DisabledHover = {0.7, 0.6, 0.4, 1},
        DisabledActive = {0.5, 0.4, 0.2, 1}
    },
    
    -- Progress bar colors
    Progress = {
        Background = {0.2, 0.35, 0.2, 0.6},
        Fill = {0.4, 0.75, 0.4, 1}
    }
}

-- ============================================================================
-- Helper Functions
-- ============================================================================

-- Convert color table to ImVec4
function Theme.ToVec4(color)
    if type(color) == "table" and #color == 4 then
        return ImVec4(color[1], color[2], color[3], color[4])
    end
    return ImVec4(1, 1, 1, 1)  -- fallback white
end

-- Push colored button style (3 colors: normal, hover, active)
function Theme.PushButtonColors(normalColor, hoverColor, activeColor)
    ImGui.PushStyleColor(ImGuiCol.Button, Theme.ToVec4(normalColor))
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, Theme.ToVec4(hoverColor))
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, Theme.ToVec4(activeColor))
end

-- Pop button colors (pops 3 style colors)
function Theme.PopButtonColors()
    ImGui.PopStyleColor(3)
end

-- ============================================================================
-- Pre-configured Button Styles
-- ============================================================================

function Theme.PushLootButton()
    Theme.PushButtonColors(Theme.Colors.Loot.Normal, Theme.Colors.Loot.Hover, Theme.Colors.Loot.Active)
end

function Theme.PushSkipButton()
    Theme.PushButtonColors(Theme.Colors.Skip.Normal, Theme.Colors.Skip.Hover, Theme.Colors.Skip.Active)
end

function Theme.PushDeleteButton()
    Theme.PushButtonColors(Theme.Colors.Delete.Normal, Theme.Colors.Delete.Hover, Theme.Colors.Delete.Active)
end

function Theme.PushKeepButton(disabled)
    if disabled then
        Theme.PushButtonColors(Theme.Colors.Keep.Disabled, Theme.Colors.Keep.DisabledHover, Theme.Colors.Keep.DisabledActive)
    else
        Theme.PushButtonColors(Theme.Colors.Keep.Normal, Theme.Colors.Keep.Hover, Theme.Colors.Keep.Active)
    end
end

function Theme.PushJunkButton(disabled)
    if disabled then
        Theme.PushButtonColors(Theme.Colors.Junk.Disabled, Theme.Colors.Junk.DisabledHover, Theme.Colors.Junk.DisabledActive)
    else
        Theme.PushButtonColors(Theme.Colors.Junk.Normal, Theme.Colors.Junk.Hover, Theme.Colors.Junk.Active)
    end
end

-- ============================================================================
-- Progress Bar Styling
-- ============================================================================

function Theme.PushProgressBarColors()
    ImGui.PushStyleColor(ImGuiCol.FrameBg, Theme.ToVec4(Theme.Colors.Progress.Background))
    ImGui.PushStyleColor(ImGuiCol.PlotHistogram, Theme.ToVec4(Theme.Colors.Progress.Fill))
end

function Theme.PopProgressBarColors()
    ImGui.PopStyleColor(2)
end

-- ============================================================================
-- Text Coloring Helpers
-- ============================================================================

function Theme.TextHeader(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Header), text)
end

function Theme.TextHeaderAlt(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.HeaderAlt), text)
end

function Theme.TextSuccess(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Success), text)
end

function Theme.TextWarning(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Warning), text)
end

function Theme.TextError(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Error), text)
end

function Theme.TextInfo(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Info), text)
end

function Theme.TextMuted(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Muted), text)
end

-- ============================================================================
-- Stat Display Helpers
-- ============================================================================

function Theme.TextHP(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.HP), text)
end

function Theme.TextMP(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.MP), text)
end

function Theme.TextEN(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.EN), text)
end

function Theme.TextAC(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.AC), text)
end

function Theme.TextATK(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.ATK), text)
end

function Theme.TextHaste(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Haste), text)
end

function Theme.TextSpeed(text)
    ImGui.TextColored(Theme.ToVec4(Theme.Colors.Speed), text)
end

-- ============================================================================
-- Future: Theme System
-- ============================================================================

-- Placeholder for future theme switching
-- Theme.Current = "Default"
-- Theme.Themes = {
--     Default = { ... },
--     Dark = { ... },
--     HighContrast = { ... }
-- }
-- 
-- function Theme.SetTheme(themeName)
--     if Theme.Themes[themeName] then
--         Theme.Current = themeName
--         -- Apply theme colors
--     end
-- end

return Theme
