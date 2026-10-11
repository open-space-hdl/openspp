# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenSPP with GHDL: elaborates spp_core in the default configuration, without the
CPTP layer, with three ports of both services at 128 bits, and with the maximum numbers of ports and destinations.

Usage: python lint/synth_check.py
Uses the libraries compiled by the regression runner (run `python run.py --compile` first).
Exit code 0 when every configuration synthesizes without error and without inferred latch.
This is a technology-independent check of synthesizability; resources and timing need the FPGA tools.
"""

import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIBS = ROOT / "vunit_out" / "ghdl" / "libraries"
CONFIGS = [("spp_core", {}),
           ("spp_core", {"Encapsulation_g": "false"}),
           ("spp_core", {"SpwAddrBytes_g": "0", "TxPathDefault_g": "false", "RxPathDefault_g": "false"}),
           ("spp_core", {"NumTx_g": "3", "NumRx_g": "3", "DataWidth_g": "128", "NumDest_g": "4",
                         "TxOctetString_g": "1111111111111101", "RxOctetString_g": "1111111111111101",
                         "TxBufferBytes_g": "16384", "RxBufferBytes_g": "16384"}),
           ("spp_core", {"NumTx_g": "16", "NumRx_g": "16", "DataWidth_g": "8", "NumDest_g": "16",
                         "SpwAddrBytes_g": "16"})]


def synth(top, generics, out_dir):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openspp",
           f"--workdir={LIBS / 'openspp'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    name = top + "".join(f"_{k[:-2]}{v}" for k, v in generics.items() if len(v) < 8)
    with open(out_dir / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    log = res.stderr
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = res.returncode == 0 and not latches and not errors
    print(f"{name}: {'OK' if ok else 'FAILED'}")
    for line in (errors + latches)[:20]:
        print("  " + line)
    return ok


def main():
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    with tempfile.TemporaryDirectory() as tmp:
        results = [synth(top, gen, Path(tmp)) for top, gen in CONFIGS]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
