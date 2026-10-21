# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit configurations of the packetizer (verification plan, section 2): every stream width from 8 to 128 bits,
the options without and with CRC and secondary header, the smallest buffer and segment, two segments in the
buffer, and the configuration of the reference system (128 bits, segments of 4096 bytes)."""


def configure(lib):
    tb = lib.test_bench("spp_packetizer_tb")

    def add(name, width, chunk, buffer, max_chunks=8, sec_hdr=3, crc=True):
        tb.add_config(name=name, generics={
            "DataWidth_g": width,
            "ChunkBytes_g": chunk,
            "BufferBytes_g": buffer,
            "MaxChunks_g": max_chunks,
            "SecHdrBytes_g": sec_hdr,
            "Crc_g": crc,
        })

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

    core = lib.test_bench("spp_packetizer_core_tb")
    core.add_config(name="w32", generics={"DataWidth_g": 32})
