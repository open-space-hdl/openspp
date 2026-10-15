# OpenSPP: Code Coverage

## 1. Method

The code coverage of the OpenSPP sources is measured with QuestaSim (Questa Sim Microchip Edition 2024.3) over the
complete regression of `run.py`, the same test set that GHDL runs in CI:

```shell
python run.py --questa --coverage -p 1
```

The sources of `hdl/<module>/src` are compiled with `+cover=sbcef`: statements, branches, conditions, expressions
(focused expression coverage) and state machines. Open Logic, UVVM and the testbenches are not instrumented; Open Logic
is verified by its own regression. `run.py` merges the coverage of all tests into `coverage/coverage.ucdb` and writes
the reports `coverage/coverage_report.txt` (details per instance) and `coverage/coverage_byfile.txt`; a design unit
is covered when any of its instances in any test covers it.

Closure rules:

- Statements, branches, state machine states and transitions: every item is covered by a test or listed with its
  justification in section 4.
- Conditions and expressions: every miss is reviewed for untested behaviour (section 3); a remaining miss is listed
  with its justification in section 4.
- `-- coverage off` / `-- coverage on` are used for one kind of code only: the `when others` branch of a state machine
  whose enumerated state type lists every state. The branch is the recovery path of an illegal state (architecture
  D14) and cannot be reached in simulation.

## 2. Result

Runs on 2026-10-15 with Open Logic 4.7.0-ft.6, both on the same HDL:

- the complete regression of 321 tests (71 test cases in their configurations) on commit af774dd, without and with
  code coverage, all passed;
- the configuration `pktmax_w8`, added on commit 711a29a (no source or testbench change against af774dd besides the
  configuration list), without and with code coverage, passed.

The numbers below are the merge (`vcover merge`) of the coverage database of the 321 tests and of the `pktmax_w8` run:
322 tests. Numbers are covered/total bins per file; bold marks a metric with misses. The FSM columns of
`spp_send_assembly.vhd` count both of its state machines; section 4 explains the misses.

| File | Statements | Branches | FSM States | FSM Transitions | Conditions | Expressions |
| --- | --- | --- | --- | --- | --- | --- |
| `spp_apid_table/src/spp_apid_table.vhd` | 62/62 | 41/41 | 4/4 | 7/7 | 11/11 | 4/4 |
| `spp_core/src/spp_core.vhd` | 18/18 | 4/4 |  |  |  |  |
| `spp_encapsulation/src/spp_decapsulation.vhd` | 45/45 | 25/25 | 3/3 | 3/3 | 10/10 | 2/2 |
| `spp_encapsulation/src/spp_encapsulation.vhd` | 26/26 | 12/12 |  |  |  |  |
| `spp_header/src/spp_header_insert.vhd` | 91/91 | 45/45 | 4/4 | **9/10** | 7/7 |  |
| `spp_header/src/spp_header_remove.vhd` | 88/88 | 34/34 | 3/3 | **4/5** | 6/6 |  |
| `spp_mib/src/spp_mib.vhd` | 234/234 | 122/122 |  |  | 13/13 |  |
| `spp_nchar/src/spp_nchar.vhd` | 54/54 | 33/33 |  |  | 14/14 | 10/10 |
| `spp_pkg/src/spp_pkg.vhd` | **26/27** | 6/6 |  |  |  |  |
| `spp_receive/src/spp_receive.vhd` | 4/4 | 6/6 |  |  |  |  |
| `spp_receive/src/spp_receive_buffer.vhd` | 53/53 | 26/26 |  |  | 6/6 | **1/2** |
| `spp_receive/src/spp_receive_demux.vhd` | 111/111 | 45/45 |  |  | 11/11 | 5/5 |
| `spp_receive/src/spp_receive_extraction.vhd` | 4/4 |  |  |  |  | 3/3 |
| `spp_send/src/spp_send.vhd` | 4/4 | 6/6 |  |  |  |  |
| `spp_send/src/spp_send_assembly.vhd` | 124/124 | 50/50 | **3/7** | **2/11** | 8/8 | 8/8 |
| `spp_send/src/spp_send_buffer.vhd` | 67/67 | 38/38 |  |  | 10/10 | 2/2 |
| `spp_send/src/spp_send_mux.vhd` | 4/4 | 4/4 |  |  |  | 2/2 |
| Total | 1015/1016 (99.9 %) | 497/497 (100.0 %) | 17/21 (81.0 %) | 25/36 (69.4 %) | 96/96 (100.0 %) | 37/38 (97.4 %) |

Every statement except one function of the package, every branch and every condition is covered. The remaining
misses are listed in section 4: one statement, one expression term, two state machine transitions that cannot occur,
and a state machine that QuestaSim does not track.

## 3. Gaps found and closed

The first complete run showed requirements whose behaviour no test exercised, and reachable code that no test reached.
Each gap was closed by a new or an extended test; one guard that could not be false was removed from the design.

