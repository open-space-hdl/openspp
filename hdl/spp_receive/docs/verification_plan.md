# spp_receive: Verification Plan

## 1. Overview

A stream source delivers received packets built by the packet model of `tb/`, with their User Application value and
EOP or EEP. A stream sink per user port compares every indication byte by byte with the Octet String (the Packet Data
Field) or the Space Packet, and `TUser` (APID, SHI, loss indicator, error flag, User Application value) on every
beat. Since the packets of one port leave in the order of reception, every sink checks in order. Discarded packets are
checked through the counters of the error events, their reason, port and APID.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_receive_tb` | `spp_receive_th` | `spp_receive` at 100 MHz with `MaxPackets_g` 8 and a buffer of 1024 beats, a stream source on the input, a stream sink per port, counters of the error events, of the delivered SDUs and of the ECC events; the testbench drives client B of the table |

| Configuration | Generics |
| --- | --- |
| `single_w<n>` | One Octet String port, `DataWidth_g` = n |
| `mixed_w<n>` | Ports 0 and 2 Octet String, port 1 Packet Service, `DataWidth_g` = n |
| `big_w32` | One Octet String port with a buffer of 131072 bytes |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_octet_delivery` (TC-RE-01) | 200 packets of random APIDs, both types, with and without SHF, Packet Data Fields of 1 to 300 bytes, random User Application values, random stalls; then 20 packets while the port does not accept, more than the buffer holds: the reception waits and delivers all; widths 8, 32, 128 | RE-IF-01, RE-IF-02, RE-IF-03, RE-RC-01, RE-EX-01, RE-DM-01 |
| `test_packet_delivery` (TC-RE-02) | 150 packets routed by APID to three ports; Space Packets with every Sequence Flags value intact on the Packet Service port; widths 24 and 64 | RE-IF-02, RE-DM-01, RE-DM-02 |
| `test_checks` (TC-RE-03) | EEP after a correct and after a short packet, packets of 1 and 6 bytes, version 4, length one more and one less than PDL + 7, longer than the maximum length of 100, Idle Packet discarded and, when enabled, delivered; each with reason and APID, each followed by a correct packet; widths 8 and 64 | RE-RC-01, RE-RC-02, RE-IF-04 |
| `test_routing` (TC-RE-04) | Disabled path and a port beyond the ports discarded (0x19) with port and APID; segments (Sequence Flags 0 to 2) discarded for an Octet String port (0x1A) and delivered on the Packet Service port | RE-DM-01, RE-DM-02, RE-IF-04 |
| `test_loss` (TC-RE-05) | Continuity check of one APID: first packet without loss, consecutive counts, a lost count, a repeated count, the wrap 16383 to 0; an APID without check never sets the indicator and keeps its entry | RE-DM-03 |
| `test_max_length` (TC-RE-06) | A Space Packet of 65542 bytes (PDL 65535) is delivered; a packet of 140006 bytes whose PDL + 7 equals its length modulo 2^17 is discarded by the length check (the byte count saturates) | RE-RC-02, RE-EX-01 |
| `test_line_rate` (TC-RE-07) | 100 back-to-back packets of 262 bytes without stalls; widths 32 and 128 | RE-PF-01 |
| `test_ecc` (TC-RE-08) | Single error in the data buffer corrected; double error sets the error flag; double error in a descriptor and in a table entry discards the packet (0x1B); single error in the table corrected; a write repairs the entry; a double error in the last word of a packet without an earlier one sets the error flag (one word at 64 bits); widths 32, 64 | RE-FT-01 |
| `test_reset` (TC-RE-09) | Reset while packets are stored and delivered: afterwards the table is initialised again and packets are delivered | RE-IF-05 |
| `test_random` (TC-RE-10) | 300 random packets to three ports, both services, with discarded packets (EEP, length) interleaved, consecutive counts on a checked APID, random stalls; widths 16 and 128 | RE-IF-01, RE-IF-02, RE-IF-03, RE-RC-01, RE-RC-02, RE-DM-01, RE-DM-02, RE-DM-03, RE-EX-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| RE-IF-01, RE-IF-03 | TC-RE-01, TC-RE-10 |
| RE-IF-02 | TC-RE-01, TC-RE-02, TC-RE-10 |
| RE-IF-04 | TC-RE-03, TC-RE-04 |
| RE-IF-05 | TC-RE-09 |
| RE-RC-01 | TC-RE-01, TC-RE-03, TC-RE-10 |
| RE-RC-02 | TC-RE-03, TC-RE-06, TC-RE-10 |
| RE-DM-01 | TC-RE-01, TC-RE-02, TC-RE-04, TC-RE-10 |
| RE-DM-02 | TC-RE-02, TC-RE-04, TC-RE-10 |
| RE-DM-03 | TC-RE-05, TC-RE-10 |
| RE-EX-01 | TC-RE-01, TC-RE-06, TC-RE-10 |
| RE-FT-01 | TC-RE-08 |
| RE-PF-01 | TC-RE-07 |
