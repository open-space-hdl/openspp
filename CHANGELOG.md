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
- `spp_core`: second reset input `DpRst` (data path reset, default '0'). It resets every function of the core like
  `Rst` (buffers, APID tables, register file, counters) except the new link output stage `spp_link_output`, which keeps
  the beat presented on `M_Link` and ends a packet that is open on the link with an EEP beat of one byte. The link and
  the node at its far end stay in operation while the core restarts; `Rst` resets the whole core as before. The user
  guide states the behaviour of every port during and after a reset, in every order of the two inputs.

### Changed

- Open Logic 4.7.0-ft.12 (from 4.7.0-ft.6); no port or generic of OpenSPP changes for it.
- Verification: the test end compares the alert counters of every level itself and ends the simulation with a
  failure, whatever the stop limits of the test.
- `spp_core`: `M_Link` is driven by the register stage `spp_link_output`, one clock cycle later than before; the
  throughput and the clock cycles per packet do not change.

### Fixed

- Documentation website: the figures are shown again (selectolax 1.0.0 pinned for the build).

## [0.1.0] - 2026-10-18

First release. CCSDS Space Packet Protocol (CCSDS 133.0-B-2) with the Packet Service and the Octet String Service on a
configurable number of user ports, a Packet Sequence Count per APID and routing by APID at the receiving end, and the
SpaceWire CCSDS Packet Transfer Protocol (ECSS-E-ST-50-53C). AXI4-Stream ports of 8 to 128 bits and a register file
behind an AXI4-Lite port. Verified by simulation (TRL 3) in GHDL and QuestaSim, on Open Logic 4.7.0-ft.6.
