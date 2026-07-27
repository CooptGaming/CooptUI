import os, stat, sys, tempfile
sys.path.insert(0, 'patcher')
import installer

tmp = tempfile.mkdtemp(prefix="coopt_pf_")
os.makedirs(os.path.join(tmp, "plugins"), exist_ok=True)
exe = os.path.join(tmp, "MacroQuest.exe")
open(exe, "wb").write(b"MZfake")
open(os.path.join(tmp, "MQ2Main.dll"), "wb").write(b"MZfake")

# 1. nothing locked
locked = installer.find_locked_files(tmp)
assert locked == [], f"expected clear, got {locked}"
print("PASS: unlocked install probes clean ->", locked)

# 2. absent files are skipped, not reported
assert "plugins/MQ2Lua.dll" not in installer.find_locked_files(tmp)
print("PASS: missing probe files are not reported as locked")

# 3. read-only / unwritable file is detected
os.chmod(exe, stat.S_IREAD)
locked = installer.find_locked_files(tmp)
assert locked == ["MacroQuest.exe"], f"expected MacroQuest.exe locked, got {locked}"
print("PASS: unwritable binary detected ->", locked)

# 4. preflight surfaces it as a user-facing reason
msg = installer.preflight_blockers(tmp)
assert msg and "MacroQuest.exe" in msg, msg
print("PASS: preflight_blockers message ->", msg)

# 5. cleared once writable again
os.chmod(exe, stat.S_IWRITE)
assert installer.find_locked_files(tmp) == []
print("PASS: clears when writable again")

# 6. non-existent target dir does not raise
assert installer.find_locked_files(os.path.join(tmp, "nope")) == []
print("PASS: missing target dir handled")

import shutil; shutil.rmtree(tmp, ignore_errors=True)
print("\nALL PREFLIGHT TESTS PASSED")
