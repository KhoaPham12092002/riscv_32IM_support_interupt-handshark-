# =============================================================================
# RISC-V M-UNIT RUN SCRIPT (GUI + Waveform)
# =============================================================================

# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile
vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../src/alu/sub_module.sv
vlog -vopt -sv ../src/alu/riscv_m_unit.sv
vlog -vopt -sv ../verify/UVM/alu/tb_m_unit.sv

# 3. Load Simulation (GUI mode)
vsim -voptargs="+acc" +UVM_TESTNAME=m_unit_test +UVM_VERBOSITY=UVM_LOW work.tb_top

# 4. Waveform Setup
radix -hex

add wave -divider "=== SYSTEM ==="
add wave -noupdate -label CLK              /tb_top/clk
add wave -noupdate -label RST_N            /tb_top/vif/rst_ni

add wave -divider "=== UPSTREAM (Driver → DUT) ==="
add wave -noupdate -label valid_i  -color green  /tb_top/vif/valid_i
add wave -noupdate -label ready_o  -color orange /tb_top/vif/ready_o
add wave -noupdate -label op                     /tb_top/vif/op
add wave -noupdate -label rs1_data               /tb_top/vif/rs1_data
add wave -noupdate -label rs2_data               /tb_top/vif/rs2_data

add wave -divider "=== FSM INTERNAL ==="
add wave -noupdate -label state    -color yellow /tb_top/dut/state
add wave -noupdate -label count              /tb_top/dut/count
add wave -noupdate -label result_reg         /tb_top/dut/result_reg
add wave -noupdate -label divisor_reg        /tb_top/dut/divisor_reg
add wave -noupdate -label div_by_zero        /tb_top/dut/div_by_zero_q
add wave -noupdate -label sign_q             /tb_top/dut/sign_q

add wave -divider "=== DOWNSTREAM (DUT → Consumer) ==="
add wave -noupdate -label valid_o  -color green  /tb_top/vif/valid_o
add wave -noupdate -label ready_i  -color orange /tb_top/vif/ready_i
add wave -noupdate -label result_o -color cyan   /tb_top/vif/result_o

# 5. Run
run -all

# 6. Zoom fit
wave zoom full
