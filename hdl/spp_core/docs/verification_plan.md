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

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_core_tb` | `spp_core_th` | Two `spp_core` at 100 MHz, link models `spp_core_tb_link`, stream sources and sinks on all user ports, injectors into both link inputs, AXI4-Lite master VVCs, monitors of `Err_*` and `Irq`, statistics of the link ports and of the send ports (beats and packets with their times) |

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
| `test_reset` (TC-CO-09) | Reset of A after five packets with a continuity check at B: B indicates the discontinuity of the restarted counts and keeps delivering | CO-SY-06 |
| `test_default_paths` (TC-CO-10) | Initial entries of an APID in both tables read through the register files; with the default paths an Octet String reaches B without configuration; without them it is rejected by A (no send path), then discarded by B (no receive path) and delivered once both paths are written; without address bytes (`nopath_w32`) a configured address length of 3 is limited to 0 and DEST_ADDR0 reads 0; `cptp_w32`, `cptp_w128`, `nopath_w32` | CO-IF-03, CO-SY-03, CO-SY-04 |
| `test_idle` (TC-CO-11) | IEEE warnings enabled; after the table initialisation the cores stay idle for 20 us, then an Octet String, an Octet String with a last beat without bytes and an SDU without any byte (rejected, ERR_TX1) pass from A to B, and a packet with a last beat without bytes enters B from the link; the post check of the configuration fails on any numeric_std metavalue warning after the start marker. Positive control: before the marker the testbench raises one numeric_std warning itself (`to_integer` of an undefined vector), and the post check fails when it is missing, so the test cannot pass with the IEEE warnings disabled; with the CPTP layer, without it and through the N-Char adapters | CO-IF-04 |
| `test_throughput` (TC-CO-12) | Statistics of the link ports and of the send ports of A record every beat with its time. Sending end: 16 SDUs per case (Octet Strings of 1, 2, 61, 256 and 1024 bytes on port 0, 61 bytes to a destination with four address bytes, Space Packets of 7, 8, 67, 262 and 1030 bytes on the Packet Service port 1) queued while the link is held: the first seven are taken at one beat per cycle; then the link drops the packets (always ready) and packets 5 to 16 must leave within max(`N` + 1, 5) cycles each. Receiving end: 16 Space Packets per length injected back-to-back into B for the Octet String port 0 and the Packet Service port 1, the link input and the receive port within the same bound. Two send ports with queued SDUs of 61 bytes delivered to B: fixed priority sends all SDUs of port 0 before port 2, round robin alternates them, both within the bound; `cptp_w32`, `cptp_w128`, `plain_w64` | CO-SY-08 |
| `test_every_port` (TC-CO-13) | One SDU at a time, 2 x max(`NumTx_g`, `NumRx_g`, `NumDest_g`) SDUs of random length: SDU `i` leaves send port `i` mod `NumTx_g` of A (Space Packets at the Packet Service port 1) through destination `i` mod `NumDest_g` and reaches receive port `i` mod `NumRx_g` of B with the User Application value of the destination; packet counters, no error event; `ports1_w32` to `ports16_w32` | CO-SY-01, CO-GN-01 |
| `test_reset_values` (TC-CO-14) | GENERICS, SERVICES, TX_BUFFER and RX_BUFFER against the generics, CONFIG and MAX_LENGTH against their reset values; in every configuration of a structure value and of a bound (`cptp_w8` to `cptp_w120`, `ports1_w32` to `ports16_w32`, `addr0_w8` to `addr16_w8`, `bufmin_w8`, `bufmax_w8`, `pktmax_w32`, `limits_w32`). Outside each bound of CO-GN-02 to CO-GN-04 the synthesis stops with the message of the bound (`lint/synth_check.py`) | CO-GN-01, CO-GN-02, CO-GN-03, CO-GN-04 |

## 4. Seams of the integration

| Seam | Crossed by |
| --- | --- |
| `spp_send` to `spp_encapsulation`: EEP and destination index in `TUser` | TC-CO-01 (destinations), TC-CO-05 (EEP of a double error) |
| `spp_decapsulation` to `spp_receive`: EEP and User Application value | TC-CO-01 (User Application values), TC-CO-03 (EEP) |
| Direct link connection without the CPTP layer | TC-CO-07, TC-CO-03 and TC-CO-04 in `plain_w64` |
| Configuration outputs of `spp_mib` (maximum length, destinations, address removal, filter) | TC-CO-02, TC-CO-03, TC-CO-06 |
| Table clients of `spp_mib` to both tables | TC-CO-01, TC-CO-03, TC-CO-06 |
| Error event indices, packet and loss events to `spp_mib` | TC-CO-01, TC-CO-03, TC-CO-04, TC-CO-06 |
| ECC channels and injection commands | TC-CO-05 |
| Initial table entries from the generics | TC-CO-01 (APIDs without a table write), TC-CO-03, TC-CO-10 (both values of the generics) |
| `spp_nchar` between two cores | TC-CO-01, TC-CO-03, TC-CO-05 in `nchar_w32` |

## 5. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| CO-IF-01 | TC-CO-01, TC-CO-07 |
| CO-IF-02 | TC-CO-03, TC-CO-07 |
| CO-IF-04 | TC-CO-11 |
| CO-IF-03 | TC-CO-01, TC-CO-10 |
| CO-SY-01 | TC-CO-01 |
| CO-SY-02 | TC-CO-02 |
| CO-SY-03 | TC-CO-03, TC-CO-04, TC-CO-05, TC-CO-06, TC-CO-10 |
| CO-SY-04 | TC-CO-01 to TC-CO-03, TC-CO-05, TC-CO-06, TC-CO-10 |
| CO-SY-05 | TC-CO-08 |
| CO-SY-06 | TC-CO-09 |
| CO-SY-07 | TC-CO-01, TC-CO-05 |
| CO-SY-08 | TC-CO-12 |
| CO-GN-01 | TC-CO-01, TC-CO-02, TC-CO-13, TC-CO-14 |
| CO-GN-02 | TC-CO-14 |
| CO-GN-03 | TC-CO-14 |
| CO-GN-04 | TC-CO-01, TC-CO-14 |
