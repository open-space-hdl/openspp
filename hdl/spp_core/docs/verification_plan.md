# spp_core: Verification Plan

## 1. Overview

The core tests are the integration tests (phase G) of all modules. Two cores A and B (three send and three receive
ports each: ports 0 and 2 Octet String Service, port 1 Packet Service; four destinations of up to four address bytes)
are connected by link models in both directions. Stream models drive and check all user ports; an AXI4-Lite VVC
configures each core and reads its counters. The link models drop packets, end packets with an EEP or switch to an
injector that sends packets built by the testbench. In the configuration `nchar_w32` both links run through two
`spp_nchar` adapters with an 8-bit N-Char stream between them.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_core_tb` | `spp_core_th` | Two `spp_core` at 100 MHz, link models `spp_core_tb_link`, stream sources and sinks on all user ports, injectors into both link inputs, AXI4-Lite master VVCs, monitors of `Err_*` and `Irq` |

| Configuration | Generics |
| --- | --- |
| `cptp_w32`, `cptp_w128` | CPTP layer, `DataWidth_g` 32 or 128 |
| `plain_w64` | Without the CPTP layer, `DataWidth_g` 64 |
| `nchar_w32` | CPTP layer, `DataWidth_g` 32, links through two N-Char adapters each |
| `nopath_w32` | CPTP layer, `DataWidth_g` 32, `TxPathDefault_g` and `RxPathDefault_g` false, `SpwAddrBytes_g` 0 |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_end_to_end` (TC-CO-01) | Five flows in both directions at the same time (A Octet String to B Octet String with continuity check over four APIDs, A Space Packet to B Octet String, A Octet String to B Space Packet, B Octet String to A Octet String, B Space Packet to A Octet String with continuity check), destinations with User Application values, the Target Logical Address filter of B, random stalls; packet counters of both cores; `cptp_w32`, `cptp_w128`, `nchar_w32` | CO-IF-01, CO-IF-03, CO-SY-01, CO-SY-04, CO-SY-07 |
| `test_address_strip` (TC-CO-02) | Destination with a Target SpaceWire Address of three bytes, removed by B | CO-SY-02, CO-SY-04 |
| `test_link_errors` (TC-CO-03) | Packets injected into B: EEP, version 2, length against PDL, longer than the maximum length 200, Idle Packet, APID without path, segment for an Octet String port, 5 bytes and, with the CPTP layer, Protocol Identifier 1, Reserved 1, Target Logical Address 0x41; then a correct packet; every counter of B, the event flags, the interrupt and the error event output; `cptp_w32`, `cptp_w128`, `plain_w64`, `nchar_w32` | CO-SY-03, CO-SY-04, CO-IF-02 |
| `test_loss` (TC-CO-04) | A packet dropped in the link: the next one has the loss indicator, RX_LOSS and the event flag of B; `cptp_w32`, `cptp_w128`, `plain_w64` | CO-SY-03 |
| `test_eep` (TC-CO-05) | A packet ended with an EEP in the link and a packet with a double error injected into the send buffer of A through its register file: both discarded by B; the ECC status of A; `cptp_w32`, `cptp_w128`, `nchar_w32` | CO-SY-03, CO-SY-04, CO-SY-07 |
| `test_send_errors` (TC-CO-06) | SDUs rejected by A: longer than the maximum length 100, APID without path, Idle Packet with SHI, Space Packet of 6 bytes; counters, error events and interrupt of A | CO-SY-03, CO-SY-04 |
| `test_plain` (TC-CO-07) | Without the CPTP layer: Octet Strings from A to B and Space Packets from B to A, User Application value 0; GENERICS of the core | CO-IF-01, CO-IF-02 |
| `test_line_rate` (TC-CO-08) | 100 Octet Strings of 1024 bytes from A to B back-to-back without stalls | CO-SY-05 |
| `test_reset` (TC-CO-09) | Reset of A after five packets with a continuity check at B: B indicates the discontinuity of the restarted counts and keeps delivering | CO-SY-06 |
| `test_default_paths` (TC-CO-10) | Initial entries of an APID in both tables read through the register files; with the default paths an Octet String reaches B without configuration; without them it is rejected by A (no send path), then discarded by B (no receive path) and delivered once both paths are written; without address bytes (`nopath_w32`) a configured address length of 3 is limited to 0 and DEST_ADDR0 reads 0; `cptp_w32`, `cptp_w128`, `nopath_w32` | CO-IF-03, CO-SY-03, CO-SY-04 |

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
| CO-IF-03 | TC-CO-01, TC-CO-10 |
| CO-SY-01 | TC-CO-01 |
| CO-SY-02 | TC-CO-02 |
| CO-SY-03 | TC-CO-03, TC-CO-04, TC-CO-05, TC-CO-06, TC-CO-10 |
| CO-SY-04 | TC-CO-01 to TC-CO-03, TC-CO-05, TC-CO-06, TC-CO-10 |
| CO-SY-05 | TC-CO-08 |
| CO-SY-06 | TC-CO-09 |
| CO-SY-07 | TC-CO-01, TC-CO-05 |
