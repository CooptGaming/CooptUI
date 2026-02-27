# Revisit: Task 2.5 Window Positioning (follow-up notes)

Captured after implementing MASTER_PLAN §2.5 (consistent window positioning policy). Basic functionality is working; these items are for later.

---

## 1. Default layout appearance

**Note:** Modify what the "default layout" actually looks like (positions/sizes of windows in the bundled default).  
When ready: adjust `lua/itemui/default_layout/itemui_layout.ini` and/or the capture process (e.g. `coopt_layout_capture.py` per DEFAULT_LAYOUT.md / create-release checklist).

---

## 2. "Reset Window Positions" option

**Note:** Unsure about keeping or changing the "Reset Window Positions" button (Settings → re-applies hub-relative positions only).  
Revisit: keep as-is, change behavior, or remove.

---

## 3. "Revert to Default Layout" — always move every window

**Note:** Later, lock down so "Revert to Default Layout" **always** moves every window back to the default position (no edge cases where a window stays put).  
Verify: after revert, all companion windows (and main window per existing behavior) end up at the positions defined in the bundled default layout.
