# Kaiju Rampage FULL GAME : write bit/kaiju_top_flash.mcs into the board's QSPI flash, then load bit/kaiju_top.bit over JTAG.
# After this the board starts the DEMO by itself at power-on when jumper JP1 is on QSPI.
# Run by 2_FLASH_DEMO_QSPI.bat, or: vivado -mode batch -source program_flash.tcl [-tclargs <flash part>]
# Flash part: Nexys A7-100T = Spansion S25FL128S -> s25fl128sxxxxxx0-spi-x1_x2_x4 (default)
set here [file dirname [file normalize [info script]]]
set mcs  $here/bit/kaiju_top_flash.mcs
set prm  $here/bit/kaiju_top_flash.prm
set part [expr {[llength $argv] > 0 ? [lindex $argv 0] : "s25fl128sxxxxxx0-spi-x1_x2_x4"}]
foreach f [list $mcs $prm] { if {![file exists $f]} { error "missing $f" } }
open_hw_manager
connect_hw_server -allow_non_jtag
if {[llength [get_hw_targets]] == 0} { error "NO BOARD: plug in the USB cable (PROG/UART port) and switch the Nexys A7 on" }
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
if {$dev eq ""} { error "NO xc7a100t: this is not a Nexys A7-100T" }
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev
set mempart [lindex [get_cfgmem_parts $part] 0]
if {$mempart eq ""} { error "unknown flash part $part" }
create_hw_cfgmem -hw_device $dev $mempart
set mem [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.ADDRESS_RANGE          use_file   $mem
set_property PROGRAM.FILES                  [list $mcs] $mem
set_property PROGRAM.PRM_FILE               $prm       $mem
set_property PROGRAM.UNUSED_PIN_TERMINATION pull-none  $mem
set_property PROGRAM.BLANK_CHECK            0          $mem
set_property PROGRAM.ERASE                  1          $mem
set_property PROGRAM.CFG_PROGRAM            1          $mem
set_property PROGRAM.VERIFY                 1          $mem
set_property PROGRAM.CHECKSUM               0          $mem
# 1) load Vivado's flash-writer core into the FPGA, 2) erase + write + verify the flash
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev
program_hw_cfgmem -hw_cfgmem $mem
puts "FLASH WRITTEN AND VERIFIED: $part"
# 3) restart the FPGA: it now loads the FULL GAME from the flash (only if JP1 is on QSPI)
boot_hw_device $dev
after 3000
refresh_hw_device -update_hw_probes false $dev
set done [get_property REGISTER.CONFIG_STATUS.BIT14_DONE_PIN $dev]
if {$done} { puts "BOOTED FROM FLASH: the FULL GAME is running" } else {
    puts "NOT BOOTED FROM FLASH (JP1 not on QSPI?) -> loading kaiju_top.bit over JTAG instead"
    set_property PROGRAM.FILE $here/bit/kaiju_top.bit $dev
    program_hw_devices $dev
    puts "PROGRAMMED OVER JTAG: the FULL GAME is running (move JP1 to QSPI to boot from flash at power-on)"
}
close_hw_target
disconnect_hw_server
close_hw_manager
