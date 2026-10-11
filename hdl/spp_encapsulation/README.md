# spp_encapsulation

Transfer layer on SpaceWire (EN-1, EN-2): the encapsulation of Space Packets into CPTP packets of ECSS-E-ST-50-53C
with the Target SpaceWire Address, Target Logical Address and User Application value of their destination, and the
decapsulation with the checks of the target.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard |
| [Architecture](docs/architecture.md) | Header of a destination, checks of the decapsulation, ports |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py -p 4 "*spp_encapsulation*"`

| File | Content |
| --- | --- |
| `tb/spp_encapsulation_tb.vhd` | VUnit runner with one `run(...)` per test case and the destination table |
| `tb/spp_encapsulation_th.vhd` | Harness: clock, both DUTs, stream sources and sinks, event counters |
| `tb/vunit_config.py` | Stream widths |
