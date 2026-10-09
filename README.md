# FPGA Build Challenge 2026
### FPGA-Based Digital Design, Hardware Acceleration & Fault Diagnosis

A collection of five FPGA design projects developed as part of the **V-SPACE FPGA BuildX Challenge 2026**, spanning serial communication, network-on-chip routing, adaptive arithmetic hardware, neuromorphic computing, and hardware fault diagnosis.

---

## Team Information

| Field | Details |
|---|---|
| **Team Name** | LeadHerBoard |
| **Team Leader** | Anjani Kadambari |
| **Team Members** | Nedunuri Avinash, Peyyala Ganesh Krishna Vamshi |
| **Registration Numbers** | 23BEC0276, 23BVD0009, 23BVD0021 | 

## Hardware Platform

- **Development Board:** Terasic DE10-Nano
- **FPGA Device:** Intel Cyclone V SoC
- **Device Part Number:** `5CSEBA6U23I7`
- **Design Languages:** Verilog HDL and SystemVerilog
- **Development Environment:** Intel Quartus Prime

---

## Project Portfolio

### 01 · Beginner 1
**FPGA-Based Self-Correcting UART with Real-Time Baud Detection**

Develops a UART communication architecture incorporating real-time baud-rate detection and correction mechanisms to improve serial communication reliability.

**Key design components**
- UART transmitter and receiver
- Baud-rate detection and generation
- Synchronization and FIFO buffering
- Error-control logic

**Focus:** Reliable serial communication and modular RTL design.

**Project files:** [`Experiment-1-Beginner/`](Experiment-1-Beginner/)

---

### 02 · Beginner 2
**FPGA-Based Congestion-Aware Packet Router with Dynamic Arbitration**

Implements a packet-routing architecture designed to manage packet movement through routing computation, buffering, switching, and arbitration.

**Key design components**
- Routing computation
- Input buffering
- Switching architecture
- Switch allocation and arbitration

**Focus:** Packet management, routing decisions, and efficient digital communication.

**Project files:** [`Experiment-2-Beginner/`](Experiment-2-Beginner/)

---

### 03 · Intermediate 1
**FPGA-Based Adaptive-Precision MAC Accelerator for Energy-Efficient Computing**

Explores a configurable Multiply-Accumulate (MAC) accelerator using a dedicated arithmetic datapath and precision-control logic.

**Key design components**
- MAC computational core
- Adaptive precision control
- Configurable arithmetic operations
- FPGA-oriented datapath design

**Focus:** Investigating the trade-offs between arithmetic precision, hardware cost, and energy-efficient computation.

**Project files:** [`Experiment-3-Intermediate/`](Experiment-3-Intermediate/)

---

### 04 · Intermediate 2
**FPGA-Based Event-Driven Spiking Neural Network (SNN) Accelerator for Handwritten Digit Recognition**

Explores event-driven neuromorphic computing through a Spiking Neural Network (SNN) architecture for handwritten digit recognition.

**Key design focus**
- Spiking-neuron computation
- Event-driven processing
- Neural-network hardware acceleration
- Efficient implementation of computational workloads

**Focus:** Exploring neuromorphic architectures and their potential for hardware-efficient inference.

**Project files:** [`Experiment-4-Intermediate/`](Experiment-4-Intermediate/)

---

### 05 · Advanced
**FPGA-Based Autonomous Hardware Failure Diagnosis and Fault Localization Engine**

Develops an RTL-based architecture for investigating hardware fault detection and localization in digital circuits.

**Key design components**
- Fault-injection cells
- Scan-control logic
- Fault-mask collection
- Cone-intersection logic
- Fault localization architecture

**Focus:** Structured fault analysis and logic-based hardware diagnosis.

**Project files:** [`Experiment-5-Advanced/`](Experiment-5-Advanced/)

---

## Repository Structure

```text
FPGA-Build-Challenge-Anjani-Kadambari/
├── README.md
├── Experiment-1-Beginner/
│   ├── RTL/
│   ├── Testbench/
│   ├── Simulation/
│   ├── Images/
│   ├── Documentation/
│   └── Video_Link.txt
├── Experiment-2-Beginner/
├── Experiment-3-Intermediate/
├── Experiment-4-Intermediate/
├── Experiment-5-Advanced/
└── Final_Report/
    └── LeadHerBoard_Final_Report.pdf
```

Each experiment directory is intended to organize the corresponding RTL source files, testbenches, simulation evidence, design images, documentation, and demonstration link.

## Tools & Technologies

- **HDL:** Verilog HDL, SystemVerilog
- **FPGA Design:** Intel Quartus Prime
- **Design & Analysis:** RTL design, module hierarchy, synthesis, and implementation
- **Hardware Platform:** Terasic DE10-Nano Development Board

## Project Goals

Across the five experiments, the portfolio explores key digital-design concepts:

- Reliable communication interfaces
- Packet routing and arbitration
- Configurable arithmetic hardware
- Neuromorphic computing
- Hardware fault diagnosis and localization

Together, these projects provide exposure to modular RTL development and FPGA-oriented system design across multiple application areas.

---

*Developed for the V-SPACE FPGA BuildX Challenge 2026.*
