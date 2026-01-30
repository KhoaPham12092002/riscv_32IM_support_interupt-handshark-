# =============================================================================
# UNIVERSAL RISC-V RUN SCRIPT
# =============================================================================

# 1. SETUP PATHS
set SRC_DIR   "../src"
set PKG_DIR   "../package"
set VERIF_DIR "../verify/UVM"
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

# 2. TEST CONFIG
set TB_TOP    "tb_top"
set TEST_NAME "riscv_core_basic_test" 

puts "\[SCRIPT\] Setup: UVM at $UVM_HOME"

# 3. CLEANUP
puts "\[SCRIPT\] Cleaning workspace..."
if {[file exists work]}       { file delete -force work }
if {[file exists uvm]}        { file delete -force uvm }
if {[file exists vsim.wlf]}   { file delete -force vsim.wlf }

vlib work; vmap work work
vlib uvm;  vmap uvm uvm

# 4. COMPILE UVM LIBRARY
puts "\[SCRIPT\] Compiling UVM..."
vlog -work uvm +incdir+$UVM_HOME/src +define+UVM_NO_DPI +acc \
     $UVM_HOME/src/uvm_pkg.sv -timescale "1ns/1ps" -suppress 2181

# 5. COMPILE USER CODE
puts "\[SCRIPT\] Compiling Design & Verify..."
vlog -sv -timescale "1ns/1ps" -L uvm +define+UVM_NO_DPI +acc \
     +incdir+$UVM_HOME/src \
     +incdir+$SRC_DIR/includes \
     +incdir+$PKG_DIR \
     $PKG_DIR/riscv_32im_pkg.sv \
     $SRC_DIR/decoder/riscv_instr.sv \
     $SRC_DIR/core/pipeline_reg.sv \
     $SRC_DIR/alu/sub_module.sv\
     $SRC_DIR/alu/alu.sv \
     $SRC_DIR/alu/riscv_m_unit.sv \
     $SRC_DIR/core/pc_gen.sv \
     $SRC_DIR/memory/register.sv \
     $SRC_DIR/decoder/decoder.sv \
     $SRC_DIR/core/lsu.sv \
     $SRC_DIR/core/riscv_core.sv \
     $VERIF_DIR/core/tb_core_riscv.sv

# 6. SIMULATE
puts "\[SCRIPT\] Simulating..."
vsim -voptargs="+acc" -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     work.$TB_TOP

# 7. WAVEFORM & RUN
# Tắt log rác numeric_std
suppress 8684,12110

# Add Wave signals quan trọng để Debug
radix -hex
add wave -noupdate -divider {TESTBENCH}
add wave -noupdate -format Logic /tb_top/clk
add wave -noupdate -format Logic /tb_top/vif/rst_i
add wave -noupdate -divider {INTERFACE}
add wave -noupdate -group {IMEM Handshake} /tb_top/vif/imem_*
add wave -noupdate -group {DMEM Handshake} /tb_top/vif/dmem_*
add wave -noupdate -divider {CORE INTERNAL}
add wave -noupdate -group {PC Path} /tb_top/dut/u_pc_gen/*
add wave -noupdate -group {Pipeline Regs} /tb_top/dut/u_if_id_reg/data_o /tb_top/dut/u_id_ex_reg/data_o
add wave -noupdate -group {Register File} /tb_top/dut/u_reg_file/rf

# Run simulation
run -all
