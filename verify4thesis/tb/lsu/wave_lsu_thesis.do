# =============================================================================
# wave_lsu_thesis.do  —  Wave layout for Hình 5.4 (Section 5.2.4)
# Loaded automatically by run_lsu_thesis.do.
#
# Five fixed groups:  Clock/Reset | Inputs | DUT internal | Outputs | Checker
# Killer test markers:  TEST 09  Misaligned LH @ odd → first big lsu_err pulse
# =============================================================================
onerror {resume}
quietly WaveActivateNextPane {} 0

# ---------- Group 1: Clock/Reset ----------
add wave -group "Clock_Reset" -position end \
    sim:/tb_top/clk \
    sim:/tb_top/vif/rst_i

# ---------- Group 2: Inputs ----------
add wave -group "Inputs" -position end -radix hex \
    sim:/tb_top/vif/addr_i \
    sim:/tb_top/vif/wdata_i
add wave -group "Inputs" -position end -radix binary \
    sim:/tb_top/vif/lsu_we_i \
    sim:/tb_top/vif/funct3_i \
    sim:/tb_top/vif/valid_i \
    sim:/tb_top/vif/ready_i

# ---------- Group 3: DUT internal ----------
add wave -group "DUT_internal" -position end \
    -label "fsm_state" -radix symbolic \
    sim:/tb_top/dut/state
add wave -group "DUT_internal" -position end -radix hex \
    sim:/tb_top/dut/addr_q \
    sim:/tb_top/dut/wdata_q
add wave -group "DUT_internal" -position end -radix binary \
    sim:/tb_top/dut/funct3_q \
    sim:/tb_top/dut/we_q \
    sim:/tb_top/dut/misaligned \
    sim:/tb_top/dut/misaligned_trap_q

# ---------- Group 4: Outputs ----------
add wave -group "Outputs_Core" -position end -radix hex \
    sim:/tb_top/vif/lsu_rdata_o
add wave -group "Outputs_Core" -position end -radix binary \
    sim:/tb_top/vif/lsu_err_o \
    sim:/tb_top/vif/valid_o \
    sim:/tb_top/vif/ready_o

add wave -group "Outputs_DMEM" -position end -radix hex \
    sim:/tb_top/vif/dmem_addr_o \
    sim:/tb_top/vif/dmem_wdata_o \
    sim:/tb_top/vif/dmem_rdata_i
add wave -group "Outputs_DMEM" -position end -radix binary \
    sim:/tb_top/vif/dmem_be_o \
    sim:/tb_top/vif/dmem_we_o \
    sim:/tb_top/vif/dmem_req_valid_o \
    sim:/tb_top/vif/dmem_req_ready_i \
    sim:/tb_top/vif/dmem_rsp_valid_i \
    sim:/tb_top/vif/dmem_rsp_ready_o

# ---------- Group 5: Checker (wave marker) ----------
add wave -group "Checker" -position end \
    -label "tb_test_id"    -radix unsigned \
    sim:/tb_top/tb_test_id
add wave -group "Checker" -position end \
    -label "tb_check_pass" -radix binary \
    sim:/tb_top/tb_check_pass

# Visual config
configure wave -namecolwidth 220
configure wave -valuecolwidth 110
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update

# After "run -all" the calling script will invoke wave zoom range — but provide
# a default zoom centred on the misaligned trap test (TEST 09, ~ around 700 ns
# given 11 cases × ~60 ns each; auto-zoom to fit).
wave zoom full
