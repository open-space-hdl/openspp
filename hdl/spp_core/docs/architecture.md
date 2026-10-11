# spp_core: Architecture

## 1. Block diagram

```text
              +-------------------------------------------------------------------------------------------+
 S_Tx ------->| spp_send --M_Pkt--> spp_encapsulation --+-------------------------------------------------|--> M_Link
              |    ^ Cfg, TxTbl                          | (Encapsulation_g = false: direct, destination   |
              |    |                                     |  index in TUser)                                |
 M_Rx <-------| spp_receive <--S_Pkt-- spp_decapsulation <-----------------------------------------------|--- S_Link
              |    ^ Cfg, RxTbl              ^ Cfg                                                       |
              |    |                         |                                                           |
 S_AxiLite -->| spp_mib: managed parameters, destinations, table access, counters, events, EDAC monitor  |--> Irq, Err_*
              +-------------------------------------------------------------------------------------------+
```

## 2. Wiring

| Signal group | From | To |
| --- | --- | --- |
| Space Packets with EEP and destination index (5-bit `TUser`) | `spp_send` | `spp_encapsulation` or the link output |
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

## 3. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `S_Tx_*` | `NumTx_g` x stream | in, out | Send ports; `User` 28 bits per port (architecture of the core, section 6) |
| `M_Rx_*` | `NumRx_g` x stream | out, in | Receive ports; `User` 22 bits per port |
| `M_Link_*` | `DataWidth_g` | out, in | Transmitted packets; `User`: EEP (bit 0, last beat), destination index (4:1) |
| `S_Link_*` | `DataWidth_g` | in, out | Received packets; `User`: EEP (last beat) |
| `S_AxiLite_*` | 11-bit address | | Register file |
| `Irq` | 1 | out | Interrupt |
| `Err_Valid`, `Err_Code`, `Err_Port`, `Err_Apid` | 1, 5, 4, 11 | out | Error event output |
