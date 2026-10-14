# spp_nchar: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 1 "*spp_nchar*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_nchar_tb` | 5 test cases in 16 configurations (link widths 8 to 128 bits in steps of 8): 80 | 80 |

| Generic | Declared range | Simulated | Synthesized |
| --- | --- | --- | --- |
| `DataWidth_g` | 8 to 128, multiple of 8 | every value | 8, 128; 12 stops with the assertion |

Rate (TC-AD-03): the transmit direction output the 1731 characters of 50 packets in 1780 cycles at 128 bits, 1751 in
1800 at 24 bits, 1750 in 1799 at 32 bits (one cycle between two packets) and 1638 in 1638 at 8 bits; the link output
of the receive direction needed no more cycles than characters at every width.

The core tests TC-CO-01, TC-CO-03 and TC-CO-05 pass with both links through two adapters (configuration `nchar_w32`).

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `lint/synth_check.py` synthesizes `spp_nchar` at 8 and 128 bits without latches, and a
width of 12 bits stops with the message of the assertion.

Findings:

| Finding | Resolution |
| --- | --- |
| At 8 bits `olo_base_wconv_n2xn` is a direct connection, so the last beat left the converter in the cycle in which the EEP flag was stored, without the flag | At 8 bits the flag is taken from the marker in the same cycle |
| A link packet that ended with a beat without byte enables blocked the transmit direction: `olo_base_wconv_xn2n` drops `In_Last` of a beat without word enables, so the marker never followed | The beat bypasses the converter and the marker follows once the converter is empty; a link packet without any byte sends nothing (AD-TX-02, D15, TC-AD-05) |
