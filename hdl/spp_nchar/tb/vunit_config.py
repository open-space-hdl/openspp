# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the N-Char adapter: every test for every stream width (multiples of 8 from 8 to 128)."""


def configure(lib):
    tb = lib.test_bench("spp_nchar_tb")
    for width in range(8, 129, 8):
        tb.add_config(name=f"w{width}", generics={"DataWidth_g": width})
