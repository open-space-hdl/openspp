# spp_mib: Specification

## 1. Overview

`spp_mib` is the register file of OpenSPP (blocks MG-1 and MG-2 of the architecture): the managed parameters of the
Space Packet Protocol and of the CPTP layer, the destinations, the access of software to both APID tables, the
counters and the last error of every rejected SDU and discarded packet, event flags with an interrupt, and the EDAC
monitor of all buffers and tables with error injection for tests. The register map is generated from one description
([register map](register_map.md)).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| MG-IF-01 | The register file shall be accessible through an AXI4-Lite slave with 11-bit byte addresses of 32-bit registers as the register map defines; unused addresses and bits read as zero. | none (P4) |
| MG-IF-02 | `Irq` shall be the OR of the event flags whose interrupt is enabled. | none |
| MG-IF-03 | Every error event shall be passed on as a one-cycle event (reason, port, APID); of several events in one cycle the one of the lowest source index. | CPTP 5.5.2c, 5.5.4.3b, 5.5.4.4b |
| MG-IF-04 | The reset input shall restore the reset values of all registers. | none (D14) |

### 2.2 Managed parameters and product information

| ID | Requirement | Clauses |
| --- | --- | --- |
| MG-CF-01 | The register file shall hold the managed parameters: maximum packet length (limited to 7 to 65542 bytes on write), packet multiplexing scheme, delivery of Idle Packets, Target Logical Address filter with the own address, leading bytes removed in front of the CPTP header, enable of the scrubbers. | SPP 5.2 |
| MG-CF-02 | The register file shall hold `NumDest_g` destinations, each with Target Logical Address, User Application value and a Target SpaceWire Address of up to `SpwAddrBytes_g` bytes with its length; destinations beyond `NumDest_g` and address bytes beyond `SpwAddrBytes_g` read as zero. | CPTP 5.1.4 to 5.1.6 |
| MG-CF-03 | The register file shall report the identification, the generics, the service type of every port and the buffer sizes. | SPP 5.2 |

### 2.3 APID tables

| ID | Requirement | Clauses |
| --- | --- | --- |
| MG-TB-01 | A write of an APID register shall read the entry of the APID into the entry register; a write of the entry register shall write it to the APID of the APID register; a read of the entry register shall wait until a pending access of its table is complete, including the initialisation of the table. | none |
| MG-TB-02 | A write of the APID or entry register while the previous access of the table is pending shall be ignored and set the overrun flag of the table; the double error flag of a read entry shall be readable. | none |

### 2.4 Counters, events and fault tolerance

| ID | Requirement | Clauses |
| --- | --- | --- |
| MG-CN-01 | Every error code shall have a 16-bit saturating counter that counts every event of the code, also several in one cycle; a write to a counter register clears both of its counters. The last error event shall be readable. | CPTP 5.5.2c, 5.5.4.3b, 5.5.4.4b |
| MG-CN-02 | The Space Packets sent, the SDUs delivered (several ports in one cycle) and the indications with a loss indicator shall be counted in 32-bit saturating counters, cleared by a write. | SPP 3.3.2.3 |
| MG-EV-01 | Event flags shall be set for a rejected SDU, a discarded packet, a packet sent, an SDU delivered, a loss indication, a single and a double ECC error, and cleared by writing one. | none |
| MG-FT-01 | The EDAC monitor shall count single and double errors of 8 channels (data, descriptor, table and scrubber of each end), keep a sticky double error flag per channel and clear on write. | none (P5) |
| MG-FT-02 | A write of the injection register shall command a single or a double error into the next write of the selected buffer or table of the sending or the receiving end. | none (P5) |

## 3. Configuration parameters

| Generic | Default | Description |
| --- | --- | --- |
| `DataWidth_g`, `NumTx_g`, `NumRx_g`, `NumDest_g`, `SpwAddrBytes_g`, `Encapsulation_g`, `TxOctetString_g`, `RxOctetString_g`, `TxBufferBytes_g`, `RxBufferBytes_g` | as the core | Reported in GENERICS, SERVICES, TX_BUFFER, RX_BUFFER; `NumDest_g` and `SpwAddrBytes_g` size the destination table |
| `MaxLength_g` | 65542 | Reset value of MAX_LENGTH |
| `RoundRobin_g` | '0' | Reset value of CONFIG.ROUND_ROBIN |
| `Tla_g` | 0xFE | Reset value of CONFIG.TLA |
| `NumErr_g` | 5 | Number of error event sources |
