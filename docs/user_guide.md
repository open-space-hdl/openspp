# OpenSPP User Guide

This guide describes how to integrate the OpenSPP core `spp_core` into an FPGA design: sources, generics, clock and
reset, interfaces, the programming sequence, the protection scope, the performance, the integration constraints and
the conformance statement for CCSDS 133.0-B-2 (Annex A, PICS proforma) and ECSS-E-ST-50-53C. The architecture is
described in [architecture.md](architecture.md), the registers in the generated
[register map](../hdl/spp_mib/docs/register_map.md).

## 1. Sources

| Library | Sources | Order |
| --- | --- | --- |
| `olo` | Open Logic areas `base`, `axi` and `ft` of the submodule `open-logic/` | `open-logic/compile_order.txt` |
| `openspp` | `hdl/<module>/src/*.vhd` of every module of `component_list.txt` | `compile_order.txt`: the modules in the order of `component_list.txt`, within a module packages first |

All sources are VHDL-2008 and contain no vendor primitive. `spp_nchar` is needed only to connect a SpaceWire port with
an N-Char stream, such as the OpenWire core.

## 2. Generics

| Generic | Default | Description |
| --- | --- | --- |
| `DataWidth_g` | 32 | Width of all streams in bits: 8 to 128, a multiple of 8 |
| `NumTx_g`, `NumRx_g` | 1 | Send and receive ports (1 to 16) |
| `TxOctetString_g`, `RxOctetString_g` | all '1' | Service of each port, bit p for port p: '1' Octet String Service, '0' Packet Service |
| `TxBufferBytes_g` | 4096 | Buffer of each send port in bytes: `DataWidth_g` / 8 times a power of two. An SDU longer than the buffer is rejected |
| `TxMaxPackets_g` | 8 | SDUs a send buffer holds (at least 2) |
| `RxBufferBytes_g` | 4096 | Receive buffer in bytes, shared by all receive ports: `DataWidth_g` / 8 times a power of two. A packet longer than the buffer is discarded |
| `RxMaxPackets_g` | 8 | Packets the receive buffer holds (at least 2) |
| `Encapsulation_g` | true | CPTP layer of ECSS-E-ST-50-53C; false removes it (section 4.3) |
| `NumDest_g` | 1 | Destinations of the CPTP layer (1 to 16) |
| `SpwAddrBytes_g` | 4 | Maximum Target SpaceWire Address of a destination in bytes (0 to 16) |
| `MaxLength_g` | 65542 | Reset value of the Maximum Packet Length in bytes (7 to 65542) |
| `RoundRobin_g` | '0' | Reset value of the Packet Multiplexing Scheme: '0' fixed priority (port 0 first), '1' round robin |
| `Tla_g` | 0xFE | Reset value of the own Target Logical Address of the receive filter |
| `TxPathDefault_g`, `RxPathDefault_g` | true | Initial entries of the APID tables: true enables the managed data path of every APID to destination 0 and to receive port 0, false disables all paths |
| `ClkFreqHz_g` | 100.0e6 | Clock frequency, passed to the scrubbers of the APID tables (they run in every idle cycle) |

With the defaults every APID has an enabled path after the reset, so a node sends and receives without software. A
flight configuration sets `TxPathDefault_g` and `RxPathDefault_g` to false and enables the managed data paths of the
mission by software.

## 3. Clock and reset

All of the core runs in `Clk`; there is no clock domain crossing. `Rst` is synchronous and high-active (Open Logic
convention); synchronise its release to `Clk`, for example with `olo_base_reset_gen` and `SyncTmr_g = true`. After
the reset the core initialises both APID tables (2048 clock cycles, `TABLE_STATUS.TX_BUSY` and `RX_BUSY`). The send
ports accept SDUs meanwhile; packets are sent and delivered once the tables are ready.

Every path takes one beat per clock cycle while its output is ready; section 7 gives the clock cycles per packet. At
100 MHz and 32 bits the link ports carry up to 3.2 Gbit/s in each direction.

## 4. Interfaces

