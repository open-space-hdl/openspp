# spp_core: Verification Report

## 1. Test results

Run on 2026-11-04 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 2`, the full
regression of OpenSPP (668 runs, all passed, none skipped).

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_core_tb` | 22 test cases in 155 runs (configurations of the verification plan) | 155 |

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

`python lint/synth_check.py` (last run on 2026-11-04, with the link output stage) synthesizes `spp_core` with GHDL in
eleven configurations (default; without the CPTP
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

QuestaSim (Questa Sim Microchip Edition 2024.3), on 2026-10-15: test cases TC-CO-01 to TC-CO-14 pass in the
regression without code coverage (`python run.py --questa -p 1`) and with it (`python run.py --questa --coverage -p 1`);
the coverage is in [docs/coverage.md](../../../docs/coverage.md). The tests of the resets (TC-CO-15 to TC-CO-22 and the
extension of TC-CO-09) and the link output stage have run in GHDL; their QuestaSim runs with and without code coverage
follow with the release 0.2.0.

### 1.1 Resets

The link output monitor checks in every cycle of every test the AXI4-Stream rules on both link outputs and, at every
reset, the behaviour of the link output stage cycle by cycle (EEP beat format and cycle, no beat after the end of the
packet before the release, no beat after an edge with `Rst`); the reset probes check the ports of a core in every
cycle of every reset, including the reset at the start of each test. Results of the reset tests:

| Test case | Result |
| --- | --- |
| TC-CO-09 | `Rst` of A with three beats of a packet of B taken: `S_Link_Ready` '1' with the CPTP layer, '0' without it; after the release A discards the rest once (0x11, 0x15) and delivers the next SDU of B |
| TC-CO-15 | One EEP beat in the cycle after the reset edge at the first, second and second-to-last beat, with the destination index of the packet (3); B discards each packet (0x10) and indicates the restarted counts; through the N-Char adapters the beat of the reset edge is pending (the adapter takes a beat every fourth cycle at 32 bits) and the EEP beat follows its transfer |
| TC-CO-16 | No EEP beat without an open packet, at the transfer of a last beat and with a packet waiting back-to-back; the waiting packet is not sent |
| TC-CO-17 | Pending middle and first beats held unchanged during the stall, then the EEP beat at once; a pending last beat ends its packet without EEP beat; with the stall beyond the release and the table initialisation, the new SDUs follow the EEP beat |
| TC-CO-18 | One EEP beat during 5000 cycles of `DpRst`; a second reset edge while the EEP beat is pending gives no second one |
| TC-CO-19 | After one and after 16 cycles of `DpRst`: `TABLE_STATUS` reads 0x3 after the release and 0x0 2063 cycles later, every register reads its reset value, the written table entries read the initial entries |
| TC-CO-20 | Seven orders of `Rst` and `DpRst`: no EEP beat after `Rst` (a pending EEP beat is withdrawn), `TX_BUSY` set after the later release; the eight bins of `RESET_ORDER` |
| TC-CO-21 | Every send port mid-SDU (1, 3 and 16 ports), a complete SDU waiting and a receive port delivering: the ports in reset as specified, the delivered SDU ends without its last beat, B delivers exactly the SDUs taken after the release |
| TC-CO-22 | Traffic in both directions: B discards the EEP packet of A, A discards the rest of the packet of B once, B indicates the restarted counts of A, every later SDU is delivered |

Coverpoints (verification plan, section 6), reached as follows:

| Coverpoint | Bins and the tests that reach them |
| --- | --- |
| `DPRST_POINT` | no packet open: TC-CO-16; first, middle beat transferred at the reset edge: TC-CO-15; last beat transferred: TC-CO-16; first, middle, last beat pending: TC-CO-17 (first and middle also TC-CO-15 through the N-Char adapters); open with no beat presented: not reached, the blocks in front of the stage deliver a packet without gaps |
| `DPRST_LINK` | no beat pending: TC-CO-15; a beat pending: TC-CO-17; end of the packet after the release: TC-CO-17 (d) |
| `DPRST_LENGTH` | 1 cycle: TC-CO-15, TC-CO-19; 2 to 16: TC-CO-18, TC-CO-19; 17 to 2048: TC-CO-17 (30 cycles); more than 2048: TC-CO-18 |
| `RESET_ORDER` | all eight bins: TC-CO-20 |
| `RESET_SLINK` | idle: the reset at the start of every test; inside a packet: TC-CO-09, TC-CO-22 |

Mutations (`spp_link_output`, reset wiring of `spp_core`), each applied alone to the committed sources and run with its
tests in GHDL; a run without a result would count as not caught:

| ID | Mutation | Failing tests |
| --- | --- | --- |
| M1 | Link output stage reset by `Rst` or `DpRst` | TC-CO-15, TC-CO-17 |
| M2 | `End_s` never loads the EEP beat | TC-CO-15 |
| M3 | EEP beat with `User(0)` '0' | TC-CO-15 |
| M4 | EEP beat with `Last` '0' | TC-CO-15 |
| M5 | EEP beat without a valid byte | TC-CO-15 |
| M6 | EEP beat with destination index 0 | TC-CO-15 (`plain_w64`) |
| M7 | EEP beat also when no packet is open | TC-CO-16 |
| M8 | `PktOpen` not cleared by a transferred last beat | TC-CO-16, TC-CO-17 |
| M9 | Pending beat replaced by the EEP beat at the reset edge | TC-CO-17 |
| M10 | `OValid` cleared by `DpRst` | TC-CO-17 |
| M11 | `S_Pkt_Ready` not gated with `DpRst` | TC-CO-15 |
| M12 | `End_s` left at the release with the end of the packet pending | TC-CO-17 |
| M13 | `Rst` without precedence | TC-CO-20 |
| M14 | `spp_mib` reset by `Rst` only | TC-CO-19 |
| M15 | `spp_send` reset by `Rst` only | TC-CO-19, TC-CO-21, TC-CO-22 |
| M16 | `spp_receive` and `spp_decapsulation` reset by `Rst` only | TC-CO-19, TC-CO-22 |
| M17 | `spp_encapsulation` reset by `Rst` only | TC-CO-15 |

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
| The reset probe failed at the start of every test: in the cycle that ends with the release edge the ready of a send port was '1' | The ready of an Open Logic FIFO input follows the level of its reset; CO-RS-09 to CO-RS-11 specify the ports from the cycle after the reset edge as long as a reset input is '1', and the probe checks exactly these cycles |
| Mutation M6 (EEP beat with destination index 0) was not caught: the link output monitor took the destination of the EEP beat itself as its reference | The monitor compares the EEP beat with the destination of the packet before the transfer of the cycle; M6 fails TC-CO-15 |
| TC-CO-21 waited for the first delivered byte with `wait until` on a function of the packet store, a shared variable: the wait never resumed and the SDU of B was delivered completely before the reset | The test polls the packet store once per cycle |
| Through the N-Char adapters a reset edge at the presentation of a beat finds it pending, at the CPTP widths it is transferred at once | TC-CO-15 and TC-CO-16 check the position of the beat (first, middle, last) whether it is transferred or pending; the monitor checks the EEP beat in both cases |
