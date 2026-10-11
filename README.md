# OpenSPP

[![TRL 3](docs/img/trl-3.svg)](https://openspacehdl.org/trl/)

OpenSPP is an open implementation of the CCSDS Space Packet Protocol (CCSDS 133.0-B-2) that is based on the Open
Logic VHDL Library. It provides the Packet Service and the Octet String Service on a configurable number of user
ports, assembles Space Packets with a Packet Sequence Count per APID, multiplexes them onto one link, and at the
receiving end validates every packet, routes it by its APID to a user port and indicates lost packets. The SpaceWire
CCSDS Packet Transfer Protocol (ECSS-E-ST-50-53C) is the transfer layer for SpaceWire and SpaceFibre networks; a generic
removes it for other subnetworks. All streams are AXI4-Stream ports of 8 to 128 bits, the managed parameters and the
APID tables are in a register file behind an AXI4-Lite port, and all buffers and tables use the fault-tolerant entities
of [Open Logic](https://github.com/open-logic/open-logic) (SECDED ECC, scrubbing).

## Status

**Technology readiness level: TRL 3** (fully verified by simulation). The core has not been tested on hardware yet
and has no flight heritage; see [what the levels mean](https://openspacehdl.org/trl/) and the next steps in the
[roadmap](docs/roadmap.md#technology-readiness).

The core is complete and verified in simulation (GHDL and QuestaSim, 64 test cases at unit and core level in 145 test
runs over stream widths of 8 to 128 bits, branch and condition coverage closed, the remaining misses justified in
[docs/coverage.md](docs/coverage.md)); the
[compliance matrix](docs/compliance.md) traces every clause of CCSDS 133.0-B-2 and ECSS-E-ST-50-53C in scope to its
requirements and test cases. Two cores exchange both services through link models in both directions, also through
the N-Char adapter, at one beat per clock cycle; injected link faults, malformed packets and double bit errors are
detected and reported with their reason. The [user guide](docs/user_guide.md) contains the conformance statement with
the PICS proforma of CCSDS 133.0-B-2 Annex A. Synthesis results on a target device and a hardware test are open; see
[docs/roadmap.md](docs/roadmap.md).

## Documentation

The documents are also published as a website: [openspacehdl.org/openspp](https://openspacehdl.org/openspp/) (built
from this repository by `tools/docs/`).

| Document | Content |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Architecture: building blocks, owned clauses, Open Logic usage, verification, traceability matrix |
| [docs/user_guide.md](docs/user_guide.md) | Integration: sources, generics, interfaces, programming sequence, integration constraints, conformance statement |
| [docs/conventions.md](docs/conventions.md) | Coding, verification and repository conventions |
| [docs/roadmap.md](docs/roadmap.md) | Technology readiness, module status and open items |
| [docs/compliance.md](docs/compliance.md) | Compliance matrix: requirements and test cases of every clause (generated) |
| [docs/coverage.md](docs/coverage.md) | Code coverage of the regression with QuestaSim |
| [hdl/spp_mib/docs/register_map.md](hdl/spp_mib/docs/register_map.md) | Register map (generated; C header `sw/spp_regs.h`) |
| `hdl/<module>/docs/` | Specification, architecture, verification plan and verification report of each module |

## Repository structure

```text
openspp/
|-- docs/             Top-level documentation
|-- hdl/<module>/     One folder per module: src/, tb/, docs/
|-- tb/               Verification components shared by the testbenches (SPP and CPTP model, stream models)
|-- lint/             VSG configuration (Open Logic rules), synthesizability check
|-- tools/            Compliance matrix and register map generators
|   `-- docs/         Documentation website (MkDocs)
|-- sw/               C header of the register map (generated)
|-- open-logic/       Git submodule: Open Logic (fault-tolerant entities branch)
|-- uvvm/             Git submodule: UVVM verification framework
|-- component_list.txt  Modules in dependency order
`-- run.py            VUnit regression runner
```

## Running the tests

Prerequisites: Python 3, [GHDL](https://github.com/ghdl/ghdl) on the `PATH` and the Python packages of
`requirements.txt`.

```shell
git submodule update --init
python -m pip install -r requirements.txt
python run.py -p 4              # full regression with GHDL, 4 parallel simulations
python run.py "*spp_send*"      # one module
python run.py --questa <test>   # QuestaSim
```

`run.py` compiles Open Logic into the VHDL library `olo`, the required UVVM components into their own libraries and
all OpenSPP sources into the library `openspp`. `SPP_GHDL_SIM_FLAGS` passes extra flags to the GHDL simulation, for
example `--vcd=wave.vcd` for a waveform.

Checks besides the regression:

```shell
python lint/lint.py                 # VSG, no errors and no warnings
python lint/synth_check.py          # synthesizability of five core configurations with GHDL
python tools/compliance.py --check  # every clause and requirement traced to a test case
python tools/regmap.py --check      # generated register map files match hdl/spp_mib/regs/spp_regs.yml
python -m mkdocs build -f tools/docs/mkdocs.yml  # documentation website, fails on broken links
```

## Licence

OpenSPP is licensed under the [PSI HDL Library License, Version 1.0](License.txt), the licence of Open Logic
(LGPL 2.1 with an exception for binaries, see [LGPL2_1.txt](LGPL2_1.txt)).
