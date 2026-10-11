# spp_header: Architecture

## 1. Principle

Both stages realign the bytes of a packet by a number of bytes that is constant during the packet. A residue register
holds the bytes that did not fit into the last output beat; every output beat is the residue followed by the bytes of
the current input beat. With `B` = `DataWidth_g` / 8 bytes per beat:

```text
 insertion, header of h bytes (h < B shown)      removal of r bytes (r < B shown)

 residue  | input beat k                         input beat k        | input beat k+1
 [h or B-o bytes][B bytes]                       [r removed][B-r bytes] [B bytes]
 output   = first B bytes                        output = residue (B-r bytes) + first r bytes of beat k+1
 residue := the other bytes                      residue := the other B-r bytes
```

A header of `B` bytes or more is output as complete header beats first; the rest of it becomes the first residue. In
the removal the first beats of a packet are consumed without output until all removed bytes are captured. When the
last input beat leaves more bytes than fit into the output beat, a flush beat follows (insertion: state `Flush_s`,
removal: state `Flush_s`); this is the additional cycle of CM-RM-03. The insertion needs no extra cycle because every
beat it adds (header beats, flush beat) is an output beat.

## 2. Ports

### spp_header_insert

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `In_Valid`, `In_Ready` | 1 | in, out | Handshake of the input |
| `In_Data` | `DataWidth_g` | in | Packet bytes, lane 0 first |
| `In_Keep` | `DataWidth_g`/8 | in | Byte enables |
| `In_Last` | 1 | in | Last beat of a packet |
| `In_User` | `UserWidth_g` | in | Side information |
| `In_Header` | 8 `MaxHeaderBytes_g` | in | Header bytes, byte 0 in bits 7:0; sampled with the first beat |
| `In_HeaderBytes` | log2(`MaxHeaderBytes_g`+1) | in | Header length; sampled with the first beat |
| `Out_*` | as the input | out, in | Output stream (`Valid`, `Ready`, `Data`, `Keep`, `Last`, `User`) |

### spp_header_remove

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `In_*` | as above | in, out | Input stream (`Valid`, `Ready`, `Data`, `Keep`, `Last`, `User`) |
| `In_RemoveBytes` | log2(`MaxRemoveBytes_g`+1) | in | Number of bytes to remove; sampled with the first beat |
| `Out_*` | as above | out, in | Output stream (`Valid`, `Ready`, `Data`, `Keep`, `Last`, `User`) |
| `Out_Header` | 8 `MaxRemoveBytes_g` | out | Removed bytes, valid with every output beat |
| `Out_Empty` | 1 | out | The packet had no byte beyond the removed ones (single beat, `Keep` zero) |

## 3. State machines

```text
 insertion                                         removal

 Idle_s --header >= B bytes--> Header_s            Idle_s --first beat--> Data_s --last beat--> Idle_s
   |  <--last beat----+          |                   |                       |
   |                  |          | header < B bytes  +--last beat------------+--residue left--> Flush_s
   +--first beat--> Data_s <-----+                                                                |
                      | last beat, residue left                                         Idle_s <--+
                      v
                   Flush_s --> Idle_s
```

Both stages have a registered output beat: a new beat is computed when the output register is empty or is being
read. The input is accepted in the same cycle (`In_Ready` follows `Out_Ready` combinationally), so that consecutive
stages keep one beat per cycle. The `when others` branch returns to `Idle_s`; the reset clears the output register.

## 4. Resources

The shift is a multiplexer of `B` inputs per output byte; it depends only on the residue count, which is constant
during a packet except in the first beats of a removal. The insertion holds `MaxHeaderBytes_g` header bytes, the
removal the removed bytes, both a residue of `B` bytes and one output beat.