All data interfaces are AXI4-Stream ports with `TKeep`. A packet of the stream is one SDU or one packet: `TLast`
marks its last beat, all bytes of a beat are valid except in the last beat, whose valid bytes are contiguous from
byte lane 0. Byte lane 0 (`TData(7:0)`) holds the first byte of the beat, and the first byte of a packet is the first
byte transmitted on the network. At the inputs (send ports, `S_Link`) a last beat without valid bytes (AXI4-Stream
null bytes) is accepted: it ends the SDU or packet, which consists of the bytes of the earlier beats. The outputs
never carry a beat without valid bytes. An SDU without any byte is rejected (0x02, SPP 3.2.3.1 and 4.1.4.1.2). Port
p of a vector port uses the bits p of `Valid`, `Ready` and `Last` and the slice p of `Data`, `Keep` and `User`.

### 4.1 Send ports (`S_Tx_*`)

A send port of the Octet String Service takes OCTET_STRING.request: the Octet String (1 to 65536 bytes, including a
Packet Secondary Header that the user places at its start) and the parameters in `TUser`, held constant during the
SDU:

| Bits | Field | Clause |
| --- | --- | --- |
| 10:0 | APID | SPP 3.4.2.2 |
| 11 | Secondary Header Indicator | SPP 3.4.2.3 |
| 12 | Packet Type: '0' telemetry, '1' telecommand | SPP 3.4.3.2.2, 4.1.3.3.2 |
| 13 | Packet Name valid: bits 27:14 are used instead of the Packet Sequence Count (telecommand only) | SPP 4.1.3.4.3.2 |
| 27:14 | Packet Name | SPP 4.1.3.4.3 |

The core builds the Packet Primary Header with version '000', the Sequence Flags '11', the Packet Sequence Count of
the APID from the send APID table (or the Packet Name) and the Packet Data Length.

A send port of the Packet Service takes PACKET.request: a complete Space Packet that the user has formatted
(7 to 65542 bytes). It is sent intact; `TUser` is not used, the APID is the one in the packet header.

Every SDU is checked while it arrives and buffered completely before it is sent. A rejected SDU is dropped from the
buffer, counted and reported (section 4.5); it never reaches the link.

### 4.2 Receive ports (`M_Rx_*`)

A receive port of the Packet Service delivers PACKET.indication: the intact Space Packet. A receive port of the Octet
String Service delivers OCTET_STRING.indication: the Packet Data Field without the Packet Primary Header. `TUser`,
constant during the SDU:

| Bits | Field | Clause |
| --- | --- | --- |
| 10:0 | APID | SPP 3.3.2.2, 3.4.2.2 |
| 11 | Secondary Header Indicator (Octet String Service) | SPP 3.4.2.3 |
| 12 | Packet Loss Indicator (Packet Service) or Data Loss Indicator (Octet String Service) | SPP 3.3.2.3, 3.4.2.4 |
| 13 | Error: double bit error in the receive buffer during this SDU; valid with `TLast` | none |
| 21:14 | User Application value of the CPTP packet (0 without the CPTP layer) | CPTP 5.2.3 |

The loss indicator is set when the continuity check of the APID is enabled (`RX_TABLE_ENTRY.CHECK`) and the Packet
Sequence Count is not the last count plus one (modulo 16384). The first packet after the reset or after the check is
enabled sets no indicator. Disable the check for paths of telecommand packets that carry a Packet Name.

### 4.3 Link ports (`M_Link_*`, `S_Link_*`)

The link ports carry one packet of the network per stream packet, at the width `DataWidth_g`. `TUser` bit 0 is the
error end of packet flag, valid with `TLast` ('0' EOP, '1' EEP). With `Encapsulation_g` true the packets are CPTP
packets: Target SpaceWire Address (0 to `SpwAddrBytes_g` bytes), Target Logical Address, Protocol Identifier 0x02,
Reserved 0x00, User Application value, Space Packet. `M_Link_User(4:1)` carries the destination index of the packet in
both configurations, so a subnetwork other than SpaceWire can route by it when the CPTP layer is removed.

