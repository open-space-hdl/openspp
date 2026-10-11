# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the N-Char adapter: every test for several stream widths."""


def configure(lib):
    tb = lib.test_bench("spp_nchar_tb")
    for width in (8, 24, 32, 128):
        tb.add_config(name=f"w{width}", generics={"DataWidth_g": width})
