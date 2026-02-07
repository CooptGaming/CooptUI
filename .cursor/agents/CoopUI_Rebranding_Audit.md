# CoopUI Rebranding Audit & Phase 1 Action Plan

**Date:** February 6, 2026  
**Status:** Ready for execution  
**Scope:** Complete rebranding to CoopUI as the umbrella product brand

---

## Executive Summary

CoopUI is the umbrella brand for four components: **ItemUI** (Lua), **ScriptTracker** (Lua), **Auto Loot** (macro), and **Auto Sell** (macro). The rebranding has two dimensions:

1. **Remove old name** — Replace all "E3Next" / "E3NextAndMQNextBinary" / "MQNext" references
2. **Establish CoopUI as umbrella** — The project currently presents "ItemUI" as the whole product. Docs and user-facing text need to shift to CoopUI as the product name, with ItemUI, ScriptTracker, Auto Loot, and Auto Sell as named components within it.

The actual Lua codebase is clean — `itemui` and `scripttracker` remain as internal package names. The work is concentrated in documentation, agent files, and user-facing strings.

**Estimated effort:** 2–3 hours for complete rebranding.

---

## 1. Component Architecture Under CoopUI

| Component | Type | Entry Point | User Command | Role |
|-----------|------|-------------|-------------|------|
| **ItemUI** | Lua package | `lua/itemui/init.lua` | `/lua run itemui` ; `/itemui` | Unified inventory/bank/sell/loot UI |
| **ScriptTracker** | Lua package | `lua/scripttracker/init.lua` | `/lua run scripttracker` ; `/scripttracker` | AA script progress tracker |
| **Auto Loot** | MQ macro | `Macros/loot.mac` | `/macro loot` or `/doloot` | Automated corpse looting |
| **Auto Sell** | MQ macro | `Macros/sell.mac` | `/macro sell` or `/dosell` | Automated item selling |

**Architectural decision needed:** Option A (brand-only, four separate entry points) vs. Option B (single `lua/coopui/init.lua` shell that loads components). This audit assumes **Option A** for Phase 1 — unify branding without changing entry points. Option B can be Phase 3 work.

---

## 2. Complete Inventory of Changes Needed

### 2.1 HIGH PRIORITY — User-Facing Files

#### README.md

| Current | Change To |
|---------|-----------|
| `# E3Next — ItemUI & ScriptTracker (MacroQuest2)` | `# CoopUI — EverQuest EMU Companion (MacroQuest2)` |
| Description treats ItemUI as the whole product | Reframe: CoopUI is the product containing ItemUI, ScriptTracker, Auto Loot, Auto Sell |
| Quick Start section only mentions ItemUI and ScriptTracker | Add Auto Loot and Auto Sell to Quick Start |
| Project Structure section | Add CoopUI framing; label each subfolder as a CoopUI component |
| "Best Practices Applied" section references only ItemUI patterns | Broaden to cover all components |
| Development section | Frame as CoopUI development |

**Proposed new title block:**
```markdown
# CoopUI — EverQuest EMU Companion (MacroQuest2)

> CoopUI is a comprehensive UI companion for EverQuest emulator servers, built on MacroQuest2. 
> It provides unified item management, AA script tracking, and automated loot/sell workflows.

## Components

| Component | Type | Command | What It Does |
|-----------|------|---------|-------------|
| **ItemUI** | Lua UI | `/lua run itemui` | Unified inventory, bank, sell, and loot interface |
| **ScriptTracker** | Lua UI | `/lua run scripttracker` | AA script progress tracking |
| **Auto Loot** | Macro | `/doloot` | Automated corpse looting |
| **Auto Sell** | Macro | `/dosell` | Automated item selling |
```

#### docs/RELEASE_AND_DEPLOYMENT.md

~15+ references to update:

| Find | Replace With |
|------|-------------|
| `E3NextAndMQNextBinary` (all instances) | `CoopUI` |
| `E3Next-ItemUI-ScriptTracker` | `CoopUI` |
| `E3Next_ItemUI_vX.Y.zip` | `CoopUI_vX.Y.zip` |
| `E3Next_ItemUI_v1.0.zip` | `CoopUI_v1.0.zip` |
| `github.com/YOUR_ORG/E3NextAndMQNextBinary` | `github.com/YOUR_ORG/CoopUI` |
| Section 1 Overview — scope description | Reframe as CoopUI with four components |
| Section 8 DEPLOY.md text — "ItemUI & ScriptTracker" title | → "CoopUI — Install / Update" |
| Section 9 versioning | `CoopUI_vX.Y.zip` naming |

