# CoOpt UI Troubleshooting Guide

## Quick Diagnostics

### Check Version

In the MQ2 console after loading ItemUI:
```
[ItemUI] Item UI v0.2.0-alpha loaded. /itemui or /inv to toggle. /dosell, /doloot for macros.
```

Version comes from `lua/coopui/version.lua`; your message may show a different version after updates.

If you don't see this message, ItemUI did not load successfully.

### Verify File Structure

Ensure these directories exist in your MQ2 root:
```
lua/itemui/init.lua           -- must exist
lua/itemui/config.lua         -- must exist
lua/itemui/rules.lua          -- must exist
lua/coopui/version.lua        -- must exist
lua/mq/ItemUtils.lua          -- must exist
Macros/sell_config/            -- must exist with INI files
Macros/shared_config/          -- must exist with INI files
Macros/loot_config/            -- must exist with INI files
```

### Console Commands

```
/itemui help    -- shows available commands
/itemui         -- toggles window (tests basic functionality)
```

---

## Common Issues

### "module not found" or require errors

**Cause:** Incomplete extraction or double-nested folders.

**Fix:**
1. Check that `lua/itemui/init.lua` exists (not `lua/itemui/itemui/init.lua` — double-nesting)
2. Re-extract the release zip, ensuring you extracted into the MQ2 root folder
3. Verify the `lua/` folder merges with the existing one (not nested inside another folder)

**Symptoms:**
```
[MQ2Lua] Error: module 'itemui.config' not found
[MQ2Lua] Error: module 'itemui.rules' not found
```

---

### Window doesn't open

**Cause:** ImGui not loaded, or ItemUI already running.

**Fix:**
1. Ensure the ImGui plugin is loaded: check MQ2 plugin list
2. Try `/lua stop itemui` first, then `/lua run itemui`
3. Try `/itemui show` to force the window visible
4. Check the MQ2 console for error messages

---

### Config files not loading / defaults everywhere

**Cause:** Missing config directories or first-time setup not completed.

**Fix:**
1. Check that `Macros/sell_config/`, `Macros/shared_config/`, and `Macros/loot_config/` exist
2. If missing, copy from `config_templates/` in the release zip, or run ItemUI and open Config — on first run it may load default protection if `sell_flags.ini` is missing
3. Check that INI files have content (not empty)
4. Try clicking "Reload from files" in the Config window

---

### Sell macro not working

**Symptoms:** Items not selling, or wrong items being sold.

#### Items not selling when they should

**Cause:** Protection flags or value thresholds are too strict.

**Fix:**
1. Open Config > General & Sell tab
2. Check protection flags — `protectNoDrop`, `protectLore`, etc. may be blocking sales
3. Check `minSellValue` and `minSellValueStack` in `sell_value.ini` — items below these thresholds are kept
4. Check if the item is in a keep list: `sell_keep_exact.ini`, `valuable_exact.ini`
5. Check `maxKeepValue` — items above this value are automatically kept

#### Items selling that shouldn't

**Cause:** Item not in any keep/protect list.

**Fix:**
1. Add the item to the keep list: click Keep in the sell view, or add to `sell_keep_exact.ini`
2. If it's a type of item (e.g., all Augmentations), add to `sell_keep_types.ini` or `sell_protected_types.ini`

#### Sell macro timing out

**Cause:** Server lag causing sell operations to fail.

**Fix:**
1. Increase `sellWaitTicks` in `sell_value.ini` (default 30 = 3 sec; try 50+ for laggy connections)
2. Increase `sellRetries` in `sell_value.ini` (default 4)

---

### Loot macro not working

#### Not looting valuable items

**Cause:** Value thresholds set too high.

**Fix:**
1. Check `minLootValue` in `loot_value.ini` (default 999 copper = ~1pp)
2. Check `minLootValueStack` (default 200 copper)
3. Add the item to `loot_always_exact.ini` or `valuable_exact.ini`

#### Looting unwanted items

**Fix:**
1. Add to `loot_skip_exact.ini` for specific items
2. Add keywords to `loot_skip_contains.ini` for patterns
3. Add types to `loot_skip_types.ini` for entire item categories

