# spp_apid_table: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_apid_table*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_apid_table_tb` | 5 | 5 |

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| The scrubber could read the not yet initialised RAM during the initialisation | The scrubber is suspended while `Init_Busy` is set |
| Code coverage: no reset in the cycle of a read (`Read_s`) | TC-TB-05 extended |
