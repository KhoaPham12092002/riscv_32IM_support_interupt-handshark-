# ==============================================================================
# run_soc_io.do  —  HEX Function Test
# Target   : soc_top_io + programv2.hex
# Run từ   : sim/ directory
# Usage    : do run_soc_io.do
#
# Test: Mode 00 — hiển thị N² trên 6 màn HEX 7-đoạn (N = SW[9:2])
# 20 test cases: N = 0,1,2,3, 4..9, 10,11,15,20,25,31, 32,50,77,99, 100,127,200,255
# ==============================================================================

# ── Clean & create library ───────────────────────────────────────────────────
vdel -lib work -all
vlib work
vmap work work

# ── Compile packages (PHẢI đứng trước RTL) ───────────────────────────────────
vlog -sv ../package/riscv_32im_pkg.sv
vlog -sv ../package/riscv_instr.sv

# ── Compile RTL ──────────────────────────────────────────────────────────────
vlog -sv ../src/alu/sub_module.sv
vlog -sv ../src/alu/alu.sv
vlog -sv ../src/alu/riscv_m_unit.sv
vlog -sv ../src/decoder/branch_cmp.sv
vlog -sv ../src/decoder/decoder.sv
vlog -sv ../src/memory/mem.sv
vlog -sv ../src/memory/imem.sv
vlog -sv ../src/memory/dmem.sv
vlog -sv ../src/core/register.sv
vlog -sv ../src/core/pc_gen.sv
vlog -sv ../src/core/pipeline_reg.sv
vlog -sv ../src/core/forwarding_unit.sv
vlog -sv ../src/core/hazard_unit.sv
vlog -sv ../src/core/lsu.sv
vlog -sv ../src/core/csr.sv
vlog -sv ../src/core/riscv_datapath.sv
vlog -sv ../src/core/riscv_control.sv
vlog -sv ../src/interrupt/interrupt_control.sv
vlog -sv ../src/in_out/uart.sv
vlog -sv ../src/top/soc_top_io.sv

# ── Compile Testbench ─────────────────────────────────────────────────────────
vlog -sv ../verify/tb_soc_io.sv

# ── Load Simulation ───────────────────────────────────────────────────────────
vsim -t 1ps -voptargs=+acc work.tb_soc_io

# ==============================================================================
# WAVEFORM SETUP — HEX Function Test
# ==============================================================================

# ── [1] CLOCK & RESET ─────────────────────────────────────────────────────────
add wave -divider "========== CLOCK & RESET =========="
add wave -noupdate -label "clk"         sim:/tb_soc_io/clk
add wave -noupdate -label "rst"         sim:/tb_soc_io/rst

# ── [2] SWITCH INPUT ──────────────────────────────────────────────────────────
add wave -divider "========== SWITCH INPUT =========="
add wave -noupdate -label "sw_i[9:0]"  -radix binary    sim:/tb_soc_io/sw_i
add wave -noupdate -label "MODE sw[1:0]" -radix unsigned sim:/tb_soc_io/sw_i
add wave -noupdate -label "rf_wdata(WB)" -radix hexadecimal sim:/tb_soc_io/u_soc/u_datapath/rf_wdata

# ── [3] HEX OUTPUT (TB side) ──────────────────────────────────────────────────
add wave -divider "========== HEX OUTPUT (7-seg codes) =========="
add wave -noupdate -label "hex5 (MSD)"  -radix hexadecimal sim:/tb_soc_io/hex5_o
add wave -noupdate -label "hex4"        -radix hexadecimal sim:/tb_soc_io/hex4_o
add wave -noupdate -label "hex3"        -radix hexadecimal sim:/tb_soc_io/hex3_o
add wave -noupdate -label "hex2"        -radix hexadecimal sim:/tb_soc_io/hex2_o
add wave -noupdate -label "hex1"        -radix hexadecimal sim:/tb_soc_io/hex1_o
add wave -noupdate -label "hex0 (LSD)"  -radix hexadecimal sim:/tb_soc_io/hex0_o

