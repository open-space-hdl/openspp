# spp_core: Verification Plan

## 1. Overview

The core tests are the integration tests (phase G) of all modules. Two cores A and B (by default three send and three
receive ports each: ports 0 and 2 to 15 Octet String Service, port 1 Packet Service; four destinations of up to four
address bytes) are connected by link models in both directions. Stream models drive and check all user ports; an
AXI4-Lite VVC configures each core and reads its counters. The link models drop packets, end packets with an EEP or
switch to an injector that sends packets built by the testbench, or remove the leading bytes of every packet as the
routers of a network remove path address bytes. In the configuration `nchar_w32` both links run through two
`spp_nchar` adapters with an 8-bit N-Char stream between them.

Every value of the generics that change the structure of the core runs in a configuration of its own: every stream
width, every port and destination count and every address length (CO-GN-01). The bounds of the buffer generics
(CO-GN-02 to CO-GN-04) run in configurations at their limits; `lint/synth_check.py` synthesizes the core at these
limits and requires that a configuration outside each bound stops with the message of its assertion. The depth limit
of Open Logic (2^29 beats) is asserted but neither elaborated nor synthesized: a buffer of that depth exceeds the
memory of a simulation host.

The resets (CO-RS-01 to CO-RS-11, CO-SY-06) are verified with `Rst` and `DpRst` of each core driven by the testbench
at chosen edges: at a given beat of a packet on `M_Link`, while the link model stalls `M_Link_Ready`, between packets,
in every order of the two inputs, and while packets travel in both directions. A monitor on the link output of each
core checks the AXI4-Stream rules in every test and records every transferred beat with its clock cycle, so a test
compares the beats around a reset edge cycle by cycle.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_core_tb` | `spp_core_th` | Two `spp_core` at 100 MHz, link models `spp_core_tb_link`, stream sources and sinks on all user ports, injectors into both link inputs, AXI4-Lite master VVCs, monitors of `Err_*` and `Irq`, statistics of the link ports and of the send ports (beats and packets with their times), `Rst` and `DpRst` of each core, monitors of the link outputs |

Bench components for the resets:

| Component | Function |
| --- | --- |
| `RstA`, `RstB`, `ResetCtrl` | Reset inputs of the cores: `Rst` and `DpRst` driven by the testbench in whole clock cycles, or by a trigger of the harness in the cycle in which a given beat of a packet is presented on `M_Link` (`DpRst` and `Rst` with their own delay and length), so that a reset edge falls exactly on the transfer of that beat or with that beat pending |
| Link model control `Stall` | Holds `M_Link_Ready` of the sending core at '0' at any beat, also inside a packet, from the cycle in which a given beat is presented, for a given number of cycles; the receiving core sees no beat meanwhile |
| Link output monitor `spp_core_tb_monitor` (one per core) | Checks in every cycle of every test: `M_Link_Valid` stays '1' and `Data`, `Keep`, `Last`, `User` stay unchanged until the transfer (Arm IHI 0051B 2.2.1); `Keep` contiguous from lane 0 and not empty; `User(0)` only with `Last`. Records every transferred beat with its cycle and the cycle of every reset edge, and reports the number of beats transferred of the current packet, so that the testbench applies `DpRst` at a chosen beat |
| Reset probes | Check in every cycle of a reset, from the cycle after the reset edge as long as a reset input is '1', `S_Tx_Ready`, `M_Rx_Valid`, the AXI4-Lite ready and response outputs, `Irq`, `Err_Valid` and `S_Link_Ready` of the core in reset against CO-RS-09 to CO-RS-11 |
| Stream source and sink abort | The source drops the SDU it is sending and the sink the SDU it is receiving when the testbench resets the core (existing `setAbort`) |

| Configuration | Generics |
| --- | --- |
| `cptp_w32`, `cptp_w128` | CPTP layer, `DataWidth_g` 32 or 128 |
| `plain_w64` | Without the CPTP layer, `DataWidth_g` 64 |
| `nchar_w32` | CPTP layer, `DataWidth_g` 32, links through two N-Char adapters each |
| `nopath_w32` | CPTP layer, `DataWidth_g` 32, `TxPathDefault_g` and `RxPathDefault_g` false, `SpwAddrBytes_g` 0 |
| `cptp_w8` to `cptp_w120` | CPTP layer, every `DataWidth_g` not covered above: 8, 16, 24, 40, 48, 56, 72, 80, 88, 96, 104, 112, 120 |
| `ports1_w32` to `ports16_w32` | CPTP layer, `DataWidth_g` 32, `n` send ports, 17 - `n` receive ports and `n` destinations |
| `addr0_w8` to `addr16_w8` | CPTP layer, `SpwAddrBytes_g` 0 to 16 with `DataWidth_g` 8, 16, ... 128, 8 in turn |
| `packets2_w32`, `packets5_w32` | CPTP layer, `DataWidth_g` 32, `TxMaxPackets_g` and `RxMaxPackets_g` 2 or 5 |
| `bufmin_w8` | `DataWidth_g` 8, buffers of 8 beats (CO-GN-02), two packets |
| `bufmax_w8` | `DataWidth_g` 8, buffers of 262144 beats with two packets (CO-GN-03) |
| `pktmax_w32` | `DataWidth_g` 32, buffers of 16 beats, `TxMaxPackets_g` 16 and `RxMaxPackets_g` 8 (CO-GN-04) |
| `pktmax_w8` | `DataWidth_g` 8, buffers of 8192 beats, `TxMaxPackets_g` 8192 and `RxMaxPackets_g` 1170 (CO-GN-04); the written beats of 8192 send packets exceed 2^29 (CO-GN-03) |
| `limits_w32` | `DataWidth_g` 32, `MaxLength_g` 7, `RoundRobin_g` '1', `Tla_g` 0x20 |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_end_to_end` (TC-CO-01) | Five flows in both directions at the same time (A Octet String to B Octet String with continuity check over four APIDs, A Space Packet to B Octet String, A Octet String to B Space Packet, B Octet String to A Octet String, B Space Packet to A Octet String with continuity check), destinations with User Application values, the Target Logical Address filter of B, random stalls; packet counters of both cores; `cptp_w32`, `cptp_w128`, `nchar_w32`, every other width (`cptp_w8` to `cptp_w120`), `packets2_w32`, `packets5_w32` | CO-IF-01, CO-IF-03, CO-SY-01, CO-SY-04, CO-SY-07, CO-GN-01, CO-GN-04 |
| `test_address_strip` (TC-CO-02) | Destination with a Target SpaceWire Address of the maximum length `SpwAddrBytes_g` (bytes 1, 2, 3, ...): B removes up to 15 bytes with RX_STRIP, the link model the remaining byte of 16; `cptp_w32`, `cptp_w128`, `addr0_w8` to `addr16_w8` | CO-SY-02, CO-SY-04, CO-GN-01 |
| `test_link_errors` (TC-CO-03) | Packets injected into B: EEP, version 2, length against PDL, longer than the maximum length 200, Idle Packet, APID without path, segment for an Octet String port, 5 bytes and, with the CPTP layer, Protocol Identifier 1, Reserved 1, Target Logical Address 0x41; then a correct packet; every counter of B, the event flags, the interrupt and the error event output; `cptp_w32`, `cptp_w128`, `plain_w64`, `nchar_w32` | CO-SY-03, CO-SY-04, CO-IF-02 |
| `test_loss` (TC-CO-04) | A packet dropped in the link: the next one has the loss indicator, RX_LOSS and the event flag of B; `cptp_w32`, `cptp_w128`, `plain_w64` | CO-SY-03 |
| `test_eep` (TC-CO-05) | A packet ended with an EEP in the link and a packet with a double error injected into the send buffer of A through its register file: both discarded by B; the ECC status of A; `cptp_w32`, `cptp_w128`, `nchar_w32` | CO-SY-03, CO-SY-04, CO-SY-07 |
| `test_send_errors` (TC-CO-06) | SDUs rejected by A: longer than the maximum length 100, APID without path, Idle Packet with SHI, Space Packet of 6 bytes; counters, error events and interrupt of A | CO-SY-03, CO-SY-04 |
| `test_plain` (TC-CO-07) | Without the CPTP layer: Octet Strings from A to B and Space Packets from B to A, User Application value 0; GENERICS of the core | CO-IF-01, CO-IF-02 |
| `test_line_rate` (TC-CO-08) | 100 Octet Strings of 1024 bytes from A to B back-to-back without stalls | CO-SY-05 |
| `test_reset` (TC-CO-09) | `Rst` of A after five packets with a continuity check at B: B indicates the discontinuity of the restarted counts and keeps delivering. Then `Rst` of A for three cycles after A has taken three beats of an Octet String of 400 bytes 0x55 from B: `S_Link_Ready` of A is '1' during the reset with the CPTP layer and '0' without it; after the release A discards the rest of the packet once with the reason of the first failed check (the payload makes it deterministic: 0x11 with the CPTP layer, 0x15 without) and delivers the next packet of B; `cptp_w32`, `cptp_w128`, `plain_w64` | CO-SY-06, CO-RS-10 |
| `test_default_paths` (TC-CO-10) | Initial entries of an APID in both tables read through the register files; with the default paths an Octet String reaches B without configuration; without them it is rejected by A (no send path), then discarded by B (no receive path) and delivered once both paths are written; without address bytes (`nopath_w32`) a configured address length of 3 is limited to 0 and DEST_ADDR0 reads 0; `cptp_w32`, `cptp_w128`, `nopath_w32` | CO-IF-03, CO-SY-03, CO-SY-04 |
| `test_idle` (TC-CO-11) | IEEE warnings enabled; after the table initialisation the cores stay idle for 20 us, then an Octet String, an Octet String with a last beat without bytes and an SDU without any byte (rejected, ERR_TX1) pass from A to B, and a packet with a last beat without bytes enters B from the link; the post check of the configuration fails on any numeric_std metavalue warning after the start marker. Positive control: before the marker the testbench raises one numeric_std warning itself (`to_integer` of an undefined vector), and the post check fails when it is missing, so the test cannot pass with the IEEE warnings disabled; with the CPTP layer, without it and through the N-Char adapters | CO-IF-04 |
| `test_throughput` (TC-CO-12) | Statistics of the link ports and of the send ports of A record every beat with its time. Sending end: 16 SDUs per case (Octet Strings of 1, 2, 61, 256 and 1024 bytes on port 0, 61 bytes to a destination with four address bytes, Space Packets of 7, 8, 67, 262 and 1030 bytes on the Packet Service port 1) queued while the link is held: the first seven are taken at one beat per cycle; then the link drops the packets (always ready) and packets 5 to 16 must leave within max(`N` + 1, 5) cycles each. Receiving end: 16 Space Packets per length injected back-to-back into B for the Octet String port 0 and the Packet Service port 1, the link input and the receive port within the same bound. Two send ports with queued SDUs of 61 bytes delivered to B: fixed priority sends all SDUs of port 0 before port 2, round robin alternates them, both within the bound; `cptp_w32`, `cptp_w128`, `plain_w64` | CO-SY-08 |
| `test_every_port` (TC-CO-13) | One SDU at a time, 2 x max(`NumTx_g`, `NumRx_g`, `NumDest_g`) SDUs of random length: SDU `i` leaves send port `i` mod `NumTx_g` of A (Space Packets at the Packet Service port 1) through destination `i` mod `NumDest_g` and reaches receive port `i` mod `NumRx_g` of B with the User Application value of the destination; packet counters, no error event; `ports1_w32` to `ports16_w32` | CO-SY-01, CO-GN-01 |
| `test_reset_values` (TC-CO-14) | GENERICS, SERVICES, TX_BUFFER and RX_BUFFER against the generics, CONFIG and MAX_LENGTH against their reset values; in every configuration of a structure value and of a bound (`cptp_w8` to `cptp_w120`, `ports1_w32` to `ports16_w32`, `addr0_w8` to `addr16_w8`, `bufmin_w8`, `bufmax_w8`, `pktmax_w32`, `pktmax_w8`, `limits_w32`). Outside each bound of CO-GN-02 to CO-GN-04 the synthesis stops with the message of the bound (`lint/synth_check.py`) | CO-GN-01, CO-GN-02, CO-GN-03, CO-GN-04 |
| `test_dprst_eep` (TC-CO-15) | Octet Strings of 200 bytes from A to B, the link takes every beat. `DpRst` of A for one cycle at the edge at which the first, the second and the second-to-last beat of a packet is transferred. The monitor of A shows the beats transferred up to the reset edge, then exactly one EEP beat in the cycle after the reset edge (`Data` 0, `Keep` lane 0 only, `Last` '1', `User(0)` '1', `User(4:1)` the destination of the packet), then `M_Link_Valid` '0' up to the first packet after the release. B discards each interrupted packet (event 0x10, its counter) and delivers every SDU that A takes after the release, the first with the loss indicator. In `plain_w64` the packets use destination 3, in `nchar_w32` the N-Char stream carries the data character 0x00 and the EEP marker; `cptp_w32`, `cptp_w128`, `plain_w64`, `nchar_w32`, `cptp_w8` | CO-RS-01, CO-RS-04, CO-RS-05, CO-RS-12, CO-SY-03, CO-SY-07 |
| `test_dprst_no_eep` (TC-CO-16) | Negative cases of the EEP: `DpRst` of A (a) while A sends nothing, (b) at the edge at which the last beat of a packet is transferred, (c) at the edge at which the last beat of a packet is transferred while the next packet waits back-to-back. No beat leaves `M_Link` of A from the reset edge up to the first packet after the release; B counts no error and delivers the packets of (b) and (c) intact; the waiting packet of (c) is not sent; `cptp_w32`, `plain_w64`, `nchar_w32` | CO-RS-05, CO-RS-06 |
| `test_dprst_stall` (TC-CO-17) | The link model stalls `M_Link_Ready` of A for 20 cycles from the beat of the reset edge, and `DpRst` of A lasts 30 cycles, with (a) a middle beat pending, (b) the first beat of a packet pending, (c) the last beat pending; (d) `DpRst` of 4 cycles with a middle beat pending and the stall kept for 3000 cycles, beyond the release edge and the table initialisation, while new SDUs wait in A. The pending beat stays unchanged on `M_Link` while the link stalls; then (a), (b), (d) send the pending beat and the EEP beat in the next cycle, (c) the last beat and no EEP beat, after which B delivers the packet of (c) intact; in (d) the first new packet follows only after the EEP beat; `cptp_w32`, `cptp_w128`, `plain_w64` | CO-RS-03, CO-RS-04, CO-RS-05, CO-RS-06 |
| `test_dprst_long` (TC-CO-18) | `DpRst` of A for 5000 cycles (longer than the table initialisation) inside a packet: exactly one EEP beat, in the cycle after the reset edge, then no beat up to the first packet after the release. Then a stalled link with the EEP beat pending and a second reset edge of `DpRst` (released for one cycle, applied again): still one EEP beat; `cptp_w32`, `plain_w64` | CO-RS-01, CO-RS-04, CO-RS-05 |
| `test_dprst_state` (TC-CO-19) | A gets values other than the reset values in every writable register (CONFIG, MAX_LENGTH, every destination, IRQ_EN, SCRUB, ECC_SELECT), written entries in both APID tables, and non-zero counters, EVENTS, LAST_ERROR and ECC counters (rejected SDUs, discarded packets, injected errors). `DpRst` for one cycle, and in a second pass for 16 cycles: after the release `TABLE_STATUS.TX_BUSY` and `RX_BUSY` read '1' and then '0' within 2048 cycles, every register reads its reset value, the written table entries read the initial entries (count 0, last count invalid), and after the programming sequence SDUs pass from A to B again; `cptp_w32`, `nopath_w32` | CO-RS-01, CO-RS-02 |
| `test_dprst_rst` (TC-CO-20) | Orders of `Rst` and `DpRst` of A with a packet open on `M_Link`: (a) `Rst` while the EEP beat is pending on a stalled link, (b) both applied at the same edge, (c) both applied, `Rst` released first and `DpRst` one cycle later, (d) `DpRst` released first and `Rst` ten cycles later, (e) `DpRst` applied for three cycles while `Rst` is applied, (f) `Rst` alone. `M_Link_Valid` of A is '0' from the cycle after the reset edge of `Rst`, no EEP beat follows `Rst` in any order, no beat leaves A before the first packet after the later release, and `TABLE_STATUS.TX_BUSY` of A reads '1' after the later release. The link model drops the cut packet together with the packet it joins at B; the following SDUs of A reach B; `cptp_w32`, `plain_w64` | CO-RS-01, CO-RS-07, CO-RS-08 |
| `test_dprst_ports` (TC-CO-21) | Every send port of A has taken part of an SDU (Octet String and Packet Service ports) and one port holds a complete SDU in its buffer when `DpRst` of A comes, while a receive port of A delivers an SDU of B. During the reset `S_Tx_Ready` of every send port, `M_Rx_Valid` of every receive port, the AXI4-Lite ready and response outputs, `Irq` and `Err_Valid` of A are '0'; the delivered SDU ends without its last beat (the sink aborts it); the sources abort their SDUs. After the release every send port sends a new SDU, and B delivers exactly these SDUs with no byte of the interrupted or the buffered ones; A delivers the next SDUs of B; `cptp_w32`, `ports1_w32`, `ports16_w32` | CO-RS-02, CO-RS-09, CO-RS-11, CO-RS-12 |
| `test_dprst_active_link` (TC-CO-22) | Octet Strings in both directions with the continuity check enabled at both cores. `DpRst` of A for 4 cycles while A sends an Octet String of 2000 bytes on `M_Link` and has taken three beats of an Octet String of 400 bytes 0x55 from B on `S_Link`: A ends its packet with the EEP beat, B discards it (0x10) and keeps sending and delivering all the time; `S_Link_Ready` of A is '1' during the reset with the CPTP layer (the beats of B are discarded without a count) and '0' without it (the link of B waits); after the release A discards the rest of the packet of B once with the reason of the first failed check (0x11 with the CPTP layer, 0x15 without); the first SDU of A after the release carries the count 0 and B indicates the discontinuity (RX_LOSS); every later SDU in both directions is delivered intact; `cptp_w32`, `cptp_w128`, `plain_w64`, `nchar_w32` | CO-SY-03, CO-SY-06, CO-RS-05, CO-RS-10, CO-RS-12 |