Connect the link ports to the packet ports of a SpaceFibre port, or through `spp_nchar` to a SpaceWire port with an
N-Char stream (section 4.6). A received packet may start with path address bytes that the network has not removed;
`CONFIG.RX_STRIP` removes up to 15 leading bytes in front of the CPTP header.

### 4.4 Register file and interrupt

`S_AxiLite_*` is an AXI4-Lite slave with an 11-bit byte address and 32-bit registers; `Irq` is the OR of the enabled
event flags. The register map is in [register_map.md](../hdl/spp_mib/docs/register_map.md), the C header in
`sw/spp_regs.h`. A read of `TX_TABLE_ENTRY` or `RX_TABLE_ENTRY` waits until a pending table access is complete.

### 4.5 Error event output

`Err_Valid` is a one-cycle event for every rejected SDU and every discarded packet, with the reason in `Err_Code`, the
send or receive port in `Err_Port` (0 when unknown) and the APID in `Err_Apid` (0 when unknown). Each reason has a
counter in the register file (`ERR_TX1` to `ERR_RX6`); `LAST_ERROR` holds the last event.

| Code | Reason | Code | Reason |
| --- | --- | --- | --- |
| 0x01 | SDU longer than the maximum packet length or the buffer | 0x10 | Packet ended with an EEP (CPTP status 0x01) |
| 0x02 | Space Packet shorter than 7 bytes, or Octet String without any byte | 0x11 | Protocol Identifier other than 2 |
| 0x03 | Packet Version Number not '000' | 0x12 | Reserved field not zero (CPTP status 0x02) |
| 0x04 | Length not the Packet Data Length plus 7 | 0x13 | Target Logical Address not accepted |
| 0x05 | Idle Packet with SHF or SHI set | 0x14 | Shorter than the CPTP header or than 7 bytes |
| 0x06 | Packet Name for a telemetry packet | 0x15 | Packet Version Number not '000' |
| 0x07 | APID without enabled managed data path | 0x16 | Length not the Packet Data Length plus 7 |
| 0x08 | Double error in the descriptor or the table entry | 0x17 | Longer than the maximum packet length or the buffer |
| | | 0x18 | Idle Packet |
| | | 0x19 | APID without enabled managed data path or with an invalid port |
| | | 0x1A | Sequence Flags other than '11' for an Octet String port |
| | | 0x1B | Double error in the descriptor or the table entry |

The receiving end checks in a fixed order (architecture, decision D8): the CPTP header (0x14, 0x11, 0x12, 0x13), then
the Space Packet (0x14 to 0x18), then the APID table (0x1B, 0x19, 0x1A). The first failed check decides; an EEP
takes precedence over every other reason.

### 4.6 N-Char adapter (`spp_nchar`)

`spp_nchar` converts the link stream to the N-Char stream of the OpenWire core and back: one data character per beat,
the end of packet marker as a separate beat with `TLast` = '1' (`TData(0)` = '0' EOP, '1' EEP). It has the generic
`DataWidth_g` of the core. A received marker without data characters is discarded. A link packet that ends with a
beat without valid bytes gets its marker after the bytes of the earlier beats; a link packet without any byte sends
nothing.

## 5. Programming sequence

1. After the reset wait until `TABLE_STATUS.TX_BUSY` and `RX_BUSY` are '0'.
2. Read `ID` (0x53505001), `GENERICS`, `SERVICES`, `TX_BUFFER` and `RX_BUFFER` to identify the core and its
   configuration.
3. Write `MAX_LENGTH` and `CONFIG` (multiplexing scheme, Idle Packet delivery, Target Logical Address filter,
   `RX_STRIP`).
4. CPTP layer: write each destination n (`DEST_CTRL` with Target Logical Address, User Application value and address
   length, `DEST_ADDR0` to `DEST_ADDR3`).
