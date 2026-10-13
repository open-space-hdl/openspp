# OpenSPP Architecture

Version 0.2. This file is the reference for the architecture and is versioned with the code.

## 1 Purpose, scope and references

This document defines the architecture of OpenSPP, an implementation of the CCSDS Space Packet Protocol (SPP) with
the SpaceWire CCSDS Packet Transfer Protocol (CPTP) as its transfer layer. Together with CCSDS 133.0-B-2 and
ECSS-E-ST-50-53C it is the complete basis for the implementation: it fixes the building blocks, their interfaces, the
clauses each block owns and the Open Logic entities each block is built from.

### In scope

- Sending end of SPP: Packet Service and Octet String Service on a configurable number of user ports, validation of
  the Space Packets of the Packet Service, assembly of Space Packets from Octet Strings with a Packet Sequence Count
  per APID or a Packet Name, multiplexing of the user ports and transfer of every packet along the managed data path
  of its APID (SPP 4.2).
- Receiving end of SPP: reception and validation of Space Packets, demultiplexing by APID to the user ports,
  delivery of intact Space Packets (Packet Service) or of Octet Strings with the Secondary Header Indicator (Octet
  String Service), Packet Loss and Data Loss Indicators from the continuity of the Packet Sequence Count (SPP 4.3).
- CPTP: encapsulation of every Space Packet with Target SpaceWire Address, Target Logical Address, Protocol
  Identifier, Reserved field and User Application field, and decapsulation with the checks and status codes of the
  target (CPTP 5.3 to 5.5). A generic removes the layer, so that SPP runs over any other subnetwork.
- Managed parameters (SPP section 5, CPTP Annex A), error information, counters and product information in a register
  file behind an AXI4-Lite port; fault tolerance; the verification architecture.
- An adapter between the link stream of the core and the N-Char packet stream of the OpenWire core.

### Out of scope

- The SpaceWire and SpaceFibre ports. OpenSPP connects to their packet ports, to a SpaceWire port of OpenWire through
  the N-Char adapter.
- The Space Data Link Protocols (TM, TC, AOS, Proximity-1, USLP) and the generation of Idle Packets, which is a
  function of these protocols (SPP 4.1.2.2 note 3).
- The contents of the Packet Secondary Header (time code, ancillary data): the sending user supplies the secondary
  header at the start of the Octet String and the receiving user interprets it (SPP 3.4.2.3, 4.1.4.2.1.4).
- Several qualities of service (optional QoS Requirement parameter, SPP 3.3.2.4): the core offers one quality of
  service.
- Other SpaceWire protocols. A received packet with a Protocol Identifier other than 2 is discarded and counted. When
  OpenSPP shares a SpaceWire port with OpenRMAP, it connects to the user port of OpenRMAP, which carries all packets
  except RMAP.

### Target technology

OpenSPP contains no vendor code. All buffers and tables are Open Logic fault-tolerant entities, all data interfaces
are AXI4-Stream and the management interface is AXI4-Lite. The core runs on any FPGA.

### Project

