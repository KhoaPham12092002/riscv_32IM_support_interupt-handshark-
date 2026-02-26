vdel -lib work -all
vlib work
vmap work work

# Compile Packages & Interfaces (nếu có)
vlog -sv ../package/riscv_32im_pkg.sv
vlog -sv ../package/riscv_instr.sv


# Compile Core & SoC
vlog -sv ../src/alu/*.sv
vlog -sv ../src/memory/*.sv
vlog -sv ../src/decoder/*.sv
vlog -sv ../src/core/*.sv
vlog -sv ../src/*.sv

vlog -sv ../verify/tb_soc_simple.sv

# Load Simulation (Lưu ý +acc để debug)
vsim -voptargs=+acc work.tb_soc_simple

# Add Wave
add wave -position insertpoint sim:/tb_soc_simple/u_soc/clk_i
add wave -position insertpoint sim:/tb_soc_simple/u_soc/rst_i
add wave -position insertpoint -radix hex sim:/tb_soc_simple/u_soc/u_core/imem_addr_o
add wave -position insertpoint -radix hex sim:/tb_soc_simple/u_soc/u_core/u_reg_file/rf

# Run
run -all