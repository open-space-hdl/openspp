# spp_packetizer: Specification

## 1. Overview

`spp_packetizer` turns a stream of data units of any length, for example compressed images, into Space Packets for
a send port of `spp_core` that uses the Packet Service (block PT-1 of the architecture). It cuts every data unit into
segments of `ChunkBytes_g` bytes and sends every segment as one Space Packet with its own Packet Primary Header:
the Sequence Flags mark the first, continuation and last segment of a data unit or a data unit of one segment, the
Packet Sequence Count of the instance numbers the packets, and the Packet Data Length gives the size of the segment.
A receiver finds the boundaries of the data units from the Sequence Flags alone, without decoding the data.

Options per instance: a Packet Secondary Header of `SecHdrBytes_g` bytes whose content the user supplies on a port,
and a CRC-16 over the bytes of every segment, appended to its User Data Field.

In terms of the standard, the packetizer is a user of the Packet Service that segments its user data
(SPP 4.1.3.4.2.1 note): `spp_core` transfers its packets without change (SPP 3.3.1). The packetizer stores every
segment completely before the packet leaves, because the Packet Data Length and the Sequence Flags are known only at
the end of the segment.

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-IF-01 | The input shall take data units as an AXI4-Stream of `DataWidth_g` bits with `Keep` and `Last`, one data unit per packet of the stream, first byte in lane 0; all beats are full except the last beat of a data unit, whose valid bytes are contiguous from lane 0. `S_Error` with the last beat marks an aborted data unit. | none |
| PT-IF-02 | The output shall give complete Space Packets as an AXI4-Stream of `DataWidth_g` bits with `Keep` and `Last`, one Space Packet per packet of the stream, first byte in lane 0, in the format of a PACKET.request at a Packet Service send port of `spp_core`. | SPP 3.3.2.1, 3.3.3.2 |
| PT-IF-03 | The reset input shall return the packetizer from any state to an empty state: buffered segments are discarded and the Packet Sequence Count starts at 0 again. While the reset input is '1' the input shall accept no beat. | SPP 4.1.3.4.3.4; none (D14) |
| PT-IF-04 | A last beat without byte enables shall end the data unit, which consists of the bytes of the earlier beats; a data unit without any byte shall produce no Space Packet. | SPP 4.1.4.1.2; none (D15) |

### 2.2 Segmentation

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-SG-01 | Every data unit shall be cut, in the order of its bytes, into segments of `ChunkBytes_g` bytes and a last segment with the remaining 1 to `ChunkBytes_g` bytes; every segment shall become one Space Packet whose User Data Field holds the bytes of the segment, followed by the CRC when `Crc_g` is set. | SPP 4.1.2.1, 4.1.4.1, 4.1.4.3 |
| PT-SG-02 | The Sequence Flags of a packet shall be '11' when its data unit has one segment, '01' for the first segment, '00' for a continuation segment and '10' for the last segment of a data unit of two or more segments. | SPP 4.1.3.4.2 |
| PT-SG-03 | An aborted data unit shall be segmented and sent like any other data unit, its last segment flagged '10' (or '11'); `Aborted` shall be '1' for one clock cycle when its last beat is accepted. | none |
| PT-SG-04 | A segment of `ChunkBytes_g` bytes that the input does not end with `Last` shall be passed on to the output side when the next beat of its data unit is accepted, so that its Sequence Flags are known. | SPP 4.1.3.4.2 |
| PT-SG-05 | The Space Packets shall leave in the order of their segments. | SPP 4.1.3.4.3.4 |

