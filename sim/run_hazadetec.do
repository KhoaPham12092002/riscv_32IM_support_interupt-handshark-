# =============================================================================
# UNIVERSAL RISC-V RUN SCRIPT (HAZARD STRESS TEST)
# =============================================================================

# 1. SETUP PATHS
set SRC_DIR   "../src"
set PKG_DIR   "../package"
set VERIF_DIR "../verify" 
set UVM_HOME  "/home/key/tool/modelsim_ase/verilog_src/uvm-1.2"

# 2. TEST CONFIG
set TB_TOP    "tb_top"
# Tên class test trong file tb_uvm_hazard.sv
set TEST_NAME "riscv_hazard_test" 

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
     $PKG_DIR/riscv_instr.sv \
     $SRC_DIR/core/pipeline_reg.sv \
     $SRC_DIR/alu/sub_module.sv\
     $SRC_DIR/alu/alu.sv \
     $SRC_DIR/alu/riscv_m_unit.sv \
     $SRC_DIR/core/pc_gen.sv \
     $SRC_DIR/memory/register.sv \
     $SRC_DIR/decoder/decoder.sv \
     $SRC_DIR/core/lsu.sv \
     $SRC_DIR/core/forwarding_unit.sv \
     $SRC_DIR/core/hazard_detection_unit.sv \
     $SRC_DIR/core/riscv_core.sv \
     $VERIF_DIR/UVM/core/tb_core_hazadetec.sv 

# Lưu ý thứ tự: Hazard Unit & Forwarding Unit phải nằm TRƯỚC riscv_core.sv

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

# =============================================================================
# GROUP 1: TESTBENCH & HAZARD CONTROL (QUAN TRỌNG NHẤT)
# =============================================================================
add wave -noupdate -divider {GLOBAL STATUS}
add wave -noupdate -label "Clock"           /tb_top/clk
add wave -noupdate -label "Reset"           /tb_top/vif/rst_i

add wave -noupdate -divider {HAZARD & FORWARDING}
add wave -noupdate -group "Hazard Unit" \
    -color "Red"    -label "PC Stall"       /tb_top/dut/u_hazard_unit/pc_stall_o \
    -color "Red"    -label "IF/ID Stall"    /tb_top/dut/u_hazard_unit/if_id_stall_o \
    -color "Orange" -label "ID/EX Flush"    /tb_top/dut/u_hazard_unit/id_ex_flush_o \
    -label "Load Use Check"                 /tb_top/dut/u_hazard_unit/id_ex_wb_sel \
    -label "Rs1 Check"                      /tb_top/dut/u_hazard_unit/if_id_rs1 \
    -label "Rs2 Check"                      /tb_top/dut/u_hazard_unit/if_id_rs2

add wave -noupdate -group "Forwarding Unit" \
    -color "Magenta" -label "Fwd A (00=Reg, 10=MEM, 01=WB)" /tb_top/dut/u_fwd_unit/forward_a_o \
    -color "Magenta" -label "Fwd B (00=Reg, 10=MEM, 01=WB)" /tb_top/dut/u_fwd_unit/forward_b_o \
    -label "EX Rs1" /tb_top/dut/u_fwd_unit/rs1_addr_ex \
    -label "EX Rs2" /tb_top/dut/u_fwd_unit/rs2_addr_ex \
    -label "MEM Rd" /tb_top/dut/u_fwd_unit/rd_addr_mem \
    -label "WB Rd"  /tb_top/dut/u_fwd_unit/rd_addr_wb

# =============================================================================
# GROUP 2: PIPELINE FLOW (THEO DÕI LỆNH TRÔI)
# =============================================================================
add wave -noupdate -divider {PIPELINE STAGES}

# Stage 1: FETCH
add wave -noupdate -group "1. IF Stage" \
    -label "PC Current"     /tb_top/dut/u_pc_gen/pc_q \
    -label "PC Next"        /tb_top/dut/u_pc_gen/pc_next \
    -label "Instr Raw"      /tb_top/dut/imem_instr_i

# Stage 2: DECODE
add wave -noupdate -group "2. ID Stage" \
    -label "Instr Decoded"  /tb_top/dut/u_decoder/instr_i \
    -label "Rs1 Addr"       /tb_top/dut/u_decoder/rs1_addr_o \
    -label "Rs2 Addr"       /tb_top/dut/u_decoder/rs2_addr_o \
    -label "Rd Addr"        /tb_top/dut/u_decoder/rd_addr_o \
    -label "Imm Val"        /tb_top/dut/u_decoder/imm_o

# Stage 3: EXECUTE (QUAN TRỌNG ĐỂ SOI FORWARDING)
add wave -noupdate -group "3. EX Stage" \
    -label "PC EX"          /tb_top/dut/id_ex_out.pc \
    -color "Cyan" -label "ALU OpA (Final)" /tb_top/dut/u_alu/alu_in.a \
    -color "Cyan" -label "ALU OpB (Final)" /tb_top/dut/u_alu/alu_in.b \
    -label "ALU Result"     /tb_top/dut/u_alu/alu_o \
    -label "Branch Taken"   /tb_top/dut/branch_taken

# Stage 4: MEMORY
add wave -noupdate -group "4. MEM Stage" \
    -label "Mem Addr"       /tb_top/dut/dmem_addr_o \
    -label "Mem WData"      /tb_top/dut/dmem_wdata_o \
    -label "Mem RData"      /tb_top/dut/dmem_rdata_i \
    -label "Mem WE"         /tb_top/dut/dmem_we_o

# Stage 5: WRITEBACK
add wave -noupdate -group "5. WB Stage" \
    -label "WB Valid"       /tb_top/dut/mem_wb_valid_o \
    -color "Green" -label "WB Data" /tb_top/dut/wb_final_data \
    -label "WB Rd Addr"     /tb_top/dut/mem_wb_out.rd_addr \
    -label "WB WE"          /tb_top/dut/mem_wb_out.ctrl.rf_we

# =============================================================================
# GROUP 3: INTERFACES & REG FILE
# =============================================================================
add wave -noupdate -divider {SYSTEM STATE}

add wave -noupdate -group "IMEM Handshake" \
    -label "Req Valid" /tb_top/vif/imem_valid_o \
    -label "Req Ready" /tb_top/vif/imem_ready_i \
    -label "Resp Valid" /tb_top/vif/imem_valid_i

add wave -noupdate -group "DMEM Handshake" \
    -label "Req Valid" /tb_top/vif/dmem_valid_o \
    -label "Req Ready" /tb_top/vif/dmem_ready_i \
    -label "Resp Valid" /tb_top/vif/dmem_valid_i

add wave -noupdate -group "Registers (x1-x10)" \
    -label "x1" /tb_top/dut/u_reg_file/rf[1] \
    -label "x2" /tb_top/dut/u_reg_file/rf[2] \
    -label "x3" /tb_top/dut/u_reg_file/rf[3] \
    -label "x4" /tb_top/dut/u_reg_file/rf[4] \
    -label "x5" /tb_top/dut/u_reg_file/rf[5] \
    -label "x31 (Ref)" /tb_top/dut/u_reg_file/rf[31]

# Configure Wave Window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Run simulation
run -all
zoom full