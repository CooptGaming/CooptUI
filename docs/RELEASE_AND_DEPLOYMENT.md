# Release and Deployment Guide

This document describes how to package, structure, and deploy CoOpt UI and its components (ItemUI, ScriptTracker, Auto Loot, Auto Sell) for test or production releases. It is intended for maintainers and for agents that need to create release packages or update deployment logic.

---

## 1. Overview

- **Scope:** CoOpt UI — ItemUI (unified inventory/bank/sell/loot UI), ScriptTracker (AA script tracker), Auto Loot and Auto Sell macros, plus required config.
- **Goal:** One versioned zip that test users can extract into their MacroQuest2 root; updates overwrite code only and never user config.
- **Convention:** Package layout **mirrors the MQ2 directory structure** so extraction is a single merge step (same pattern as KissAssist and other MQ2 add-ons).

---

## 2. GitHub Repository Setup and Sync

Use a GitHub repository for version control and to make the codebase available to testers and contributors.

### 2.1 Initial setup (one-time)

1. **Create the repository** on GitHub (e.g. `CoopUI`). Prefer a **private** repo until you are ready for public testing; then switch to public or use GitHub’s “invite collaborators” for testers.
2. **Clone or link locally**  
   - If this folder is not yet a Git repo: run `git init`, then `git remote add origin https://github.com/YOUR_ORG/CoopUI.git` (or your repo URL).  
   - If you already cloned from GitHub: ensure `origin` points to the correct repo with `git remote -v`.
3. **Use the recommended `.gitignore`** in the project root so binaries, logs, and user-specific data are not committed (see Section 2.4 and the project `.gitignore`).

### 2.2 Best practices

| Practice | Recommendation |
|----------|----------------|
| **Branch strategy** | Use `main` (or `master`) for stable/release-ready code. Optionally use a `develop` branch for integration; merge to `main` when cutting a release. |
| **Tags** | Tag each release, e.g. `v1.0`, `v1.1`, so testers can clone or download a specific version. Use **Releases** on GitHub to attach the zip (e.g. `CoOpt UI_v1.0.zip`) to the tag. |
| **README** | Keep the root `README.md` updated with: what the project is, requirements (MQ2, Lua, ImGui), link to this doc or DEPLOY.md for install/update. |
| **Commit messages** | Use clear, short messages (e.g. “Fix sell progress reset”, “ItemUI: add column config”). Optionally prefix with scope: `itemui:`, `scripttracker:`, `macros:`, `docs:`. |
| **What to commit** | Commit all files listed in **Section 3 (Repository file list)** that are under version control. Do **not** commit: `Backup/`, `Logs/`, `Macros/sell_config/Chars/`, binaries (`.exe`, `.dll`), or other paths listed in `.gitignore`. |

### 2.3 Consistent sync workflow

- **When to commit:** After each logical change (e.g. one feature, one bugfix, or one doc update). Small, frequent commits make history easier to follow and roll back.
- **When to push:** Push to GitHub at least daily when active, and always before sharing with testers or building a release. Run a quick test (e.g. `/lua run itemui`) if possible before pushing.
- **Before a release:** Ensure `main` is up to date, tag the version, build the zip from the file list in Section 5, and create a GitHub Release with the zip attached.
- **Sync checklist (optional):** Keep a short checklist in this repo or in your process: (1) All changes committed, (2) No unintended files in commit (check `git status`), (3) Push to `origin main`, (4) If release: tag and upload zip to Releases.

### 2.4 Project-only .gitignore (recommended)

The project uses a **project-only** `.gitignore`: only the files you’re working on are tracked; the rest of the MacroQuest2 instance (config/, plugins/, modules/, mono/, binaries, etc.) is ignored. That way you push just CoOpt UI (ItemUI, ScriptTracker, macros, docs, and related assets)—not the whole MQ2 install.

