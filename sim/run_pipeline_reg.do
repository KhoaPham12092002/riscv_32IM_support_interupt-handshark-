# run_pipeline_reg.do
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

vlog -vopt -sv ../package/riscv_32im_pkg.sv
vlog -vopt -sv ../package/riscv_instr.sv
vlog -vopt -sv ../src/core/pipeline_reg.sv
vlog -vopt -sv ../verify/tb_pipeline_reg.sv

vsim -voptargs="+acc" tb_pipeline_reg
run -all
