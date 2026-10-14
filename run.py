# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""VUnit regression runner of OpenSPP.

Compiles Open Logic into the library `olo`, the UVVM components used by the testbenches into their own
libraries and every module of component_list.txt plus the shared verification components (tb/) into the
library `openspp`, then runs all testbenches.

GHDL is the default simulator. `--questa` selects QuestaSim; `--questa --coverage` collects the code coverage
(statements, branches, conditions, expressions, state machines) of the OpenSPP sources and merges it into
coverage/coverage.ucdb with the text report coverage/coverage_report.txt.

`--compile-order` writes compile_order.txt with the synthesis sources of the library `openspp` in compile order and
exits without simulating.
"""

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent

# QuestaSim installation used when --questa is given and VUNIT_MODELSIM_PATH is not set
QUESTA_DEFAULT_PATH = r"D:\Microchip\Libero_SoC_2025.2\Libero_SoC\QuestaSim_Pro\win64"

# Simulator selection must happen before VUnit parses the command line
COMPILE_ORDER = "--compile-order" in sys.argv
if COMPILE_ORDER:
    sys.argv.remove("--compile-order")
COVERAGE = "--coverage" in sys.argv
if COVERAGE:
    sys.argv.remove("--coverage")
if "--questa" in sys.argv:
    sys.argv.remove("--questa")
    os.environ["VUNIT_SIMULATOR"] = "modelsim"
    if "VUNIT_MODELSIM_PATH" not in os.environ and Path(QUESTA_DEFAULT_PATH).exists():
        os.environ["VUNIT_MODELSIM_PATH"] = QUESTA_DEFAULT_PATH
else:
    os.environ.setdefault("VUNIT_SIMULATOR", "ghdl")

from vunit import VUnit  # noqa: E402  (import after the simulator selection)

# Open Logic areas compiled into the library olo (the areas fix and intf are not used)
OLO_AREAS = ("base", "axi", "ft")

# UVVM components used by the testbenches, in dependency order
UVVM_COMPONENTS = (
    "uvvm_util",
    "uvvm_vvc_framework",
    "bitvis_vip_scoreboard",
    "bitvis_vip_axilite",
)


def add_open_logic(vu):
    lib = vu.add_library("olo")
    for line in (ROOT / "open-logic" / "compile_order.txt").read_text().splitlines():
        rel = line.strip()
        if rel and rel.split("/")[1] in OLO_AREAS:
            lib.add_source_file(ROOT / "open-logic" / rel)


def add_uvvm(vu):
    for component in UVVM_COMPONENTS:
        lib = vu.add_library(component)
        script_dir = ROOT / "uvvm" / component / "script"
        for line in (script_dir / "compile_order.txt").read_text().splitlines():
            rel = line.strip()
            if rel and not rel.startswith("#"):
                lib.add_source_file((script_dir / rel).resolve())


def read_component_list():
    modules = []
    for line in (ROOT / "component_list.txt").read_text().splitlines():
        name = line.strip()
        if name and not name.startswith("#"):
            modules.append(name)
    return modules


def add_openspp(vu):
    lib = vu.add_library("openspp")
    shared_tb = sorted((ROOT / "tb").glob("*.vhd"))
    if shared_tb:
        lib.add_source_files(shared_tb)
    modules = read_component_list()
    for module in modules:
        for sub in ("src", "tb"):
            files = sorted((ROOT / module / sub).glob("*.vhd"))
            if files:
                added = lib.add_source_files(files)
                if COVERAGE and sub == "src":
                    added.add_compile_option("modelsim.vcom_flags", ["+cover=sbcef"])
    return lib, modules


def apply_module_configs(lib, modules):
    """A module can add VUnit configurations in hdl/<module>/tb/vunit_config.py (function configure(lib))."""
    for module in modules:
        cfg = ROOT / module / "tb" / "vunit_config.py"
        if cfg.exists():
            spec = importlib.util.spec_from_file_location(f"vunit_config_{Path(module).name}", cfg)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            mod.configure(lib)


def set_simulator_options(vu):
    # UVVM uses shared variables of non-protected types; GHDL accepts them with -frelaxed
    vu.add_compile_option("ghdl.a_flags", ["-frelaxed", "-Wno-hide", "-Wno-shared"])
    vu.set_sim_option("ghdl.elab_flags", ["-frelaxed"])
    # Large word arrays in testbench processes exceed the default stack limit of GHDL. Extra simulation flags for
    # debugging, for example a waveform: SPP_GHDL_SIM_FLAGS="--vcd=D:/tmp/wave.vcd --read-wave-opt=D:/tmp/wave.opt"
    extra = os.environ.get("SPP_GHDL_SIM_FLAGS", "").split()
    vu.set_sim_option("ghdl.sim_flags", ["--max-stack-alloc=0"] + extra)
    vu.set_sim_option("disable_ieee_warnings", True)
    vu.add_compile_option("modelsim.vcom_flags", ["-suppress", "1346,1236,1090"])
    vu.set_sim_option("modelsim.vsim_flags", ["-suppress", "3009,3473,8684,8683"])


def merge_coverage(results):
    """Merges the coverage of all tests and writes a text report (with --coverage)."""
    if not COVERAGE:
        return
    out = ROOT / "coverage"
    out.mkdir(exist_ok=True)
    ucdb = out / "coverage.ucdb"
    results.merge_coverage(file_name=str(ucdb))
    vcover = Path(os.environ["VUNIT_MODELSIM_PATH"]) / "vcover"
    subprocess.run([str(vcover), "report", "-details", "-output", str(out / "coverage_report.txt"), str(ucdb)],
                   check=False)
    subprocess.run([str(vcover), "report", "-byfile", "-output", str(out / "coverage_byfile.txt"), str(ucdb)],
                   check=False)


def write_compile_order():
    """Writes compile_order.txt: the synthesis sources of the library openspp (hdl/<module>/src/ of every module of
    component_list.txt), one path per line relative to the repository root. The modules keep the order of
    component_list.txt, the files of a module the order of the VUnit dependency scan; the scan also checks that no
    file depends on a later one. Open Logic is a separate library and only referenced, so the order does not depend
    on the submodules."""
    vu = VUnit.from_argv(argv=[])
    vu.add_external_library("olo", ROOT / "open-logic")
    lib = vu.add_library("openspp")
    modules = read_component_list()
    for module in modules:
        lib.add_source_files(sorted((ROOT / module / "src").glob("*.vhd")))

    def rel(source):
        return Path(source.name).resolve().relative_to(ROOT).as_posix()

    scan = [rel(source) for source in vu.get_compile_order() if source.library.name == "openspp"]
    order = sorted(scan, key=lambda path: (modules.index(Path(path).parents[1].as_posix()), scan.index(path)))
    for source in lib.get_source_files():
        later = [rel(dep) for dep in vu.get_compile_order([source]) if order.index(rel(dep)) > order.index(rel(source))]
        if later:
            sys.exit(f"{rel(source)} depends on {', '.join(later)}: correct the order of component_list.txt")
    (ROOT / "compile_order.txt").write_text("".join(path + "\n" for path in order), encoding="utf-8", newline="\n")


def main():
    if COMPILE_ORDER:
        write_compile_order()
        return
    vu = VUnit.from_argv()
    vu.add_vhdl_builtins()
    add_open_logic(vu)
    add_uvvm(vu)
    lib, modules = add_openspp(vu)
    # Simulator options first: options of a module configuration (vunit_config.py) override them
    set_simulator_options(vu)
    apply_module_configs(lib, modules)
    if COVERAGE:
        vu.set_sim_option("enable_coverage", True)
    vu.main(post_run=merge_coverage)


if __name__ == "__main__":
    main()
