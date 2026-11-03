# spp_core: Specification

## 1. Overview

`spp_core` is the top level of OpenSPP: the sending end (`spp_send`), the receiving end (`spp_receive`), the transfer
layer of ECSS-E-ST-50-53C (`spp_encapsulation`, `spp_decapsulation`, removable by a generic), the register file
(`spp_mib`) and the link output stage (`spp_link_output`, LK-1) in one clock domain. Its requirements cover what only
the assembled core shows: the plumbing of the generics, the wiring between the modules, the two resets and the
end-to-end behaviour between two cores. The protocol functions are specified in the modules.

## 2. Requirements

### 2.1 Interfaces and configuration

| ID | Requirement | Clauses |
| --- | --- | --- |
| CO-IF-01 | The core shall provide `NumTx_g` send ports and `NumRx_g` receive ports of the services selected per port, one transmit and one receive link port, an AXI4-Lite register port, an interrupt and an error event output, all in the clock domain `Clk` with the synchronous resets `Rst` and `DpRst`. | SPP 4.2.3.1, 4.3.3.1 |
| CO-IF-02 | With `Encapsulation_g` = true the link ports shall carry CPTP packets; with false they shall carry the Space Packets, the destination index in `TUser` of the transmit link, and the received packets shall have the User Application value 0. | CPTP 5.4 |
| CO-IF-03 | After the reset every APID shall have an enabled managed data path to destination 0 and to receive port 0 when `TxPathDefault_g` and `RxPathDefault_g` are true, and none when they are false. | SPP 4.2.3.3, 4.3.3.2 |
| CO-IF-04 | After the reset and the initialisation of the APID tables, no register that feeds the arithmetic or the conversions of the data paths shall hold an undefined value, also while the core is idle; a last beat without byte enables at a send port or at the receive link port shall end the SDU or packet without a beat without bytes at an output. | SPP 4.1.4.1.2; none (D15, D16) |

### 2.2 System behaviour

| ID | Requirement | Clauses |
| --- | --- | --- |
| CO-SY-01 | Space Packets and Octet Strings submitted at one core shall be delivered at the receive ports of their APIDs at another core connected through the link ports, in both directions at the same time, with the Packet Service and the Octet String Service on either side, with the User Application value of the destination and the continuity of the Packet Sequence Count. | SPP 2.2.2.1, 3.3.1, 3.4.1, 4.2.3.3, 4.3.3.3 |
| CO-SY-02 | A Target SpaceWire Address of the destination shall be transmitted in front of the CPTP header and removed by the receiving core with its `RX_STRIP` setting. | CPTP 5.3.1 |
| CO-SY-03 | Every rejection at the sending end and every discard at the receiving end of a core shall be counted in its register file, set its event flags and interrupt and appear on its error event output; a packet lost or ended with an EEP on the link, and a double error in a send buffer, shall be detected by the receiving core. | SPP 3.3.2.3; CPTP 5.5.2c, 5.5.4.4 |
| CO-SY-04 | The managed parameters written through the register file (maximum length, destinations, APID tables, Target Logical Address filter, error injection) shall take effect in the modules. | SPP 5.2 |
| CO-SY-05 | Back-to-back Octet Strings of 1024 bytes shall pass from one core to another with at most three clock cycles per packet in addition to the link beats. | none (P6) |
| CO-SY-06 | A reset of one core with `DpRst` while packets travel in both directions, or with `Rst` while no packet is open on its link output, shall not stop the other core: the other core shall keep sending and delivering, shall discard and count the packet that the reset core ended with an EEP, and shall indicate the discontinuity of the counts of the reset core, which restart at 0; the reset core shall send and deliver again after the initialisation of its APID tables. | SPP 4.1.3.4.3.4; CPTP 5.5.4.4 |
| CO-SY-07 | Two cores shall exchange packets through two `spp_nchar` adapters and an N-Char stream in each direction, including the end of packet markers EOP and EEP. | CPTP 5.4.1.8 |
| CO-SY-08 | A send port shall take one beat per clock cycle while its buffer has room. Back-to-back packets of `N` link beats shall leave the link output, be taken at the link input and be delivered at their receive port within max(`N` + 1, 5) clock cycles per packet, also when two send ports alternate. With fixed priority the lower send port shall be served first, with round robin the ports shall alternate. | none (P6) |

