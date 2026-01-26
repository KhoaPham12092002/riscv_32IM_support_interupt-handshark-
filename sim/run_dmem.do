# =============================================================================
# RUN SCRIPT (FIXED SYNTAX & UVM_NO_DPI)
# =============================================================================

# 1. SETUP PATHS
set SRC_DIR   "../src"
set VERIF_DIR "../verify"
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

puts "\[SCRIPT\] Using UVM Source at: $UVM_HOME"

# 2. CLEANUP
puts "\[SCRIPT\] Cleaning up workspace..."

# Lưu ý: Đã thêm dấu cách trước dấu { ở các dòng dưới
if {[file exists work]}        { file delete -force work }
if {[file exists uvm]}         { file delete -force uvm }
if {[file exists vsim.wlf]}    { file delete -force vsim.wlf }

vlib work
vmap work work
vlib uvm
vmap uvm uvm







# -----------------------------------------------------------------------------
# 4. COMPILE UVM LIBRARY
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Compiling UVM Library..."

vlog -work uvm \
    +incdir+$UVM_HOME/src \
    +define+UVM_NO_DPI \
    +acc \
    $UVM_HOME/src/uvm_pkg.sv \
    -timescale "1ns/1ps" \
    -suppress 2181

# -----------------------------------------------------------------------------
# 5. COMPILE USER CODE
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Compiling User Design..."

vlog -sv -timescale "1ns/1ps" \
    -L uvm \
    +define+UVM_NO_DPI \
    +acc \
    +incdir+$UVM_HOME/src \
    +incdir+$SRC_DIR/memory \
    +incdir+$VERIF_DIR/UVM/memory/ \
    \
    $SRC_DIR/memory/memory_pkg.sv \
    $SRC_DIR/memory/dmem.sv \
    $VERIF_DIR/UVM/memory/tb_dmem.sv

# -----------------------------------------------------------------------------
# 6. SIMULATE
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Starting Simulation..."
vsim -voptargs="+acc" -L uvm +UVM_TESTNAME=dmem_basic_test +UVM_VERBOSITY=UVM_HIGH work.tb_top

add wave -position insertpoint sim:/tb_top/dut/*
run -all
