# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the header insertion and removal: every test for each stream width."""


def configure(lib):
    tb = lib.test_bench("spp_header_tb")
    for width in (8, 16, 24, 32, 64, 128):
        tb.add_config(name=f"w{width}", generics={"DataWidth_g": width})
