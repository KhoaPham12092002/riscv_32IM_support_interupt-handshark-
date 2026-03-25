# =============================================================================
# RUN SCRIPT: run_imem.do (Executed from /sim/ directory)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. SETUP PATHS (Relative to /sim/)
# -----------------------------------------------------------------------------
set PKG_DIR   "../package"
set SRC_DIR   "../src/memory" ;# Work note: Cậu nhớ check lại thư mục chứa imem.sv nhé
set VERIF_DIR "../verify/MCU"
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

puts "\[SCRIPT\] Root Paths Configured. Using UVM at: $UVM_HOME"

# -----------------------------------------------------------------------------
# 2. CLEANUP WORKSPACE
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Cleaning up old simulation files..."

if {[file exists work]}       { file delete -force work }
if {[file exists uvm]}        { file delete -force uvm }
if {[file exists transcript]} { file delete -force transcript }
if {[file exists vsim.wlf]}   { file delete -force vsim.wlf }

vlib work
vmap work work
vlib uvm
vmap uvm uvm

# -----------------------------------------------------------------------------
# 3. COPY HEX FILE (For Instruction Memory Initialization)
# -----------------------------------------------------------------------------
if {[file exists "$SRC_DIR/new_code.hex"]} {
    file copy -force "$SRC_DIR/new_code.hex" .
    puts "\[SCRIPT\] Copied fresh new_code.hex to /sim/"
} else {
    puts "\[WARNING\] new_code.hex NOT FOUND! Memory might be uninitialized (X-state)."
}

# -----------------------------------------------------------------------------
# 4. COMPILE UVM BASE LIBRARY
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Compiling UVM Base Library (UVM_NO_DPI)..."
vlog -work uvm \
    +incdir+$UVM_HOME/src \
    +define+UVM_NO_DPI \
    +acc \
    $UVM_HOME/src/uvm_pkg.sv \
    -timescale "1ns/1ps" \
    -suppress 2181

# -----------------------------------------------------------------------------
# 5. COMPILE USER DESIGN & TESTBENCH
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Compiling Project Files (Strict Compile Order)..."

vlog -sv -timescale "1ns/1ps" \
    -L uvm \
    +define+UVM_NO_DPI \
    +acc \
    +incdir+$UVM_HOME/src \
    +incdir+$PKG_DIR \
    +incdir+$VERIF_DIR \
    +incdir+$SRC_DIR \
    \
    $PKG_DIR/riscv_32im_pkg.sv \
    $VERIF_DIR/imem_pkg.sv \
    $SRC_DIR/imem.sv \
    $VERIF_DIR/tb_top.sv

# Ghi chú của Work: 
# 1. riscv_32im_pkg.sv: Phải dịch đầu tiên để lấy định nghĩa opcode, parameter chung.
# 2. imem_pkg.sv: Dịch kế tiếp để lấy định nghĩa UVM components (Sequence, Driver, v.v.).
# 3. imem.sv: RTL core.
# 4. tb_top.sv: Nối dây cấp cao nhất, instantiate interface và DUT.

# -----------------------------------------------------------------------------
# 6. ELABORATION & SIMULATION
# -----------------------------------------------------------------------------
puts "\[SCRIPT\] Starting UVM Simulation Phase..."
# Gọi UVM_TESTNAME từ command line để truyền test vào imem_pkg
vsim -voptargs="+acc" -onfinish stop -L uvm +UVM_TESTNAME=imem_basic_test work.tb_top

# -----------------------------------------------------------------------------
# 7. ADD WAVEFORMS
# -----------------------------------------------------------------------------
if {[batch_mode] == 0} {
    catch {delete wave *}
    
    add wave -noupdate -divider {HANDSHAKE INTERFACE}
    add wave -noupdate -radix binary /tb_top/vif/clk_i
    add wave -noupdate -radix binary /tb_top/vif/rst_i
    add wave -noupdate -color Gold -radix binary /tb_top/vif/req_i
    
    add wave -noupdate -divider {MEMORY BUS}
    add wave -noupdate -color Cyan -radix hex /tb_top/vif/addr_i
    add wave -noupdate -color Magenta -radix hex /tb_top/vif/instr_o
    
    add wave -noupdate -divider {RTL INTERNAL}
    add wave -noupdate -radix hex /tb_top/dut/word_addr
    # Monitor the first 4 words to check initialization
    add wave -noupdate -radix hex {/tb_top/dut/mem_array[0]}
    add wave -noupdate -radix hex {/tb_top/dut/mem_array[1]}
    
    wave zoom full
}

# Chạy simulation cho đến khi UVM phase kết thúc
run -all