OpenSPP is an open CCSDS Space Packet Protocol implementation that is based on the Open Logic VHDL Library. The code
lives in [open-space-hdl/openspp](https://github.com/open-space-hdl/openspp) under the PSI HDL Library License,
Version 1.0, the licence of Open Logic. Open Logic is pinned to the tag `4.7.0-ft.2` of the branch `fault-tolerant`
of open-space-hdl/open-logic-ft, the fault-tolerant fork of Open Logic.

### References

| ID | Document | Version used |
| --- | --- | --- |
| \[SPP\] | CCSDS 133.0-B-2, Space Packet Protocol, Recommended Standard, Issue 2 | June 2020, with Editorial Changes 1 (October 2020) and 2 (September 2024) |
| \[CPTP\] | ECSS-E-ST-50-53C, SpaceWire: CCSDS packet transfer protocol | 5 February 2010 |
| \[PID\] | ECSS-E-ST-50-51C, SpaceWire protocol identification | 5 February 2010 |
| \[SPW\] | ECSS-E-ST-50-12C Rev.1, SpaceWire: Links, nodes, routers and networks | 15 May 2019 |
| \[OLO\] | [Open Logic, fault-tolerant fork, branch fault-tolerant](https://github.com/open-space-hdl/open-logic-ft/tree/fault-tolerant) | 4.7.0-ft.2 |

### Conventions

- Clause references name the standard: SPP for CCSDS 133.0-B-2 and CPTP for ECSS-E-ST-50-53C, for example
  SPP 4.1.3.4.3.4 or CPTP 5.5.4.3a. A range such as CPTP 5.3.2 to 5.3.6 means all requirements of those clauses.
- Coding conventions: those of Open Logic (naming, two-process style, synchronous high-active resets, VSG rules),
  entity prefix `spp_`, VHDL library `openspp`; see [conventions.md](conventions.md).
- "FT" (fault-tolerant) means the Open Logic `olo_ft_*` entities: SECDED ECC on every buffer and table.

| Term | Meaning |
| --- | --- |
| SDU | Service data unit: a Space Packet (Packet Service) or an Octet String (Octet String Service), SPP 3.2 |
| SAP | Service access point; in OpenSPP a user port |
| APID | Application Process Identifier, 11 bits (SPP 4.1.3.3.4) |
| PDL | Packet Data Length field: number of octets of the Packet Data Field minus one (SPP 4.1.3.5) |
| SHF, SHI | Secondary Header Flag (SPP 4.1.3.3.3), Secondary Header Indicator (SPP 3.4.2.3) |
| Managed data path | Path of the packets of one APID from the source to the destination users, configured by management (SPP 2.1.1) |
| Idle Packet | Space Packet with the APID 2047 (all ones), SPP 4.1.3.3.4.4 |
| CPTP packet | SpaceWire packet that carries one Space Packet behind the CPTP header (CPTP 5.4) |
| Destination | Target SpaceWire Address, Target Logical Address and User Application value of a CPTP packet |
| Beat | One transfer of a stream of `DataWidth_g` bits |
| Link stream | Packet stream of the link ports: `DataWidth_g` bits, `TKeep`, `TLast`, error end of packet flag in `TUser` |
| N-Char stream | Packet stream of the OpenWire core: one data character per beat, the end of packet marker as a separate beat with `TLast` = '1' (`TData(0)` = '0' EOP, '1' EEP) |

## 2 Space Packet Protocol functional overview

SPP carries application data in Space Packets that are identified by their APID (SPP 2.1). The APID is the only
address of the protocol: it names the managed data path of a packet from its source user application to its
destination user applications, and every property of a path, from the Packet Sequence Count to the destination in the
subnetwork, belongs to one APID. The services are preconfigured, unidirectional, asynchronous, unconfirmed, incomplete
and not sequence-preserving (SPP 2.2.1).

SPP offers two services (SPP 2.2.2). The Packet Service transfers Space Packets that the user has formatted, intact
and without changes. The Octet String Service transfers strings of octets; the protocol entity builds the Packet
Primary Header from the parameters of the request and removes it again at the receiving end. At the sending end the
Packet Assembly Function builds packets from Octet Strings and the Packet Transfer Function multiplexes all packets and
hands them to the subnetwork by APID (SPP 4.2). At the receiving end the Packet Reception Function demultiplexes the
packets by APID and the Packet Extraction Function returns Octet Strings to their users (SPP 4.3).

CPTP is the subnetwork service on SpaceWire: each Space Packet travels in one SpaceWire packet behind a Target
SpaceWire Address, the Target Logical Address, the Protocol Identifier 2, a Reserved byte and a User Application byte
(CPTP 5.4). The target discards packets that end with an error end of packet or have a non-zero Reserved field and
informs its user (CPTP 5.5.4). SpaceFibre carries SpaceWire packets unchanged, so the same layer serves both networks.

| Function | Clauses |
| --- | --- |
| Service data units: Space Packet and Octet String | SPP 3.2 |
| Packet Service: parameters and primitives | SPP 3.3 |
| Octet String Service: parameters and primitives | SPP 3.4 |
| Space Packet format | SPP 4.1 |
| Sending end: Packet Assembly and Packet Transfer | SPP 4.2 |
| Receiving end: Packet Reception and Packet Extraction | SPP 4.3 |
| Managed parameters | SPP 5, CPTP Annex A |
| Protocol implementation conformance statement | SPP Annex A |
| CPTP service parameters and primitives | CPTP 5.1, 5.2 |
| CPTP fields and packet format | CPTP 5.3, 5.4 |
| CPTP actions of initiator and target | CPTP 5.5 |

Four properties of the standards shape the architecture more than any single feature:

- **The length precedes the data.** The PDL of the Packet Primary Header is sent before the Packet Data Field, so an
  Octet String must be complete before its packet can start. The sending end buffers every SDU completely.
- **A packet is checked before it is delivered.** CPTP discards packets with an error end of packet or a non-zero
  Reserved field (CPTP 5.5.4.3a, 5.5.4.4a), and the PDL can only be compared with the received length at the end of
  the packet. The receiving end buffers every packet completely and discards it on any error, so that a user never
  receives a partial or inconsistent packet.
- **The APID is the only address.** The Packet Sequence Count (SPP 4.1.3.4.3.3), the destination at the sending end
  (SPP 4.2.3.3) and the user at the receiving end (SPP 4.3.3.2) are functions of the APID. The core keeps a table entry
  for each of the 2048 APIDs, so that every APID works without allocation and no packet is lost to a full table.
- **The Packet Sequence Count is continuous per APID** (SPP 4.1.3.4.3.4). The counts live in ECC-protected and
  scrubbed memory, survive any error of other paths and restart only with the reset of the core.

## 3 Design drivers

| Driver | Consequence |
| --- | --- |
| Use in space: single event upsets in buffers, tables and registers | SECDED ECC on every buffer and table, background scrubbing of the APID tables, state machines with a recovery state, an EDAC monitor in the register file (P5) |
| Throughput of multi-lane SpaceFibre links and of instrument data | Wide streams of up to 128 bits and one beat per clock cycle on every path (P6) |
| Integration with SpaceWire and SpaceFibre ports | Link stream with an error end of packet flag, N-Char adapter for OpenWire, removable CPTP layer (P7) |
| Many data sources and users in one node | A configurable number of user ports, a selectable multiplexing scheme and APID routing (P8) |
| Technology independence | AXI4-Stream and AXI4-Lite interfaces, no vendor primitive (P11) |
| Verifiability | Every block verified through its ports against an independent model of SPP and CPTP (P9, section 9) |
| Reuse | Every generic function comes from Open Logic; custom logic is limited to SPP and CPTP (P10) |

## 4 Design goals

| Goal | Implementation |
| --- | --- |
| Defined handshakes between blocks | Every internal data path is a valid / ready stream or a stream of one-cycle events (P2) |
| One protocol function per block | A block implements one function of the standards; no clause is owned by two blocks (P1) |
| No partial or inconsistent packet at any output | Store-and-forward at both ends; a rejected SDU or a discarded packet leaves no beat at any port (D4) |
| Deterministic error reporting | One fixed order of the checks and one counter per reason (D8, D10) |
| Fault tolerance | FT buffers and tables, scrubbing, safe state machines, contained double errors (P5) |
| One management interface | All managed parameters in a register file behind one AXI4-Lite port (P4) |
| Tests independent of the design hierarchy | Tests observe only ports and the register file (section 9) |

## 5 Design principles

| ID | Principle | Rule for the implementation |
| --- | --- | --- |
| P1 | One protocol function per block | A block implements one function of SPP or CPTP. Its specification names the clauses it owns; no clause is owned by two blocks. |
| P2 | Streams everywhere | Every data path between blocks is a valid / ready stream (Open Logic AXI4-Stream conventions) or a valid-only stream of events. |
| P3 | One clock domain | All blocks run in `Clk`. Clock domain crossings of the SpaceWire or SpaceFibre port stay in the port. |
| P4 | One management interface | All configuration, status and error information lives in one register file behind one AXI4-Lite port, generated from a single register description (VHDL package, documentation, C header). |
| P5 | Fault tolerance by construction | All buffers and tables are `olo_ft_*` entities (SECDED ECC); the APID tables are scrubbed. State machines have a defined recovery state. ECC events are counted in the register file; a double error is contained and never delivered as valid data. |
| P6 | Line rate | Every path accepts one beat per clock cycle while its output is ready. Header insertion and removal realign the bytes in place; there is no width conversion inside the core. |
| P7 | Link format of the network ports | The link ports carry whole packets with `TKeep` and an error end of packet flag; an adapter converts them to the N-Char stream of OpenWire. |
| P8 | User ports are service access points | One service type per port, fixed by a generic. The APID and the other parameters of the primitives travel in `TUser`. |
| P9 | Verifiable in isolation | Each module has a specification and a testbench that drives only its ports. The SPP and CPTP model of the testbenches is written independently of the RTL. |
| P10 | Reuse before design | A function available in Open Logic (FIFO, packet FIFO, RAM, arbiter, AXI4-Lite slave, ECC monitor, width converter) is instantiated, not rewritten. |
| P11 | No vendor code | The core has no vendor primitive. |

## 6 Architecture overview

![Architecture overview of spp_core: the sending end (SE-1 to SE-3, TB-1) and the receiving end (RE-1 to RE-3,
TB-2) between the user ports and the transfer layer (EN-1, EN-2), with the register file (MG-1, MG-2) in the
middle](img/spp_core_overview.drawio.svg)

At the sending end each user port has a buffer that checks every SDU while it arrives and holds complete SDUs. The
multiplexer selects the next complete SDU, the packet assembly takes the Packet Sequence Count and the destination from
the send APID table and builds the Packet Primary Header of an Octet String (a Space Packet passes unchanged), and the
encapsulation puts the packet into a CPTP packet. At the receiving end the decapsulation checks and removes the CPTP
header, the reception buffers and validates the complete Space Packet, the demultiplexer finds the user port of its
APID in the receive APID table and checks the continuity of the Packet Sequence Count, and the packet extraction
removes the Packet Primary Header for the ports of the Octet String Service.

### Data formats of the ports

User ports carry one SDU per packet of the stream: `TLast` marks the last beat, `TKeep` the valid bytes. All bytes of a
beat are valid except in the last beat, whose valid bytes are contiguous from byte lane 0. Byte lane 0 (`TData(7:0)`)
holds the first byte of the beat; the first byte of an SDU is the first byte transmitted on the network.

`TUser` of a send port (`S_Tx`), constant during an SDU:

| Bits | Field | Service | Clause |
| --- | --- | --- | --- |
| 10:0 | APID | Octet String | SPP 3.4.2.2 |
| 11 | Secondary Header Indicator | Octet String | SPP 3.4.2.3 |
| 12 | Packet Type: '0' telemetry, '1' telecommand | Octet String | SPP 3.4.3.2.2, 4.1.3.3.2 |
| 13 | Packet Name valid: bits 27:14 are used instead of the Packet Sequence Count | Octet String | SPP 4.1.3.4.3.2 |
| 27:14 | Packet Name | Octet String | SPP 4.1.3.4.3 |

A port of the Packet Service does not use `TUser`: the APID parameter of PACKET.request is the APID in the header of
the submitted Space Packet (SPP 3.1 leaves the representation of parameters to the implementation).

`TUser` of a receive port (`M_Rx`):

| Bits | Field | Service | Clause |
| --- | --- | --- | --- |
| 10:0 | APID | both | SPP 3.3.2.2, 3.4.2.2 |
| 11 | Secondary Header Indicator | Octet String | SPP 3.4.2.3 |
| 12 | Packet Loss Indicator (Packet Service), Data Loss Indicator (Octet String) | both | SPP 3.3.2.3, 3.4.2.4 |
| 13 | Error: the receive buffer reported a double bit error in this SDU, valid with `TLast` | both | none (P5) |
| 21:14 | User Application value of the CPTP packet | both | CPTP 5.2.3.2 |

`TUser` of the link ports: bit 0 is the error end of packet flag, valid with `TLast` ('0' EOP, '1' EEP). `M_Link_TUser`
also carries the destination index of the packet in its upper bits, so that a subnetwork other than SpaceWire can
route by it when the CPTP layer is removed.

### Architecture decisions

| ID | Decision | Reason |
| --- | --- | --- |
| D1 | One clock domain `Clk` for all functions, including the register file | The SpaceWire and SpaceFibre ports already cross from their link clocks to their user clock; a second crossing adds latency and FT crossings without benefit |
| D2 | User ports are AXI4-Stream ports of `DataWidth_g` bits (8 to 128, a multiple of 8) with `TKeep` and `TUser`; their number (`NumTx_g`, `NumRx_g`) and the service type of each port (`TxOctetString_g`, `RxOctetString_g`) are generics | A port is a service access point (P8); a fixed service per port lets synthesis remove the unused function and makes the format of each port unambiguous |
| D3 | The link ports use the same width with `TKeep` and an error end of packet flag in `TUser`; the adapter `spp_nchar` converts them to and from the N-Char stream of OpenWire | One beat per clock on wide SpaceFibre interfaces; EOP and EEP stay distinguishable, as CPTP requires (CPTP 5.5.4.4) |
| D4 | Store-and-forward at both ends: every send port checks its SDUs while they arrive, buffers complete SDUs in an `olo_ft_fifo_packet` (data only) and records length and request parameters in an `olo_ft_fifo_sync` of descriptors; the receiving end does the same with every packet. A failed SDU or packet is dropped from the buffer (`In_Drop`). A preparation stage takes the next descriptor and accesses the APID table while the previous packet is transferred. Buffer sizes are generics; the maximum packet length is a register, limited by the buffers | The PDL must be known before the header is sent; validation before delivery; CPTP discards erroneous packets (CPTP 5.5.4.3a, 5.5.4.4a); a rejected SDU never blocks the link; the table access does not cost throughput |
| D5 | Two APID tables with one entry per APID (2048 entries) in `olo_ft_ram_sdp_scrub`: the send table holds the Packet Sequence Count, the path enable and the destination index; the receive table holds the path enable, the user port, the continuity check enable and the last received count. After the reset the tables are initialised with a default entry; the register file reads and writes every entry | Sequence counts for every APID without allocation (SPP 4.1.3.4.3.3); the APID selects the managed data path (SPP 4.2.3.3, 4.3.3.2); SECDED and scrubbing keep long-lived entries correct |
| D6 | The multiplexer passes complete SDUs, one at a time, in fixed priority (port 0 first) or round robin; the scheme is a register | The Packet Multiplexing Scheme is a managed parameter (SPP 4.2.3.2, Table 5-1); complete SDUs keep each packet contiguous |
| D7 | `NumDest_g` destinations in the register file, each with a Target SpaceWire Address of 0 to `SpwAddrBytes_g` bytes, a Target Logical Address and a User Application value; the send APID table selects the destination of each APID | The Packet Transfer Function identifies the receiving entity by the APID (SPP 4.2.3.3); an indirection keeps the APID table narrow |
| D8 | One order of the checks at the receiving end: the decapsulation checks that a byte follows the CPTP header, the Protocol Identifier, the Reserved field and the Target Logical Address filter; the reception checks the error end of packet, the minimum length, the Packet Version Number, the length against PDL, the maximum packet length and the Idle APID; the demultiplexer checks the table entry, the path and user port and the Sequence Flags of an Octet String port. The first failed check discards the packet and is counted; an error end of packet takes precedence over every other reason | A fixed order makes the reported reason deterministic and testable |
| D9 | The Packet Loss and Data Loss Indicators are generated per APID when the continuity check of the APID is enabled: a count other than the last count plus one (modulo 16384) sets the indicator; the first packet after the initialisation or after enabling the check sets none | The indicators are optional and declared at design time (SPP 3.3.2.3); paths of telecommand packets that carry a Packet Name are excluded by management |
| D10 | Every rejected SDU and every discarded packet increments a counter of its reason and produces a one-cycle event (`Err_*`: reason, port, APID) and an interrupt | The user application is informed (CPTP 5.5.2c, 5.5.4.3b, 5.5.4.4b) without polling |
| D11 | A double bit error in a send buffer ends the CPTP packet with an EEP; in the receive buffer it sets the error bit of the receive port. A double error in a descriptor or an APID table entry discards the SDU or packet. All are counted by the EDAC monitor. The EEP and error flags are defined with the last beat only | A corrupted packet is never delivered as valid (P5) |
| D12 | Idle Packets (APID 2047) are accepted by the Packet Service only with the SHF '0' and by the Octet String Service only with the SHI '0'; received Idle Packets are discarded and counted unless the register file enables their delivery | SPP 4.1.3.3.3.4; Idle Packets carry no user data (SPP 4.1.4.3.4) |
| D13 | Header insertion and removal shift the bytes of a stream by a number of bytes that is constant during a packet, in one stage that keeps one beat per clock | Line rate without width conversion (P6) |
| D14 | The protocol state machines have a defined recovery state, without TMR: the `when others` branch leads to it from an illegal state where the synthesis tool implements the state machine safe, and the reset input restarts it from any state | Same as OpenWire and OpenRMAP; a corrupted packet is discarded by the checks of the receiving end |

### Clock and reset

All blocks run in `Clk`. The reset input `Rst` is synchronous and high-active (Open Logic convention); the integrator
synchronises it to `Clk`, for example with `olo_base_reset_gen` and `SyncTmr_g = true`. After the reset the core
initialises the APID tables (2048 clock cycles); meanwhile the send buffers accept SDUs, and packets are sent and
delivered once the tables are ready.

### Internal interfaces

| Interface | Between | Payload | Protocol |
| --- | --- | --- | --- |
| SDU stream | User ports, SE-1, RE-3 | Space Packet or Octet String with request or indication parameters | AXI4-Stream |
| Packet stream | SE-2, SE-3, EN-1, EN-2, RE-1, RE-2 | Space Packet with its side information (port, destination, User Application value, error end) | AXI4-Stream |
| Link stream | EN-1, EN-2 and the link ports | CPTP packet or Space Packet, error end of packet flag (D3) | AXI4-Stream |
| Table access | SE-3 and TB-1, RE-2 and TB-2, MG-1 and both tables | Read and read-modify-write of one APID entry | Valid / ready |
| Error event | All checks to MG-1 | Reason, port, APID | Valid-only event |
| Register bus | MG-1 and the user | Configuration, status, counters | AXI4-Lite (`olo_axi_lite_slave`) |

## 7 Building block specifications

The core has 14 building blocks in five groups. Each block lists its responsibility, the Open Logic entities it is
built from and the clauses it owns (P1: no clause is owned twice).

### 7.1 Sending end

| ID | Block | Responsibility | Open Logic | Clauses |
| --- | --- | --- | --- | --- |
| SE-1 | Send buffer (one per send port) | Accepts PACKET.request or OCTET_STRING.request, checks the SDU while it arrives (length against the maximum packet length and the buffer; for a Space Packet minimum length, version, length against PDL, Idle Packet rules; for an Octet String Idle and Packet Name rules), stores accepted SDUs completely and records length and request parameters | `olo_ft_fifo_packet`, `olo_ft_fifo_sync` | SPP 3.2.2, 3.2.3.1, 3.2.3.4, 3.3.2.1, 3.3.2.2, 3.3.3.2, 3.4.2.1, 3.4.2.2, 3.4.3.2; CPTP 5.1.1, 5.1.2, 5.5.2 |
| SE-2 | Multiplexer | Selects the next complete SDU among the send buffers by fixed priority or round robin and passes it as one unit | `olo_base_arb_prio`, `olo_base_arb_rr` | SPP 4.2.3.2 |
| SE-3 | Packet assembly | Destination and path enable of the APID from TB-1; Octet String: Packet Primary Header (version, type, SHF from the SHI, APID, Sequence Flags '11', Packet Sequence Count or Packet Name, PDL) followed by the Octet String; Space Packet passed intact | `spp_header_insert` | SPP 3.2.3.2, 3.2.3.3, 3.3.1, 3.4.1, 3.4.2.3, 4.1.2, 4.1.3, 4.1.4.1, 4.1.4.3, 4.2.2, 4.2.3.3 |
| TB-1 | Send APID table | Packet Sequence Count, path enable and destination index per APID; initialisation after reset, read-modify-write for SE-3, access for MG-1, scrubbing | `olo_ft_ram_sdp_scrub` | SPP 4.1.3.4.3.3, 4.1.3.4.3.4 |

### 7.2 Receiving end

| ID | Block | Responsibility | Open Logic | Clauses |
| --- | --- | --- | --- | --- |
| RE-1 | Reception | Stores the complete Space Packet, checks minimum length, version, length against PDL and the maximum packet length, error end of packet; discards a failed packet and Idle Packets | `olo_ft_fifo_packet`, `olo_ft_fifo_sync` | SPP 4.3.3.1 |
| RE-2 | Demultiplexer | User port and path enable of the APID from TB-2, continuity of the Packet Sequence Count and loss indicator, delivery of intact Space Packets to the ports of the Packet Service | none | SPP 3.3.2.3, 3.3.3.3, 3.4.2.4, 4.3.3.2, 4.3.3.3 |
| RE-3 | Packet extraction (one per receive port) | Removes the Packet Primary Header for an Octet String port and delivers OCTET_STRING.indication with the SHI from the SHF; a Packet Service port receives the Space Packet intact; registered output per port | `spp_header_remove` | SPP 3.4.3.3, 4.3.2 |
| TB-2 | Receive APID table | Path enable, user port, continuity check enable and last received count per APID; initialisation, access for RE-2 and MG-1, scrubbing | `olo_ft_ram_sdp_scrub` | none (storage of managed parameters) |

### 7.3 Transfer layer

| ID | Block | Responsibility | Open Logic | Clauses |
| --- | --- | --- | --- | --- |
| EN-1 | Encapsulation | Target SpaceWire Address of the destination, Target Logical Address, Protocol Identifier 2, Reserved 0, User Application value, the Space Packet, EOP or EEP | `spp_header_insert` | SPP 4.2.3.1; CPTP 5.1.4 to 5.1.6, 5.2.1, 5.2.2, 5.3, 5.4, 5.5.3 |
| EN-2 | Decapsulation | Removes leading address bytes (configurable), checks the Protocol Identifier, the Reserved field and optionally the Target Logical Address, discards failed packets, passes the Space Packet with the User Application value and the end of packet flag, status codes | `spp_header_remove` | CPTP 5.1.3, 5.2.3, 5.5.4 |

With the generic `Encapsulation_g` = false both blocks are removed: the link ports carry plain Space Packets and the
destination index travels in `M_Link_TUser`.

### 7.4 Management

| ID | Block | Responsibility | Open Logic | Clauses |
| --- | --- | --- | --- | --- |
| MG-1 | Register file | Managed parameters (maximum packet length, multiplexing scheme, destinations, Target Logical Address filter, removal of leading bytes, delivery of Idle Packets), access to both APID tables, counters per reason, error events and interrupt, product information, generated from one register description (`hdl/spp_mib/regs/spp_regs.yml`, `tools/regmap.py`) | `olo_axi_lite_slave` | SPP 5.2 |
| MG-2 | EDAC monitor | Counts the SEC and DED events of every FT buffer and table, raises an interrupt, injects single and double errors for tests | `olo_ft_ecc_monitor` | none (fault tolerance, P5) |

### 7.5 Common functions and adapter

| ID | Block | Responsibility | Open Logic | Clauses |
| --- | --- | --- | --- | --- |
| CM-1 | Header insertion | Inserts a header of a number of bytes that is constant during a packet in front of a stream with `TKeep`, one beat per clock (D13); used by SE-3 and EN-1 | none | none |
| CM-2 | Header removal | Removes a number of leading bytes that is constant during a packet, one beat per clock (D13); used by EN-2 and RE-3 | none | none |
| AD-1 | N-Char adapter (`spp_nchar`) | Converts the link stream to and from the N-Char stream of OpenWire: width conversion, EOP or EEP marker beat against `TLast` with the error end of packet flag | `olo_base_wconv_xn2n`, `olo_base_wconv_n2xn` | none (packet end of \[SPW\] 5.6) |

### Modules

A module is one group of blocks with its own specification, verification plan, testbench and verification report.

| Module | Blocks | Entities |
| --- | --- | --- |
| `spp_pkg` | Common types, constants of the header fields | `spp_pkg`, `spp_regs_pkg` (generated) |
| `spp_header` | CM-1, CM-2 | `spp_header_insert`, `spp_header_remove` |
| `spp_apid_table` | TB-1, TB-2 | `spp_apid_table` |
| `spp_send` | SE-1 to SE-3 | `spp_send`, `spp_send_buffer`, `spp_send_mux`, `spp_send_assembly` |
| `spp_receive` | RE-1 to RE-3 | `spp_receive`, `spp_receive_buffer`, `spp_receive_demux`, `spp_receive_extraction` |
| `spp_encapsulation` | EN-1, EN-2 | `spp_encapsulation`, `spp_decapsulation` |
| `spp_mib` | MG-1, MG-2 | `spp_mib` |
| `spp_core` | Top level | `spp_core` |
| `spp_nchar` | AD-1 | `spp_nchar` |

## 8 Open Logic usage

| Open Logic entity | Used in | Purpose |
| --- | --- | --- |
| `olo_ft_fifo_packet` | SE-1, RE-1 | Store-and-forward buffer of complete SDUs and packets, drop of rejected packets, ECC |
| `olo_ft_fifo_sync` | SE-1, RE-1 | Descriptor FIFO: byte length and parameters of every buffered SDU or packet |
| `olo_ft_ram_sdp_scrub` | TB-1, TB-2 | APID tables with ECC and background scrubbing |
| `olo_base_arb_prio`, `olo_base_arb_rr` | SE-2 | Multiplexing schemes |
| `olo_axi_lite_slave` | MG-1 | AXI4-Lite access to the register file |
| `olo_ft_ecc_monitor` | MG-2 | SEC and DED counters per buffer and table, DED sticky flags |
| `olo_base_wconv_xn2n`, `olo_base_wconv_n2xn` | AD-1 | Width conversion between the link stream and the N-Char stream |

### Gaps in Open Logic

| Gap | Resolution in this architecture |
| --- | --- |
| No insertion or removal of a header of N bytes on a stream with byte enables | CM-1 and CM-2 in the module `spp_header` |
| No packet-atomic stream multiplexer | SE-2: arbiter with a packet lock |
| `Out_Size` of `olo_ft_fifo_packet` counts words, not bytes | Descriptor FIFO with the byte length of every packet (SE-1, RE-1) |
| No TMR helper for protocol state machines | Recovery state of every state machine (D14) |

## 9 Verification architecture

The core is verified with VUnit and UVVM in a seven-phase module workflow (requirements, architecture, verification
plan, RTL, testbenches, verification, integration; see [conventions.md](conventions.md)). Every module of section 7
has its own specification, verification plan, testbench and verification report; core tests cross the seams between
the modules. Every test case names the requirements it verifies, and every requirement names its clauses, so the
traceability matrix of section 10 is checked by `tools/compliance.py`.

| Level | Scope | Bench | Checks |
| --- | --- | --- | --- |
| Unit | `spp_pkg`, header insertion and removal, APID table, sending end, receiving end, encapsulation, register file, N-Char adapter | `<entity>_th.vhd` (clock, DUT, models) and `<entity>_tb.vhd` (VUnit runner, one `run("test_...")` per test of the verification plan) | UVVM checks, packets compared byte by byte with the SPP and CPTP model |
| Core | Two cores connected by link models in both directions, also through two N-Char adapters per direction: every send port of one core reaches the receive ports of the other | Stream models on the user ports, an AXI4-Lite VVC on each register file, link models that drop packets, end them with an EEP or inject packets | Both services end to end, asymmetric services, routing by APID, destinations, address removal, loss indicators, every discard and rejection reason through the registers, EEP and double errors end to end, line rate, reset of one core |

### Framework

- VUnit (`run.py`) discovers and runs every test and is the CI regression. UVVM supplies the verification building
  blocks: the AXI4-Lite VVC, alert and log handling, `check_value` / `await_value`, randomisation.
- The SPP and CPTP model of the testbenches (`tb/spp_tb_packet_pkg.vhd`) builds Space Packets, Octet Strings and
  CPTP packets with its own implementation of SPP 4.1 and CPTP 5.4, independent of the RTL. Sequence counts and loss
  indicators are predicted by a reference model per APID.
- Stream source and sink models (`tb/spp_tb_stream_*.vhd`) send and check packets of any length with random stall
  cycles; the sink compares every byte, the byte enables and `TUser` of every beat, and matches packets of several
  sources to their queues. The AXI4-Stream VVC of UVVM is limited to 16 KiB per packet and therefore not used.
- The link model between two cores drops packets, ends packets with an EEP and injects packets built by the
  testbench (corrupted header fields, truncated and extended packets).
- Simulator: GHDL for every test; QuestaSim for code coverage.

### Rules

- Tests observe ports and the register file only (P9).
- A failed check fails the test; a test cannot pass with a failed step.
- Negative tests inject the fault from the bench (wrong version, length different from the PDL, oversized SDU, EEP,
  non-zero Reserved field, wrong Protocol Identifier, unrouted APID, lost packet, double error through the error
  injection of the FT buffers and tables) and expect the counter, the event or the indicator; never from an RTL
  mutation.
- Every commit passes the full regression.

## 10 Requirement traceability matrix

Every clause in the scope of section 1 has exactly one owner block. "User" marks a clause that the user of the core
fulfils; the user guide states it. "First verified at" names the lowest verification level at which the clause can be
fully checked. The [compliance matrix](compliance.md), generated from this table, the module specifications and the
verification plans, lists the requirements and test cases of every clause.

| Clause | Title | Owner | Also involved | First verified at |
| --- | --- | --- | --- | --- |
| SPP 3.2.2 | Space Packet SDU | SE-1 | SE-3, RE-1 | Unit |
| SPP 3.2.3.1 | Octet String length | SE-1 |  | Unit |
| SPP 3.2.3.2, 3.2.3.3 | Secondary header in and placement of the Octet String | SE-3 |  | Unit |
| SPP 3.2.3.4 | Use of the Octet String Service | SE-1 | RE-3 | Unit |
| SPP 3.3.1 | Packet Service | SE-3 | RE-2 | Unit |
| SPP 3.3.2.1, 3.3.2.2 | Space Packet and APID parameters | SE-1 | RE-2 | Unit |
| SPP 3.3.2.3 | Packet Loss Indicator | RE-2 | TB-2 | Unit |
| SPP 3.3.2.4 | QoS Requirement | Not implemented (one quality of service) |  | - |
| SPP 3.3.3.2 | PACKET.request | SE-1 |  | Unit |
| SPP 3.3.3.3 | PACKET.indication | RE-2 |  | Unit |
| SPP 3.4.1 | Octet String Service | SE-3 | RE-3 | Unit |
| SPP 3.4.2.1, 3.4.2.2 | Octet String and APID parameters | SE-1 | RE-3 | Unit |
| SPP 3.4.2.3 | Secondary Header Indicator | SE-3 | RE-3 | Unit |
| SPP 3.4.2.4 | Data Loss Indicator | RE-2 | RE-3 | Unit |
| SPP 3.4.3.2 | OCTET_STRING.request | SE-1 | SE-3 | Unit |
| SPP 3.4.3.3 | OCTET_STRING.indication | RE-3 |  | Unit |
| SPP 4.1.2 | Space Packet structure and length | SE-3 | RE-1 | Unit |
| SPP 4.1.3.1, 4.1.3.2 | Packet Primary Header, Packet Version Number | SE-3 | RE-1 | Unit |
| SPP 4.1.3.3.1, 4.1.3.3.2 | Packet Identification Field, Packet Type | SE-3 |  | Unit |
| SPP 4.1.3.3.3 | Secondary Header Flag | SE-3 | RE-3 | Unit |
| SPP 4.1.3.3.4 | Application Process Identifier | SE-3 | RE-1, RE-2 | Unit |
| SPP 4.1.3.4.1, 4.1.3.4.2 | Packet Sequence Control Field, Sequence Flags | SE-3 | RE-3 | Unit |
| SPP 4.1.3.4.3 | Packet Sequence Count or Packet Name | TB-1 | SE-3 | Unit |
| SPP 4.1.3.5 | Packet Data Length | SE-3 | RE-1 | Unit |
| SPP 4.1.4.1 | Packet Data Field | SE-3 | RE-1 | Unit |
| SPP 4.1.4.2 | Packet Secondary Header | User (contents of the Octet String) | SE-3 | - |
| SPP 4.1.4.3 | User Data Field | SE-3 |  | Unit |
| SPP 4.2.2 | Packet Assembly Function | SE-3 | TB-1 | Unit |
| SPP 4.2.3.1 | Packet Transfer Function | EN-1 | SE-3 | Unit |
| SPP 4.2.3.2 | Multiplexing of the packets | SE-2 | MG-1 | Unit |
| SPP 4.2.3.3 | Transfer by APID | SE-3 | TB-1, EN-1 | Unit |
| SPP 4.3.2 | Packet Extraction Function | RE-3 |  | Unit |
| SPP 4.3.3.1 | Packet Reception Function | RE-1 |  | Unit |
| SPP 4.3.3.2, 4.3.3.3 | Demultiplexing by APID, delivery by service type | RE-2 | TB-2, RE-3 | Unit |
| SPP 5.2 | Protocol configuration parameters | MG-1 | SE-1, SE-2, RE-1 | Core |
| CPTP 5.1.1, 5.1.2 | CCSDS packet and packet length parameters | SE-1 | RE-1 | Unit |
| CPTP 5.1.3 | Status code parameter | EN-2 | MG-1 | Unit |
| CPTP 5.1.4 to 5.1.6 | Target SpaceWire Address, Target Logical Address, User Application value | EN-1 | MG-1 | Unit |
| CPTP 5.2.1, 5.2.2 | CCSDS packet transfer service, CCSDS_PACKET_SEND.request | EN-1 | SE-3 | Unit |
| CPTP 5.2.3 | CCSDS_PACKET_RECEIVED.indication | EN-2 | RE-1, RE-2 | Unit |
| CPTP 5.3 | CCSDS packet transfer protocol fields | EN-1 | EN-2 | Unit |
| CPTP 5.4 | CCSDS packet transfer protocol format | EN-1 | EN-2 | Unit |
| CPTP 5.5.2 | Send request | SE-1 | MG-1 | Unit |
| CPTP 5.5.3 | Transfer packet | EN-1 |  | Unit |
| CPTP 5.5.4.1 to 5.5.4.3 | Protocol Identifier, Reserved field zero and not zero | EN-2 | MG-1 | Unit |
| CPTP 5.5.4.4 | Error end of packet | EN-2 | RE-1 | Unit |

## 11 Development plan

1. Foundations: repository, `spp_pkg`, verification components (SPP and CPTP model, test end check), regression and
   CI.
2. Header insertion and removal (CM-1, CM-2) with unit tests of every shift and width.
3. APID table (TB-1, TB-2) with unit tests of initialisation, access arbitration, scrubbing and error injection.
4. Sending end (SE-1 to SE-3) with unit tests against the SPP model.
5. Receiving end (RE-1 to RE-3) with unit tests against the SPP model.
6. Transfer layer (EN-1, EN-2) with unit tests against the CPTP model.
7. Register file (MG-1, MG-2) with the generated register map.
8. Core top level (`spp_core`) with core tests of two cores, the compliance matrix, the synthesizability check and the
   user guide.
9. N-Char adapter (AD-1) with unit tests against the N-Char model and a core test through the adapter.
