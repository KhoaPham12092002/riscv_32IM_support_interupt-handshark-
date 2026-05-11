# =============================================================================
# run_hazadetec_thesis.do  —  Thesis Section 5.3.2 → Hình 5.6
# Usage: cd ~/workspace/project2_axi/sim && vsim -do ../verify4thesis/logs/scripts/run_hazadetec_thesis.do
# =============================================================================
set SRC_DIR    "~/workspace/project2_axi/src"
set PKG_DIR    "~/workspace/project2_axi/package"
set V4T_DIR    "~/workspace/project2_axi/verify4thesis"
set TB_DIR     "${V4T_DIR}/logs"
set OUT_DIR    "${V4T_DIR}/logs/output"
set UVM_HOME   "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

set TB_TOP    "tb_top"
set TEST_NAME "hz_test"

if {![file exists $OUT_DIR]} { file mkdir $OUT_DIR }

puts "\[run_hazadetec_thesis\] Cleaning..."
if {[file exists work]}          { file delete -force work }
if {[file exists uvm]}           { file delete -force uvm }
if {[file exists vsim.wlf]}      { file delete -force vsim.wlf }
if {[file exists cov_hz.ucdb]}   { file delete -force cov_hz.ucdb }

vlib work; vmap work work
vlib uvm;  vmap uvm uvm

# Packages — riscv_32im_pkg required for wb_sel_e
vlog -vopt -sv -timescale "1ns/1ps" $PKG_DIR/riscv_32im_pkg.sv

# UVM
vlog -work uvm +incdir+$UVM_HOME/src +define+UVM_NO_DPI +acc \
     $UVM_HOME/src/uvm_pkg.sv -timescale "1ns/1ps" -suppress 2181

# DUT + thesis tb
vlog -sv -timescale "1ns/1ps" -L uvm +define+UVM_NO_DPI +acc -coveropt 3 +cover=bcefsx \
     +incdir+$UVM_HOME/src \
     +incdir+$V4T_DIR/logs \
     $SRC_DIR/core/hazard_unit.sv \
     $TB_DIR/tb_hazadetec_thesis.sv

# Simulate
vsim -voptargs="+acc" -coverage -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     -assertdebug \
     work.$TB_TOP

# Wave
do ~/workspace/project2_axi/verify4thesis/tb/hazadetec/wave_hazadetec_thesis.do

run -all

coverage save -onexit ${OUT_DIR}/cov_hz.ucdb

