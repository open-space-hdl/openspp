# spp_packetizer: Verification Plan

## 1. Overview

A stream source drives data units into the packetizer, a stream sink compares every output packet byte by byte with
the Space Packet that the packet model of `tb/` builds for its segment (`tbSpacePacket` with the Sequence Flags,
the expected count, the secondary header and the CRC of an own CRC-16 function of the model). The model never uses
the RTL of the core. Monitors in the testbench count `Hdr_Sample`, `Aborted`, `Ecc_Sec` and `Ecc_Ded`, record the
values of `Cfg_*` and `SecHdr_Data` at every sampling edge, and measure the cycles of input and output.

The integration with the core (phase G) runs in a second testbench: packetizer, `spp_core` with a send port and a
receive port of the Packet Service, link output looped back to the link input.

## 2. Test configuration

| Testbench | DUT and environment |
| --- | --- |
| `spp_packetizer_tb` | `spp_packetizer` at 100 MHz, a stream source on `S`, a stream sink on `M`, monitors of the side signals; `Cfg_*` and `SecHdr_Data` driven by the test |
| `spp_packetizer_core_tb` | `spp_packetizer` in front of send port 0 of `spp_core` (Packet Service), link output of the core looped back to its link input, receive port 0 (Packet Service) into a stream sink |

VUnit configurations of `spp_packetizer_tb` (every configuration runs every test case):

| Configuration | `DataWidth_g` | `ChunkBytes_g` | `BufferBytes_g` | `MaxChunks_g` | `SecHdrBytes_g` | `Crc_g` |
| --- | --- | --- | --- | --- | --- | --- |
| `w8` to `w128` (16) | 8 to 128 in steps of 8 | 8 beats | 16 beats | 8 | 3 | true |
| `plain` | 32 | 32 | 64 | 8 | 0 | false |
| `crc` | 32 | 32 | 64 | 8 | 0 | true |
| `sh1` | 32 | 32 | 64 | 8 | 1 | false |
| `sh64` | 32 | 32 | 64 | 8 | 64 | true |
| `buf1` | 32 | 32 | 32 | 8 | 3 | true |
| `mc2` | 32 | 32 | 64 | 2 | 3 | true |
| `beat1` | 32 | 4 | 8 | 8 | 3 | true |
| `w128_4k` | 128 | 4096 | 8192 | 8 | 0 | true |

`spp_packetizer_core_tb` runs at 32 bits with `ChunkBytes_g` = 64, `SecHdrBytes_g` = 3 and `Crc_g` = true.

