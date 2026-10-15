# OpenSPP Conventions

OpenSPP follows the coding conventions of Open Logic and the module development process of the architecture
document. This page lists the rules and the few OpenSPP-specific additions.

## VHDL coding

- The [Open Logic coding conventions](../open-logic/doc/Conventions.md) apply in full: port names
  `<Interface>_<Signal>`, generics `_g`, constants `_c`, variables `_v`, types `_t`, FSM types `<Name>Fsm_t` with
  states `_s`, functions in `lowerCamelCase`, four spaces of indentation, no tabs, no trailing whitespace.
- Entities are named `spp_<function>` (for example `spp_send_buffer`). All OpenSPP sources are compiled into the VHDL
  library `openspp`; Open Logic is compiled into the library `olo`.
- Language: VHDL-2008.
- Entities with non-trivial state use the two-process pattern of Open Logic: all registers in one `TwoProcess_r`
  record, signals `r` and `r_next`, a combinational process starting with `v := r;` and ending with
  `r_next <= v;`, a sequential process with `r <= r_next;` and the reset override at its end.
- Resets are synchronous and high-active. Only state registers are reset. The core has one clock domain `Clk`.
- The actual of a port is a name (signal, constant, index or slice of one), never an expression such as
  `to_integer(...)` or a concatenation: declare a signal or constant of the port's subtype and associate it. QuestaSim
  with full optimisation can give the implicit signal of an expression actual a range that matches neither the port
  nor the expression and stop the simulation.
- Every data path between blocks is a valid / ready stream (AXI4-Stream handshake semantics) or a valid-only stream
  of one-cycle events where the receiver is never slower than the source.
- Packet streams carry the first byte of a packet in byte lane 0 (`TData(7:0)`). All bytes of a beat are valid
  except in the last beat of a packet, whose valid bytes are contiguous from lane 0 (`TKeep`).
- Standard functions (FIFOs, RAMs, crossings, synchronisers, arbiters, pipeline stages) are instantiated from Open
  Logic, never rewritten. FIFOs, RAMs and crossings use the fault-tolerant `olo_ft_*` entities.
- State machines have a `when others` branch that returns to a defined recovery state; the reset leads to that state
  from any state.
- Every line that implements a requirement of the standards is traceable through the module specification; comments
  name the clause where it helps the reader (for example `-- SPP 4.1.3.4.3.4` or `-- CPTP 5.5.4.3a`).
- File header: copyright line and authors, then a 1 to 2 sentence description that links to the module
  documentation. Never write "all rights reserved".
- Never use em-dashes in code, comments or documentation. Use UTF-8 only.
- VSG 3.27 with the Open Logic configuration in `lint/config` must report no errors and no warnings:
  `python lint/lint.py`. Safe automatic fixes: `python lint/lint.py --fix`.
- The design must be synthesizable in a technology-independent way: `python lint/synth_check.py` elaborates
  `spp_core` and `spp_nchar` with the synthesis of GHDL (after `python run.py --compile`) and fails on errors and
  inferred latches.
  `to_01` and other simulation-only functions are not used in RTL.
- `compile_order.txt` lists the synthesis sources of the library `openspp` in compile order. After adding, removing
  or renaming a source file, regenerate it with `python run.py --compile-order`; the CI fails when it is out of date.
- Traceability: every requirement of a specification is verified by at least one test case of the verification plan,
  every clause of the traceability matrix (architecture section 10) by the test cases of its requirements, and
  every test case of a plan is run by a testbench. `python tools/compliance.py` writes the
  [compliance matrix](compliance.md); `python tools/compliance.py --check` fails on a gap.

## Module development process

Every module goes through the seven phases of the architecture document (section 9):

| Phase | Output |
| --- | --- |
| A Requirements | `hdl/<module>/docs/specification.md`: requirements with IDs, each tracing to clauses of the standards |
| B Architecture | `hdl/<module>/docs/architecture.md`: blocks, ports, state machines, data formats |
| C Verification plan | `hdl/<module>/docs/verification_plan.md`: test cases with IDs, requirement coverage |
| D RTL | `hdl/<module>/src/*.vhd` |
| E Testbenches | `hdl/<module>/tb/<entity>_th.vhd` (harness) and `<entity>_tb.vhd` (VUnit runner) |
| F Verification | Regression green, `hdl/<module>/docs/verification_report.md` |
| G Integration | Tests at the next level that cross every seam the module touches |

