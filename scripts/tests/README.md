# Regression tests

Small, dependency-free tests for bugs that were fixed and must not come back. They live
under `scripts/` on purpose: `scripts/` is never staged into the EMU bundle and is not in
`release_manifest.json`, so nothing here ships to players.

There is no test framework. Each test is a standalone script that exits non-zero on failure.

## Running them

```powershell
.\scripts\tests\run-tests.ps1
```

`run-tests.ps1` needs a LuaJIT binary for the Lua tests. It finds one automatically inside any
Build-Smart output tree (`<OutputDir>\.mq-source\...\tools\luajit\luajit.exe`), or you can point
it at one:

```powershell
.\scripts\tests\run-tests.ps1 -LuaJit "C:\path\to\luajit.exe"
```

`$env:COOPT_LUAJIT` works too. **A skipped test exits non-zero on purpose** — this is a release
gate, and "I could not run" must not look the same as "everything passed".

Use **LuaJIT**, not Lua 5.4 — MQ2Lua is LuaJIT (Lua 5.1 semantics), and the point of running
the game's own interpreter is to catch things a newer Lua would accept.

## What is covered

| Test | Guards against |
|------|----------------|
| `test_skin_sync.lua` | The CoOpt skin failing to install when `lfs` is unavailable in MQ2Lua, and a skin file being left **missing** in the EQ client when the tmp→destination rename fails. Also pins the opt-in contract (a maintenance sync must never install uninvited), incremental copy, and retired-file removal. |
| `test_patcher_preflight.py` | The patcher starting a write over a live MacroQuest install. Covers the lock probe that catches a running MQ tray even when it runs under a randomised process name, which the process-name check cannot see. |
| `test_reroll_service.lua` | The reroll id lists (a sell/loot **protection** set) being silently destroyed: (a) starting CoOpt before the character resolves persisting empty lists over the user's cache, (b) a stray chat line that looks like a list header wiping a list outside any request window. Also pins that a normal Refresh still resets and refills the list. |

## The other two gates

These tests do not replace the two static gates that must pass after any Lua change:

- **luacheck** — `luacheck lua/itemui lua/coopui` (see `.github/workflows/luacheck.yml`).
- **LuaJIT compile sweep** — `loadfile()` every file under `lua/`. This is the only thing that
  catches LuaJIT's 60-upvalues-per-function limit, which luacheck and Lua 5.4 both allow and
  which has broken the addon in-game before.

`run-tests.ps1 -All` runs the compile sweep as well.