## 4. Seams of the integration

| Seam | Crossed by |
| --- | --- |
| `spp_send` to `spp_encapsulation`: EEP and destination index in `TUser` | TC-CO-01 (destinations), TC-CO-05 (EEP of a double error) |
| `spp_encapsulation`, or `spp_send` without the CPTP layer, to `spp_link_output` | Every test that sends; TC-CO-15 to TC-CO-18 (EEP beat), TC-CO-15 in `plain_w64` (destination index of the EEP beat) |
| `spp_decapsulation` to `spp_receive`: EEP and User Application value | TC-CO-01 (User Application values), TC-CO-03 (EEP) |
| Direct link connection without the CPTP layer | TC-CO-07, TC-CO-03 and TC-CO-04 in `plain_w64` |
| Configuration outputs of `spp_mib` (maximum length, destinations, address removal, filter) | TC-CO-02, TC-CO-03, TC-CO-06 |
| Table clients of `spp_mib` to both tables | TC-CO-01, TC-CO-03, TC-CO-06 |
| Error event indices, packet and loss events to `spp_mib` | TC-CO-01, TC-CO-03, TC-CO-04, TC-CO-06 |
| ECC channels and injection commands | TC-CO-05 |
| Initial table entries from the generics | TC-CO-01 (APIDs without a table write), TC-CO-03, TC-CO-10 (both values of the generics), TC-CO-19 (after `DpRst`) |
| Data path reset (`Rst` or `DpRst`) to every module except `spp_link_output` | TC-CO-19 (register file, tables), TC-CO-21 (send buffers, receive ports, register port), TC-CO-22 (receiving end) |
| `spp_nchar` between two cores | TC-CO-01, TC-CO-03, TC-CO-05 in `nchar_w32`; TC-CO-15, TC-CO-16, TC-CO-22 in `nchar_w32` (EEP beat of `DpRst`) |

