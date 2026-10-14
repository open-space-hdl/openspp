# spp_send: Architecture

## 1. Block diagram

![Block diagram of spp_send: send buffers (SE-1) per user port, multiplexer (SE-2), packet assembly (SE-3)
and send APID table (TB-1)](img/spp_send_arch.drawio.svg)

## 2. Send buffer (SE-1, `spp_send_buffer`)

The buffer checks an SDU while it arrives and writes it into an `olo_ft_fifo_packet` (data only, `DataWidth_g` bits
per word, feature set `DROP_SKIP_ONLY`). At the last beat the checks of SE-BF-02 to SE-BF-04 decide in a fixed order:

| Order | Octet String port | Packet Service port |
| --- | --- | --- |
| 1 | Oversize (0x01) | Oversize (0x01) |
| 2 | Without any byte (0x02) | Shorter than 7 bytes (0x02) |
| 3 | Idle APID with SHI (0x05) | Version not '000' (0x03) |
| 4 | Packet Name of a telemetry packet (0x06) | Length not PDL + 7 (0x04) |
| 5 | | Idle APID with SHF (0x05) |

The byte count adds the set bits of `Keep` of every beat, so a last beat without byte enables (D15) adds nothing: the
SDU consists of the bytes of the earlier beats, and the beat itself is stored like any other.

A failed SDU is dropped with `In_Drop` together with its last beat and reported. The oversize check runs on every
beat: once the byte count exceeds the limit, `In_Drop` is asserted and the rest of the SDU is consumed. The byte count
saturates at 2^17 - 1. A Space Packet's first six bytes are captured from fixed beat and lane positions (byte `k` in
beat `k / B`, lane `k mod B`), including the current beat, so that the checks at the last beat see the complete header.

An accepted SDU writes a descriptor into an `olo_ft_fifo_sync` of `MaxPackets_g` entries:

| Bits | Content |
| --- | --- |
| 16:0 | Byte length of the SDU |
| 44:17 | `TUser` of the request (Octet String) or the APID of the header in bits 27:17 (Space Packet) |

The input is ready when both FIFOs are ready. The data FIFO accepts at most `MaxPackets_g` packets, so the descriptor
FIFO never overflows.

## 3. Multiplexer (SE-2, `spp_send_mux`)

`olo_base_arb_prio` (latency 0) and `olo_base_arb_rr` arbitrate among the ports with a descriptor. Port 0 is mapped to
the left-most request bit, the highest priority of both arbiters. `Cfg_RoundRobin` selects the grant; the round-robin
arbiter advances only when its grant is taken.

## 4. Packet assembly (SE-3, `spp_send_assembly`)

The assembly has two state machines that work concurrently, so that the preparation of the next packet overlaps the
transfer of the current one.

![State machines of the packet assembly: preparation (PIdle_s to PJob_s) and transfer (SIdle_s,
SStream_s)](img/spp_send_fsm.drawio.svg)

`PWrite_s` decides with the entry of the APID: a double error or a disabled path makes a job that drops the SDU and
reports it; an Octet String gets its header, and the entry is written back with the incremented count unless a Packet
Name is used (then it is released); a Space Packet releases the entry. The job holds the port, the drop flag, the header
and its length (6 or 0), the byte length and the destination.

`SStream_s` reads the data FIFO of the job's port. A dropped SDU is skipped with `Out_Next` on its first word, which
ends it at once. Otherwise every word goes through `spp_header_insert` with the job's header; the byte enables and
`Last` of the last word follow from the remaining byte count. When a stored word without bytes follows (a last beat
without byte enables at the port, D15), it is skipped like a dropped SDU, so no beat without bytes leaves the output.
A double error in any word sets the EEP flag of `TUser` with the last beat.

The table transaction takes four cycles and the job register lets it run during the transfer of the previous packet;
in simulation, packets of 256 bytes leave the output without a gap (SE-PF-01).

## 5. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `S_Tx_Valid`, `S_Tx_Ready`, `S_Tx_Last` | `NumTx_g` | in, out, in | Handshake and end of SDU per port |
| `S_Tx_Data` | `NumTx_g` x `DataWidth_g` | in | SDU bytes, port p in the bits of index p |
| `S_Tx_Keep` | `NumTx_g` x `DataWidth_g`/8 | in | Byte enables |
| `S_Tx_User` | `NumTx_g` x 28 | in | Parameters of OCTET_STRING.request (unused for Packet Service ports) |
| `M_Pkt_*` | `DataWidth_g` | out, in | Space Packets (`Valid`, `Ready`, `Data`, `Keep`, `Last`), `User`: EEP (bit 0), destination (4:1) |
| `Cfg_MaxLength`, `Cfg_RoundRobin`, `Cfg_TableInit` | 17, 1, 19 | in | Managed parameters, initial table entry |
| `Tbl_*` | | | Client B of the send APID table; `Tbl_Busy` during its initialisation |
| `Err` | `NumTx_g` + 1 events | out | Index p: send buffer of port p; index `NumTx_g`: assembly |
| `Sent` | 1 | out | A Space Packet left the output |
| `Ecc_Sec`, `Ecc_Ded` | 4 | out | ECC events: 0 data buffers, 1 descriptor buffers, 2 table reads, 3 scrubber |
| `ErrInj_Channel`, `ErrInj_Double`, `ErrInj_Valid` | 6, 1, 1 | in | Injection into the next write: channel 2p data buffer of port p, 2p + 1 its descriptor buffer, 2 `NumTx_g` table |
| `Scrub_Enable` | 1 | in | Scrubber of the table enabled |

## 6. Send APID table entry

| Bits | Field |
| --- | --- |
| 13:0 | Packet Sequence Count of the next Octet String |
| 17:14 | Destination index |
| 18 | Managed data path enabled |