`lint/synth_check.py` synthesizes the packetizer at the bounds of every range: `DataWidth_g` 8 and 128,
`ChunkBytes_g` of one beat and 65536 (without secondary header and CRC), `BufferBytes_g` equal to `ChunkBytes_g`,
`MaxChunks_g` 2 and 64, `SecHdrBytes_g` 64. A width of 12 bits, a segment that is not a multiple of the beat, a
segment longer than 65536 bytes less the secondary header and the CRC, a buffer that is not a power of two beats or
smaller than a segment, `MaxChunks_g` = 1 or 65 and `SecHdrBytes_g` = 65 stop with the message of their assertion.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_segmentation` (TC-PT-01) | Data units of 1 byte, one beat, a segment less one byte, one segment, one segment plus one byte, two and three segments plus a part, and 40 random lengths up to five segments, random stalls at input and output: every packet byte-exact (flags, count, length, APID, type, Secondary Header Flag, secondary header, data, CRC) and in order | PT-IF-01, PT-IF-02, PT-SG-01, PT-SG-02, PT-SG-05, PT-HD-01, PT-HD-03, PT-SH-01, PT-SH-02, PT-CR-01, PT-CR-02, PT-BF-01 |
| `test_count_wrap` (TC-PT-02) | 16390 data units of one byte without stalls: the counts run from 0 to 16383 and continue with 0 to 5 | PT-HD-02 |
| `test_aborted` (TC-PT-03) | Data units with `S_Error` on the last beat (a data beat and a last beat without byte enables, one and several segments) between normal ones: the packets are those of normal data units, `Aborted` pulses once per aborted data unit and never otherwise; `S_Error` on beats other than the last is ignored | PT-SG-03 |
| `test_null_last` (TC-PT-04) | Data units ending with a last beat without byte enables: after a partial beat, after a full beat inside a segment, directly after a full segment (flags '10' or '11' on that segment) and as the only beat of a data unit (no packet, the count does not change); stalls on both sides | PT-IF-04, PT-SG-02, PT-SG-04 |
| `test_held_segment` (TC-PT-05) | A full segment without `Last` and a pause of 200 cycles at the input: no `Hdr_Sample` and no output during the pause; the next beat releases the packet with '01'; the same with a last beat without byte enables gives '11' | PT-SG-04 |
| `test_header_sample` (TC-PT-06) | `Cfg_Apid`, `Cfg_Type` and `SecHdr_Data` change in every clock cycle: every packet carries the values of the sampling edge of its `Hdr_Sample` cycle; one pulse per packet, in packet order, at least two cycles before the first output beat of the packet | PT-HD-01, PT-HD-04, PT-SH-01 |
| `test_crc_vectors` (TC-PT-07) | The four data blocks of ECSS-E-ST-70-41C Table B-2 as data units: the CRC bytes are 1D 0F, CC 9C, 04 A2 and 7F D5 (configurations with `Crc_g`) | PT-CR-01 |
| `test_ecc_single` (TC-PT-08) | Single data-bit errors injected into the buffer and into the descriptor FIFO during traffic: every packet byte-exact, `Ecc_Sec` bit 0 and bit 1 pulse once per error, `Ecc_Ded` stays 0 | PT-BF-01, PT-BF-02, PT-BF-03 |
| `test_ecc_double` (TC-PT-09) | Double data-bit error in the buffer: `Ecc_Ded(0)` pulses, the packet leaves with exactly the two data bits flipped, complete and correctly framed, and with `Crc_g` its CRC is that of the original segment; double error in a descriptor: `Ecc_Ded(1)` pulses, the packet leaves with the corrupted length and the beats of its segment; the packets after both errors are byte-exact | PT-BF-02, PT-BF-03 |
| `test_reset` (TC-PT-10) | Reset with segments in the buffer, a held beat and a packet half output: afterwards no stale beat leaves, the first packet carries count 0 and all further packets are byte-exact | PT-IF-03 |
| `test_throughput` (TC-PT-11) | 20 data units of three full segments back to back, output always ready: one output beat per cycle within a packet and at most 3 cycles between packets; with `BufferBytes_g` of two segments the input stalls per segment at most the extra output beats of its packet plus 3 cycles (measured and reported in the other configurations) | PT-PF-01, PT-PF-02 |
| `test_core_packet_service` (TC-PT-12) | Integration: data units through the packetizer, a send port and a receive port of the Packet Service of `spp_core` and the link loop: every Space Packet arrives intact with its Sequence Flags, count, secondary header and CRC | PT-IF-02, PT-SG-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PT-IF-01 | TC-PT-01 |
| PT-IF-02 | TC-PT-01, TC-PT-12 |
| PT-IF-03 | TC-PT-10 |
| PT-IF-04 | TC-PT-04 |
| PT-SG-01 | TC-PT-01 |
| PT-SG-02 | TC-PT-01, TC-PT-04, TC-PT-12 |
| PT-SG-03 | TC-PT-03 |
| PT-SG-04 | TC-PT-04, TC-PT-05 |
| PT-SG-05 | TC-PT-01 |
| PT-HD-01 | TC-PT-01, TC-PT-06 |
| PT-HD-02 | TC-PT-02 |
| PT-HD-03 | TC-PT-01 |
| PT-HD-04 | TC-PT-06 |
| PT-SH-01 | TC-PT-01, TC-PT-06 |
| PT-SH-02 | TC-PT-01 |
| PT-CR-01 | TC-PT-01, TC-PT-07 |
| PT-CR-02 | TC-PT-01 |
| PT-BF-01 | TC-PT-01, TC-PT-08 |
| PT-BF-02 | TC-PT-08, TC-PT-09 |
| PT-BF-03 | TC-PT-08, TC-PT-09 |
| PT-PF-01 | TC-PT-11 |
| PT-PF-02 | TC-PT-11 |

## 5. Negative tests and mutations

Each check of the packetizer has a test that fails when the check is removed. The verification report lists the
mutations of the RTL (applied outside the repository history and reverted) and the test that caught each one:

| Function | Mutation | Expected failing test |
| --- | --- | --- |
| Sequence Flags | Last segment flagged '00' | TC-PT-01 |
| Count wrap | The count stops at 16383 | TC-PT-02 |
| Aborted data unit | Its last beat does not end the data unit | TC-PT-03 |
| Aborted event | `Aborted` not raised for a last beat without byte enables | TC-PT-03 |
| Held segment | A full segment is written without waiting for the next beat | TC-PT-04, TC-PT-05 |
| Header sampling | APID of the cycle before the sampling edge | TC-PT-06 |
| CRC | Initial value 0 instead of all ones | TC-PT-07 |
| ECC single error | `Ecc_Sec(0)` not raised | TC-PT-08 |
| ECC double error | `Ecc_Ded(1)` not raised | TC-PT-09 |
| ECC injection | No data bit flipped in the buffer | TC-PT-08, TC-PT-09 |
| Reset | The count is not reset | TC-PT-10 |
