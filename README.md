# Kaiju Rampage: CPE222 Final Project (Group 04)

An FPGA game in Verilog for the Digilent Nexys A7-100T, built with Vivado 2024.2.

| Path | Contents |
|---|---|
| `kaiju_fpga/rtl/` | Verilog source (`kaiju_top.v` is the top module) |
| `kaiju_fpga/constrs/` | Pin constraints (`kaiju.xdc`) |
| `kaiju_fpga/mem/` | Tile, map, palette, sprite and text memory files |
| `kaiju_fpga/sim/` | Testbenches and simulation results |
| `kaiju_fpga/tools/` | Scripts that generate some of the `.mem` files |
| `kaiju_fpga/bit/kaiju_top.bit` | Built bitstream of the full game |
| `kaiju_fpga/*.tcl`, `*.bat` | Project, build and programming scripts |

Build, play and simulation instructions are in [`kaiju_fpga/README.md`](kaiju_fpga/README.md).
