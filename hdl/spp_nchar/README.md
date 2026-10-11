# spp_nchar

N-Char adapter (AD-1): converts the link streams of the core to and from the N-Char packet stream of a SpaceWire port
of OpenWire (one character per beat, the end of packet marker EOP or EEP as a separate beat).

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements and configuration |
| [Architecture](docs/architecture.md) | Both directions, ports |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py -p 4 "*spp_nchar*"`; the integration with two cores: `python run.py -p 4 "*spp_core*nchar*"`.

| File | Content |
| --- | --- |
| `tb/spp_nchar_tb.vhd` | VUnit runner with the DUT and the stream models |
| `tb/vunit_config.py` | Link widths |
