# spp_pkg: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_pkg*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_pkg_tb` | 4 | 4 |

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings.

Findings:

| Finding | Resolution |
| --- | --- |
| GHDL 6.0.0 (mcode) aborts the elaboration when a protected type stores access values of the UVVM type `t_byte_array` | The testbenches use their own byte array type `TbBytes_t` |
| The UVVM AXI4-Stream VVC limits a packet to 16 KiB and `TUser` to 32 bits, below the Space Packet length of 65542 octets | The stream source and sink models of `tb/` replace the VVC |