5. Managed data paths, for every APID of the sending end: write the APID to `TX_TABLE_APID`, read `TX_TABLE_ENTRY`,
   write `TX_TABLE_ENTRY` (`ENABLE`, `DEST`, `COUNT`), read `TX_TABLE_ENTRY` again. The same sequence with
   `RX_TABLE_APID` and `RX_TABLE_ENTRY` (`ENABLE`, `PORT`, `CHECK`) configures the receiving end. Each read waits for
   the preceding access, so no write is lost; `TABLE_STATUS.TX_OVERRUN` and `RX_OVERRUN` flag a write that arrived
   while an access was pending.
6. Write `IRQ_EN` for the events of interest and clear `EVENTS` by writing ones.
7. In operation read the counters (cleared by a write), `LAST_ERROR`, `ECC_STATUS` and `ECC_COUNT` (channel selected
   by `ECC_SELECT`). `SCRUB.ENABLE` controls the scrubbers of the APID tables.

A write of `TX_TABLE_ENTRY` replaces the whole entry including the Packet Sequence Count. Change the entry of an APID
while its source sends nothing, or the count of a packet sent between the read and the write is used again.

## 6. Protection scope

The core is designed for radiation environments together with the triple modular redundancy (TMR) of the synthesis
tool, like the Open Logic ft entities it is built on. It protects the parts in the first rows itself and relies on
TMR for all other logic:

| Part | Protection | Indication and test |
| --- | --- | --- |
| Data and descriptor buffers of every send port and of the receiving end (`olo_ft_fifo_packet`, `olo_ft_fifo_sync`); send and receive APID tables (`olo_ft_ram_sdp_scrub`, scrubbed in idle cycles) | SECDED ECC of the Open Logic ft entities: a single error is corrected, a double error is detected and contained: in a send data buffer the packet ends with an EEP, in the receive data buffer the SDU is delivered with the error bit of `M_Rx_TUser` set; in a descriptor or an APID table entry the SDU is rejected (0x08) or the packet discarded (0x1B). A table entry with a double error stays so until it is written again | `ECC_STATUS` (double error per channel), `ECC_SELECT` and `ECC_COUNT` (SEC and DED counters per channel, channels 0 to 7), `EVENTS.ECC_SEC` and `ECC_DED` with `Irq`, `Err_*` with 0x08 and 0x1B; error injection through the `ECC_INJECT` register |
| Clock domain crossings and reset synchronisers | None in the core: it runs in one clock domain, and the release of `Rst` is synchronised outside the core (section 3). Use triplicated synchronisers there (`SyncTmr_g` = true, for example `olo_base_reset_gen`): three synchroniser chains and a majority voter. Their registers carry the Synplify attribute `syn_radhardlevel` = `none`, so the TMR of the synthesis tool adds no voters between the stages | none |
| State machines | Recovery state through the `when others` branch and the reset | none |
| All other logic: registers of the control and data paths, counters, pointers, pipeline registers | TMR of the synthesis tool (for example `syn_radhardlevel` = `tmr` with Synplify, or the equivalent setting of the tool chain). The core adds no protection of its own for this logic; without TMR, an upset in it is not covered | synthesis report |

The integrator:

- enables the TMR of the synthesis tool for the core and the logic around it,
- checks in the synthesis report that TMR was applied, that the synchroniser chains of the crossings were not
  triplicated a second time, and that no register-based storage meant to be protected by TMR was inferred as a RAM
  primitive,
- requests safe state machines, so that synthesis keeps the `when others` branches (AMD Vivado: property
  `FSM_SAFE_STATE` = `default_state` on the state registers; Synplify: attribute `syn_encoding` = `safe`),
- protects the configuration memory of SRAM-based FPGAs by scrubbing; this is part of the FPGA design, not of the
  core.

The ECC paths are verified in simulation by error injection. Whether the protection as a whole meets the
requirements of a mission is shown by a radiation test with the core in operation (TRL 5).

## 7. Performance

The figures are clock cycles of `Clk` for back-to-back packets of one length without stalls at the outputs, with
B = `DataWidth_g` / 8 bytes per beat. They follow from the design and are measured by the core test TC-CO-12 at 32,
64 and 128 bits ([verification report](../hdl/spp_core/docs/verification_report.md)). All rates scale with the
frequency of `Clk`; the core has no clock ratio constraint.

