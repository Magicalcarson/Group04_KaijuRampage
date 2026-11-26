# Kaiju Rampage : program the board (no GUI)
#   full game : C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source program.tcl
#   demo      : C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source program.tcl -tclargs demo
set root [file dirname [file normalize [info script]]]
set name [expr {([llength $argv] > 0 && [lindex $argv 0] eq "demo") ? "kaiju_demo" : "kaiju_top"}]
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $root/bit/$name.bit $dev
program_hw_devices $dev
puts "PROGRAMMED: [get_property NAME $dev] with $name.bit"
close_hw_target
disconnect_hw_server
close_hw_manager
