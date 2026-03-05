# MQ Version Pinning Policy

**Task:** 3.3 — Define how the CoOpt UI project tracks the upstream MacroQuest version.

---

## Pin to a specific MQ commit

- CoOpt UI **pins** to a specific MacroQuest **commit hash**, not to `master`/`main` HEAD.
- The pin is stored in **`plugin/MQ_COMMIT_SHA.txt`** (or via a git submodule reference). CI and packaging scripts read this file to clone/checkout the exact commit.
- **Do not** track the latest MQ commit automatically; every build must use the pinned commit for reproducibility and ABI compatibility.

---

## Rationale

- MQ internal structures (vtables, struct layouts, plugin API) change with EQ patches and MQ updates. A plugin DLL built against one MQ commit can crash or fail to load when used with another.
- CI must build against the **exact** pinned commit so that the produced `MQ2CoOptUI.dll` matches the MQ build shipped in the CoOpt UI distribution.

---

## Update cadence

- When a new MQ release is tagged (e.g. after a Live EQ patch), maintainers:
  1. Update the pin in `plugin/MQ_COMMIT_SHA.txt` to the new commit/tag.
  2. Rebuild MQ and the plugin (both architectures if applicable).
  3. Smoke-test the distribution, then release a new CoOpt UI version.

---

## EMU (32-bit) consideration

- EMU builds use the **`emu`** branch of the **`eqlib`** submodule and produce **Win32** binaries.
- EMU client versions change less often than Live. The EMU pin can be updated on a different cadence and should be documented (e.g. “MQ EMU @ commit xyz” in release notes).
- Distribution zips must be clearly labeled: **Live 64-bit** vs **EMU 32-bit** and, when relevant, target EQ client version.

---

## Version TLO

- The plugin exposes **`CoOptUI.Version`** (e.g. `"1.0.0-mq:abc1234"`) and, when implemented, **`CoOptUI.MQCommit`** so Lua can warn if the running MQ build does not match the build the plugin was compiled against.

---

## Tradeoff

| Approach | Pros | Cons |
|----------|------|------|
| **Pinning** | Reproducible builds; no surprise breakage from MQ changes. | Manual updates; we don’t automatically get MQ bugfixes. |
| **Tracking latest** | Always on newest MQ. | Any MQ push can break the plugin; unstable for users. |

**Policy:** Pinning is required. Update cost is manual and bounded (rebuild + smoke test).
