# ---------------------------------------------------------------------------------------------------
# Copyright (c) 2026 by Julian Schneider
# Authors: Julian Schneider
# ---------------------------------------------------------------------------------------------------
"""Compliance matrix of OpenSPP.

Usage: python tools/compliance.py [--check]
Reads the requirement traceability matrix of docs/architecture.md (section 10), the requirements of every
hdl/<module>/docs/specification.md (ID and clauses) and the test cases of every verification_plan.md (test and
requirement IDs), and writes docs/compliance.md: for every clause of the matrix the requirements that trace to it and
the test cases that verify them. Clauses carry the standard they belong to: "SPP" for CCSDS 133.0-B-2 and "CPTP" for
ECSS-E-ST-50-53C, for example "SPP 4.1.3.5" or "CPTP 5.5.4.4a"; a clause without a standard belongs to the standard
named before it in the same cell. With --check the file is not written; the exit code is 1 when a clause in the scope
of the core has no test case, when a requirement has no test case, when a test case of a plan is not run or when
docs/compliance.md is not current.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "compliance.md"
STANDARDS = ("SPP", "CPTP")
# Clause with optional sub-item letters and an optional range end: '5.5.2 to 5.5.4', '5.5.4.3a'
RANGE_RE = re.compile(r"(\d+(?:\.\d+)+)(?:[a-z]+\d*)?(?:\s+to\s+(\d+(?:\.\d+)+))?")
STD_RE = re.compile(r"\b(SPP|CPTP)\b")
REQ_RE = re.compile(r"^[A-Z]+(-[A-Z0-9]+)*-\d{2}$")


def table_rows(text):
    """Rows of markdown tables as lists of cells (header and separator rows included)."""
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("|") and line.endswith("|"):
            yield [c.strip() for c in line.strip("|").split("|")]


def clauses(cell):
    """Clauses of a cell as (standard, clause) pairs, ranges expanded: 'SPP 4.1.3.5, 4.1.2; CPTP 5.1.4 to 5.1.6'
    -> [('SPP', '4.1.3.5'), ('SPP', '4.1.2'), ('CPTP', '5.1.4'), ('CPTP', '5.1.5'), ('CPTP', '5.1.6')]."""
    result = []
    # Segments from one standard name to the next; text before the first standard name is ignored
    marks = [(m.start(), m.group(1)) for m in STD_RE.finditer(cell)] + [(len(cell), None)]
    for i, (start, std) in enumerate(marks[:-1]):
        segment = cell[start:marks[i + 1][0]]
        for m in RANGE_RE.finditer(segment):
            first, last = m.group(1), m.group(2)
            if last:
                fp, lp = first.split("."), last.split(".")
                if len(fp) == len(lp) and fp[:-1] == lp[:-1] and int(fp[-1]) <= int(lp[-1]):
                    result += [(std, ".".join(fp[:-1] + [str(n)])) for n in range(int(fp[-1]), int(lp[-1]) + 1)]
                else:
                    result += [(std, first), (std, last)]
            else:
                result.append((std, first))
    return result


def expand_ids(cell):
    """Requirement IDs of a test row: 'SE-IF-01, SE-AS-01 to 03, RE-DM-01, 02' -> full list."""
    ids = []
    last = None
    for part in [p.strip() for p in cell.split(",")]:
        m = re.match(r"^([A-Z]+(?:-[A-Z0-9]+)*-)(\d+)(?:\s+to\s+(?:[A-Z]+(?:-[A-Z0-9]+)*-)?(\d+))?", part)
        if m:
            prefix, first = m.group(1), int(m.group(2))
            last_n = int(m.group(3)) if m.group(3) else first
            width = len(m.group(2))
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
            last = (prefix, width)
            continue
        m = re.match(r"^(\d+)(?:\s+to\s+(\d+))?$", part)
        if m and last:
            prefix, width = last
            first = int(m.group(1))
            last_n = int(m.group(2)) if m.group(2) else first
            ids += [f"{prefix}{n:0{width}d}" for n in range(first, last_n + 1)]
    return ids


def load_requirements():
    """Requirements of the module specifications: ID -> (module, clauses)."""
    reqs = {}
    for spec in sorted(ROOT.glob("hdl/*/docs/specification.md")):
        module = spec.parent.parent.name
        for row in table_rows(spec.read_text(encoding="utf-8")):
            if len(row) >= 3 and REQ_RE.match(row[0]):
                reqs[row[0]] = (module, clauses(row[-1]))
    return reqs


def load_tests():
    """Test cases of the verification plans: test ID -> requirement IDs. Also returns the test names of the plans
    that no testbench of the repository runs."""
    tests = {}
    names = set()
    for plan in sorted(ROOT.glob("hdl/*/docs/verification_plan.md")):
        for row in table_rows(plan.read_text(encoding="utf-8")):
            if len(row) >= 3 and row[0].startswith("`test_"):
                m = re.search(r"\((TC-[A-Z]+-\d+)\)", row[0])
                tid = m.group(1) if m else row[0]
                tests.setdefault(tid, set()).update(expand_ids(row[-1]))
                names.add(row[0].split("`")[1])
    run_names = set()
    for tb in ROOT.glob("hdl/*/tb/*.vhd"):
        run_names.update(re.findall(r'run\("(test_\w+)"\)', tb.read_text(encoding="utf-8")))
    return tests, sorted(names - run_names)


def load_matrix():
    text = (ROOT / "docs" / "architecture.md").read_text(encoding="utf-8")
    section = text[text.index("## 10 Requirement traceability matrix"):text.index("## 11 ")]
    rows = []
    for row in table_rows(section):
        if len(row) >= 5 and STD_RE.match(row[0]):
            rows.append(row[:5])
    return rows


def matches(req_clauses, row_clauses):
    for rs, rc in req_clauses:
        for s, c in row_clauses:
            if rs == s and (rc == c or rc.startswith(c + ".")):
                return True
    return False


def test_key(tid):
    parts = tid.split("-")
    return (parts[1], int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0)


def main():
    reqs = load_requirements()
    tests, not_run = load_tests()
    matrix = load_matrix()
    lines = [
        "# OpenSPP: Compliance Matrix",
        "",
        "Generated by `python tools/compliance.py` from the requirement traceability matrix of the",
        "[architecture](architecture.md) (section 10), the requirements of the module specifications and the test cases",
        "of the module verification plans. `python tools/compliance.py --check` fails when a clause or a requirement",
        "has no test case, or when a test case of a plan is not run by a testbench.",
        "",
        "## 1. Clauses",
        "",
        "SPP: CCSDS 133.0-B-2 Space Packet Protocol. CPTP: ECSS-E-ST-50-53C SpaceWire CCSDS packet transfer protocol.",
        "A clause is listed with every requirement whose reference lies in the clause, and with the test cases that",
        "verify these requirements. The interpretations of the standards are listed in the sections \"Interpretation of",
        "the standard\" of the module specifications.",
        "",
        "| Clause | Title | Owner | Requirements | Test cases | Status |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    missing = []
    counts = {}
    for clause, title, owner, _, _ in matrix:
        cl = clauses(clause)
        req_ids = sorted(r for r, (_, rc) in reqs.items() if matches(rc, cl))
        test_ids = sorted({t for t, ids in tests.items() if ids & set(req_ids)}, key=test_key)
        if owner.startswith("Not implemented"):
            status = "Not implemented"
        elif owner.startswith("User"):
            status = "User obligation"
        elif test_ids:
            status = "Verified"
        else:
            status = "Not traced"
            missing.append(clause)
        counts[status] = counts.get(status, 0) + 1
        lines.append(f"| {clause} | {title} | {owner} | {', '.join(req_ids) or '-'} | {', '.join(test_ids) or '-'} | "
                     f"{status} |")
    summary = "; ".join(f"{k.lower()}: {v}" for k, v in sorted(counts.items()))
    lines += [
        "",
        f"Clauses: {len(matrix)}; {summary}.",
        "",
        "## 2. Requirements",
        "",
        "Requirements of the module specifications and the test cases that verify them (requirements without a clause",
        "included).",
        "",
        "| Module | Requirements | Verified by a test case | Without a test case |",
        "| --- | --- | --- | --- |",
    ]
    covered = set().union(*tests.values()) if tests else set()
    untested = sorted(r for r in reqs if r not in covered)
    for module in sorted({m for m, _ in reqs.values()}):
        ids = [r for r, (m, _) in reqs.items() if m == module]
        gaps = [r for r in ids if r not in covered]
        lines.append(f"| `{module}` | {len(ids)} | {len(ids) - len(gaps)} | {', '.join(gaps) or '-'} |")
    lines += [
        "",
        f"Requirements: {len(reqs)}; without a test case: {len(untested)}; test cases of the plans not run by a "
        f"testbench: {len(not_run)}.",
        "",
    ]
    text = "\n".join(lines)
    stale = False
    if "--check" not in sys.argv:
        OUT.write_text(text, encoding="utf-8", newline="\n")
        print(f"written {OUT.relative_to(ROOT)}")
    elif not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
        stale = True
        print(f"{OUT.relative_to(ROOT)} is not current: run python tools/compliance.py")
    for c in missing:
        print(f"clause not traced: {c}")
    for r in untested:
        print(f"requirement without a test case: {r}")
    for n in not_run:
        print(f"test case of a plan not run by a testbench: {n}")
    failed = missing or untested or not_run or stale
    sys.exit(1 if failed and "--check" in sys.argv else 0)


if __name__ == "__main__":
    main()
