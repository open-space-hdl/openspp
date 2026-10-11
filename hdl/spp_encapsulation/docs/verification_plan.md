# spp_encapsulation: Verification Plan

## 1. Overview

Both blocks are driven by stream sources and checked by stream sinks: every CPTP packet is compared byte by byte with
the packet that the packet model (`tbCptp`) builds from the destination and the Space Packet, every Space Packet of
the decapsulation with the packet inside the CPTP packet, `TUser` on every beat. Discarded packets are checked through
the counters of the error events.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_encapsulation_tb` | `spp_encapsulation_th` | `spp_encapsulation` (`NumDest_g` 4, `SpwAddrBytes_g` 16) and `spp_decapsulation` at 100 MHz, a stream source and a sink on each; destinations with addresses of 0, 1, 3 and 16 bytes |

VUnit configurations `w8`, `w24`, `w64`, `w128` run every test with the stream widths 8 to 128 bits.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_encapsulation` (TC-EN-01) | 100 Space Packets to the four destinations and to the index 9 (destination 0), some ended by an EEP, random stalls; then the address length of destination 3 set to 20, beyond `SpwAddrBytes_g` 16: its packets carry 16 address bytes | EN-IF-01, EN-TX-01, EN-TX-02 |
| `test_decapsulation` (TC-EN-02) | CPTP packets with 0 to 15 leading address bytes removed, random User Application values, EOP and EEP passed on, random stalls | EN-IF-02, EN-RX-01, EN-RX-03 |
| `test_decap_checks` (TC-EN-03) | Protocol Identifier 1 (0x11), Reserved 1 (0x12), Target Logical Address filter (own address and 0xFE accepted, 0x41 discarded with 0x13, accepted with the filter off), only the CPTP header and a packet of 2 bytes (0x14), an EEP on a packet with a wrong Protocol Identifier (0x10); each followed by a correct packet | EN-RX-02, EN-IF-03 |
| `test_random` (TC-EN-04) | 300 random packets through both blocks at the same time, random destinations, strip counts, EEPs and stalls | EN-IF-01, EN-IF-02, EN-TX-01, EN-TX-02, EN-RX-01, EN-RX-03 |
| `test_reset` (TC-EN-05) | Reset while both blocks hold a packet that the sinks do not accept; afterwards ten packets through each | EN-IF-04 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| EN-IF-01 | TC-EN-01, TC-EN-04 |
| EN-IF-02 | TC-EN-02, TC-EN-04 |
| EN-IF-03 | TC-EN-03 |
| EN-IF-04 | TC-EN-05 |
| EN-TX-01, EN-TX-02 | TC-EN-01, TC-EN-04 |
| EN-RX-01, EN-RX-03 | TC-EN-02, TC-EN-04 |
| EN-RX-02 | TC-EN-03 |
