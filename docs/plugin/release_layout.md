# Release Artifact Layout

**Task:** 4.1 — Define the CoOpt UI distribution zip layout.

---

## Directory layout

The CoOpt UI distribution zip extracts to a single root folder. Users run `MacroQuest.exe` from that folder; no other steps are required.

```
CoOptUI-v1.0.0/
  MacroQuest.exe                  # MQ launcher (from MQ build or official release)
  MQ2Main.dll                     # MQ core
  plugins/
    MQ2CoOptUI.dll                # CoOpt UI plugin
    MQ2Lua.dll                    # Lua scripting (from MQ build)
    MQ2Mono.dll                   # .NET hosting (for E3Next compatibility)
    MQ2Nav.dll                    # Navigation (if E3Next needs it)
    ...                           # Other MQ plugins from build
  lua/
    itemui/                       # CoOpt UI Lua source (entire tree)
    coopui/                       # CoOpt UI branded entrypoint
    scripttracker/                # ScriptTracker
    mq/                           # MQ Lua libs
  Macros/
    sell_config/                  # Sell configuration
    shared_config/                # Shared configuration
    loot_config/                  # Loot configuration
    sell.mac, loot.mac            # Macros
  resources/                      # UI resource files
  config_templates/               # Default configs
  E3 Bot Inis/                    # E3Next bot configurations (if bundled)
```

---

## Notes

- This layout matches the structure produced by **`create_mq64_coopui_copy.ps1`**.
- The packaging script (Task 4.2) and any patcher (Task 4.3) must follow this layout so that updates overwrite the correct paths.
- For a **32-bit EMU** distribution, the same layout applies; only the binaries (and optionally `MacroQuest.exe` from an EMU build) are 32-bit.
