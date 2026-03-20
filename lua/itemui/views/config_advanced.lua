--[[
    Advanced tab for CoOpt UI Settings: Debug channels, Sound, Diagnostics, Backup & Restore.
]]

require('ImGui')

local ConfigFilters = require('itemui.views.config_filters')
local debugModule = require('itemui.core.debug')
local diagnostics = require('itemui.core.diagnostics')
local soundService = require('itemui.services.sound')
local backupService = require('itemui.services.backup_service')

local ConfigAdvanced = {}
local state = {
    exportPath = "",
    importPath = "",
    importPreview = nil,
    importConfirmOpen = false,
    soundTestResult = nil,  -- { key = "event_name", ok = true/false } set on Test press
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

        local channelDescriptions = {
            Sell = "Sell macro start/stop, progress, failed items, and batch operations",
            Loot = "Loot evaluation decisions (Evaluating, LOOTING, SKIPPING) and macro echo",
            Augment = "Augment insert/remove operations and slot detection",
            MacroBridge = "Macro communication: IPC polling, progress file reads, state transitions",
            Layout = "Layout save/load, cache hits/misses, column visibility changes",
            Scan = "Inventory/bank/loot scan triggers, timing, and item counts",
            ItemOps = "Item operations: equip, move, destroy, and cursor handling",
        }
        for _, name in ipairs(debugModule.knownChannels or {}) do
            local enabled = debugModule.isChannelEnabled(name)
            local prev = enabled
            enabled = ImGui.Checkbox("Debug: " .. name .. "##Debug" .. name, enabled)
            if prev ~= enabled then
                debugModule.setChannelEnabled(name, enabled)
            end
            if ImGui.IsItemHovered() and channelDescriptions[name] then
                ImGui.BeginTooltip()
                ImGui.Text(channelDescriptions[name])
                ImGui.EndTooltip()
            end
        end
        -- Sync Performance: prints timing lines when saves/loads exceed threshold
        ImGui.Spacing()
        local profEnabled = debugModule.isProfileEnabled()
        local prevProf = profEnabled
        profEnabled = ImGui.Checkbox("Debug: Sync Performance##DebugSyncPerf", profEnabled)
        if prevProf ~= profEnabled then
            debugModule.setProfileEnabled(profEnabled)
        end
        if ImGui.IsItemHovered() then
            ImGui.BeginTooltip()
            ImGui.Text("Prints [CoOpt UI Profile] timing lines to the console when saves or loads exceed the threshold.")
            ImGui.EndTooltip()
        end
        if profEnabled then
            ImGui.SameLine()
            ImGui.SetNextItemWidth(100)
            local threshold = debugModule.getProfileThresholdMs()
            local newThreshold, changed = ImGui.InputInt("ms threshold##ProfileThreshold", threshold, 5, 25)
            if changed then
                debugModule.setProfileThresholdMs(newThreshold)
            end
            if ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text("Only print timing lines for operations that take at least this many milliseconds.")
                ImGui.Text("Default: 30 ms.")
                ImGui.EndTooltip()
            end
        end
    end

    if ImGui.CollapsingHeader("Sound Notifications", ImGuiTreeNodeFlags.None) then
        renderBreadcrumb("Advanced", "Sound Notifications")
        ImGui.TextColored(theme.ToVec4(theme.Colors.Muted), "Audio alerts for key events. Place .wav files in the EQ sounds/ folder and enter the filename below, or leave blank for system beep. Mythical Alert defaults to double-beep.")
        ImGui.Spacing()

        local masterEnabled = soundService.isEnabled()
        local prevMaster = masterEnabled
        masterEnabled = ImGui.Checkbox("Enable Sound Notifications##SoundMaster", masterEnabled)
        if prevMaster ~= masterEnabled then soundService.setEnabled(masterEnabled) end

        if masterEnabled then
            ImGui.Spacing()
            local displayOrder = {
                { key = "sell_complete",  label = "Sell Complete",  desc = "Played when sell macro finishes" },
                { key = "loot_rare",      label = "Rare Loot",      desc = "Played per-item when a Legendary, Script, or Mythical item is looted" },
                { key = "mythical_alert", label = "Mythical Alert", desc = "Played when a mythical item is detected on a corpse (double-beep by default)" },
            }
            for _, entry in ipairs(displayOrder) do
                local ev = soundService.getEventSettings(entry.key) or { enabled = true, file = nil }
                local prevEv = ev.enabled
                ev.enabled = ImGui.Checkbox(entry.label .. "##Sound" .. entry.key, ev.enabled)
                if prevEv ~= ev.enabled then soundService.setEventEnabled(entry.key, ev.enabled) end
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip(); ImGui.Text(entry.desc); ImGui.EndTooltip()
                end
                if ev.enabled then
                    ImGui.SameLine()
                    ImGui.SetNextItemWidth(150)
                    local file = ev.file or ""
                    local newFile
                    newFile, _ = ImGui.InputText("##SoundFile" .. entry.key, file, 128)
                    if newFile ~= file then
                        soundService.setEventFile(entry.key, newFile)
                        state.soundTestResult = nil  -- clear stale result on file change
                    end
                    if ImGui.IsItemHovered() then
                        ImGui.BeginTooltip()
                        ImGui.Text("Filename in the EQ sounds/ folder (e.g. myalert.wav).")
                        ImGui.Text("Blank = system beep.")
                        ImGui.EndTooltip()
                    end
                    ImGui.SameLine()
                    if ImGui.SmallButton("Test##Sound" .. entry.key) then
                        -- Check file exists only when Test is pressed
                        if file ~= "" then
                            local exists = soundService.fileExistsInSoundsDir(file)
                            if exists == false then
                                state.soundTestResult = { key = entry.key, ok = false }
                            else
                                state.soundTestResult = { key = entry.key, ok = true }
                            end
                        else
                            state.soundTestResult = nil
                        end
                        soundService.play(entry.key)
                    end
                    -- Show file-exists result only for the event that was just tested
                    if state.soundTestResult and state.soundTestResult.key == entry.key then
                        ImGui.SameLine()
                        if state.soundTestResult.ok then
                            ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "OK")
                        else
                            ImGui.TextColored(theme.ToVec4(theme.Colors.Error), "File not found")
                            if ImGui.IsItemHovered() then
                                ImGui.BeginTooltip()
                                ImGui.Text("File not found in EQ sounds/ folder.")
                                ImGui.Text("Make sure the .wav file exists there.")
                                ImGui.EndTooltip()
                            end
                        end
                    end
                end
            end
        end
    end

    if ImGui.CollapsingHeader("Recent Errors", ImGuiTreeNodeFlags.None) then
        renderBreadcrumb("Advanced", "Recent Errors")
        local errors = diagnostics.getErrors()
        local count = #errors
        if count == 0 then
            ImGui.TextColored(theme.ToVec4(theme.Colors.Success), "No errors recorded.")
        else
            ImGui.TextColored(theme.ToVec4(theme.Colors.Warning), string.format("%d error(s) in buffer:", count))
            ImGui.SameLine()
            if ImGui.SmallButton("Clear##DiagErrors") then
                diagnostics.clearErrors()
            end
            ImGui.Spacing()
            ImGui.BeginChild("DiagErrorList##Advanced", ImVec2(0, math.min(count * 22 + 8, 200)), true)
            for i = count, 1, -1 do
                local e = errors[i]
                local ts = e.timestamp and os.date("%H:%M:%S", e.timestamp) or "?"
                local detail = (e.err and e.err ~= "") and (" | " .. e.err) or ""
                ImGui.TextColored(theme.ToVec4(theme.Colors.Error),
                    string.format("[%s] %s: %s%s", ts, e.source or "?", e.message or "", detail))
            end
            ImGui.EndChild()
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