### 7.1 Packet lengths

| Length | Bytes |
| --- | --- |
| Space Packet `Lsp` | Octet String plus 6 (Packet Primary Header); at a Packet Service port the SDU itself |
| Link packet `Llink` | With the CPTP layer `Lsp` + 4 + `A` (Target Logical Address, Protocol Identifier, Reserved, User Application value; `A` address bytes of the destination, 0 to `SpwAddrBytes_g`); without it `Lsp` |
| Delivered SDU | The receiving end removes `CONFIG.RX_STRIP` + 4 bytes (CPTP layer) and, at an Octet String port, the 6 bytes of the Packet Primary Header |

### 7.2 Data rate per interface

With `N` = ceil(`Llink` / B) link beats of a packet:

| Interface | Beats per clock cycle | Clock cycles per packet |
| --- | --- | --- |
| `S_Tx_*` (each send port) | 1 while its buffer has room (`TxMaxPackets_g` SDUs, `TxBufferBytes_g`) | ceil(SDU / B): no cycle between SDUs |
| `M_Link_*` | 1 during a packet | max(`N` + `e`, 5), `e` 0 or 1 (below) |
| `S_Link_*` | 1 while the receive buffer has room (`RxMaxPackets_g` packets, `RxBufferBytes_g`) | `N`, at most one cycle more for the removal of the CPTP header |
| `M_Rx_*` (the port of the packet) | 1 during an SDU | max(ceil(`Lsp` / B) + 1, 5) |

Both directions therefore carry at least one packet per max(`N` + 1, 5) clock cycles. The receiving end delivers a
packet in max(ceil(`Lsp` / B) + 1, 5) cycles: the one cycle is the read of the next packet from the receive buffer.
The sending end needs `e` = 1 cycle per packet to pass from one SDU in the send buffer to the next; this cycle is
hidden (`e` = 0) when a header insertion outputs a final beat with the bytes it shifted past the last input beat. A
header of `h` bytes in front of `n` bytes does so when ceil((`n` + `h`) / B) > floor(`h` / B) + ceil(`n` / B), with
`h` = 6 for the Packet Primary Header of an Octet String and `h` = 4 + `A` for the CPTP header in front of the Space
Packet. Packet Service ports without the CPTP layer always have `e` = 1. The lower limit of five cycles per packet is
the preparation of a packet (choice of the port, descriptor, access to the APID table) at the sending end and the
lookup of the receive APID table at the receiving end; both overlap the transfer of the previous packet, so they
limit only packets of up to four link beats.

Measured cycles per packet with the CPTP layer and a destination without Target SpaceWire Address (TC-CO-12):

| Packets | 32 bits: `N` | `M_Link` | `M_Rx` | 128 bits: `N` | `M_Link` | `M_Rx` |
| --- | --- | --- | --- | --- | --- | --- |
| Octet Strings of 1 byte | 3 | 5 | 5 | 1 | 5 | 5 |
| Octet Strings of 61 bytes | 18 | 19 | 18 | 5 | 5 | 6 |
| Octet Strings of 256 bytes | 67 | 67 | 67 | 17 | 17 | 18 |
| Octet Strings of 1024 bytes | 259 | 259 | 259 | 65 | 65 | 66 |
| Space Packets of 67 bytes (Packet Service) | 18 | 19 | 18 | 5 | 6 | 6 |
| Space Packets of 1030 bytes (Packet Service) | 259 | 260 | 259 | 65 | 66 | 66 |

From end to end the slower of both ends sets the rate: at 100 MHz Octet Strings of 1024 bytes pass at 3.16 Gbit/s of
SDU data at 32 bits (259 cycles) and at 12.4 Gbit/s at 128 bits (66 cycles).

### 7.3 Several active ports

- The multiplexer chooses the next packet when the transfer of the current packet starts, among the send ports with
  a complete SDU in their buffer. A change of the port costs no cycle: two ports that alternate keep the cycles per
  packet of one port.
