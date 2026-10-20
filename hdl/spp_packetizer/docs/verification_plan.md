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
| `test_segmentation` (TC-PK-01) | Data units of 1 byte, one beat, a segment less one byte, one segment, one segment plus one byte, two and three segments plus a part, and 40 random lengths up to five segments, random stalls at input and output: every packet byte-exact (flags, count, length, APID, type, Secondary Header Flag, secondary header, data, CRC) and in order | PK-IF-01, PK-IF-02, PK-SG-01, PK-SG-02, PK-SG-05, PK-HD-01, PK-HD-03, PK-SH-01, PK-SH-02, PK-CR-01, PK-CR-02, PK-BF-01 |
| `test_count_wrap` (TC-PK-02) | 16390 data units of one byte without stalls: the counts run from 0 to 16383 and continue with 0 to 5 | PK-HD-02 |
| `test_aborted` (TC-PK-03) | Data units with `S_Error` on the last beat (a data beat and a last beat without byte enables, one and several segments) between normal ones: the packets are those of normal data units, `Aborted` pulses once per aborted data unit and never otherwise; `S_Error` on beats other than the last is ignored | PK-SG-03 |
| `test_null_last` (TC-PK-04) | Data units ending with a last beat without byte enables: after a partial beat, after a full beat inside a segment, directly after a full segment (flags '10' or '11' on that segment) and as the only beat of a data unit (no packet, the count does not change); stalls on both sides | PK-IF-04, PK-SG-02, PK-SG-04 |
| `test_held_segment` (TC-PK-05) | A full segment without `Last` and a pause of 200 cycles at the input: no `Hdr_Sample` and no output during the pause; the next beat releases the packet with '01'; the same with a last beat without byte enables gives '11' | PK-SG-04 |
| `test_header_sample` (TC-PK-06) | `Cfg_Apid`, `Cfg_Type` and `SecHdr_Data` change in every clock cycle: every packet carries the values of the sampling edge of its `Hdr_Sample` cycle; one pulse per packet, in packet order, at least two cycles before the first output beat of the packet | PK-HD-01, PK-HD-04, PK-SH-01 |
| `test_crc_vectors` (TC-PK-07) | The four data blocks of ECSS-E-ST-70-41C Table B-2 as data units: the CRC bytes are 1D 0F, CC 9C, 04 A2 and 7F D5 (configurations with `Crc_g`) | PK-CR-01 |
| `test_ecc_single` (TC-PK-08) | Single data-bit errors injected into the buffer and into the descriptor FIFO during traffic: every packet byte-exact, `Ecc_Sec` bit 0 and bit 1 pulse once per error, `Ecc_Ded` stays 0 | PK-BF-01, PK-BF-02, PK-BF-03 |
| `test_ecc_double` (TC-PK-09) | Double data-bit error in the buffer: `Ecc_Ded(0)` pulses, the packet leaves with exactly the two data bits flipped, complete and correctly framed, and with `Crc_g` its CRC is that of the original segment; double error in a descriptor: `Ecc_Ded(1)` pulses, the packet leaves with the corrupted length and the beats of its segment; the packets after both errors are byte-exact | PK-BF-02, PK-BF-03 |
| `test_reset` (TC-PK-10) | Reset with segments in the buffer, a held beat and a packet half output: afterwards no stale beat leaves, the first packet carries count 0 and all further packets are byte-exact | PK-IF-03 |
| `test_throughput` (TC-PK-11) | 20 data units of three full segments back to back, output always ready: one output beat per cycle within a packet and at most 3 cycles between packets; with `BufferBytes_g` of two segments the input stalls per segment at most the extra output beats of its packet plus 3 cycles (measured and reported in the other configurations) | PK-PF-01, PK-PF-02 |
| `test_core_packet_service` (TC-PK-12) | Integration: data units through the packetizer, a send port and a receive port of the Packet Service of `spp_core` and the link loop: every Space Packet arrives intact with its Sequence Flags, count, secondary header and CRC | PK-IF-02, PK-SG-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PK-IF-01 | TC-PK-01 |
| PK-IF-02 | TC-PK-01, TC-PK-12 |
| PK-IF-03 | TC-PK-10 |
| PK-IF-04 | TC-PK-04 |
| PK-SG-01 | TC-PK-01 |
| PK-SG-02 | TC-PK-01, TC-PK-04, TC-PK-12 |
| PK-SG-03 | TC-PK-03 |
| PK-SG-04 | TC-PK-04, TC-PK-05 |
| PK-SG-05 | TC-PK-01 |
| PK-HD-01 | TC-PK-01, TC-PK-06 |
| PK-HD-02 | TC-PK-02 |
| PK-HD-03 | TC-PK-01 |
| PK-HD-04 | TC-PK-06 |
| PK-SH-01 | TC-PK-01, TC-PK-06 |
| PK-SH-02 | TC-PK-01 |
| PK-CR-01 | TC-PK-01, TC-PK-07 |
| PK-CR-02 | TC-PK-01 |
| PK-BF-01 | TC-PK-01, TC-PK-08 |
| PK-BF-02 | TC-PK-08, TC-PK-09 |
| PK-BF-03 | TC-PK-08, TC-PK-09 |
| PK-PF-01 | TC-PK-11 |
| PK-PF-02 | TC-PK-11 |

## 5. Negative tests and mutations

Each check of the packetizer has a test that fails when the check is removed. The verification report lists the
mutations of the RTL (applied outside the repository history and reverted) and the test that caught each one:

| Function | Mutation | Expected failing test |
| --- | --- | --- |
| Sequence Flags | Last segment flagged '00' | TC-PK-01 |
| Count wrap | Count of 15 bits instead of 14 | TC-PK-02 |
| Aborted data unit | Last segment of an aborted data unit not closed (flag '00') | TC-PK-03 |
| Aborted event | `Aborted` not raised for a last beat without byte enables | TC-PK-03 |
| Held segment | Full segment released without waiting for the next beat | TC-PK-04, TC-PK-05 |
| Header sampling | Header sampled one cycle late | TC-PK-06 |
| CRC | Initial value 0 instead of all ones | TC-PK-07 |
| ECC single error | Uncorrected output of the buffer used | TC-PK-08 |
| ECC events | `Ecc_Ded` not connected | TC-PK-09 |
| Reset | Count not reset | TC-PK-10 |
