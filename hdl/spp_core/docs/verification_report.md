# spp_core: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 1 "*spp_core*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_core_tb` | 14 test cases in 130 runs (configurations of the verification plan) | 130 |

Line rate (TC-CO-08): 100 Octet Strings of 1024 bytes reached the receive port of B in 25897 cycles for 25900 link
beats at 32 bits (the link is the limit) and in 6598 cycles for 6500 link beats at 128 bits (one cycle per packet).

Throughput (TC-CO-12): every send port took its SDUs at one beat per cycle (7 SDUs of 1024 bytes in 1792 cycles at
32 bits). Cycles per packet in the steady state, from the windows of 12 sent and 16 received packets:

| Packets | 32 bits CPTP: `N`, `M_Link`, `M_Rx` | 64 bits without CPTP | 128 bits CPTP |
| --- | --- | --- | --- |
| Octet Strings of 1 byte | 3, 5, 5 | 1, 5, 5 | 1, 5, 5 |
| Octet Strings of 61 bytes | 18, 19, 18 | 9, 9, 10 | 5, 5, 6 |
| Octet Strings of 61 bytes, four address bytes | 19, 20, - | - | 5, 5, - |
| Octet Strings of 256 bytes | 67, 67, 67 | 33, 33, 34 | 17, 17, 18 |
| Octet Strings of 1024 bytes | 259, 259, 259 | 129, 129, 130 | 65, 65, 66 |
| Space Packets of 7 bytes (Packet Service) | 3, 5, 5 | 1, 5, 5 | 1, 5, 5 |
| Space Packets of 67 bytes (Packet Service) | 18, 19, 18 | 9, 10, 10 | 5, 6, 6 |
| Space Packets of 262 bytes (Packet Service) | 67, 68, 67 | 33, 34, 34 | 17, 18, 18 |
| Space Packets of 1030 bytes (Packet Service) | 259, 260, 259 | 129, 130, 130 | 65, 66, 66 |
| Two ports alternating, Octet Strings of 61 bytes | 18, 19, - | 9, 9, - | 5, 6 (receiving end), - |

`M_Rx` is measured with Space Packets of the same length injected into B (the `M_Rx` column of an Octet String row is
the Space Packet of that Octet String delivered at an Octet String port). Every value equals the model of the user
guide (section 7): max(`N` + `e`, 5) at the sending end and max(ceil(`Lsp` / B) + 1, 5) at the receiving end.

`python lint/synth_check.py` synthesizes `spp_core` with GHDL in eleven configurations (default; without the CPTP
layer; without address bytes and default paths; three ports of both services at 128 bits with four destinations;
16 ports, 16 destinations and 16 address bytes at 8 bits; `MaxLength_g` 7, `RoundRobin_g` '1' and `Tla_g` 0x20;
buffers of 8 beats at 8 bits; buffers of 262144 beats at 8 bits and of 16384 beats at 128 bits with two packets;
buffers of 16 beats at 32 bits with 16 and 8 packets; buffers of 8192 beats at 8 bits with 8192 and 1170 packets)
without errors and without latches. Outside the bounds the
synthesis stops with the message of the bound: a send buffer of 4 bytes at 8 bits (CO-GN-02), buffers of 524288
beats at 8 bits with two packets (CO-GN-03), one packet in a send buffer and 9 packets in a receive buffer of 16 beats
at 32 bits (CO-GN-04).

Generic ranges: every value of a generic that changes the structure is simulated, the bounds of the other ranges are
elaborated and synthesized (configurations in the verification plan, section 2).