### 2.3 Generics

B is `DataWidth_g` / 8, the bytes of a beat. The buffers store complete SDUs and packets (store and forward) in an
Open Logic packet FIFO whose depth in beats is a power of two.

| ID | Requirement | Clauses |
| --- | --- | --- |
| CO-GN-01 | The core shall work with every value of `DataWidth_g` (8 to 128 in steps of 8), of `NumTx_g`, `NumRx_g` and `NumDest_g` (1 to 16) and of `SpwAddrBytes_g` (0 to 16): every send port, destination and receive port shall carry SDUs, and a Target SpaceWire Address of the maximum length shall be transmitted. The registers GENERICS, SERVICES, TX_BUFFER and RX_BUFFER shall show the generics, and CONFIG and MAX_LENGTH shall reset to `RoundRobin_g`, `Tla_g` and `MaxLength_g`. | SPP 4.2.3.1, 4.3.3.1; CPTP 5.3.1 |
| CO-GN-02 | `TxBufferBytes_g` and `RxBufferBytes_g` shall hold at least max(2, nextpow2(ceil(7 / B))) beats, and the elaboration shall stop with a message otherwise. Reason: the shortest Space Packet has 7 bytes, so a smaller buffer rejects or discards every SDU of the Packet Service and every received packet; the packet FIFO needs two entries. | SPP 4.1.2.2 |
| CO-GN-03 | `TxBufferBytes_g` shall hold at most nextpow2(`TxMaxPackets_g` x ceil(65542 / B)) beats and `RxBufferBytes_g` at most nextpow2(`RxMaxPackets_g` x ceil(65542 / B)) beats, and the elaboration shall stop with a message otherwise. Reason: the packet FIFO holds at most `MaxPackets_g` packets of at most 65542 bytes, so the beats above this bound are never written. | SPP 4.1.2.2 |
| CO-GN-04 | `TxMaxPackets_g` shall be 2 to max(2, `TxBufferBytes_g` / B) and `RxMaxPackets_g` 2 to max(2, floor(`RxBufferBytes_g` / B / ceil(7 / B))), and the elaboration shall stop with a message otherwise. Reason: the packet FIFO needs two entries (one packet read, one written); an Octet String of one byte takes one beat of a send buffer and a received Space Packet at least ceil(7 / B) beats, so more entries are never used. | SPP 4.1.2.2 |

### 2.4 Resets

The core has two synchronous, high-active reset inputs. `Rst` resets the whole core. `DpRst` (data path reset) resets
every function except the link output stage LK-1, which ends a packet that is open on `M_Link` with an EEP, so that
the link and the node at its far end stay in operation while the core restarts.

Terms of this section:

- A reset input is applied at a rising edge of `Clk` at which it is sampled '1'. Its reset edge is an edge at which it
  is applied after an edge at which it was not. The core is in reset from the first reset edge of either input up to
  the release edge, the first edge after it at which neither input is applied.
- A beat is transferred at an edge when `M_Link_Valid` and `M_Link_Ready` are '1' in the clock cycle that ends with
  that edge. A beat is pending at an edge when `M_Link_Valid` is '1' in that cycle and the beat is not transferred.
- A packet is open at an edge when its first beat was presented (`M_Link_Valid` '1') in the cycle that ends with the
  edge or earlier and its last beat (`M_Link_Last` '1') has not been transferred at that edge or earlier.

