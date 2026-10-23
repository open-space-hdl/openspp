# Changelog

The notable changes of OpenSPP. The versions follow semantic versioning: 0.y.z while the core is at TRL 3, a major
version for an incompatible change of ports, stream formats, generics or register map, a minor version for a feature
and a patch version for a fix.

## [Unreleased]

### Added

- `spp_packetizer`: cuts data units of any length into Space Packets in front of a send port. The Sequence Flags mark
  the first, continuation and last segment (CCSDS 133.0-B-2 4.1.3.4.2.2), with an optional Packet Secondary Header
  from a port and an optional CRC-16 trailer over the data of each packet. Verified with GHDL; its QuestaSim runs and
  code coverage follow with the next release.

### Changed

- Open Logic 4.7.0-ft.9 (from 4.7.0-ft.6); no port or generic of OpenSPP changes.
- Verification: the test end compares the alert counters of every level itself and ends the simulation with a
  failure, whatever the stop limits of the test.

### Fixed

- Documentation website: the figures are shown again (selectolax 1.0.0 pinned for the build).

## [0.1.0] - 2026-10-18

First release. CCSDS Space Packet Protocol (CCSDS 133.0-B-2) with the Packet Service and the Octet String Service on a
configurable number of user ports, a Packet Sequence Count per APID and routing by APID at the receiving end, and the
SpaceWire CCSDS Packet Transfer Protocol (ECSS-E-ST-50-53C). AXI4-Stream ports of 8 to 128 bits and a register file
behind an AXI4-Lite port. Verified by simulation (TRL 3) in GHDL and QuestaSim, on Open Logic 4.7.0-ft.6.
