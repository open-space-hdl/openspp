# spp_nchar: Verification Plan

## 1. Overview

Stream models drive and check both directions: every N-Char packet is compared byte by byte with the bytes of the
link packet followed by its marker, every link packet with the data characters of the N-Char packet and its EEP flag.
The integration with the core is tested by the core tests in the configuration `nchar_w32` (two cores, both links
through two adapters).

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_nchar_tb` | none (DUT in the testbench) | `spp_nchar` at 100 MHz, a stream source and a sink on each of the four streams |

VUnit configurations `w8`, `w16`, ... `w128` run every test with every link width from 8 to 128 bits in steps of 8.
`lint/synth_check.py` synthesizes the adapter at 8 and 128 bits and requires that a width that is not a multiple of 8
(12 bits) stops with the message of its assertion.

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_transmit` (TC-AD-01) | Link packets of 1 byte to three beats and random lengths up to 200 bytes, EOP and EEP, random stalls | AD-IF-01, AD-TX-01 |
| `test_receive` (TC-AD-02) | N-Char packets of 0 to three beats of data characters and random lengths, EOP and EEP; packets without data discarded; random stalls | AD-IF-01, AD-RX-01 |
| `test_back_to_back` (TC-AD-03) | 50 packets of 1 to 64 bytes in both directions at the same time without stalls, EOP and EEP: the transmit direction outputs them within one cycle per packet beyond their characters (data and marker), the receive direction takes one character per cycle | AD-TX-01, AD-RX-01, AD-PF-01 |
| `test_reset` (TC-AD-04) | Reset with packets in both directions that the sinks do not accept; afterwards ten packets in each direction | AD-IF-02 |
| `test_null_bytes` (TC-AD-05) | Link packets of 0 to three beats of bytes, each with an additional last beat without byte enables, EOP and EEP flagged on that beat, stalls on both sides: the marker follows the last byte, a packet without any byte produces no character, normal packets pass afterwards | AD-TX-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| AD-IF-01 | TC-AD-01, TC-AD-02 |
| AD-IF-02 | TC-AD-04 |
| AD-TX-01 | TC-AD-01, TC-AD-03 |
| AD-TX-02 | TC-AD-05 |
| AD-RX-01 | TC-AD-02, TC-AD-03 |
| AD-PF-01 | TC-AD-03 |
