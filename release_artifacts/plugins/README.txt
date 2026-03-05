MQ2CoOptUI — Optional plugin for CoOpt UI
=========================================

This plugin is OPTIONAL. CoOpt UI works fully without it (using Lua/TLO). The plugin adds faster scanning and IPC streaming for auto-sell and auto-loot.

REQUIREMENTS
------------
- MacroQuest build from the E3Next prebuilt (same build this DLL was compiled with).
- Do NOT use this DLL with a different MQ build (e.g. different MQ version or Live vs EMU); it can crash due to ABI mismatch.

INSTALL
-------
1. Copy MQ2CoOptUI.dll into your MacroQuest plugins folder (e.g. MacroQuest\plugins\).
2. Ensure your MQ install is the E3Next prebuilt that matches this build.
3. In-game: /plugin MQ2CoOptUI (or enable it in MacroQuest.ini).

If you use a different MQ build, build the plugin from source instead. See the CoOpt UI repo docs/plugin/dev_setup.md.
