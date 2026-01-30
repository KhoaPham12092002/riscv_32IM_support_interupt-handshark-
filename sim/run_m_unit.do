# =============================================================================
# RISC-V M-UNIT RUN SCRIPT
# ============================================================================
# 1. SETUP PATHS
set SRC_DIR   "../src"
set VERIF_DIR "../verify"
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

# 2. TEST CONFIG
set TB_TOP    "tb_top"
set TEST_NAME "m_unit_test" 

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

# Lưu ý: Thứ tự compile rất quan trọng!
# 1. Package trước.
# 2. Sub-modules (i_adder) trước.
# 3. Top module (m_unit) sau.
# 4. Testbench cuối cùng.

vlog -sv -timescale "1ns/1ps" -L uvm +define+UVM_NO_DPI +acc \
     +incdir+$UVM_HOME/src \
     +incdir+$SRC_DIR/includes \
     +incdir+$SRC_DIR/alu \
     ../package/riscv_32im_pkg.sv \
     $SRC_DIR/alu/sub_module.sv \
     $SRC_DIR/alu/riscv_m_unit.sv \
     $VERIF_DIR/UVM/alu/tb_m_unit.sv

# 6. SIMULATE
puts "\[SCRIPT\] Simulating..."
vsim -voptargs="+acc" -L uvm -L work \
     +UVM_TESTNAME=$TEST_NAME \
     +UVM_VERBOSITY=UVM_LOW \
     work.$TB_TOP

# 7. WAVEFORM CONFIGURATION
# Sếp đã thêm sẵn các tín hiệu quan trọng để em debug ngay lập tức
radix -hex
add wave -noupdate -divider {System}
add wave -noupdate -label CLK /tb_top/dut/clk
add wave -noupdate -label RST /tb_top/dut/rst

add wave -noupdate -divider {Upstream Handshake}
add wave -noupdate -label Valid_In -color green /tb_top/dut/valid_i
add wave -noupdate -label Ready_Out -color orange /tb_top/dut/ready_o
add wave -noupdate -label Opcode /tb_top/dut/m_in.op
add wave -noupdate -label RS1 /tb_top/dut/m_in.a_i
add wave -noupdate -label RS2 /tb_top/dut/m_in.b_i

add wave -noupdate -divider {Internal FSM}
add wave -noupdate -label State -color yellow /tb_top/dut/state
add wave -noupdate -label Count /tb_top/dut/count
add wave -noupdate -label Reg_Result /tb_top/dut/result_reg

add wave -noupdate -divider {Downstream Handshake}
add wave -noupdate -label Valid_Out -color green /tb_top/dut/valid_o
add wave -noupdate -label Ready_In -color orange /tb_top/dut/ready_i
add wave -noupdate -label Final_Result -color cyan /tb_top/dut/result_o

# Zoom fit để thấy toàn cảnh
run -all
wave zoom full