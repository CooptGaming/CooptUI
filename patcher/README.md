# CoOpt UI Patcher

Desktop application that updates **CoOpt UI project files** (ItemUI, ScriptTracker, macros, resources) in your MacroQuest root. It validates the MQ directory, fetches a release manifest, compares local files by hash, and downloads only changed files via raw GitHub URLs.

**New in v2:** The patcher can be launched from anywhere — no need to run it from your MQ root. It auto-detects installations, remembers your last folder, and can do a fresh install from GitHub Releases.

## Quick Start

1. **Double-click `CoOptUIPatcher.exe`** from anywhere (Desktop, Downloads, etc.)
2. On first run, choose:
   - **"I already have MacroQuest"** — browse to your MQ folder
   - **"Fresh install"** — pick a destination folder and the patcher downloads everything
3. The patcher remembers your folder for next time

## Requirements

- Windows (MacroQuest is Windows-only)
- For building from source: Python 3.10+

## Run from source

1. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```
2. Run the patcher:
   ```bash
   cd patcher
   python patcher.py
   ```
   The patcher will show a folder picker if no saved path exists. You can also pass to an MQ root directory by running from that directory.

## Build a single .exe (PyInstaller)

1. **Install dependencies** (includes PyInstaller and Pillow):
   ```bash
   cd patcher
   pip install -r requirements.txt
   ```

2. **Create the .exe icon** from the CooptGaming banner:
   ```bash
   python build_icon.py
   ```

3. **Build the executable**:
   ```bash
   pyinstaller patcher.spec
   ```

4. **Output:** `patcher/dist/CoOptUIPatcher.exe`

The exe can be placed anywhere — it saves its config (`patcher_config.json`) next to itself.

## Configuration files

### patcher_config.json

Saved next to the exe. Stores the last-used MQ root and recent paths:

```json
{
  "mq_root": "C:\\Games\\MacroQuest",
  "recent_paths": [
    "C:\\Games\\MacroQuest",
    "D:\\EQ\\MQ2"
  ]
}
```

### release_manifest.json

Fetched from the repo at runtime. Schema:

```json
{
  "version": "1.0.0",
  "changelog": [
    "### Fixed",
    "Sell macro gold calculation",
    "### Added",
    "Augment pool sorting"
  ],
  "files": [
    { "path": "lua/itemui/init.lua", "hash": "<sha256 hex>" }
  ]
}
```

- `version`: CoOpt UI version string
- `changelog`: Array of changelog entries (from CHANGELOG.md, parsed by generate_manifest.py)
- `files[].path`: relative path from repo root
- `files[].hash`: SHA256 hex digest

### default_config_manifest.json

Maps template config files to install paths. Patcher installs only when the file doesn't exist (create-if-missing, never overwrites user data).

## Fresh install

The patcher queries the GitHub Releases API for the latest published release, downloads the ZIP asset, and extracts it into the chosen folder. Draft releases are skipped. Requires at least one published release on the repo.

## When do users get updates?

The patcher only offers files listed in the manifest. During development, push code freely — users won't see changes until you regenerate and push the manifest:

```bash
python patcher/generate_manifest.py           # release manifest
python patcher/generate_default_config_manifest.py  # default config manifest
```

## Auto-detection

The patcher scans for MacroQuest installations in:
- Windows registry (Daybreak/SOE EverQuest install paths)
- Common filesystem locations (drive roots, Games/, EQ/ folders)
- Previously used paths (from patcher_config.json)

## Module overview

| File | Role |
|---|---|
| `patcher.py` | GUI application (Setup/Main views) |
| `updater.py` | Manifest fetch, hash comparison, file download, verification |
| `validator.py` | MQ root validation (three-tier: valid, fixable, invalid) |
| `config.py` | Persistent config (load/save patcher_config.json) |
| `path_finder.py` | Auto-detect MQ installations |
| `fresh_install.py` | GitHub Releases API, ZIP download/extract |
| `migrate_itemui_to_coopui.py` | One-time migration from old layout |
| `generate_manifest.py` | Dev tool: generate release_manifest.json |
| `generate_default_config_manifest.py` | Dev tool: generate default_config_manifest.json |
| `build_icon.py` | Dev tool: generate icon.ico from banner.png |
