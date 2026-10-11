# spp_pkg

Common package of OpenSPP: fields and lengths of the Space Packet and of the CPTP packet, layouts of `TUser`, error
codes, the error event record and the functions that build and decode the Packet Primary Header.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements |
| [Architecture](docs/architecture.md) | Contents of the package |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results |

Tests: `python run.py -p 4 "*spp_pkg*"`

| File | Content |
| --- | --- |
| `src/spp_pkg.vhd` | The package |
| `tb/spp_pkg_tb.vhd` | Functions and constants against the packet model; self-test of the stream models of `tb/` |
