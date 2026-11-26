# Kaiju Rampage FULL GAME : load bit/kaiju_top.bit into the FPGA over the USB cable (JTAG).
set here [file dirname [file normalize [info script]]]
set bit  $here/bit/kaiju_top.bit
if {![file exists $bit]} { error "missing $bit" }
open_hw_manager
connect_hw_server -allow_non_jtag
if {[llength [get_hw_targets]] == 0} { error "NO BOARD: plug in the USB cable (PROG/UART port) and switch the Nexys A7 on" }
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { error "NO xc7a100t: this is not a Nexys A7-100T" }
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set_property PROGRAM.FILE $bit $dev
program_hw_devices $dev
puts "PROGRAMMED: [get_property NAME $dev] with kaiju_top.bit"
close_hw_target
disconnect_hw_server
close_hw_manager
