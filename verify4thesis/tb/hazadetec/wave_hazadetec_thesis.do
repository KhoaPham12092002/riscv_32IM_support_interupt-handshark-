# =============================================================================
# wave_hazadetec_thesis.do  —  Wave layout for Hình 5.6 (Section 5.3.2)
# Loaded automatically by run_hazadetec_thesis.do.
# =============================================================================
onerror {resume}
quietly WaveActivateNextPane {} 0

# ---------- Group 1: Clock ----------
add wave -group "Clock" -position end \
    sim:/tb_top/clk

# ---------- Group 2: Inputs ----------
add wave -group "Inputs" -position end -radix unsigned \
    sim:/tb_top/vif/rs1_id \
    sim:/tb_top/vif/rs2_id \
    sim:/tb_top/vif/rd_ex
add wave -group "Inputs" -position end -radix binary \
    sim:/tb_top/vif/we_ex \
    sim:/tb_top/vif/wb_sel_ex \
    sim:/tb_top/vif/jump_trap

# ---------- Group 3: DUT internal ----------
add wave -group "DUT_internal" -position end -radix unsigned \
    sim:/tb_top/dut/hz_id_rs1_addr_i \
    sim:/tb_top/dut/hz_id_rs2_addr_i \
    sim:/tb_top/dut/hz_ex_rd_addr_i
add wave -group "DUT_internal" -position end -radix binary \
    sim:/tb_top/dut/hz_ex_reg_we_i \
    sim:/tb_top/dut/hz_ex_wb_sel_i \
    sim:/tb_top/dut/jump_trap_i \
    sim:/tb_top/dut/is_load_use

# ---------- Group 4: Outputs ----------
add wave -group "Outputs" -position end -radix binary \
    sim:/tb_top/vif/stall_id_o \
    sim:/tb_top/vif/flush_if_id_o \
    sim:/tb_top/vif/flush_id_ex_o

# ---------- Group 5: Checker ----------
add wave -group "Checker" -position end \
    -label "tb_test_id"    -radix unsigned \
    sim:/tb_top/tb_test_id
add wave -group "Checker" -position end \
    -label "tb_check_pass" -radix binary \
    sim:/tb_top/tb_check_pass

configure wave -namecolwidth 230
configure wave -valuecolwidth 110
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -timelineunits ns
update
wave zoom range 0 500
