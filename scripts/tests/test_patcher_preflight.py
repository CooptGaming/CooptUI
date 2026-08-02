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

# 4. preflight surfaces it as a user-facing reason.
#
# is_macroquest_running() is stubbed FALSE for this assertion. preflight_blockers checks
# the running process first and returns a different message, so with MacroQuest actually
# open on the developer's machine this test asserted the wrong branch and failed - a gate
# whose result depended on whether the game happened to be running. Stubbing isolates the
# thing under test (locked-file reporting); the running-process branch is checked below.
_real_running = installer.is_macroquest_running
installer.is_macroquest_running = lambda: False
try:
    msg = installer.preflight_blockers(tmp)
    assert msg and "MacroQuest.exe" in msg, msg
    print("PASS: preflight_blockers message ->", msg)

    # 4b. the running-process branch wins over locked files, and says something different.
    installer.is_macroquest_running = lambda: True
    running_msg = installer.preflight_blockers(tmp)
    assert running_msg and "MacroQuest.exe" not in running_msg, running_msg
    print("PASS: a running MacroQuest pre-empts the locked-file message ->", running_msg)
finally:
    installer.is_macroquest_running = _real_running

# 5. cleared once writable again
os.chmod(exe, stat.S_IWRITE)
assert installer.find_locked_files(tmp) == []
print("PASS: clears when writable again")

# 6. non-existent target dir does not raise
assert installer.find_locked_files(os.path.join(tmp, "nope")) == []
print("PASS: missing target dir handled")

import shutil; shutil.rmtree(tmp, ignore_errors=True)
print("\nALL PREFLIGHT TESTS PASSED\n")

# ---------------------------------------------------------------------------
# Stock-base downgrade guard.
#
# The stock-E3 fallback bundle is a DIFFERENT MacroQuest family: overlaying it
# replaces every .exe/.dll in the target and force-disables MQ2CoOptUI. It must
# therefore never be applied to a folder that already has CoOpt in it - a GitHub
# rate limit (403/429) is enough to reach that path, and the operation used to
# report success afterwards.
# ---------------------------------------------------------------------------
d0 = tempfile.mkdtemp(prefix="coopt_dg_")
assert installer._has_coopt_install(d0) is False
print("PASS: empty folder is not a CoOpt install")
shutil.rmtree(d0, ignore_errors=True)

for rel in ("plugins/MQ2CoOptUI.dll", "Macros/coopui_installed_version.txt", "lua/itemui/init.lua"):
    d = tempfile.mkdtemp(prefix="coopt_dg_")
    p = os.path.join(d, rel.replace("/", os.sep))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write("x")
    assert installer._has_coopt_install(d) is True, rel
    print(f"PASS: {rel} marks an existing install to protect")
    shutil.rmtree(d, ignore_errors=True)

# A vanilla MacroQuest with no CoOpt has nothing to lose, so the fallback stays available.
d = tempfile.mkdtemp(prefix="coopt_dg_")
open(os.path.join(d, "MacroQuest.exe"), "w").write("x")
assert installer._has_coopt_install(d) is False
print("PASS: vanilla MacroQuest (no CoOpt) still allows the stock fallback")
shutil.rmtree(d, ignore_errors=True)

print("\nALL DOWNGRADE-GUARD TESTS PASSED")