**Tracked (what gets pushed):**
- **lua/** — `itemui/` (full tree), `scripttracker/` (full tree), `mq/ItemUtils.lua` only
- **Macros/** — `sell.mac`, `loot.mac`, `shared_config/` (INIs + .mac), `sell_config/` (INI templates, README; not Chars/), `loot_config/` (INIs, README)
- **resources/** — `UIFiles/Default/EQUI.xml`, `MQUI_ItemColorAnimation.xml`, `ItemColorBG.tga` only
- **docs/**, **epic_quests/**, **.cursor/**, **README.md**, **.gitignore**, **archive_backups.ps1**

**Always ignored:** `Backup/`, `Logs/`, `Macros/logs/`, `Macros/sell_config/Chars/`, `Macros/sell_config/sell_cache.ini`, `Macros/bank_data/`, and everything not listed above (config, plugins, modules, mono, .exe, .dll, etc.).

See the project `.gitignore` for the exact patterns; adjust if you want to add or remove paths.

---

## 3. Repository File List (Files We Are Working With)

This is the canonical list of project files under version control and included in releases. Use it when setting up the repo, building packages, or auditing what to sync.

### 3.1 Lua — ItemUI (`lua/itemui/`)

| Path | Role |
|------|------|
| `lua/itemui/init.lua` | Entry point; binds /itemui, /inv, /dosell, /doloot; main loop |
| `lua/itemui/config.lua` | INI read/write, paths for sell_config, shared_config, loot_config |
| `lua/itemui/config_cache.lua` | Cached sell/loot flags and lists |
| `lua/itemui/context.lua` | Shared UI context |
| `lua/itemui/rules.lua` | willSell, willLoot, epic protection rules |
| `lua/itemui/storage.lua` | Per-char inventory/bank persistence |
| `lua/itemui/upvalue_check.lua` | Upvalue / module checks |
| `lua/itemui/README.md` | ItemUI readme |
| `lua/itemui/components/filters.lua` | Filter UI components |
| `lua/itemui/components/progressbar.lua` | Progress bar component |
| `lua/itemui/components/searchbar.lua` | Search bar component |
| `lua/itemui/core/cache.lua` | Cache logic |
| `lua/itemui/core/events.lua` | Event handling |
| `lua/itemui/services/filter_service.lua` | Filter service |
| `lua/itemui/services/macro_bridge.lua` | Macro bridge |
| `lua/itemui/services/scan.lua` | Scan service |
| `lua/itemui/utils/column_config.lua` | Column configuration |
| `lua/itemui/utils/columns.lua` | Column definitions |
| `lua/itemui/utils/file_safe.lua` | File-safe utilities |
| `lua/itemui/utils/item_tooltip.lua` | Item tooltip |
| `lua/itemui/utils/layout.lua` | Layout utilities |
| `lua/itemui/utils/sort.lua` | Sort utilities |
| `lua/itemui/utils/theme.lua` | Theme utilities |
| `lua/itemui/views/augments.lua` | Augments view |
| `lua/itemui/views/bank.lua` | Bank view |
| `lua/itemui/views/config.lua` | Config view |
| `lua/itemui/views/inventory.lua` | Inventory view |
| `lua/itemui/views/loot.lua` | Loot view |
| `lua/itemui/views/sell.lua` | Sell view |
| `lua/itemui/docs/*.md` | ItemUI design/phase docs (optional in release zip) |

### 3.2 Lua — ScriptTracker (`lua/scripttracker/`)

| Path | Role |
|------|------|
| `lua/scripttracker/init.lua` | AA script tracker; /scripttracker |
| `lua/scripttracker/README.md` | ScriptTracker readme |
| `lua/scripttracker/scripttracker.ini` | Optional config (script may not read it yet) |

### 3.3 Lua — MQ shared (`lua/mq/`)

| Path | Role |
|------|------|
| `lua/mq/ItemUtils.lua` | formatValue, formatWeight (ItemUI dependency) |

*(Other files under `lua/mq/` such as `eval.lua`, `Icons.lua`, `ImGuiFileDialog.lua`, etc., are MQ2/Lua ecosystem files; include in repo only if this project owns or modifies them.)*

### 3.4 Macros (release scope)

| Path | Role |
|------|------|
| `Macros/sell.mac` | Sell flow; used by ItemUI /dosell |
| `Macros/loot.mac` | Loot flow; used by ItemUI /doloot |
| `Macros/shared_config/log_item.mac` | Log items to valuable lists |
| `Macros/shared_config/validate_config.mac` | Validate config INIs |

### 3.5 Config templates (source: Macros; for release use `config_templates/`)

Template INIs are copied from the repo’s `Macros/sell_config`, `Macros/shared_config`, and `Macros/loot_config` into `config_templates/` when building the zip. **Do not commit user-specific or runtime files** (e.g. `Macros/sell_config/Chars/`, `Macros/logs/`). Track these INI template sources:

- **sell_config:** `sell_flags.ini`, `sell_value.ini`, `sell_keep_exact.ini`, `sell_keep_contains.ini`, `sell_keep_types.ini`, `sell_always_sell_exact.ini`, `sell_always_sell_contains.ini`, `sell_protected_types.ini`, `sell_augment_always_sell_exact.ini`
- **shared_config:** `epic_classes.ini`, `epic_items_exact.ini`, `epic_items_<class>.ini` (all class variants), `valuable_exact.ini`, `valuable_contains.ini`, `valuable_types.ini`
- **loot_config:** `loot_flags.ini`, `loot_value.ini`, `loot_sorting.ini`, `loot_always_exact.ini`, `loot_always_contains.ini`, `loot_always_types.ini`, `loot_skip_exact.ini`, `loot_skip_contains.ini`, `loot_skip_types.ini`, `loot_augment_skip_exact.ini`

### 3.6 UI resources (ItemUI-related only)

| Path | Role |
|------|------|
| `resources/UIFiles/Default/EQUI.xml` | Modified to include ItemUI summary |
| `resources/UIFiles/Default/MQUI_ItemColorAnimation.xml` | Item color animation |
| `resources/UIFiles/Default/ItemColorBG.tga` | Item color texture |

### 3.7 Documentation and root

| Path | Role |
|------|------|
| `docs/RELEASE_AND_DEPLOYMENT.md` | This document |
| `docs/MQ2_BEST_PRACTICES.md` | MQ2 best practices |
| `docs/MQ2_STATUS_CHECK_AND_PLAN.md` | Status and plan |
| `docs/OPTIMIZATION_ROADMAP.md` | Optimization roadmap |
| `docs/SELL_CACHE_DESIGN.md` | Sell cache design |
| `docs/QUICK_REFERENCE_NEW_FEATURES.md` | Quick reference |
| `docs/guides/classes/*.md` | Class guides (e.g. warrior, rogue, shadowknight) |
| `README.md` | Project readme (root) |
| `DEPLOY.md` | *(Create for releases)* User-facing install/update steps; copy into zip root |
| `CHANGELOG.md` | *(Optional)* Version history; can live in repo and zip |

### 3.8 Epic quests (optional project scope)

| Path | Role |
|------|------|
| `epic_quests/README.md`, `epic_quests/IMPLEMENTATION_SUMMARY.md`, `epic_quests/GENERATED_FILES.md` | Epic quests docs |
| `epic_quests/data/*.json`, `epic_quests/data/*.lua`, `epic_quests/data/lua/*.lua` | Epic data and generated Lua |
| `epic_quests/scripts/*.py` | Scripts to generate epic data |
| `epic_quests/docs/SUGGESTIONS.md` | Suggestions |

*(Include in the repo if epic_quests is part of this project; omit from the ItemUI/ScriptTracker release zip unless you ship it.)*

### 3.9 Other (optional)

| Path | Role |
|------|------|
| `.cursor/agents/*.md` | Cursor/agent rules (if you want them in the repo) |
| `.gitignore` | Git ignore rules (see below) |
| `archive_backups.ps1` | Backup script (if used for repo workflow) |

---

## 4. Package Structure

The release zip should mirror the MacroQuest2 root. When extracted into the MQ2 folder, paths must match what the code expects (e.g. `lua/itemui`, `Macros/sell_config`).

### 4.1 Directory tree (inside the zip)

```
CoOpt UI_vX.Y.zip
├── lua/
│   ├── itemui/                    # Full ItemUI module tree
│   │   ├── init.lua
│   │   ├── config.lua
│   │   ├── config_cache.lua
│   │   ├── context.lua
│   │   ├── rules.lua
│   │   ├── storage.lua
│   │   ├── upvalue_check.lua
│   │   ├── README.md
│   │   ├── components/
│   │   │   ├── filters.lua
│   │   │   ├── progressbar.lua
│   │   │   └── searchbar.lua
│   │   ├── core/
│   │   │   ├── cache.lua
│   │   │   └── events.lua
│   │   ├── services/
│   │   │   ├── filter_service.lua
│   │   │   ├── macro_bridge.lua
│   │   │   └── scan.lua
│   │   ├── utils/
│   │   │   ├── column_config.lua
│   │   │   ├── columns.lua
│   │   │   ├── item_tooltip.lua
│   │   │   ├── layout.lua
│   │   │   ├── sort.lua
│   │   │   └── theme.lua
│   │   └── views/
│   │       ├── augments.lua
│   │       ├── bank.lua
│   │       ├── config.lua
│   │       ├── inventory.lua
│   │       ├── loot.lua
│   │       └── sell.lua
│   ├── scripttracker/
│   │   ├── init.lua
│   │   ├── README.md
│   │   └── scripttracker.ini
│   └── mq/
│       └── ItemUtils.lua
├── Macros/
│   ├── sell.mac
│   ├── loot.mac
│   └── shared_config/
│       ├── log_item.mac
│       └── validate_config.mac
├── config_templates/               # Default INIs; copy once if missing
│   ├── sell_config/
│   │   ├── sell_flags.ini
│   │   ├── sell_value.ini
│   │   ├── sell_keep_exact.ini
│   │   ├── sell_keep_contains.ini
│   │   ├── sell_keep_types.ini
│   │   ├── sell_always_sell_exact.ini
│   │   ├── sell_always_sell_contains.ini
│   │   ├── sell_protected_types.ini
│   │   └── sell_augment_always_sell_exact.ini
│   ├── shared_config/
│   │   ├── epic_classes.ini
│   │   ├── epic_items_exact.ini
│   │   ├── epic_items_<class>.ini   # all class variants
│   │   ├── valuable_exact.ini
│   │   ├── valuable_contains.ini
│   │   └── valuable_types.ini
│   └── loot_config/
│       ├── loot_flags.ini
│       ├── loot_value.ini
│       ├── loot_sorting.ini
│       ├── loot_always_exact.ini
│       ├── loot_always_contains.ini
│       ├── loot_always_types.ini
│       ├── loot_skip_exact.ini
│       ├── loot_skip_contains.ini
│       ├── loot_skip_types.ini
│       └── loot_augment_skip_exact.ini
├── resources/
│   └── UIFiles/
│       └── Default/
│           ├── EQUI.xml
│           ├── MQUI_ItemColorAnimation.xml
│           └── ItemColorBG.tga
├── DEPLOY.md                       # User-facing install/update steps
└── CHANGELOG.md                    # Optional; version history
```

### 4.2 What each top-level folder is for

| Folder | Purpose |
|--------|---------|
| `lua/` | Scripts (itemui, scripttracker, mq/ItemUtils). Replaced on every update. |
| `Macros/` | sell.mac, loot.mac, shared_config/*.mac only. Replaced on update. User INIs live in Macros/sell_config, shared_config, loot_config and are **not** in the zip (or come from config_templates once). |
| `config_templates/` | Default INI files. Users copy into Macros/sell_config (etc.) on first install only; never overwrite existing config on update. |
| `resources/` | ItemUI-related UI files only. Replaced on update. |
| `DEPLOY.md` | Copy into zip root; first-time install and update instructions for end users. |

---

## 5. Replace vs preserve (update safety)

When building an **update** package or script, follow this rule so user settings are never lost.

### 5.1 Replace on every update (safe to overwrite)

- **lua/itemui/** — entire directory
- **lua/scripttracker/** — init.lua, README.md; scripttracker.ini is optional (script does not currently read it)
- **lua/mq/ItemUtils.lua**
- **Macros/sell.mac**, **Macros/loot.mac**
- **Macros/shared_config/log_item.mac**, **Macros/shared_config/validate_config.mac**
- **resources/UIFiles/Default/EQUI.xml**, **MQUI_ItemColorAnimation.xml**, **ItemColorBG.tga**

### 5.2 Never overwrite on update (user/config and runtime data)

- **Macros/sell_config/** — all .ini files (sell_flags, sell_value, sell_keep_*, sell_always_sell_*, itemui_layout, etc.) and **Chars/** (per-character bank.lua, inventory.lua, sell_cache.ini)
- **Macros/shared_config/** — all .ini files (epic_classes, epic_items_*, valuable_*); overwrite only the .mac files
- **Macros/loot_config/** — all .ini files
- **Macros/logs/item_management/** — sell_progress.ini, sell_failed.ini (runtime)

### 5.3 Config templates (first install only)

- **config_templates/** contents are copied to **Macros/sell_config**, **Macros/shared_config**, **Macros/loot_config** only when those folders are missing or the user is doing a first-time install. Never overwrite existing INIs in those locations with template contents during an update.

---

## 6. Config templates

- **Purpose:** Give new users working defaults without editing code paths. Existing users keep their own INIs.
- **Source:** Populate `config_templates/sell_config`, `shared_config`, `loot_config` from the repo’s current **Macros/sell_config**, **Macros/shared_config**, **Macros/loot_config** (INI files only; omit Chars, logs, and any character-specific or machine-specific files).
- **Usage:** Document in DEPLOY.md: “If you don’t have Macros/sell_config (and shared_config, loot_config), copy the contents of config_templates/sell_config into Macros/sell_config,” etc.

---

## 7. File inventory (quick reference)

Use this when building the package or an update script. For the full repository file list, see **Section 3**.

### 7.1 Lua (all under lua/)

| Path | Role |
|------|------|
| itemui/init.lua | Entry point; binds /itemui, /inv, /dosell, /doloot; main loop |
| itemui/config.lua | INI read/write, paths for sell_config, shared_config, loot_config |
| itemui/config_cache.lua | Cached sell/loot flags and lists |
| itemui/context.lua | Shared UI context |
| itemui/rules.lua | willSell, willLoot, epic protection rules |
| itemui/storage.lua | Per-char inventory/bank persistence |
| itemui/components/*.lua | filters, progressbar, searchbar |
| itemui/core/*.lua | cache, events, state |
| itemui/services/*.lua | filter_service, macro_bridge, scan |
| itemui/utils/*.lua | column_config, columns, item_tooltip, layout, sort, theme |
| itemui/views/*.lua | inventory, bank, sell, loot, config, augments |
| scripttracker/init.lua | AA script tracker; /scripttracker |
| mq/ItemUtils.lua | formatValue, formatWeight (ItemUI dependency) |

### 7.2 Macros

| Path | Role |
|------|------|
| Macros/sell.mac | Sell flow; used by ItemUI /dosell |
| Macros/loot.mac | Loot flow; used by ItemUI /doloot |
| Macros/shared_config/log_item.mac | Log items to valuable lists |
| Macros/shared_config/validate_config.mac | Validate config INIs |

### 7.3 UI (ItemUI-related only)

| Path | Role |
|------|------|
| resources/UIFiles/Default/EQUI.xml | Modified to include ItemUI summary |
| resources/UIFiles/Default/MQUI_ItemColorAnimation.xml | Item color animation |
| resources/UIFiles/Default/ItemColorBG.tga | Item color texture |

---

## 8. User-facing instructions (DEPLOY.md)

The following text is intended to be placed in **DEPLOY.md** at the root of the release zip so test users have a single place to look. Maintainers can copy this into the zip when cutting a release.

```markdown
# CoOpt UI — Install / Update

## Requirements

- MacroQuest2 with Lua support (mq2lua) and ImGui.
- In-game: `/lua run itemui` and `/lua run scripttracker` must work.

## First-time install

1. Extract this zip into your **MacroQuest2 folder** (the folder that already contains `lua`, `Macros`, `config`). When prompted, choose to merge/overwrite so that the new `lua`, `Macros`, and `resources` folders merge with your existing ones.
2. If you do **not** already have `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config` with INI files inside, copy the contents of `config_templates/sell_config` into `Macros/sell_config`, `config_templates/shared_config` into `Macros/shared_config`, and `config_templates/loot_config` into `Macros/loot_config`.
3. In-game: run `/lua run itemui` and optionally `/lua run scripttracker`. Use `/itemui` and `/scripttracker` to toggle the windows.

## Updating

1. Extract the new zip into your MacroQuest2 folder.
2. Allow overwriting for: `lua/itemui`, `lua/scripttracker`, `lua/mq/ItemUtils.lua`, `Macros/sell.mac`, `Macros/loot.mac`, `Macros/shared_config/*.mac`, and `resources/UIFiles/Default/` (EQUI.xml, MQUI_ItemColorAnimation.xml, ItemColorBG.tga).
3. Do **not** overwrite your existing `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config` INI files (or the `Chars` folders inside sell_config). Your keep/junk lists and layout will be preserved.

## Commands

- `/itemui` or `/inv` — Toggle ItemUI window
- `/itemui setup` — Configure panel sizes
- `/scripttracker` — Toggle ScriptTracker (Lost/Planar script counts)
- `/dosell` — Run sell macro (sell marked items)
- `/doloot` — Run loot macro (auto-loot)
```

---

## 9. Versioning and changelog

- **Zip naming:** Use a versioned name, e.g. `CoOpt UI_v1.0.zip`, so testers know what they have.
- **CHANGELOG.md:** Optional file in the zip and in the repo listing changes per version (e.g. “1.1 – sell progress fix, scripttracker pop-out from ItemUI”). Refer to it from DEPLOY.md if present.

---

## 10. Optional: update script

For power users or internal testing, a small script (e.g. PowerShell or batch) can copy only the “replace on update” paths from an extracted release folder into the current MQ2 root. The script should:

- Accept the MQ2 root path (or assume current directory is the release root and MQ2 root is parent or a fixed relative path).
- Copy: `lua/itemui`, `lua/scripttracker`, `lua/mq/ItemUtils.lua`, `Macros/sell.mac`, `Macros/loot.mac`, `Macros/shared_config/*.mac`, `resources/UIFiles/Default/` (the three ItemUI files only).
- Not copy or overwrite: `Macros/sell_config`, `Macros/shared_config` INIs, `Macros/loot_config`, or `Macros/logs`.

This document does not define the script; it is optional and can be added later.

### 10.1 Deploy clean install (testing)

For testing "clean installs" (what a new user would see), use `scripts/deploy-clean-install.ps1`:

```powershell
.\scripts\deploy-clean-install.ps1
```

This script:

- Copies from `C:\MIS\MacroquestEnvironments\DeployTest\E3NextAndMQNextBinary-main` (or via `-SourceFolder`) into `C:\MIS\MacroquestEnvironments\DeployTest`
- Creates `CoOptUI`, `CoOptUI2`, `CoOptUI3`, … (sequential if folders exist)
- **CoOpt UI patcher simulation:** Copies all `release_manifest.json` files from the repo, then applies `default_config_manifest.json` (config templates → `Macros/`)
- Copies `CoOptUIPatcher.exe` to the deploy root (if built via `pyinstaller patcher.spec`)
- **E3 autologin:** Copies `config/MQ2AutoLogin.ini` and ensures `mq2autologin=1` in `MacroQuest.ini` so autologin works

Use the resulting folder as a simulated MQ root to verify first-run behavior.

---

## 11. Bootstrap readiness checklist (Task 8.4)

Before each release, verify that a **fresh install** (Zip or patcher) can reach the Welcome process and tutorial without red validation failures:

1. **Zip audit:** Extract the release Zip (or run the patcher) into a **clean** MacroQuest directory (no existing `Macros/sell_config`, `Macros/shared_config`, `Macros/loot_config`, or ensure they are empty/minimal).
2. **Launch:** Start MQ2 and run `/lua run itemui`.
3. **Welcome:** Confirm the Welcome panel appears with the **Environment check** section. All entries should show **[OK]** or **[Created]** (no **[Failed]**). If any fail, fix the package (include missing defaults) or document the requirement.
4. **Proceed:** Click "Run Setup" or "I Know What I'm Doing (Skip)" and confirm the tutorial step or main UI loads.
5. **Patcher:** If using the patcher as the delivery mechanism, confirm it runs **environment validation** (creation of `Macros/sell_config`, `shared_config`, `loot_config` and minimal INI when missing) as part of the **post-patch** sequence, not only on first install.

Files that the Welcome process can auto-generate (folders, minimal INI) may be omitted from the Zip to reduce size; document any such exclusion. Include all **process files** (Lua source, macros) and the **defaults/** configuration package when using backup/restore defaults (Task 8.3).

---

## 12. Summary for agents

When creating or updating a release package:

1. **Structure:** Mirror MQ2 root inside the zip (lua/, Macros/, resources/, config_templates/).
2. **Replace on update:** All of lua/itemui, lua/scripttracker, lua/mq/ItemUtils.lua, Macros/sell.mac, loot.mac, shared_config/*.mac, and the three UI files under resources/UIFiles/Default/.
3. **Preserve:** Macros/sell_config, shared_config, loot_config INIs and Chars/; Macros/logs/item_management.
4. **Templates:** config_templates/ holds default INIs; users copy into Macros/ on first install only; never overwrite existing Macros/*/ INIs on update.
5. **Docs:** Include DEPLOY.md in the zip with the instructions in Section 8; optionally CHANGELOG.md.
6. **Bootstrap:** Run the checklist in Section 11 (extract to clean MQ, launch, confirm Welcome env check passes).
