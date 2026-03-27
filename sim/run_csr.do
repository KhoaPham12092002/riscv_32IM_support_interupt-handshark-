# =============================================================================
# UNIVERSAL RISC-V RUN SCRIPT (PERFORMANCE & HAZARD STRESS TEST)
# =============================================================================

# 1. SETUP PATHS
set SRC_DIR   "../src"
set PKG_DIR   "../package"
set VERIF_DIR "../verify/UVM/core"  
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

# 2. TEST CONFIG
set TB_TOP    "tb_csr_top"
set TB_FILE   "tb_csr.sv" 
# Tên test trong file tb_csr.sv
set TEST_NAME "csr_test" 

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
     +incdir+. \
     $PKG_DIR/riscv_32im_pkg.sv \
     $PKG_DIR/riscv_instr.sv \
     $SRC_DIR/core/csr.sv \
     $VERIF_DIR/$TB_FILE


# 6. SIMULATE
puts "\[SCRIPT\] Simulating..."
vsim -voptargs="+acc" -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     work.$TB_TOP

# -----------------------------------------------------------------------------
# 7. WAVEFORM CONFIGURATION
# -----------------------------------------------------------------------------

# Xóa wave cũ để tránh trùng lặp
delete wave *
# Tắt log rác
suppress 8684,12110

# Cấu hình hiển thị Hex cho dễ nhìn
radix -hex

# Run simulation
run -all
quit -f