# spp_nchar: Specification

## 1. Overview

`spp_nchar` is the adapter between the link ports of the core and a SpaceWire port of OpenWire (block AD-1 of the
architecture). The core carries packets on streams of `DataWidth_g` bits with byte enables and an EEP flag; the
SpaceWire port carries N-Char streams: one data character per beat and the end of packet marker as a separate beat
with `TLast` = '1' and `TData(0)` = '0' for EOP or '1' for EEP.

## 2. Requirements

| ID | Requirement | Clauses |
| --- | --- | --- |
| AD-IF-01 | The adapter shall take the link stream of the core (`DataWidth_g` bits, `Keep`, `Last`, EEP flag in `TUser`) and give an N-Char stream, and take an N-Char stream and give the link stream of the core. | none |
| AD-IF-02 | The reset input shall return both directions from any state to the start of a packet. | none (D14) |
| AD-TX-01 | Every link packet shall become its bytes as data characters, first byte first, followed by the marker EOP, or EEP when the EEP flag of its last beat is set. | CPTP 5.4.1.8 |
| AD-TX-02 | A link packet whose last beat has no byte enables shall end with its marker after the bytes of the earlier beats; a link packet without any byte shall produce no character. | none (D15) |
| AD-RX-01 | The data characters of an N-Char packet shall become a link packet, first character in lane 0, with the EEP flag of the last beat set when the marker is an EEP; a marker without data characters shall be discarded. | CPTP 5.4.1.8 |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of the link streams |