## 5. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CO-IF-01 | TC-CO-01, TC-CO-07 |
| CO-IF-02 | TC-CO-03, TC-CO-07 |
| CO-IF-04 | TC-CO-11 |
| CO-IF-03 | TC-CO-01, TC-CO-10 |
| CO-SY-01 | TC-CO-01 |
| CO-SY-02 | TC-CO-02 |
| CO-SY-03 | TC-CO-03, TC-CO-04, TC-CO-05, TC-CO-06, TC-CO-10, TC-CO-15, TC-CO-22 |
| CO-SY-04 | TC-CO-01 to TC-CO-03, TC-CO-05, TC-CO-06, TC-CO-10 |
| CO-SY-05 | TC-CO-08 |
| CO-SY-06 | TC-CO-09, TC-CO-22 |
| CO-SY-07 | TC-CO-01, TC-CO-05, TC-CO-15 |
| CO-SY-08 | TC-CO-12 |
| CO-GN-01 | TC-CO-01, TC-CO-02, TC-CO-13, TC-CO-14 |
| CO-GN-02 | TC-CO-14 |
| CO-GN-03 | TC-CO-14 |
| CO-GN-04 | TC-CO-01, TC-CO-14 |
| CO-RS-01 | TC-CO-15, TC-CO-18, TC-CO-19, TC-CO-20 |
| CO-RS-02 | TC-CO-19, TC-CO-21 |
| CO-RS-03 | TC-CO-17 |
| CO-RS-04 | TC-CO-15, TC-CO-17, TC-CO-18 |
| CO-RS-05 | TC-CO-15 to TC-CO-18, TC-CO-22 |
| CO-RS-06 | TC-CO-16, TC-CO-17 |
| CO-RS-07 | TC-CO-20 |
| CO-RS-08 | TC-CO-20 |
| CO-RS-09 | TC-CO-21 |
| CO-RS-10 | TC-CO-09, TC-CO-22 |
| CO-RS-11 | TC-CO-21 |
| CO-RS-12 | TC-CO-15, TC-CO-21, TC-CO-22 |

