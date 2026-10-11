# spp_header

Header insertion and removal (CM-1, CM-2): stream stages that put a header of up to `MaxHeaderBytes_g` bytes in front
of a packet or remove up to `MaxRemoveBytes_g` leading bytes, one beat per clock cycle on streams of 8 to 128 bits with
byte enables.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements and configuration |
| [Architecture](docs/architecture.md) | Realignment, ports, state machines |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results |

Tests: `python run.py -p 4 "*spp_header*"` (every test for the stream widths 8, 16, 24, 32, 64 and 128 bits).

| File | Content |
| --- | --- |
| `tb/spp_header_tb.vhd` | VUnit runner with one `run(...)` per test case |
| `tb/spp_header_th.vhd` | Harness: clock, both DUTs, stream sources and sinks |
| `tb/spp_header_tb_pkg.vhd` | Constants and the procedures that queue a packet and its expected result |
| `tb/vunit_config.py` | Configurations for the stream widths |
