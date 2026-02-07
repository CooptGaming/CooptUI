# Changelog

All notable changes to CoopUI are documented here. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- GitHub release workflow: push a `v*` tag to build a zip and create a draft release.
- Release build script (`scripts/build-release.ps1`) for local or CI packaging.
- DEPLOY.md in release zip with install/update instructions for testers.

---

## [0.1.0-alpha] — Early alpha

First packaged release for early alpha testers.

### Added
- **ItemUI** — Unified inventory, bank, sell, and loot window (`/lua run itemui`, `/itemui`).
- **ScriptTracker** — AA script progress (Lost/Planar, etc.) via `/lua run scripttracker`.
- **Auto Sell** — `sell.mac` and `/dosell`; configurable keep/junk and epic protection.
- **Auto Loot** — `loot.mac` and `/doloot`; configurable filters and sorting.
- Config templates for sell_config, shared_config, and loot_config (first-time install).
- Epic item protection and class-specific epic lists in shared_config.
- ItemUI views: inventory, bank, sell, loot, config, augments; theme and layout support.

### Requirements
- MacroQuest2 with Lua (mq2lua) and ImGui.
