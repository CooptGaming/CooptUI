# Regression tests

Small, dependency-free tests for bugs that were fixed and must not come back. They live
under `scripts/` on purpose: `scripts/` is never staged into the EMU bundle and is not in
`release_manifest.json`, so nothing here ships to players.

There is no test framework. Each test is a standalone script that exits non-zero on failure.

## Running them

```powershell
.\scripts\tests\run-tests.ps1
```

`run-tests.ps1` needs a LuaJIT binary for the Lua tests. It looks for one in the build tree
and accepts an override:

```powershell
.\scripts\tests\run-tests.ps1 -LuaJit "C:\path\to\luajit.exe"
```

Use **LuaJIT**, not Lua 5.4 — MQ2Lua is LuaJIT (Lua 5.1 semantics), and the point of running
the game's own interpreter is to catch things a newer Lua would accept.

## What is covered

| Test | Guards against |
|------|----------------|
| `test_skin_sync.lua` | The CoOpt skin failing to install when `lfs` is unavailable in MQ2Lua, and a skin file being left **missing** in the EQ client when the tmp→destination rename fails. Also pins the opt-in contract (a maintenance sync must never install uninvited), incremental copy, and retired-file removal. |
| `test_patcher_preflight.py` | The patcher starting a write over a live MacroQuest install. Covers the lock probe that catches a running MQ tray even when it runs under a randomised process name, which the process-name check cannot see. |

## The other two gates

These tests do not replace the two static gates that must pass after any Lua change:

- **luacheck** — `luacheck lua/itemui lua/coopui` (see `.github/workflows/luacheck.yml`).
- **LuaJIT compile sweep** — `loadfile()` every file under `lua/`. This is the only thing that
  catches LuaJIT's 60-upvalues-per-function limit, which luacheck and Lua 5.4 both allow and
  which has broken the addon in-game before.

`run-tests.ps1 -All` runs the compile sweep as well.
