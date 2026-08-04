--[[
    Reroll Companion — UI for server Augment and Mythical reroll lists.
    Architecture: New companion window (like Augments/Bank) with two internal tabs:
    Augments and Mythicals. Each tab shows the server list, inventory match counter,
    and actions (Add to Reroll from Cursor — auto-routes to the aug or mythical list
    by item, Remove, Roll, Refresh). Fits CoOpt UI's existing companion pattern and
    design language.
]]

local mq = require('mq')
require('ImGui')
local constants = require('itemui.constants')
local context = require('itemui.context')
local ItemTooltip = require('itemui.utils.item_tooltip')
local registry = require('itemui.core.registry')
local windowHeader = require('itemui.components.window_header')

local REROLL = constants.REROLL or {}
local ITEMS_REQUIRED = REROLL.ITEMS_REQUIRED or 10
local AUGMENT_TYPE = REROLL.AUGMENT_TYPE_NAME or "Augmentation"

local RerollView = {}

-- Sort cache: avoid re-sorting every frame. Per-track cache keyed by sort params + data generation.
local _sortCache = {
    aug = { sortCol = -1, sortAsc = true, listLen = 0, listGen = -1, locGen = -1, result = nil },
    mythical = { sortCol = -1, sortAsc = true, listLen = 0, listGen = -1, locGen = -1, result = nil },
}

-- Track inventory/bank item count so we can detect moves and invalidate location cache.
local _lastInvCount = -1
local _lastBankCount = -1

-- Tab index: 1 = Augments, 2 = Mythicals

-- 20b tray geometry. Two rows of five, fixed cells so a long name never shifts a slot.
local TRAY_PER_ROW = 5
local TRAY_CELL_W = 96
local TRAY_NAME_MAX = 14

