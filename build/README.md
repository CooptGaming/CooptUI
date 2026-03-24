# CoOpt UI Build System

Python-based build and distribution for CoOpt UI. Replaces prior PowerShell scripts.

## Quick Start

```bash
# From repo root
python build/build.py --output C:\path\to\output
```

## Outputs

1. **Full Build Folder** (`output/full_build/`) — Complete MQ2 + E3Next + MQ2Mono + CoOpt UI + Patcher + Plugin
2. **CoOptUI-Full_vX.X.zip** — Full folder zipped (E3Next + Mono + CoOptUI + Patcher + Plugin)
3. **CoOptUI-Patcher-Plugin_vX.X.zip** — CoOptUI files + Patcher + MQ2CoOptUI.dll
4. **CoOptUI-PatcherOnly_vX.X.zip** — Just CoOptUIPatcher.exe
5. **CoOptUI-Patcher_vX.X.zip** — CoOptUI files + Patcher (no plugin)

## Options

| Option | Description |
|--------|-------------|
| `--output`, `-o` | **Required.** Destination directory |
| `--skip-full-build` | Only create distribution ZIP (no binary bundle download) |
| `--skip-dist-zip` | Only create full build folder |
| `--version` | Version string for zip name (default: 1.0.0 or `RELEASE_VERSION`) |
| `--build-plugin` | Build MQ2CoOptUI plugin from source (clone MacroQuest, CMake, VS2022) |
| `--cmake-path` | Path to CMake (default: `C:\MIS\CMake-3.30`) |
| `--mq-ref` | MacroQuest ref: branch, tag, or SHA (default: `plugin/MQ_COMMIT_SHA.txt` or `main`) |

## Requirements

- Python 3.9+
- `dotnet` (for CoopHelper.dll)
- `PyInstaller` (for CoOptUIPatcher.exe) — installed via `patcher/requirements.txt`

**For `--build-plugin`:** git, CMake 3.30 (e.g. `C:\MIS\CMake-3.30`), Visual Studio 2022 with C++ workload.

## See Also

- [docs/RELEASE_PROCESS.md](../docs/RELEASE_PROCESS.md) — GitHub sync and release workflow