# ── [4] HEX REGISTERS (inside soc_top_io) ────────────────────────────────────
add wave -divider "========== HEX REGISTERS (SoC internal) =========="
add wave -noupdate -label "hex_reg[5]"  -radix hexadecimal sim:/tb_soc_io/u_soc/hex_reg[5]
add wave -noupdate -label "hex_reg[4]"  -radix hexadecimal sim:/tb_soc_io/u_soc/hex_reg[4]
add wave -noupdate -label "hex_reg[3]"  -radix hexadecimal sim:/tb_soc_io/u_soc/hex_reg[3]
add wave -noupdate -label "hex_reg[2]"  -radix hexadecimal sim:/tb_soc_io/u_soc/hex_reg[2]
add wave -noupdate -label "hex_reg[1]"  -radix hexadecimal sim:/tb_soc_io/u_soc/hex_reg[1]
add wave -noupdate -label "hex_reg[0]"  -radix hexadecimal sim:/tb_soc_io/u_soc/hex_reg[0]

# ── [5] ADDRESS DECODER (cho HEX peripheral) ─────────────────────────────────
add wave -divider "========== ADDRESS DECODER =========="
add wave -noupdate -label "io_req_valid"  sim:/tb_soc_io/u_soc/io_req_valid
add wave -noupdate -label "io_we"         sim:/tb_soc_io/u_soc/io_we
add wave -noupdate -label "cs_hex"        sim:/tb_soc_io/u_soc/cs_hex
add wave -noupdate -label "cs_sw_led"     sim:/tb_soc_io/u_soc/cs_sw_led
add wave -noupdate -label "dmem_addr"    -radix hexadecimal sim:/tb_soc_io/u_soc/dmem_addr
add wave -noupdate -label "dmem_wdata"   -radix hexadecimal sim:/tb_soc_io/u_soc/dmem_wdata

# ── [6] DMEM BUS (hex_map LOAD/STORE tại 0x2000_0000) ────────────────────────
add wave -divider "========== DMEM BUS (hex_map access) =========="
add wave -noupdate -label "dmem_req_valid"  sim:/tb_soc_io/u_soc/real_dmem_req_valid
add wave -noupdate -label "dmem_req_ready"  sim:/tb_soc_io/u_soc/real_dmem_req_ready
add wave -noupdate -label "dmem_rsp_valid"  sim:/tb_soc_io/u_soc/real_dmem_rsp_valid
add wave -noupdate -label "dmem_we"         sim:/tb_soc_io/u_soc/dmem_we
add wave -noupdate -label "dmem_be"        -radix binary    sim:/tb_soc_io/u_soc/dmem_be
add wave -noupdate -label "dmem_wdata(dm)" -radix hexadecimal sim:/tb_soc_io/u_soc/dmem_wdata
add wave -noupdate -label "dmem_rdata(dm)" -radix hexadecimal sim:/tb_soc_io/u_soc/real_dmem_rdata

# ── [7] LED (mirror SW) ───────────────────────────────────────────────────────
add wave -divider "========== LED (mirror SW) =========="
add wave -noupdate -label "led_o"       -radix binary    sim:/tb_soc_io/led_o
add wave -noupdate -label "led_reg"     -radix binary    sim:/tb_soc_io/u_soc/led_reg

# ── [8] PIPELINE WB (debug: xem lệnh nào đang writeback) ─────────────────────
add wave -divider "========== PIPELINE WB =========="
add wave -noupdate -label "mem_wb_valid"  sim:/tb_soc_io/u_soc/u_datapath/mem_wb_valid
add wave -noupdate -label "rf_we"         sim:/tb_soc_io/u_soc/u_datapath/mem_wb_out.ctrl.rf_we
add wave -noupdate -label "rd_addr"      -radix unsigned  sim:/tb_soc_io/u_soc/u_datapath/mem_wb_out.rd_addr
add wave -noupdate -label "rf_wdata"     -radix hexadecimal sim:/tb_soc_io/u_soc/u_datapath/rf_wdata
add wave -noupdate -label "pc_wb"        -radix hexadecimal sim:/tb_soc_io/u_soc/u_datapath/mem_wb_out.pc_plus4

# ── Wave display settings ─────────────────────────────────────────────────────
configure wave -namecolwidth  230
configure wave -valuecolwidth 100
configure wave -justifyvalue  left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

# Zoom: ước tính 20 test × 30000 cycle × 20ns = 12ms + 500 init cycles ≈ 12ms
# Hiển thị 15ms để dư margin
WaveRestoreZoom {0 ns} {15000000 ns}

# ── Run ───────────────────────────────────────────────────────────────────────
run -all
