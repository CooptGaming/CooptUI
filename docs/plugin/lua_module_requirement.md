# Lua Module Requirement (CreateLuaModule)

When you see:

```text
[CoOpt UI] CoOptUI TLO present but Lua module not found. Using Lua fallback. (Plugin may need CreateLuaModule.)
```

it means the **MQ2CoOptUI** plugin DLL is loaded and has registered the **CoOptUI TLO** (so `${CoOptUI.Version}` etc. work), but **no Lua module** is registered. CoOpt UI’s Lua code uses `require("plugin.MQ2CoOptUI")` or `require("plugin.CoOptUI")` to get the capability table (`ipc`, `window`, `items`, `loot`, `ini`). If that `require` fails, the shim falls back to Lua/TLO and prints the message above.

## Setup (ensuring CreateLuaModule is exported)

The plugin uses `MQ2CoOptUI.def` to force-export `CreateLuaModule` so MQ2Lua's `GetProcAddress` can find it. If you build the plugin yourself:

1. Ensure `plugin/MQ2CoOptUI/MQ2CoOptUI.def` exists and contains `EXPORTS CreateLuaModule`.
2. Rebuild the plugin (e.g. via the plugin-build workflow or locally under MQ's tree).
3. Copy the new `MQ2CoOptUI.dll` into MQ's `plugins/` folder and restart.

To verify the export:

```powershell
dumpbin /exports path\to\MQ2CoOptUI.dll | findstr CreateLuaModule
```

You should see `CreateLuaModule` in the output.

## What the C++ plugin must do

The plugin must **expose a Lua module** so that:

- `require("plugin.MQ2CoOptUI")` or `require("plugin.CoOptUI")` succeeds, and  
- the returned value is a **table** with (at least) these keys: `ipc`, `window`, `items`, `loot`, `ini`.

In MacroQuest, this is done by implementing and registering **CreateLuaModule** (or the equivalent API your MQ build uses for plugin-provided Lua modules). The implementation should:

1. Create a Lua table (e.g. via sol2).
2. Attach sub-tables or functions for each capability:
   - `ipc` — e.g. `send`, `receive`, `peek`, `clear`
   - `window` — e.g. `click`, `isWindowOpen`, etc.
   - `items` — e.g. `scanInventory`, `scanBank`, `getItem`
   - `loot` — e.g. `pollEvents`
   - `ini` — e.g. `read`, `write`, `readBatch`, `readSection`
3. Return that table as the module so `require("plugin.MQ2CoOptUI")` (or `"plugin.CoOptUI"`) gets it.

Exact function name and signature depend on your MQ version; check the **MQ2Lua** (or main MQ) source for how plugins register Lua modules (e.g. search for `CreateLuaModule` or “plugin” + “require” in the MQ repo).

## How to confirm it works

After the plugin correctly exposes the Lua module:

1. Restart CoOpt UI (e.g. `/lua end itemui` then run itemui again).
2. You should see in the console:
   ```text
   [CoOpt UI] Plugin MQ2CoOptUI v1.0.0 loaded (API 1) — using plugin for scan, IPC, INI, window ops.
   ```
3. When an inventory scan uses the plugin, the profile line will include `(plugin)`:
   ```text
   [CoOpt UI Profile] scanInventory: scan=... ms, save=... ms (187 items) (plugin)
   ```

Until the plugin registers this Lua module, CoOpt UI will keep using the Lua fallback and the “Lua module not found” message will continue to appear. Functionality is unchanged; only the high-performance plugin paths (batch scan, IPC, etc.) are unused.

## TLO present but Lua module not found (DLL is correct)

If you verified that your DLL exports `CreateLuaModule` (e.g. `dumpbin /exports …\MQ2CoOptUI.dll | findstr CreateLuaModule`) and you still see "CoOptUI TLO present but Lua module not found", then **the running game is loading the plugin from a different folder** than the one where you put the new DLL.

MacroQuest loads plugins from the `plugins` directory of the **MQ install that is actually running** (the folder containing the launcher/injector that started the game). That path can differ from your repo or a second install.

**What to do:**

1. **Find the plugins path MQ is using** — In-game, run: `/echo ${MacroQuest.Path[plugins]}` (or from Lua: `print(mq.TLO.MacroQuest.Path("plugins"))`). Note the full path.
2. **Copy the new DLL into that folder** — Copy the DLL you built into the folder from step 1 and overwrite `MQ2CoOptUI.dll` there.
3. **Restart MQ / game** so the new DLL is loaded, then run `/lua run itemui` again.

If the `require` error listed paths under another folder (e.g. `C:\AnotherMQInstall`), copy the DLL into that install's `plugins` folder as well.

## MQ build must include the plugin require() loader

The Lua `require("plugin.MQ2CoOptUI")` is handled by a **custom package loader** inside **MQ2Lua** (see `LuaThread.cpp` → `PackageLoader`). If your MQ install was not built from a tree that includes this loader (e.g. an older or prebuilt MQ2Lua), then `require` will never call the plugin and you will always see "module not found" and the long list of file paths.

**Fix:** Run **MacroQuest** (not EverQuest) from a build that includes the plugin loader. MQ and EQ are separate installs: EQ stays where it is; only which MQ executable you run matters.

1. Build full MQ (including MQ2Lua) from the same tree you use for MQ2CoOptUI (e.g. `C:\MQ-EMU-Dev\macroquest`).
2. Run **MacroQuest.exe** (or the MQ launcher) from that build’s **output** folder. With CMake this is `macroquest-clone\build\bin\release\` (not `build\solution\` — solution holds the .sln; binaries go in `build\bin\release\`). That folder is your “MQ install” for this: put `MQ2CoOptUI.dll` in its `plugins` subfolder. If you don’t see `MacroQuest.exe`, ensure the launcher was built (don’t use `-SkipLauncher` or `MQ_BUILD_LOADER=OFF`).
3. EverQuest stays in its current install folder (e.g. elsewhere on the same machine). Configure or launch EQ as you normally do (MQ’s config or launcher usually points to your EQ path). When you play, you are running **this** MQ build against your existing EQ install.

Do not use a different MQ install (e.g. from a release zip or another path) unless you know its MQ2Lua has the plugin loader.