### 2.3 Packet Primary Header

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-HD-01 | Every packet shall carry the Packet Version Number '000', the Packet Type `Cfg_Type`, the Secondary Header Flag '1' when `SecHdrBytes_g` is greater than 0 and '0' otherwise, and the APID `Cfg_Apid`. | SPP 4.1.3.1, 4.1.3.2, 4.1.3.3 |
| PT-HD-02 | The Packet Sequence Count of the first packet after the reset shall be 0, and that of every further packet the count of the packet before it plus one, modulo 16384; the count is not set back by anything but the reset. | SPP 4.1.3.4.1, 4.1.3.4.3 |
| PT-HD-03 | The Packet Data Length shall be `SecHdrBytes_g` plus the number of bytes of the segment, plus 2 when `Crc_g` is set, minus one. | SPP 4.1.3.5 |
| PT-HD-04 | `Hdr_Sample` shall be '1' for exactly one clock cycle per packet; `Cfg_Apid`, `Cfg_Type` and `SecHdr_Data` shall be sampled at the rising edge of `Clk` that ends this cycle and used for that packet. The cycle shall lie at least two clock cycles before the first output beat of the packet, and the pulses shall follow the order of the packets. | SPP 4.1.4.2.1.4 |

### 2.4 Packet Secondary Header

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-SH-01 | When `SecHdrBytes_g` is greater than 0, every packet shall carry a Packet Secondary Header of `SecHdrBytes_g` bytes, the sampled `SecHdr_Data` with bits 7:0 as its first byte, directly after the Packet Primary Header and before the User Data Field. | SPP 4.1.3.3.3, 4.1.4.2.1.1, 4.1.4.2.1.3 to 4.1.4.2.1.6 |
| PT-SH-02 | When `SecHdrBytes_g` is 0, no packet shall carry a Packet Secondary Header; the User Data Field follows the Packet Primary Header. | SPP 4.1.3.3.3, 4.1.4.2.1.2, 4.1.4.3.1, 4.1.4.3.2 |

### 2.5 CRC

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-CR-01 | When `Crc_g` is set, the User Data Field of every packet shall end with a CRC of two bytes over the bytes of its segment only: generator polynomial x^16 + x^12 + x^5 + 1, initial value all ones, no final inversion, the most significant byte first. The CRC is computed on the input side, before the segment is stored. | none (parameters of ECSS-E-ST-70-41C Annex B.1) |
| PT-CR-02 | When `Crc_g` is not set, the User Data Field shall hold the bytes of the segment only. | SPP 4.1.4.3.4 |

### 2.6 Buffers and protection

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-BF-01 | Every segment shall be stored completely in a buffer of `BufferBytes_g` bytes, and its length, Sequence Flags and CRC in a descriptor, before its packet is output; the buffer holds up to `MaxChunks_g` segments. Buffer and descriptors shall be protected by a SECDED code. | none (P5) |
| PT-BF-02 | A single bit error in the buffer or in a descriptor shall be corrected and reported on `Ecc_Sec` (bit 0 buffer, bit 1 descriptor) for one clock cycle. A double bit error shall be reported on `Ecc_Ded` in the same way, and the packet shall still be sent, with the bytes as read from the buffer and the framing of the buffer. | none (P5) |
| PT-BF-03 | `ErrInj_Data` and `ErrInj_Desc` shall flip one data bit, or two data bits with `ErrInj_Double`, of the next word written into the buffer or into the descriptor memory. | none |

### 2.7 Performance

| ID | Requirement | Clauses |
| --- | --- | --- |
| PT-PF-01 | With the output always ready and the segments complete, the packetizer shall output every packet one beat per clock cycle from its first to its last beat, with at most 3 clock cycles between two packets. | none (P6) |
| PT-PF-02 | With `BufferBytes_g` at least twice `ChunkBytes_g` and the output always ready, the input shall accept a continuous stream of full segments with at most as many stall cycles per segment as its packet has output beats more than its segment has input beats, plus 3. | none (P6) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of the streams |
| `ChunkBytes_g` | 4096 | multiple of `DataWidth_g`/8, at least `DataWidth_g`/8, at most 65536 less `SecHdrBytes_g` and less 2 when `Crc_g` is set | Bytes of a segment, the last segment of a data unit may be shorter |
| `BufferBytes_g` | 8192 | `DataWidth_g`/8 times a power of two, at least `ChunkBytes_g` | Segment buffer. At twice `ChunkBytes_g` the next segment enters while a packet leaves; at `ChunkBytes_g` the input waits until the packet before has left |
| `MaxChunks_g` | 8 | 2 to 64 | Segments the buffer holds at most (relevant for short data units) |
| `SecHdrBytes_g` | 0 | 0 to 64 | Bytes of the Packet Secondary Header, 0 for none |
| `Crc_g` | false | boolean | CRC at the end of every User Data Field |

