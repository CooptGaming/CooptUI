# Win32 (32-bit) Build Viability

**Task:** 1.1 — Investigate whether the official MacroQuest source builds as Win32 and whether our plugin can target it.

**Date:** 2025-02-28

---

## Summary

| Item | Result |
|------|--------|
| **CMake Win32 support** | **Pass** — MQ CMake explicitly supports `-A Win32` (see root `CMakeLists.txt` and `ci_shared.yaml`: `client_target: emu` → `Platform: Win32`). |
| **Local configure (EMU source zip)** | **Blocked** — Configure failed: vcpkg toolchain file not found. Pre-downloaded EMU source at `C:\MIS\MacroquestEnvironments\MacroquestEMU\...` does not include a bootstrapped `contrib/vcpkg` (no `scripts/buildsystems/vcpkg.cmake`). |
| **Local build** | **Not run** — Build not attempted until configure succeeds. |

---

## Evidence

### CMake and CI support Win32

- Root `CMakeLists.txt`: `if(CMAKE_GENERATOR_PLATFORM STREQUAL "Win32")` sets `VCPKG_TARGET_TRIPLET` to `x86-windows-static` and documents `cmake -B build_win32 -G "Visual Studio 17 2022" -A Win32`.
- Official CI (`.github/workflows/ci_shared.yaml`): `platform: "${{ inputs.client_target == 'emu' && 'Win32' || 'x64' }}"` — EMU builds use Win32.
- EMU release is built from the same repo with `eqlib` on the `emu` branch and produces 32-bit binaries.

### Local configure attempt (EMU source)

**Command (from EMU repo root):**

```powershell
$env:VCPKG_ROOT = "C:\MIS\MacroquestEnvironments\MacroquestEMU\macroquest-rel-emu\macroquest-rel-emu\contrib\vcpkg"
cmake -B build_win32 -G "Visual Studio 17 2022" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=OFF
```

**Result:** CMake error before `project()`:

```
Could not find toolchain file: "/scripts/buildsystems/vcpkg.cmake"
```

**Cause:** In the downloaded EMU source zip, `contrib/vcpkg/scripts/buildsystems/vcpkg.cmake` does not exist (vcpkg is likely a submodule or not fully included in the source package). So `VCPKG_ROOT` pointed at a valid directory but the toolchain file was missing.

---

## Recommendation

1. **Proceed with 64-bit as primary.** The plan’s Option B (own distribution, 64-bit MQ + plugin) is unchanged. Use `create_mq64_coopui_copy.ps1` and a full MQ clone with `-A x64` for development and release.
2. **Treat 32-bit as optional.** Use a full MacroQuest clone with submodules and vcpkg bootstrapped: either the **EMU full clone** at `C:\MIS\MacroquestEnvironments\MacroquestEMU\macroquest-clone\`, or a single clone with `git -C src/eqlib checkout emu`. Set `VCPKG_ROOT` to that clone’s `contrib/vcpkg`, then run `cmake -B build_win32 -G "Visual Studio 17 2022" -A Win32 -DMQ_BUILD_CUSTOM_PLUGINS=ON`. If configure and build succeed, the plugin can be built for Win32 the same way (symlink plugin into `src/plugins/MQ2CoOptUI` and build).
3. **Do not block Phase 2+ on Win32.** Task 1.2 (dev setup) and bootstrap script should document the **x64** path as the primary flow and add an optional “Building for EMU (Win32)” section that references a full clone + eqlib `emu` branch + vcpkg bootstrap.

---

## Next steps (optional, time-boxed)

- Use the full EMU clone at `C:\MIS\MacroquestEnvironments\MacroquestEMU\macroquest-clone\` (vcpkg already bootstrapped), set `VCPKG_ROOT` to that path’s `contrib\vcpkg`, then run the Win32 configure and build to confirm end-to-end 32-bit build and update this document with pass/fail and any error excerpts.
