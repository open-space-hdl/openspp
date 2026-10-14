# spp_send: Verification Report

## 1. Test results

Run on 2026-10-14 with GHDL 6.0.0 (mcode), VUnit 5.0.0.dev7, UVVM 2026.03.20: `python run.py -p 3 "*spp_send*"`.

| Testbench | Tests | Passed |
| --- | --- | --- |
| `spp_send_tb` | 15 test cases in 25 configurations | 25 |

Line rate (TC-SE-11): 100 Octet Strings of 256 bytes left the output in 6600 cycles for 6600 beats at 32 bits and in
1700 cycles for 1700 beats at 128 bits: no cycle between the packets.

QuestaSim (Questa Sim Microchip Edition 2024.3): the same tests pass in the regression with code coverage
(`python run.py --questa --coverage -p 1`); the coverage is in [docs/coverage.md](../../../docs/coverage.md).

## 2. Summary

All test cases pass; every requirement of the specification is covered (see the verification plan). VSG reports no
errors and no warnings; `ghdl --synth` elaborates `spp_send` without latches.

Findings:

| Finding | Resolution |
| --- | --- |
| The EEP flag of a packet with a double error in its data was set on every beat after the error, while the interface defines it with the last beat | The flag is set with the last beat only (TC-SE-12) |
| GHDL synthesis rejected the byte multiplexers of the header stages (indices guarded only by run-time conditions) | Multiplexers written as comparisons of output position and lane (`spp_header`) |
| The receiving end found that PDL + 7 was computed in 16 bits, so a Space Packet of the maximum length (PDL 65535) failed the length check of the Packet Service | 17-bit arithmetic; TC-SE-07 sends a Space Packet of 65542 bytes on a Packet Service port |
| Code coverage: the saturation of the byte count (SDUs beyond 131071 bytes) and a double error in the last word of an SDU without an earlier one were not exercised | TC-SE-07 and TC-SE-12 extended |
| An Octet String without any byte (one last beat without byte enables) was accepted and left as a Space Packet of 6 bytes without Packet Data Field (SPP 3.2.3.1, 4.1.4.1.2) | Rejected with reason 0x02 (SE-BF-04, TC-SE-15) |
| A last beat without byte enables after the bytes of an SDU left the output as a beat without bytes | `Last` follows the remaining byte count and the stored beat is skipped (SE-IF-07, D15, TC-SE-15) |
| The packet assembly evaluated undefined registers (byte count, header length) while idle: metavalue warnings in simulation | The registers are reset (D16); TC-CO-11 checks it at core level |
