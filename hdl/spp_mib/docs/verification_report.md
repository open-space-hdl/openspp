# spp_mib: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_mib*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_mib_tb` | 7 | 7 |

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `ghdl --synth` elaborates `spp_mib` without latches. The register map is in sync with its
description (`python tools/regmap.py --check`).

Findings:

| Finding | Resolution |
| --- | --- |
| A table access requested during the initialisation of the table was rejected as an overrun | Requests are accepted during the initialisation and start after it; only a request while the previous one is pending is an overrun (TC-MG-04) |
| Code coverage: RX_TABLE_APID was never read, TABLE_STATUS never written with one overrun bit only, and RX_TABLE_ENTRY never read while the receive table was busy | TC-MG-04 extended; the harness has a holding client on both tables |
| Code coverage: a guard on the generic `SpwAddrBytes_g` in the access to the address bytes was constant per instance | Replaced by the loop bound `SpwAddrBytes_g - 1`, same behaviour; `nopath_w32` of the core tests reads DEST_ADDR0 without address bytes |
