# spp_core

Top level of OpenSPP: sending end, receiving end, the transfer layer of ECSS-E-ST-50-53C and the register file. The
integration tests connect two cores through link models and N-Char adapters.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements and generics |
| [Architecture](docs/architecture.md) | Wiring and ports |
| [Verification plan](docs/verification_plan.md) | Test cases and seams of the integration |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py -p 4 "*spp_core*"`

| File | Content |
| --- | --- |
| `tb/spp_core_tb.vhd` | VUnit runner with one `run(...)` per test case |
| `tb/spp_core_th.vhd` | Harness: two cores, link models, optional N-Char adapters, stream models, AXI4-Lite VVCs |
| `tb/spp_core_tb_link.vhd` | Link model: forward, drop, end with EEP, inject |
| `tb/spp_core_tb_pkg.vhd` | Configuration, channels, records of the link control |
| `tb/vunit_config.py` | Configurations with and without the CPTP layer and through N-Char adapters |
