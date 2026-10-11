# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the core tests: stream widths with the CPTP layer, one width without it, the N-Char
adapters and cores without default managed data paths."""

CPTP = ["test_end_to_end", "test_address_strip", "test_link_errors", "test_loss", "test_eep", "test_send_errors",
        "test_line_rate", "test_reset", "test_default_paths"]
PLAIN = ["test_plain", "test_link_errors", "test_loss"]
# Both links through two N-Char adapters with an 8-bit N-Char stream between them
NCHAR = ["test_end_to_end", "test_link_errors", "test_eep"]
# TxPathDefault_g and RxPathDefault_g false: no APID has a managed data path after the reset; no address bytes
NOPATH = ["test_default_paths"]


def configure(lib):
    tb = lib.test_bench("spp_core_tb")
    for test in CPTP:
        for width in (32, 128):
            tb.test(test).add_config(name=f"cptp_w{width}", generics={"DataWidth_g": width, "Encapsulation_g": True})
    for test in PLAIN:
        tb.test(test).add_config(name="plain_w64", generics={"DataWidth_g": 64, "Encapsulation_g": False})
    for test in NCHAR:
        tb.test(test).add_config(name="nchar_w32", generics={"DataWidth_g": 32, "Encapsulation_g": True, "NChar_g": True})
    for test in NOPATH:
        tb.test(test).add_config(name="nopath_w32", generics={"DataWidth_g": 32, "Encapsulation_g": True,
                                                              "PathDefault_g": False, "SpwAddrBytes_g": 0})
