# spp_receive

Receiving end of the Space Packet Protocol (RE-1 to RE-3, TB-2): reception with the checks of the Space Packets, the
demultiplexer by APID with the continuity check of the Packet Sequence Count, the delivery to the user ports through
the Packet Service or the Octet String Service, and the receive APID table.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard |
| [Architecture](docs/architecture.md) | Reception, demultiplexer, extraction, ports, table entry |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py -p 4 "*spp_receive*"`

| File | Content |
| --- | --- |
| `tb/spp_receive_tb.vhd` | VUnit runner with one `run(...)` per test case |
| `tb/spp_receive_th.vhd` | Harness: clock, DUT, stream source and sinks, event counters |
| `tb/spp_receive_tb_pkg.vhd` | Types and the procedures that queue a received packet and its expected indication |
| `tb/vunit_config.py` | Port configurations and stream widths per test |