A module is one group of blocks of the architecture (section 7). `hdl/<module>/README.md` links the four documents
and explains how to run the tests.

Requirement IDs have the form `<GROUP>-<AREA>-<NN>`, for example `SE-IF-01`. The last column of a requirement table
names the clauses with their standard (`SPP 4.1.3.5`, `CPTP 5.5.4.4`) or `none`.

## Diagrams

- Every architecture document has a block diagram; state machines and data formats have one where text alone is
  hard to follow.
- Diagrams are draw.io drawings stored as editable SVG with the drawing embedded (`<name>.drawio.svg`) in the `img/`
  folder next to the document. The SVG is the source: open it in draw.io to change it. It is exported with the light
  theme on an opaque white background, so that it reads in both colour schemes of the documentation site.
- Blocks: light blue for OpenSPP logic, white with a blue outline for an OpenSPP entity instantiated as a whole, light
  grey for an Open Logic entity, drawn inside the block that instantiates it. A dashed outline groups the blocks of
  one entity instance; a stacked block is replicated per port (`× T`, `× R`). The title carries the building block ID
  of the architecture (`SE-1 Send buffer`), the entity follows in grey.
- Connections: thick lines for streams and buses, thin lines for single signals. Every line is horizontal or
  vertical; a dot marks a branch. Ports cross the frame of the entity, inputs on the left, outputs on the right where
  the layout allows.
- A diagram is at most about 1000 px wide, so that its text stays readable in the content column, and its alt text
  names the blocks it shows.

## Verification

- VUnit runs every test (`run.py`); UVVM supplies VVCs, BFMs, checks, randomisation and functional coverage.
  VUnit 5.0.0.dev7 appends the generics of every GHDL simulation to one shared `ghdl.sim_flags` list, so a test
  would inherit the generics it does not set from earlier tests: `run.py` gives every simulation its own copy and
  stops when a GHDL command carries other generics than those of its configuration.
- The harness (`_th`) contains clocks, reset, the DUT and the VVCs, the testbench (`_tb`) contains one
  `if run("<test id>") then` block per test case of the verification plan. The test IDs of the plan and the names
  in `run(...)` are identical.
- A test passes only when UVVM reports no unexpected alerts and every expected alert occurred
  (`spp_tb_pkg.sppTestEnd`).
- Tests observe ports and management interfaces only, never internal signals.
- GHDL is the default simulator; QuestaSim (`python run.py --questa`) is used for code coverage
  ([coverage.md](coverage.md)). Every test passes in GHDL and in QuestaSim, in QuestaSim both with code coverage
  (`--coverage`) and without it: the coverage options reduce the optimisation of the simulator, so only the run
  without them shows the behaviour of a fully optimised simulation.
- A side effect is never obtained by calling an impure function and discarding its result: QuestaSim may remove such
  a call. Protected types offer a procedure for it.
- A random value is drawn into a variable before it is used in the actual of an unconstrained array parameter
  (`Len_v := Rand_v.rand(1, 300); octet(..., tbPayload(Len_v, Seed_v))`): QuestaSim does not evaluate an impure call
  inside such an actual exactly once, so the stimulus and the expected packet would differ.
- Packets are built and checked by the packet model of `tb/` (own implementation of the Space Packet format of
  SPP 4.1 and of the CPTP packet format of CPTP 5.4); tests never use the RTL of the core to build or check packets.
- Generic ranges are verified, not only declared: every value of a generic that changes the structure (stream width,
  port, destination and address counts, booleans) runs in a configuration of its own; the bounds of every other
  range are elaborated and synthesized (`lint/synth_check.py`), and a value outside them stops the elaboration with
  an assertion that names the bound (checked by `lint/synth_check.py` as well). A bound that cannot be elaborated on a
  simulation host is asserted and stated as not elaborated. The verification report of the core lists every generic
  with its declared range and the simulated and synthesized values.
- Negative tests inject the fault from the bench (wrong Packet Version Number, length different from the PDL,
  oversized SDU, EEP, non-zero Reserved field, wrong Protocol Identifier, unrouted APID, lost packet, double error
  through the `ErrInj` ports) and expect the counter, the event or the indicator.

## Git

- `main` holds the integrated state. Every module or change is developed on a branch `feature/<module>` or
  `bugfix/<topic>` and merged with `--no-ff` once its regression is green.
- Commit messages: imperative subject line, body explains what and why.
