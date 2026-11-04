# spp_header: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_header*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_header_tb` | 5 test cases in 6 configurations (stream widths 8, 16, 24, 32, 64, 128 bits): 30 | 30 |

QuestaSim (Questa Sim Microchip Edition 2024.3) at a time resolution of 1 fs, release 0.2.0 on 2026-11-04: the 30 runs
of `spp_header_tb` (5 test cases) pass without code coverage (`python run.py --questa -p 1`) and with it
(`python run.py --questa --coverage -p 1`), in the complete regression of 668 runs; the coverage is in
[docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass for every stream width; every requirement of the specification is covered (see the verification
plan). VSG reports no errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The removal needs one clock cycle more per packet when the residue of the last input beat does not fit into the last output beat (flush beat) | Inherent to a realignment without a second output register; CM-RM-03 states the bound, TC-CM-04 checks it |
| Code coverage: a guard on the header index in the insertion could not be false in its branch | Replaced by the loop bound `minimum(Bytes_c, MaxHeaderBytes_g)`, same behaviour |