| ID | Requirement | Clauses |
| --- | --- | --- |
| CO-RS-01 | The core shall have the input `DpRst`, synchronous to `Clk`, high-active, with the default value '0'. A `DpRst` applied at a single edge (one clock cycle) shall have the full effect of CO-RS-02 to CO-RS-06; a longer `DpRst` shall have the same effect. `DpRst` may be applied alone, or before, together with or after `Rst`, and either input may be released first. | none (D18) |
| CO-RS-02 | `DpRst` shall reset every function of the core except the link output stage, with the effect of `Rst`: the send buffer of every port (the SDU being received and every complete SDU whose packet has not started on `M_Link` are discarded), the multiplexer, the packet assembly, the encapsulation, the decapsulation, the receive buffer (every packet in it is discarded), the demultiplexer, the packet extraction of every receive port, both APID tables, the register file and the EDAC monitor. After the release edge both APID tables shall be initialised again with the entries of `TxPathDefault_g` and `RxPathDefault_g` (every Packet Sequence Count 0, every last received count invalid) within 2048 clock cycles, `TABLE_STATUS.TX_BUSY` and `RX_BUSY` shall read '1' until the initialisation is complete, and every register shall read its reset value of the register map (counters and event flags 0), as after `Rst`. | none (D18) |
| CO-RS-03 | `DpRst` shall not reset the link output stage. A beat pending at the reset edge of `DpRst` shall stay presented with unchanged `M_Link_Data`, `M_Link_Keep`, `M_Link_Last` and `M_Link_User` until it is transferred (AXI4-Stream, Arm IHI 0051B 2.2.1). The link output stage shall take no beat of the blocks in front of it at the reset edge or later until the end of the packet open at the reset edge has been transferred and `DpRst` is released. | none (D18) |
| CO-RS-04 | When a packet is open at the reset edge of `DpRst` and the beat pending at that edge, if any, is not its last beat, the link output stage shall end the packet with exactly one EEP beat: `M_Link_Data` all '0', `M_Link_Keep` with byte lane 0 only, `M_Link_Last` '1', `M_Link_User(0)` '1' (EEP) and `M_Link_User(4:1)` the destination index of the packet. It shall present the EEP beat in the cycle after the reset edge, or, when a beat is pending at the reset edge, in the cycle after the transfer of that beat, whether `DpRst` is still applied or not, and keep it presented until it is transferred. | \[SPW\] 5.6.2.1c, 5.6.8.12d; CPTP 5.5.3, 5.5.4.4 |
| CO-RS-05 | No beat of a packet that is open at the reset edge of `DpRst` shall follow its EEP beat or its last beat. The byte of the EEP beat is a fill byte in front of the end of the packet: a port that sends the valid bytes of a last beat before its end of packet marker (a SpaceWire or SpaceFibre port, for example a virtual channel of OpenFibre) delivers the bytes transferred before the reset edge, the fill byte 0x00 and the EEP, and no byte of the packet after the EEP. After the end of that packet, `M_Link_Valid` shall stay '0' up to the first packet of an SDU whose first beat a send port took after the release edge, and `M_Link` shall carry only such packets. | CPTP 5.5.3 |
| CO-RS-06 | When no packet is open at the reset edge of `DpRst`, or the beat pending at that edge is the last beat of the open packet, the link output stage shall present no EEP beat: a pending last beat ends its packet unchanged. | CPTP 5.5.3 |
| CO-RS-07 | `Rst` shall reset the whole core including the link output stage and take precedence over `DpRst`: from the cycle after a reset edge of `Rst`, `M_Link_Valid` shall be '0' and the link output stage shall hold no beat, also when `DpRst` is applied at the same edge or before it. A packet open at that edge is cut: it gets neither its last beat nor an EEP beat, and an EEP beat that is pending at that edge is withdrawn. | none (D18) |
| CO-RS-08 | For every order of the two inputs the core shall leave the reset at the release edge, the later of the two releases: `DpRst` applied alone behaves as in CO-RS-02 to CO-RS-06; from a reset edge of `Rst` on, CO-RS-07 applies, and no EEP beat follows up to the release edge. In particular, `Rst` and `DpRst` applied together, and `DpRst` released one or more cycles after `Rst` (as at the power-up of a system whose data path reset is the OR of its system reset and a command), shall present no beat on `M_Link` before the first packet of CO-RS-05. | none (D18) |
| CO-RS-09 | Send ports: from the cycle after the reset edge of `Rst` or `DpRst` as long as a reset input is '1', `S_Tx_Ready` of every send port shall be '0'. After the release edge the next beat taken at a send port shall be the first beat of an SDU. | none (D18) |
| CO-RS-10 | Link input: from the cycle after the reset edge of `Rst` or `DpRst` as long as a reset input is '1', the core shall take no packet from `S_Link`: with `Encapsulation_g` true `S_Link_Ready` shall be '1' and every beat shall be discarded, with false `S_Link_Ready` shall be '0'. Beats and packets discarded during the reset shall not be counted. After the release edge the next beat taken at `S_Link` shall be the first beat of a packet: the rest of a packet interrupted by the reset is checked as a packet of its own and, when it fails a check, discarded and counted once with the reason of the first failed check (D8). | SPP 4.3.3.1; CPTP 5.5.4.1 to 5.5.4.4 |
| CO-RS-11 | Receive ports, register port and events: from the cycle after the reset edge of `Rst` or `DpRst` as long as a reset input is '1', `M_Rx_Valid` of every receive port, `S_AxiLite_ArReady`, `S_AxiLite_AwReady`, `S_AxiLite_WReady`, `S_AxiLite_BValid`, `S_AxiLite_RValid`, `Irq` and `Err_Valid` shall be '0'; an SDU that a receive port is delivering at the reset edge ends without its last beat. | none (D18) |
| CO-RS-12 | The interfaces shall belong to these reset domains: `M_Link` to `Rst` only; `S_Tx`, `M_Rx`, `S_Link`, `S_AxiLite`, `Irq` and `Err` to `Rst` and `DpRst`. The sources of `S_Tx` and the sinks of `M_Rx` are reset together with `DpRst` (user guide, integration constraints), the link side with `Rst` only. | none (D18) |

