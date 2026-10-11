# spp_pkg: Verification Plan

## 1. Overview

The functions and constants are compared with the packet model of `tb/` (`spp_tb_packet_pkg`), which builds the
Packet Primary Header bit by bit in transmission order, independently of the package. The stream models of `tb/` are
checked against themselves: a source looped back to a sink with deliberately wrong expectations.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_pkg_tb` | none | Functions of `spp_pkg`; a stream source of 32 bits looped back to a stream sink at 100 MHz |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_primary_header` (TC-PK-01) | 1000 headers (all fields zero, all at their maximum, alternating bit patterns, random) encoded and compared octet by octet with the model, every field decoded again; a header with version 5 from the model decoded | PK-FN-01, PK-FN-02 |
| `test_constants` (TC-PK-02) | Every constant compared with the value of its clause | PK-CN-01 |
| `test_keep` (TC-PK-03) | `keepOfBytes` and `bytesOfKeep` for all byte counts of widths 1 to 16 bytes and beyond the width | PK-FN-03 |
| `test_model_checks` (TC-PK-04) | Ten correct packets with stall cycles pass; a wrong byte, one byte too many, a wrong `TUser` on three beats, an unexpected packet and a missing packet raise exactly the expected alerts; a masked `TUser` difference raises none | PK-TB-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| PK-FN-01, PK-FN-02 | TC-PK-01 |
| PK-FN-03 | TC-PK-03 |
| PK-CN-01 | TC-PK-02 |
| PK-TB-01 | TC-PK-04 |
