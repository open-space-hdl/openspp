# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core tests: stream widths with the CPTP layer, one width without it, the N-Char
adapters and cores without default managed data paths."""

from pathlib import Path

CPTP = ["test_end_to_end", "test_address_strip", "test_link_errors", "test_loss", "test_eep", "test_send_errors",
        "test_line_rate", "test_reset", "test_default_paths"]
PLAIN = ["test_plain", "test_link_errors", "test_loss"]
# Both links through two N-Char adapters with an 8-bit N-Char stream between them
NCHAR = ["test_end_to_end", "test_link_errors", "test_eep"]
# TxPathDefault_g and RxPathDefault_g false: no APID has a managed data path after the reset; no address bytes
NOPATH = ["test_default_paths"]
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
