# spp_header: Verification Plan

## 1. Overview

Both stages are driven by the stream source model and checked by the stream sink model of `tb/`: every output packet
is compared byte by byte with the packet the testbench builds (header followed by the packet, or the packet without
its first bytes), together with `User`, the removed bytes and the empty flag on every beat. The byte enables of every
output beat are checked by the sink (all set except in the last beat, contiguous).

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_header_tb` | `spp_header_th` | `spp_header_insert` and `spp_header_remove` (`MaxHeaderBytes_g` = `MaxRemoveBytes_g` = 20, `UserWidth_g` 4) at 100 MHz, a stream source and a stream sink on each; header, header length and removal count travel in `TUser` of the sources |

VUnit configurations `w8`, `w16`, `w24`, `w32`, `w64`, `w128` run every test with `DataWidth_g` of 8 to 128 bits.
Simulator: GHDL; QuestaSim for code coverage.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_insert` (TC-CM-01) | Every header length from 0 to 20 bytes with packet lengths of 1, 2, B-1, B, B+1, 2B+3, 3B and 41 bytes, 30 % random stall cycles on input and output | CM-IF-01, CM-IF-02, CM-IN-01 |
| `test_remove` (TC-CM-02) | Every removal count from 0 to 20 bytes with packet lengths from 1 byte up to 2B+2 bytes beyond the removed ones, including packets shorter than and as long as the removal (empty packets), 30 % random stall cycles | CM-IF-01, CM-IF-02, CM-RM-01, CM-RM-02 |
| `test_random` (TC-CM-03) | 400 packets through each stage with random lengths (1 to 300 bytes), header lengths and removal counts (0 to 20), random `User` and random stall probabilities up to 60 %, both stages at the same time | CM-IF-01, CM-IF-02, CM-IN-01, CM-RM-01, CM-RM-02 |
| `test_line_rate` (TC-CM-04) | 50 back-to-back packets of 64 to 113 bytes with headers of 6 to 15 bytes without stall cycles: the insertion outputs one beat per cycle from the first to the last beat; the removal needs at most one cycle more per packet than input beats | CM-IN-02, CM-RM-03 |
| `test_reset` (TC-CM-05) | Reset while both stages hold a packet that the sink does not accept; afterwards 20 random packets through each stage are correct | CM-IF-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CM-IF-01, CM-IF-02 | TC-CM-01, TC-CM-02, TC-CM-03 |
| CM-IF-03 | TC-CM-05 |
| CM-IN-01 | TC-CM-01, TC-CM-03 |
| CM-IN-02 | TC-CM-04 |
| CM-RM-01 | TC-CM-02, TC-CM-03 |
| CM-RM-02 | TC-CM-02, TC-CM-03 |
| CM-RM-03 | TC-CM-04 |
