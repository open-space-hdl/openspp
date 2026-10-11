# spp_apid_table: Architecture

## 1. Block diagram

```text
              +-----------------------------------------------------------+
 A_* -------->|  arbiter and      Wr_*  +-------------------------------+  |
 B_* -------->|  transaction  -------->|  olo_ft_ram_sdp_scrub         |  |
              |  state machine  Rd_* ->|  2048 x Width_g, SECDED,      |--|--> Ecc_*, Scrub_*
 Init_Value ->|                <------ |  scrubber in idle cycles      |  |
              |                 data   +-------------------------------+  |
 ErrInj_* --->|  injection latch (applied to the next client write)       |
              +-----------------------------------------------------------+
```

## 2. Ports

| Port | Width | Direction | Description |
| --- | --- | --- | --- |
| `Clk`, `Rst` | 1 | in | Clock, synchronous high-active reset |
| `Init_Value` | `Width_g` | in | Value written into every entry after the reset |
| `Init_Busy` | 1 | out | Initialisation in progress |
| `A_Valid`, `A_Ready` | 1 | in, out | Request of client A and its grant |
| `A_Apid` | 11 | in | APID of the request |
| `A_RdValid`, `A_RdData`, `A_RdDed` | 1, `Width_g`, 1 | out | Entry of the transaction, one cycle after the grant, with the double error flag |
| `A_WrEna`, `A_WrData` | 1, `Width_g` | in | Write back and end the transaction |
| `A_Release` | 1 | in | End the transaction without a write |
| `B_*` | as `A_*` | | Client B |
| `Ecc_Sec`, `Ecc_Ded` | 1 | out | Single or double error in a client read (one-cycle pulses) |
| `Scrub_Sec`, `Scrub_Ded` | 1 | out | Single or double error found by the scrubber |
| `Scrub_Enable` | 1 | in | Scrubber enabled (suspended during the initialisation) |
| `ErrInj_BitFlip`, `ErrInj_Valid` | codeword, 1 | in | Error injection pattern, latched by the strobe |

## 3. State machine

```text
 reset --> Init_s --2048 writes--> Idle_s --grant A or B--> Read_s --read data--> Hold_s
                                     ^                                               |
                                     +------------- write back or release -----------+
```

`Init_s` writes `Init_Value` to the addresses 0 to 2047, one per cycle; the scrubber is held off meanwhile. `Idle_s`
grants one request: client A unless client B also requests and A was served last. The grant (`Ready`) and the RAM
read happen in the same cycle; the read data returns in `Read_s` one cycle later. `Hold_s` waits for the write or the
release of the owner of the transaction; a write in this state also applies a latched error injection pattern. The
`when others` branch returns to `Idle_s`.

A transaction takes three cycles when the client answers in the cycle after the read data. Both clients therefore see
at most one transaction of the other between two of their own.

## 4. Fault tolerance

The RAM is `olo_ft_ram_sdp_scrub` with a read latency of one cycle and no ECC pipeline. User reads and writes have
priority over the scrubber, which uses the idle cycles; a scrubber write-back is abandoned when a client writes the
same address. A double error is not repaired: the client sees the flag and the register file reports it, the entry is
repaired by the next write.
