# =============================================================================
# run_lsu_thesis.do  —  Thesis Section 5.2.4 → Hình 5.4
# Usage:  cd ~/workspace/project2_axi/sim && vsim -do ../verify4thesis/logs/scripts/run_lsu_thesis.do
# Optional plusargs:
#   +UVM_VERBOSITY=UVM_HIGH      verbose internal log
#   +ntb_random_seed=<N>         override seed (regression script supplies this)
# =============================================================================
set SRC_DIR    "/home/key/workspace/project2_axi/src"
set PKG_DIR    "/home/key/workspace/project2_axi/package"
set V4T_DIR    "/home/key/workspace/project2_axi/verify4thesis"
set COMMON_DIR "${V4T_DIR}/logs/common"
set TB_DIR     "${V4T_DIR}/logs"
set OUT_DIR    "${V4T_DIR}/logs/output"
set UVM_HOME   "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

set TB_TOP    "tb_top"
set TEST_NAME "lsu_test"

if {![file exists $OUT_DIR]} { file mkdir $OUT_DIR }

puts "\[run_lsu_thesis\] Cleaning…"
if {[file exists work]}       { file delete -force work }
if {[file exists uvm]}        { file delete -force uvm }
if {[file exists vsim.wlf]}   { file delete -force vsim.wlf }
if {[file exists cov_lsu.ucdb]} { file delete -force cov_lsu.ucdb }

vlib work; vmap work work
vlib uvm;  vmap uvm uvm

# Packages first
vlog -vopt -sv -timescale "1ns/1ps" $PKG_DIR/riscv_32im_pkg.sv

# UVM
vlog -work uvm +incdir+$UVM_HOME/src +define+UVM_NO_DPI +acc \
     $UVM_HOME/src/uvm_pkg.sv -timescale "1ns/1ps" -suppress 2181

# DUT + thesis tb
vlog -sv -timescale "1ns/1ps" -L uvm +define+UVM_NO_DPI +acc -coveropt 3 +cover=bcefsx \
     +incdir+$UVM_HOME/src \
     +incdir+$SRC_DIR/core \
     +incdir+$V4T_DIR/logs \
     $SRC_DIR/core/lsu.sv \
     $TB_DIR/tb_lsu_thesis.sv

# Simulate (seed forwarded by regression via -sv_seed env or +ntb_random_seed)
vsim -voptargs="+acc" -coverage -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     -assertdebug \
     work.$TB_TOP

# Wave
do /home/key/workspace/project2_axi/verify4thesis/tb/lsu/wave_lsu_thesis.do

run -all

# Save coverage db (regression merges these)
coverage save -onexit ${OUT_DIR}/cov_lsu.ucdb

