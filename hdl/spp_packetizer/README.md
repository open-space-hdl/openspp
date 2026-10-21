# spp_packetizer

Packetizer (PT-1): cuts data units of any length into segments and sends every segment as a Space Packet for a send
port of the Packet Service of `spp_core`, with the Sequence Flags of its segment, the Packet Sequence Count of the
instance, an optional Packet Secondary Header and an optional CRC-16.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements, configuration, interpretation of the standard, protection scope |
| [Architecture](docs/architecture.md) | Segmenter, buffers, packet output, ports, timing |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results and findings |

Tests: `python run.py -p 4 "*spp_packetizer_tb*"`; the integration with the core:
`python run.py -p 4 "*spp_packetizer_core_tb*"`.

| File | Content |
| --- | --- |
| `tb/spp_packetizer_tb.vhd` | VUnit runner with the DUT, the stream models and the monitors |
| `tb/spp_packetizer_core_tb.vhd` | VUnit runner of the integration with `spp_core` |
| `tb/vunit_config.py` | Configurations |
