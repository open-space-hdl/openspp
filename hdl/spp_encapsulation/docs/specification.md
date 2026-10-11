# spp_encapsulation: Specification

## 1. Overview

`spp_encapsulation` is the transfer layer of OpenSPP on SpaceWire (blocks EN-1 and EN-2 of the architecture): the
SpaceWire CCSDS Packet Transfer Protocol of ECSS-E-ST-50-53C. The encapsulation puts every Space Packet into a CPTP
packet for the destination of its APID; the decapsulation checks a received CPTP packet and passes its Space Packet
and User Application value to the receiving end.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| EN-IF-01 | The encapsulation shall take Space Packets and give CPTP packets as AXI4-Streams of `DataWidth_g` bits with `Keep` and `Last`; `TUser` bit 0 flags an error end of packet with the last beat, bits 4:1 hold the destination index. | CPTP 5.4.1.8 |
| EN-IF-02 | The decapsulation shall take CPTP packets with the error end of packet flag in `TUser` and give Space Packets with the error end of packet flag (bit 0, last beat) and the User Application value (bits 8:1) in `TUser`. | CPTP 5.2.3.2 |
| EN-IF-03 | Every packet discarded by the decapsulation shall be reported as a one-cycle event with its reason. | CPTP 5.1.3, 5.5.4.3b |
| EN-IF-04 | The reset input shall return both blocks from any state to the reception of a new packet. | none (D14) |

### 2.2 Encapsulation (EN-1)

| ID | Requirement | Clauses |
| --- | --- | --- |
| EN-TX-01 | A CPTP packet shall consist of the Target SpaceWire Address of the destination (0 to `SpwAddrBytes_g` bytes), its Target Logical Address, the Protocol Identifier 0x02, the Reserved field 0x00, its User Application value and the Space Packet, first byte first, ended like the Space Packet (EOP, or EEP). | SPP 4.2.3.1; CPTP 5.1.4 to 5.1.6, 5.2.1, 5.2.2, 5.3, 5.4, 5.5.3 |
| EN-TX-02 | The destination shall be the entry of the destination index of the packet in the destination table of `NumDest_g` entries; an index beyond the table selects destination 0, an address length beyond `SpwAddrBytes_g` is limited to it. | CPTP 5.2.2.5 |

### 2.3 Decapsulation (EN-2)

| ID | Requirement | Clauses |
| --- | --- | --- |
| EN-RX-01 | The decapsulation shall remove `Cfg_RxStrip` leading bytes (0 to 15) and the CPTP header and pass the Space Packet with the User Application value of the header. | CPTP 5.3.1, 5.5.4.2 |
| EN-RX-02 | A packet shall be discarded when it has no byte beyond the CPTP header (0x14), when its Protocol Identifier is not 2 (0x11), when its Reserved field is not zero (0x12), or, with the filter enabled, when its Target Logical Address is neither `Cfg_Tla` nor 0xFE (0x13); a discarded packet terminated by an EEP is reported as 0x10. | CPTP 5.3.2, 5.5.4.1, 5.5.4.3a, 5.5.4.4 |
| EN-RX-03 | A packet terminated by an EEP that passes the checks shall be passed on with the error end of packet flag, so that the reception discards it. | CPTP 5.5.4.4a |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of the streams |
| `NumDest_g` | 1 | 1 to 16 | Entries of the destination table |
| `SpwAddrBytes_g` | 4 | 0 to 16 | Maximum length of the Target SpaceWire Address |

| Configuration input | Description |
| --- | --- |
| `Cfg_DestAddr`, `Cfg_DestAddrLen`, `Cfg_DestTla`, `Cfg_DestUa` | Destination table: Target SpaceWire Address and its length, Target Logical Address, User Application value per destination |
| `Cfg_RxStrip` | Leading bytes removed before the CPTP header of a received packet |
| `Cfg_TlaCheck`, `Cfg_Tla` | Target Logical Address filter and the accepted address besides 0xFE |

Changes of `Cfg_RxStrip` take effect with the next packet; the configuration inputs are changed while no packet is in
transfer.

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| CPTP 5.1.1 | The CCSDS packet is the Space Packet of CCSDS 133.0-B-2, whose format is the one of Issue 1. |
| CPTP 5.1.3, 5.2.3.2c | Status 0x00 is a delivered packet; status 0x01 (EEP) and 0x02 (Reserved not zero) are reported as the error events 0x10 and 0x12. |
| CPTP 5.3.1 | The network removes the Target SpaceWire Address; for networks that deliver leading bytes, `Cfg_RxStrip` removes them. |
| CPTP 5.3.2 | The target accepts every Target Logical Address unless the filter is enabled; with the filter it accepts its own address and the default 0xFE. |
| CPTP 5.5.4.1 | A packet with another Protocol Identifier is not a CPTP packet; it is discarded and reported. |
