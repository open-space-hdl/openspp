# spp_core: Specification

## 1. Overview

`spp_core` is the top level of OpenSPP: the sending end (`spp_send`), the receiving end (`spp_receive`), the transfer
layer of ECSS-E-ST-50-53C (`spp_encapsulation`, `spp_decapsulation`, removable by a generic) and the register file
(`spp_mib`) in one clock domain. Its requirements cover what only the assembled core shows: the plumbing of the
generics, the wiring between the modules and the end-to-end behaviour between two cores. The protocol functions are
specified in the modules.

## 2. Requirements

### 2.1 Interfaces and configuration

| ID | Requirement | Clauses |
| --- | --- | --- |
| CO-IF-01 | The core shall provide `NumTx_g` send ports and `NumRx_g` receive ports of the services selected per port, one transmit and one receive link port, an AXI4-Lite register port, an interrupt and an error event output, all in the clock domain `Clk` with the synchronous reset `Rst`. | SPP 4.2.3.1, 4.3.3.1 |
| CO-IF-02 | With `Encapsulation_g` = true the link ports shall carry CPTP packets; with false they shall carry the Space Packets, the destination index in `TUser` of the transmit link, and the received packets shall have the User Application value 0. | CPTP 5.4 |
| CO-IF-03 | After the reset every APID shall have an enabled managed data path to destination 0 and to receive port 0 when `TxPathDefault_g` and `RxPathDefault_g` are true, and none when they are false. | SPP 4.2.3.3, 4.3.3.2 |

### 2.2 System behaviour

| ID | Requirement | Clauses |
| --- | --- | --- |
| CO-SY-01 | Space Packets and Octet Strings submitted at one core shall be delivered at the receive ports of their APIDs at another core connected through the link ports, in both directions at the same time, with the Packet Service and the Octet String Service on either side, with the User Application value of the destination and the continuity of the Packet Sequence Count. | SPP 2.2.2.1, 3.3.1, 3.4.1, 4.2.3.3, 4.3.3.3 |
| CO-SY-02 | A Target SpaceWire Address of the destination shall be transmitted in front of the CPTP header and removed by the receiving core with its `RX_STRIP` setting. | CPTP 5.3.1 |
| CO-SY-03 | Every rejection at the sending end and every discard at the receiving end of a core shall be counted in its register file, set its event flags and interrupt and appear on its error event output; a packet lost or ended with an EEP on the link, and a double error in a send buffer, shall be detected by the receiving core. | SPP 3.3.2.3; CPTP 5.5.2c, 5.5.4.4 |
| CO-SY-04 | The managed parameters written through the register file (maximum length, destinations, APID tables, Target Logical Address filter, error injection) shall take effect in the modules. | SPP 5.2 |
| CO-SY-05 | Back-to-back Octet Strings of 1024 bytes shall pass from one core to another with at most three clock cycles per packet in addition to the link beats. | none (P6) |
| CO-SY-06 | A reset of one core shall not disturb the other core; the receiving core shall indicate the discontinuity of the counts that restart at 0. | SPP 4.1.3.4.3.4 |
| CO-SY-07 | Two cores shall exchange packets through two `spp_nchar` adapters and an N-Char stream in each direction, including the end of packet markers EOP and EEP. | CPTP 5.4.1.8 |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of all streams |
| `NumTx_g`, `NumRx_g` | 1 | 1 to 16 | Send and receive ports |
| `TxOctetString_g`, `RxOctetString_g` | all '1' | 16 bits | Service per port: '1' Octet String, '0' Packet Service |
| `TxBufferBytes_g`, `RxBufferBytes_g` | 4096 | `DataWidth_g`/8 times a power of two | Buffer of each send port, of the reception |
| `TxMaxPackets_g`, `RxMaxPackets_g` | 8 | 2 to any | SDUs and packets a buffer holds |
| `Encapsulation_g` | true | boolean | CPTP layer of ECSS-E-ST-50-53C |
| `NumDest_g` | 1 | 1 to 16 | Destinations |
| `SpwAddrBytes_g` | 4 | 0 to 16 | Maximum Target SpaceWire Address |
| `MaxLength_g` | 65542 | 7 to 65542 | Reset value of the maximum packet length |
| `RoundRobin_g` | '0' | std_logic | Reset value of the multiplexing scheme |
| `Tla_g` | 0xFE | 8 bits | Reset value of the own Target Logical Address of the filter |
| `TxPathDefault_g`, `RxPathDefault_g` | true | boolean | Initial managed data paths of all APIDs |
| `ClkFreqHz_g` | 100.0e6 | real | Clock frequency |
