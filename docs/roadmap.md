# OpenSPP Roadmap

The development follows the plan of the [architecture](architecture.md) (section 11). This page tracks the state of
every module; a module is done when its verification report is written and its regression is green.

## Technology readiness

The core is at **TRL 3**: fully verified by simulation, not yet tested on hardware, no flight heritage. The
[TRL page](https://openspacehdl.org/trl/) explains what the levels mean for an IP core.

| Next level | What is needed | State |
| --- | --- | --- |
| TRL 4 | Synthesis and timing closure on a target FPGA; hardware test together with a SpaceWire port (e.g. OpenWire through `spp_nchar`) or a SpaceFibre port: both services against independent CCSDS packet equipment, CPTP packets from and to an independent SpaceWire node; hardware test plan and test report | Open (see the open items) |
| TRL 5 | Single-event effects test (beam test) on a radiation-tolerant FPGA with the core in operation that confirms the single-event mitigation and quantifies the error rates; operation over the temperature range | Open |

## Modules

| Module | Blocks (architecture section 7) | Status |
| --- | --- | --- |
| `spp_pkg` | Common types, constants and header fields, register package | Done |
| `tb` (shared) | SPP and CPTP model, stream source and sink models, AXI4-Lite VVC wrapper | Done |
| `spp_header` | CM-1, CM-2 (header insertion and removal) | Done |
| `spp_apid_table` | TB-1, TB-2 (APID tables) | Done |
| `spp_send` | SE-1 to SE-3 (sending end) | Done |
| `spp_receive` | RE-1 to RE-3 (receiving end) | Done |
| `spp_encapsulation` | EN-1, EN-2 (CPTP layer) | Done |
| `spp_mib` | MG-1, MG-2 (register file, EDAC monitor) | Done |
| `spp_core` | Core top level | Done |
| `spp_nchar` | AD-1 (N-Char adapter) | Done |

## Open items

| Item | State |
| --- | --- |
| Synthesis on a target device: resources and timing | Open; `lint/synth_check.py` checks the synthesizability of five core configurations with GHDL |
| Hardware test with a SpaceWire or SpaceFibre port and independent CCSDS packet equipment | Open |
| Code coverage with QuestaSim | Done: [coverage.md](coverage.md) |
| Several qualities of service (optional QoS Requirement parameter, SPP 3.3.2.4) | Not planned; one quality of service |
