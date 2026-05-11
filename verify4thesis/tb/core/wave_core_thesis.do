# =============================================================================
# wave_core_thesis.do  —  Wave layout for full-core stress (Section 5.4)
# Five fixed groups: Clock_Reset / Pipeline / Hazards / Memory / Checker
# =============================================================================
onerror {resume}

# ---------- Group 1: Clock/Reset ----------
add wave -group "Clock_Reset" -position end \
    sim:/tb_top/clk \
    sim:/tb_top/vif/rst_i

# ---------- Group 2: Pipeline (PC + IF/ID/EX) ----------
add wave -group "Pipeline" -position end -radix hex \
    sim:/tb_top/dut/u_datapath/u_pc_gen/pc_q \
    sim:/tb_top/dut/u_datapath/u_pc_gen/pc_next
add wave -group "Pipeline" -position end -radix hex \
    sim:/tb_top/dut/u_datapath/u_reg_if_id/data_o \
    sim:/tb_top/dut/u_datapath/u_reg_id_ex/data_o

# ---------- Group 3: Hazards (control unit signals) ----------
add wave -group "Hazards" -position end -radix binary -color red \
    sim:/tb_top/dut/ctrl_force_stall_id
add wave -group "Hazards" -position end -radix binary -color orange \
    sim:/tb_top/dut/ctrl_flush_if_id \
    sim:/tb_top/dut/ctrl_flush_id_ex
add wave -group "Hazards" -position end -radix binary \
    sim:/tb_top/dut/ctrl_fwd_rs1_sel \
    sim:/tb_top/dut/ctrl_fwd_rs2_sel \
    sim:/tb_top/dut/ctrl_pc_sel

# ---------- Group 4: Memory ----------
add wave -group "Memory_IMEM" -position end -radix hex \
    sim:/tb_top/vif/imem_addr_o \
    sim:/tb_top/vif/imem_instr_i
add wave -group "Memory_IMEM" -position end -radix binary \
    sim:/tb_top/vif/imem_valid_o \
    sim:/tb_top/vif/imem_ready_i \
    sim:/tb_top/vif/imem_valid_i \
    sim:/tb_top/vif/imem_ready_o

add wave -group "Memory_DMEM" -position end -radix hex \
    sim:/tb_top/vif/dmem_addr_o \
    sim:/tb_top/vif/dmem_wdata_o \
    sim:/tb_top/vif/dmem_rdata_i
add wave -group "Memory_DMEM" -position end -radix binary \
    sim:/tb_top/vif/dmem_valid_o \
    sim:/tb_top/vif/dmem_ready_i \
    sim:/tb_top/vif/dmem_we_o

# ---------- Group 5: Checker (wave marker) ----------
add wave -group "Checker" -position end \
    -label "tb_test_id"    -radix unsigned   sim:/tb_top/tb_test_id
add wave -group "Checker" -position end \
    -label "tb_check_pass" -radix binary     sim:/tb_top/tb_check_pass
add wave -group "Checker" -position end -radix unsigned \
    sim:/tb_top/dut/u_datapath/u_register_file/rf
add wave -group "Checker" -position end -radix binary \
    sim:/tb_top/vif/dbg_wb_we
add wave -group "Checker" -position end -radix unsigned \
    sim:/tb_top/vif/dbg_wb_rd

configure wave -namecolwidth 220
configure wave -valuecolwidth 110
configure wave -justifyvalue left
configure wave -timelineunits ns
update
wave zoom full
