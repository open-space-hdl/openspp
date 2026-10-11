# spp_apid_table: Specification

## 1. Overview

`spp_apid_table` holds one entry per APID (blocks TB-1 and TB-2 of the architecture). The sending end keeps the
Packet Sequence Count, the path enable and the destination of every APID in one instance, the receiving end the path
enable, the user port and the continuity state in another. Two clients access the table: the datapath (client A) and
the register file (client B). A transaction reads an entry and then writes it back or releases it; the table is locked
for the transaction, so a read-modify-write of one client is never interleaved with an access of the other.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| TB-IF-01 | Each client shall request a transaction with an APID (valid / ready), receive the entry with a double error flag one cycle after the grant, and end the transaction with a write of a new entry or a release. | none |
| TB-IF-02 | When both clients request in the same cycle, the client that was not served last shall be granted. | none |
| TB-IF-03 | The reset input shall abort a transaction and restart the initialisation from any state. | none (D14) |

### 2.2 Function

| ID | Requirement | Clauses |
| --- | --- | --- |
| TB-FN-01 | The table shall hold one entry of `Width_g` bits for each of the 2048 APIDs; an entry keeps its value until a client writes it or the core is reset. | SPP 4.1.3.4.3.3, 4.1.3.4.3.4 |
| TB-FN-02 | After the reset the table shall write `Init_Value` into every entry within 2048 clock cycles, indicate this on `Init_Busy` and grant no transaction before it is complete. | none |
| TB-FN-03 | No access of the other client shall occur between the read and the write or release of a transaction. | none |

### 2.3 Fault tolerance

| ID | Requirement | Clauses |
| --- | --- | --- |
| TB-FT-01 | The entries shall be protected by SECDED: a single bit error shall be corrected in the read data and reported on `Ecc_Sec`, a double bit error shall be flagged to the client and reported on `Ecc_Ded`. A pattern on the error injection input shall be applied to the next write of a client. | none (P5) |
| TB-FT-02 | A scrubber shall read every entry in idle cycles, write a corrected entry back when it finds a single bit error and report single and double errors on `Scrub_Sec` and `Scrub_Ded`; `Scrub_Enable` = '0' suspends it. | none (P5) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `Width_g` | none | 1 to any | Bits per entry |
| `ClkFreqHz_g` | 100.0e6 | real | Clock frequency, used by the optional scrub pacer |
| `ScrubPeriod_g` | 0.0 | 0.0 or >= 0.001 | Seconds per scrub pass; 0.0 lets the scrubber run in every idle cycle |
| `RamStyle_g` | "auto" | string | RAM implementation attribute |
