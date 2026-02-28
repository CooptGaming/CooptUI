--[[
    Advanced tab for CoOpt UI Settings: Debug channel toggles (Task 8.1), Backup & Restore (Task 8.3).
]]

require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')
local debugModule = require('itemui.core.debug')
local backupService = require('itemui.services.backup_service')

local ConfigAdvanced = {}
local state = {
    exportPath = "",
    importPath = "",
    importPreview = nil,
    importConfirmOpen = false,
}

function ConfigAdvanced.render(ctx)
    local theme = ctx.theme
    local setStatusMessage = ctx.setStatusMessage or function() end
    local renderBreadcrumb = function(tab, section) ConfigFilters.renderBreadcrumb(ctx, tab, section) end

    ImGui.Spacing()
    renderBreadcrumb("Advanced", "Overview")
    if ImGui.CollapsingHeader("Debug channels", ImGuiTreeNodeFlags.DefaultOpen) then
        renderBreadcrumb("Advanced", "Debug channels")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Enable debug channels to see runtime messages in the console and in logs/coopui_debug.log (rotates at 1MB). Default: all off.")
        ImGui.Spacing()
        for _, name in ipairs(debugModule.knownChannels or {}) do
            local enabled = debugModule.isChannelEnabled(name)
            local prev = enabled
            enabled = ImGui.Checkbox("Debug: " .. name .. "##Debug" .. name, enabled)
            if prev ~= enabled then
                debugModule.setChannelEnabled(name, enabled)
            end
        end
    end

    if ImGui.CollapsingHeader("Backup & Restore", ImGuiTreeNodeFlags.None) then
        renderBreadcrumb("Advanced", "Backup & Restore")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Export all CoOpt UI settings (INI and list files) to a folder. Import from a previous export; existing files are backed up to coopui_backup_restore.bak before overwriting.")
        ImGui.Spacing()
        ImGui.SetNextItemWidth(320)
        state.exportPath, _ = ImGui.InputText("Export to folder##BackupExport", state.exportPath or "", 512)
        if ImGui.Button("Export##Backup", ImVec2(100, 0)) then
            local ok, result = backupService.exportPackage(state.exportPath)
            if ok then
                setStatusMessage(string.format("Export complete. %d files written.", result or 0))
            else
                setStatusMessage("Export failed: " .. tostring(result or "unknown"))
            end
        end
        ImGui.Spacing()
        ImGui.SetNextItemWidth(320)
        state.importPath, _ = ImGui.InputText("Import from folder##BackupImport", state.importPath or "", 512)
        if ImGui.Button("Import##Backup", ImVec2(100, 0)) then
            local preview, err = backupService.previewImport(state.importPath)
            if err then
                setStatusMessage("Import preview failed: " .. tostring(err))
            else
                state.importPreview = preview
                state.importConfirmOpen = true
            end
        end
        if state.importConfirmOpen and state.importPreview and not ImGui.IsPopupOpen("Confirm Import##Backup") then
            ImGui.OpenPopup("Confirm Import##Backup")
        end
        if ImGui.BeginPopupModal("Confirm Import##Backup", nil, ImGuiWindowFlags.AlwaysAutoResize) then
            ImGui.Text("The following files will be overwritten (current versions backed up first):")
            ImGui.BeginChild("ImportPreview##Backup", ImVec2(400, 120), true)
            for _, rel in ipairs(state.importPreview or {}) do ImGui.Text(rel) end
            ImGui.EndChild()
            if ImGui.Button("Confirm Import##BackupBtn", ImVec2(120, 0)) then
                local ok, result = backupService.importPackage(state.importPath)
                if ok then
                    setStatusMessage(string.format("Import complete. %d files restored.", result or 0))
                else
                    setStatusMessage("Import failed: " .. tostring(result or "unknown"))
                end
                state.importConfirmOpen = false
                state.importPreview = nil
                ImGui.CloseCurrentPopup()
            end
            ImGui.SameLine()
            if ImGui.Button("Cancel##BackupImport") then
                state.importConfirmOpen = false
                state.importPreview = nil
                ImGui.CloseCurrentPopup()
            end
            ImGui.EndPopup()
        end
        if backupService.hasRestoreBackup and backupService.hasRestoreBackup() then
            ImGui.Spacing()
            if ImGui.Button("Restore Previous (from .bak)##Backup", ImVec2(220, 0)) then
                local ok, result = backupService.restoreFromBackup()
                if ok then
                    setStatusMessage(string.format("Restore complete. %d files restored from backup.", result or 0))
                else
                    setStatusMessage("Restore failed: " .. tostring(result or "unknown"))
                end
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Restore files from the backup created by the last Import.")
                ImGui.EndTooltip()
            end
        end
    end
end

return ConfigAdvanced
