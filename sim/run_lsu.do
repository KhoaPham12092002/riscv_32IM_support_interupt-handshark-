# =============================================================================
# UNIVERSAL RISC-V RUN SCRIPT FOR LSU (LOAD STORE UNIT)
# =============================================================================
# NOTES FOR AI:
# 1. Do NOT change directory variables (matched to user's environment).
# 2. FILL the "COMPILE USER CODE" section with new modules when implementing.
# 3. Always keep +define+UVM_NO_DPI and -voptargs="+acc".
# =============================================================================

# 1. SETUP PATHS (FIXED)
set SRC_DIR   "../src"
set VERIF_DIR "../verify/UVM/core"
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

# 2. TEST CONFIG (UPDATED FOR LSU)
set TB_TOP    "tb_top"
set TEST_NAME "lsu_basic_test"

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

# 5. COMPILE USER CODE (LSU & TESTBENCH)
puts "\[SCRIPT\] Compiling Design & Verify..."
vlog -sv -timescale "1ns/1ps" -L uvm +define+UVM_NO_DPI +acc \
     +incdir+$UVM_HOME/src \
     +incdir+$SRC_DIR/core \
     +incdir+$SRC_DIR/includes \
     \
     $SRC_DIR/core/lsu.sv \
     \
     $VERIF_DIR/tb_lsu.sv

# 6. SIMULATE
puts "\[SCRIPT\] Simulating..."
vsim -voptargs="+acc" -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     work.$TB_TOP

# 7. WAVEFORM & RUN
radix -hex
# Add DUT signals for debugging
# add wave -noupdate -group "LSU Interface" -radix hex sim:/$TB_TOP/dut/*

# Run simulation
run -all
quit
