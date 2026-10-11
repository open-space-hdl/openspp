# spp_pkg: Architecture

## 1. Contents

| Group | Items |
| --- | --- |
| Space Packet | `PrimaryHeaderBytes_c`, `MinPacketBytes_c`, `MaxPacketBytes_c`, `MaxOctetStringBytes_c`, `PacketVersion_c`, `IdleApid_c`, `Unsegmented_c`, `SeqCountModulo_c`, `ApidCount_c`, `LengthWidth_c` (17-bit byte counters that saturate at `LengthMax_c`) |
| CPTP packet | `CptpHeaderBytes_c`, `CptpProtocolId_c`, `CptpReserved_c`, `DefaultLogicalAddr_c`, `MaxSpwAddrBytes_c`, `MaxRxStripBytes_c` |
| Ports | `MaxPorts_c`, `MaxDest_c` and the bit positions of `TUser` of the send ports (`TxUser*`), the receive ports (`RxUser*`) and the link ports (`LinkUser*`) |
| Errors | `ErrCode_t` with one code per reason (`ErrTx*`, `ErrRx*`), the event record `ErrEvent_t` (valid, code, port, APID) and its array type |
| Functions | `keepOfBytes`, `bytesOfKeep`, `primaryHeader`, `hdrVersion`, `hdrType`, `hdrShf`, `hdrApid`, `hdrFlags`, `hdrCount`, `hdrPdl` |

## 2. Header representation

A header is a vector of six octets with octet 0 in bits 7:0, the order in which the octets travel in byte lanes 0 to 5
of a stream. Within an octet the most significant bit is transmitted first (SPP 1.6.3), so bit 0 of the Packet
Primary Header (the first bit of the Packet Version Number) is bit 7 of octet 0.

## 3. Error codes

| Code | Name | Reason |
| --- | --- | --- |
| 0x01 | `ErrTxOversize_c` | SDU longer than the maximum packet length or the send buffer |
| 0x02 | `ErrTxShort_c` | Space Packet of the Packet Service shorter than 7 octets |
| 0x03 | `ErrTxVersion_c` | Packet Version Number not '000' |
| 0x04 | `ErrTxLength_c` | Length of a Space Packet other than its Packet Data Length plus 7 |
| 0x05 | `ErrTxIdle_c` | Idle Packet with a Secondary Header Flag or Secondary Header Indicator of '1' |
| 0x06 | `ErrTxName_c` | Packet Name given for a telemetry packet |
| 0x07 | `ErrTxNoPath_c` | APID without an enabled managed data path |
| 0x08 | `ErrTxBuffer_c` | Double bit error in the descriptor of an SDU or in the send APID table |
| 0x10 | `ErrRxEep_c` | Packet terminated by an EEP (CPTP status 0x01) |
| 0x11 | `ErrRxProtocolId_c` | Protocol Identifier other than 2 |
| 0x12 | `ErrRxReserved_c` | Reserved field not zero (CPTP status 0x02) |
| 0x13 | `ErrRxAddress_c` | Target Logical Address not accepted |
| 0x14 | `ErrRxShort_c` | Packet shorter than the CPTP header or than 7 octets |
| 0x15 | `ErrRxVersion_c` | Packet Version Number not '000' |
| 0x16 | `ErrRxLength_c` | Length other than the Packet Data Length plus 7 |
| 0x17 | `ErrRxOversize_c` | Longer than the maximum packet length or the receive buffer |
| 0x18 | `ErrRxIdle_c` | Idle Packet discarded |
| 0x19 | `ErrRxNoPath_c` | APID without an enabled managed data path or with an invalid user port |
| 0x1A | `ErrRxFlags_c` | Sequence Flags other than '11' for a port of the Octet String Service |
| 0x1B | `ErrRxBuffer_c` | Double bit error in the descriptor of a packet or in the receive APID table |
