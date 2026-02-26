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
// 5. SCOREBOARD (PRO REPORTING & CHECKING)
// -----------------------------------------------------------------------------
class decoder_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(decoder_scoreboard)
    uvm_analysis_imp #(decoder_item, decoder_scoreboard) sb_export;
    
    // --- BIẾN THỐNG KÊ ---
    int instr_count[string]; // Map để đếm tên lệnh: "ADD" -> 50 lần
    
    int cnt_total   = 0;
    int cnt_illegal = 0;
    int cnt_rf_write = 0;
    int cnt_mem_req  = 0;
    int cnt_br_jump  = 0;

    // --- BIẾN ĐIỀU KHIỂN LOG ---
    bit verbose = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) begin
            verbose = 1;
            `uvm_info("SCB", "DEBUG MODE: ENABLED", UVM_LOW)
        end
    endfunction

    // Hàm nhận diện tên lệnh (Dùng Casez giống DUT để đối chiếu)
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

    function void write(decoder_item pkt);
        string name;
        string msg;
        bit    is_pass = 1;

        name = identify_instr(pkt.instr);

        // --- 1. BASIC CHECKING ---
        if (name == "ILLEGAL") begin
            if (pkt.ctrl.illegal_instr !== 1'b1) begin
                `uvm_error("FAIL", $sformatf("Missed ILLEGAL detection! Instr: %h", pkt.instr))
                is_pass = 0;
            end
        end else begin
            if (pkt.ctrl.illegal_instr === 1'b1) begin
                `uvm_error("FAIL", $sformatf("Valid Instr %s detected as ILLEGAL!", name))
                is_pass = 0;
            end
        end

        // --- 2. LOGGING ---
        if (is_pass && verbose) begin
            msg = $sformatf("[PASS] Instr:%-8s | Hex:%h | RF_WE:%b", name, pkt.instr, pkt.ctrl.rf_we);
            $display(msg);
        end

        // --- 3. STATISTICS GATHERING ---
        if (instr_count.exists(name)) instr_count[name]++; else instr_count[name] = 1;
        
        cnt_total++;
        if (pkt.ctrl.illegal_instr) cnt_illegal++;
        if (pkt.ctrl.rf_we)         cnt_rf_write++;
        if (pkt.ctrl.lsu_req.re || pkt.ctrl.lsu_req.we) cnt_mem_req++;
        if (pkt.ctrl.br_req.is_branch || pkt.ctrl.br_req.is_jump) cnt_br_jump++;

    endfunction

    function void report_phase(uvm_phase phase);
        string name_str;

        $display("\n==================================================");
        $display("          DECODER VERIFICATION REPORT             ");
        $display("==================================================");
        
        $display("\n--- 1. INSTRUCTION COVERAGE ---");
        foreach (instr_count[key]) begin
             $display("Instr %-10s : Detected %0d times", key, instr_count[key]);
        end

        $display("\n--- 2. QUALITY METRICS (CORNER CASES) ---");
        $display("Total Instructions   : %0d", cnt_total);
        $display("Illegal Instructions : %0d", cnt_illegal);
        $display("Register File Writes : %0d", cnt_rf_write);
        $display("Memory Accesses (L/S): %0d", cnt_mem_req);
        $display("Branch / Jump Taken  : %0d", cnt_br_jump);
        
        $display("\n==================================================\n");
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