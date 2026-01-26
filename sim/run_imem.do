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
if {[file exists transcript]}  { file delete -force transcript }
if {[file exists vsim.wlf]}    { file delete -force vsim.wlf }

vlib work
vmap work work
vlib uvm
vmap uvm uvm

# 3. COPY HEX FILE
if {[file exists "$SRC_DIR/memory/program.hex"]} {
    file copy -force "$SRC_DIR/memory/program.hex" .
    puts "\[SCRIPT\] Copied fresh program.hex"
}

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
    $VERIF_DIR/UVM/memory//imem_pkg.sv \
    $SRC_DIR/memory/imem.sv \
    $VERIF_DIR/UVM/memory//tb_top.sv

# -----------------------------------------------------------------------------
# 6. SIMULATE
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Starting Simulation..."
vsim -voptargs="+acc" -onfinish stop -L uvm +UVM_TESTNAME=imem_basic_test work.tb_top
# 7. WAVEFORM
if {[batch_mode] == 0} {
    catch {delete wave *}
    
    add wave -noupdate -divider {INTERFACE}
    add wave -noupdate -radix binary /tb_top/vif/clk_i
    add wave -noupdate -radix binary /tb_top/vif/rst_i
    add wave -noupdate -radix binary /tb_top/vif/req_i
    add wave -noupdate -radix hex    /tb_top/vif/addr_i
    add wave -noupdate -radix hex    /tb_top/vif/instr_o

    add wave -noupdate -divider {INTERNAL}
    add wave -noupdate -radix hex /tb_top/dut/word_addr
    add wave -noupdate -radix hex {/tb_top/dut/mem_array[0]}
    
    wave zoom full
}

run -all