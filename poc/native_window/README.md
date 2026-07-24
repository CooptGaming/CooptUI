# Native-Window Extension — Proof of Concept

> **Status: superseded** by the production native merchant strip
> (`lua/itemui/services/native_bridge.lua` + `uifiles/coopt`). Do not run
> `coopt_poc` alongside itemui with the `coopt` skin — the control names
> differ. Two hard-won lessons folded into production: (1) `Window.Child()`
> for an **absent** name can return an object with a non-nil ToString but
> nil members — test a member, never ToString; (2) unlatching a checkbox by
> sending a synthetic `/notify leftmouseup` immediately after detecting the
> click can land **while the user's real mouse button is still down**,
> wedging EQ's mouse capture on that button. Production detects checkbox
> state *transitions* instead and only sends the cosmetic un-latch when
> `MouseOver()` is false.

Tests whether CoOpt features can live **inside native EQ windows**: a custom UI
skin adds a CoOpt button strip to the stock RoF2 Merchant window, and a small
Lua script gives those buttons behavior through MacroQuest.

## What it proves (the three open questions)

1. **Do skin-added controls render and survive in a stock window on RoF2?**
   → Open a merchant with the skin loaded: a `CoOpt` button, a `CoOpt UI`
   button, and a yellow status line appear at the bottom of the window.
2. **Can Lua detect clicks on them?** The buttons are `Style_Checkbox`, so a
   click latches; the script polls `Window("MerchantWnd").Child(...).Checked`,
   acts, and unlatches via `/notify leftmouseup`.
3. **Can Lua write dynamic text into the native window?** The status line is a
   transparent EditBox (this MQ build's `Window.SetText` only supports
   EditBoxes). The script self-tests two write paths and prints PASS/FAIL.

## Files

| File | Installs to |
|---|---|
| `EQUI_MerchantWnd.xml` | `<EQ>\uifiles\coopt_poc\` (stock RoF2 file + 3 added controls — all 25 stock ScreenIDs untouched, verified) |
| `coopt_poc.lua` | `<MQ>\lua\` |

`install_poc.ps1 [-EqDir <path>] [-MqDir <path>]` copies both.

## Test steps (in game)

1. `/loadskin coopt_poc` — merchant window gets the CoOpt strip. Everything
   else stays your normal UI (per-file skin fallback).
2. `/lua run coopt_poc`
3. Open any merchant. Expect a PASS line saying the controls were found.
4. Click **CoOpt** → beep + PASS line in chat + (if SetText works) the status
   line updates with a ping counter.
5. Click **CoOpt UI** → the CoOpt UI toggles (requires itemui running).
6. Revert anytime: `/loadskin default` and `/lua stop coopt_poc`.

Nothing in the POC sells, buys, or moves items.

## Known cosmetics / notes

- On the merchant's **Parcels tab**, the status line overlaps the stock
  Note field (both live in the bottom strip). Cosmetic, POC-only.
- The status line is technically an EditBox: clicking it lets you type into
  it. Harmless; the real implementation uses the plugin (`SetWindowText` on a
  true Label, `WndNotification` hooks instead of checkbox polling).
- If you play from a different EQ folder than `PerkyCrew-EQ - Copy`, run
  `install_poc.ps1 -EqDir <that folder>` (or copy `uifiles\coopt_poc` over).

## What to report back

- Did the strip render? Any visual glitches when resizing the window?
- Did clicks register every time (PASS lines)? Any missed/double fires?
- Which SetText path passed (`method`, `invoke`, or FAIL)?
- Any crash/oddity when clicking Buy/Sell/tabs with the skin loaded.
