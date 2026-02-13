# ItemUI — Current Status

Short reference so agents and contributors know what is done and what is next. For full phase breakdown and next steps, see [PHASE_PLAN_UPDATED.md](PHASE_PLAN_UPDATED.md) and [PROJECT_ROADMAP.md](PROJECT_ROADMAP.md).

---

## Done

- **Phases 1–5:** State/cache refactor, instant-open performance, unified filter system, SellUI consolidation, macro integration (including macro_bridge and polling reduction). All complete.
- **Phase 7 (partial):** View extraction and theme/layout utilities are in place (inventory, sell, bank, loot views; `utils/layout.lua`, `utils/theme.lua`). Config view integration and init.lua refactor are still remaining.

## Planned / deferred

- **Phase 6:** Settings and configuration overhaul (tabs, statistics panel, presets, export/import). Planned; deferred until after current priorities.
- **Phase 7 (remaining):** Full `views/config.lua` integration, reusable itemtable/progressbar components, and init.lua size reduction.
- **Phase 8:** Advanced features (comparison tooltips, drag-and-drop, theme system, etc.) — future.

---

Historical implementation details for each phase are in `lua/itemui/docs/archive/`. This file and the roadmap/phase plan are the source of truth for current status and next steps.
