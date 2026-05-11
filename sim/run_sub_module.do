# run_sub_module.do
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -vopt -sv ../src/alu/sub_module.sv
vlog -vopt -sv ../verify/tb_sub_module.sv

vsim -voptargs="+acc" tb_sub_module

run -all