- Round robin (`CONFIG.ROUND_ROBIN` = '1'): the ports with a complete SDU take turns packet by packet. With `k` active
  ports each gets every `k`-th packet, so its share of the link is in proportion to the lengths of its packets
  (fair per packet, not per byte).
- Fixed priority (`CONFIG.ROUND_ROBIN` = '0'): the send port with the lowest index and a complete SDU is chosen. A port
  that always has a complete SDU blocks all higher ports; their `S_Tx_Ready` stays low once their buffers are full.
- Receiving end: all receive ports share one buffer and get their packets in the order of arrival. A receive port
  that does not take its SDU stops the delivery to all ports (section 8).

### 7.4 Latency

Both ends store and forward: a packet is sent only after the last beat of its SDU is in the send buffer, and an SDU
is delivered only after the last beat of its packet is in the receive buffer. The latency of a packet therefore
contains its own length twice, once at each end, besides the preparation and the pipeline stages.

### 7.5 N-Char adapter

`spp_nchar` converts a link packet of `n` bytes into `n` data characters and the end of packet marker, one character
per clock cycle; at widths above 8 bits one cycle separates two packets, so a packet needs at most `n` + 2 cycles. In
the receive direction the adapter takes one character per clock cycle (TC-AD-03).

## 8. Integration constraints

| Constraint | Reason |
| --- | --- |
| TMR of the synthesis tool enabled for the core | The core protects its buffers and APID tables itself and relies on TMR for all other logic (section 6) |
| Serve every receive port, or place a buffer behind a port whose user can stall for long | All receive ports share one receive buffer: a packet waits at its port and the packets behind it wait for it |
| `TxBufferBytes_g` holds the longest SDU of the port, `RxBufferBytes_g` the longest Space Packet | The core sends and delivers only complete SDUs and packets; longer ones are rejected (0x01) or discarded (0x17) |
| Hold `TUser` of a send port constant during an SDU | The parameters are recorded with the SDU |
| The user supplies the Packet Secondary Header at the start of the Octet String and keeps the Secondary Header Flag of an APID static | SPP 4.1.4.2, 4.1.3.3.3.3: the core does not interpret the secondary header |
| `Err_*` shows one event per cycle | Events of several sources in the same cycle are all counted; the output and `LAST_ERROR` show the one of the lowest source (send ports, decapsulation, receiving end) |
| The subnetwork returns `S_Link_Ready` flow control to its sender | The receiving end stalls the link while its buffer is full |
| The ECC injection (`ECC_INJECT`) is for tests only | An injected double error discards an SDU or packet or ends it with an EEP |

## 9. Conformance

### 9.1 Space Packet Protocol (CCSDS 133.0-B-2, Annex A)

OpenSPP implements the Packet Service and the Octet String Service at the sending and the receiving end. The support
column of the requirements list of the PICS proforma (Annex A2.2) for a core with ports of both services:

