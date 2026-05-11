# 1. Setup Library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# 2. Compile
vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../src/alu/sub_module.sv
vlog -vopt -sv ../src/alu/alu.sv
vlog -vopt -sv ../verify/UVM/alu/tb_alu.sv

# 3. Load Simulation (GUI mode, full visibility)
vsim -voptargs="+acc" work.tb_alu_top

# 4. Setup Waveform Window
add wave -divider "=== CLOCK ==="
add wave -noupdate -format Logic                          /tb_alu_top/clk

add wave -divider "=== ALU INPUT ==="
add wave -noupdate -format Literal -radix unsigned        /tb_alu_top/vif/op
add wave -noupdate -format Literal -radix hexadecimal     /tb_alu_top/vif/a
add wave -noupdate -format Literal -radix hexadecimal     /tb_alu_top/vif/b

add wave -divider "=== ALU OUTPUT ==="
add wave -noupdate -format Literal -radix hexadecimal     /tb_alu_top/vif/result
add wave -noupdate -format Logic                          /tb_alu_top/vif/zero

add wave -divider "=== DUT INTERNAL ==="
add wave -noupdate -format Logic                          /tb_alu_top/dut/is_sub
add wave -noupdate -format Literal -radix hexadecimal     /tb_alu_top/dut/adder_o
add wave -noupdate -format Literal -radix hexadecimal     /tb_alu_top/dut/shift_o
add wave -noupdate -format Literal -radix unsigned        /tb_alu_top/dut/shift_type

# 5. Run
run -all

# 6. Fit waveform vào màn hình
wave zoom full
