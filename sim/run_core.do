# =============================================================================
# RISC-V CORE FULL INTEGRATION RUN SCRIPT (GUI + Waveform)
# =============================================================================

# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile — packages first, then sub-modules, then core, then TB
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

vlog -vopt -sv ../verify/UVM/core/tb_core_riscv.sv

# 3. Load Simulation
vsim -voptargs="+acc=all" +UVM_TESTNAME=riscv_hazard_test +UVM_VERBOSITY=UVM_LOW work.tb_top

# 4. Waveform Setup (GUI mode only; catch prevents wave errors from aborting run)
if {![batch_mode]} {
    catch {
        radix -hex
        add wave -divider "=== SYSTEM ==="
        add wave -noupdate -label CLK /tb_top/clk
        add wave -noupdate -label RST /tb_top/vif/rst_i
        add wave -divider "=== IMEM HANDSHAKE ==="
        add wave -noupdate -label imem_valid_o /tb_top/vif/imem_valid_o
        add wave -noupdate -label imem_ready_i /tb_top/vif/imem_ready_i
        add wave -noupdate -label imem_addr    /tb_top/vif/imem_addr_o
        add wave -noupdate -label imem_instr   /tb_top/vif/imem_instr_i
        add wave -noupdate -label imem_valid_i /tb_top/vif/imem_valid_i
        add wave -divider "=== PC GEN ==="
        add wave -noupdate -label pc_current /tb_top/dut/u_datapath/u_pc_gen/pc_q
        add wave -noupdate -label pc_next    /tb_top/dut/u_datapath/u_pc_gen/pc_next
        add wave -divider "=== HAZARD CONTROL ==="
        add wave -noupdate -label force_stall -color red    /tb_top/dut/ctrl_force_stall_id
        add wave -noupdate -label flush_if_id -color orange /tb_top/dut/ctrl_flush_if_id
        add wave -noupdate -label flush_id_ex -color orange /tb_top/dut/ctrl_flush_id_ex
        add wave -divider "=== PIPELINE REGISTERS ==="
        add wave -noupdate -label if_id_out /tb_top/dut/u_datapath/u_reg_if_id/data_o
        add wave -noupdate -label id_ex_out /tb_top/dut/u_datapath/u_reg_id_ex/data_o
        add wave -divider "=== DMEM HANDSHAKE ==="
        add wave -noupdate -label dmem_valid_o /tb_top/vif/dmem_valid_o
        add wave -noupdate -label dmem_we      /tb_top/vif/dmem_we_o
        add wave -noupdate -label dmem_addr    /tb_top/vif/dmem_addr_o
        add wave -noupdate -label dmem_wdata   /tb_top/vif/dmem_wdata_o
        add wave -noupdate -label dmem_rdata   /tb_top/vif/dmem_rdata_i
        add wave -divider "=== REGISTER FILE ==="
        add wave -noupdate -label rf /tb_top/dut/u_datapath/u_register_file/rf
    }
}

# 5. Run
run -all

# 6. Zoom fit
if {![batch_mode]} { wave zoom full }
