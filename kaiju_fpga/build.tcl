# Kaiju Rampage : build the bitstream without the GUI (non-project mode).
#   full game : C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source build.tcl
#   demo      : C:\Xilinx\Vivado\2024.2\bin\vivado.bat -mode batch -source build.tcl -tclargs demo
# Output: bit/kaiju_top.bit (full) or bit/kaiju_demo.bit (Progress Presentation), reports in bit/
#         plus bit/<name>_flash.bit + .mcs/.prm : image for the board's QSPI flash (boots by itself, JP1 = QSPI)
#         demo builds are also copied into demo_ready/ (double-click loaders, see demo_ready/README_DEMO.md)
set root [file dirname [file normalize [info script]]]
set out  $root/bit
file mkdir $out
cd $out                                     ;# Vivado's temporary files go here, not into mem/
set demo [expr {[llength $argv] > 0 && [lindex $argv 0] eq "demo"}]
set name [expr {$demo ? "kaiju_demo" : "kaiju_top"}]
read_verilog [glob $root/rtl/*.v]
read_mem     [glob $root/mem/*.mem]
read_xdc $root/constrs/kaiju.xdc
synth_design -top kaiju_top -part xc7a100tcsg324-1 -generic DEMO=$demo
opt_design
place_design
route_design
report_utilization    -file $out/utilization_$name.txt
report_timing_summary -file $out/timing_$name.txt
write_bitstream -force $out/$name.bit

# Flash version: same design, only the start-up settings differ (compressed, 4-bit SPI at 33 MHz = boots in < 1 s).
# Nexys A7-100T flash = 128 Mbit (16 MB) Spansion S25FL128S.
set_property CONFIG_VOLTAGE 3.3                      [current_design]
set_property CFGBVS VCCO                             [current_design]
set_property CONFIG_MODE SPIx4                       [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4         [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33          [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE         [current_design]
write_bitstream -force $out/${name}_flash.bit
write_cfgmem -force -format mcs -size 16 -interface SPIx4 \
    -loadbit "up 0x00000000 $out/${name}_flash.bit" -file $out/${name}_flash.mcs
if {$demo} {                                ;# keep the double-click folder up to date
    foreach f [list $name.bit ${name}_flash.mcs ${name}_flash.prm] { file copy -force $out/$f $root/demo_ready/$f }
}
puts "DONE: $out/$name.bit and $out/${name}_flash.mcs"
