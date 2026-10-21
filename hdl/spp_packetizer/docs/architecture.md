# spp_packetizer: Architecture

## 1. Block diagram

![Block diagram of spp_packetizer: segmenter with hold register and CRC, segment buffer and descriptor FIFO,
packet output with the header insertion and the CRC trailer](img/spp_packetizer_arch.drawio.svg)

The packetizer has an input side and an output side, coupled by two FIFOs with SECDED protection. The input side
cuts the data units into segments and writes every segment into the segment buffer (`olo_ft_fifo_packet`) and its
descriptor into the descriptor FIFO (`olo_ft_fifo_sync`). The output side takes the next complete segment, builds its
headers, and passes the segment through the header insertion (`spp_header_insert`) and the CRC trailer to the output.

## 2. Input side: segmenter

### 2.1 Hold register

The segmenter holds the latest accepted beat of a data unit in a hold register until the next beat shows how the data
unit continues. A beat is written into the segment buffer when the next beat of the input is accepted, or in the next
clock cycle when the held beat carries `Last` itself. This answers two questions that the last data beat cannot
answer alone:

- Is a full segment the last one of its data unit? A segment of `ChunkBytes_g` bytes whose last beat has no `Last`
  is the last segment only if the next beat is a last beat without byte enables (PT-SG-04).
- Where does a data unit end that ends with a last beat without byte enables (PT-IF-04, D15)? The held beat becomes
  the last beat of the segment; the beat without bytes is not written.

When the held beat is written, `In_Last` of the segment buffer marks the end of a segment: the beat completes
`ChunkBytes_g` bytes, or it is the last data beat of its data unit. Writing the held beat and accepting the next
beat happen in the same clock cycle, so the input accepts one beat per clock cycle while the buffer has room.

A data unit without any byte (a last beat without byte enables while the hold register is empty) is discarded.
`Aborted` is '1' for one clock cycle when a last beat with `S_Error` = '1' is accepted, with or without bytes.

### 2.2 Segment length and CRC

A byte counter counts the bytes of the current segment: `DataWidth_g`/8 for every beat except the last beat of a
data unit, whose bytes follow from `S_Keep`. With `Crc_g` set, `olo_base_crc` processes every beat written into the
segment buffer (`In_Last` at the end of a segment, `In_Be` the byte enables of the beat) with the parameters of
PT-CR-01: `Polynomial_g` = x"1021", `InitialValue_g` = x"FFFF", `BitOrder_g` = "MSB_FIRST", `ByteOrder_g` =
"LSB_FIRST" (byte lane 0 first). The CRC of a segment is available one clock cycle after its last beat; the
descriptor is therefore written one clock cycle after the last beat of its segment, with or without CRC.

### 2.3 Descriptor

| Bits | Field | Content |
| --- | --- | --- |
| 15:0 | Length | Number of bytes of the segment minus one (0 to 65535) |
| 16 | First | The segment is the first one of its data unit |
| 17 | Last | The segment is the last one of its data unit |
| 33:18 | CRC | CRC of the segment, bit 15 first transmitted (only with `Crc_g`) |

The descriptor FIFO has `MaxChunks_g` entries, as many as the segment buffer has packets. A descriptor is read when
the header of its packet is built, before the segment leaves the buffer, so the descriptor FIFO always has room for
the descriptor of a segment the buffer accepted.

### 2.4 Segment buffer

`olo_ft_fifo_packet` with `Width_g` = `DataWidth_g`, `Depth_g` = `BufferBytes_g` / (`DataWidth_g`/8) and
`MaxPackets_g` = `MaxChunks_g`. It works store and forward: a segment is visible at the output only when its last
beat is written. Its packet boundaries are held in flip-flops (`SmallRamStyle_g` = "registers"), outside the
SECDED code, so a double error in a data word never changes the framing. The buffer frees the space of a segment when
the segment has been read completely; with `BufferBytes_g` = 2 × `ChunkBytes_g` the next segment is written while the
packet before it leaves.

## 3. Output side

### 3.1 Packet control

| State | Action | Next state |
| --- | --- | --- |
| `Idle_s` | Waits for a complete segment in the buffer and its descriptor. When both are present: `Hdr_Sample` = '1', the header register takes the Packet Primary Header and `SecHdr_Data`, the CRC register takes the CRC, the descriptor is read and the count is incremented | `Data_s` |
| `Data_s` | Passes the beats of the segment from the buffer to the header insertion; `Keep` is all ones except for the last beat, whose valid bytes follow from the length | `Idle_s` after the last beat, and in the same cycle the header of the next packet when its segment is complete |
| `others` | Recovery | `Idle_s` |

The header of the next packet is taken at the earliest in the clock cycle in which the last beat of the packet
before it enters the header insertion. The insertion samples the header register with the first beat of a packet, so
the register is stable from the moment it is taken until the insertion has used it.

Packet Primary Header (`primaryHeader` of `spp_pkg`):