A value outside these ranges stops the elaboration with an assertion that names the bound.

| Configuration input | Description |
| --- | --- |
| `Cfg_Apid` | APID of the packets (11 bits), sampled per packet (PT-HD-04) |
| `Cfg_Type` | Packet Type: '0' telemetry, '1' telecommand, sampled per packet |
| `SecHdr_Data` | Content of the Packet Secondary Header, `8 * SecHdrBytes_g` bits, sampled per packet |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| SPP 3.3.1, 4.1.3.4.2.1 | Segmentation is a function of the user of the Packet Service: the packetizer formats complete Space Packets with the Sequence Flags of its segments, `spp_core` transfers them unchanged. |
| SPP 4.1.3.4.2.3 | The Sequence Flags '01', '00' and '10' are allowed only when no Octet String Service is used on the managed data path: the send port of `spp_core` and the receive port at the far end use the Packet Service (integration constraint). |
| SPP 4.1.3.4.3.2 | The packetizer writes the Packet Sequence Count also into telecommand packets; it does not use a Packet Name. |
| SPP 4.1.3.4.3.3 | One count per instance: the APID of an instance is used by no other source of packets on the same managed data path (integration constraint). |
| SPP 4.1.3.4.3.4 | The count is set back only by the reset, an unavoidable reinitialisation. |
| SPP 4.1.3.3.3.3, 4.1.4.2.1.6 | The presence and the length of the Packet Secondary Header are fixed by the generic `SecHdrBytes_g`, so they are static for the APID of the instance. `Cfg_Apid` and `Cfg_Type` are changed only while the packetizer holds no data (integration constraint). |
| SPP 4.1.4.2.1.4, 4.1.4.2.1.5 | The content of the Packet Secondary Header (a Time Code Field, an Ancillary Data Field or both) is defined by the user and supplied on `SecHdr_Data`; the packetizer does not interpret it. |
| SPP 4.1.3.3.4.4, 4.1.4.3.4 | The packets carry user data, never Idle Data: `Cfg_Apid` is not the Idle APID (integration constraint). |
| SPP 4.1.2.2 | The longest packet has `6 + SecHdrBytes_g + ChunkBytes_g` bytes, plus 2 with the CRC; the maximum packet length of `spp_core` is set to at least this value (integration constraint). |
| ECSS-E-ST-70-41C 7.4.2, 6.13 | The packets are not PUS packets: PUS uses only the Sequence Flags '11' and transfers large data with its service type 13. The CRC uses the parameters of the PUS packet error control (Annex B.1) but covers the segment only, not the headers. |

## 5. Protection scope

| Element | Protection |
| --- | --- |
| Segment buffer, descriptors | SECDED (`olo_ft_*`): single errors corrected, double errors reported on `Ecc_Ded`. A packet with a double error is still sent. `Crc_g` is the detection at the receiver: the CRC is computed before the buffer, so it exposes a double error in the segment and in the length or CRC of its descriptor; without `Crc_g` such a packet can be well-formed and is reported only on `Ecc_Ded` (architecture, section 5). |
| Packet boundaries in the buffer | Kept in flip-flops of the Open Logic packet FIFO, covered by the TMR of the synthesis tool: a double error in a data word or a descriptor does not change the framing of the packets. |
| Packet Secondary Header, `Cfg_Apid`, `Cfg_Type` | Supplied by the user and sampled per packet; protected neither by the SECDED code nor by the CRC. |
| Count, state machines, other registers | TMR of the synthesis tool; every state machine returns to its idle state from any state. |
