repo: CooptGaming/CooptUI
branch: master

## Last sync
date: 2026-07-30T05:43:23Z

### Updated in this project
- Nothing to pull: `master` has no changes touching any screen in this doc since the last sync. The `[Unreleased]` CHANGELOG entries (complete EMU plugin bundle, fresh-install fixes, toggle keybind via `/timed`) are build and installer work only.
- **`master` does not contain the bars work.** A repo-wide search for `dock_top`, `dock_state`, `DOCK_BAR_PADDING_Y` and `UIMode` returns zero matches, and `lua/itemui/views/` upstream has no `dock_top.lua`, `dock_bottom.lua` or `chat_window.lua`. Turns 17–20 were built from the attached local working copy, which is ahead of `master` and unpushed.
- Verified against upstream anyway: `views/equipment.lua` on `master` already carries `EQUIPMENT_PAPER_DOLL_ORDER` and `EQUIPMENT_ROW_LENGTHS = { 4, 2, 2, 2, 2, 4, 3, 4 }`, so 19d's 23-slot paper-doll map is correct against both copies.
- `views/item_display.lua` on `master` (13.7 KB) predates the verdict-card / stat-tile work in the local copy, so the 17a defects (per-tile scrollbars, `SetWindowFontScale` at :160) describe local code that has not shipped yet.

## Divergence
Local working copy has these files, `master` does not — push before the next sync or the map below cannot be resolved from the repo:
`views/dock_top.lua`, `views/dock_bottom.lua`, `views/chat_window.lua`, `services/dock_state.lua`, `services/chat_feed.lua`, `services/chat_console.lua`, `services/hints.lua`, `services/window_zones.lua`, `services/layout_presets.lua`, `services/dock_state.lua`, `utils/dock_layout.lua`, `utils/item_compare.lua`

## Screen map
| Project screen | Repo files |
|---|---|
| 17a Item Display defects (annotated) | lua/itemui/views/item_display.lua *(local ahead of master)*, lua/itemui/constants.lua, lua/itemui/utils/item_compare.lua *(local only)* |
| 17b/17c Item Display v2 | lua/itemui/views/item_display.lua, lua/itemui/utils/item_compare.lua, lua/itemui/utils/item_tooltip.lua, lua/itemui/utils/tooltip_render.lua |
| 17d Crispness levers | lua/itemui/views/item_display.lua:160-162, lua/itemui/components/character_stats.lua:260,386,400,402, lua/coopui/utils/theme.lua, docs/research/APPENDIX_A_SOURCE_EVIDENCE.md |
| 18a Item Display v2.1 (type-aware strip, heroic rank) | lua/itemui/utils/item_compare.lua, lua/itemui/views/item_display.lua, lua/itemui/utils/augment_ranking.lua |
| 18b / 19b Top + bottom bar treatment | lua/itemui/views/dock_top.lua *(local only)*, lua/itemui/views/dock_bottom.lua *(local only)*, lua/itemui/utils/dock_layout.lua *(local only)*, lua/itemui/constants.lua |
| 19a Ornament slot | lua/itemui/views/item_display.lua, lua/itemui/services/augment_ops.lua, lua/itemui/utils/augment_helpers.lua |
| 19c Chat window v2 | lua/itemui/views/chat_window.lua *(local only)*, lua/itemui/services/chat_feed.lua *(local only)*, lua/itemui/services/chat_console.lua *(local only)* |
| 19d Bags pane | lua/itemui/views/inventory.lua, lua/itemui/utils/column_config.lua, lua/itemui/utils/columns.lua, lua/itemui/services/filter_service.lua |
| 19d Equipment pane (paper-doll) | lua/itemui/views/equipment.lua:33-52 |
| 19d Effects pane | lua/itemui/views/effects.lua:267-370 |
| 20a Bank | lua/itemui/views/bank.lua, lua/itemui/utils/column_config.lua:97-137 |
| 20b Reroll | lua/itemui/views/reroll.lua, lua/itemui/services/reroll_service.lua |
| 20c Aug Utility | lua/itemui/views/augment_utility.lua, lua/itemui/utils/augment_ranking.lua, lua/itemui/services/augment_ops.lua |
| 1a Hub + welcome | lua/itemui/views/main_window.lua, lua/itemui/views/tutorial.lua, lua/itemui/components/character_stats.lua, lua/itemui/core/registry.lua |
| 1b Wizard step 10 | lua/itemui/views/tutorial.lua, lua/itemui/views/main_window.lua |
| 1c Settings → Sell Rules | lua/itemui/views/settings.lua, lua/itemui/views/config_filters.lua, lua/itemui/views/config_general.lua |
| 1d Command Center | lua/itemui/views/command_center.lua |
| Palette / colors | lua/coopui/utils/theme.lua |
| 2f Native merchant strip | uifiles/coopt/EQUI_MerchantWnd.xml, lua/itemui/services/native_bridge.lua |

## Sync history
### 2026-07-27
- Recreated the current in-game UI (hub + welcome, setup wizard step, Settings → Sell Rules, Command Center) from Lua source
- Added onboarding and windowing redesign options drawn in the same ImGui vocabulary
- Added a native EQ Merchant strip option based on the shipped CoOpt skin XML
