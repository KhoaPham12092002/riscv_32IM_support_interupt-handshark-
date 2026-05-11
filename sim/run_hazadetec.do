# =============================================================================
# RISC-V CORE HAZARD STRESS TEST RUN SCRIPT (GUI + Waveform)
# Covers: Load-Use Stall (5.6) + Control Hazard & Flush (5.7)
# =============================================================================

# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile — packages first, then sub-modules, then core, then wrapper, then TB
vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../package/riscv_instr.sv

vlog -vopt -sv ../src/alu/sub_module.sv
vlog -vopt -sv ../src/alu/alu.sv
vlog -vopt -sv ../src/alu/riscv_m_unit.sv

vlog -vopt -sv ../src/decoder/branch_cmp.sv
vlog -vopt -sv ../src/decoder/decoder.sv

vlog -vopt -sv ../src/core/pc_gen.sv
vlog -vopt -sv ../src/core/register.sv
vlog -vopt -sv ../src/core/pipeline_reg.sv
vlog -vopt -sv ../src/core/lsu.sv
vlog -vopt -sv ../src/core/forwarding_unit.sv
vlog -vopt -sv ../src/core/hazard_unit.sv
vlog -vopt -sv ../src/core/csr.sv
vlog -vopt -sv ../src/core/riscv_control.sv
vlog -vopt -sv ../src/core/riscv_datapath.sv
vlog -vopt -sv ../src/core/riscv_core.sv

vlog -vopt -sv ../verify/UVM/core/tb_core_hazadetec.sv

# 3. Load Simulation
vsim -voptargs="+acc" +UVM_TESTNAME=riscv_hazard_test +UVM_VERBOSITY=UVM_LOW work.tb_top

# 4. Waveform Setup
radix -hex

add wave -divider "=== SYSTEM ==="
add wave -noupdate -label CLK   /tb_top/clk
add wave -noupdate -label RST   /tb_top/vif/rst_i

add wave -divider "=== HAZARD CONTROL SIGNALS ==="
add wave -noupdate -label force_stall -color red    /tb_top/dut/u_control/u_hazard/ctrl_force_stall_id_o
add wave -noupdate -label flush_if_id -color orange /tb_top/dut/u_control/u_hazard/ctrl_flush_if_id_o
add wave -noupdate -label flush_id_ex -color orange /tb_top/dut/u_control/u_hazard/ctrl_flush_id_ex_o
add wave -noupdate -label is_load_use               /tb_top/dut/u_control/u_hazard/is_load_use
add wave -noupdate -label jump_trap                 /tb_top/dut/u_control/jump_trap_comb

add wave -divider "=== FORWARDING ==="
add wave -noupdate -label fwd_rs1 -color yellow /tb_top/dut/u_control/u_forwarding/ctrl_fwd_rs1_sel_o
add wave -noupdate -label fwd_rs2 -color yellow /tb_top/dut/u_control/u_forwarding/ctrl_fwd_rs2_sel_o
add wave -noupdate -label ex_rs1                /tb_top/dut/u_control/u_forwarding/hz_ex_rs1_addr_i
add wave -noupdate -label ex_rs2                /tb_top/dut/u_control/u_forwarding/hz_ex_rs2_addr_i
add wave -noupdate -label mem_rd                /tb_top/dut/u_control/u_forwarding/hz_mem_rd_addr_i
add wave -noupdate -label wb_rd                 /tb_top/dut/u_control/u_forwarding/hz_wb_rd_addr_i

add wave -divider "=== IMEM HANDSHAKE ==="
add wave -noupdate -label imem_valid_o /tb_top/vif/imem_valid_o
add wave -noupdate -label imem_ready_i /tb_top/vif/imem_ready_i
add wave -noupdate -label imem_addr    /tb_top/vif/imem_addr_o
add wave -noupdate -label imem_instr   /tb_top/vif/imem_instr_i
add wave -noupdate -label imem_valid_i /tb_top/vif/imem_valid_i

add wave -divider "=== PC GEN ==="
add wave -noupdate -label pc_current /tb_top/dut/u_datapath/u_pc_gen/pc_q
add wave -noupdate -label pc_next    /tb_top/dut/u_datapath/u_pc_gen/pc_next

add wave -divider "=== DMEM HANDSHAKE ==="
add wave -noupdate -label dmem_valid_o /tb_top/vif/dmem_valid_o
add wave -noupdate -label dmem_we      /tb_top/vif/dmem_we_o
add wave -noupdate -label dmem_addr    /tb_top/vif/dmem_addr_o
add wave -noupdate -label dmem_wdata   /tb_top/vif/dmem_wdata_o
add wave -noupdate -label dmem_rdata   /tb_top/vif/dmem_rdata_i

add wave -divider "=== REGISTER FILE (x1-x10, x31) ==="
add wave -noupdate -label x1  /tb_top/dut/u_datapath/u_register_file/rf[1]
add wave -noupdate -label x2  /tb_top/dut/u_datapath/u_register_file/rf[2]
add wave -noupdate -label x3  /tb_top/dut/u_datapath/u_register_file/rf[3]
add wave -noupdate -label x4  /tb_top/dut/u_datapath/u_register_file/rf[4]
add wave -noupdate -label x5  /tb_top/dut/u_datapath/u_register_file/rf[5]
add wave -noupdate -label x31 /tb_top/dut/u_datapath/u_register_file/rf[31]

# 5. Run
run -all

# 6. Zoom fit
wave zoom full
