vlib work
vlog -sv pc_gen.sv tb_pc_gen.sv
vsim -voptargs=+acc tb_pc_gen
add wave -position insertpoint sim:/tb_pc_gen/*
run -all