| Item | Description | Reference | Status | Support |
| --- | --- | --- | --- | --- |
| SPP-1 | Space Packet SDU | 3.2.2 | M | Yes |
| SPP-2 | Octet String SDU | 3.2.3 | M | Yes |
| SPP-3 | APID (Packet Service) | 3.3.2.2 | M | Yes |
| SPP-4 | Packet Loss Indicator | 3.3.2.3 | O | Yes, per APID (`RX_TABLE_ENTRY.CHECK`) |
| SPP-5 | QoS Requirement | 3.3.2.4 | O | No: one quality of service |
| SPP-6 | Octet String | 3.4.2.1 | M | Yes, 1 to 65536 bytes |
| SPP-7 | APID (Octet String Service) | 3.4.2.2 | M | Yes |
| SPP-8 | Secondary Header Indicator | 3.4.2.3 | M | Yes |
| SPP-9 | Data Loss Indicator | 3.4.2.4 | O | Yes, per APID (`RX_TABLE_ENTRY.CHECK`) |
| SPP-10 | PACKET.request | 3.3.3.2 | M | Yes |
| SPP-11 | PACKET.indication | 3.3.3.3 | M | Yes |
| SPP-12 | OCTET_STRING.request | 3.4.3.2 | M | Yes |
| SPP-13 | OCTET_STRING.indication | 3.4.3.3 | M | Yes |
| SPP-14 | Space Packet | 4.1 | M | Yes |
| SPP-15 | Packet Primary Header | 4.1.3 | M | Yes |
| SPP-16 | Packet Data Field | 4.1.4 | M | Yes |
| SPP-17 | Packet Secondary Header | 4.1.4.2 | C1 | Yes, supplied by the user in the Octet String |
| SPP-18 | User Data Field | 4.1.4.3 | C2 | Yes |
| SPP-19 | Packet Assembly Function | 4.2.2 | M | Yes |
| SPP-20 | Packet Transfer Function | 4.2.3 | M | Yes |
| SPP-21 | Packet Extraction Function | 4.3.2 | M | Yes |
| SPP-22 | Packet Reception Function | 4.3.3 | M | Yes |
| SPP-23 | Maximum Packet Length (octets) | Table 5-1 | M | Yes: 7 to 65542 (`MAX_LENGTH`), limited by the buffers |
| SPP-24 | Packet Type of Outgoing Packets | Table 5-1 | M | Yes: per Octet String in `TUser` (Table 5-1 note 2), in the header of a Space Packet of the Packet Service |
| SPP-25 | Packet Multiplexing Scheme | Table 5-1 | O | Yes: fixed priority or round robin (`CONFIG.ROUND_ROBIN`) |
| SPP-26 | Service Type | Table 5-1 | M | Yes: per port (`TxOctetString_g`, `RxOctetString_g`); the APID tables assign each APID to a port |

The Packet Secondary Header Contents (Table 5-1) are agreed between the users by management; the core passes them
unchanged. The interpretations of the standard are listed in the sections "Interpretation of the standard" of the
module specifications, for example that the APID parameter of PACKET.request is the APID of the submitted packet.

### 9.2 CCSDS packet transfer protocol (ECSS-E-ST-50-53C)

With `Encapsulation_g` true the core is initiator and target of the CCSDS packet transfer protocol:

| Clauses | Function | Implementation |
| --- | --- | --- |
| 5.1, 5.2 | Service parameters and primitives | CCSDS_PACKET_SEND.request is the transfer of a Space Packet of the sending end with the destination of its APID; CCSDS_PACKET_RECEIVED.indication is the delivery at a receive port with the User Application value in `TUser`; status codes 0x01 and 0x02 are the error events 0x10 and 0x12 |
| 5.3, 5.4 | Fields and format | Target SpaceWire Address of 0 to `SpwAddrBytes_g` bytes, Target Logical Address and User Application value per destination, Protocol Identifier 0x02, Reserved 0x00 |
| 5.5.2 | Send request | A request with a packet longer than the maximum is rejected and reported (0x01) |
| 5.5.3 | Transfer packet | One CPTP packet per Space Packet, ended with an EOP (an EEP after a double error in the send buffer) |
| 5.5.4 | Receive packet | Packets ended with an EEP or with a Reserved field other than zero are discarded and reported to the user (error events, counters, interrupt); packets with another Protocol Identifier are discarded and reported as well; the Target Logical Address filter is optional (`CONFIG.TLA_CHECK`) |
| Annex A | Managed parameters | Minimum Space Packet length 7 bytes (fixed, SPP 4.1.2); maximum Space Packet size `MAX_LENGTH` |

The [compliance matrix](compliance.md) lists the requirements and the test cases of every clause.

## 10. Verification and tools

```shell
python run.py -p 4                          # regression with GHDL
python run.py --questa -p 1                 # regression with QuestaSim, full optimisation
python run.py --questa --coverage -p 1      # code coverage with QuestaSim
python lint/lint.py                         # VSG
python lint/synth_check.py                  # synthesizability of five core configurations with GHDL
python tools/compliance.py --check          # traceability of SPP and CPTP
python tools/regmap.py --check              # generated register map up to date
python run.py --compile-order               # compile_order.txt of the synthesis sources
```
