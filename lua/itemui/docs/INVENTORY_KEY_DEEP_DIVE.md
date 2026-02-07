# Deep Dive: /invopen Error and defend.mac Console Output

## The Error

```
DoCommand - Couldn't parse '/invopen'
defend.mac@9 (Main): /delay .2s
```

## Root Cause Chain

### 1. The I Key Is Bound to a Custom Bind

In `config/MacroQuest.ini`:
```
itemui_inv_Nrm=I
```
This means: **Pressing I** triggers the custom bind named `itemui_inv`.

### 2. The Bind's Command Comes from MQ2CustomBinds.txt

In `config/MQ2CustomBinds.txt`:
```
name=itemui_inv
down=/invopen
up=
```

When you press I, MQ2CustomBinds executes `down=/invopen`. The command `/invopen` **does not exist** — it's not a built-in MQ command, and ItemUI provides `/inv` (not `/invopen`). MQ's parser fails with "Couldn't parse '/invopen'".

### 3. Why defend.mac Appears in the Output

**defend.mac is not triggered by pressing I.** It's simply the macro that was running when the error occurred.

Flow:
1. **defend.mac** is your active macro (always-on loop: /doevent, /delay .2s, /goto Start).
2. When defend.mac hits `/delay .2s`, it **yields** — MQ processes the event queue.
3. **You press I** during that yield.
4. The I key fires the `itemui_inv` bind → tries to run `/invopen` → **error**.
5. MQ reports the error and includes the **current execution context**: the macro that yielded (defend.mac) at line 9.

So `defend.mac@9 (Main): /delay .2s` means: "This error happened while defend.mac was paused at its /delay line." It's **context**, not causation.

### 4. Why MQ2CustomBinds.txt May Revert to /invopen

If you previously fixed the file to `down=/inv` but it shows `/invopen` again, possible causes:
- **Git/sync overwrite** — Another branch, backup, or sync restored the old file.
- **Deploy script** — A deploy or install script may copy from a template that has `/invopen`.
- **Multiple MQ installs** — You might be editing one config while MQ runs from another (e.g. different folder).
- **File not saved** — The editor hadn't saved before testing.

## Fixes

### Fix 1: Correct the Bind (Primary)

Edit `config/MQ2CustomBinds.txt`:
```
name=itemui_inv
down=/inv
up=
```

Then **reload MQ2CustomBinds** so it picks up the change:
```
/plugin MQ2CustomBinds unload
/plugin MQ2CustomBinds
```

Or restart MacroQuest.

### Fix 2: Suppress the Error (Optional)

If you can't fix the bind immediately, add a filter in `config/MacroQuest.ini` under `[Filter]` (or wherever Filter28/29 live):
```
FilterXX=DoCommand - Couldn't parse '/invopen'
```
Replace XX with the next unused filter number. This only hides the message; the bind still fails.

### Fix 3: Remove the I Key Bind

If you prefer EQ's default inventory behavior (no custom bind on I):
1. Clear the bind: `/bind itemui_inv clear`
2. ItemUI will still auto-open when it detects the EQ inventory window opening.

## Summary

| What | Why |
|------|-----|
| `/invopen` error | MQ2CustomBinds.txt has `down=/invopen`; that command doesn't exist |
| defend.mac in output | defend.mac was the active macro when the bind fired; MQ shows context |
| ItemUI still opens | ItemUI detects the EQ inventory window and runs `/inv` via its main loop |

---

## I Key vs /inv: Why Different Behavior?

**Previously:** When pressing I (EQ inventory opens), ItemUI auto-detected and showed the UI with **cached data first**, then deferred the scan to the next frame. Result: UI appeared quickly but items "shuffled" as the scan updated the table.

**When using /inv:** handleCommand ran `maybeScanInventory()` **immediately** before the next render. Result: UI appeared with fresh data, no shuffle.

**Fix:** Auto-show from inventory open now runs `maybeScanInventory()` immediately (same as /inv), so both paths behave identically — UI shows with fresh data, no shuffle.
