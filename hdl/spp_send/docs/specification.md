# spp_send: Specification

## 1. Overview

`spp_send` is the sending end of the Space Packet Protocol (blocks SE-1 to SE-3 and TB-1 of the architecture). It
accepts the requests of `NumTx_g` user ports, each of them a service access point of the Packet Service or of the
Octet String Service, checks and buffers every SDU, multiplexes the ports, builds the Packet Primary Header of every
Octet String with the Packet Sequence Count of its APID or a Packet Name, and passes each Space Packet with the
destination of its managed data path to the transfer layer.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| SE-IF-01 | Each user port shall take requests as an AXI4-Stream of `DataWidth_g` bits with `Keep` and `Last`, one SDU per packet of the stream, first byte in lane 0; the generic `TxOctetString_g` selects the Octet String Service ('1') or the Packet Service ('0') per port. A request is passed when its last beat is accepted. | SPP 3.2.3.4, 3.3.3.2, 3.4.3.2.1.1 |
| SE-IF-02 | `TUser` of an Octet String port shall carry the parameters of OCTET_STRING.request (APID, Secondary Header Indicator, Packet Type, Packet Name valid, Packet Name; layout of the architecture, section 6), constant during the SDU. | SPP 3.4.2.1, 3.4.2.2, 3.4.3.2.2 |
| SE-IF-03 | A request of a Packet Service port shall be a complete Space Packet; the APID parameter of PACKET.request is the APID of its header. | SPP 3.3.2.1, 3.3.2.2; CPTP 5.1.1 |
| SE-IF-04 | The packet output shall be an AXI4-Stream of `DataWidth_g` bits with `Keep` and `Last`, one Space Packet per packet of the stream; `TUser` bit 0 shall flag an error end of packet with the last beat and bits 4:1 shall hold the destination index of the APID. | none |
| SE-IF-05 | Every rejected SDU shall be reported as a one-cycle event with its reason, its port and its APID; every Space Packet that leaves the output shall be signalled on `Sent`. | CPTP 5.5.2c |
| SE-IF-06 | The reset input shall return the sending end from any state to an empty state and initialise the send APID table again. | none (D14) |

### 2.2 Send buffers (SE-1)

| ID | Requirement | Clauses |
| --- | --- | --- |
| SE-BF-01 | Each port shall store complete SDUs in a buffer of `BufferBytes_g` bytes and pass them on in the order of submission. | SPP 3.2.2.1 |
| SE-BF-02 | An SDU longer than the maximum packet length (less 6 bytes for an Octet String) or than the buffer shall be rejected (reason 0x01). | SPP 3.2.2.1, 3.2.3.1; CPTP 5.1.2, 5.5.2 |
| SE-BF-03 | A Space Packet of the Packet Service shall be rejected when it is shorter than 7 bytes (0x02), when its Packet Version Number is not '000' (0x03), when its length is not its Packet Data Length plus 7 (0x04), or when it is an Idle Packet with the Secondary Header Flag set (0x05). | SPP 4.1.2.2, 4.1.3.2.2, 4.1.3.3.3.4, 4.1.3.5 |
| SE-BF-04 | An Octet String shall be rejected when its APID is the Idle APID and its Secondary Header Indicator is set (0x05), or when it carries a Packet Name for a telemetry packet (0x06). | SPP 4.1.3.3.3.4, 4.1.3.4.3.2 |

### 2.3 Multiplexer (SE-2)

| ID | Requirement | Clauses |
| --- | --- | --- |
| SE-MX-01 | The multiplexer shall pass one complete SDU at a time, selecting among the ports with a complete SDU by fixed priority (port 0 first) or by round robin as `Cfg_RoundRobin` selects. | SPP 4.2.3.2 |

### 2.4 Packet assembly (SE-3)

| ID | Requirement | Clauses |
| --- | --- | --- |
| SE-AS-01 | One Octet String shall result in one Space Packet: the Packet Primary Header (Packet Version Number '000', the Packet Type of the request, the Secondary Header Flag equal to the Secondary Header Indicator, the APID, Sequence Flags '11', Packet Sequence Count or Packet Name, Packet Data Length equal to the length of the Octet String minus one) followed without gap by the Octet String. | SPP 3.2.3.2, 3.2.3.3, 3.4.1, 3.4.2.3, 3.4.3.2.1.2, 4.1.2.1, 4.1.3.1, 4.1.3.2, 4.1.3.3.1, 4.1.3.3.2, 4.1.3.3.3, 4.1.3.3.4, 4.1.3.4.1, 4.1.3.4.2, 4.1.3.5, 4.1.4.1, 4.1.4.3, 4.2.2 |
| SE-AS-02 | The Packet Sequence Count shall be the count of the APID in the send APID table, which is then incremented modulo 16384; a telecommand packet with a valid Packet Name shall carry the name and leave the count unchanged. | SPP 4.1.3.4.3, 4.2.2.4 |
| SE-AS-03 | A Space Packet of the Packet Service shall be transferred without any change. | SPP 3.3.1 |
| SE-AS-04 | Every SDU shall be transferred along the managed data path of its APID: the destination index of its entry; an SDU whose APID has no enabled path shall be rejected (0x07). | SPP 4.2.3.3 |
| SE-AS-05 | An SDU whose descriptor or table entry has a double bit error shall be rejected (0x08); a double bit error in the data of an SDU shall end its Space Packet with an error end of packet. | none (P5) |

### 2.5 Performance

| ID | Requirement | Clauses |
| --- | --- | --- |
| SE-PF-01 | Back-to-back Octet Strings of 256 bytes on one port shall leave the output with at most three clock cycles per packet in addition to its beats. | none (P6) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of the streams |
| `NumTx_g` | 1 | 1 to 16 | Number of user ports |
| `TxOctetString_g` | all '1' | 16 bits | Bit p: port p uses the Octet String Service ('1') or the Packet Service ('0') |
| `BufferBytes_g` | 4096 | `DataWidth_g`/8 times a power of two | Buffer of each port in bytes |
| `MaxPackets_g` | 8 | 2 to any | SDUs that a buffer holds at most |
| `ClkFreqHz_g` | 100.0e6 | real | Clock frequency (scrub pacer of the table) |

| Configuration input | Description |
| --- | --- |
| `Cfg_MaxLength` | Maximum Space Packet length in bytes, 7 to 65542 (SPP Table 5-1) |
| `Cfg_RoundRobin` | Packet Multiplexing Scheme: '0' fixed priority, '1' round robin (SPP Table 5-1) |
| `Cfg_TableInit` | Entry written into every APID of the send APID table after the reset |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| SPP 3.1, 3.3.3.2.2 | The APID parameter of PACKET.request is represented by the APID of the submitted Space Packet. |
| SPP 3.3.2.4 | One quality of service: the optional QoS Requirement parameter is not implemented. |
| SPP 4.1.3.3.3.3 | The Secondary Header Flag of an APID is kept static by the user; the core does not check it. |
| SPP 4.1.3.4.3.2 | A telemetry packet carries the Packet Sequence Count; a Packet Name in the request of a telemetry packet is rejected. |
| SPP 4.1.3.4.3.4 | The counts are reset only by the reset of the core (an unavoidable reinitialisation); the register file can set them. |
| CPTP 5.5.2c | "Reject the send request and inform the initiator user application": the SDU is discarded and an error event is reported. |
