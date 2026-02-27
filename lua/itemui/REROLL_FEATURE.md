# Reroll Companion Feature

## Architecture Decision

**Chosen approach: New companion window with two internal tabs (Augments | Mythicals).**

- **Why not a new tab in the main Inventory view:** The main content area is context-driven (Inventory vs Sell vs Loot), not a tab bar. Adding Reroll as a fourth context would dilute the primary use case and require another mode switch.
- **Why not the Augments window:** The Augments window is for “Always sell / Never loot” and augment lists; it is not a server-backed list. Reroll is a separate system (server commands, list from chat, roll consumption).
- **Why a companion window:** Matches existing CoOpt UI pattern: Bank, Equipment, Augments, Augment Utility, Item Display, AA, and Loot are all separate companion windows opened by header buttons. The Reroll Companion fits this model and keeps the main hub uncluttered.
- **Why two tabs inside:** Augments and Mythicals are parallel tracks with identical command shapes (!augadd / !mythicaladd, etc.). One window with two tabs avoids two nearly identical windows and shares layout/position.

## Access

- **Header:** Click “Reroll” in the CoOpt UI Inventory Companion header (next to Augments).
- **Slash command:** `/itemui reroll` or `/inv reroll` (consistent with `/itemui config`).

## Server Integration

- Commands are sent via `/say <command>` (e.g. `/say !auglist`). If your server uses a different channel (e.g. tell, guild), the service can be extended to use a configurable command prefix or channel.
- **List response parsing:** The service registers `mq.event` for chat lines containing `:`. When you request a list, the next ~3 seconds of matching chat lines are parsed as `ID: Name` or `ID - Name` and appended to the current list. Server list output should use one line per item in that format.

## Files

- **`lua/itemui/constants.lua`** — `M.REROLL` and `M.VIEWS` (WidthRerollPanel, HeightReroll).
- **`lua/itemui/services/reroll_service.lua`** — List state, `/say` commands, chat event parsing, inventory count helper.
- **`lua/itemui/views/reroll.lua`** — Reroll Companion window: tabs, table (Name, Item ID, In Inventory), counter (X/10), Add/Remove/Roll/Refresh with confirmations.
- **`lua/itemui/views/main_window.lua`** — “Reroll” button, `renderRerollWindow`, initial position when first opened.
- **`lua/itemui/init.lua`** — `rerollService.init`, context `rerollService`, `uiState.rerollWindowOpen/ShouldDraw`, `closeCompanionWindow("reroll")`, `handleCommand("reroll")`, help text.
- **`lua/itemui/utils/layout.lua`** — Load/save/capture for WidthRerollPanel, HeightReroll, RerollWindowX, RerollWindowY.

## Constants (no magic strings)

All command and UI constants live in `itemui.constants` (`M.REROLL`, `M.VIEWS`). The service and view use these only.

## Error Handling and UX

- Add (from Cursor): Disabled when cursor empty, item already on list, or (Mythical tab) cursor item not named “Mythical*”; tooltip explains why.
- Remove: Requires selection (or context menu “Remove from list”); confirmation step before sending !augremove / !mythicalremove.
- Roll: Enabled only when “X / 10 items in inventory” ≥ 10; confirmation step before sending !augroll / !mythicalroll.
- Refresh: Sends !auglist or !mythicallist and repopulates from chat; status message and list update after server response.
- Empty list / no inventory match: Muted text and clear messaging; no hard errors.

## Design Language

- Colors, fonts, spacing, and table style come from `coopui.utils.theme` and existing table flags (e.g. `ctx.uiState.tableFlags`). Counter uses theme Success / Warning / Muted. Buttons use PushKeepButton / PushDeleteButton / PopButtonColors like other companions.
