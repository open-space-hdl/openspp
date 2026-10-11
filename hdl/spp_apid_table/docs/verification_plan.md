# spp_apid_table: Verification Plan

## 1. Overview

The testbench drives both clients with transaction procedures and keeps a reference model of all 2048 entries. The
ECC paths are exercised through the error injection input; the scrubber through an injected error in a stored entry.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_apid_table_tb` | none (DUT in the testbench) | `spp_apid_table` with entries of 21 bits at 100 MHz, transaction procedures for clients A and B, a second process for client B in the arbitration test, counters of the ECC events |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_init` (TC-TB-01) | Client A requests during the initialisation: no grant for 2048 cycles, then granted; every entry holds `Init_Value`; no ECC event | TB-FN-02, TB-IF-01 |
| `test_read_write` (TC-TB-02) | 1000 random writes by both clients with random hold times, every old value checked against the model, a release leaves the entry unchanged; first and last entry | TB-IF-01, TB-FN-01 |
| `test_arbitration` (TC-TB-03) | Both clients increment the same entry 300 times concurrently; the final value is 600 (no lost update) and client B is served while client A requests continuously | TB-IF-02, TB-FN-03 |
| `test_ecc` (TC-TB-04) | Single error injected: corrected, `Ecc_Sec`; double error: flag to the client and `Ecc_Ded`, repaired by a write; single error in a stored entry found and written back by the scrubber, the entry then reads without error | TB-FT-01, TB-FT-02 |
| `test_reset` (TC-TB-05) | Reset while client A holds an entry and in the cycle of a read: the table initialises again and serves both clients | TB-IF-03, TB-FN-01 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| TB-IF-01 | TC-TB-01, TC-TB-02 |
| TB-IF-02 | TC-TB-03 |
| TB-IF-03 | TC-TB-05 |
| TB-FN-01 | TC-TB-02, TC-TB-05 |
| TB-FN-02 | TC-TB-01 |
| TB-FN-03 | TC-TB-03 |
| TB-FT-01, TB-FT-02 | TC-TB-04 |
