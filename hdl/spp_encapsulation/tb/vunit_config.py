# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the transfer layer: every test for several stream widths."""


def configure(lib):
    tb = lib.test_bench("spp_encapsulation_tb")
    for width in (8, 24, 64, 128):
        tb.add_config(name=f"w{width}", generics={"DataWidth_g": width})
