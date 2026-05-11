# =============================================================================
# run_core_thesis.do  —  Thesis Section 5.4 → Bảng 1
# Usage: cd ~/workspace/project2_axi/sim && vsim -do ../verify4thesis/logs/scripts/run_core_thesis.do
# =============================================================================
set SRC_DIR    "/home/key/workspace/project2_axi/src"
set PKG_DIR    "/home/key/workspace/project2_axi/package"
set V4T_DIR    "/home/key/workspace/project2_axi/verify4thesis"
set TB_DIR     "${V4T_DIR}/logs"
set OUT_DIR    "${V4T_DIR}/logs/output"
set UVM_HOME   "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

set TB_TOP    "tb_top"
set TEST_NAME "core_thesis_test"

if {![file exists $OUT_DIR]} { file mkdir $OUT_DIR }

puts "\[run_core_thesis\] Cleaning…"
if {[file exists work]}      { file delete -force work }
if {[file exists uvm]}       { file delete -force uvm }
if {[file exists vsim.wlf]}  { file delete -force vsim.wlf }
if {[file exists cov_core.ucdb]} { file delete -force cov_core.ucdb }

vlib work; vmap work work
vlib uvm;  vmap uvm uvm

# Packages
vlog -vopt -sv -timescale "1ns/1ps" $PKG_DIR/riscv_32im_pkg.sv
vlog -vopt -sv -timescale "1ns/1ps" $PKG_DIR/riscv_instr.sv

# UVM
vlog -work uvm +incdir+$UVM_HOME/src +define+UVM_NO_DPI +acc \
     $UVM_HOME/src/uvm_pkg.sv -timescale "1ns/1ps" -suppress 2181

# Sub-modules (compile order matches existing run_core.do)
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/alu/sub_module.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/alu/alu.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/alu/riscv_m_unit.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/decoder/branch_cmp.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/decoder/decoder.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/pc_gen.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/register.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/pipeline_reg.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/lsu.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/forwarding_unit.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/hazard_unit.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/csr.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/riscv_control.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/core/riscv_datapath.sv
vlog -vopt -sv -timescale "1ns/1ps" $SRC_DIR/soc_without_mem.sv

# Thesis tb
vlog -sv -timescale "1ns/1ps" -L uvm +define+UVM_NO_DPI +acc -coveropt 3 +cover=bcefsx \
     +incdir+$UVM_HOME/src \
     +incdir+$SRC_DIR/core \
     +incdir+$V4T_DIR/logs \
     $TB_DIR/tb_core_riscv_thesis.sv

vsim -voptargs="+acc=all" -coverage -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     -assertdebug \
     work.$TB_TOP

do ${V4T_DIR}/tb/core/wave_core_thesis.do

run -all

coverage save -onexit ${OUT_DIR}/cov_core.ucdb
quit -f