#### docs/GITHUB_HTTPS_SETUP.md

| Find | Replace With |
|------|-------------|
| `E3NextAndMQNextBinary` (repo name suggestions) | `CoopUI` |
| `E3Next-ItemUI-ScriptTracker` | `CoopUI` |
| Commit message example: `"Initial commit: ItemUI, ScriptTracker, macros, docs"` | `"Initial commit: CoopUI (ItemUI, ScriptTracker, Auto Loot, Auto Sell)"` |

### 2.2 MEDIUM PRIORITY — Agent & Internal Dev Files

#### .cursor/agents/lua-ux-dev.md

| Current | Change To |
|---------|-----------|
| Description: "Expert on UX for MacroQuest2 Lua tools" | Add CoopUI context: "Expert on UX for CoopUI, the MacroQuest2 EQ companion" |
| References "itemui, boxhud, buttonmaster, sellui, lootui, epicquestui, bankui, inventoryui, lazbis" | Update: SellUI, LootUI, BankUI, InventoryUI are deprecated into ItemUI. Frame as CoopUI components |
| Core Responsibilities item 1: lists many UIs | Simplify to CoopUI's actual components: ItemUI, ScriptTracker |
| "Scan existing UIs" references deprecated UIs | Update to current state |

#### .cursor/agents/mq2-macro-dev.md

| Current | Change To |
|---------|-----------|
| Description mentions "itemui, boxhud, sellui, lootui, etc." | Update to CoopUI component names |
| Lua UI integration section references "itemui, sellui, lootui" | → "CoopUI components (ItemUI for inventory/sell/loot)" |
| Continuity checklist: "config works with itemui/sellui/lootui" | → "config works with CoopUI's ItemUI" |

#### lua/itemui/docs/PHASE1_AND_PHASE2_SUMMARY.md

| Find | Replace With |
|------|-------------|
| `c:\MIS\E3NextAndMQNextBinary-main\lua\itemui\...` (hardcoded paths) | Relative paths or `<PROJECT_ROOT>\lua\itemui\...` |

#### lua/itemui/phase7_check.ps1

