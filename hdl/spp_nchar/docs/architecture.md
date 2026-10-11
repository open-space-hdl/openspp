# spp_nchar: Architecture

## 1. Block diagram

![Block diagram of spp_nchar: transmit direction (link beats to N-Chars with end markers) and receive direction
(N-Chars to link beats)](img/spp_nchar_arch.drawio.svg)

## 2. Transmit direction

`olo_base_wconv_xn2n` splits every link beat into its bytes; `S_Link_Keep` is its word enable, so only the valid bytes
of the last beat are sent. When the last beat of a packet enters the converter, its EEP flag is stored and the input is
blocked until the marker of that packet is sent. After the converter outputs the last byte, the adapter outputs the
marker (`TData` 0x00 for EOP, 0x01 for EEP, `TLast` = '1'). The destination index of `S_Link_User` is not used: on
SpaceWire the Target SpaceWire Address routes the packet.

## 3. Receive direction

The adapter holds one data character back until the next character shows whether it is the last one: a data character
passes the held one on, the marker passes it on with `In_Last` to `olo_base_wconv_n2xn`, which outputs the last beat
with its word enables as byte enables. The EEP flag of the marker is stored and output with the last beat. At 8 bits
the converter is a direct connection, so the flag is taken from the marker in the same cycle. A marker without a held
character (a packet without data) is consumed and discarded.

## 4. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `S_Link_*` | `DataWidth_g` | in, out | From the core (`M_Link`): `Valid`, `Ready`, `Data`, `Keep`, `Last`, `User` (5 bits, EEP in bit 0) |
| `M_NChar_*` | 8 | out, in | To the SpaceWire port: `Valid`, `Ready`, `Data`, `Last` (marker) |
| `S_NChar_*` | 8 | in, out | From the SpaceWire port |
| `M_Link_*` | `DataWidth_g` | out, in | To the core (`S_Link`): `Valid`, `Ready`, `Data`, `Keep`, `Last`, `User` (EEP) |
