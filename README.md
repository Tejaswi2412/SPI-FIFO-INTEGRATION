# SPI + FIFO Integration — Verilog Implementation

[![Language](https://img.shields.io/badge/Language-Verilog-blue)](https://img.shields.io/badge/Language-Verilog-blue) [![Simulator](https://img.shields.io/badge/Simulator-Icarus%20Verilog-green)](https://img.shields.io/badge/Simulator-Icarus%20Verilog-green) [![Status](https://img.shields.io/badge/Status-Verified-brightgreen)](https://img.shields.io/badge/Status-Verified-brightgreen) [![Mode](https://img.shields.io/badge/SPI-Mode%200-orange)](https://img.shields.io/badge/SPI-Mode%200-orange) [![FIFO](https://img.shields.io/badge/FIFO-8%20x%208--bit-purple)](https://img.shields.io/badge/FIFO-8%20x%208--bit-purple)

A fully verified **buffered SPI transmission system** implemented in Verilog HDL. A synchronous FIFO buffers multiple bytes upfront, and a custom Controller FSM automatically drains them one by one through an SPI Master — without any intervention after the initial writes. Verified using Icarus Verilog with GTKWave waveform analysis.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Module Description](#module-description)
- [Controller FSM](#controller-fsm)
- [Design Specifications](#design-specifications)
- [Key Design Decisions](#key-design-decisions)
- [Simulation Results](#simulation-results)
- [How to Run](#how-to-run)
- [Directory Structure](#directory-structure)
- [Tools Used](#tools-used)
- [Synthesis Results](#synthesis-results)
- [Future Improvements](#future-improvements)

---

## Overview

In standard SPI, the master must wait for each byte to finish before initiating the next. This project solves that by inserting a **synchronous FIFO buffer** between the data source and the SPI master. A **Controller FSM** monitors both modules and automatically manages the handoff:

```
Write multiple bytes → FIFO stores them → Controller drains them → SPI transmits one by one
```

This is the same architecture used in real microcontroller SPI peripherals (STM32, ATSAM) where a TX FIFO decouples the CPU write rate from the SPI transmission rate.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        spi_fifo_top.v                           │
│                                                                 │
│  wr_en ──────→ ┌────────────┐  wr_en_mem  ┌──────────┐          │
│  data_in ────→ │ fifo_ctrl  │ ──────────→ │ fifo_mem │          │
│                │  (pointers │  rd_en_mem  │ (8x8b    │          │
│  rd_en ──────→ │  & flags)  │ ──────────→ │  memory) │          │
│                └────────────┘             └──────────┘          │
│                  ↑  ↓                        ↓ data_out         │
│               empty full                     ↓                  │
│                  ↑  ↓                        ↓                  │
│             ┌──────────────────────────┐     ↓                  │
│             │     Controller FSM       │─────┘                  │
│             │  IDLE→READ→WAIT1→LOAD    │                        │
│             │  →WAIT→SENDING→IDLE      │                        │
│             └──────────────────────────┘                        │
│                        ↓ start                                  │
│                 ┌─────────────┐                                 │
│                 │  spi_master │──→ MOSI, SCLK, CS               │
│                 └─────────────┘←── MISO                         │
└─────────────────────────────────────────────────────────────────┘
```

**Key design choice:** The Controller FSM is the only new logic written for this integration — approximately 30 lines. Both FIFO and SPI modules reused unchanged from standalone implementations.

---

## Module Description

### 1. `fifo_ctrl.v` — FIFO Controller
Manages read/write pointers and generates full/empty flags using 4-bit pointer MSB trick.

```
empty = (wr_ptr == rd_ptr)
full  = (wr_ptr[2:0] == rd_ptr[2:0]) && (wr_ptr[3] != rd_ptr[3])
```

### 2. `fifo_mem.v` — FIFO Memory
8-slot × 8-bit synchronous register array. `data_out` valid one cycle after `rd_en`.

### 3. `spi_master.v` — SPI Master (Mode 0)
FSM-based, clock divider (SCLK = 2MHz from 50MHz), shifts out MSB first on MOSI, samples MISO on rising edge.

### 4. `spi_fifo_top.v` — Top Level + Controller FSM
Instantiates all three modules and contains the 6-state Controller FSM.

| Port | Direction | Width | Description |
| --- | --- | --- | --- |
| `clk` | input | 1 | System clock |
| `reset` | input | 1 | Synchronous reset |
| `wr_en` | input | 1 | Write enable — push data into FIFO |
| `data_in` | input | 8 | Data byte to write into FIFO |
| `MISO` | input | 1 | SPI MISO from slave |
| `MOSI` | output | 1 | SPI MOSI to slave |
| `sclk` | output | 1 | SPI clock to slave |
| `cs` | output | 1 | SPI chip select to slave |
| `done` | output | 1 | Pulses HIGH after each byte transmitted |

---

## Controller FSM

```
   ┌──────────────────────────────────────────┐
   ↓                                          │
┌──────┐  !empty && cs   ┌──────┐             │
│ IDLE │ ──────────────→ │ READ │ rd_en=1     │
└──────┘                 └──────┘             │
                            ↓                 │
                        ┌───────┐             │
                        │ WAIT1 │ (1 cycle    │
                        └───────┘  latency)   │
                            ↓                 │
                        ┌──────┐              │
                        │ LOAD │ start=1      │
                        └──────┘              │
                            ↓                 │
                        ┌──────┐              │
                        │ WAIT │ wait cs=0    │
                        └──────┘              │
                            ↓ !cs             │
                      ┌─────────┐             │
                      │ SENDING │ wait cs=1   │
                      └─────────┘             │
                            │ cs=1            │
                            └─────────────────┘
```

| State | Action | Exit Condition |
| --- | --- | --- |
| `IDLE` | Wait | `!empty && cs` |
| `READ` | Assert `rd_en=1` | Always next cycle |
| `WAIT1` | Wait for data_out valid (memory latency) | Always next cycle |
| `LOAD` | Assert `start=1` to SPI | Always next cycle |
| `WAIT` | Wait for SPI to begin (`cs` goes LOW) | `cs == 0` |
| `SENDING` | Wait for SPI to finish (`cs` goes HIGH) | `cs == 1` |

---

## Design Specifications

| Parameter | Value |
| --- | --- |
| Clock Frequency | 50 MHz |
| FIFO Depth | 8 bytes |
| FIFO Width | 8 bits |
| SPI Mode | Mode 0 (CPOL=0, CPHA=0) |
| SPI Clock Divider | 25 (SCLK = 2 MHz) |
| Controller FSM States | 6 |
| HDL Standard | Verilog |

---

## Key Design Decisions

### Producer-Consumer Decoupling
Testbench writes all bytes in consecutive clock cycles. SPI transmits one byte every ~1.25 µs. FIFO absorbs the rate mismatch.

### Controller FSM — Internal Signals Only
`rd_en` and `start` are internal `reg` signals — not exposed as ports. All read timing and SPI triggering handled autonomously.

### Default Signal Deassert
`rd_en` and `start` set to 0 at top of always block — asserted for exactly one clock cycle only.

### WAIT1 State
`fifo_mem` uses registered reads — `data_out` appears one cycle after `rd_en`. WAIT1 accounts for this pipeline delay.

---

## Simulation Results

**Test vector:** Three bytes — `0xAA`, `0xBB`, `0xCC`

```
Transfer 1: shift_reg = 10101010 = 0xAA ✅
Transfer 2: shift_reg = 10111011 = 0xBB ✅
Transfer 3: shift_reg = 11001100 = 0xCC ✅

cs toggled exactly 3 times ✅
empty=1 after all transfers ✅
cs=1 at end — SPI returned to idle cleanly ✅
```

---

## How to Run

### Compile
```
iverilog -o spi_fifo_tb spi_fifo_tb.v spi_fifo_top.v fifo_ctrl.v fifo_mem.v spi_master.v
```

### Simulate
```
vvp spi_fifo_tb
```

### View Waveforms
```
gtkwave spi_fifo_tb.vcd
```

---

## Directory Structure

```
spi_fifo_integration/
├── fifo_ctrl.v        # FIFO controller — pointers, flags, qualified enables
├── fifo_mem.v         # FIFO memory — 8x8-bit synchronous register array
├── spi_master.v       # SPI master — Mode 0, FSM-based, clock divider
├── spi_fifo_top.v     # Top-level integration + Controller FSM
├── spi_fifo_tb.v      # Testbench — burst writes, automatic drain verification
└── README.md          # This file
```

---

## Tools Used

| Tool | Version | Purpose |
| --- | --- | --- |
| Icarus Verilog | 12.0 | HDL compilation and simulation |
| GTKWave | 3.3.108 | Waveform visualization |
| VS Code | Latest | Code editor |

---

## Synthesis Results

**Target Device:** Xilinx Artix-7 `xc7a35tcpg236-1` | **Tool:** Vivado 2025.1

| Resource | Used | Available | Utilization |
| --- | --- | --- | --- |
| Slice LUTs | 44 | 20800 | <1% |
| Slice Registers (FFs) | 48 | 41600 | <1% |
| Bonded IOB | 15 | 106 | <1% |
| BUFGCTRL | 1 | 32 | <1% |

**Timing Summary**
- Failing Endpoints: **0**
- Total Negative Slack (TNS): 0.000 ns
- Worst Negative Slack (WNS): inf

### Schematic
<img width="1920" height="1020" alt="spi_fifo_schematic" src="https://github.com/user-attachments/assets/18545ec9-e1a5-41eb-8c21-f2fb5cf94bca" />


### Utilization Report
<img width="1920" height="1013" alt="spififo-utilization" src="https://github.com/user-attachments/assets/d35e98ed-d5fd-4649-be91-fd2df76a27ee" />


### Timing Report
<img width="1920" height="1020" alt="spi_fifo_timing" src="https://github.com/user-attachments/assets/b4703d31-98c4-48be-8a4b-a850c7382223" />


---

## Future Improvements

- [ ] Make FIFO depth and SPI clock divider configurable via parameters
- [ ] Support continuous streaming — write new bytes while transmission is in progress
- [ ] Add SPI Mode 1/2/3 support via CPOL/CPHA parameters
- [ ] Implement slave-select for multi-slave SPI bus
- [ ] Synthesize and test on Basys3/Nexys4 FPGA board
- [ ] Upgrade testbench to SystemVerilog with assertions and coverage

---

## Related Projects

- [UART Controller](https://github.com/Tejaswi2412/UART-TRANSMITTER-RECEIVER-VERILOG)
- [Synchronous FIFO](https://github.com/Tejaswi2412/SYNCHRONOUS-FIFO)
- [SPI Master](https://github.com/Tejaswi2412/SPI)

---

## Author

**Tejaswi** ECE Student | Hardware Design Enthusiast  
Building skills in VLSI, FPGA, and SoC design

---

*Built from scratch — FIFO and SPI modules reused from prior projects, integrated via a custom Controller FSM written and debugged independently.*