| Field | Value |
| --- | --- |
| Packet Version Number | '000' |
| Packet Type | `Cfg_Type` |
| Secondary Header Flag | '1' when `SecHdrBytes_g` > 0 |
| APID | `Cfg_Apid` |
| Sequence Flags | First and Last: '11'; First: '01'; Last: '10'; neither: '00' |
| Packet Sequence Count | Count register (14 bits), incremented modulo 16384 with every header |
| Packet Data Length | `SecHdrBytes_g` + Length + 1 (+ 2 with `Crc_g`) - 1 |

### 3.2 Timing of `Hdr_Sample`

```text
Clk          _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
Hdr_Sample   ___/‾‾‾\_____________
SecHdr_Data  ==X=== A ===X========     sampled at the rising edge that ends the Hdr_Sample cycle
M_Valid      ___________/‾‾‾‾‾‾‾‾‾     first beat of the packet: at the earliest two cycles later
```

`Cfg_Apid`, `Cfg_Type` and `SecHdr_Data` are sampled at the rising edge of `Clk` that ends the cycle in which
`Hdr_Sample` is '1'. The first output beat of the packet follows at the earliest in the second cycle after that
(header insertion with registered output). A user who presents a time code on `SecHdr_Data` gets the time of that
edge.

### 3.3 Header insertion

`spp_header_insert` with `MaxHeaderBytes_g` = 6 + `SecHdrBytes_g` and the constant header length 6 +
`SecHdrBytes_g`: the header register supplies the Packet Primary Header in bytes 0 to 5 and `SecHdr_Data` in the
bytes after it. The insertion shifts the segment behind the header and keeps one beat per clock cycle. `User` of the
insertion carries the CRC of the segment to the last beat of the packet.

### 3.4 CRC trailer

With `Crc_g` set, the trailer appends the two CRC bytes behind the last valid byte of every packet, bits 15:8 first.
When the last beat has room for both bytes, they fill its next lanes; otherwise the trailer adds one beat (or two at a
width of 8 bits). The trailer holds one output beat in a register and keeps one beat per clock cycle, except for the
added beat. Without `Crc_g` the trailer is not instantiated.

## 4. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `S_Valid`, `S_Ready` | 1 | in, out | Handshake of the input data units |
| `S_Data`, `S_Keep` | `DataWidth_g`, `DataWidth_g`/8 | in | Bytes and byte enables, byte lane 0 first |
| `S_Last` | 1 | in | Last beat of a data unit |
| `S_Error` | 1 | in | With `S_Last`: the data unit was aborted |
| `M_Valid`, `M_Ready` | 1 | out, in | Handshake of the output Space Packets |
| `M_Data`, `M_Keep` | `DataWidth_g`, `DataWidth_g`/8 | out | Bytes and byte enables |
| `M_Last` | 1 | out | Last beat of a Space Packet |
| `Cfg_Apid` | 11 | in | APID of the packets |
| `Cfg_Type` | 1 | in | Packet Type |
| `SecHdr_Data` | 8 × max(`SecHdrBytes_g`, 1) | in | Packet Secondary Header, bits 7:0 first byte (unused when `SecHdrBytes_g` = 0) |
| `Hdr_Sample` | 1 | out | One cycle per packet: `Cfg_*` and `SecHdr_Data` are sampled at the end of this cycle |
| `Aborted` | 1 | out | One cycle per accepted last beat with `S_Error` |
| `Ecc_Sec`, `Ecc_Ded` | 2 | out | One cycle per corrected or detected error; bit 0 segment buffer, bit 1 descriptor FIFO |
| `ErrInj_Data`, `ErrInj_Desc` | 1 | in | Inject into the next word written into the buffer or the descriptor FIFO |
| `ErrInj_Double` | 1 | in | '0': flip data bit 0 (single error), '1': data bits 0 and 1 (double error) |

The injection flips data bits, not parity bits, so a single error shows that the output uses the corrected data and
a double error shows its consequence in the packet (codeword positions 3 and 5 of the Open Logic SECDED code).

## 5. Error behaviour

| Event | Behaviour |
| --- | --- |
| Single error in a segment word or a descriptor | Corrected on reading, `Ecc_Sec` pulse when the word is read |
| Double error in a segment word | `Ecc_Ded(0)` pulse; the beat leaves as read, the packet is complete and correctly framed; with `Crc_g` the CRC at the receiver does not match |
| Double error in a descriptor | `Ecc_Ded(1)` pulse; the packet leaves with the fields as read. The number of beats comes from the segment buffer; a corrupted length can make the Packet Data Length differ from the bytes of the packet, which the length check of the send port of `spp_core` rejects (reason 0x04) |
| Aborted data unit | Segmented and sent as usual (PT-SG-03), `Aborted` pulse |
| Reset | Both FIFOs and the hold register are emptied, the state machine returns to `Idle_s`, the count to 0 |

## 6. Resources

The segment buffer is the main resource: `BufferBytes_g` bytes plus the SECDED bits of every word (for example
8 bits per 32-bit word, 9 bits per 128-bit word). The descriptor FIFO holds `MaxChunks_g` words of 18 bits, or 34
with the CRC, plus their SECDED bits.