The link output monitor runs in every test, so the AXI4-Stream rules of CO-RS-03 are checked in every configuration,
not only around a reset.

## 6. Functional coverage of the resets

The reset tests are directed; the coverpoints record that every case of the plan was reached, sampled by the link
output monitor (`DPRST_POINT`, `DPRST_LINK`) and by the reset probe (`DPRST_LENGTH`, `RESET_ORDER`, `RESET_SLINK`)
at every reset edge and release edge. Each test checks the bins of its cases, so every bin is hit in the regression:
`DPRST_POINT` in TC-CO-15 to TC-CO-17, `DPRST_LINK` in TC-CO-15 and TC-CO-17, `DPRST_LENGTH` in TC-CO-15, TC-CO-18 and
TC-CO-19, `RESET_ORDER` in TC-CO-20, `RESET_SLINK` in TC-CO-09 and TC-CO-22. The bin "open, nothing presented" of
`DPRST_POINT` is not reachable through the ports: the blocks in front of the link output stage keep a packet beat by
beat without gaps.

| Coverpoint | Requirements | Bins |
| --- | --- | --- |
| `DPRST_POINT`: state of `M_Link` at the reset edge of `DpRst` | CO-RS-03 to CO-RS-06 | no packet open; first, middle, last beat transferred at the edge; first, middle, last beat pending; open with no beat presented |
| `DPRST_LINK`: `M_Link` at the reset edge and the end of the packet | CO-RS-03, CO-RS-04 | no beat pending at the reset edge; a beat pending; end of the packet transferred after the release edge |
| `DPRST_LENGTH`: cycles of `DpRst` | CO-RS-01 | 1; 2 to 16; more than 2048 |
| `RESET_ORDER`: order of `Rst` and `DpRst` | CO-RS-07, CO-RS-08 | `DpRst` alone; `Rst` alone; same edge; `Rst` during `DpRst`; `DpRst` during `Rst`; `Rst` released first; `DpRst` released first |
| `RESET_SLINK`: link input at the reset edge | CO-RS-10 | idle; inside a packet, with and without the CPTP layer |

