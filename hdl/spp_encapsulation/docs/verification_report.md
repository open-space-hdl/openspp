# spp_encapsulation: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20:
`python run.py -p 4 "*spp_encapsulation*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_encapsulation_tb` | 5 test cases in 4 configurations (stream widths 8, 24, 64, 128 bits): 20 | 20 |

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `ghdl --synth` elaborates both entities without latches.

Findings:

| Finding | Resolution |
| --- | --- |
| Review before the first run: a discarded packet of a single beat would not have been reported, because the forwarding branch overwrote the drop state | Decision of the forwarding branch limited to forwarded beats; TC-EN-03 discards single-beat packets |
| Code coverage: the limit of the address length to `SpwAddrBytes_g` (EN-TX-02) was not exercised | TC-EN-01 extended (address length 20 at `SpwAddrBytes_g` 16) |
