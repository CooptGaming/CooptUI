# Compatibility Matrix

**Task:** 4.5 — Document which CoOpt UI, plugin, and MQ versions work together.

---

## Matrix

| CoOpt UI Version | Plugin Version | MQ Build              | EQ Client   | Notes |
|------------------|----------------|------------------------|------------|-------|
| v2.x (current)   | none          | any (E3Next 32-bit)    | EMU 32-bit | Full Lua, no plugin. |
| v3.0+            | 1.0.0         | MQ Live @ pinned (64-bit) | Live 64-bit  | Plugin active. |
| v3.0+            | 1.0.0         | MQ EMU @ pinned (32-bit)  | EMU 32-bit  | Plugin active if Win32 build is offered. |
| v3.0+            | none          | any (E3Next 32-bit)   | EMU 32-bit | Lua fallback; no regression. |
| v3.0+            | 1.0.0         | wrong MQ build        | any        | Plugin may warn or fail to load; Lua fallback used. |

---

## Version checks

- The plugin exposes **`APIVersion`** (and optionally **`Version`**, **`MQCommit`**) via the `CoOptUI` TLO. The Lua shim (Task 6.1) checks `APIVersion` against `REQUIRED_API_VERSION` in `constants.lua` and falls back to Lua if the plugin is missing or incompatible.
- This document should be updated with each release (CoOpt UI version, plugin version, and which MQ commit each distribution was built against).