#### Lore duplicate issues

**Cause:** Attempting to loot a lore item you already own will close the loot window and stop all looting.

The macro checks both inventory and bank before looting lore items. If the check fails:
1. Ensure your bank data is up-to-date (open bank window with ItemUI running)
2. The lore check is hardcoded and cannot be disabled

#### Loop limit reached

**Symptoms:** Macro ends with "loop limit reached" message.

**Fix:** This is a safety limit to prevent infinite loops. If legitimate, the macro will continue on the next `/doloot` call.

---

### Bank shows "Historic" when banker is open

**Cause:** The bank window needs to be detected as open by MQ2.

**Fix:**
1. Ensure you are interacting with the banker NPC (not just standing near them)
2. The EQ bank window must be open for live bank data
3. Try `/itemui refresh` to force a rescan
4. Close and reopen the bank window

---

### Window position/size issues

#### Window too small or off-screen

**Fix:**
1. Delete `Macros/sell_config/itemui_layout.ini` to reset layout to defaults
2. Restart ItemUI: `/lua stop itemui` then `/lua run itemui`

#### Window not snapping correctly

**Fix:**
1. Open Config > check/uncheck "Snap to Inventory" or "Snap to Merchant"
2. Use `/itemui setup` to enter setup mode and resize panels

#### Reset to default button doesn't resize immediately

This is expected ImGui behavior — windows don't programmatically resize while open. Close and reopen ItemUI after clicking "Reset to Default".

---

### Performance issues

#### High CPU usage

**Fix:**
1. Enable "Suppress when loot.mac running" in Config to prevent UI updates during macro execution
2. Avoid running multiple CoOpt UI instances simultaneously
3. Close the bank panel when not needed

#### Slow UI open

The UI should open in ~15ms. If it's slow:
1. Check for error messages in console
2. Large inventories (100+ items) may take slightly longer on first scan
3. Subsequent opens use cached data and should be instant

---

### ScriptTracker issues

#### ScriptTracker not loading

**Fix:**
1. Ensure `lua/scripttracker/init.lua` exists
2. Run `/lua run scripttracker`
3. Check console for errors

#### ScriptTracker not refreshing

ScriptTracker auto-refreshes on inventory changes. To force refresh:
1. Close and reopen the ScriptTracker window: `/scripttracker`
2. Open your inventory to trigger a fingerprint change

---

## Error Messages Reference

### "too many upvalues"

```
[MQ2Lua] Error: too many upvalues
```

**Cause:** A Lua closure references more than 60 variables from outer scopes.

**Context:** This is a Lua language limit. CoOpt UI uses the context registry pattern (`context.lua`) to work around it. If you see this error after modifying code, you've added too many local variables to a function that's captured by a closure.

**Fix for developers:** Consolidate variables into tables or use `context.build()` to access shared state through a single metatable proxy.

### "attempt to call a nil value"

```
[MQ2Lua] Error: attempt to call a nil value
```

**Cause:** A function reference is missing, usually due to:
- Module not loaded (check `require` statements)
- Dependency not passed in `init(deps)` call
- Typo in function name

**Fix:** Check the full error message for the file and line number. Verify the referenced function exists and is properly exported.

### "too many local variables in function"

```
[MQ2Lua] Error: too many local variables in function
```

**Cause:** A function scope has more than 200 local variables.

**Context:** CoOpt UI uses state tables (`uiState`, `sortState`, etc.) to consolidate locals. If you see this after modifying code, you've added too many `local` declarations.

**Fix for developers:** Move new variables into existing state tables rather than declaring new locals.

---

## Reporting Issues

If you encounter a bug not covered here:

1. **Check the console** for error messages (copy the full error including file/line)
2. **Note the steps** to reproduce the issue
3. **Note your version** (shown on load in console)
4. **Open an issue** at: https://github.com/CooptGaming/CoopUI/issues

Include:
- CoOpt UI version
- MQ2 version (if known)
- Full error message from console
- Steps to reproduce
- What you expected vs what happened
