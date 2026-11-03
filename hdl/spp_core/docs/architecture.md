# spp_core: Architecture

## 1. Block diagram

![Block diagram of spp_core: spp_send, spp_encapsulation, spp_link_output, spp_mib, spp_decapsulation and spp_receive
with the signal groups between them](img/spp_core_arch.drawio.svg)

## 2. Wiring

| Signal group | From | To |
| --- | --- | --- |
| Space Packets with EEP and destination index (5-bit `TUser`) | `spp_send` | `spp_encapsulation`, or `spp_link_output` without the CPTP layer |
| Link packets with EEP and destination index (5-bit `TUser`) | `spp_encapsulation` | `spp_link_output` |
| Space Packets with EEP and User Application value (9-bit `TUser`) | `spp_decapsulation` or the link input (User Application value 0) | `spp_receive` |
| Maximum packet length | `spp_mib` | `spp_send`, `spp_receive` |
| Multiplexing scheme | `spp_mib` | `spp_send` |
| Destinations | `spp_mib` | `spp_encapsulation` |
| Idle delivery | `spp_mib` | `spp_receive` |
| Address removal, Target Logical Address filter | `spp_mib` | `spp_decapsulation` |
| Client B of the send and the receive APID table | `spp_mib` | `spp_send`, `spp_receive` |
| Initial table entries (`TxPathDefault_g`, `RxPathDefault_g`) | generics | `spp_send`, `spp_receive` |
| Error events: index 0 to `NumTx_g` sending end, `NumTx_g` + 1 decapsulation, `NumTx_g` + 2 and + 3 receiving end | modules | `spp_mib` |
| Packets sent, SDUs delivered per port, loss indications | `spp_send`, `spp_receive` | `spp_mib` |
| ECC events: channels 0 to 3 sending end, 4 to 7 receiving end | `spp_send`, `spp_receive` | `spp_mib` |
| Injection commands, scrubber enable | `spp_mib` | `spp_send`, `spp_receive` |
| Reset of the data path `Rst` or `DpRst` | ports | `spp_send`, `spp_encapsulation`, `spp_decapsulation`, `spp_receive`, `spp_mib` |
| `Rst` and `DpRst` | ports | `spp_link_output` |

## 3. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset of the whole core |
| `DpRst` | 1 | in | Synchronous high-active reset of the data path: every function except `spp_link_output`; default '0' |
| `S_Tx_*` | `NumTx_g` x stream | in, out | Send ports; `User` 28 bits per port (architecture of the core, section 6) |
| `M_Rx_*` | `NumRx_g` x stream | out, in | Receive ports; `User` 22 bits per port |
| `M_Link_*` | `DataWidth_g` | out, in | Transmitted packets; `User`: EEP (bit 0, last beat), destination index (4:1) |
| `S_Link_*` | `DataWidth_g` | in, out | Received packets; `User`: EEP (last beat) |
| `S_AxiLite_*` | 11-bit address | | Register file |
| `Irq` | 1 | out | Interrupt |
| `Err_Valid`, `Err_Code`, `Err_Port`, `Err_Apid` | 1, 5, 4, 11 | out | Error event output |

## 4. Resets

The core derives one internal reset of the data path, `Rst` or `DpRst` (an OR of the two synchronous inputs, no
register), and connects it to the reset inputs of `spp_send`, `spp_encapsulation`, `spp_decapsulation`, `spp_receive`
and `spp_mib`. These modules therefore see one reset that starts at the first reset edge of either input and ends at
the release edge, and behave under `DpRst` exactly as under `Rst` (specification CO-RS-02). Only the link output stage
`spp_link_output` (LK-1) takes both inputs separately: `Rst` resets it, `DpRst` makes it end an open packet.

Behaviour of the modules during the reset, which the specification requires at the ports (CO-RS-09 to CO-RS-11):

| Port | During the reset | Mechanism |
| --- | --- | --- |
| `S_Tx_Ready` | '0' | The data FIFO of each send buffer (`olo_ft_fifo_packet`) keeps its input ready '0' while its reset is applied (the FIFO of the packet ends inside the Open Logic packet FIFO has `ReadyRstState_g` = '0') |
| `S_Link_Ready`, CPTP layer | '1', beats discarded | `spp_header_remove` of the decapsulation is in its idle state with an empty output register, so it takes every beat; the reset clears what it took |
| `S_Link_Ready`, no CPTP layer | '0' | The link input is the input of the receive buffer, an `olo_ft_fifo_packet` as at the send ports |
| `M_Rx_Valid` | '0' | The output register of the packet extraction of each port is reset |
| `S_AxiLite_*` ready and valid | '0' | `olo_axi_lite_slave` resets its ready and response registers; a pending response is lost |
| `Irq`, `Err_Valid` | '0' | Registers of `spp_mib` |

After the release edge the APID tables run their initialisation of 2048 clock cycles (`spp_apid_table`, TB-FN-02),
`TABLE_STATUS.TX_BUSY` and `RX_BUSY` read '1' meanwhile, and every register of `spp_mib` holds its reset value. The
receive buffer takes beats from the first cycle after the release edge; the demultiplexer delivers them once the
receive table is ready, and the packet assembly sends once the send table is ready.

