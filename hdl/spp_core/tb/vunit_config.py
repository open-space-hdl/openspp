# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core tests: stream widths with the CPTP layer, one width without it, the N-Char
adapters and cores without default managed data paths, and every value of the generics that change the structure of
the core (stream width, port and destination counts, address length) and the bounds of the others."""

from pathlib import Path

CPTP = ["test_end_to_end", "test_address_strip", "test_link_errors", "test_loss", "test_eep", "test_send_errors",
        "test_line_rate", "test_throughput", "test_reset", "test_default_paths"]
PLAIN = ["test_plain", "test_link_errors", "test_loss", "test_throughput"]
# Both links through two N-Char adapters with an 8-bit N-Char stream between them
NCHAR = ["test_end_to_end", "test_link_errors", "test_eep"]
# TxPathDefault_g and RxPathDefault_g false: no APID has a managed data path after the reset; no address bytes
NOPATH = ["test_default_paths"]
# Every stream width (multiples of 8 from 8 to 128) that the configurations above do not cover
WIDTHS = [8, 16, 24, 40, 48, 56, 72, 80, 88, 96, 104, 112, 120]
# Every port and destination count: n send ports, 17 - n receive ports and n destinations
PORTS = range(1, 17)
# Every Target SpaceWire Address length, with the stream widths in turn
ADDRESS = range(0, 17)
# Packets held by a send buffer and by the receive buffer: the minimum and a value that is not a power of two
PACKETS = [2, 5]
# Bounds of the buffers (specification CO-GN-02 to CO-GN-04): the smallest buffer at 8 bits, the largest buffer
# that is ever written with two packets at 8 bits, and the most packets a buffer of 16 beats holds at 32 bits and a
# buffer of 8192 beats at 8 bits (8192 send packets exceed 2**29 beats of written data: the bound of CO-GN-03 is
# above every valid depth)
BUFFERS = {"bufmin_w8": {"DataWidth_g": 8, "BufferBeats_g": 8, "TxMaxPackets_g": 2, "RxMaxPackets_g": 2},
           "bufmax_w8": {"DataWidth_g": 8, "BufferBeats_g": 262144, "TxMaxPackets_g": 2, "RxMaxPackets_g": 2},
           "pktmax_w32": {"DataWidth_g": 32, "BufferBeats_g": 16, "TxMaxPackets_g": 16, "RxMaxPackets_g": 8},
           "pktmax_w8": {"DataWidth_g": 8, "BufferBeats_g": 8192, "TxMaxPackets_g": 8192, "RxMaxPackets_g": 1170}}
# Lower bound of the Maximum Packet Length, round robin and a Target Logical Address other than the defaults
LIMITS = {"MaxLength_g": 7, "RoundRobin_g": True, "Tla_g": 0x20}
# Idle cores with the IEEE warnings enabled: no metavalue warning after the table initialisation
IDLE = {"cptp_w32": {"DataWidth_g": 32, "Encapsulation_g": True},
        "plain_w64": {"DataWidth_g": 64, "Encapsulation_g": False},
        "nchar_w32": {"DataWidth_g": 32, "Encapsulation_g": True, "NChar_g": True}}
IDLE_MARKER = "SPP_IDLE_CHECK_START"
# Positive control: the testbench raises the warning of to_integer on an undefined vector between these markers
PROBE_MARKERS = ("SPP_IDLE_PROBE_START", "SPP_IDLE_PROBE_END")


def no_metavalue_after_marker(output_path):
    """Post check of test_idle: requires the numeric_std warning of the testbench probe (the IEEE warnings are
    enabled) and fails on a numeric_std metavalue warning after the marker of the testbench."""
    text = (Path(output_path) / "output.txt").read_text(encoding="utf-8", errors="replace").splitlines()
    probe = [next((i for i, line in enumerate(text) if marker in line), None) for marker in PROBE_MARKERS]
    if None in probe:
        print("test_idle: probe markers " + " and ".join(PROBE_MARKERS) + " not found in the simulator output")
        return False
    if not any("TO_INTEGER" in line.upper() and "metavalue" in line.lower() for line in text[probe[0] + 1:probe[1]]):
        print("test_idle: the numeric_std warning of the testbench probe is missing; the IEEE warnings are disabled, "
              "so the check after the marker would see nothing")
        return False
    start = next((i for i, line in enumerate(text) if IDLE_MARKER in line), None)
    if start is None:
        print("test_idle: marker " + IDLE_MARKER + " not found in the simulator output")
        return False
    found = [line for line in text[start + 1:] if "metavalue" in line.lower()]
    for line in found[:10]:
        print("test_idle: " + line)
    return not found


def configure(lib):
    tb = lib.test_bench("spp_core_tb")
    for test in CPTP:
        for width in (32, 128):
            tb.test(test).add_config(name=f"cptp_w{width}", generics={"DataWidth_g": width, "Encapsulation_g": True})
    for test in PLAIN:
        tb.test(test).add_config(name="plain_w64", generics={"DataWidth_g": 64, "Encapsulation_g": False})
    for test in NCHAR:
        tb.test(test).add_config(name="nchar_w32", generics={"DataWidth_g": 32, "Encapsulation_g": True, "NChar_g": True})
    for name, generics in IDLE.items():
        tb.test("test_idle").add_config(name=name, generics=generics, sim_options={"disable_ieee_warnings": False},
                                        post_check=no_metavalue_after_marker)
    for test in NOPATH:
        tb.test(test).add_config(name="nopath_w32", generics={"DataWidth_g": 32, "Encapsulation_g": True,
                                                              "PathDefault_g": False, "SpwAddrBytes_g": 0})
    for width in WIDTHS:
        for test in ("test_end_to_end", "test_reset_values"):
            tb.test(test).add_config(name=f"cptp_w{width}", generics={"DataWidth_g": width, "Encapsulation_g": True})
    for n in PORTS:
        generics = {"DataWidth_g": 32, "Encapsulation_g": True, "NumTx_g": n, "NumRx_g": 17 - n, "NumDest_g": n}
        for test in ("test_every_port", "test_reset_values"):
            tb.test(test).add_config(name=f"ports{n}_w32", generics=generics)
    for length in ADDRESS:
        width = 8 * (length % 16 + 1)
        generics = {"DataWidth_g": width, "Encapsulation_g": True, "SpwAddrBytes_g": length}
        for test in ("test_address_strip", "test_reset_values"):
            tb.test(test).add_config(name=f"addr{length}_w{width}", generics=generics)
    for packets in PACKETS:
        tb.test("test_end_to_end").add_config(name=f"packets{packets}_w32", generics={
            "DataWidth_g": 32, "Encapsulation_g": True, "TxMaxPackets_g": packets, "RxMaxPackets_g": packets})
    for name, generics in BUFFERS.items():
        tb.test("test_reset_values").add_config(name=name, generics=dict(generics, Encapsulation_g=True))
    tb.test("test_reset_values").add_config(name="limits_w32", generics=dict(LIMITS, DataWidth_g=32,
                                                                             Encapsulation_g=True))