## 7. Mutations

Every check of the reset tests is proven by a mutation of the RTL that makes it fail (phase E). The mutations are
applied by a script outside the repository to the committed sources, one at a time, and every mutation must make at
least one test of the regression fail; a mutation that no test detects fails the step.

| ID | Mutation | Expected to fail |
| --- | --- | --- |
| M1 | `spp_link_output` reset by `Rst` or `DpRst` (as the other modules) | TC-CO-15, TC-CO-17 (no EEP beat, pending beat withdrawn: monitor) |
| M2 | `End_s` never loads the EEP beat | TC-CO-15, TC-CO-22 |
| M3 | EEP beat with `User(0)` '0' | TC-CO-15 (beat format, event 0x10 at B) |
| M4 | EEP beat with `Last` '0' | TC-CO-15 |
| M5 | EEP beat without a valid byte (`Keep` all '0') | TC-CO-15 (beat format), monitor |
| M6 | EEP beat with destination index 0 | TC-CO-15 in `plain_w64` |
| M7 | EEP beat also when no packet is open (`OpenNext` ignored) | TC-CO-16 |
| M8 | `Open` not cleared by a transferred last beat | TC-CO-16, TC-CO-17 (c) |
| M9 | Pending beat replaced by the EEP beat at the reset edge | TC-CO-17 (monitor) |
| M10 | `OValid` cleared by `DpRst` | TC-CO-17 (monitor) |
| M11 | `S_Pkt_Ready` not gated with `DpRst` (a beat of the blocks in front taken at the reset edge) | TC-CO-15 (beats before the EEP beat) |
| M12 | `End_s` left at the release edge with the end of the packet still pending | TC-CO-17 (d) |
| M13 | `Rst` without precedence (the registers of the stage reset only when `DpRst` is '0') | TC-CO-20 |
| M14 | `spp_mib` reset by `Rst` only | TC-CO-19 |
| M15 | `spp_send` reset by `Rst` only | TC-CO-19 (send table), TC-CO-21, TC-CO-22 |
| M16 | `spp_receive` and `spp_decapsulation` reset by `Rst` only | TC-CO-19 (receive table), TC-CO-22 |
| M17 | `spp_encapsulation` reset by `Rst` only | TC-CO-15 (a beat of the interrupted packet after the EEP beat, the next packet without its CPTP header) |
