# Graceful Degradation (Fallback Contract)

**Task:** 4.4 — Document the contract that every plugin capability has a Lua equivalent and that the absence of the plugin causes zero feature regression.

---

## Contract

| Capability   | Plugin API                          | Fallback when plugin absent                    | Fallback location |
|-------------|--------------------------------------|------------------------------------------------|-------------------|
| IPC         | `coopt.ipc.send` / `receive`         | `macro_bridge.lua` INI file reads/writes       | `services/macro_bridge.lua` |
| Window ops  | `coopt.window.click` / `waitOpen`    | `mq.cmdf('/notify ...')` + state machine       | `services/augment_ops.lua`, `services/sell_batch.lua` |
| Item scan   | `coopt.items.scanInventory` / `scanBank` | `buildItemFromMQ` TLO loop                  | `services/scan.lua` (lines 149–196), `utils/item_helpers.lua` |
| Loot events | `coopt.loot.pollEvents`              | `loot_feed_events.lua` + `macro_bridge.pollLootProgress` | `services/loot_feed_events.lua`, `services/macro_bridge.lua` |
| INI read/write | `coopt.ini.read` / `write` / `readBatch` | `config.safeIniValueByPath` / `mq.cmdf('/ini ...')` | `config.lua` |

---

## Enforcement

- The **plugin shim** (Task 6.1) is the single point of plugin detection. It exposes `pluginShim.isLoaded()`, `pluginShim.get()`, and capability accessors (`pluginShim.ipc()`, `.window()`, `.items()`, `.loot()`, `.ini()`).
- Call sites check the shim: if the plugin is present, they use the plugin API; otherwise they use the existing Lua/TLO implementation. No feature is removed when the plugin is absent.
- The scan fallback is already implemented in `scan.lua` via `tryCoopUIPlugin()`; that logic will be updated to use the shim (Task 6.4).
