--[[
    CoopUI - ScriptTracker
    Purpose: AA Script Progress Tracker
    Part of CoopUI — EverQuest EMU Companion
    Author: Perky's Crew
    Version: see coopui.version (SCRIPTTRACKER)
    Dependencies: mq2lua, ImGui

    Tracks Lost and Planar scripts in inventory; shows counts and total AA value.
    Script types: Lost Memories, Planar Power
    Tiers (AA each): normal(1), Enhanced(2), Rare(3), Epic(4), Legendary(5)

    Usage: /lua run scripttracker
    Toggle: /scripttracker
--]]

local mq = require('mq')
require('ImGui')
local CoopVersion = require('coopui.version')
local theme = require('coopui.utils.theme')

local VERSION = CoopVersion.SCRIPTTRACKER

-- Rarity tiers: same AA value for Planar and Lost of same rarity
local RARITY_ROWS = {
    { label = "Normal", tierKey = "normal", aa = 1 },
    { label = "Enhanced", tierKey = "enhanced", aa = 2 },
    { label = "Rare", tierKey = "rare", aa = 3 },
    { label = "Epic", tierKey = "epic", aa = 4 },
    { label = "Legendary", tierKey = "legendary", aa = 5 },
}

-- Script definitions: { suffix = "Lost Memories"|"Planar Power", tier = prefix, aa = value }
local SCRIPT_DEFS = {
    { suffix = "Lost Memories", tier = "", aa = 1 },
    { suffix = "Lost Memories", tier = "Enhanced ", aa = 2 },
    { suffix = "Lost Memories", tier = "Rare ", aa = 3 },
    { suffix = "Lost Memories", tier = "Epic ", aa = 4 },
    { suffix = "Lost Memories", tier = "Legendary ", aa = 5 },
    { suffix = "Planar Power", tier = "", aa = 1 },
    { suffix = "Planar Power", tier = "Enhanced ", aa = 2 },
    { suffix = "Planar Power", tier = "Rare ", aa = 3 },
    { suffix = "Planar Power", tier = "Epic ", aa = 4 },
    { suffix = "Planar Power", tier = "Legendary ", aa = 5 },
}

-- State
local isOpen = true
local shouldDraw = false
local terminate = false
local pinned = false
local scriptCounts = {}  -- key = "Lost:normal", "Lost:enhanced", etc.; value = count
local totalAA = 0
local lastScanTime = 0
-- Trigger-based refresh when pinned: no fixed timer; rescan only when inventory changes
local lastFingerprint = ""       -- lightweight inventory signature
local lastFingerprintCheck = 0  -- last time we checked fingerprint (ms)
local FINGERPRINT_CHECK_MS = 300  -- when pinned, check for inventory change every 300ms

-- ============================================================================
-- Fingerprint (lightweight inventory change detection)
-- ============================================================================

