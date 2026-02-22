# Config templates — default settings files

These folders hold the **official default** INI files for sell, loot, and shared config. They mirror the maintainer’s current general settings. They are used by:

1. **Patcher (create-if-missing)** — When a user runs the patcher, any file listed here is installed into `Macros/sell_config`, `Macros/shared_config`, or `Macros/loot_config` **only if that file does not already exist**. Existing user files are never overwritten.
2. **UI startup (optional safety net)** — The UI can create a minimal version of a few critical files if they are missing (so the app doesn’t break if the user never ran the patcher).

## Don’t update these when you push

- Your **local** config lives under `Macros/sell_config`, `Macros/loot_config`, `Macros/shared_config`. Those INI files are **gitignored**, so they are **never pushed**.
- The **only** INI defaults in the repo are in `config_templates/`. Only change files here when you want to change the **official defaults** for new users (e.g. add a new key, change a default value).
- To refresh templates from your local setup: copy specific files from `Macros/...` into `config_templates/...` only when you intend that to be the new default, then commit.

---

## What’s in the templates

- **General settings** (flags, value thresholds, epic_classes, layout) — Mirror current maintainer settings.
- **Sell list, loot list, shared list** — Only **types** and **keyword** entries (exact, contains). No extra chunk keys (exact2–exact20, etc.); single-line values only.
- **Class-specific epic INIs** (`epic_items_<class>.ini`) — **Contain the full epic item entries** for each class (from your Macros). Beastlord and berserker are empty (no source INI in Macros).

### Not in config_templates

- **sell_augment_always_sell_exact.ini**, **loot_augment_skip_exact.ini** — Omitted; only main sell/loot/shared list types and keywords are templated.
- **epic_items_resolved.ini** — Written by UI for macro; do not ship as template.
- **Runtime files** — sell_cache.ini, loot_history.ini, skip_history.ini, loot_session.ini, loot_skipped.ini, loot_progress.ini, loot_mythical_alert.ini.

We **do** ship **itemui_layout.ini** so new users get a valid layout; patcher installs it only if missing.
