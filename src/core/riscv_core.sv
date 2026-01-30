`timescale 1ns/1ps
import riscv_32im_pkg::*;
import riscv_instr::*;

module riscv_core (
    input  logic        clk_i,
    input  logic        rst_i,

    // --- Instruction Memory Interface (To IMEM) ---
    output logic [31:0] imem_addr_o,
    output logic        imem_valid_o,
    input  logic        imem_ready_i,
    input  logic [31:0] imem_instr_i,
    input  logic        imem_valid_i,
    output logic        imem_ready_o,

    // --- Data Memory Interface (To DMEM) ---
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
    // INTERNAL SIGNALS DECLARATION
        // --- Global Control ---
        logic flush_pipeline;

        // --- IF Stage Signals ---
        if_id_t      if_id_in, if_id_out;
        logic        if_id_valid_o, if_id_ready_i;

        // --- ID Stage Signals ---
        dec_out_t    dec_ctrl;
        logic [31:0] dec_imm;
        logic [4:0]  dec_rd_addr, dec_rs1_addr, dec_rs2_addr;
        logic        dec_valid_o, dec_ready_i;
        logic [31:0] rf_r1_data, rf_r2_data;
        
        id_ex_t      id_ex_in, id_ex_out;
        logic        id_ex_valid_o, id_ex_ready_i;

        // --- EX Stage Signals ---
        // ALU inputs wrapped in struct
        alu_in_t     alu_req_packet; 
        logic [31:0] alu_res;
        logic        alu_zero;
        
        // M-Unit inputs wrapped in struct
        m_in_t       m_req_packet;
        logic        m_valid_i, m_ready_o; // Handshake Input M-Unit
        logic        m_valid_o, m_ready_i; // Handshake Output M-Unit
        logic [31:0] m_result;

        // Branch Signals
        logic [31:0] branch_target;
        logic        branch_taken;
        logic [31:0] pc_plus4_calc;

        ex_mem_t     ex_mem_in, ex_mem_out;
        logic        ex_mem_valid_o, ex_mem_ready_i;

        // --- MEM Stage Signals ---
        logic        lsu_valid_o, lsu_ready_i;
        logic [31:0] lsu_load_data;
        
        mem_wb_t     mem_wb_in, mem_wb_out;
        logic        mem_wb_valid_o, mem_wb_ready_i;

        // --- WB Stage Signals ---
        logic [31:0] wb_final_data;
// DATAPATH (INSTANTIATIONS & WIRING)
    // ---------------------- STAGE 1: FETCH (IF) ----------------------
        pc_gen u_pc_gen (
            .clk_i                (clk_i),
            .rst_i                (rst_i),
            .ready_i              (imem_ready_i),
            .valid_o              (imem_valid_o),
            .branch_taken_i       (branch_taken),      // Wired from Control Logic
            .branch_target_addr_i (branch_target),     // Wired from Control Logic
            .pc_o                 (imem_addr_o)
        );

        pipeline_reg #( .T_DATA(if_id_t) ) u_if_id_reg (
            .clk_i    (clk_i),
            .rst_i    (rst_i),
            .flush_i  (flush_pipeline),                // Wired from Control Logic
            .valid_i  (imem_valid_i),
            .ready_o  (imem_ready_o),
            .data_i   (if_id_in),
            .data_o   (if_id_out),
            .valid_o  (if_id_valid_o),
            .ready_i  (if_id_ready_i)
        );
    // ---------------------- STAGE 2: DECODE (ID) ----------------------
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
            .clk_i      (clk_i),
            .rst_i      (rst_i),
            .w_ena_i    (mem_wb_out.ctrl.rf_we && mem_wb_valid_o), // Ghi từ WB Stage
            .w_addr_i   (mem_wb_out.rd_addr),
            .w_data_i_i (wb_final_data),               // Wired from WB Logic
            .r1_addr_i  (dec_rs1_addr),
            .r1_data_o  (rf_r1_data),
            .r2_addr_i  (dec_rs2_addr),
            .r2_data_o  (rf_r2_data)
        );

        pipeline_reg #( .T_DATA(id_ex_t) ) u_id_ex_reg (
            .clk_i    (clk_i),
            .rst_i    (rst_i),
            .flush_i  (flush_pipeline),
            .valid_i  (dec_valid_o),
            .ready_o  (dec_ready_i),
            .data_i   (id_ex_in),
            .data_o   (id_ex_out),
            .valid_o  (id_ex_valid_o),
            .ready_i  (id_ex_ready_i)
        );
    // ---------------------- STAGE 3: EXECUTE (EX) ----------------------
        alu u_alu (
            .alu_in     (alu_req_packet),              // Wired from Control Logic
            .Zero       (alu_zero),
            .alu_o      (alu_res),
            .vaild_o    (),                            // Ignore (Combinational)
            .ready_o    ()                             // Ignore
        );

        riscv_m_unit u_m_unit (
            .clk        (clk_i),
            .rst        (rst_i),
            .valid_i    (m_valid_i),                   // Wired from Control Logic
            .ready_o    (m_ready_o),
            .m_in       (m_req_packet),                // Wired from Control Logic
            .valid_o    (m_valid_o),
            .ready_i    (m_ready_i),                   // Wired from Control Logic
            .result_o   (m_result)
        );

        pipeline_reg #( .T_DATA(ex_mem_t) ) u_ex_mem_reg (
            .clk_i    (clk_i),
            .rst_i    (rst_i),
            .flush_i  (1'b0),
            // Mux Valid: Nếu là lệnh M-Unit, lấy valid từ M-Unit. Lệnh thường lấy từ Pipeline cũ.
            .valid_i  (id_ex_out.ctrl.m_req.valid ? m_valid_o : id_ex_valid_o),
            .ready_o  (), // Handshake này xử lý ở Control Logic
            .data_i   (ex_mem_in),
            .data_o   (ex_mem_out),
            .valid_o  (ex_mem_valid_o),
            .ready_i  (ex_mem_ready_i)
        );
    // ---------------------- STAGE 4: MEMORY (MEM) ----------------------
        lsu u_lsu (
            .clk_i        (clk_i),
            .rst_i        (rst_i),
            .addr_i       (ex_mem_out.alu_result),
            .wdata_i      (ex_mem_out.store_data),
            .lsu_we_i     (ex_mem_out.ctrl.lsu_req.we),
            .funct3_i     (ex_mem_out.ctrl.lsu_req.width), // Lưu ý type cast nếu cần
            // Handshake internal
            .valid_i      (ex_mem_valid_o),
            .ready_o      (ex_mem_ready_i),
            .valid_o      (lsu_valid_o),
            .ready_i      (lsu_ready_i),
            // External Interface to DMEM
            .dmem_addr_o  (dmem_addr_o),
            .dmem_wdata_o (dmem_wdata_o),
            .dmem_be_o    (dmem_be_o),
            .dmem_we_o    (dmem_we_o),
            .dmem_rdata_i (dmem_rdata_i),
            // Result back to Core
            .lsu_rdata_o  (lsu_load_data),
            .lsu_err_o    ()
        );

        pipeline_reg #( .T_DATA(mem_wb_t) ) u_mem_wb_reg (
            .clk_i    (clk_i),
            .rst_i    (rst_i),
            .flush_i  (1'b0),
            .valid_i  (dmem_valid_o),  // Chờ Memory valid
            .ready_o  (dmem_ready_i),
            .data_i   (mem_wb_in),
            .data_o   (mem_wb_out),
            .valid_o  (mem_wb_valid_o),
            .ready_i  (mem_wb_ready_i)
        );
// CONTROL LOGIC (COMBINATIONAL LOGIC BLOCK)
    // ---------------------- FETCH LOGIC ----------------------
        // Đóng gói IF -> ID
        assign if_id_in.pc    = imem_addr_o;
        assign if_id_in.instr = imem_instr_i;

    // ---------------------- DECODE LOGIC ----------------------
        // Đóng gói ID -> EX
        assign id_ex_in.pc       = if_id_out.pc;
        assign id_ex_in.ctrl     = dec_ctrl;
        assign id_ex_in.rs1_data = rf_r1_data;
        assign id_ex_in.rs2_data = rf_r2_data;
        assign id_ex_in.imm      = dec_imm;
        assign id_ex_in.rd_addr  = dec_rd_addr;
        assign id_ex_in.rs1_addr = dec_rs1_addr;
        assign id_ex_in.rs2_addr = dec_rs2_addr;

    // ---------------------- EXECUTE LOGIC ----------------------
    
        // 1. ALU Input Muxing & Packing
        always_comb begin
            // Mux chọn OpA
            if (id_ex_out.ctrl.alu_req.op_a_sel == OP_A_PC)
                alu_req_packet.a = id_ex_out.pc;
            else
                alu_req_packet.a = id_ex_out.rs1_data;

            // Mux chọn OpB
            if (id_ex_out.ctrl.alu_req.op_b_sel == OP_B_IMM)
                alu_req_packet.b = id_ex_out.imm;
            else
                alu_req_packet.b = id_ex_out.rs2_data;
                
            alu_req_packet.op      = id_ex_out.ctrl.alu_req.op;
            // Các tín hiệu này ALU không dùng cho logic tính toán, gán 1 để bypass
            alu_req_packet.valid_i = 1'b1; 
            alu_req_packet.ready_i = 1'b1;
        end

        // 2. M-Unit Input Packing & Control
        assign m_req_packet.a_i = id_ex_out.rs1_data;
        assign m_req_packet.b_i = id_ex_out.rs2_data;
        assign m_req_packet.op  = id_ex_out.ctrl.m_req.op;

        // Kích hoạt M-Unit khi Decoder báo lệnh MUL/DIV và Data Valid
        assign m_valid_i = id_ex_valid_o && id_ex_out.ctrl.m_req.valid;

        // Logic Stall (Back-pressure) cho EX Stage
        always_comb begin
            if (id_ex_out.ctrl.m_req.valid) begin
                // Lệnh M-Unit: Chờ M-Unit xong và Tầng sau ready
                id_ex_ready_i = m_valid_o && ex_mem_ready_i;
                m_ready_i     = ex_mem_ready_i; 
            end else begin
                // Lệnh thường: Chờ Tầng sau ready (Bypass ALU)
                id_ex_ready_i = ex_mem_ready_i;
                m_ready_i     = 1'b0; 
            end
        end

        // 3. Branch Logic
        assign branch_target = id_ex_out.pc + id_ex_out.imm; 
        assign pc_plus4_calc = id_ex_out.pc + 32'd4;

        always_comb begin
            branch_taken = 1'b0;
            if (id_ex_valid_o) begin 
                if (id_ex_out.ctrl.br_req.is_jump) begin
                    branch_taken = 1'b1; // JAL, JALR
                end else if (id_ex_out.ctrl.br_req.is_branch) begin
                    case (id_ex_out.ctrl.br_req.op)
                        BR_BEQ:  branch_taken = (id_ex_out.rs1_data == id_ex_out.rs2_data);
                        BR_BNE:  branch_taken = (id_ex_out.rs1_data != id_ex_out.rs2_data);
                        BR_BLT:  branch_taken = ($signed(id_ex_out.rs1_data) <  $signed(id_ex_out.rs2_data));
                        BR_BGE:  branch_taken = ($signed(id_ex_out.rs1_data) >= $signed(id_ex_out.rs2_data));
                        BR_BLTU: branch_taken = (id_ex_out.rs1_data <  id_ex_out.rs2_data);
                        BR_BGEU: branch_taken = (id_ex_out.rs1_data >= id_ex_out.rs2_data);
                        default: branch_taken = 1'b0;
                    endcase
                end
            end
        end

        assign flush_pipeline = branch_taken;

        // 4. Packing EX -> MEM
        assign ex_mem_in.ctrl       = id_ex_out.ctrl;
        assign ex_mem_in.alu_result = alu_res;
        assign ex_mem_in.m_result   = m_result;      // Nối kết quả M-Unit
        assign ex_mem_in.pc_plus4   = pc_plus4_calc; // Nối PC+4
        assign ex_mem_in.store_data = id_ex_out.rs2_data;
        assign ex_mem_in.rd_addr    = id_ex_out.rd_addr;

    // ---------------------- MEMORY LOGIC ----------------------
        // Wiring Handshake
        assign lsu_ready_i  = mem_wb_ready_i;
        assign dmem_ready_o = mem_wb_ready_i;

        // Packing MEM -> WB
        assign mem_wb_in.ctrl       = ex_mem_out.ctrl;
        assign mem_wb_in.alu_result = ex_mem_out.alu_result;
        assign mem_wb_in.m_result   = ex_mem_out.m_result;   // Pass through
        assign mem_wb_in.pc_plus4   = ex_mem_out.pc_plus4;   // Pass through
        assign mem_wb_in.load_data  = lsu_load_data;
        assign mem_wb_in.rd_addr    = ex_mem_out.rd_addr;

    // ---------------------- WRITEBACK LOGIC ----------------------
        assign mem_wb_ready_i = 1'b1; // Register File luôn sẵn sàng

        always_comb begin
            case (mem_wb_out.ctrl.wb_sel)
                WB_ALU:      wb_final_data = mem_wb_out.alu_result;
                WB_MEM:      wb_final_data = mem_wb_out.load_data;
                WB_PC_PLUS4: wb_final_data = mem_wb_out.pc_plus4;
                WB_M_UNIT:   wb_final_data = mem_wb_out.m_result;
                default:     wb_final_data = 32'b0;
            endcase
        end

endmodule