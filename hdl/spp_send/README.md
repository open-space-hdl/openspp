# spp_send

Sending end of the Space Packet Protocol (SE-1 to SE-3, TB-1): send buffers of the user ports with the checks of the
SDUs, the multiplexer, the packet assembly with the Packet Sequence Count of every APID, and the send APID table with
the managed data paths.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard |
| [Architecture](docs/architecture.md) | Buffers, multiplexer, assembly, ports, table entry |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py -p 4 "*spp_send*"`

| File | Content |
| --- | --- |
| `tb/spp_send_tb.vhd` | VUnit runner with one `run(...)` per test case |
| `tb/spp_send_th.vhd` | Harness: clock, DUT, stream sources and sink, event counters |
| `tb/spp_send_tb_pkg.vhd` | Types and the procedures that queue a request and its expected Space Packet |
| `tb/vunit_config.py` | Port configurations and stream widths per test |