## 5. Link output stage (LK-1, `spp_link_output`)

### 5.1 Function

`spp_link_output` is the last stage of the transmit path in both configurations, behind `spp_encapsulation` or,
without the CPTP layer, behind `spp_send`. It is a register stage of one beat with a combinational ready path: it
passes one beat per clock cycle while `M_Link_Ready` is '1' and adds one clock cycle of latency, no cycle per packet.
Because `DpRst` does not reset it, it knows after the reset edge of `DpRst` which beat is on `M_Link` and whether a
packet is open, and it ends an open packet with an EEP beat of one byte (specification CO-RS-03 to CO-RS-06).

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst`, `DpRst` | 1 | in | Clock, reset of the stage, data path reset of the core |
| `S_Pkt_Valid`, `S_Pkt_Ready`, `S_Pkt_Data`, `S_Pkt_Keep`, `S_Pkt_Last` | stream | in, out | Link packets of `spp_encapsulation` or `spp_send` |
| `S_Pkt_User` | 5 | in | EEP (bit 0, with the last beat), destination index (4:1) |
| `M_Link_*` | stream, `User` 5 bits | out, in | The link output of the core, driven by the registers of the stage |

Generic: `DataWidth_g` of the core. Open Logic offers no stage with this function: `olo_base_pl_stage` with
`UseReady_g` true holds a second beat in its skid register that is not visible on the output and that the stage could
neither discard nor follow by the EEP beat, so the stage is a register of its own with the EEP multiplexer in front of
it (decision D19 of the core architecture).

### 5.2 Registers

| Register | Reset by | Content |
| --- | --- | --- |
| `OValid`, `OData`, `OKeep`, `OLast`, `OUser` | `Rst` (`OValid`) | The beat on `M_Link`; `M_Link_*` are these registers |
| `Open` | `Rst` | '1' after the transfer of a beat with `OLast` '0', '0' after the transfer of a beat with `OLast` '1': a packet has started on `M_Link` and its last beat is not transferred |
| `State` | `Rst` | `Pass_s`: forwards the beats of the core; `End_s`: ends the open packet after `DpRst` and waits for the release |

The destination index of the open packet is `OUser(4:1)` of its last transferred beat; the register keeps it after the
transfer (only `OValid` changes on a handshake).

### 5.3 Behaviour in each clock cycle

Signals of the cycle:

- `Hs` = `OValid` and `M_Link_Ready`: the beat in the register is transferred at the edge that ends the cycle.
- `Free` = not `OValid` or `M_Link_Ready`: the register can take a beat at that edge.
- `OpenNext` = `Open` when `Hs` is '0', not `OLast` when `Hs` is '1': whether a packet is open after that edge.

| State | Condition in the cycle | `S_Pkt_Ready` | At the edge that ends the cycle | Next state |
| --- | --- | --- | --- | --- |
| `Pass_s` | `DpRst` '0' | `Free` | A beat of `S_Pkt` is loaded on its handshake; otherwise `OValid` is cleared on `Hs` | `Pass_s` |
| `Pass_s` | `DpRst` '1' (its reset edge, or `DpRst` still applied after `Rst`) | '0' | As in `End_s` | `End_s` |
| `End_s` | `Free` '0' (a pending beat or EEP beat) | '0' | Nothing: the beat stays presented | `End_s` |
| `End_s` | `Free` '1' and `OpenNext` '1' | '0' | The EEP beat is loaded: `OData` 0, `OKeep` byte lane 0, `OLast` '1', `OUser` = `OUser(4:1)` & '1' | `End_s` |
| `End_s` | `Free` '1', `OpenNext` '0', `DpRst` '1' | '0' | `OValid` cleared | `End_s` |
| `End_s` | `Free` '1', `OpenNext` '0', `DpRst` '0' | '0' | `OValid` cleared | `Pass_s` |
| any | `Rst` '1' | as above | `OValid` and `Open` cleared, overriding the rows above | `Pass_s` |

`Open` takes `OpenNext` at every edge. An illegal state leads to `Pass_s` (`when others`, decision D14).

`S_Pkt_Ready` is '0' in the cycle that ends with the reset edge of `DpRst`, so the beat that the blocks in front
present in that cycle is not taken; they are reset at that edge, and the stage takes no beat until it is back in
`Pass_s`. The EEP beat is loaded at the edge at which the register becomes free, so it follows a pending beat without
a gap, and it is loaded whether `DpRst` is still applied or not. The EEP beat closes the packet (`OLast` '1'), so
`OpenNext` is '0' after its transfer and exactly one EEP beat is sent. A further reset edge of `DpRst` in `End_s`
changes nothing.

The EEP beat carries one byte because the outputs of the core never carry a beat without valid bytes (decision D15):
a SpaceWire or SpaceFibre port, the N-Char adapter and width converters can then process it like any last beat. Its
data byte 0x00 is never delivered: the target discards a packet that ends with an EEP (CPTP 5.5.4.4a).

### 5.4 Examples

Cycle `n` ends with edge `n`. Beats `b0` to `b5` form one packet; `-` means `Valid` '0'.

`DpRst` for one cycle while the link takes every beat: the packet ends with the EEP beat in the cycle after the
reset edge.

| Cycle | `DpRst` | `S_Pkt` presented | `S_Pkt_Ready` | `M_Link` presented | `M_Link_Ready` | At the edge |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 0 | `b3` | 1 | `b2` | 1 | `b2` transferred, `b3` loaded |
| 1 | 1 | `b4` | 0 | `b3` | 1 | Reset edge: `b3` transferred, `b4` not taken, EEP loaded |
| 2 | 0 | - | 0 | EEP | 1 | Release edge; EEP transferred, `Pass_s` |
| 3 | 0 | - | 1 | - | 1 | The blocks in front start again from their reset state |

`DpRst` for three cycles while the link stalls with `b3` pending: `b3` stays presented and the EEP beat follows it.

| Cycle | `DpRst` | `S_Pkt` presented | `S_Pkt_Ready` | `M_Link` presented | `M_Link_Ready` | At the edge |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 1 | `b4` | 0 | `b3` | 0 | Reset edge: `b3` pending, `End_s` |
| 1 | 1 | - | 0 | `b3` | 0 | `b3` pending |
| 2 | 1 | - | 0 | `b3` | 1 | `b3` transferred, EEP loaded |
| 3 | 0 | - | 0 | EEP | 0 | Release edge of the other blocks; EEP pending |
| 4 | 0 | - | 0 | EEP | 1 | EEP transferred, `Pass_s` |
| 5 | 0 | - | 1 | - | 1 | |

`DpRst` while the last beat `b5` is pending: the packet ends with `b5` and no EEP beat follows.

| Cycle | `DpRst` | `S_Pkt` presented | `S_Pkt_Ready` | `M_Link` presented | `M_Link_Ready` | At the edge |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | 1 | `c0` (next packet) | 0 | `b5` | 0 | Reset edge: `b5` pending, `End_s` |
| 1 | 0 | - | 0 | `b5` | 1 | Release edge; `b5` transferred, `OpenNext` '0', `Pass_s` |
| 2 | 0 | - | 1 | - | 1 | |

Between packets (`OValid` '0', `Open` '0') the reset edge only moves the stage to `End_s`, and the release edge back to
`Pass_s`; `M_Link_Valid` stays '0'. The same holds when the last beat is transferred at the reset edge.

### 5.5 Rst and the order of the two inputs

`Rst` resets the registers of the stage at every edge at which it is applied, whatever `DpRst` does (specification
CO-RS-07, CO-RS-08):

| Order | Link output stage | Rest of the core |
| --- | --- | --- |
| `DpRst` alone | Ends an open packet with the EEP beat | Reset from the reset edge to the release edge of `DpRst` |
| `Rst` alone | Cut: `M_Link_Valid` '0' from the cycle after the reset edge, no EEP beat | Reset from the reset edge to the release edge of `Rst` |
| Both applied at the same edge | As `Rst` alone | Reset up to the later release |
| `Rst` applied while `DpRst` is applied | From the reset edge of `Rst`: cut; a pending beat or EEP beat is withdrawn | Reset up to the later release |
| `DpRst` applied while `Rst` is applied | No packet is open and no beat is held, so no EEP beat follows | Reset up to the later release |
| `Rst` released first, `DpRst` one or more cycles later | `End_s` without an open packet until `DpRst` is released; no beat on `M_Link` | Reset up to the release of `DpRst` |
| `DpRst` released first, `Rst` later | Reset up to the release of `Rst` | Reset up to the release of `Rst` |
| Both released at the same edge | Leaves the reset at that edge | Leaves the reset at that edge |

### 5.6 Alternatives

- A stage without its own register, which passes the beats through and loads a hold register only at the reset edge
  of `DpRst`, has no latency. It relies on the blocks in front keeping their output registers unchanged in the cycle
  that ends with the reset edge, and it puts a multiplexer behind the output registers of the core. The registered
  stage holds its own state, drives `M_Link` directly from registers and costs one clock cycle of latency and
  `DataWidth_g` + `DataWidth_g` / 8 + 9 flip-flops.
- A guard block outside the core, behind `M_Link`, needs the same logic in every system and leaves the hazard in the
  core.

## 6. Receive side after a reset

The receiving end resumes after the release edge without knowledge of the packet that was arriving when the reset came
(specification CO-RS-10). The next beat at `S_Link` starts a packet, so the rest of an interrupted packet passes the
checks of decision D8 as a packet of its own: with the CPTP layer its first bytes are taken as the CPTP header (usually
discarded as 0x11, 0x12 or 0x13), without it as the Packet Primary Header (usually discarded as 0x15 or 0x16). It is
counted once like any discarded packet. A rest whose bytes happen to form a valid packet for an enabled path is
delivered; the user guide states the constraint for the far end.
