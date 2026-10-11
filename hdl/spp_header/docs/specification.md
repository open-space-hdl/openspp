# spp_header: Specification

## 1. Overview

`spp_header` holds the two stream stages that put a header in front of a packet and remove the first bytes of a packet
(blocks CM-1 and CM-2 of the architecture). The packet assembly and the encapsulation use the insertion, the
decapsulation and the packet extraction use the removal. Both keep one beat per clock cycle on streams of 8 to 128
bits with byte enables, so that the protocol blocks need no width conversion (architecture P6, D13).

## 2. Requirements

### 2.1 Interfaces

| ID | Requirement | Clauses |
| --- | --- | --- |
| CM-IF-01 | Both stages shall take and give packets as valid / ready streams of `DataWidth_g` bits (a multiple of 8 from 8 to 128) with `Keep`, `Last` and `User`: byte lane 0 holds the first byte of a beat; all bytes are valid except in the last beat of a packet, whose valid bytes are contiguous from lane 0 and at least one. Bytes of lanes without byte enable are ignored. | none |
| CM-IF-02 | `User` of an output beat shall be `User` of the latest input beat that contributed bytes to it; the header beats of the insertion carry `User` of the first input beat. | none |
| CM-IF-03 | The reset input shall return both stages from any state to the reception of a new packet within one clock cycle, with no output beat pending. | none (D14) |

### 2.2 Header insertion (CM-1)

| ID | Requirement | Clauses |
| --- | --- | --- |
| CM-IN-01 | The insertion shall output every input packet preceded by the first `In_HeaderBytes` bytes of `In_Header` (0 to `MaxHeaderBytes_g`, byte 0 first); both are sampled with the first beat of the packet. | none |
| CM-IN-02 | Without backpressure the insertion shall output one beat per clock cycle from the first to the last beat of back-to-back packets. | none (P6) |

### 2.3 Header removal (CM-2)

| ID | Requirement | Clauses |
| --- | --- | --- |
| CM-RM-01 | The removal shall output every input packet without its first `In_RemoveBytes` bytes (0 to `MaxRemoveBytes_g`, sampled with the first beat) and present the removed bytes on `Out_Header` with every output beat of the packet (byte 0 first, zero beyond the end of a shorter packet). | none |
| CM-RM-02 | A packet with no byte beyond the removed ones shall be output as one beat with `Keep` all zero, `Last` and `Out_Empty` set. | none |
| CM-RM-03 | Without backpressure the removal shall accept one input beat per clock cycle and need at most one additional clock cycle per packet. | none (P6) |

## 3. Configuration parameters

| Generic | Default | Range | Description |
| --- | --- | --- | --- |
| `DataWidth_g` | 32 | 8 to 128, multiple of 8 | Width of the streams in bits |
| `MaxHeaderBytes_g` | 6 | 1 to any | Maximum header length of the insertion |
| `MaxRemoveBytes_g` | 6 | 1 to any | Maximum number of bytes removed |
| `UserWidth_g` | 1 | 1 to any | Width of `User` |
