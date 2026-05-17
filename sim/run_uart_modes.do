# ==============================================================================
# run_uart_modes.do  —  UART Mode 01 & Mode 10 Verification
# Target   : soc_top_io + programv2.hex
# Run từ   : sim/ directory
# Usage    : do run_uart_modes.do
#
# Test Mode 01: VALUE → TX "HH\r\n" (2 hex ASCII + CR LF)
# Test Mode 10: RX byte → CPU echo → TX
# ==============================================================================

# ── Clean & create library ───────────────────────────────────────────────────
vdel -lib work -all
vlib work
vmap work work

# ── Compile packages ──────────────────────────────────────────────────────────
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
vlog -sv ../verify/tb_uart_modes.sv

# ── Simulate ─────────────────────────────────────────────────────────────────
vsim -t 1ps -voptargs=+acc work.tb_uart_modes

# ── Wave: UART TX/RX pins và UART internal ────────────────────────────────────
add wave -noupdate -divider "CLK/RST"
add wave -noupdate -label "clk"       sim:/tb_uart_modes/clk
add wave -noupdate -label "rst"       sim:/tb_uart_modes/rst

add wave -noupdate -divider "SW/MODE"
add wave -noupdate -label "sw_i"      -radix hexadecimal sim:/tb_uart_modes/sw_i

add wave -noupdate -divider "UART Pins"
add wave -noupdate -label "uart_tx_o" sim:/tb_uart_modes/uart_tx_o
add wave -noupdate -label "uart_rx_i" sim:/tb_uart_modes/uart_rx_i

add wave -noupdate -divider "UART Internal"
add wave -noupdate -label "tx_busy"   sim:/tb_uart_modes/u_soc/u_uart/tx_busy
add wave -noupdate -label "rx_valid"  sim:/tb_uart_modes/u_soc/u_uart/rx_data_valid
add wave -noupdate -label "rx_data"   -radix hexadecimal sim:/tb_uart_modes/u_soc/u_uart/rx_data_reg

configure wave -namecolwidth  200
configure wave -valuecolwidth 100
configure wave -justifyvalue  left
configure wave -signalnamewidth 1

# Mode01: 6 tests × 4 bytes × 4320 cycles + anti-spam 15000 + overhead ~120000 cycles
# Mode10: 5 tests × (4320 send + 4320 echo + 300 overhead) ~46000 cycles × 5 ~230000 cycles
# Total ~350000 cycles × 20ns ≈ 7ms
WaveRestoreZoom {0 ns} {8000000 ns}

# ── Run ───────────────────────────────────────────────────────────────────────
run -all
