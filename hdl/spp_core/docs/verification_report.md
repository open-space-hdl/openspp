# spp_core: Verification Report

## 1. Test results

Run on 2026-10-10 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 4 "*spp_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_core_tb` | 10 test cases in 25 configurations | 25 |

Line rate (TC-CO-08): 100 Octet Strings of 1024 bytes reached the receive port of B in 25897 cycles for 25900 link
beats at 32 bits (the link is the limit) and in 6598 cycles for 6500 link beats at 128 bits (one cycle per packet).

`python lint/synth_check.py` synthesizes `spp_core` with GHDL in five configurations (default; without the CPTP
layer; without address bytes and default paths; three ports of both services at 128 bits with four destinations;
16 ports, 16 destinations and 16 address bytes at 8 bits) without errors and without latches.

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered and every seam of the integration is crossed
by a test (see the verification plan).

Findings:

| Finding | Resolution |
| --- | --- |
| The error event output reports one event per cycle (the lowest source index); simultaneous events at 128 bits are all counted, but only one appears on the output | Behaviour as specified (MG-IF-03); the tests check the counters exactly |
| GHDL synthesis aborted on index ranges of packed port vectors selected by a variable port number | Port selection written as loops over the ports (`spp_send_assembly`) |
| Under QuestaSim four core tests failed with stimulus and expected packets of different lengths: a random length drawn by an impure call inside the actual of an unconstrained array parameter was not evaluated exactly once | The lengths are drawn into a variable before the call; rule added to [conventions.md](../../../docs/conventions.md) |
| Code coverage: CO-IF-03 with `TxPathDefault_g` and `RxPathDefault_g` false, and a core without Target SpaceWire Address bytes, were never simulated | New test TC-CO-10 with the configuration `nopath_w32`; `lint/synth_check.py` synthesizes the configuration |