--- Build a cheap signature of inventory that changes when items are added/removed.
--- Used when pinned to trigger a full scan only when something actually changed.
local function buildInventoryFingerprint()
    local parts = {}
    for bagNum = 1, 10 do
        local pack = mq.TLO.Me.Inventory("pack" .. bagNum)
        local count = 0
        if pack and pack.Container() then
            for slotNum = 1, pack.Container() do
                local item = pack.Item(slotNum)
                if item and item.ID() and item.ID() > 0 then count = count + 1 end
            end
        end
        parts[#parts + 1] = string.format("b%d:%d", bagNum, count)
    end
    return table.concat(parts, "|")
end

-- ============================================================================
-- Scanning
-- ============================================================================

local function getScriptKey(suffix, tier)
    local typeKey = (suffix == "Lost Memories") and "Lost" or "Planar"
    local tierKey = (tier == "") and "normal" or tier:lower():gsub(" ", "")
    return typeKey .. ":" .. tierKey
end

local function getDisplayLabel(suffix, tier)
    local typeShort = (suffix == "Lost Memories") and "Lost" or "Planar"
    local tierLabel = (tier == "") and "Normal" or tier:gsub("^%s*(.-)%s*$", "%1")
    return typeShort .. " " .. tierLabel
end

local function scanScripts()
    for _, def in ipairs(SCRIPT_DEFS) do
        local key = getScriptKey(def.suffix, def.tier)
        scriptCounts[key] = 0
    end
    totalAA = 0

    for bagNum = 1, 10 do
        local pack = mq.TLO.Me.Inventory("pack" .. bagNum)
        if pack and pack.Container() then
            local bagSize = pack.Container()
            for slotNum = 1, bagSize do
                local item = pack.Item(slotNum)
                if item and item.ID() and item.ID() > 0 then
                    local name = item.Name() or ""
                    local stack = item.Stack() or 1
                    if stack < 1 then stack = 1 end

                    for _, def in ipairs(SCRIPT_DEFS) do
                        local fullName = def.tier .. "Script of " .. def.suffix
                        if name == fullName then
                            local key = getScriptKey(def.suffix, def.tier)
                            scriptCounts[key] = (scriptCounts[key] or 0) + stack
                            totalAA = totalAA + (def.aa * stack)
                            break
                        end
                    end
                end
            end
        end
    end

    lastScanTime = mq.gettime()
    lastFingerprint = buildInventoryFingerprint()
end

-- ============================================================================
-- Rendering
-- ============================================================================

local function renderUI()
    if not shouldDraw then return end

    -- When pinned, rescan only when inventory actually changes (trigger-based, no fixed timer)
    if pinned then
        local now = mq.gettime()
        if now - lastFingerprintCheck >= FINGERPRINT_CHECK_MS then
            lastFingerprintCheck = now
            local currentFp = buildInventoryFingerprint()
            if currentFp ~= lastFingerprint then
                scanScripts()
            end
        end
    end

    local windowFlags = bit32.bor(ImGuiWindowFlags.NoCollapse, ImGuiWindowFlags.AlwaysAutoResize)
    if pinned then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoMove)
    end
    local windowOpen, windowVisible = ImGui.Begin("AA Scripts##ScriptTracker", isOpen, windowFlags)
    -- When pinned, prevent closing (ignore X button and keep open for next frame)
    if pinned then
        isOpen = true
    else
        isOpen = windowOpen
    end

    if not windowOpen then
        if not pinned then shouldDraw = false end
        ImGui.End()
        return
    end

    -- Escape closes only when not pinned
    if ImGui.IsKeyPressed(ImGuiKey.Escape) and not pinned then
        shouldDraw = false
        isOpen = false
        ImGui.End()
        return
    end

    if not windowVisible then
        ImGui.End()
        return
    end

    -- Row 1: "AA Script Tracker v1.1.0" only (no overlap)
    theme.TextInfo("AA Script Tracker")
    ImGui.SameLine()
    theme.TextMuted(string.format("v%s", VERSION))

    -- Row 2: Refresh and PIN checkbox next to each other
    if ImGui.Button("Refresh", ImVec2(70, 0)) then
        scanScripts()
    end
    ImGui.SameLine()
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 2, 2)
    pinned = ImGui.Checkbox("PIN", pinned)
    ImGui.PopStyleVar(1)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("When pinned, window cannot be closed or moved; counts refresh when inventory changes (e.g. item looted)"); ImGui.EndTooltip() end

    -- Scripts label and table (Planar + Lost combined by rarity)
    ImGui.Text("Scripts")
    if ImGui.BeginTable("ScriptCounts", 3, ImGuiTableFlags.Borders) then
        ImGui.TableSetupColumn("Rarity", ImGuiTableColumnFlags.WidthFixed, 90)
        ImGui.TableSetupColumn("Count", ImGuiTableColumnFlags.WidthFixed, 50)
        ImGui.TableSetupColumn("AA", ImGuiTableColumnFlags.WidthFixed, 40)
        ImGui.TableHeadersRow()

        for _, row in ipairs(RARITY_ROWS) do
            local lostKey = "Lost:" .. row.tierKey
            local planarKey = "Planar:" .. row.tierKey
            local count = (scriptCounts[lostKey] or 0) + (scriptCounts[planarKey] or 0)
            local aaVal = row.aa * count
            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            ImGui.Text(row.label)
            ImGui.TableNextColumn()
            ImGui.Text(tostring(count))
            ImGui.TableNextColumn()
            ImGui.Text(tostring(aaVal))
        end
        ImGui.EndTable()
    end

    -- Total AA
    theme.TextWarning(string.format("Total AA: %d", totalAA))

    -- Last Scan
    theme.TextMuted(string.format("Last scan: %s", os.date("%H:%M:%S", lastScanTime / 1000)))

    ImGui.End()
end

-- ============================================================================
-- Commands & main
-- ============================================================================

local function handleCommand(...)
    local args = {...}
    local cmd = args[1] and args[1]:lower() or ""

    if cmd == "" or cmd == "toggle" then
        shouldDraw = not shouldDraw
        if shouldDraw then
            isOpen = true
            scanScripts()
            print("\ag[ScriptTracker]\ax Window opened")
        else
            print("\ag[ScriptTracker]\ax Window closed")
        end
    elseif cmd == "show" then
        shouldDraw = true
        isOpen = true
        scanScripts()
        print("\ag[ScriptTracker]\ax Window opened")
    elseif cmd == "hide" then
        shouldDraw = false
        isOpen = false
    elseif cmd == "refresh" then
        scanScripts()
        print("\ag[ScriptTracker]\ax Scripts refreshed")
    elseif cmd == "help" then
        print("\ag[ScriptTracker]\ax Commands: /scripttracker [toggle|show|hide|refresh|help]")
        print("\ag[ScriptTracker]\ax Use PIN checkbox to prevent window from closing")
    else
        print(string.format("\ar[ScriptTracker]\ax Unknown command: %s", cmd))
    end
end

local function main()
    print(string.format("\ag[ScriptTracker]\ax AA Script Tracker v%s loaded", VERSION))
    print("\ag[ScriptTracker]\ax Type /scripttracker to toggle. Tracks Lost & Planar scripts.")

    mq.bind('/scripttracker', handleCommand)
    mq.imgui.init('ScriptTracker', renderUI)

    -- Trigger: refresh when game reports item added to inventory (loot, trade, etc.)
    mq.event('ScriptTrackerInventory', '#*#added to your inventory#*#', function()
        scanScripts()
    end)
    mq.event('ScriptTrackerLoot', '#*#You have looted#*#', function()
        scanScripts()
    end)

    while not mq.TLO.Me.Name() do
        mq.delay(1000)
    end

    scanScripts()

    while not terminate do
        mq.delay(shouldDraw and 100 or 500)
        mq.doevents()
    end

    mq.imgui.destroy('ScriptTracker')
    mq.unbind('/scripttracker')
end

main()
