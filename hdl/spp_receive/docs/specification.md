# spp_receive: Specification

## 1. Overview

`spp_receive` is the receiving end of the Space Packet Protocol (blocks RE-1 to RE-3 and TB-2 of the architecture).
It receives Space Packets from the transfer layer, checks and buffers every packet completely, discards failed
packets, looks up the user port of the APID in the receive APID table, checks the continuity of the Packet Sequence
Count, and delivers each packet intact (Packet Service) or as an Octet String (Octet String Service) to one of
`NumRx_g` user ports.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| RE-IF-01 | The packet input shall be an AXI4-Stream of `DataWidth_g` bits with `Keep` and `Last`, one received packet per packet of the stream; `TUser` bit 0 flags an error end of packet with the last beat, bits 8:1 hold the User Application value. | SPP 4.3.3.1 |
| RE-IF-02 | Each user port shall deliver indications as an AXI4-Stream of `DataWidth_g` bits with `Keep` and `Last`, one SDU per packet of the stream; the generic `RxOctetString_g` selects the Octet String Service ('1') or the Packet Service ('0') per port. | SPP 3.3.3.3, 3.4.3.3 |
| RE-IF-03 | `TUser` of a user port shall carry the APID, the Secondary Header Indicator, the loss indicator and the User Application value of the SDU, constant during the SDU, and an error flag with the last beat. | SPP 3.3.2.2, 3.4.2.2, 3.4.3.3.2; CPTP 5.2.3.2 |
| RE-IF-04 | Every discarded packet shall be reported as a one-cycle event with its reason, its user port when known and its APID; every delivered SDU shall be signalled per port. | CPTP 5.5.4.4b |
| RE-IF-05 | The reset input shall return the receiving end from any state to an empty state and initialise the receive APID table again. | none (D14) |
| RE-IF-06 | A last beat without byte enables at the packet input shall end the packet, which consists of the bytes of the earlier beats; its SDU shall leave the user port without that beat, and a packet without any byte is shorter than 7 bytes (0x14). | SPP 4.1.4.1.2; none (D15) |

### 2.2 Reception (RE-1)

| ID | Requirement | Clauses |
| --- | --- | --- |
| RE-RC-01 | The reception shall store complete packets in a buffer of `BufferBytes_g` bytes, discard a failed packet completely and pass the others on in the order of reception. | SPP 4.3.3.1 |
| RE-RC-02 | A packet shall be discarded for the first failed check in this order: terminated by an error end of packet (0x10), shorter than 7 bytes (0x14), Packet Version Number not '000' (0x15), length not its Packet Data Length plus 7 (0x16), longer than the maximum packet length or the buffer (0x17), Idle Packet while the delivery of Idle Packets is disabled (0x18). | SPP 3.2.2.1, 4.1.2.2, 4.1.3.2.2, 4.1.3.3.4.4, 4.1.3.5; CPTP 5.5.4.4a |

### 2.3 Demultiplexer (RE-2)

| ID | Requirement | Clauses |
| --- | --- | --- |
| RE-DM-01 | Every packet shall be routed to the user port of its APID in the receive APID table; a packet whose APID has no enabled path or a port beyond `NumRx_g` shall be discarded (0x19). | SPP 4.3.3.2 |
| RE-DM-02 | A Packet Service port shall receive the Space Packet intact; a packet for an Octet String port whose Sequence Flags are not '11' shall be discarded (0x1A). | SPP 3.3.3.3, 4.1.3.4.2.3, 4.3.3.3 |
| RE-DM-03 | When the continuity check of the APID is enabled, the loss indicator shall be set for a Packet Sequence Count other than the last count plus one (modulo 16384); the first packet after the check was enabled sets none; the entry keeps the last count. | SPP 3.3.2.3, 3.4.2.4 |

### 2.4 Packet extraction (RE-3)

| ID | Requirement | Clauses |
| --- | --- | --- |
| RE-EX-01 | An Octet String port shall receive the Packet Data Field without the Packet Primary Header, with the Secondary Header Indicator equal to the Secondary Header Flag. | SPP 3.4.2.3, 4.3.2 |

### 2.5 Fault tolerance and performance

| ID | Requirement | Clauses |
| --- | --- | --- |
| RE-FT-01 | A packet whose descriptor or table entry has a double bit error shall be discarded (0x1B); a double bit error in the data of a packet shall set the error flag of its SDU. | none (P5) |
| RE-PF-01 | Back-to-back packets of 262 bytes shall leave an Octet String port with at most three clock cycles per packet in addition to their received beats. | none (P6) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of the streams |
| `NumRx_g` | 1 | 1 to 16 | Number of user ports |
| `RxOctetString_g` | all '1' | 16 bits | Bit p: port p uses the Octet String Service ('1') or the Packet Service ('0') |
| `BufferBytes_g` | 4096 | `DataWidth_g`/8 times a power of two | Receive buffer in bytes |
| `MaxPackets_g` | 8 | 2 to any | Packets that the buffer holds at most |
| `ClkFreqHz_g` | 100.0e6 | real | Clock frequency (scrub pacer of the table) |

| Configuration input | Description |
| --- | --- |
| `Cfg_MaxLength` | Maximum Space Packet length in bytes, 7 to 65542 (SPP Table 5-1) |
| `Cfg_IdleDeliver` | '1' delivers Idle Packets like other packets, '0' discards them |
| `Cfg_TableInit` | Entry written into every APID of the receive APID table after the reset |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| SPP 3.3.2.3, 3.4.2.4 | The Packet Loss and Data Loss Indicators are generated when the continuity check of the APID is enabled; management disables it for APIDs whose telecommand packets carry Packet Names. |
| SPP 4.1.3.3.4.4, 4.1.4.3.4 | Idle Packets carry no user data and are discarded unless the register file enables their delivery. |
| SPP 4.1.3.4.2.3 | Segmented User Data is not delivered through the Octet String Service; such a packet is discarded and reported. |
| SPP 4.3.3.1 | A packet is delivered only after it was received completely and passed all checks. |
| CPTP 5.2.3.2b | A packet terminated by an EEP is not delivered (null packet); its status is reported as an error event. |
