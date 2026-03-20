`timescale 1ns/1ps
import riscv_32im_pkg::*;
import riscv_instr::*;

module riscv_core (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Interrupt Inputs ---
    input logic         irq_sw_i,
    input logic         irq_timer_i,
    input logic         irq_ext_i,

    // --- Instruction Memory Interface ---
    output logic [31:0] imem_addr_o,
    output logic        imem_valid_o,
    input  logic        imem_ready_i,
    input  logic [31:0] imem_instr_i,
    input  logic        imem_valid_i,
    output logic        imem_ready_o,

    // --- Data Memory Interface ---
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_be_o,
    output logic        dmem_we_o,
    output logic        dmem_valid_o,
    input  logic        dmem_ready_i,
    input  logic [31:0] dmem_rdata_i,
    input  logic        dmem_valid_i,
    output logic        dmem_ready_o
);

    // =========================================================================
    // INTERNAL SIGNALS DECLARATION
    // =========================================================================
    
    // --- Global Control & Hazard ---
    logic        flush_pipeline;
    logic        pipeline_stall;
    logic        pc_stall, if_id_stall, id_ex_flush; // FIXED: Added missing decl

    // --- IF Stage ---
    if_id_t      if_id_in, if_id_out;
    logic        if_id_valid_o, if_id_ready_i;

    // --- ID Stage ---
    dec_out_t    dec_ctrl;
    logic [31:0] dec_imm;
    logic [4:0]  dec_rd_addr, dec_rs1_addr, dec_rs2_addr;
    logic        dec_valid_o, dec_ready_i;
    logic [31:0] rf_r1_data, rf_r2_data;
    id_ex_t      id_ex_in, id_ex_out;
    logic        id_ex_valid_o, id_ex_ready_i; // Driven by Control Logic
    logic        id_ex_ready_from_reg;         // FIXED: To avoid multiple drivers

    // --- EX Stage ---
    alu_in_t     alu_req_packet; 
    logic [31:0] alu_res;
    logic        alu_zero;
    logic [1:0]  fwd_a_sel, fwd_b_sel;
    logic [31:0] rs1_data_fwd, rs2_data_fwd;
    
    m_in_t       m_req_packet;
    logic        m_valid_i, m_ready_o, m_valid_o, m_ready_i;
    logic [31:0] m_result;

    csr_req_t    csr_req_final;
    logic [31:0] csr_rdata, csr_epc, csr_mtvec;
    logic        trap_triggered;
    logic [3:0]  trap_cause;
    logic [31:0] trap_val;
    logic        is_mret_ex;
    
    logic [31:0] pc_target, branch_target_ex; // FIXED: Added branch_target_ex
    logic        pc_taken, branch_taken, branch_condition_met;
    logic [31:0] pc_plus4_calc;

    ex_mem_t     ex_mem_in, ex_mem_out;
    logic        ex_mem_valid_o, ex_mem_ready_i;

    // --- MEM Stage ---
    logic        lsu_valid_o, lsu_ready_i;
    logic [31:0] lsu_load_data;
    mem_wb_t     mem_wb_in, mem_wb_out;
    logic        mem_wb_valid_o, mem_wb_ready_i;

    // --- WB Stage ---
    logic [31:0] wb_final_data;

    // =========================================================================
    // HAZARD DETECTION & GLOBAL STALL
    // =========================================================================
    // =========================================================================
    // STAGE 1: FETCH (IF)
    // =========================================================================
    pc_gen u_pc_gen (
        .clk_i                (clk_i),
        .rst_i                (rst_i),
        .ready_i              (imem_ready_o && !pc_stall), 
        .valid_o              (imem_valid_o),
        .branch_taken_i       (pc_taken),
        .branch_target_addr_i (pc_target),
        .pc_o                 (imem_addr_o)
    );

    pipeline_reg #( .T_DATA(if_id_t) ) u_if_id_reg (
        .clk_i    (clk_i),
        .rst_i    (rst_i),
        .flush_i  (flush_pipeline),
        .valid_i  (imem_valid_i),
        .ready_o  (imem_ready_o),
        .data_i   (if_id_in),
        .data_o   (if_id_out),
        .valid_o  (if_id_valid_o),
        .ready_i  (if_id_ready_i && !if_id_stall)
    );

    assign if_id_in.pc    = imem_addr_o;
    assign if_id_in.instr = imem_instr_i;

    // =========================================================================
    // STAGE 2: DECODE (ID)
    // =========================================================================
    decoder u_decoder (
        .instr_i    (if_id_out.instr),
        .ctrl_o     (dec_ctrl),
        .imm_o      (dec_imm),
        .rd_addr_o  (dec_rd_addr),
        .rs1_addr_o (dec_rs1_addr),
        .rs2_addr_o (dec_rs2_addr),
        .valid_i    (if_id_valid_o),
        .ready_o    (if_id_ready_i),
        .valid_o    (dec_valid_o),
        .ready_i    (dec_ready_i)
    );

    register u_reg_file (
        .clk_i    (clk_i),
        .rst_i    (rst_i),
        .w_ena_i  (mem_wb_out.ctrl.rf_we && mem_wb_valid_o),
        .w_addr_i (mem_wb_out.rd_addr),
        .w_data_i (wb_final_data),
        .r1_addr_i(dec_rs1_addr),
        .r1_data_o(rf_r1_data),
        .r2_addr_i(dec_rs2_addr),
        .r2_data_o(rf_r2_data)
    );

    pipeline_reg #( .T_DATA(id_ex_t) ) u_id_ex_reg (
        .clk_i    (clk_i),
        .rst_i    (rst_i),
        .flush_i  (flush_pipeline || id_ex_flush),
        .valid_i  (dec_valid_o),
        .ready_o  (dec_ready_i),
        .data_i   (id_ex_in),
        .data_o   (id_ex_out),
        .valid_o  (id_ex_valid_o),
        .ready_i  (id_ex_ready_i) // Driven by Stage 3 Logic
    );

    assign id_ex_in.pc       = if_id_out.pc;
    assign id_ex_in.ctrl     = dec_ctrl;
    assign id_ex_in.rs1_data = rf_r1_data;
    assign id_ex_in.rs2_data = rf_r2_data;
    assign id_ex_in.imm      = dec_imm;
    assign id_ex_in.rd_addr  = dec_rd_addr;
    assign id_ex_in.rs1_addr = dec_rs1_addr;
    assign id_ex_in.rs2_addr = dec_rs2_addr;

    // =========================================================================
    // STAGE 3: EXECUTE (EX)
    // =========================================================================
    
    // 1. Forwarding Unit Instance
    forwarding_unit u_fwd_unit (
        .rs1_addr_ex (id_ex_out.rs1_addr),
        .rs2_addr_ex (id_ex_out.rs2_addr),
        .rd_addr_mem (ex_mem_out.rd_addr),
        .rf_we_mem   (ex_mem_out.ctrl.rf_we && ex_mem_valid_o),
        .rd_addr_wb  (mem_wb_out.rd_addr),
        .rf_we_wb    (mem_wb_out.ctrl.rf_we && mem_wb_valid_o),
        .forward_a_o (fwd_a_sel),
        .forward_b_o (fwd_b_sel)
    );

    // 2. Data Muxing (Forwarding)
    always_comb begin
        case (fwd_a_sel)
            2'b10:   rs1_data_fwd = ex_mem_out.alu_result;
            2'b01:   rs1_data_fwd = wb_final_data;
            default: rs1_data_fwd = id_ex_out.rs1_data;
        endcase
        case (fwd_b_sel)
            2'b10:   rs2_data_fwd = ex_mem_out.alu_result;
            2'b01:   rs2_data_fwd = wb_final_data;
            default: rs2_data_fwd = id_ex_out.rs2_data;
        endcase
    end

    // 3. ALU & M-Unit & CSR Units
    alu u_alu (
        .alu_in  (alu_req_packet),
        .Zero    (alu_zero),
        .alu_o   (alu_res),
        .vaild_o (), .ready_o ()
    );

    riscv_m_unit u_m_unit (
        .clk(clk_i), .rst(rst_i),
        .valid_i(m_valid_i), .ready_o(m_ready_o),
        .m_in(m_req_packet),
        .valid_o(m_valid_o), .ready_i(m_ready_i),
        .result_o(m_result)
    );

    csr u_csr_unit(
        .clk_i(clk_i), .rst_i(rst_i),
        .csr_req_i(csr_req_final), .csr_rdata_o(csr_rdata),
        .trap_valid_i(trap_triggered), .trap_cause_i(trap_cause),
        .trap_pc_i(id_ex_out.pc), .trap_val_i(trap_val),
        .mret_i(is_mret_ex), .epc_o(csr_epc), .trap_vector_o(csr_mtvec),
        .irq_sw_i(irq_sw_i), .irq_timer_i(irq_timer_i), .irq_ext_i(irq_ext_i)
    );

    // 4. Execution Stage Control Logic
    always_comb begin
        // ALU Mux
        alu_req_packet.a = (id_ex_out.ctrl.alu_req.op_a_sel == OP_A_PC) ? id_ex_out.pc : rs1_data_fwd;
        alu_req_packet.b = (id_ex_out.ctrl.alu_req.op_b_sel == OP_B_IMM) ? id_ex_out.imm : rs2_data_fwd;
        alu_req_packet.op = id_ex_out.ctrl.alu_req.op;
        alu_req_packet.valid_i = 1'b1; alu_req_packet.ready_i = 1'b1;

        // M-Unit Mux
        m_req_packet.a_i = rs1_data_fwd;
        m_req_packet.b_i = rs2_data_fwd;
        m_req_packet.op  = id_ex_out.ctrl.m_req.op;
        m_valid_i = id_ex_valid_o && id_ex_out.ctrl.m_req.valid;

        // Stage Ready/Stall Logic
        if (id_ex_out.ctrl.m_req.valid) begin
            id_ex_ready_i = m_valid_o && id_ex_ready_from_reg;
            m_ready_i     = ex_mem_ready_i;
        end else begin
            id_ex_ready_i = id_ex_ready_from_reg;
            m_ready_i     = 1'b0;
        end
    end

    // 5. Branch & Trap & PC Next Logic
    assign branch_target_ex = (id_ex_out.ctrl.br_req.is_jump) ? alu_res : (id_ex_out.pc + id_ex_out.imm);
    assign pc_plus4_calc    = id_ex_out.pc + 32'd4;

    always_comb begin
        branch_condition_met = 1'b0;
        if (id_ex_valid_o && id_ex_out.ctrl.br_req.is_branch) begin
            case (id_ex_out.ctrl.br_req.op)
                BR_BEQ:  branch_condition_met = (rs1_data_fwd == rs2_data_fwd);
                BR_BNE:  branch_condition_met = (rs1_data_fwd != rs2_data_fwd);
                BR_BLT:  branch_condition_met = ($signed(rs1_data_fwd) <  $signed(rs2_data_fwd));
                BR_BGE:  branch_condition_met = ($signed(rs1_data_fwd) >= $signed(rs2_data_fwd));
                BR_BLTU: branch_condition_met = (rs1_data_fwd <  rs2_data_fwd);
                BR_BGEU: branch_condition_met = (rs1_data_fwd >= rs2_data_fwd);
                default: branch_condition_met = 1'b0;
            endcase
        end
    end

    assign branch_taken = id_ex_valid_o && (id_ex_out.ctrl.br_req.is_jump || (id_ex_out.ctrl.br_req.is_branch && branch_condition_met));
    assign is_mret_ex   = id_ex_valid_o && id_ex_out.ctrl.is_mret;

    always_comb begin
        trap_triggered = 1'b0; trap_cause = 4'b0; trap_val = 32'b0;
        if (id_ex_valid_o) begin
            if (id_ex_out.ctrl.illegal_instr) begin
                trap_triggered = 1'b1; trap_cause = EXC_ILLEGAL_INSTR; trap_val = id_ex_out.pc;
            end else if (id_ex_out.ctrl.is_ecall) begin
                trap_triggered = 1'b1; trap_cause = EXC_ECALL_M;
            end else if (id_ex_out.ctrl.is_ebreak) begin
                trap_triggered = 1'b1; trap_cause = EXC_BREAKPOINT; trap_val = id_ex_out.pc;
            end
        end
    end

    always_comb begin
        pc_taken = 1'b0; pc_target = 32'b0;
        if (trap_triggered) begin pc_taken = 1'b1; pc_target = csr_mtvec; end
        else if (is_mret_ex) begin pc_taken = 1'b1; pc_target = csr_epc; end
        else if (branch_taken) begin pc_taken = 1'b1; pc_target = branch_target_ex; end
    end

    assign flush_pipeline = pc_taken;

    // 6. CSR Packing
    always_comb begin
        csr_req_final = id_ex_out.ctrl.csr_req;
        if (id_ex_out.ctrl.csr_req.valid && !id_ex_out.ctrl.csr_req.is_imm)
            csr_req_final.wdata = rs1_data_fwd;
    end

    // 7. EX -> MEM Register
    pipeline_reg #( .T_DATA(ex_mem_t) ) u_ex_mem_reg (
        .clk_i    (clk_i), .rst_i (rst_i), .flush_i (1'b0),
        .valid_i  (id_ex_out.ctrl.m_req.valid ? m_valid_o : id_ex_valid_o),
        .ready_o  (id_ex_ready_from_reg),
        .data_i   (ex_mem_in), .data_o (ex_mem_out),
        .valid_o  (ex_mem_valid_o), .ready_i (ex_mem_ready_i)
    );

    assign ex_mem_in.ctrl       = id_ex_out.ctrl;
    assign ex_mem_in.alu_result = alu_res;
    assign ex_mem_in.m_result   = m_result;
    assign ex_mem_in.pc_plus4   = pc_plus4_calc;
    assign ex_mem_in.store_data = rs2_data_fwd;
    assign ex_mem_in.rd_addr    = id_ex_out.rd_addr;
    assign ex_mem_in.csr_data   = csr_rdata;

    // =========================================================================
    // STAGE 4: MEMORY (MEM)
    // =========================================================================
    lsu u_lsu (
        .clk_i(clk_i), .rst_i(rst_i),
        .addr_i(ex_mem_out.alu_result), .wdata_i(ex_mem_out.store_data),
        .lsu_we_i(ex_mem_out.ctrl.lsu_req.we),
        .funct3_i({ex_mem_out.ctrl.lsu_req.is_unsigned, ex_mem_out.ctrl.lsu_req.width}),
        .valid_i(ex_mem_valid_o), .ready_o(ex_mem_ready_i),
        .valid_o(lsu_valid_o), .ready_i(lsu_ready_i),
        .dmem_addr_o(dmem_addr_o), .dmem_wdata_o(dmem_wdata_o),
        .dmem_be_o(dmem_be_o), .dmem_we_o(dmem_we_o), .dmem_rdata_i(dmem_rdata_i),
        .lsu_rdata_o(lsu_load_data), .lsu_err_o()
    );

    pipeline_reg #( .T_DATA(mem_wb_t) ) u_mem_wb_reg (
        .clk_i(clk_i), .rst_i(rst_i), .flush_i(1'b0),
        .valid_i((ex_mem_out.ctrl.wb_sel == WB_MEM || ex_mem_out.ctrl.lsu_req.we) ? lsu_valid_o : ex_mem_valid_o),
        .ready_o(lsu_ready_i),
        .data_i(mem_wb_in), .data_o(mem_wb_out),
        .valid_o(mem_wb_valid_o), .ready_i(mem_wb_ready_i)
    );

    assign dmem_ready_o = lsu_ready_i;
    assign mem_wb_in.ctrl       = ex_mem_out.ctrl;
    assign mem_wb_in.alu_result = ex_mem_out.alu_result;
    assign mem_wb_in.m_result   = ex_mem_out.m_result;
    assign mem_wb_in.pc_plus4   = ex_mem_out.pc_plus4;
    assign mem_wb_in.load_data  = lsu_load_data;
    assign mem_wb_in.rd_addr    = ex_mem_out.rd_addr;
    assign mem_wb_in.csr_data   = ex_mem_out.csr_data;

    // =========================================================================
    // STAGE 5: WRITEBACK (WB)
    // =========================================================================
    assign mem_wb_ready_i = 1'b1;

    always_comb begin
        case (mem_wb_out.ctrl.wb_sel)
            WB_ALU:      wb_final_data = mem_wb_out.alu_result;
            WB_MEM:      wb_final_data = mem_wb_out.load_data;
            WB_PC_PLUS4: wb_final_data = mem_wb_out.pc_plus4;
            WB_M_UNIT:   wb_final_data = mem_wb_out.m_result;
            WB_CSR:      wb_final_data = mem_wb_out.csr_data;
            default:     wb_final_data = 32'b0;
        endcase
    end

    // Hazard Unit Instance
    hazard_detection_unit u_hazard_unit (
        .id_ex_wb_sel   (id_ex_out.ctrl.wb_sel),
        .id_ex_rd       (id_ex_out.rd_addr),
        .if_id_rs1      (dec_rs1_addr),
        .if_id_rs2      (dec_rs2_addr),
        .pc_stall_o     (pc_stall),
        .if_id_stall_o  (if_id_stall),
        .id_ex_flush_o  (id_ex_flush)
    );

endmodule