| Generic | Declared range | Simulated | Synthesized |
| --- | --- | --- | --- |
| `DataWidth_g` | 8 to 128, multiple of 8 | every value | 8, 32, 128 |
| `NumTx_g` | 1 to 16 | every value | 1, 3, 16 |
| `NumRx_g` | 1 to 16 | every value | 1, 3, 16 |
| `NumDest_g` | 1 to 16 | every value | 1, 4, 16 |
| `SpwAddrBytes_g` | 0 to 16 | every value | 0, 4, 16 |
| `Encapsulation_g` | boolean | true, false | true, false |
| `TxOctetString_g`, `RxOctetString_g` | one bit per port | '1' and '0' (port 1 Packet Service) | all '1', port 1 '0' |
| `TxPathDefault_g`, `RxPathDefault_g` | boolean | true, false | true, false |
| `TxBufferBytes_g`, `RxBufferBytes_g` | CO-GN-02, CO-GN-03; at most 2^29 beats | 8 beats at 8 bits (minimum), 16, 1024, 4096 and 8192 beats, 262144 beats at 8 bits with two packets (maximum) | 8 beats at 8 bits, 16, 1024, 4096, 8192 beats, 262144 beats at 8 bits and 16384 beats at 128 bits with two packets; 2^29 beats asserted, not elaborated (memory of a simulation host) |
| `TxMaxPackets_g` | CO-GN-04 | 2, 5, 8, 16, 8192 (maxima of 16 and 8192 beats) | 2, 8, 16, 8192 |
| `RxMaxPackets_g` | CO-GN-04 | 2, 5, 8, 1170 (maxima of 16 beats at 32 bits and 8192 beats at 8 bits) | 2, 8, 1170 |
| `MaxLength_g` | 7 to 65542 | 7, 65542 | 7, 65542 |
| `RoundRobin_g` | '0', '1' | '0', '1' | '0', '1' |
| `Tla_g` | 8 bits | 0xFE, 0x20 | 0xFE, 0x20 |
| `ClkFreqHz_g` | real, no effect | 100.0e6 | 100.0e6 |

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered and every seam of the integration is crossed
by a test (see the verification plan).

Findings:

| Finding | Resolution |
| --- | --- |
| Most values of the structure generics had never run at core level (three ports, four destinations, four address bytes, widths 32, 64 and 128); `spp_nchar` was not synthesized by `lint/synth_check.py`; the buffer generics had no declared bounds | Every value of `DataWidth_g`, `NumTx_g`, `NumRx_g`, `NumDest_g` and `SpwAddrBytes_g` runs in a configuration of its own, the bounds of the buffer generics are derived from the design and asserted (CO-GN-01 to CO-GN-04); all pass without a change of the data path |
| One packet per buffer stopped the elaboration with a range error inside Open Logic before the assertion of the core could report the bound | The buffers get at least two packets, so that the assertion of CO-GN-04 reports the value |
| The error event output reports one event per cycle (the lowest source index); simultaneous events at 128 bits are all counted, but only one appears on the output | Behaviour as specified (MG-IF-03); the tests check the counters exactly |
| GHDL synthesis aborted on index ranges of packed port vectors selected by a variable port number | Port selection written as loops over the ports (`spp_send_assembly`) |
| Under QuestaSim four core tests failed with stimulus and expected packets of different lengths: a random length drawn by an impure call inside the actual of an unconstrained array parameter was not evaluated exactly once | The lengths are drawn into a variable before the call; rule added to [conventions.md](../../../docs/conventions.md) |
| Code coverage: CO-IF-03 with `TxPathDefault_g` and `RxPathDefault_g` false, and a core without Target SpaceWire Address bytes, were never simulated | New test TC-CO-10 with the configuration `nopath_w32`; `lint/synth_check.py` synthesizes the configuration |
| A system with the core and `spp_nchar` behind a SpaceWire port logged about 27000 numeric_std metavalue warnings in 100 us: from the end of the table initialisation until the first received packet the demultiplexer and the packet assembly evaluated undefined registers; single warnings came from the header removal and insertion | The registers are reset (D16); TC-CO-11 runs idle cores with the IEEE warnings enabled and fails on any metavalue warning after the table initialisation |
| The simulator options of `run.py` were applied after the module configurations and overrode their settings | `run.py` applies them first |
| VUnit 5.0.0.dev7 appended the generics of every GHDL simulation to one `ghdl.sim_flags` list shared by all configurations, and GHDL applies the last value of a generic: a test inherited every generic it does not set from the tests started before it (a configuration `cptp_w32` started after `nchar_w32` ran with `NChar_g` true). GHDL results before the fix may have run with foreign generics; the QuestaSim results were not affected | `run.py` gives every simulation its own copy of the flags and stops when a GHDL command carries other generics than those of its configuration (docs/conventions.md); the GHDL regression was repeated with the fix |
| The user guide stated that the sending end adds no cycle per packet. TC-CO-12 measured one cycle per packet for Space Packets of the Packet Service and for Octet Strings whose header insertions end without an extra beat (61 bytes at 32 bits: 19 cycles for 18 link beats) | User guide corrected; section 7 gives the cycles per packet with the condition, TC-CO-12 checks the bound max(`N` + 1, 5) |
| The post check of TC-CO-11 only looked for the absence of metavalue warnings: with the IEEE warnings disabled (as with the earlier order of the simulator options) the test passed without checking anything | Positive control: the testbench raises one numeric_std warning itself before the marker and the post check requires it; with `disable_ieee_warnings` set to true for the test, all three configurations fail in GHDL and in QuestaSim |
