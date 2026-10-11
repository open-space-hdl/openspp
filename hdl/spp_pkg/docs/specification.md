# spp_pkg: Specification

## 1. Overview

`spp_pkg` holds what all modules share: the constants of the standards, the layouts of `TUser` on the ports, the error
codes and the functions of the Packet Primary Header. The stream and packet models of `tb/` belong to the verification
environment of every module; their self-test is part of this module.

## 2. Requirements

| ID | Requirement | Clauses |
| --- | --- | --- |
| PK-FN-01 | `primaryHeader` shall return the six octets of the Packet Primary Header (version '000', Packet Type, Secondary Header Flag, APID, Sequence Flags, Packet Sequence Count or Packet Name, Packet Data Length) with bit 0 of the header as the most significant bit of the first octet; octet 0 in bits 7:0. | SPP 4.1.3.1, 4.1.3.2, 4.1.3.3.1, 4.1.3.3.2, 4.1.3.4.1, 4.1.3.5 |
| PK-FN-02 | `hdrVersion`, `hdrType`, `hdrShf`, `hdrApid`, `hdrFlags`, `hdrCount` and `hdrPdl` shall return the fields of a header given as six octets. | SPP 4.1.3.1 |
| PK-FN-03 | `keepOfBytes(n, w)` shall return the byte enables of the first `n` of `w` bytes (all for `n` >= `w`), `bytesOfKeep` the number of set byte enables. | none |
| PK-CN-01 | The constants shall hold the values of the standards: Space Packet length 7 to 65542 octets, Octet String length up to 65536 octets, Packet Primary Header of 6 octets, Packet Version Number '000', Idle APID all ones, Sequence Flags '11' for unsegmented data, count modulo 16384, Protocol Identifier 2, Reserved 0, default Target Logical Address 0xFE. | SPP 3.2.3.1, 4.1.2.2, 4.1.3.3.4.4, 4.1.3.4.2.2; CPTP 5.3.2, 5.3.3, 5.3.4 |
| PK-TB-01 | The stream sink of the testbenches shall report a wrong byte, a wrong packet length, a wrong `TUser` on any beat, an unexpected packet and, through `tbWaitEmpty`, a missing packet. | none (verification environment) |