| Find | Replace With |
|------|-------------|
| `$initFile = "c:\MIS\E3NextAndMQNextBinary-main\lua\itemui\init.lua"` | Parameterize: `$projectRoot = $PSScriptRoot; $initFile = "$projectRoot\lua\itemui\init.lua"` |
| All 3 hardcoded `c:\MIS\E3NextAndMQNextBinary-main\` paths | Use `$projectRoot` variable |

#### lua/itemui/docs/PROJECT_ROADMAP.md

| Current | Change To |
|---------|-----------|
| Framing around "ItemUI" as the whole product | Add CoopUI context where appropriate |
| Success metrics: "Users run ItemUI only" | → "Users run CoopUI components (ItemUI for items, ScriptTracker for AAs)" |

#### docs/SPRING_CLEANING_AUDIT_2025.md

| Current | Change To |
|---------|-----------|
| Title: "EQ UI Overhaul" | → "CoopUI — Spring Cleaning Audit" or keep as historical |
| "ItemUI-centric architecture" framing | Add note that ItemUI is now a CoopUI component |
| References to deprecated UIs (SellUI, LootUI, BankUI, itemui_package) | Can stay as historical context with a note they're consolidated |

### 2.3 LOW PRIORITY — Structural / Future

| Item | Current | Target | Notes |
|------|---------|--------|-------|
| Root folder name | `E3NextAndMQNextBinary-main` | `CoopUI` | Git repo rename; cosmetic but nice |
| GitHub repo name | `E3NextAndMQNextBinary` | `CoopUI` | Do when ready; update remotes |
| Future: `lua/coopui/init.lua` | Doesn't exist | Optional loader shell | Phase 3 / Option B decision |

### 2.4 CODE FILES — No Changes Needed ✅

These files are already clean of old-name references and use correct component naming:

| Component | Files | Status |
|-----------|-------|--------|
| ItemUI Lua package | `init.lua`, `config.lua`, `config_cache.lua`, `context.lua`, `rules.lua`, `storage.lua` | ✅ Uses "ItemUI" |
| ItemUI submodules | `components/*.lua`, `core/*.lua`, `services/*.lua`, `utils/*.lua`, `views/*.lua` | ✅ Clean |
| ScriptTracker | `init.lua`, `README.md`, `scripttracker.ini` | ✅ Uses "ScriptTracker" |
| Shared utils | `lua/mq/ItemUtils.lua` | ✅ Clean |
| Macros | `sell.mac`, `loot.mac`, `shared_config/*.mac` | ✅ No old name |
| Config INIs | All `*_config/*.ini` files | ✅ No old name |
| UI resources | `resources/UIFiles/Default/*` | ✅ Clean |
| Epic quests | `epic_quests/*` | ✅ Standalone data |

---

## 3. Lua Code: CoopUI Branding Touchpoints

While the code doesn't need find/replace for old names, these are the places where CoopUI branding should be **added**:

### 3.1 File Headers (Add "Part of CoopUI")

**lua/itemui/init.lua** — Current header:
```lua
--[[
    ItemUI - Unified Inventory / Bank / Sell / Loot Interface
    ...
```
**Proposed:**
```lua
--[[
    CoopUI - ItemUI
    Purpose: Unified Inventory / Bank / Sell / Loot Interface
    Part of CoopUI — EverQuest EMU Companion
    Author: Perky's Crew
    Version: 1.0.0-rc1
    Dependencies: mq2lua, ImGui
--]]
```

**lua/scripttracker/init.lua** — Add similarly:
```lua
--[[
    CoopUI - ScriptTracker
    Purpose: AA Script Progress Tracker
    Part of CoopUI — EverQuest EMU Companion
    Author: Perky's Crew
    Version: 1.0.0-rc1
    Dependencies: mq2lua, ImGui
--]]
```

**Macros/sell.mac** and **Macros/loot.mac** — In the header comment block:
```
| CoopUI — Auto Sell vX.X                            |
```
```
| CoopUI — Auto Loot vX.X                            |
```

### 3.2 Version Constant

In `lua/itemui/init.lua`:
```lua
-- Current:
VERSION = "1.6.0",
-- Change to:
VERSION = "1.0.0-rc1",
```

**Note on versioning:** The reset to 1.0.0-rc1 marks CoopUI's first release identity. If you prefer version continuity (since the code is mature), use `2.0.0-rc1` instead.

### 3.3 In-Game Print Messages (Optional)

Currently: `\ag[ItemUI]\ax Item UI v1.6.0 loaded.`

Could become: `\ag[CoopUI » ItemUI]\ax v1.0.0-rc1 loaded.` — but this is cosmetic and could wait for Phase 2. The `[ItemUI]` prefix is already clean and recognizable.

---

## 4. Execution Plan (Step-by-Step)

### Step 1: README.md
Rewrite title, description, Quick Start, and Project Structure to present CoopUI as the umbrella brand with four components.

### Step 2: docs/RELEASE_AND_DEPLOYMENT.md
Systematic find/replace of all `E3Next*` references → `CoopUI`. Update zip naming, repo URLs, section descriptions.

### Step 3: docs/GITHUB_HTTPS_SETUP.md
Replace `E3Next*` repo name suggestions → `CoopUI`.

### Step 4: .cursor/agents/lua-ux-dev.md
Update to reference CoopUI and its current component list. Remove references to deprecated UIs (SellUI, LootUI, BankUI as standalone).

### Step 5: .cursor/agents/mq2-macro-dev.md
Update Lua UI integration references to use CoopUI framing.

### Step 6: Internal dev docs (lua/itemui/docs/*.md)
Replace hardcoded `E3NextAndMQNextBinary-main` Windows paths with relative or parameterized paths.

### Step 7: phase7_check.ps1
Parameterize the base path instead of hardcoding `c:\MIS\E3NextAndMQNextBinary-main\`.

### Step 8: Lua file headers
Add "CoopUI - [Component]" and "Part of CoopUI" to init.lua headers for ItemUI and ScriptTracker. Add CoopUI branding to macro headers.

### Step 9: Version bump
Update `VERSION` constant in `lua/itemui/init.lua` to `1.0.0-rc1`.

---

## 5. Verification

After completing all changes, run:

```bash
# Should return ZERO results (run from project root)
grep -ri "E3Next" --include="*.lua" --include="*.md" --include="*.ps1" --include="*.mac" .
grep -ri "MQNext" --include="*.lua" --include="*.md" --include="*.ps1" --include="*.mac" .
grep -ri "E3NextAndMQNextBinary" .
```

**Acceptable exceptions:**
- Git history (immutable without rebase)
- `.git/` directory internals

**Also verify CoopUI presence:**
```bash
# Should appear in README, docs, agent files, and Lua headers
grep -ri "CoopUI" --include="*.lua" --include="*.md" --include="*.ps1" --include="*.mac" . | wc -l
# Expected: 20+ hits across docs and headers
```

---

## 6. Key Decision: Package Names Stay

**`itemui` and `scripttracker` remain as Lua package names.** No `require()` paths change.

Rationale:
- `require('itemui.config')` is already clean and descriptive
- Changing would require updating every `require()` across 30+ files
- Would break existing user setups (`/lua run itemui`)
- CoopUI is the *product brand*; ItemUI and ScriptTracker are *component names*
- This mirrors "Microsoft Office" → "Word" / "Excel" or "WeakAuras" containing multiple modules

The hierarchy: **CoopUI** (product) → **ItemUI** + **ScriptTracker** + **Auto Loot** + **Auto Sell** (components)

---

## 7. Terminology Reference

For consistency across all docs and code comments:

| Term | Meaning | Use In |
|------|---------|--------|
| **CoopUI** | The product / umbrella brand | README, docs, headers, window titles (optional) |
| **ItemUI** | Lua package for inventory/bank/sell/loot UI | `require()` paths, `/lua run itemui`, component references |
| **ScriptTracker** | Lua package for AA script tracking | `require()` paths, `/lua run scripttracker`, component references |
| **Auto Loot** | MQ macro for automated looting | Docs, macro header; file stays `loot.mac` |
| **Auto Sell** | MQ macro for automated selling | Docs, macro header; file stays `sell.mac` |
| **Lua package** | A folder under `lua/` with `init.lua` | Technical docs (not "plugin" — that means C++ in MQ2) |
| **Macro** | A `.mac` file in `Macros/` | Technical docs |
| **Component** | Any of the four pieces above | General reference to parts of CoopUI |

---

## 8. Post-Rebranding: Architecture Observations for Phase 2–3

While auditing, I noted these items for future phases:

### Strengths
- Clean module structure with proper `require()` dependency graph
- Config/rules/storage properly separated from UI rendering
- View modules extracted (inventory, bank, sell, loot, config, augments)
- Event bus, state management, and cache infrastructure in place
- Context module elegantly solves Lua's 200-upvalue limit
- Agent files (lua-ux-dev, mq2-macro-dev) provide excellent continuity guidelines

### Phase 2 Opportunities
- `init.lua` is ~5000+ lines — roadmap targets <600 per file
- `buildItemFromMQ()` makes ~50+ TLO calls per item — profile which stats each view actually needs
- `perfCache` and `core/cache.lua` coexist — consolidation opportunity
- Comments like `Phase 2: Core infrastructure (state/events/cache unused)` suggest incomplete integration
- SellUI deprecation code can be fully removed if SellUI is no longer shipped

### Phase 3 (Architectural Cohesion) Considerations
- **Option B decision:** Whether to create `lua/coopui/init.lua` as a unified loader
- Standardize how all four components report version and status
- Consider a shared `lua/coopui/version.lua` that all components reference
- Future expansion: the structure should accommodate new Lua packages under CoopUI

---

## 9. Recommended Next Steps

1. **Upload the project files** (zip preferred) so I can execute all replacements and hand back rebranded files ready to commit
2. **Or** use this document as a checklist to make changes in your editor, then share updated files for verification
3. After rebranding verification, move to **Phase 2** starting with `init.lua` architecture review and optimization

---

*This audit was generated from project knowledge search of the repository and the CoopUI framing document. All file references verified against the project structure.*
