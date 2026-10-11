# spp_mib

Register file of OpenSPP (MG-1, MG-2): managed parameters, destinations, software access to the APID tables, counters
per error reason and of the packets, event flags with interrupt and the EDAC monitor with error injection, behind an
AXI4-Lite slave.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements and configuration |
| [Architecture](docs/architecture.md) | Register access, table access, counters, EDAC monitor, ports |
| [Register map](docs/register_map.md) | Every register and field (generated) |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

The register map is described in `regs/spp_regs.yml`; `python tools/regmap.py` generates the VHDL package
`hdl/spp_pkg/src/spp_regs_pkg.vhd`, the register map and the C header `sw/spp_regs.h`.

Tests: `python run.py -p 4 "*spp_mib*"`

| File | Content |
| --- | --- |
| `tb/spp_mib_tb.vhd` | VUnit runner with one `run(...)` per test case |
| `tb/spp_mib_th.vhd` | Harness: clock, DUT, both APID tables, AXI4-Lite master VVC |
| `tb/spp_mib_tb_pkg.vhd` | Configuration of the DUT and the records of its inputs and outputs |
