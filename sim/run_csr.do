# =============================================================================
# RISC-V CSR UNIT RUN SCRIPT (GUI + Waveform)
# =============================================================================

# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile
vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../package/riscv_instr.sv
vlog -vopt -sv ../src/core/csr.sv
vlog -vopt -sv ../verify/UVM/core/tb_csr.sv

# 3. Load Simulation
vsim -voptargs="+acc" +UVM_TESTNAME=csr_test +UVM_VERBOSITY=UVM_LOW work.tb_csr_top

# 4. Waveform Setup
radix -hex

add wave -divider "=== SYSTEM ==="
add wave -noupdate -label CLK   /tb_csr_top/clk
add wave -noupdate -label RST   /tb_csr_top/rst_i

add wave -divider "=== CORE ACCESS (CSR R/W) ==="
add wave -noupdate -label req_valid  -color green  /tb_csr_top/vif/req.valid
add wave -noupdate -label req_addr                 /tb_csr_top/vif/req.addr
add wave -noupdate -label req_op                   /tb_csr_top/vif/req.op
add wave -noupdate -label req_wdata                /tb_csr_top/vif/req.wdata
add wave -noupdate -label csr_ready  -color orange /tb_csr_top/vif/ready
add wave -noupdate -label csr_rdata  -color cyan   /tb_csr_top/vif/rdata

add wave -divider "=== TRAP / MRET ==="
add wave -noupdate -label trap_valid -color red    /tb_csr_top/vif/trap_valid
add wave -noupdate -label trap_cause               /tb_csr_top/vif/trap_cause
add wave -noupdate -label trap_pc                  /tb_csr_top/vif/trap_pc
add wave -noupdate -label mret       -color yellow /tb_csr_top/vif/mret

add wave -divider "=== CSR REGISTER STATE ==="
add wave -noupdate -label mstatus_mie              /tb_csr_top/dut/mstatus_mie
add wave -noupdate -label mstatus_mpie             /tb_csr_top/dut/mstatus_mpie
add wave -noupdate -label mtvec                    /tb_csr_top/dut/mtvec
add wave -noupdate -label mepc                     /tb_csr_top/dut/mepc
add wave -noupdate -label mcause                   /tb_csr_top/dut/mcause

add wave -divider "=== PC OUTPUTS ==="
add wave -noupdate -label epc         -color cyan  /tb_csr_top/vif/epc
add wave -noupdate -label trap_vector -color cyan  /tb_csr_top/vif/trap_vector

# 5. Run
run -all

# 6. Zoom fit
wave zoom full
