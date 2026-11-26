# Kaiju Rampage : create the Vivado project of this folder.
# In Vivado (start page), open the Tcl Console at the bottom and type, with / not \ :
#   cd <path-to-repo>/kaiju_fpga
#   source create_kaiju.tcl
# (no spaces or Thai letters in the path)
set root [file dirname [file normalize [info script]]]

create_project kaiju_fpga $root/vivado -part xc7a100tcsg324-1 -force
catch { set_property board_part digilentinc.com:nexys-a7-100t:part0:1.2 [current_project] }

# design sources + memory files (the .mem files must be in the project for $readmemh)
add_files -norecurse [concat [glob $root/rtl/*.v] [glob $root/mem/*.mem]]
set_property top kaiju_top [get_filesets sources_1]

add_files -fileset constrs_1 -norecurse $root/constrs/kaiju.xdc

# simulation: Run All plays a short game and saves screenshots shot_*.ppm
add_files -fileset sim_1 -norecurse [glob $root/sim/*.v]
set_property top tb_kaiju [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "Project ready: $root/vivado/kaiju_fpga.xpr"
