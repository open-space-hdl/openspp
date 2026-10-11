# spp_nchar: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_nchar*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_nchar_tb` | 4 test cases in 4 configurations (link widths 8, 24, 32, 128 bits): 16 | 16 |

The core tests TC-CO-01, TC-CO-03 and TC-CO-05 pass with both links through two adapters (configuration `nchar_w32`).

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `ghdl --synth` elaborates `spp_nchar` at 8, 32 and 128 bits without latches.

Findings:

| Finding | Resolution |
| --- | --- |
| At 8 bits `olo_base_wconv_n2xn` is a direct connection, so the last beat left the converter in the cycle in which the EEP flag was stored, without the flag | At 8 bits the flag is taken from the marker in the same cycle |
