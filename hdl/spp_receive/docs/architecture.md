# spp_receive: Architecture

## 1. Block diagram

![Block diagram of spp_receive: reception (RE-1), demultiplexer (RE-2), packet extraction per user port (RE-3) and
receive APID table (TB-2)](img/spp_receive_arch.drawio.svg)

## 2. Reception (RE-1, `spp_receive_buffer`)

The reception checks a packet while it arrives and writes it into an `olo_ft_fifo_packet` (data only, feature set
`DROP_SKIP_ONLY`). The first six bytes are captured from fixed beat and lane positions. The checks of RE-RC-02 decide
at the last beat in the order of the table below; the oversize check also runs on every beat and drops the rest of a
packet that exceeds the limit.

| Order | Check | Reason |
| --- | --- | --- |
| 1 | Error end of packet (`TUser` bit 0 of the last beat) | 0x10 |
| 2 | Shorter than 7 bytes | 0x14 |
| 3 | Packet Version Number not '000' | 0x15 |
| 4 | Length not PDL + 7 (17-bit arithmetic) | 0x16 |
| 5 | Longer than `Cfg_MaxLength` or the buffer | 0x17 |
| 6 | Idle APID while `Cfg_IdleDeliver` = '0' | 0x18 |

An accepted packet writes a descriptor into an `olo_ft_fifo_sync`:

| Bits | Content |
| --- | --- |
| 16:0 | Byte length of the packet |
| 64:17 | Packet Primary Header (byte 0 in bits 24:17) |
| 72:65 | User Application value |

## 3. Demultiplexer (RE-2, `spp_receive_demux`)

Two concurrent state machines, as in the packet assembly of the sending end:

![State machines of the demultiplexer: preparation (PIdle_s to PJob_s) and transfer (SIdle_s,
SStream_s)](img/spp_receive_fsm.drawio.svg)

`PWrite_s` decides with the entry of the APID, in this order: double error in the entry (0x1B), path disabled or
port beyond `NumRx_g` (0x19), Octet String port and Sequence Flags not '11' (0x1A). Otherwise the job carries the port
and the indication parameters: APID, SHI from the SHF, User Application value and the loss indicator. With the
continuity check enabled, the loss indicator is set when the entry is valid and the count differs from the last count
plus one; the entry is then written back with the count as last count and the valid bit set. Without the check the
entry is released unchanged.

`SStream_s` reads the packet from the buffer and offers it to the user port of the job (valid of that port only).
A dropped packet is skipped with `Out_Next`. The byte enables and `Last` of the last word follow from the remaining
byte count; a stored word without bytes after it (a last beat without byte enables at the input, D15) is skipped like a
dropped packet. A double error in any word sets the error flag with the last beat.

## 4. Packet extraction (RE-3, `spp_receive_extraction`)

One instance per user port: `spp_header_remove` removes the six bytes of the Packet Primary Header for an Octet String
port and nothing for a Packet Service port, so that every port has a registered output. The error flag of `TUser` is
masked to the last beat, because the realignment fills a beat from the last input beat that is not always the last
output beat.

## 5. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `S_Pkt_*` | `DataWidth_g` | in, out | Received packets (`Valid`, `Ready`, `Data`, `Keep`, `Last`), `User`: EEP (bit 0), User Application value (8:1) |
| `M_Rx_Valid`, `M_Rx_Ready`, `M_Rx_Last` | `NumRx_g` | out, in, out | Handshake and end of SDU per port |
| `M_Rx_Data`, `M_Rx_Keep` | `NumRx_g` x `DataWidth_g`, x `DataWidth_g`/8 | out | SDU bytes and byte enables, port p in the bits of index p |
| `M_Rx_User` | `NumRx_g` x 22 | out | APID (10:0), SHI (11), loss (12), error (13, last beat), User Application value (21:14) |
| `Cfg_MaxLength`, `Cfg_IdleDeliver`, `Cfg_TableInit` | 17, 1, 21 | in | Managed parameters, initial table entry |
| `Tbl_*` | | | Client B of the receive APID table; `Tbl_Busy` during its initialisation |
| `Err` | 2 events | out | Index 0: reception, 1: demultiplexer |
| `Loss` | 1 | out | An indication with the loss indicator set (SPP 3.3.2.3, 3.4.2.4) |
| `Delivered` | `NumRx_g` | out | An SDU left the port |
| `Ecc_Sec`, `Ecc_Ded` | 4 | out | ECC events: 0 data buffer, 1 descriptor buffer, 2 table reads, 3 scrubber |
| `ErrInj_Channel`, `ErrInj_Double`, `ErrInj_Valid` | 6, 1, 1 | in | Injection into the next write: channel 0 data buffer, 1 descriptor buffer, 2 table |
| `Scrub_Enable` | 1 | in | Scrubber of the table enabled |

## 6. Receive APID table entry

| Bits | Field |
| --- | --- |
| 13:0 | Last Packet Sequence Count received |
| 14 | Last count valid |
| 15 | Continuity check enabled |
| 19:16 | User port |
| 20 | Managed data path enabled |

A packet blocks the reception while its user port does not accept it; the other ports wait behind it. The integrator
provides buffering behind a port whose user can stall for long.
