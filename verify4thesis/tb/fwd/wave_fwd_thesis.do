# =============================================================================
# wave_fwd_thesis.do  —  Wave layout for Hình 5.5 (Section 5.3.1)
# Loaded automatically by run_fwd_thesis.do.
# =============================================================================
onerror {resume}
quietly WaveActivateNextPane {} 0

# ---------- Group 1: Clock/Reset ----------
add wave -group "Clock_Reset" -position end \
    sim:/tb_top/clk

# ---------- Group 2: Inputs ----------
add wave -group "Inputs" -position end -radix unsigned \
    sim:/tb_top/vif/rs1_addr_ex \
    sim:/tb_top/vif/rs2_addr_ex \
    sim:/tb_top/vif/rd_addr_mem \
    sim:/tb_top/vif/rd_addr_wb
add wave -group "Inputs" -position end -radix binary \
    sim:/tb_top/vif/rf_we_mem \
    sim:/tb_top/vif/rf_we_wb

# ---------- Group 3: DUT internal ----------
add wave -group "DUT_internal" -position end -radix unsigned \
    sim:/tb_top/dut/hz_ex_rs1_addr_i \
    sim:/tb_top/dut/hz_ex_rs2_addr_i \
    sim:/tb_top/dut/hz_mem_rd_addr_i \
    sim:/tb_top/dut/hz_wb_rd_addr_i
add wave -group "DUT_internal" -position end -radix binary \
    sim:/tb_top/dut/hz_mem_reg_we_i \
    sim:/tb_top/dut/hz_wb_reg_we_i

# ---------- Group 4: Outputs ----------
add wave -group "Outputs" -position end -radix binary \
    sim:/tb_top/vif/ctrl_fwd_rs1_sel_o \
    sim:/tb_top/vif/ctrl_fwd_rs2_sel_o

# ---------- Group 5: Checker ----------
add wave -group "Checker" -position end \
    -label "tb_test_id"    -radix unsigned \
    sim:/tb_top/tb_test_id
add wave -group "Checker" -position end \
    -label "tb_check_pass" -radix binary \
    sim:/tb_top/tb_check_pass

configure wave -namecolwidth 220
configure wave -valuecolwidth 110
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update
wave zoom range 0 300
