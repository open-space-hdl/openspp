# spp_packetizer: Verification Report

## 1. Test results

Run on 2026-10-21 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 2 "*spp_packetizer*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_packetizer_tb` | 11 test cases in 24 configurations (verification plan, section 2): 264 | 264 |
| `spp_packetizer_core_tb` | 1 test case (integration with `spp_core`) | 1 |

All 265 runs passed, 0 skipped.

| Generic | Declared range | Simulated | Synthesized |
| --- | --- | --- | --- |
| `DataWidth_g` | 8 to 128, multiple of 8 | every value | 8, 24, 32, 128; 12 stops with the assertion |
| `ChunkBytes_g` | multiple of the beat, at most 65536 less `SecHdrBytes_g` and less 2 with `Crc_g` | one beat (4 bytes at 32 bits), 8 beats at every width, 32, 4096 | 1 (one beat at 8 bits), 48, 4096, 65536; 6 at 32 bits and 65536 with the CRC stop with the assertion |
| `BufferBytes_g` | beat times a power of two, at least `ChunkBytes_g` | one segment (`buf1`), two segments | 1, 96, 8192, 65536; 96 at 32 bits (24 beats) and 2048 below a segment of 4096 stop with the assertion |
| `MaxChunks_g` | 2 to 64 | 2, 8 | 2, 8, 64; 1 and 65 stop with the assertion |
| `SecHdrBytes_g` | 0 to 64 | 0, 1, 3, 64 | 0, 7, 64; 65 stops with the assertion |
| `Crc_g` | boolean | false, true | false, true |

Rate (TC-PT-11, 60 full segments back to back, output always ready):

| Configuration | Largest gap between packets | Cycles without data inside a packet | Input stall cycles (limit of PT-PF-02) |
| --- | --- | --- | --- |
| `w8` | 0 | 0 | 641 (840) |
| `w16` | 0 | 0 | 351 (540) |
| `w24` | 1 | 0 | 293 (420) |
| `w32` | 1 | 0 | 235 (360) |
| `w40` | 0 | 0 | 177 (360) |
| `w48` to `w72` | 1 | 0 | 177 (300) |
| `w80` | 1 | 0 | 147 (300) |
| `w88` to `w128` | 2 | 0 | 147 (240) |
| `plain`, `crc`, `sh1` | 1 | 0 | 177 (300) |
| `sh64` | 1 | 0 | 1105 (1260) |
| `mc2` | 1 | 0 | 235 (360) |
| `beat1` | 1 | 0 | 231 (360) |
| `w128_4k` | 2 | 0 | 147 (240) |
| `buf1` (one segment of buffer, not covered by PT-PF-02) | 12 | 0 | 885 |

In the configuration of the reference system (`w128_4k`, segments of 4096 bytes at 128 bits) the input accepted the
256 beats of a segment with 2.45 stall cycles per segment on average, 99 % of the beat rate. With a buffer of one
segment (`buf1`) the input waits while every packet leaves, as documented for `BufferBytes_g`.

The integration test TC-PT-12 sends 30 data units of 1 to 256 bytes through the packetizer, a send port and a receive
port of the Packet Service of `spp_core` with the CPTP layer and the link looped back: all 78 Space Packets arrive
intact with their Sequence Flags, counts, secondary header and CRC; the core reports no error event.

QuestaSim: the module enters the QuestaSim regression (with and without code coverage) of the next OpenSPP release;
the results and the coverage will be in [docs/coverage.md](../../../docs/coverage.md).

## 2. Negative tests and mutations

| Check | Negative test |
| --- | --- |
| Single error in the buffer and in the descriptors corrected and reported | TC-PT-08 (data-bit injection, before and during traffic) |
| Double error in the buffer and in a descriptor reported, packet sent with the bytes as read | TC-PT-09 |
| Aborted data unit closed and reported | TC-PT-03 |
| Header fields of the sampling edge | TC-PT-06 (fields change in every cycle) |
| CRC values | TC-PT-07 (ECSS-E-ST-70-41C Table B-2) |

Every mutation of the verification plan (section 5) was applied to the RTL outside the history of the repository,
run in the configuration `w32` with the tests named for it, and reverted:

| Function | Mutation | Failing tests | Result |
| --- | --- | --- | --- |
| Sequence Flags | Last segment flagged '00' | TC-PT-01 | Caught |
| Count wrap | The count stops at 16383 | TC-PT-02 | Caught |
| Aborted data unit | Its last beat does not end the data unit | TC-PT-03 | Caught |
| Aborted event | `Aborted` not raised for a last beat without byte enables | TC-PT-03 | Caught |
| Held segment | A full segment is written without waiting for the next beat | TC-PT-04, TC-PT-05 | Caught |
| Header sampling | APID of the cycle before the sampling edge | TC-PT-06 | Caught |
| CRC | Initial value 0 instead of all ones | TC-PT-07 | Caught |
| ECC single error | `Ecc_Sec(0)` not raised | TC-PT-08 | Caught |
| ECC double error | `Ecc_Ded(1)` not raised | TC-PT-09 | Caught |
| ECC injection | No data bit flipped in the buffer | TC-PT-08, TC-PT-09 | Caught |
| Reset | The count is not reset | TC-PT-10 | Caught |

Run on 2026-10-21 with GHDL in the configuration `w32`; a mutation counts as caught only when a test of the
mutated design fails, not when it fails to compile.

## 3. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `lint/synth_check.py` synthesizes `spp_packetizer` at the bounds of its ranges without latches,
and every value outside them stops with the message of its assertion.

Findings:

| Finding | Resolution |
| --- | --- |
| A beat before a last beat without byte enables can be partial; the segmenter counted it as a full beat | The byte count of every beat follows from its byte enables (TC-PT-04) |
| `olo_base_crc` evaluates `In_Last` and `In_Be` in every clock cycle, also without `In_Valid`; with `In_Last` = '1' and no byte enable the simulation stops with a bound check failure (segments of one beat) | The segmenter drives `In_Last` and `In_Be` of the CRC only together with a write; reported as an Open Logic defect |
| GHDL checks the constant slice bounds of a process also in a branch that is never executed, so the CRC field of the descriptor could not be read without `Crc_g` | The packet control reads the descriptor in the full layout of `spp_pkg`, the CRC bits zero without `Crc_g` |
| `MaxChunks_g` = 1 stopped at the range of `MaxPackets_g` of `olo_ft_fifo_packet` before the own assertion | The value passed to Open Logic is at least 2, so the own assertion names the bound |
