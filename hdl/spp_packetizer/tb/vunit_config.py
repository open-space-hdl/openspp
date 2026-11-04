# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the packetizer (verification plan, section 2): every stream width from 8 to 128 bits,
the options without and with CRC and secondary header, the smallest buffer and segment, two segments in the
buffer, the configuration of the reference system (128 bits, segments of 4096 bytes), and the bounds of the ranges
(the longest segment with every option, the most segments in the buffer) with the tests that reach them."""


def generics(width, chunk, buffer, max_chunks=8, sec_hdr=3, crc=True):
    return {
        "DataWidth_g": width,
        "ChunkBytes_g": chunk,
        "BufferBytes_g": buffer,
        "MaxChunks_g": max_chunks,
        "SecHdrBytes_g": sec_hdr,
        "Crc_g": crc,
    }


# Bounds of the ranges and the tests that run in them
BOUNDS = {
    # Packet Data Length 65535 without options, with the CRC, with the longest secondary header, with both
    "max64k": (generics(128, 65536, 65536, sec_hdr=0, crc=False), ["test_bounds"]),
    "maxcrc": (generics(16, 65534, 65536, sec_hdr=0, crc=True), ["test_bounds", "test_crc_vectors"]),
    "maxsh": (generics(8, 65472, 65536, sec_hdr=64, crc=False), ["test_bounds"]),
    "maxshcrc": (generics(32, 65468, 65536, sec_hdr=64, crc=True), ["test_bounds"]),
    # 64 segments in the buffer: short data units while the output is slower than the input
    "mc64": (generics(32, 32, 512, max_chunks=64), ["test_bounds", "test_segmentation", "test_count_wrap"]),
}


def configure(lib):
    tb = lib.test_bench("spp_packetizer_tb")

    def add(name, *args, **kwargs):
        tb.add_config(name=name, generics=generics(*args, **kwargs))

    for width in range(8, 129, 8):
        beat = width // 8
        add(f"w{width}", width, 8 * beat, 16 * beat)
    add("plain", 32, 32, 64, sec_hdr=0, crc=False)
    add("crc", 32, 32, 64, sec_hdr=0)
    add("sh1", 32, 32, 64, sec_hdr=1, crc=False)
    add("sh64", 32, 32, 64, sec_hdr=64)
    add("buf1", 32, 32, 32)
    add("mc2", 32, 32, 64, max_chunks=2)
    add("beat1", 32, 4, 8)
    add("w128_4k", 128, 4096, 8192, sec_hdr=0)

    for name, (gen, tests) in BOUNDS.items():
        for test in tests:
            tb.test(test).add_config(name=name, generics=gen)

    core = lib.test_bench("spp_packetizer_core_tb")
    core.add_config(name="w32", generics={"DataWidth_g": 32})