--- The ten items a roll would actually consume, bags first then bank — the same order
--- the roll's own bank-move pre-flight uses, so the tray is not a separate opinion about
--- what would happen. Returns up to ITEMS_REQUIRED entries { name, id, where }.
---
--- Membership is a set built ONCE per call, then O(1) per item — not a list scan per
--- item. This runs every frame the window is open, over the full bag and bank lists.
--- Returns (tray, bankRows) where bankRows are the DISTINCT bank rows the tray drew from.
--- Both are needed because they count different things: the tray counts UNITS (a stack of
--- four augs is four of the ten), while a bank fetch moves ROWS (one /itemnotify brings
--- the whole stack). The roll's pre-flight must size itself in rows or it asks for free
--- bag slots it does not need and fetches items already accounted for.
local function buildTray(rerollService, list, inventoryItems, bankList)
    local listed = {}
    for _, e in ipairs(list or {}) do
        if e.id then listed[e.id] = true end
    end
    local out, bankRows = {}, {}
    local function take(items, where)
        for _, it in ipairs(items or {}) do
            if #out >= ITEMS_REQUIRED then return end
            local id = it.id or it.ID
            if id and listed[id] then
                -- Stacks count per unit: the roll consumes items, not slots.
                local n = tonumber(it.stackSize) or 1
                if n < 1 then n = 1 end
                local before = #out
                for _ = 1, n do
                    if #out >= ITEMS_REQUIRED then break end
                    out[#out + 1] = { name = it.name, id = id, where = where }
                end
                if where == "bank" and #out > before then
                    bankRows[#bankRows + 1] = { bag = it.bag, slot = it.slot, id = id, name = it.name or "" }
                end
                if #out >= ITEMS_REQUIRED then return end
            end
        end
    end
    take(inventoryItems, "inv")
    take(bankList, "bank")
    return out, bankRows
end

--- Why Roll is off, in the user's words, or nil when it is on. 20b: "Roll says why it's
--- off" — inline, never a tooltip, because a tooltip hides the answer behind a hover on a
--- control you have already decided not to press.
local function rollBlockedReason(ctx, tray, isMovingFromBank, pendingBankMoves, bankConnected, countInBank)
    if isMovingFromBank then
        -- nextIndex is the NEXT item to move, so after the last one it reads total+1.
        -- Clamped: "fetching 6 of 5" is the kind of number that makes a user think the
        -- tool has lost count of what it is doing.
        local total = #((pendingBankMoves and pendingBankMoves.items) or {})
        local done = math.min(tonumber(pendingBankMoves and pendingBankMoves.nextIndex) or 1,
            math.max(total, 1))
        return string.format("fetching %d of %d from the bank", done, total)
    end
    local short = ITEMS_REQUIRED - #tray
    if short > 0 then
        -- Name the fix, not just the shortfall: an unopened bank is the common cause and
        -- the user cannot see it from the count alone.
        if not bankConnected then
            return string.format("%d more needed - open your bank if the rest are in it", short)
        end
        return string.format("%d more needed", short)
    end
    if countInBank > 0 and not bankConnected then
        return "your bank has to be open to use the items in it"
    end
    return nil
end

local function renderTabContent(ctx, track, rerollService)
    local isAug = (track == "aug")
    local list = isAug and rerollService.getAugList() or rerollService.getMythicalList()
    local pendingList = isAug and rerollService.getPendingAugList() or rerollService.getPendingMythicalList()
    local inGuildHall = rerollService.isInGuildHall and rerollService.isInGuildHall()
    local inventoryItems = ctx.inventoryItems or {}
    local bankItems = ctx.bankItems or {}
    local bankCache = ctx.bankCache or {}
    local bankConnected = ctx.isBankWindowOpen and ctx.isBankWindowOpen() or false
    local bankList = bankConnected and bankItems or bankCache
    -- Detect inventory/bank content changes and invalidate location cache so Status/Location columns update live.
    local invCount = inventoryItems and #inventoryItems or 0
    local bankCount = bankList and #bankList or 0
    if invCount ~= _lastInvCount or bankCount ~= _lastBankCount then
        _lastInvCount = invCount
        _lastBankCount = bankCount
        rerollService.invalidateLocationCache()
    end
    local countInInv = rerollService.countInInventory(list, inventoryItems)
    local countInBank = (bankConnected and bankList and #bankList > 0) and rerollService.countInInventory(list, bankList) or 0
    local combinedCount = countInInv + countInBank
    local theme = ctx.theme
    local setStatusMessage = ctx.setStatusMessage or function() end

    -- Selection state (defined first so Remove button can use it)
    local selectedKey = isAug and "rerollSelectedAugId" or "rerollSelectedMythicalId"
    local pendingRemoveKey = isAug and "rerollPendingRemoveAugId" or "rerollPendingRemoveMythicalId"
    local pendingRollKey = isAug and "rerollPendingAugRoll" or "rerollPendingMythicalRoll"
    local selectedId = ctx.uiState[selectedKey]
    local pendingRemoveId = ctx.uiState[pendingRemoveKey]
    local pendingRoll = ctx.uiState[pendingRollKey]
    local pendingBankMoves = ctx.uiState.pendingRerollBankMoves
    local isMovingFromBank = pendingBankMoves and pendingBankMoves.list == track

    -- ---------------------------------------------------------------------
    -- 20b: THE TRAY IS THE INTERFACE.
    --
    -- A roll consumes ten listed items you own. The old surface said "7 / 10" and left
    -- you to work out which seven those were from a table sorted by something else. Ten
    -- slots say it directly: these are the items going in, in the order they will go,
    -- bags before bank. Empty slots are the shortfall, countable at a glance.
    --
    -- The ten is a CLIENT convention (constants.REROLL.ITEMS_REQUIRED). The service does
    -- not check it: augRoll() takes no arguments, guards nothing, /say-s the command and
    -- optimistically trims the tail of its own list. So the tray is also the only place
    -- that can honestly say what a roll would consume.
    -- ---------------------------------------------------------------------
    local tray, trayBankRows = buildTray(rerollService, list, inventoryItems,
        bankConnected and bankList or nil)
    do
        local filled = #tray
        -- One register per line: this line answers "can I roll" and nothing else. The
        -- ownership pair (bags N . bank N) is a property of the server LIST, not the
        -- tray, and lives on the list's header line below — beside "N of 10 ready" it
        -- read as a second opinion about the same number.
        local header = string.format("%d of %d ready", filled, ITEMS_REQUIRED)
        if filled >= ITEMS_REQUIRED then
            theme.TextSuccess(header)
        elseif filled >= (ITEMS_REQUIRED - 2) then
            theme.TextWarning(header)
        else
            theme.TextMuted(header)
        end

        -- Two rows of five. Each cell is a fixed-width child so a long item name stays
        -- inside its slot instead of shoving the next one sideways — and each cell is
        -- CONTAINED: the kit's Inset wash (whose definition names tray cells) plus a 1px
        -- Divider hairline. Ten floating labels read as a wrapped sentence; ten bounded
        -- slots are countable, and an EMPTY slot only states the shortfall if it is
        -- visible as a slot.
        local cellW = TRAY_CELL_W
        local lineH = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14
        local cellH = lineH + 6
        ImGui.PushStyleColor(ImGuiCol.ChildBg, theme.ToVec4(theme.Kit.Inset))
        for i = 1, ITEMS_REQUIRED do
            if (i - 1) % TRAY_PER_ROW ~= 0 then ImGui.SameLine(0, 4) end
            local slot = tray[i]
            local okCell = pcall(function()
                -- border = FALSE. The bool-border overload maps true to
                -- ImGuiChildFlags_Borders, and a bordered child DOES apply WindowPadding
                -- (8px top and bottom) — which would leave a lineH+6 cell with negative
                -- room for its own text and clip every slot label. Same class as the
                -- bar-button clipping this session already fixed: the container has to
                -- pay for what it draws. Containment is the ChildBg wash plus the
                -- hairline drawn after EndChild — never the border flag.
                if ImGui.BeginChild("rerollTray_" .. track .. "_" .. i, ImVec2(cellW, cellH), false,
                        bit32.bor(ImGuiWindowFlags.NoScrollbar, ImGuiWindowFlags.NoScrollWithMouse)) then
                    if slot then
                        -- Location is the tint, same vocabulary the list table uses:
                        -- in bags = ready, in bank = has to be fetched first. Inside a
                        -- bounded cell the truncation marker is ".." — one dot reads as
                        -- a period; two read as deliberate.
                        local name = tostring(slot.name or "?")
                        if #name > TRAY_NAME_MAX then name = name:sub(1, TRAY_NAME_MAX - 2) .. ".." end
                        ImGui.SetCursorPosX(3)
                        ImGui.SetCursorPosY(3)
                        if slot.where == "bank" then
                            theme.TextWarning(name)
                        else
                            theme.TextSuccess(name)
                        end
                    else
                        -- Centered in the visible slot: "empty" is the fact the tray
                        -- exists to state, not filler text.
                        local tw = ImGui.CalcTextSize and ImGui.CalcTextSize("empty")
                        if type(tw) == "number" and tw > 0 and tw < cellW then
                            ImGui.SetCursorPosX((cellW - tw) * 0.5)
                        else
                            ImGui.SetCursorPosX(3)
                        end
                        ImGui.SetCursorPosY(3)
                        theme.TextMuted("empty")
                    end
                end
                ImGui.EndChild()
            end)
            if not okCell then break end
            -- The 1px hairline over the cell's rect. Four AddRectFilled strips, not
            -- AddRect: an outline is unproven in this binding (window_header records
            -- why), and filled strips are what ships everywhere else.
            pcall(function()
                local dl = ImGui.GetWindowDrawList and ImGui.GetWindowDrawList()
                if not dl or not dl.AddRectFilled then return end
                local x1, y1 = ImGui.GetItemRectMin()
                local x2, y2 = ImGui.GetItemRectMax()
                if type(x1) ~= "number" or type(x2) ~= "number" then return end
                local col = ImGui.GetColorU32 and ImGui.GetColorU32(theme.ToVec4(theme.Kit.Divider))
                    or 0xFF302B2B
                dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x2, y1 + 1), col)
                dl:AddRectFilled(ImVec2(x1, y2 - 1), ImVec2(x2, y2), col)
                dl:AddRectFilled(ImVec2(x1, y1), ImVec2(x1 + 1, y2), col)
                dl:AddRectFilled(ImVec2(x2 - 1, y1), ImVec2(x2, y2), col)
            end)
            if slot and ImGui.IsItemHovered() then
                ImGui.BeginTooltip()
                ImGui.Text(tostring(slot.name or "?"))
                ImGui.Text(string.format("id %s . %s", tostring(slot.id),
                    (slot.where == "bank") and "in your bank (moved to bags for the roll)" or "in your bags"))
                ImGui.EndTooltip()
            end
        end
        ImGui.PopStyleColor(1)
    end

    -- Action buttons row. Add auto-routes by cursor item: Mythical-prefixed -> mythical list,
    -- augments -> aug list (resolveCursorList in reroll_service; nil = not reroll-eligible).
    local hasCursor = ctx.hasItemOnCursor and ctx.hasItemOnCursor()
    local cursorList = nil
    if hasCursor and rerollService.resolveCursorList then cursorList = rerollService.resolveCursorList() end
    local cursorOnList = false
    if cursorList then
        local destEntries = (cursorList == "aug") and rerollService.getAugList() or rerollService.getMythicalList()
        cursorOnList = rerollService.isCursorIdInList(destEntries)
    end
    local addDisabled = not hasCursor or not cursorList or cursorOnList or (ctx.uiState.pendingRerollAdd ~= nil)
    -- The TRAY is the gate now, not a raw count: it is capped at ten and built from the
    -- items a roll would actually take, so "the tray is full" and "the roll can run" are
    -- the same fact rather than two that can disagree.
    local rollBlockedText = rollBlockedReason(ctx, tray, isMovingFromBank, pendingBankMoves,
        bankConnected, countInBank)
    local rollDisabled = rollBlockedText ~= nil

    -- Verbs grouped by what they act on, top to bottom in consequence order: Roll
    -- (consumes the tray) alone with its printed reason; Add/Remove (edit the list);
    -- Refresh/Sync (talk to the server). Every confirm and failure surface anchors
    -- directly under the row that owns it — always the same home. Each row starts flush
    -- left: a SameLine chain here once hung the whole strip off the tray's second row
    -- and clipped every button past the right edge ("the reroll has no way to sync" was
    -- a true statement about the pixels, photographed in fullscreen-bankopen).
    local groupGap = (ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14
    ImGui.Spacing()

    -- Row 1: Roll — the primary verb, directly under the tray it consumes.
    if rollDisabled then
        theme.PushKeepButton(true)
    else
        theme.PushKeepButton(false)
    end
    -- The label stays "Roll" in every state (20b: same slot, same width, the reason lives
    -- beside it) rather than becoming "Moving 3/7" — a button whose text changes under
    -- your cursor is a button you misclick.
    if ImGui.Button("Roll##" .. track, ImVec2(60, 0)) then
        if not rollDisabled then ctx.uiState[pendingRollKey] = true end
    end
    theme.PopButtonColors()
    -- 20b: the reason is PRINTED, not hovered. Kit §3.5 - "Disabled = with the reason
    -- printed beside it, never in a tooltip."
    if rollBlockedText then
        ImGui.SameLine(0, 8)
        theme.TextMuted(rollBlockedText)
    end

    -- Roll's confirm, at its fixed home under Roll's own row.
    if pendingRoll then
        theme.TextWarning("Roll will consume 10 listed items from your inventory. Continue?")
        ImGui.SameLine()
        theme.PushKeepButton(false)
        if ImGui.Button("Confirm Roll##" .. track, ImVec2(100, 0)) then
            -- Sized from the TRAY, which is what the user was just looking at: exactly the
            -- distinct bank ROWS its entries came from. The old arithmetic
            -- (ITEMS_REQUIRED - countInInv) mixed units and rows — countInInventory counts
            -- rows and ignores stackSize — so a stack of four listed augs in bags filled
            -- four tray slots while the pre-flight still believed nine had to be fetched.
            local bankItemsToMove = trayBankRows or {}
            local needToMove = #bankItemsToMove
            if needToMove > 0 then
                -- Pre-flight: need free bag space for the bank ROWS we'll move
                local freeSlots = (ctx.countFreeInvSlots and ctx.countFreeInvSlots()) or 0
                if freeSlots < needToMove then
                    setStatusMessage(string.format("Need %d free bag slots to move items from bank; you have %d. Free %d more.", needToMove, freeSlots, needToMove - freeSlots))
                    -- Keep pendingRoll so they can fix and try again
                elseif not bankConnected then
                    setStatusMessage("Bank must be open to use bank items for roll.")
                else
                    do
                        -- Start bank-to-bag move sequence; main_loop will process one per tick then trigger roll
                        -- Pause location cache updates so each move doesn't trigger a rebuild
                        rerollService.pauseLocationCache()
                        ctx.uiState.pendingRerollBankMoves = { list = track, items = bankItemsToMove, nextIndex = 1 }
                        ctx.uiState[pendingRollKey] = nil
                        setStatusMessage(string.format("Moving %d item(s) from bank...", needToMove))
                    end
                end
            else
                -- Enough in inventory already; roll immediately
                rerollService.pauseLocationCache()
                if isAug then
                    rerollService.augRoll()
                    ctx.uiState.pendingAugRollComplete = true
                    ctx.uiState.pendingAugRollCompleteAt = (mq and mq.gettime and mq.gettime()) or 0
                else
                    rerollService.mythicalRoll()
                    -- Schedule reroll quick refresh so count updates and next roll doesn't use stale items.
                    ctx.uiState.rerollPendingScan = true
                    ctx.uiState.rerollPendingScanAt = (mq and mq.gettime and mq.gettime()) or 0
                end
                ctx.uiState[pendingRollKey] = nil
            end
        end
        theme.PopButtonColors()
        ImGui.SameLine()
        if ImGui.Button("Cancel##Roll" .. track, ImVec2(60, 0)) then
            ctx.uiState[pendingRollKey] = nil
        end
    end

    ImGui.Dummy(ImVec2(1, groupGap))

    -- Row 2: the list editors.
    if addDisabled then
        theme.PushKeepButton(true)
    else
        theme.PushKeepButton(false)
    end
    local addLabel = "Add to Reroll (from Cursor)##" .. track
    if ImGui.Button(addLabel, ImVec2(170, 0)) then
        -- Re-check the disable gate on click (styled-disabled buttons still emit clicks), same as Roll/Sync.
        if not addDisabled then
            if cursorList == "aug" then rerollService.addAugFromCursor() else rerollService.addMythicalFromCursor() end
            if ctx.invalidateSellConfigCache then ctx.invalidateSellConfigCache() end
            if ctx.invalidateLootConfigCache then ctx.invalidateLootConfigCache() end
            if ctx.computeAndAttachSellStatus and ctx.inventoryItems and #ctx.inventoryItems > 0 then ctx.computeAndAttachSellStatus(ctx.inventoryItems) end
            if ctx.computeAndAttachSellStatus and ctx.bankItems and #ctx.bankItems > 0 then ctx.computeAndAttachSellStatus(ctx.bankItems) end
        end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        if not hasCursor then
            ImGui.Text("Place an item on your cursor first.")
        elseif not cursorList then
            ImGui.Text("Cursor item is not reroll-eligible (needs an augment or a Mythical-prefixed item).")
        elseif cursorOnList then
            ImGui.Text("This item is already on the list.")
        elseif ctx.uiState.pendingRerollAdd then
            ImGui.Text("Another add is in progress.")
        else
            ImGui.Text(string.format("Auto-routes by item: adds the cursor item to the %s list, whichever tab is active.", (cursorList == "mythical") and "mythical" or "augment"))
        end
        ImGui.EndTooltip()
    end
    theme.PopButtonColors()

    ImGui.SameLine(0, 8)
    theme.PushDeleteButton()
    local removeLabel = "Remove##" .. track
    if ImGui.Button(removeLabel, ImVec2(70, 0)) then
        if selectedId then
            ctx.uiState[pendingRemoveKey] = selectedId
        else
            setStatusMessage("Select an item in the list first.")
        end
    end
    ImGui.PopStyleColor(3)
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Select a row (or use context menu), then click Remove to confirm."); ImGui.EndTooltip() end

    -- The list editors' confirm, at its fixed home under their row. It names the ITEM —
    -- ids are the wire's vocabulary, names are the user's; the id stays reachable on the
    -- row's hover tooltip and keys the removal internally, unchanged.
    if pendingRemoveId then
        local removeName
        for _, e in ipairs(list) do
            if e.id == pendingRemoveId then removeName = e.name; break end
        end
        local ask = (removeName and removeName ~= "")
            and string.format("Remove %s?", removeName)
            or string.format("Remove item ID %s?", tostring(pendingRemoveId))
        theme.TextWarning(ask)
        ImGui.SameLine()
        if ImGui.Button("Confirm Remove##" .. track, ImVec2(120, 0)) then
            if isAug then rerollService.removeAug(pendingRemoveId) else rerollService.removeMythical(pendingRemoveId) end
            ctx.uiState[pendingRemoveKey] = nil
            ctx.uiState[selectedKey] = nil
            if ctx.invalidateSellConfigCache then ctx.invalidateSellConfigCache() end
            if ctx.invalidateLootConfigCache then ctx.invalidateLootConfigCache() end
            if ctx.computeAndAttachSellStatus and ctx.inventoryItems and #ctx.inventoryItems > 0 then ctx.computeAndAttachSellStatus(ctx.inventoryItems) end
            if ctx.computeAndAttachSellStatus and ctx.bankItems and #ctx.bankItems > 0 then ctx.computeAndAttachSellStatus(ctx.bankItems) end
        end
        ImGui.SameLine()
        if ImGui.Button("Cancel##Remove" .. track, ImVec2(60, 0)) then
            ctx.uiState[pendingRemoveKey] = nil
        end
    end

    ImGui.Dummy(ImVec2(1, groupGap))

    -- Row 3: the server verbs. Sync Pending used to sit clipped off the right edge when
    -- these trailed the editor row past the 420px window floor — a sync surface that
    -- exists but cannot be seen was field-reported as "the reroll has no way to sync".
    if ImGui.Button("Refresh##" .. track, ImVec2(70, 0)) then
        rerollService.requestBothLists()
    end
    if ImGui.IsItemHovered() then ImGui.BeginTooltip(); ImGui.Text("Request both aug and mythical lists from server"); ImGui.EndTooltip() end

    -- Sync pending: only active in guild hall when this tab's pending list is non-empty.
    local pendingCount = pendingList and #pendingList or 0
    local rerollState = rerollService.getState and rerollService.getState() or {}
    local sync = rerollState.pendingRerollSync
    local syncActive = sync and sync.list == track
    local syncPendingDisabled = (not inGuildHall or pendingCount == 0) and not syncActive
    ImGui.SameLine(0, 8)
    if syncPendingDisabled then
        theme.PushKeepButton(true)
    else
        theme.PushKeepButton(false)
    end
    -- The label carries the COUNT: "Sync Pending 3" is the number the field asked for --
    -- how many items are waiting to reach the server list.
    local syncLabel
    if syncActive then
        syncLabel = string.format("Syncing %d/%d##%s", sync.nextIndex or 0, sync.totalCount or 0, track)
    elseif pendingCount > 0 then
        syncLabel = string.format("Sync Pending %d##%s", pendingCount, track)
    else
        syncLabel = "Sync Pending##" .. track
    end
    if ImGui.Button(syncLabel, ImVec2(115, 0)) then
        if not syncPendingDisabled and not syncActive then rerollService.startPendingSync(track) end
    end
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        if syncActive then
            ImGui.Text(string.format("Syncing: %d/%d (%d failed)", sync.syncedCount or 0, sync.totalCount or 0, sync.failedCount or 0))
        elseif not inGuildHall then
            ImGui.Text("Must be in guild hall to sync pending.")
        elseif pendingCount == 0 then
            ImGui.Text("No pending items to sync.")
        else
            ImGui.Text(string.format("Sync %d pending item(s) to server.", pendingCount))
        end
        ImGui.EndTooltip()
    end
    theme.PopButtonColors()
    -- The reason, printed beside per kit rule 3.5 -- and the pending count even when the
    -- button is grey, so "3 waiting - sync in the guild hall" is readable at a glance
    -- instead of being a fact the tooltip hides.
    if not syncActive and pendingCount > 0 and not inGuildHall then
        ImGui.SameLine(0, 8)
        theme.TextMuted(string.format("%d waiting - sync in the guild hall", pendingCount))
    end

    -- Sync failures, said out loud. main_loop records a per-item {name, reason} for every
    -- item a sync could not push (equipped, in the bank, not owned) — and until now
    -- NOTHING rendered it: only failedCount reached the UI, inside a tooltip. A count with
    -- no reason is the thing 20b exists to delete.
    if syncActive and sync.failedItems and #sync.failedItems > 0 then
        theme.TextWarning(string.format("%d could not be synced:", #sync.failedItems))
        for i = 1, math.min(#sync.failedItems, 5) do
            local f = sync.failedItems[i]
            theme.TextMuted(string.format("  %s - %s", tostring(f.name or "?"),
                tostring(f.reason or "unknown")))
        end
        if #sync.failedItems > 5 then
            theme.TextMuted(string.format("  +%d more", #sync.failedItems - 5))
        end
    end

    ImGui.Separator()

    -- Server list table: Name, Status (Available / List Only), Location (Inventory /
    -- Bank / —). No Item ID column: names are the user's vocabulary, ids are the wire's —
    -- the id rides every row's hover tooltip instead (the tray cells' pattern). The muted
    -- ownership pair lives on this header because it is a property of this LIST ("what do
    -- I own on it"), not of the tray above.
    theme.TextHeader(isAug and "Server reroll list (augments)" or "Server reroll list (mythicals)")
    ImGui.SameLine(0, 8)
    if countInBank > 0 then
        theme.TextMuted(string.format(". yours: bags %d . bank %d", countInInv, countInBank))
    else
        theme.TextMuted(string.format(". yours: bags %d", countInInv))
    end
    if #list == 0 then
        theme.TextMuted(isAug and "No augments on list. Add from cursor or refresh." or "No mythicals on list. Add from cursor or refresh.")
    else
    -- Use cached deduplicated list (rebuilt only when list generation changes)
    local uniqueList = isAug and rerollService.getUniqueAugList() or rerollService.getUniqueMythicalList()
    local tableFlags = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
    local nCols = 3
    if ImGui.BeginTable("RerollList_" .. track, nCols, tableFlags) then
        ImGui.TableSetupColumn("Item Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable, ImGuiTableColumnFlags.DefaultSort), 0, 0)
        ImGui.TableSetupColumn("Status", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 80, 1)
        ImGui.TableSetupColumn("Location", bit32.bor(ImGuiTableColumnFlags.WidthFixed, ImGuiTableColumnFlags.Sortable), 80, 2)
        ImGui.TableSetupScrollFreeze(0, 1)
        ImGui.TableHeadersRow()

        -- Sort
        local sortSpecs = ImGui.TableGetSortSpecs()
        local sortCol = 0
        local sortAsc = true
        if sortSpecs and sortSpecs.SpecsCount > 0 then
            local spec = sortSpecs:Specs(1)
            if spec then
                sortCol = spec.ColumnIndex
                sortAsc = (spec.SortDirection == ImGuiSortDirection.Ascending)
            end
            sortSpecs.SpecsDirty = false
        end

        -- Use cached location sets (rebuilt only when list/inventory/bank change)
        local inInvSet, inBankSet = rerollService.getLocationSets(inventoryItems, bankList)
        local listGen = rerollService.getListGeneration()
        local locGen = rerollService.getLocationGeneration()

        -- Sort cache: only re-sort when sort params, list, or location sets change
        local sc = _sortCache[track]
        local needsResort = (sc.sortCol ~= sortCol or sc.sortAsc ~= sortAsc
            or sc.listLen ~= #uniqueList or sc.listGen ~= listGen
            or sc.locGen ~= locGen or not sc.result)
        local sorted
        if needsResort then
            sorted = {}
            for i = 1, #uniqueList do sorted[i] = uniqueList[i] end
            -- Strict comparator: never return true when a and b are equal; use id as tie-breaker.
            table.sort(sorted, function(a, b)
                local aid, bid = a.id or 0, b.id or 0
                local an, bn = (a.name or ""):lower(), (b.name or ""):lower()
                local primary_lt, primary_gt
                if sortCol == 0 then
                    primary_lt = an < bn
                    primary_gt = an > bn
                elseif sortCol == 1 then
                    -- Status: Available (inv or bank) = 1, List Only = 0
                    local av = (inInvSet[a.id] or inBankSet[a.id]) and 1 or 0
                    local bv = (inInvSet[b.id] or inBankSet[b.id]) and 1 or 0
                    primary_lt = av < bv
                    primary_gt = av > bv
                else
                    -- Location: Inventory (2) > Bank (1) > none (0)
                    local av = inInvSet[a.id] and 2 or (inBankSet[a.id] and 1 or 0)
                    local bv = inInvSet[b.id] and 2 or (inBankSet[b.id] and 1 or 0)
                    primary_lt = av < bv
                    primary_gt = av > bv
                end
                if primary_lt then return sortAsc end
                if primary_gt then return not sortAsc end
                -- Tie-breaker: same primary value -> order by id so comparator is strict
                return (aid < bid) and sortAsc or (aid > bid) and not sortAsc
            end)
            sc.result = sorted
            sc.sortCol = sortCol
            sc.sortAsc = sortAsc
            sc.listLen = #uniqueList
            sc.listGen = listGen
            sc.locGen = locGen
        else
            sorted = sc.result
        end

        -- One id -> item map per frame (first match wins, like the old per-row linear scans)
        local invById, bankById = {}, {}
        for _, inv in ipairs(inventoryItems) do
            local iid = inv.id or inv.ID
            if iid and not invById[iid] then invById[iid] = inv end
        end
        for _, bn in ipairs(bankList) do
            local bid = bn.id or bn.ID
            if bid and not bankById[bid] then bankById[bid] = bn end
        end

        local clipper = ImGuiListClipper.new()
        clipper:Begin(#sorted)
        while clipper:Step() do
        for i = clipper.DisplayStart + 1, clipper.DisplayEnd do
            local entry = sorted[i]
            if not entry then goto continue end
            ImGui.TableNextRow()
            local inInv = inInvSet[entry.id] == true
            local inBank = inBankSet[entry.id] == true
            -- Row ID must include index so duplicate list entries (same item twice) get unique ImGui IDs
            local rowId = "reroll_" .. track .. "_" .. tostring(i) .. "_" .. tostring(entry.id)
            -- Resolve inv/bank item for tooltip and shared context menu (id map, not linear scan)
            local invItem = invById[entry.id]
            local bankItem = (not invItem) and bankById[entry.id] or nil
            local tipItem = invItem or bankItem
            local tipSource = invItem and "inv" or "bank"
            local menuItem = { name = entry.name, id = entry.id, type = isAug and AUGMENT_TYPE or nil }
            if tipItem then menuItem.bag = tipItem.bag; menuItem.slot = tipItem.slot; menuItem.inKeep = tipItem.inKeep; menuItem.inJunk = tipItem.inJunk end

            ImGui.TableNextColumn()
            ImGui.PushID(rowId)
            -- Three-tier coloring: green (inventory, ready to roll), yellow (bank, needs move), grey (list only)
            if inInv then
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Success))
            elseif inBank then
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Warning))
            else
                ImGui.PushStyleColor(ImGuiCol.Text, theme.ToVec4(theme.Colors.Muted))
            end
            ImGui.Selectable(entry.name or ("ID " .. tostring(entry.id)), selectedId == entry.id, ImGuiSelectableFlags.None, ImVec2(0, 0))
            ImGui.PopStyleColor(1)
            if ImGui.IsItemHovered() then
                -- Tooltip: try to show item details from inventory or bank if we have it
                if tipItem and ctx.getItemStatsForTooltip then
                    local showItem = ctx.getItemStatsForTooltip(tipItem, tipSource)
                    if showItem then
                        local opts = { source = tipSource, bag = tipItem.bag, slot = tipItem.slot }
                        local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                        opts.effects = effects
                        -- The id rides the tooltip now that the column is gone. The
                        -- tooltip is sized EXACTLY by prepareTooltipContent, so the extra
                        -- line must pay for its own height or it clips.
                        local idLineH = ((ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14) + 4
                        ItemTooltip.beginItemTooltip(w, (h or 0) + idLineH)
                        ImGui.Text("Stats")
                        ImGui.Separator()
                        ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                        theme.TextMuted(string.format("id %s", tostring(entry.id)))
                        ImGui.EndTooltip()
                    end
                else
                    ImGui.BeginTooltip()
                    ImGui.Text(entry.name or "\xe2\x80\x94")
                    ImGui.Text("ID: " .. tostring(entry.id))
                    if inInv then ImGui.Text("In inventory (ready to roll)") elseif inBank then ImGui.Text("In bank" .. (bankConnected and " (bank open)" or " (bank not open)")) else ImGui.Text("Not in inventory or bank") end
                    ImGui.EndTooltip()
                end
            end
            if ImGui.IsItemClicked(ImGuiMouseButton.Left) then
                ctx.uiState[selectedKey] = entry.id
            end
            ctx.renderItemContextMenu(ctx, menuItem, {
                source = "reroll",
                popupId = "ItemContextReroll_" .. rowId,
                bankOpen = bankConnected,
                hasCursor = hasCursor,
                onRemoveFromRerollList = function(id) ctx.uiState[pendingRemoveKey] = id end,
                rerollEntryId = entry.id,
            })
            ImGui.PopID()

            -- Status column: Available or List Only
            ImGui.TableNextColumn()
            if inInv or inBank then
                theme.TextSuccess("Available")
            else
                theme.TextMuted("List Only")
            end

            -- Location column: Inventory, Bank, or —
            ImGui.TableNextColumn()
            if inInv then
                theme.TextSuccess("Inventory")
            elseif inBank then
                theme.TextWarning("Bank")
            else
                theme.TextMuted("\xe2\x80\x94")
            end
            ::continue::
        end
        end
        ImGui.EndTable()
    end
    end

    -- In your inventory: augments (or mythicals) currently in bags
    local prefix = REROLL.MYTHICAL_NAME_PREFIX or "Mythical"
    local invFiltered = {}
    for _, it in ipairs(inventoryItems) do
        if isAug then
            local t = (it.type or ""):match("^%s*(.-)%s*$")
            if t == AUGMENT_TYPE then table.insert(invFiltered, it) end
        else
            local name = it.name or ""
            if name:sub(1, #prefix) == prefix then table.insert(invFiltered, it) end
        end
    end
    ImGui.Spacing()
    if pendingCount and pendingCount > 0 then
        theme.TextHeader("Pending (sync in guild hall)")
        ImGui.Text(string.format("%d item(s) will be added to server list when you sync in guild hall.", pendingCount))
        local plist = isAug and rerollService.getPendingAugList() or rerollService.getPendingMythicalList()
        if plist and #plist > 0 and ImGui.BeginTable("RerollPending_" .. track, 2, ctx.uiState.tableFlags or 0) then
            ImGui.TableSetupColumn("Item Name", ImGuiTableColumnFlags.WidthStretch, 0, 0)
            ImGui.TableSetupColumn("", ImGuiTableColumnFlags.WidthFixed, 70, 1)
            ImGui.TableHeadersRow()
            for pidx, pe in ipairs(plist) do
                ImGui.PushID("RerollPending_" .. track .. "_" .. tostring(pidx))
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                theme.TextWarning(pe.name or ("ID " .. tostring(pe.id)))
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text(tostring(pe.name or "?"))
                    ImGui.Text(string.format("id %s . waiting to sync", tostring(pe.id)))
                    ImGui.EndTooltip()
                end
                ImGui.TableNextColumn()
                if ImGui.Button("Remove##RerollPending" .. tostring(pe.id), ImVec2(64, 0)) then
                    rerollService.removeFromPending(track, pe.id)
                end
                if ImGui.IsItemHovered() then
                    ImGui.BeginTooltip()
                    ImGui.Text("Remove from the pending list WITHOUT adding to the server list.")
                    ImGui.Text("Use this to clear stuck items (already added, sold, in the bank, etc.).")
                    ImGui.EndTooltip()
                end
                ImGui.PopID()
            end
            ImGui.EndTable()
        end
        ImGui.Spacing()
    end
    theme.TextHeader(isAug and "In your inventory (augmentations)" or "In your inventory (mythicals)")
    if #invFiltered == 0 then
        theme.TextMuted(isAug and "No augmentations in your bags." or "No mythical items in your bags.")
    else
        local invTableFlags = bit32.bor(ctx.uiState.tableFlags or 0, ImGuiTableFlags.Sortable)
        if ImGui.BeginTable("RerollInv_" .. track, 2, invTableFlags) then
            ImGui.TableSetupColumn("Item Name", bit32.bor(ImGuiTableColumnFlags.WidthStretch, ImGuiTableColumnFlags.Sortable), 0, 0)
            ImGui.TableSetupColumn("On list", ImGuiTableColumnFlags.WidthFixed, 70, 1)
            ImGui.TableSetupScrollFreeze(0, 1)
            ImGui.TableHeadersRow()
            for idx, it in ipairs(invFiltered) do
                ImGui.PushID("RerollInv_" .. track .. "_" .. tostring(idx))
                local id = it.id or it.ID
                local status = (id and rerollService.getListStatus) and rerollService.getListStatus(track, id) or nil
                local onList = status == "listed"
                local onPending = status == "pending"
                ImGui.TableNextRow()
                ImGui.TableNextColumn()
                local dispName = it.name or ("ID " .. tostring(id))
                if (it.stackSize or 1) > 1 then dispName = dispName .. string.format(" (x%d)", it.stackSize or 1) end
                if onList then
                    theme.TextSuccess(dispName)
                elseif onPending then
                    theme.TextWarning(dispName)
                else
                    ImGui.Text(dispName)
                end
                if ImGui.IsItemHovered() then
                    local showItem = ctx.getItemStatsForTooltip and ctx.getItemStatsForTooltip(it, "inv")
                    if showItem then
                        local opts = { source = "inv", bag = it.bag, slot = it.slot }
                        local effects, w, h = ItemTooltip.prepareTooltipContent(showItem, ctx, opts)
                        opts.effects = effects
                        -- Same contract as the server list: the id rides the tooltip and
                        -- pays for its own line, because the size is exact.
                        local idLineH = ((ImGui.GetTextLineHeight and ImGui.GetTextLineHeight()) or 14) + 4
                        ItemTooltip.beginItemTooltip(w, (h or 0) + idLineH)
                        ImGui.Text("Stats")
                        ImGui.Separator()
                        ItemTooltip.renderStatsTooltip(showItem, ctx, opts)
                        theme.TextMuted(string.format("id %s", tostring(id or "?")))
                        ImGui.EndTooltip()
                    else
                        ImGui.BeginTooltip()
                        ImGui.Text(tostring(it.name or "?"))
                        ImGui.Text(string.format("id %s", tostring(id or "?")))
                        ImGui.EndTooltip()
                    end
                end
                ImGui.TableNextColumn()
                if onList then
                    theme.TextSuccess("Yes")
                elseif onPending then
                    theme.TextWarning("Pending")
                else
                    theme.TextMuted("No")
                end
                ImGui.PopID()
            end
            ImGui.EndTable()
        end
    end
end

-- Render the full Reroll Companion window (tabs + content).
function RerollView.render(ctx)
    local state = registry.getWindowState("reroll")
    if not state.windowShouldDraw then return end

    local layoutConfig = ctx.layoutConfig or {}
    local layoutDefaults = ctx.layoutDefaults or {}
    local constants_views = constants.VIEWS or {}
    local w = layoutConfig.WidthRerollPanel or layoutDefaults.WidthRerollPanel or constants_views.WidthRerollPanel or 520
    local h = layoutConfig.HeightReroll or layoutDefaults.HeightReroll or constants_views.HeightReroll or 480

    local forceApply = ctx.uiState.layoutRevertedApplyFrames and ctx.uiState.layoutRevertedApplyFrames > 0
    local condPos = forceApply and ImGuiCond.Always or ImGuiCond.FirstUseEver
    local rx = layoutConfig.RerollWindowX or 0
    local ry = layoutConfig.RerollWindowY or 0
    if rx and ry and (rx ~= 0 or ry ~= 0) then
        ImGui.SetNextWindowPos(ImVec2(rx, ry), condPos)
    end
    if w > 0 and h > 0 then
        -- Size floor (handoff item 6): band + table header + three rows - below this the
        -- 26px band stat is the first casualty.
        ImGui.SetNextWindowSizeConstraints(ImVec2(420, 240), ImVec2(16384, 16384))
        ImGui.SetNextWindowSize(ImVec2(w, h), condPos)
    end

    local windowFlags = 0
    if ctx.uiState.uiLocked then
        windowFlags = bit32.bor(windowFlags, ImGuiWindowFlags.NoResize)
    end

    local winOpen, winVis = ImGui.Begin("CoOpt UI Reroll Companion##ItemUIReroll", state.windowOpen, windowFlags)
    registry.setWindowState("reroll", winOpen, winOpen)

    if not winOpen then ImGui.End(); return end
    if not winVis then ImGui.End(); return end
    local barsOn = tostring(layoutConfig.UIMode or "classic") == "bars"
    -- The kit band carries the pin in bars; the legacy checkbox row stays for classic.
    if not barsOn and ctx.renderWindowLock then ctx.renderWindowLock(ctx, "reroll") end

    if not ctx.uiState.uiLocked then
        local cw, ch = ImGui.GetWindowSize()
        if cw and ch and cw > 0 and ch > 0 then
            layoutConfig.WidthRerollPanel = cw
            layoutConfig.HeightReroll = ch
        end
    end
    local cx, cy = ImGui.GetWindowPos()
    if cx and cy and ctx.scheduleLayoutSave then
        if not layoutConfig.RerollWindowX or math.abs(layoutConfig.RerollWindowX - cx) > 1 or
           not layoutConfig.RerollWindowY or math.abs(layoutConfig.RerollWindowY - cy) > 1 then
            layoutConfig.RerollWindowX = cx
            layoutConfig.RerollWindowY = cy
            ctx.scheduleLayoutSave()
        end
    end

    local rerollService = ctx.rerollService
    if not rerollService then
        ctx.theme.TextMuted("Reroll service not available.")
        ImGui.End()
        return
    end

    -- 19d: the shared band, above the tab bar because it describes the window, not a tab.
    -- The stat is deliberately NOT the tray's "N of 10 ready" (each tab already says that
    -- for itself, and loudly) and not the bar chip's pending count either -- it is how big
    -- the two server lists are, which is the fact neither surface states.
    if barsOn then
        local augN = #((rerollService.getAugList and rerollService.getAugList()) or {})
        local mythN = #((rerollService.getMythicalList and rerollService.getMythicalList()) or {})
        windowHeader.render({
            id = "reroll", title = "Reroll",
            stat = string.format("on the server list: %d augs . %d mythics", augN, mythN),
            actions = {
                { label = windowHeader.GLYPHS.REFRESH, tooltip = "Request both lists from the server",
                  onClick = function()
                      if rerollService.requestBothLists then rerollService.requestBothLists() end
                  end },
            },
            lock = windowHeader.registryLock("reroll", ctx),
        })
    end

    -- Tab bar: Augments | Mythicals
    ctx.uiState.rerollTab = ctx.uiState.rerollTab or 1
    if ImGui.BeginTabBar("RerollTabs##ItemUI", ImGuiTabBarFlags.None) then
        if ImGui.BeginTabItem("Augments", nil, ImGuiTabItemFlags.None) then
            ctx.uiState.rerollTab = 1
            renderTabContent(ctx, "aug", rerollService)
            ImGui.EndTabItem()
        end
        if ImGui.BeginTabItem("Mythicals", nil, ImGuiTabItemFlags.None) then
            ctx.uiState.rerollTab = 2
            renderTabContent(ctx, "mythical", rerollService)
            ImGui.EndTabItem()
        end
        ImGui.EndTabBar()
    end

    ImGui.End()
end

-- Registry: Reroll module (Task 4.1 — second extraction)
registry.register({
    id          = "reroll",
    zone        = "R2",  -- window_zones placement column/slot (mockup 10a)
    label       = "Reroll",
    buttonWidth = 55,
    tooltip     = "Manage server augment and mythical reroll lists",
    layoutKeys  = { x = "RerollWindowX", y = "RerollWindowY" },
    enableKey   = "ShowRerollWindow",
    onOpen      = function() end,
    onClose     = function() end,
    onTick      = nil,
    render      = function(refs)
        local ctx = context.build()
        RerollView.render(ctx)
    end,
})

-- Test seams: the tray build and the blocked-reason are pure functions over plain
-- tables, and they are the whole of 20b's logic - what a roll would consume, and why it
-- cannot run. Exported so a suite can pin them without driving the window.
RerollView._buildTray = buildTray
RerollView._rollBlockedReason = rollBlockedReason

return RerollView