Reset domains of the interfaces (CO-RS-12), the basis of the reset groups of a system:

| Interface | Reset by | Behaviour at `DpRst` |
| --- | --- | --- |
| `M_Link_*` | `Rst` | Not reset: a pending beat stays, an open packet ends with an EEP beat (CO-RS-03 to CO-RS-06) |
| `S_Link_*` | `Rst`, `DpRst` | Reset: `S_Link_Ready` '1' with the CPTP layer (beats discarded), '0' without it (CO-RS-10) |
| `S_Tx_*` | `Rst`, `DpRst` | Reset: `S_Tx_Ready` '0'; the source is reset together with the core (CO-RS-09) |
| `M_Rx_*` | `Rst`, `DpRst` | Reset: `M_Rx_Valid` '0', an SDU in delivery ends without its last beat; the sink is reset together with the core (CO-RS-11) |
| `S_AxiLite_*`, `Irq`, `Err_*` | `Rst`, `DpRst` | Reset: no ready, no response, no event; every register returns to its reset value (CO-RS-02, CO-RS-11) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of all streams |
| `NumTx_g`, `NumRx_g` | 1 | 1 to 16 | Send and receive ports |
| `TxOctetString_g`, `RxOctetString_g` | all '1' | 16 bits | Service per port: '1' Octet String, '0' Packet Service |
| `TxBufferBytes_g`, `RxBufferBytes_g` | 4096 | B times a power of two; CO-GN-02, CO-GN-03; at most 2^29 beats (asserted, not elaborated) | Buffer of each send port, of the reception |
| `TxMaxPackets_g`, `RxMaxPackets_g` | 8 | CO-GN-04 | SDUs and packets a buffer holds |
| `Encapsulation_g` | true | boolean | CPTP layer of ECSS-E-ST-50-53C |
| `NumDest_g` | 1 | 1 to 16 | Destinations |
| `SpwAddrBytes_g` | 4 | 0 to 16 | Maximum Target SpaceWire Address |
| `MaxLength_g` | 65542 | 7 to 65542 | Reset value of the maximum packet length |
| `RoundRobin_g` | '0' | std_logic | Reset value of the multiplexing scheme |
| `Tla_g` | 0xFE | 8 bits | Reset value of the own Target Logical Address of the filter |
| `TxPathDefault_g`, `RxPathDefault_g` | true | boolean | Initial managed data paths of all APIDs |
| `ClkFreqHz_g` | 100.0e6 | real | Frequency of `Clk`; it has no effect, because the scrubbers of the APID tables run free (Open Logic `ScrubPeriod_g` = 0.0) |

## 4. Interpretation of the standard

| Clause | Interpretation |
| --- | --- |
| CPTP 5.5.3; \[SPW\] 5.6.2.1c | A CPTP packet whose transfer the initiator cannot complete, because `DpRst` resets the data path while the packet is on the link, ends with an EEP, as a routing switch ends a stuck packet (\[SPW\] 5.6.8.12d). The target discards it (CPTP 5.5.4.4a). |
| SPP 4.1.3.4.3.4 | `DpRst` restarts the Packet Sequence Counts at 0 like `Rst`; a receiving end with the continuity check enabled indicates the discontinuity (decision D9). |
