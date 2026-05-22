
# SPI + FIFO Integration — Verilog Implementation

![Language](https://img.shields.io/badge/Language-Verilog-blue)
![Simulator](https://img.shields.io/badge/Simulator-Icarus%20Verilog-green)
![Status](https://img.shields.io/badge/Status-Verified-brightgreen)
![Mode](https://img.shields.io/badge/SPI-Mode%200-orange)
![FIFO](https://img.shields.io/badge/FIFO-8%20x%208--bit-purple)

A fully verified **buffered SPI transmission system** implemented in Verilog HDL. A synchronous FIFO buffers multiple bytes upfront, and a custom Controller FSM automatically drains them one by one through an SPI Master — without any intervention after the initial writes. Simulated using Icarus Verilog with waveform analysis in GTKWave.

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
- [Future Improvements](#future-improvements)

---

## Overview

In standard SPI communication, the master must wait for each byte to finish transmitting before initiating the next one. This creates a tight coupling between the data producer and the SPI controller — every write must be manually triggered.

This project solves that problem by inserting a **synchronous FIFO buffer** between the data source and the SPI master. A lightweight **Controller FSM** monitors both modules and automatically manages the handoff:

```
Write multiple bytes → FIFO stores them → Controller drains them → SPI transmits one by one
```

This is the same architecture used in real microcontroller SPI peripherals (STM32, ATSAM, etc.) where a TX FIFO decouples the CPU write rate from the SPI transmission rate.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        spi_fifo_top.v                           │
│                                                                 │
│  wr_en ──────→ ┌────────────┐  wr_en_mem ┌──────────┐           │
│  data_in ────→ │ fifo_ctrl  │ ──────────→ │          │          │
│                │  (pointers │  rd_en_mem  │ fifo_mem │          │
│  rd_en ──────→ │  & flags)  │ ──────────→ │ (8x8b    │          │
│                └────────────┘             │  memory) │          │
│                  ↑  ↓                     └──────────┘          │
│               empty full                    ↓ data_out          │
│                  ↑  ↓                       ↓                   │
│             ┌──────────────────────────┐    ↓                   │
│             │     Controller FSM       │    ↓                   │
│             │  IDLE→READ→WAIT1→LOAD    │────┘                   │
│             │  →WAIT→SENDING→IDLE      │                        │
│             └──────────────────────────┘                        │
│                        ↓ start                                  │
│                 ┌─────────────┐                                 │
│                 │  spi_master │──→ MOSI                         │
│                 │  (Mode 0,   │──→ SCLK                         │
│                 │   FSM-based)│──→ CS                           │
│                 └─────────────┘←── MISO                         │
│                        ↓done                                    │
└─────────────────────────────────────────────────────────────────┘
```

**Key design choice:** The Controller FSM is the only new logic written for this integration — approximately 30 lines. Both FIFO and SPI modules are reused unchanged from their standalone implementations.

---

## Module Description

### 1. `fifo_ctrl.v` — FIFO Controller
Manages read/write pointers and generates full/empty flags. Uses a **4-bit pointer with MSB trick** for full/empty distinction without wasting memory.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `reset` | input | 1 | Synchronous reset — clears pointers |
| `wr_en` | input | 1 | Write enable from external source |
| `rd_en` | input | 1 | Read enable from Controller FSM |
| `wr_addr` | output | 3 | Write address to memory |
| `rd_addr` | output | 3 | Read address to memory |
| `full` | output | 1 | HIGH when FIFO is full (8 bytes) |
| `empty` | output | 1 | HIGH when FIFO has no data |
| `wr_en_mem` | output | 1 | Qualified write enable to memory |
| `rd_en_mem` | output | 1 | Qualified read enable to memory |

**Full/Empty detection:**
```
empty = (wr_ptr == rd_ptr)
full  = (wr_ptr[2:0] == rd_ptr[2:0]) && (wr_ptr[3] != rd_ptr[3])
```
The MSB of the pointer wraps independently — when pointers have the same lower 3 bits but different MSBs, the FIFO has wrapped exactly once — meaning it is full.

---

### 2. `fifo_mem.v` — FIFO Memory
An 8-slot, 8-bit wide register array. Writes and reads are synchronous (registered on `posedge clk`).

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `wr_en` | input | 1 | Write enable (from fifo_ctrl) |
| `rd_en` | input | 1 | Read enable (from fifo_ctrl) |
| `wr_addr` | input | 3 | Write address |
| `rd_addr` | input | 3 | Read address |
| `data_in` | input | 8 | Data to write |
| `data_out` | output | 8 | Data read out (registered — valid one cycle after rd_en) |

**Important:** `data_out` is registered. It appears **one clock cycle after** `rd_en` is asserted. The Controller FSM accounts for this with the `wait1` state.

---

### 3. `spi_master.v` — SPI Master (Mode 0)
FSM-based SPI master. Divides the system clock to generate SCLK, shifts out data MSB-first on MOSI, and samples MISO on rising edge of SCLK.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `start` | input | 1 | Pulse HIGH to begin transfer |
| `tx_data` | input | 8 | Byte to transmit |
| `MOSI` | output | 1 | Serial data output (MSB first) |
| `MISO` | input | 1 | Serial data input from slave |
| `sclk` | output | 1 | SPI clock (system clock / 25) |
| `cs` | output | 1 | Chip select (active LOW during transfer) |
| `done` | output | 1 | Pulses HIGH for one cycle when transfer complete |
| `rx_data` | output | 8 | Received byte (captured from MISO) |

**SPI FSM States:**
```
IDLE     → cs=1, wait for start=1
LOAD     → cs=0, load tx_data into shift_reg
TRANSFER → shift out 8 bits on MOSI, sample MISO
DONE_SH  → done=1, cs=1, capture rx_data → return to IDLE
```

**Clock divider:** `clk_divider = 25` — SCLK toggles every 25 system clock cycles.

---

### 4. `spi_fifo_top.v` — Top Level Integration
Instantiates all three modules and contains the Controller FSM that manages the data flow between FIFO and SPI.

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
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

### 5. `spi_fifo_tb.v` — Testbench
Writes 3 bytes into FIFO back-to-back, then lets the Controller FSM drain them automatically through SPI.

---

## Controller FSM

The Controller FSM is the core contribution of this integration project. It answers one question every clock cycle: **is there data in the FIFO and is SPI free? If yes — fetch and send.**

```
      ┌─────────────────────────────────────────────┐
      ↓                                             │
   ┌──────┐  !empty && cs   ┌──────┐                │
   │ IDLE │ ──────────────→ │ READ │                │
   └──────┘                 └──────┘                │
                               │ rd_en=1            │
                               ↓                    │
                           ┌───────┐                │
                           │ WAIT1 │  (1 cycle for  │
                           └───────┘   data_out)    │
                               │                    │
                               ↓                    │
                           ┌──────┐                 │
                           │ LOAD │  start=1        │
                           └──────┘                 │
                               │                    │
                               ↓                    │
                           ┌──────┐                 │
                           │ WAIT │  wait for cs=0  │
                           └──────┘                 │
                               │ !cs                │
                               ↓                    │
                         ┌─────────┐                │
                         │ SENDING │  wait for cs=1 │
                         └─────────┘                │
                               │ cs=1               │
                               └────────────────────┘
```

| State | Action | Exit Condition |
|-------|--------|---------------|
| `IDLE` | Wait | `!empty && cs` |
| `READ` | Assert `rd_en=1` — tell FIFO to pop a byte | Always — next cycle |
| `WAIT1` | Wait one cycle for `data_out` to become valid (registered memory latency) | Always — next cycle |
| `LOAD` | Assert `start=1` — trigger SPI transmission | Always — next cycle |
| `WAIT` | Wait for SPI to actually begin (`cs` goes LOW) | `cs == 0` |
| `SENDING` | Wait for SPI to finish transmission (`cs` goes HIGH) | `cs == 1` |

**Why WAIT and SENDING are separate states:**
When `start` is asserted, SPI takes one clock cycle to pull `cs` LOW. If WAIT checked `cs==1` immediately, it would exit before SPI started. WAIT first confirms SPI has begun (`cs=0`), then SENDING waits for completion (`cs=1`).

**Why WAIT1 state exists:**
`fifo_mem` uses a registered (synchronous) read — `data_out` appears one clock cycle after `rd_en` is asserted. WAIT1 provides that one-cycle pipeline delay before LOAD presents data to SPI.

---

## Design Specifications

| Parameter | Value |
|-----------|-------|
| Clock Frequency | 50 MHz |
| FIFO Depth | 8 bytes |
| FIFO Width | 8 bits |
| SPI Mode | Mode 0 (CPOL=0, CPHA=0) |
| SPI Clock Divider | 25 (SCLK = 2 MHz) |
| Data Bits | 8 |
| Bit Order | MSB first |
| Controller FSM States | 6 |
| HDL Standard | Verilog |

---

## Key Design Decisions

### Producer-Consumer Decoupling
The testbench (producer) writes all bytes in consecutive clock cycles without waiting. The SPI master (consumer) transmits one byte every ~1.25 µs. The FIFO absorbs the rate mismatch — this is the fundamental purpose of a buffer in hardware design.

### Controller FSM — Internal Signals Only
`rd_en` and `start` are declared as internal `reg` signals driven by the FSM — not exposed as top-level ports. The outside world only provides data and write enable. All read timing and SPI triggering is handled autonomously by the controller.

### Default Signal Deassert
`rd_en` and `start` are set to 0 at the top of the `always` block before the case statement. This ensures they are asserted for exactly one clock cycle when needed, preventing unintended repeated triggers from register hold behavior.

### Registered Memory Read Latency
`fifo_mem` uses `always@(posedge clk)` for reads — `data_out` is valid one cycle after `rd_en`. The `wait1` state in the Controller FSM explicitly accounts for this pipeline stage before asserting `start` to SPI.

### wr_en_mem and rd_en_mem Connections
`fifo_ctrl` generates qualified enable signals (`wr_en_mem`, `rd_en_mem`) that include full/empty protection. These must be connected to `fifo_mem` — connecting raw `wr_en`/`rd_en` would bypass overflow and underflow protection.

### Non-Blocking Assignments
All sequential logic uses `<=` inside `always@(posedge clk)` blocks, correctly modeling flip-flop behavior and avoiding simulation race conditions.

---

## Simulation Results

**Test vector:** Three bytes written into FIFO — `0xAA`, `0xBB`, `0xCC`

**Expected MOSI bit patterns (MSB first):**
```
0xAA = 10101010
0xBB = 10111011
0xCC = 11001100
```

**Verified via shift_reg inspection:**
```
Transfer 1: shift_reg = 10101010 = 0xAA ✅
Transfer 2: shift_reg = 10111011 = 0xBB ✅
Transfer 3: shift_reg = 11001100 = 0xCC ✅
```

**Terminal output:**
```
VCD info: dumpfile spi_fifo_tb.vcd opened for output.
Time=1690000   bit_count=0   ← Byte 1, bit 0 shifting out
...
Time=8690000   bit_count=7   ← Byte 1 complete (8 bits)
Time=10370000  bit_count=0   ← Byte 2 starts automatically
...
Time=17370000  bit_count=7   ← Byte 2 complete
Time=19050000  bit_count=0   ← Byte 3 starts automatically
...
Time=26050000  bit_count=7   ← Byte 3 complete
Time=30110000  cs=1 empty=1  ← SPI idle, FIFO drained ✅
```

**What this confirms:**
- All 3 bytes transmitted completely (bit_count 0→7 three times)
- FIFO drained automatically without testbench intervention after writes
- `cs` toggled exactly 3 times — one transaction per byte
- `empty=1` after all transfers — no bytes left behind
- `cs=1` at end — SPI returned to idle cleanly

---

## How to Run

### Prerequisites
- [Icarus Verilog](http://iverilog.icarus.com/) — HDL simulator
- [GTKWave](http://gtkwave.sourceforge.net/) — Waveform viewer

### Compile
```bash
iverilog -o spi_fifo_tb spi_fifo_tb.v spi_fifo_top.v fifo_ctrl.v fifo_mem.v spi_master.v
```

### Simulate
```bash
vvp spi_fifo_tb
```

### View Waveforms
```bash
gtkwave spi_fifo_tb.vcd
```

### Expected Output
```
VCD info: dumpfile spi_fifo_tb.vcd opened for output.
Time=8690000   bit_count=7
Time=17370000  bit_count=7
Time=26050000  bit_count=7
Time=30110000  cs=1 empty=1
$finish called at 530110000
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
|------|---------|---------|
| Icarus Verilog | 12.0 | HDL compilation and simulation |
| GTKWave | 3.3.108 | Waveform visualization |
| VS Code | Latest | Code editor |

---

## Future Improvements

- [ ] Add full/done status output ports for system-level monitoring
- [ ] Make FIFO depth and SPI clock divider configurable via parameters
- [ ] Support continuous streaming — write new bytes while transmission is in progress
- [ ] Add SPI Mode 1/2/3 support via CPOL/CPHA parameters
- [ ] Implement slave-select for multi-slave SPI bus
- [ ] Add underflow/overflow error flags
- [ ] Synthesize and test on Basys3/Nexys4 FPGA board
- [ ] Upgrade testbench to SystemVerilog with assertions and coverage

---

## Related Projects

- [UART Controller](../uart/) — Asynchronous serial communication
- [Synchronous FIFO](../fifo/) — Standalone FIFO implementation
- [SPI Master](../spi/) — Standalone SPI master

---

## Author

**Tejaswi**
ECE Student | Hardware Design Enthusiast
Building skills in VLSI, FPGA, and SoC design

---

*Built from scratch — FIFO and SPI modules reused from prior projects, integrated via a custom Controller FSM written and debugged independently.*
