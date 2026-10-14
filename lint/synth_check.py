# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Synthesis check of OpenSPP with GHDL: elaborates spp_core in the default configuration, without the
CPTP layer, with three ports of both services at 128 bits, with the maximum numbers of ports and destinations, and
with the lower bound of the Maximum Packet Length and round robin as reset values, with the bounds of the buffers
(specification CO-GN-02 to CO-GN-04); spp_nchar at the smallest and the largest stream width. Configurations outside
the bounds must stop with the assertion of the bound.

Usage: python lint/synth_check.py
Uses the libraries compiled by the regression runner (run `python run.py --compile` first).
Exit code 0 when every configuration synthesizes without error and without inferred latch, and every configuration
outside the bounds fails with its assertion.
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
                         "SpwAddrBytes_g": "16"}),
           ("spp_core", {"MaxLength_g": "7", "RoundRobin_g": "'1'", "Tla_g": "00100000"}),
           # Smallest buffers at 8 bits (8 beats, two packets)
           ("spp_core", {"DataWidth_g": "8", "TxBufferBytes_g": "8", "RxBufferBytes_g": "8", "TxMaxPackets_g": "2",
                         "RxMaxPackets_g": "2"}),
           # Largest buffers that are ever written with two packets: 262144 beats at 8 bits, 16384 beats at 128 bits
           ("spp_core", {"DataWidth_g": "8", "TxBufferBytes_g": "262144", "RxBufferBytes_g": "262144",
                         "TxMaxPackets_g": "2", "RxMaxPackets_g": "2"}),
           ("spp_core", {"DataWidth_g": "128", "TxBufferBytes_g": "262144", "RxBufferBytes_g": "262144",
                         "TxMaxPackets_g": "2", "RxMaxPackets_g": "2"}),
           # Most packets in buffers of 16 beats at 32 bits
           ("spp_core", {"DataWidth_g": "32", "TxBufferBytes_g": "64", "RxBufferBytes_g": "64", "TxMaxPackets_g": "16",
                         "RxMaxPackets_g": "8"}),
           ("spp_nchar", {"DataWidth_g": "8"}),
           ("spp_nchar", {"DataWidth_g": "128"})]
# Outside the bounds, with the text that the assertion must report
NEGATIVE = [("spp_core", {"DataWidth_g": "8", "TxBufferBytes_g": "4"}, "(CO-GN-02)"),
            ("spp_core", {"DataWidth_g": "8", "TxBufferBytes_g": "524288", "RxBufferBytes_g": "524288",
                          "TxMaxPackets_g": "2", "RxMaxPackets_g": "2"}, "(CO-GN-03)"),
            ("spp_core", {"TxMaxPackets_g": "1"}, "(CO-GN-04)"),
            ("spp_core", {"TxBufferBytes_g": "64", "RxBufferBytes_g": "64", "RxMaxPackets_g": "9"}, "(CO-GN-04)"),
            ("spp_nchar", {"DataWidth_g": "12"}, "multiple of 8")]


def run_synth(top, generics, out_dir):
    cmd = ["ghdl", "--synth", "--std=08", "-frelaxed", f"-P{LIBS / 'olo'}", "--work=openspp",
           f"--workdir={LIBS / 'openspp'}"]
    cmd += [f"-g{name}={value}" for name, value in generics.items()]
    cmd.append(top)
    name = top + "".join(f"_{k[:-2]}{v.strip(chr(39))}" for k, v in generics.items() if len(v) < 8)
    with open(out_dir / f"{name}.vhd", "w") as netlist:
        res = subprocess.run(cmd, stdout=netlist, stderr=subprocess.PIPE, text=True)
    return name, res.returncode, res.stderr


def synth(top, generics, out_dir):
    name, returncode, log = run_synth(top, generics, out_dir)
    # Inferred latches are reported as "latch" warnings
    latches = [line for line in log.splitlines() if re.search(r"\blatch\b", line, re.IGNORECASE)]
    errors = [line for line in log.splitlines() if "error" in line.lower() or "exception" in line.lower()]
    ok = returncode == 0 and not latches and not errors
    print(f"{name}: {'OK' if ok else 'FAILED'}")
    for line in (errors + latches)[:20]:
        print("  " + line)
    return ok


def synth_fails(top, generics, expected, out_dir):
    name, returncode, log = run_synth(top, generics, out_dir)
    ok = returncode != 0 and expected in log
    print(f"{name}: {'stopped as expected' if ok else 'FAILED, expected a stop with ' + expected}")
    if not ok:
        for line in log.splitlines()[:20]:
            print("  " + line)
    return ok


def main():
    if not LIBS.exists():
        raise SystemExit("compiled libraries not found, run: python run.py --compile")
    with tempfile.TemporaryDirectory() as tmp:
        results = [synth(top, gen, Path(tmp)) for top, gen in CONFIGS]
        results += [synth_fails(top, gen, expected, Path(tmp)) for top, gen, expected in NEGATIVE]
    sys.exit(0 if all(results) else 1)


if __name__ == "__main__":
    main()