| Gap | Resolution |
| --- | --- |
| CO-IF-03 with `TxPathDefault_g` and `RxPathDefault_g` false: every core of the regression started with the default paths | New test TC-CO-10 in the configurations `cptp_w32`, `cptp_w128` and `nopath_w32` (no default paths): the initial entries of both tables, rejection without a send path (0x07), discard without a receive path (0x19), delivery once both paths are written |
| A core without Target SpaceWire Address bytes (`SpwAddrBytes_g` 0) was never elaborated | `nopath_w32` has `SpwAddrBytes_g` 0: a configured address length of 3 is limited to 0 and the packet is delivered; `lint/synth_check.py` synthesizes the configuration |
| EN-TX-02: an address length beyond `SpwAddrBytes_g` is limited to it | TC-EN-01 extended: destination 3 configured with 20 bytes at `SpwAddrBytes_g` 16 |
| Byte count of the send and receive buffers beyond 131071 bytes (saturation) | TC-SE-07: an Octet String of 140000 bytes is rejected. TC-RE-06: a packet of 140006 bytes whose PDL + 7 equals its length modulo 2^17 is discarded by the length check, which a wrapping count would pass |
| Double error in the last word of an SDU or packet without an earlier one (the combinational path to the EEP and error flags) | TC-SE-12 (SDU of one word) and TC-RE-08 (packet of one word in the new configuration at 64 bits) extended |
| Receive buffer full of packets (`MaxPackets_g`) while its port does not accept them (found while reviewing the expression miss of `spp_receive_buffer.vhd` in section 4) | TC-RE-01 extended: 20 packets of 7 bytes while the port does not accept them; the reception waits and delivers all |
| Register file: a guard on the generic `SpwAddrBytes_g` in the access to the address bytes, constant per instance | Replaced by the loop bound `SpwAddrBytes_g - 1` (no address byte without `SpwAddrBytes_g`), same behaviour |
| Register file: RX_TABLE_APID never read; TABLE_STATUS written with only one of the overrun bits; a read of RX_TABLE_ENTRY while the receive table is busy | TC-MG-04 extended, with a holding client of the receive table in the harness; TC-CO-10 reads RX_TABLE_APID |
| APID table: reset in the cycle of a read (`Read_s`) | TC-TB-05 extended |
| The bound of CO-GN-03 for more than 2^29 written beats (`spp_core.vhd`, function `writtenBeats`) was not reached by the regression of 321 tests | New configuration `pktmax_w8`: 8192 send packets in buffers of 8192 beats at 8 bits |
| Header insertion: a guard on the header index that cannot be false in its branch (a beat of header bytes only is not wider than the header) | Replaced by the loop bound `minimum(Bytes_c, MaxHeaderBytes_g)`, same behaviour |

## 4. Remaining misses

| Location | Item not covered | Justification |
| --- | --- | --- |
| `spp_pkg/src/spp_pkg.vhd:275` | Statement of the function `hdrType` | The function is one of the header decoding functions of PK-FN-02 and is called only by the testbench of `spp_pkg` (TC-PK-01 checks its result for boundary and random headers in both simulators); the core does not need the Packet Type at the receiving end. The calls of the testbench, which is not instrumented, are not counted. |
| `spp_header/src/spp_header_insert.vhd:246` | Transition `Flush_s -> Data_s` | QuestaSim derives the transition from the assignment after the `case` statement, which runs only when an input beat is consumed. No input beat is consumed in `Flush_s`, so the transition cannot occur. |
| `spp_header/src/spp_header_remove.vhd:211` | Transition `Idle_s -> Flush_s` | A flush beat follows only when the residue and the bytes of the last beat exceed one output beat. In `Idle_s` the residue is empty, so the bytes of one input beat never exceed one output beat. |
| `spp_send/src/spp_send_assembly.vhd` | State machine `PState`: states `PTable_s`, `PRead_s`, `PWrite_s`, `PJob_s` and their 9 transitions | `vopt` recognises the state machine and its complete transition table, but QuestaSim records only the state after each reset (`PIdle_s`), although every packet of the regression passes all states. Every statement and branch of the file is covered, including every `when` branch and every transition assignment (lines 233, 235, 243, 250, 257 and 294). The reset assignment (line 397) does not depend on the state; TC-SE-13 resets the sending end during a transfer. |
| `spp_receive/src/spp_receive_demux.vhd` | State machines `PState` and `SState` | `vopt` does not recognise them, so no state machine coverage is reported for the file. They have the structure of the state machines of `spp_send_assembly`; every statement and branch of the file is covered, and TC-RE-09 resets the receiving end while packets are stored and delivered. |
| `spp_receive/src/spp_receive_buffer.vhd:109` | Expression term: `Desc_InReady` = '0' while `Fifo_InReady` = '1' | The packet FIFO and the descriptor FIFO hold `MaxPackets_g` packets each, a descriptor is written only for an accepted packet and leaves its FIFO before its packet. The descriptor FIFO is therefore never full while the packet FIFO accepts; the term keeps the descriptor FIFO from overflowing by construction. TC-RE-01 fills the buffer with packets while the port does not accept them. |

## 5. Reproduction

```shell
python run.py --questa --coverage -p 1
vcover report -byfile -details -zeros -code sbf coverage/coverage.ucdb
```

The second command lists the statements, branches and state machine items that are not covered, per file.
