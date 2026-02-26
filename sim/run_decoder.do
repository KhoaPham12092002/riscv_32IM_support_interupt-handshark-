# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile 
# Package phải compile đầu tiên
vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../package/riscv_instr.sv

# Module chính và Testbench
vlog -vopt -sv ../src/decoder/decoder.sv
vlog -vopt -sv ../verify/UVM/decoder/tb_decoder.sv

# 3. Load Simulation (Console mode)
vsim -c -voptargs="+acc" work.tb_top

# 4. Run & Quit
run -all
quit -f
