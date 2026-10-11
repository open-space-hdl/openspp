# spp_send: Verification Plan

## 1. Overview

A stream source per user port submits SDUs; the stream sink on the packet output compares every Space Packet byte by
byte with the packet the packet model of `tb/` builds from the request (Octet String) or with the submitted packet
(Packet Service), and `TUser` with the destination of the APID. The testbench keeps the expected Packet Sequence Count
of every APID. With several ports the sink matches each packet to the queue of its port by the APID (bytes 0 and 1),
so that the order is checked per port; the multiplexing test checks the order across the ports. Rejected SDUs are
checked through the counters of the error events, their reason, port and APID.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_send_tb` | `spp_send_th` | `spp_send` at 100 MHz with `MaxPackets_g` 8 and a buffer of 1024 beats per port, a stream source per port, a stream sink on the output, counters of the error events, of `Sent` and of the ECC events; the testbench drives client B of the table |

| Configuration | Generics |
| --- | --- |
| `single_w<n>` | One Octet String port, `DataWidth_g` = n |
| `mixed_w<n>` | Ports 0 and 2 Octet String, port 1 Packet Service, `DataWidth_g` = n |
| `big_w32`, `big_mixed_w64` | One Octet String port, or the mixed ports, with a buffer of 32768 beats |

Simulator: GHDL; QuestaSim for code coverage.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_octet_string` (TC-SE-01) | 200 Octet Strings of four APIDs interleaved (lengths 1 to 8, around the beat width and random up to 300 bytes, both Packet Types, with and without SHI), APID 100 with destination 5, random stalls; widths 8, 32, 128 | SE-IF-01, SE-IF-02, SE-IF-04, SE-BF-01, SE-AS-01, SE-AS-02, SE-AS-04 |
| `test_packet_name` (TC-SE-02) | Telecommand packets with a Packet Name keep the count of the APID; a Packet Name of a telemetry packet is rejected (0x06) with port and APID; the next packet passes | SE-AS-02, SE-BF-04, SE-IF-05 |
| `test_count_wrap` (TC-SE-03) | Count 16381 set through the table: counts 16381, 16382, 16383, 0, 1, 2; a second APID counts independently; the entries afterwards | SE-AS-02 |
| `test_packet_service` (TC-SE-04) | 100 Space Packets of every Sequence Flags value, both types, with and without secondary header flag, 7 to 200 bytes, transferred intact with the destination of their APID while the Octet String ports send; the counts of their APIDs stay 0; widths 24 and 64 | SE-IF-03, SE-AS-03, SE-AS-04 |
| `test_packet_checks` (TC-SE-05) | Space Packets of 6 bytes, with version 1, with a PDL one too large and one too small, an Idle Packet with SHF, a packet longer than the maximum length of 100 bytes: each rejected with its reason, port and APID, the next packet passes; an Idle Packet without SHF passes; widths 8 and 64 | SE-BF-02, SE-BF-03, SE-IF-05 |
| `test_oversize` (TC-SE-06) | Maximum length 100: Octet Strings of 94 bytes pass, of 95 bytes are rejected; at the maximum length 65542 an Octet String of the buffer size passes and one byte more is rejected | SE-BF-02 |
| `test_max_length` (TC-SE-07) | An Octet String of 65536 bytes becomes a Space Packet of 65542 bytes with PDL 65535; 65537 bytes and 140000 bytes (beyond the range of the byte count) are rejected; in the mixed configuration a Space Packet of 65542 bytes passes the Packet Service port | SE-BF-02, SE-BF-03, SE-AS-01, SE-AS-03 |
| `test_idle` (TC-SE-08) | Octet String with the Idle APID: rejected with SHI, sent without | SE-BF-04 |
| `test_no_path` (TC-SE-09) | An APID without enabled path is rejected (0x07) and skipped; the destinations 3 and 15 of other APIDs | SE-AS-04, SE-IF-05 |
| `test_multiplexing` (TC-SE-10) | Three SDUs per port buffered while the table is held: fixed priority sends port 0, 1, 2 in turn, round robin alternates the ports | SE-MX-01 |
| `test_line_rate` (TC-SE-11) | 100 back-to-back Octet Strings of 256 bytes without stalls: cycles from the first to the last output beat; widths 32 and 128 | SE-PF-01 |
| `test_ecc` (TC-SE-12) | Single error in the data buffer corrected; double error ends the packet with EEP; double error in a descriptor rejects the SDU (0x08); single error in the table corrected; double error in the table rejects the SDU, a write repairs it; a double error in the only (last) word of an SDU ends it with EEP | SE-AS-05, SE-IF-05 |
| `test_reset` (TC-SE-13) | Reset while a packet is sent and further SDUs are buffered: afterwards the table is initialised again and the counts start at 0 | SE-IF-06 |
| `test_random` (TC-SE-14) | 300 random SDUs on three ports (both services, random lengths up to 400 bytes, APIDs, parameters), random stalls, switching the scheme every 50 SDUs; widths 16 and 128 | SE-IF-01, SE-IF-02, SE-IF-03, SE-BF-01, SE-MX-01, SE-AS-01, SE-AS-02, SE-AS-03 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| SE-IF-01, SE-IF-02 | TC-SE-01, TC-SE-14 |
| SE-IF-03 | TC-SE-04, TC-SE-14 |
| SE-IF-04 | TC-SE-01 |
| SE-IF-05 | TC-SE-02, TC-SE-05, TC-SE-09, TC-SE-12 |
| SE-IF-06 | TC-SE-13 |
| SE-BF-01 | TC-SE-01, TC-SE-14 |
| SE-BF-02 | TC-SE-05, TC-SE-06, TC-SE-07 |
| SE-BF-03 | TC-SE-05 |
| SE-BF-04 | TC-SE-02, TC-SE-08 |
| SE-MX-01 | TC-SE-10, TC-SE-14 |
| SE-AS-01 | TC-SE-01, TC-SE-07, TC-SE-14 |
| SE-AS-02 | TC-SE-01, TC-SE-02, TC-SE-03, TC-SE-14 |
| SE-AS-03 | TC-SE-04, TC-SE-14 |
| SE-AS-04 | TC-SE-01, TC-SE-04, TC-SE-09 |
| SE-AS-05 | TC-SE-12 |
| SE-PF-01 | TC-SE-11 |
