# spp_apid_table

APID table (TB-1, TB-2): one entry per APID in an ECC-protected, scrubbed RAM, initialised after the reset and
accessed by two clients with locked read-modify-write transactions.

| Document | Content |
| --- | --- |
| [Specification](docs/specification.md) | Requirements and configuration |
| [Architecture](docs/architecture.md) | Arbitration, transactions, fault tolerance |
| [Verification plan](docs/verification_plan.md) | Test cases |
| [Verification report](docs/verification_report.md) | Results |

Tests: `python run.py -p 4 "*spp_apid_table*"`

| File | Content |
| --- | --- |
| `tb/spp_apid_table_tb.vhd` | VUnit runner with the DUT, transaction procedures and a reference model |
