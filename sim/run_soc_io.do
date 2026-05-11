vdel -lib work -all
vlib work
vmap work work

# Compile Packages
vlog -sv ../package/riscv_32im_pkg.sv
vlog -sv ../package/riscv_instr.sv

# Compile RTL
vlog -sv ../src/alu/*.sv
vlog -sv ../src/memory/*.sv
vlog -sv ../src/decoder/*.sv
vlog -sv ../src/core/*.sv
vlog -sv ../src/interrupt/*.sv
vlog -sv ../src/*.sv

# Compile Testbench
vlog -sv ../verify/tb_soc_io.sv

# Load Simulation
vsim -voptargs=+acc work.tb_soc_io

# Add Waveforms
add wave -position insertpoint sim:/tb_soc_io/clk
add wave -position insertpoint sim:/tb_soc_io/rst
add wave -position insertpoint -radix bin sim:/tb_soc_io/sw_i
add wave -position insertpoint -radix unsigned sim:/tb_soc_io/led_o
add wave -position insertpoint sim:/tb_soc_io/uart_tx_o
add wave -position insertpoint -radix hex sim:/tb_soc_io/lcd_data_o
add wave -position insertpoint sim:/tb_soc_io/lcd_en_o

# Run Simulation
run -all
