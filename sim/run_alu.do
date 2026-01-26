# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile 
# Package phải compile đầu tiên
vlog -vopt -sv ../package/alu_types_pkg.sv

# Các module con
vlog -vopt -sv ../src/alu/sub_module.sv

# Module chính và Testbench
vlog -vopt -sv ../src/alu/alu.sv
vlog -vopt -sv ../verify/tb_alu.sv

# 3. Load Simulation (Console mode)
vsim -c -voptargs="+acc" work.tb_alu

# 4. Run & Quit
run -all
quit -f
