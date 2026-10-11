# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VSG lint of all OpenSPP VHDL files with the Open Logic rule set.

Usage: python lint/lint.py [--fix] [files...]
  --fix  apply the safe automatic fixes of lint/config/fix_only_openspp.yml first
Exit code 0 when all files are clean (no errors, no warnings).
"""

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "lint" / "config" / "vsg_config.yml"
FIX_ONLY = ROOT / "lint" / "config" / "fix_only_openspp.yml"
CRLF = bytes([13, 10])
LF = bytes([10])


def find_vsg():
    # "python -m vsg" silently does nothing on some installations, use the executable
    exe = shutil.which("vsg")
    if exe:
        return exe
    candidate = Path(sys.executable).parent / "Scripts" / "vsg.exe"
    if candidate.exists():
        return str(candidate)
    raise SystemExit("vsg executable not found (pip install vsg==3.27)")


def vhdl_files():
    files = sorted((ROOT / "hdl").rglob("*.vhd")) + sorted((ROOT / "tb").rglob("*.vhd"))
    return [str(f.relative_to(ROOT)) for f in files]


def main():
    args = sys.argv[1:]
    fix = "--fix" in args
    files = [a for a in args if a != "--fix"] or vhdl_files()
    vsg = find_vsg()
    os.chdir(ROOT)
    if fix:
        # VSG rewrites every file; restore the time stamp of files whose content did not change, so that
        # the simulators do not ask for a re-analysis of unchanged files
        before = {f: (Path(f).read_bytes(), os.stat(f)) for f in files}
        # Several passes: VSG fixes phase by phase
        for _ in range(3):
            subprocess.run([vsg, "-c", str(CONFIG), "--fix", "--fix_only", str(FIX_ONLY), "-f", *files],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        for f, (content, st) in before.items():
            new = Path(f).read_bytes()
            # Keep LF line endings (VSG writes CRLF on Windows)
            if CRLF not in content and CRLF in new:
                new = new.replace(CRLF, LF)
                Path(f).write_bytes(new)
            if new == content:
                os.utime(f, ns=(st.st_atime_ns, st.st_mtime_ns))
    result = subprocess.run([vsg, "-c", str(CONFIG), "--all_phases", "-of", "summary", "-f", *files],
                            capture_output=True, text=True, check=False)
    print(result.stdout)
    if result.returncode != 0:
        print(result.stderr)
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
