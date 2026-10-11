# spp_receive: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_receive*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_receive_tb` | 10 test cases in 17 configurations | 17 |

Line rate (TC-RE-07): 100 packets of 262 bytes left the port in 6697 cycles for 6600 received beats at 32 bits and in
1798 cycles for 1700 received beats at 128 bits: one cycle per packet (the read stall of the packet FIFO).

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `ghdl --synth` elaborates `spp_receive` without latches.

Findings:

| Finding | Resolution |
| --- | --- |
| The length check computed PDL + 7 in 16 bits, so a packet of the maximum length (PDL 65535) failed it; the same in the send buffer for the Packet Service | 17-bit arithmetic in both buffers; TC-RE-06 and a Packet Service case of TC-SE-07 cover the maximum length |
| The error flag of an Octet String appeared also on the beat before the last when the header removal needed a flush beat | The flag is masked to the last beat |
| Code coverage: the saturation of the byte count, a double error in the last word of a packet without an earlier one and a buffer full of packets while the port stalls were not exercised | TC-RE-06 (a packet whose PDL matches a wrapped count), TC-RE-08 (new configuration at 64 bits) and TC-RE-01 extended |
