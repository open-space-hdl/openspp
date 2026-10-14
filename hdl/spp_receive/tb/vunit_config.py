# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the receiving end: each test in the port configurations and stream widths it needs."""

SINGLE = {"NumRx_g": 1, "PacketPorts_g": 0}
# Ports 0 and 2 Octet String Service, port 1 Packet Service
MIXED = {"NumRx_g": 3, "PacketPorts_g": 2}

TESTS = {
    "test_octet_delivery": [("single", SINGLE, w) for w in (8, 32, 128)],
    "test_packet_delivery": [("mixed", MIXED, w) for w in (24, 64)],
    "test_checks": [("single", SINGLE, w) for w in (8, 64)],
    "test_null_bytes": [("single", SINGLE, w) for w in (8, 32, 128)] + [("mixed", MIXED, 64)],
    "test_routing": [("mixed", MIXED, 32)],
    "test_loss": [("single", SINGLE, 32)],
    "test_max_length": [("big", SINGLE, 32)],
    "test_line_rate": [("single", SINGLE, w) for w in (32, 128)],
    "test_ecc": [("single", SINGLE, w) for w in (32, 64)],
    "test_reset": [("single", SINGLE, 32)],
    "test_random": [("mixed", MIXED, w) for w in (16, 128)],
}


def configure(lib):
    tb = lib.test_bench("spp_receive_tb")
    for test, configs in TESTS.items():
        for name, generics, width in configs:
            # Buffer of 1024 beats (32768 beats for the maximum packet length)
            beats = 32768 if name == "big" else 1024
            generics = dict(generics, DataWidth_g=width, BufferBytes_g=width // 8 * beats)
            tb.test(test).add_config(name=f"{name}_w{width}", generics=generics)
