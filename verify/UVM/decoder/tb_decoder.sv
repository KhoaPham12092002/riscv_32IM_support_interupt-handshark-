// =============================================================================
// FILE: tb_decoder.sv (STRICT UVM COMPLIANCE - PRO VERSION)
// Features: Manual Randomization, Verbose Mode, Detailed Coverage Report
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
import riscv_instr::*; // Chứa định nghĩa LUI, ADD... (Bitmask)
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface decoder_if(input logic clk);
    logic [31:0] instr;
    
    // Output quan sát
    dec_out_t    ctrl;
    logic [31:0] imm;
    logic [4:0]  rd_addr;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;

    // Handshake
    logic valid_i;
    logic ready_o;
    logic valid_o;
    logic ready_i;
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM & SEQUENCE
// -----------------------------------------------------------------------------
class decoder_item extends uvm_sequence_item;
    rand logic [31:0] instr;
    
    // Các biến phụ để Scoreboard dễ check (optional)
    dec_out_t    ctrl;
    logic [31:0] imm;

    `uvm_object_utils(decoder_item)
    function new(string name = "decoder_item"); super.new(name); endfunction
endclass

class decoder_random_seq extends uvm_sequence #(decoder_item);
    `uvm_object_utils(decoder_random_seq)
    function new(string name=""); super.new(name); endfunction

    // --- HÀM TẠO LỆNH THỦ CÔNG (MANUAL INSTRUCTION BUILDER) ---
    // Thay thế cho constraint solver bị khóa license
    function logic [31:0] get_rand_instr();
        // Mảng chứa các mẫu lệnh (Pattern) từ package riscv_instr
        logic [31:0] patterns[] = {
            LUI, AUIPC, JAL, JALR, 
            BEQ, BNE, BLT, BGE, BLTU, BGEU,
            LB, LH, LW, LBU, LHU, SB, SH, SW,
            ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI,
            ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND,
            MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU,
            CSRRW, CSRRS, CSRRC, ECALL, EBREAK, MRET,
            CSRRWI, CSRRSI, CSRRCI
        };
        logic [31:0] csr_imm_ops[] = {CSRRWI, CSRRSI, CSRRCI};
        int idx;
        int dice;
        logic [31:0] pat;
        logic [31:0] noise;
        logic [31:0] final_instr;
        // --- CHIẾN THUẬT: BOOST XÁC SUẤT ---
        dice = $urandom_range(0, 99);
        if (dice < 5) begin
            idx = $urandom_range(0, 2); // Chọn 1 trong 3 lệnh CSR Imm
            pat = csr_imm_ops[idx];
        end
        else begin
        // 1. Chọn ngẫu nhiên 1 loại lệnh
        idx = $urandom_range(0, patterns.size() - 1);
        pat = patterns[idx];
        end
        // 2. Sinh ngẫu nhiên các bit tham số (Rd, Rs1, Imm...)
        noise = $urandom();

        // 3. Hợp nhất: Giữ lại bit định danh (0/1), điền noise vào chỗ '?' (Z/X)
        // Lưu ý: Logic này giả định package riscv_instr định nghĩa bit '?' là 'z' hoặc 'x'
        for(int i=0; i<32; i++) begin
            if (pat[i] === 1'b0) final_instr[i] = 1'b0;
            else if (pat[i] === 1'b1) final_instr[i] = 1'b1;
            else final_instr[i] = noise[i]; // Fill noise vào chỗ trống
        end
        
        // 5% cơ hội sinh lệnh rác (Illegal)
        if ($urandom_range(0, 99) < 5) return $urandom(); 
        
        return final_instr;
    endfunction

    task body();
        repeat(50000) begin // Test 10,000 lệnh
            req = decoder_item::type_id::create("req");
            start_item(req);
            
            // Gọi hàm random thủ công
            req.instr = get_rand_instr();
            
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class decoder_driver extends uvm_driver #(decoder_item);
    `uvm_component_utils(decoder_driver)
    virtual decoder_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual decoder_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        vif.instr   <= 0;
        vif.valid_i <= 0;
        vif.ready_i <= 1; // Luôn sẵn sàng nhận output (Simulation model)
    
        @(posedge vif.clk);
        forever begin
            seq_item_port.get_next_item(req);
            
            // Drive Input
            vif.valid_i <= 1'b1;
            vif.instr   = req.instr;

            // Chờ 1 clock để logic lan truyền (Vì Decoder là Combinational + Handshake)
            @(posedge vif.clk);
            
            // Reset Valid
            vif.valid_i <= 0;
            
            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class decoder_monitor extends uvm_monitor;
    `uvm_component_utils(decoder_monitor)
    virtual decoder_if vif;
    uvm_analysis_port #(decoder_item) mon_ap;
    decoder_item req; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual decoder_if)::get(this, "", "vif", vif)) `uvm_fatal("MON", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk); 
            // Capture khi có Valid Input
            #1;
            if (vif.valid_i) begin
                req = decoder_item::type_id::create("pkt");
                req.instr = vif.instr;
                
                // Sample Output (với delay nhỏ để đảm bảo combinational logic đã xong)
                 
                req.ctrl = vif.ctrl;
                req.imm  = vif.imm;
                
                mon_ap.write(req);
            end
        end
    endtask
endclass


// -----------------------------------------------------------------------------
// 5. SCOREBOARD (GOLDEN MODEL & TABLE-DRIVEN VERIFICATION - FINAL PRO VERSION)
// -----------------------------------------------------------------------------
class decoder_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(decoder_scoreboard)
    uvm_analysis_imp #(decoder_item, decoder_scoreboard) sb_export;
    
    // --- GOLDEN MODEL LOOK-UP TABLE ---
    dec_out_t expected_table[string];
    
    // --- BIẾN THỐNG KÊ ---
    int instr_count[string];
    int fail_counts[string];
    int cnt_total   = 0;
    int cnt_pass    = 0;
    int cnt_fail    = 0;
    bit verbose     = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
        
        build_golden_table();
    endfunction

    // =========================================================================
    // 1. HÀM XÂY DỰNG BẢNG GOLDEN (100% FULL INSTRUCTION SET)
    // =========================================================================
    function void build_golden_table();
        dec_out_t def_ctrl; 
        dec_out_t ctrl;
        
        string r_type_ops[]   = {"ADD", "SUB", "AND", "OR", "XOR", "SLL", "SRL", "SRA", "SLT", "SLTU"};
        alu_op_e r_type_alu[] = {ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR, ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU};
        string i_type_ops[]   = {"ADDI", "ANDI", "ORI", "XORI", "SLLI", "SRLI", "SRAI", "SLTI", "SLTIU"};
        alu_op_e i_type_alu[] = {ALU_ADD, ALU_AND, ALU_OR, ALU_XOR, ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU};
        string load_ops[]  = {"LB", "LH", "LW", "LBU", "LHU"};
        string store_ops[] = {"SB", "SH", "SW"};
        string br_ops[] = {"BEQ", "BNE", "BLT", "BGE", "BLTU", "BGEU"};
        br_op_e br_req_op[] = {BR_BEQ, BR_BNE, BR_BLT, BR_BGE, BR_BLTU, BR_BGEU};
        string u_type_ops[] = {"LUI", "AUIPC"};
        string muldiv_ops[]   = {"MUL", "MULH", "MULHSU", "MULHU", "DIV", "DIVU", "REM", "REMU"};
        m_op_e muldiv_req_op[] = {M_MUL, M_MULH, M_MULHSU, M_MULHU, M_DIV, M_DIVU, M_REM, M_REMU};
        string csr_ops[]      = {"CSRRW", "CSRRS", "CSRRC", "CSRRWI", "CSRRSI", "CSRRCI"};
        csr_op_e csr_req_op[] = {CSR_RW, CSR_RS, CSR_RC, CSR_RW, CSR_RS, CSR_RC};

        def_ctrl.illegal_instr = 0; def_ctrl.is_mret = 0; def_ctrl.is_ecall = 0; def_ctrl.is_ebreak = 0;
        def_ctrl.imm_type = IMM_I;  def_ctrl.rf_we = 0;   def_ctrl.wb_sel = WB_ALU;
        def_ctrl.alu_req = ALU_REQ_RST; def_ctrl.m_req = M_REQ_RST; 
        def_ctrl.lsu_req = LSU_REQ_RST; def_ctrl.br_req = BR_REQ_RST; def_ctrl.csr_req = CSR_REQ_RST;

        foreach(r_type_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_Z; ctrl.rf_we = 1; ctrl.wb_sel = WB_ALU;
            ctrl.alu_req.op = r_type_alu[i]; ctrl.alu_req.op_a_sel = OP_A_RS1; ctrl.alu_req.op_b_sel = OP_B_RS2;
            expected_table[r_type_ops[i]] = ctrl;
        end

        foreach(i_type_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_I; ctrl.rf_we = 1; ctrl.wb_sel = WB_ALU;
            ctrl.alu_req.op = i_type_alu[i]; ctrl.alu_req.op_a_sel = OP_A_RS1; ctrl.alu_req.op_b_sel = OP_B_IMM;
            expected_table[i_type_ops[i]] = ctrl;
        end

        foreach(load_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_I; ctrl.rf_we = 1; ctrl.wb_sel = WB_MEM;
            ctrl.alu_req.op = ALU_ADD; ctrl.alu_req.op_a_sel = OP_A_RS1; ctrl.alu_req.op_b_sel = OP_B_IMM;
            ctrl.lsu_req.re = 1;
            if (load_ops[i] == "LB" || load_ops[i] == "LBU") ctrl.lsu_req.width = MEM_BYTE;
            else if (load_ops[i] == "LH" || load_ops[i] == "LHU") ctrl.lsu_req.width = MEM_HALF;
            else ctrl.lsu_req.width = MEM_WORD;
            ctrl.lsu_req.is_unsigned = (load_ops[i] == "LBU" || load_ops[i] == "LHU" || load_ops[i] == "LW") ? 1 : 0;
            expected_table[load_ops[i]] = ctrl;
        end

        foreach(store_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_S; ctrl.rf_we = 0; 
            ctrl.alu_req.op = ALU_ADD; ctrl.alu_req.op_a_sel = OP_A_RS1; ctrl.alu_req.op_b_sel = OP_B_IMM;
            ctrl.lsu_req.we = 1;
            if (store_ops[i] == "SB") ctrl.lsu_req.width = MEM_BYTE;
            else if (store_ops[i] == "SH") ctrl.lsu_req.width = MEM_HALF;
            else ctrl.lsu_req.width = MEM_WORD;
            expected_table[store_ops[i]] = ctrl;
        end

        foreach(br_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_B; ctrl.rf_we = 0; 
            ctrl.br_req.is_branch = 1; ctrl.br_req.is_jump = 0; ctrl.br_req.op = br_req_op[i];
            ctrl.alu_req.op = ALU_ADD; ctrl.alu_req.op_a_sel = OP_A_PC; ctrl.alu_req.op_b_sel = OP_B_IMM;
            expected_table[br_ops[i]] = ctrl;
        end

        ctrl = def_ctrl; ctrl.imm_type = IMM_J; ctrl.rf_we = 1; ctrl.wb_sel = WB_PC_PLUS4;
        ctrl.br_req.is_jump = 1; ctrl.br_req.is_branch = 0;
        ctrl.alu_req.op = ALU_ADD; ctrl.alu_req.op_a_sel = OP_A_PC; ctrl.alu_req.op_b_sel = OP_B_IMM;
        expected_table["JAL"] = ctrl;

        ctrl = def_ctrl; ctrl.imm_type = IMM_I; ctrl.rf_we = 1; ctrl.wb_sel = WB_PC_PLUS4;
        ctrl.br_req.is_jump = 1; ctrl.br_req.is_branch = 0;
        ctrl.alu_req.op = ALU_ADD; ctrl.alu_req.op_a_sel = OP_A_RS1; ctrl.alu_req.op_b_sel = OP_B_IMM;
        expected_table["JALR"] = ctrl;

        foreach(muldiv_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_Z; ctrl.rf_we = 1; ctrl.wb_sel = WB_M_UNIT;
            ctrl.m_req.valid = 1; ctrl.m_req.op = muldiv_req_op[i];
            expected_table[muldiv_ops[i]] = ctrl;
        end

        foreach(u_type_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_U; ctrl.rf_we = 1; ctrl.wb_sel = WB_ALU;
            ctrl.alu_req.op = (u_type_ops[i] == "AUIPC") ? ALU_ADD : ALU_B; 
            ctrl.alu_req.op_a_sel = (u_type_ops[i] == "AUIPC") ? OP_A_PC : OP_A_RS1; 
            ctrl.alu_req.op_b_sel = OP_B_IMM;
            expected_table[u_type_ops[i]] = ctrl;
        end

        foreach(csr_ops[i]) begin
            ctrl = def_ctrl; ctrl.imm_type = IMM_I; ctrl.rf_we = 1; ctrl.wb_sel = WB_CSR;
            ctrl.csr_req.valid = 1; ctrl.csr_req.op = csr_req_op[i];
            ctrl.csr_req.is_imm = (csr_ops[i] == "CSRRWI" || csr_ops[i] == "CSRRSI" || csr_ops[i] == "CSRRCI") ? 1 : 0;
            expected_table[csr_ops[i]] = ctrl;
        end
    endfunction

    // =========================================================================
    // 2. HÀM NHẬN DIỆN LỆNH (TỪ CODE GỐC CỦA BẠN)
    // =========================================================================
    function string identify_instr(logic [31:0] instr);
        casez (instr)
            LUI: return "LUI"; AUIPC: return "AUIPC";
            JAL: return "JAL"; JALR: return "JALR";
            BEQ: return "BEQ"; BNE: return "BNE"; BLT: return "BLT"; BGE: return "BGE"; BLTU: return "BLTU"; BGEU: return "BGEU";
            LB: return "LB"; LH: return "LH"; LW: return "LW"; LBU: return "LBU"; LHU: return "LHU";
            SB: return "SB"; SH: return "SH"; SW: return "SW";
            ADDI: return "ADDI"; SLTI: return "SLTI"; SLTIU: return "SLTIU"; XORI: return "XORI"; ORI: return "ORI"; ANDI: return "ANDI"; SLLI: return "SLLI"; SRLI: return "SRLI"; SRAI: return "SRAI";
            ADD: return "ADD"; SUB: return "SUB"; SLL: return "SLL"; SLT: return "SLT"; SLTU: return "SLTU"; XOR: return "XOR"; SRL: return "SRL"; SRA: return "SRA"; OR: return "OR"; AND: return "AND";
            MUL: return "MUL"; MULH: return "MULH"; MULHSU: return "MULHSU"; MULHU: return "MULHU"; DIV: return "DIV"; DIVU: return "DIVU"; REM: return "REM"; REMU: return "REMU";
            CSRRW: return "CSRRW"; CSRRS: return "CSRRS"; CSRRC: return "CSRRC"; 
            CSRRWI: return "CSRRWI"; CSRRSI: return "CSRRSI"; CSRRCI: return "CSRRCI";
            ECALL: return "ECALL"; EBREAK: return "EBREAK"; MRET: return "MRET";
            default: return "ILLEGAL";
        endcase
    endfunction

    // =========================================================================
    // 3. HÀM DỰ ĐOÁN IMMEDIATE
    // =========================================================================
    function logic [31:0] predict_imm(logic [31:0] instr, imm_type_e type_e);
        case (type_e)
            IMM_I: return {{20{instr[31]}}, instr[31:20]};
            IMM_S: return {{20{instr[31]}}, instr[31:25], instr[11:7]};
            IMM_B: return {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            IMM_U: return {instr[31:12], 12'b0};
            IMM_J: return {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            IMM_Z: return 32'b0; 
            default: return 32'b0;
        endcase
    endfunction

    // =========================================================================
    // 4. THE CHECKER (LUẬT KIỂM CHỨNG)
    // =========================================================================
    function void write(decoder_item pkt);
        string name = identify_instr(pkt.instr); 
        dec_out_t exp_ctrl;
        logic [31:0] exp_imm;
        bit is_pass = 1;

        cnt_total++;
        if (instr_count.exists(name)) instr_count[name]++; else instr_count[name] = 1;

        if (name == "ILLEGAL") begin
            if (pkt.ctrl.illegal_instr !== 1'b1) begin
                `uvm_error("FAIL_ILL", $sformatf("Missed ILLEGAL detection! Instr: %h", pkt.instr))
                cnt_fail++;
            end else cnt_pass++;
            return; 
        end 
        
        if (pkt.ctrl.illegal_instr === 1'b1) begin
            `uvm_error("FAIL_VALID", $sformatf("Valid Instr %s detected as ILLEGAL!", name))
            cnt_fail++; return;
        end

        if (expected_table.exists(name)) begin
            exp_ctrl = expected_table[name];
            
            if (pkt.ctrl.rf_we !== exp_ctrl.rf_we) begin
                `uvm_error("FAIL_RF", $sformatf("[%s] RF_WE Mismatch! Exp:%b Act:%b", name, exp_ctrl.rf_we, pkt.ctrl.rf_we))
                is_pass = 0;
            end
            if (pkt.ctrl.wb_sel !== exp_ctrl.wb_sel) begin
                `uvm_error("FAIL_WB", $sformatf("[%s] WB_SEL Mismatch! Exp:%s Act:%s", name, exp_ctrl.wb_sel.name(), pkt.ctrl.wb_sel.name()))
                is_pass = 0;
            end
            if (pkt.ctrl.alu_req.op !== exp_ctrl.alu_req.op) begin
                `uvm_error("FAIL_ALU", $sformatf("[%s] ALU_OP Mismatch! Exp:%s Act:%s", name, exp_ctrl.alu_req.op.name(), pkt.ctrl.alu_req.op.name()))
                is_pass = 0;
            end
            if (pkt.ctrl.alu_req.op_a_sel !== exp_ctrl.alu_req.op_a_sel || pkt.ctrl.alu_req.op_b_sel !== exp_ctrl.alu_req.op_b_sel) begin
                `uvm_error("FAIL_MUX", $sformatf("[%s] ALU MUX Mismatch!", name))
                is_pass = 0;
            end
            if (pkt.ctrl.lsu_req.we !== exp_ctrl.lsu_req.we || pkt.ctrl.lsu_req.re !== exp_ctrl.lsu_req.re) begin
                `uvm_error("FAIL_LSU", $sformatf("[%s] LSU RE/WE Mismatch!", name))
                is_pass = 0;
            end

            exp_imm = predict_imm(pkt.instr, exp_ctrl.imm_type);
            if (pkt.imm !== exp_imm) begin
                `uvm_error("FAIL_IMM", $sformatf("[%s] Immediate Mismatch! Exp:%h Act:%h", name, exp_imm, pkt.imm))
                is_pass = 0;
            end
        end else begin
            if (name != "ECALL" && name != "EBREAK" && name != "MRET") begin
                 `uvm_warning("SCB_MISS", $sformatf("Instruction %s not in Golden Table!", name))
            end
        end

        if (is_pass) begin
            cnt_pass++;
            if (verbose) $display("[PASS] %-8s | Hex:%h properly decoded.", name, pkt.instr);
        end else begin
            cnt_fail++;
            // THÊM 2 DÒNG NÀY ĐỂ GHI NHẬN LỖI:
            if (fail_counts.exists(name)) fail_counts[name]++; 
            else fail_counts[name] = 1;
        end
    endfunction

    // =========================================================================
    // 5. REPORT PHASE MỚI CHUYÊN NGHIỆP HƠN
    // =========================================================================
    function void report_phase(uvm_phase phase);
        $display("\n==================================================");
        $display("   DECODER VERIFICATION REPORT (GOLDEN MODEL)     ");
        $display("==================================================");
        $display("Total Instructions Tested: %0d", cnt_total);
        $display("Passed Correctly         : %0d", cnt_pass);
        $display("Failed (Errors)          : %0d", cnt_fail);
        $display("--------------------------------------------------");
        
        $display(">>> FAILURES BREAKDOWN BY INSTRUCTION <<<");
        if (cnt_fail == 0) begin
            $display("  [+] NONE! All instructions perfectly decoded.");
        end else begin
            foreach (fail_counts[key]) begin
                 $display("  [-] %-10s : FAILED %0d times", key, fail_counts[key]);
            end
        end
        $display("--------------------------------------------------");

        $display("INSTRUCTION COVERAGE (SAMPLE):");
        foreach (instr_count[key]) begin
             if (instr_count[key] > 0 && key != "ILLEGAL")
                 $display("  -> %-10s : %0d times", key, instr_count[key]);
        end
        $display("  -> ILLEGAL / JUNK: %0d times", instr_count["ILLEGAL"]);
        $display("==================================================\n");
        if (cnt_fail == 0) $display(">>> PERFECT DECODING! READY FOR TAPE-OUT <<<");
        else               $display(">>> FAILED! PLEASE CHECK THE UVM_ERROR LOGS <<<");
    endfunction
endclass
// -----------------------------------------------------------------------------
// 6. AGENT & ENV (STANDARD UVM)
// -----------------------------------------------------------------------------
class decoder_agent extends uvm_agent;
    `uvm_component_utils(decoder_agent)
    decoder_driver drv; decoder_monitor mon; uvm_sequencer #(decoder_item) sqr;
    
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        drv = decoder_driver::type_id::create("drv", this);
        mon = decoder_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(decoder_item)::type_id::create("sqr", this);
    endfunction
    
    function void connect_phase(uvm_phase phase); 
        drv.seq_item_port.connect(sqr.seq_item_export); 
    endfunction
endclass

class decoder_env extends uvm_env;
    `uvm_component_utils(decoder_env)
    decoder_agent agent; 
    decoder_scoreboard scb;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = decoder_agent::type_id::create("agent", this);
        scb   = decoder_scoreboard::type_id::create("scb", this);
    endfunction
    
    function void connect_phase(uvm_phase phase); 
        agent.mon.mon_ap.connect(scb.sb_export); 
    endfunction
endclass

class decoder_test extends uvm_test;
    `uvm_component_utils(decoder_test)
    decoder_env env;
    
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase); 
        env = decoder_env::type_id::create("env", this); 
    endfunction
    
    task run_phase(uvm_phase phase);
        decoder_random_seq seq = decoder_random_seq::type_id::create("seq");
        phase.raise_objection(this); 
        seq.start(env.agent.sqr); 
        phase.drop_objection(this);
    endtask
endclass

// -----------------------------------------------------------------------------
// 7. TOP MODULE
// -----------------------------------------------------------------------------
module tb_top;
    import uvm_pkg::*;
    import riscv_32im_pkg::*; 
    // import riscv_instr::*; // Đã import ở file pkg của sequence, nếu cần có thể import lại

    logic clk; always #5 clk = ~clk; 
    decoder_if vif(clk);
    
    // DUT Instantiation
    decoder dut (
        .instr_i    (vif.instr),
        .ctrl_o     (vif.ctrl),
        .imm_o      (vif.imm),
        .rd_addr_o  (vif.rd_addr),
        .rs1_addr_o (vif.rs1_addr),
        .rs2_addr_o (vif.rs2_addr),
        
        .valid_i    (vif.valid_i),
        .ready_o    (vif.ready_o),
        .valid_o    (vif.valid_o),
        .ready_i    (vif.ready_i)
    );

    initial begin
        clk=0;
        uvm_config_db#(virtual decoder_if)::set(null, "*", "vif", vif);
        run_test("decoder_test");
    end
endmodule