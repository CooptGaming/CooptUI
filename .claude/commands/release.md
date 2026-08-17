---
description: Cut a CoOpt UI release — gate on luacheck and the LuaJIT test sweep, dry-run the pipeline, then run release-all.ps1. Knows why releases are local-only and which CMake is required.
---

You are cutting a CoOpt UI release. `scripts/release-all.ps1` does the actual work
(manifest → commit → tag → push → local builds → create release → publish). Your job is
to run the gates before it, drive it safely, and stop the moment something looks wrong.

**A release ships to players running this inside a live game.** The bug class that matters
here loads fine and crashes someone mid-raid. Never skip the gates to save time.

## Why this is local-only

Do not suggest moving this to CI. GitHub-hosted runners ship **CMake 4.x**; the EMU bundle
needs **CMake 3.x** (`release-all.ps1` defaults to `C:\MIS\CMake-3.30`) plus Visual Studio
2022 with MSVC toolset 14.44.35207, the Mono SDK, and the .NET SDK. That is why
`.github/workflows/release.yml` is manual-dispatch only and builds nothing but the patcher.

## Step 1 — establish the version

Read `lua/coopui/version.lua`. **PACKAGE is the source of truth.** Version numbers in
`.md` files go stale and must not be trusted. Report the version you found and what the
last tag was (`git tag -l | tail -3`) before going further.

## Step 2 — the gates, in this order

Run luacheck. This is the same command CI runs, so a failure here fails CI too:

```
luacheck lua/itemui lua/coopui
```

Then the regression tests **with `-All`**:

```
powershell -File .\scripts\tests\run-tests.ps1 -All
```

`-All` adds the LuaJIT compile sweep, which is the only check that catches the 60-upvalue
limit — luacheck and Lua 5.4 both miss it. If the runner reports Lua tests as **skipped**
because no LuaJIT was found, say so plainly and treat it as a gate that did not run. Skipped
is not passed.

If either gate fails, stop and report. Do not proceed to a dry run with a failing gate.

## Step 3 — confirm the tree

`git status` must be clean and you must be on `master`. Uncommitted work at release time
means the tag will not describe what shipped. Surface anything unexpected and ask before
continuing.

## Step 4 — dry run, always

```
powershell -File .\scripts\release-all.ps1 -DryRun
```

Walk the user through what it reports: the version it resolved, the tag it will create, the
assets it will build, and whether it found an existing release it would overwrite. Do not
proceed until they confirm.

## Step 5 — cut it

```
powershell -File .\scripts\release-all.ps1
```

Useful variants, offered when they fit:

- `-SkipEMU` — CoOpt UI ZIP + patcher only. Correct when the full MQ/Mono/E3 toolchain is
  unavailable on this machine; check with `.\Build-Smart.ps1 -CheckPrereqs` if unsure.
- `-SkipPublish` — build and upload, leave the release as a draft for review.
- `-Version "1.2.0"` — override the resolved version.
- `-Force` — no prompts, overwrite an existing release. Only with explicit say-so.

Prerequisites the script checks but worth knowing: `git`, `python`, and an authenticated
`gh` CLI. If the EMU ZIP needs attaching to an existing release separately, that is
`scripts/upload-emu-zip.ps1 -ZipPath <path>`.

## After

Report the tag, the release URL, and which assets actually attached. If the release was left
as a draft, say so explicitly — a draft nobody publishes looks identical to a successful
release from the terminal output alone.
