#!/usr/bin/env python3
"""
CoOpt UI rebranding verification.
Run from project root. Excludes .git/ and docs/CoopUI_Rebranding_Audit.md
(that file intentionally documents old names).
"""
import os
import re
import sys

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXTS = ('.lua', '.md', '.ps1', '.mac')
EXCLUDE_DIRS = {'.git', 'node_modules', '__pycache__', 'Backup'}
AUDIT_DOC = 'docs' + os.sep + 'CoopUI_Rebranding_Audit.md'

PATTERNS = [
    ('E3Next', re.compile(r'E3Next', re.I)),
    ('MQNext', re.compile(r'MQNext', re.I)),
    ('E3NextAndMQNextBinary', re.compile(r'E3NextAndMQNextBinary', re.I)),
]

def relpath(path):
    return os.path.relpath(path, PROJECT_ROOT)

def main():
    os.chdir(PROJECT_ROOT)
    hits = []  # (file, line_no, pattern_name, line_text)

    for root, dirs, files in os.walk(PROJECT_ROOT, topdown=True):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        for f in files:
            if not any(f.endswith(ext) for ext in EXTS):
                continue
            path = os.path.join(root, f)
            rel = relpath(path)
            if rel.replace(os.sep, '/') == 'docs/CoopUI_Rebranding_Audit.md':
                continue
            try:
                with open(path, 'r', encoding='utf-8', errors='replace') as fp:
                    for i, line in enumerate(fp, 1):
                        for name, pat in PATTERNS:
                            if pat.search(line):
                                hits.append((rel, i, name, line.rstrip()[:80]))
            except Exception as e:
                print(f"Warning: could not read {rel}: {e}", file=sys.stderr)

    # Report
    if not hits:
        print("Verification PASSED: no E3Next/MQNext/E3NextAndMQNextBinary in code/docs.")
        print("(Excluded: .git/, docs/CoopUI_Rebranding_Audit.md)")
        return 0

    print("Verification FAILED: found old-name references:")
    for rel, line_no, name, text in hits:
        print(f"  {rel}:{line_no} [{name}] {text}")
    print(f"\nTotal: {len(hits)} hit(s). Fix or add to exclusions.")
    return 1

if __name__ == '__main__':
    sys.exit(main())
