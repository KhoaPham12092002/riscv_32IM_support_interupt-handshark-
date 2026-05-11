# =============================================================================
# RISC-V FORWARDING UNIT RUN SCRIPT (GUI + Waveform)
# =============================================================================

# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile
vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../package/riscv_instr.sv
vlog -vopt -sv ../src/core/forwarding_unit.sv
vlog -vopt -sv ../verify/UVM/core/tb_fwd.sv

# 3. Load Simulation
vsim -voptargs="+acc" +UVM_TESTNAME=fwd_test +UVM_VERBOSITY=UVM_LOW work.tb_top

# 4. Waveform Setup
radix -hex

add wave -divider "=== INPUTS: EX Stage ==="
add wave -noupdate -label rs1_addr_ex            /tb_top/vif/rs1_addr_ex
add wave -noupdate -label rs2_addr_ex            /tb_top/vif/rs2_addr_ex

add wave -divider "=== INPUTS: MEM Stage ==="
add wave -noupdate -label rd_addr_mem            /tb_top/vif/rd_addr_mem
add wave -noupdate -label rf_we_mem  -color cyan /tb_top/vif/rf_we_mem

add wave -divider "=== INPUTS: WB Stage ==="
add wave -noupdate -label rd_addr_wb             /tb_top/vif/rd_addr_wb
add wave -noupdate -label rf_we_wb   -color cyan /tb_top/vif/rf_we_wb

add wave -divider "=== OUTPUTS (01=FwdMEM  10=FwdWB  00=NoFwd) ==="
add wave -noupdate -label forward_a -color yellow /tb_top/vif/forward_a_o
add wave -noupdate -label forward_b -color yellow /tb_top/vif/forward_b_o

# 5. Run
run -all

# 6. Zoom fit
wave zoom full
