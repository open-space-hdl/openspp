# spp_mib: Verification Plan

## 1. Overview

Every register is accessed through the UVVM AXI4-Lite VVC and compared with the value the register map defines. The
harness connects the register file to a real send and a real receive APID table, so that the table accesses run
against the table protocol; a client A of the send table can hold an entry to keep an access pending. Events and ECC
pulses are driven by the test sequencer.

## 2. Test configuration

| Testbench | Harness | DUT and environment |
| --- | --- | --- |
| `spp_mib_tb` | `spp_mib_th` | `spp_mib` with 3 send ports (ports 0 and 2 Octet String), 2 receive ports (port 0 Octet String), 3 destinations of up to 6 address bytes, 8 bytes per beat, CPTP layer, buffers of 4096 and 8192 bytes, maximum length 1000, round robin, own address 0x40, 7 error event sources, at 100 MHz; two `spp_apid_table`, AXI4-Lite master VVC |

## 3. Test cases

| Test ID | Description | Requirements |
| --- | --- | --- |
| `test_identification` (TC-MG-01) | ID, GENERICS, SERVICES, TX_BUFFER, RX_BUFFER; unused addresses read zero | MG-IF-01, MG-CF-03 |
| `test_config` (TC-MG-02) | Reset values of CONFIG, MAX_LENGTH and SCRUB and their outputs; writes and outputs; MAX_LENGTH limited to 7 and 65542; reset restores the reset values | MG-CF-01, MG-IF-04 |
| `test_destinations` (TC-MG-03) | Reset value and write of every destination, outputs, address bytes beyond 6 not stored, a destination beyond NUM_DEST reads zero | MG-CF-02 |
| `test_tables` (TC-MG-04) | Entry reads during the initialisation wait for it; write and read back of both tables; a write while an access is pending is ignored and flagged, the flag cleared by writing one to its own bit only; a double error injected into an entry is flagged with the entry | MG-TB-01, MG-TB-02, MG-FT-02 |
| `test_counters` (TC-MG-05) | Every error code once with port and APID (LAST_ERROR); one code from all sources in one cycle; two events in one cycle (lower index reported, also on `Err_*`); clear by write; saturation at 0xFFFF; packet counters with two ports in one cycle, clear | MG-CN-01, MG-CN-02, MG-IF-03 |
| `test_events` (TC-MG-06) | Every event flag set by its source; the interrupt follows each enable bit; write one clears | MG-EV-01, MG-IF-02 |
| `test_ecc` (TC-MG-07) | SEC and DED pulses of two channels: sticky DED flags, counters of the selected channel, clear of a channel and of all; injection commands into both ends with channel and kind | MG-FT-01, MG-FT-02 |

## 4. Requirement coverage

| Requirement | Test cases |
| --- | --- |
| MG-IF-01 | TC-MG-01 |
| MG-IF-02 | TC-MG-06 |
| MG-IF-03 | TC-MG-05 |
| MG-IF-04 | TC-MG-02 |
| MG-CF-01 | TC-MG-02 |
| MG-CF-02 | TC-MG-03 |
| MG-CF-03 | TC-MG-01 |
| MG-TB-01, MG-TB-02 | TC-MG-04 |
| MG-CN-01, MG-CN-02 | TC-MG-05 |
| MG-EV-01 | TC-MG-06 |
| MG-FT-01 | TC-MG-07 |
| MG-FT-02 | TC-MG-04, TC-MG-07 |
