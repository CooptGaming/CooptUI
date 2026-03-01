# CoOpt Plugin — Inactive (Paused)

**Status:** Plugin development has been paused. This documentation is preserved for future reference.

## What Was Done

The `feature/CoOptPlugin` branch contains exploratory work on a MacroQuest2 C++ plugin to complement the Lua-based CoOpt UI:

- **plugin_shim.lua** — Lua bridge to communicate with the plugin when loaded
- **scripts/rebuild-plugin.ps1** — Build automation for the plugin
- **scripts/bootstrap_dev.ps1** — Dev environment setup
- **macro_bridge.lua** changes — Plugin-aware IPC paths
- **config.lua / constants.lua** — Plugin-related config keys

## Where to Find It

- **Branch:** `feature/CoOptPlugin`
- **Base:** Branched from `5d308c5` (pre-Phase A–D)
- **Note:** The plugin branch diverged from master before Phases A–D and Phase E landed. Merging would require resolving structural differences (wiring→app, context_builder→context_init, config→settings).

## Build / Deploy Docs (if committed)

Commit `7ef19ac` referenced:

- `docs/plugin/MacroQuestCoOpt_build_and_updates.md`
- `docs/plugin/MacroQuestCoOpt_deploy.md`
- `.cursor/rules/mq-plugin-build-gotchas.mdc`

These may exist only in local working copies or unstaged files. If you have them, consider adding to this archive.

## Resuming Later

To resume plugin work:

1. Create a new branch from current `master` (which has Phase E).
2. Cherry-pick or manually port plugin-specific changes from `feature/CoOptPlugin`.
3. Adapt to current structure: `app.lua`, `context_init.lua`, `views/settings.lua`, `commands.lua`, etc.
