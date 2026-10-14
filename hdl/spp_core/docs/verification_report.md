# spp_core: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 2 "*spp_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_core_tb` | 11 test cases in 28 configurations | 28 |

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
| A system with the core and `spp_nchar` behind a SpaceWire port logged about 27000 numeric_std metavalue warnings in 100 us: from the end of the table initialisation until the first received packet the demultiplexer and the packet assembly evaluated undefined registers; single warnings came from the header removal and insertion | The registers are reset (D16); TC-CO-11 runs idle cores with the IEEE warnings enabled and fails on any metavalue warning after the table initialisation |
| The simulator options of `run.py` were applied after the module configurations and overrode their settings | `run.py` applies them first |
| The post check of TC-CO-11 only looked for the absence of metavalue warnings: with the IEEE warnings disabled (as with the earlier order of the simulator options) the test passed without checking anything | Positive control: the testbench raises one numeric_std warning itself before the marker and the post check requires it; with `disable_ieee_warnings` set to true for the test, all three configurations fail in GHDL and in QuestaSim |
