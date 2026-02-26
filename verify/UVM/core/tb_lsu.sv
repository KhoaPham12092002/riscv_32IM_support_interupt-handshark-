// =============================================================================
// FILE: tb_lsu.sv (STRICT UVM COMPLIANCE - PRO VERSION)
// Features: LSU Handshake, Memory Simulation, Misaligned Checking
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
import riscv_32im_pkg::*; 
`include "uvm_macros.svh"

// -----------------------------------------------------------------------------
// 1. INTERFACE
// -----------------------------------------------------------------------------
interface lsu_if(input logic clk);
    logic        rst_i;

    // Interface with Core (Input)
    logic [31:0] addr_i;
    logic [31:0] wdata_i;
    logic        lsu_we_i;    // 1=Store, 0=Load
    logic [2:0]  funct3_i;    // Data type
    logic        valid_i;
    logic        ready_o;

    // Output to Core
    logic        valid_o;
    logic        ready_i;     // Core ready to accept result
    logic [31:0] lsu_rdata_o;
    logic        lsu_err_o;

    // Interface with DMEM (Memory Side)
    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;
    logic        dmem_we_o;
    logic [31:0] dmem_rdata_i; // Mock Memory Data
endinterface

// -----------------------------------------------------------------------------
// 2. SEQUENCE ITEM & SEQUENCE
// -----------------------------------------------------------------------------
class lsu_item extends uvm_sequence_item;
    // --- INPUTS ---
    rand logic [31:0] addr;
    rand logic [31:0] wdata;
    rand logic        we;      // 0: Load, 1: Store
    rand logic [2:0]  funct3;
    
    // --- MOCK MEMORY INPUT ---
    // Giả lập dữ liệu có sẵn trong RAM tại địa chỉ đó
    rand logic [31:0] mock_mem_data; 

    // --- OUTPUTS (OBSERVED) ---
    logic [31:0] actual_rdata;
    logic        actual_err;
    logic [31:0] actual_dmem_addr;
    logic [31:0] actual_dmem_wdata;
    logic [3:0]  actual_dmem_be;
    logic        actual_dmem_we;

    `uvm_object_utils_begin(lsu_item)
        `uvm_field_int(addr, UVM_DEFAULT)
        `uvm_field_int(wdata, UVM_DEFAULT)
        `uvm_field_int(we, UVM_DEFAULT)
        `uvm_field_int(funct3, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "lsu_item"); super.new(name); endfunction
endclass

class lsu_random_seq extends uvm_sequence #(lsu_item);
    `uvm_object_utils(lsu_random_seq)
    function new(string name=""); super.new(name); endfunction

    // --- MANUAL RANDOMIZATION FUNCTIONS ---
    
    // 1. Biased Data (Corner cases: 0, -1, Max, Min)
    function logic [31:0] get_biased_data();
        int dice = $urandom_range(0, 99);
        if (dice < 5)       return 32'h00000000; 
        else if (dice < 10) return 32'hFFFFFFFF; 
        else if (dice < 15) return 32'h7FFFFFFF; 
        else if (dice < 20) return 32'h80000000; 
        else                return $urandom();   
    endfunction

    // 2. Biased Address (Test Misaligned)
    function logic [31:0] get_biased_addr();
        int dice = $urandom_range(0, 99);
        logic [31:0] base;
        base = $urandom() & 32'hFFFFFFFC; // Mặc định Aligned 4 byte
        
        // 10% cơ hội sinh địa chỉ lẻ (Misaligned)
        if (dice < 10) return base | $urandom_range(1, 3); 
        else return base; // 90% Aligned
    endfunction

    // 3. Random Funct3 (LB, LH, LW, LBU, LHU, SB, SH, SW)
    function logic [2:0] get_rand_funct3(bit is_store);
        int sel;
        if (is_store) begin
            // Store: 000(SB), 001(SH), 010(SW)
            sel = $urandom_range(0, 2);
            return sel[2:0];
        end else begin
            // Load: 000(LB), 001(LH), 010(LW), 100(LBU), 101(LHU)
            logic [2:0] load_ops[] = '{3'b000, 3'b001, 3'b010, 3'b100, 3'b101};
            sel = $urandom_range(0, 4);
            return load_ops[sel];
        end
    endfunction

    task body();
        repeat(10000) begin
            req = lsu_item::type_id::create("req");
            start_item(req);
            
            // Randomize manually
            req.we            = $urandom_range(0, 1); // 50% Load, 50% Store
            req.addr          = get_biased_addr();
            req.wdata         = get_biased_data();
            req.mock_mem_data = get_biased_data(); // Dữ liệu giả định trong RAM
            req.funct3        = get_rand_funct3(req.we);
            
            finish_item(req);
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 3. DRIVER
// -----------------------------------------------------------------------------
class lsu_driver extends uvm_driver #(lsu_item);
    `uvm_component_utils(lsu_driver)
    virtual lsu_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual lsu_if)::get(this, "", "vif", vif)) `uvm_fatal("DRV", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        // Init Inputs
        vif.rst_i        <= 1;
        vif.valid_i      <= 0;
        vif.ready_i      <= 1; // Core luôn sẵn sàng nhận kết quả trả về
        vif.dmem_rdata_i <= 0;
        
        @(posedge vif.clk);
        vif.rst_i <= 0;
        
        forever begin
            seq_item_port.get_next_item(req);
            
            // --- 1. DRIVE REQUEST ---
            @(posedge vif.clk);
            // Chờ LSU sẵn sàng (IDLE)
            while (vif.ready_o !== 1) @(posedge vif.clk);

            vif.valid_i      <= 1;
            vif.addr_i       <= req.addr;
            vif.wdata_i      <= req.wdata;
            vif.lsu_we_i     <= req.we;
            vif.funct3_i     <= req.funct3;
            
            // Cung cấp dữ liệu giả lập cho DMEM (để Load path có cái mà đọc)
            vif.dmem_rdata_i <= req.mock_mem_data;

            // --- 2. HANDSHAKE DONE ---
            @(posedge vif.clk);
            vif.valid_i <= 0; // Xả valid
            
            // Chờ LSU trả kết quả (FSM: IDLE -> WAIT -> DONE)
            // Trong DUT: valid_o bật khi state == DONE
            while (vif.valid_o !== 1) @(posedge vif.clk);

            seq_item_port.item_done();
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 4. MONITOR
// -----------------------------------------------------------------------------
class lsu_monitor extends uvm_monitor;
    `uvm_component_utils(lsu_monitor)
    virtual lsu_if vif;
    uvm_analysis_port #(lsu_item) mon_ap;
    
    lsu_item pending_item;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon_ap = new("mon_ap", this);
        if(!uvm_config_db#(virtual lsu_if)::get(this, "", "vif", vif)) `uvm_fatal("MON", "No IF")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge vif.clk);
            #1;
            // 1. CAPTURE REQUEST & MEMORY SIGNALS (Khi Valid & Ready)
            // Đây là lúc duy nhất dmem_we/dmem_be bật lên
            if (vif.valid_i && vif.ready_o) begin
                pending_item = lsu_item::type_id::create("pkt");
                pending_item.addr          = vif.addr_i;
                pending_item.wdata         = vif.wdata_i;
                pending_item.we            = vif.lsu_we_i;
                pending_item.funct3        = vif.funct3_i;
                pending_item.mock_mem_data = vif.dmem_rdata_i;

                // Delay 1ns để chờ logic tổ hợp của DUT tính toán xong
                pending_item.actual_dmem_addr  = vif.dmem_addr_o;
                pending_item.actual_dmem_wdata = vif.dmem_wdata_o;
                pending_item.actual_dmem_be    = vif.dmem_be_o;
                pending_item.actual_dmem_we    = vif.dmem_we_o;
                // --------------------------------------------------
            end

            // 2. CAPTURE RESPONSE (Khi Valid Output)
            if (vif.valid_o) begin
                if (pending_item != null) begin
                    // Lúc này chỉ bắt kết quả trả về cho Core
                    pending_item.actual_rdata      = vif.lsu_rdata_o;
                    pending_item.actual_err        = vif.lsu_err_o;
                    
                    // Gửi trọn gói sang Scoreboard
                    mon_ap.write(pending_item);
                    pending_item = null; // Clear
                end
            end
        end
    endtask
endclass

// -----------------------------------------------------------------------------
// 5. SCOREBOARD
// -----------------------------------------------------------------------------
class lsu_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(lsu_scoreboard)
    uvm_analysis_imp #(lsu_item, lsu_scoreboard) sb_export;
    
    // --- STATISTICS ---
    int cnt_load       = 0;
    int cnt_store      = 0;
    int cnt_misaligned = 0;
    int cnt_byte       = 0;
    int cnt_half       = 0;
    int cnt_word       = 0;
    int cnt_pass       = 0;

    bit verbose = 0; 

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sb_export = new("sb_export", this);
        if ($test$plusargs("VERBOSE")) verbose = 1;
    endfunction

    // --- GOLDEN MODEL FUNCTIONS ---

    // 1. Check Misaligned
    function bit check_misaligned(logic [31:0] addr, logic [2:0] funct3);
        case (funct3)
            3'b010: return (addr[1:0] != 0);    // LW, SW (Align 4)
            3'b001, 3'b101: return (addr[0] != 0); // LH, LHU, SH (Align 2)
            default: return 0; // Byte is always aligned
        endcase
    endfunction

    // 2. Predict Load Data (Sign Extension Logic)
    function logic [31:0] predict_load(lsu_item pkt);
        logic [31:0] aligned_data;
        logic [1:0]  offset;
        offset = pkt.addr[1:0];
        
        // Dịch dữ liệu thô xuống bit 0 (Mô phỏng: raw >> offset*8)
        aligned_data = pkt.mock_mem_data >> (offset * 8);

        case (pkt.funct3)
            3'b000: return {{24{aligned_data[7]}}, aligned_data[7:0]};   // LB
            3'b100: return {24'b0, aligned_data[7:0]};                   // LBU
            3'b001: return {{16{aligned_data[15]}}, aligned_data[15:0]}; // LH
            3'b101: return {16'b0, aligned_data[15:0]};                  // LHU
            3'b010: return pkt.mock_mem_data;                            // LW
            default: return 0;
        endcase
    endfunction

    // 3. Predict Store (Data Shifting & BE)
    function void predict_store(lsu_item pkt, output logic [31:0] exp_wdata, output logic [3:0] exp_be);
        logic [1:0] offset = pkt.addr[1:0];
        
        exp_wdata = pkt.wdata << (offset * 8);
        
        case (pkt.funct3)
            3'b000: exp_be = 4'b0001 << offset; // SB
            3'b001: exp_be = 4'b0011 << offset; // SH
            3'b010: exp_be = 4'b1111;           // SW
            default: exp_be = 0;
        endcase
    endfunction

    // --- MAIN CHECK LOGIC ---
    function void write(lsu_item pkt);
        string msg;
        bit    expected_err;
        logic [31:0] expected_rdata;
        logic [31:0] expected_dmem_wdata;
        logic [3:0]  expected_dmem_be;

        // 1. Check Alignment
        expected_err = check_misaligned(pkt.addr, pkt.funct3);

        if (pkt.actual_err !== expected_err) begin
            `uvm_error("FAIL", $sformatf("Misaligned Check Fail! Addr:%h F3:%b ExpErr:%b ActErr:%b", 
                pkt.addr, pkt.funct3, expected_err, pkt.actual_err))
        end

        // 2. If Error -> Stop checking data
        if (expected_err) begin
            cnt_misaligned++;
            if (verbose) $display("[PASS] Misaligned Trap Caught: Addr %h", pkt.addr);
            return;
        end

        // 3. Check LOAD
        if (pkt.we == 0) begin
            expected_rdata = predict_load(pkt);
            if (pkt.actual_rdata !== expected_rdata) begin
                `uvm_error("FAIL", $sformatf("[LOAD] Data Mismatch! Addr:%h F3:%b Mem:%h Exp:%h Act:%h",
                    pkt.addr, pkt.funct3, pkt.mock_mem_data, expected_rdata, pkt.actual_rdata))
            end else if (verbose) begin
                $display("[PASS] LOAD Addr:%h | Type:%b | Val:%h", pkt.addr, pkt.funct3, pkt.actual_rdata);
            end
            cnt_load++;
        end 
        
        // 4. Check STORE
        else begin
            predict_store(pkt, expected_dmem_wdata, expected_dmem_be);
            
            if (pkt.actual_dmem_we !== 1) `uvm_error("FAIL", "[STORE] DMEM WE should be 1")
            
            if (pkt.actual_dmem_be !== expected_dmem_be) 
                `uvm_error("FAIL", $sformatf("[STORE] BE Mismatch! Addr:%h F3:%b ExpBE:%b ActBE:%b",
                    pkt.addr, pkt.funct3, expected_dmem_be, pkt.actual_dmem_be))
            
            if (pkt.actual_dmem_wdata !== expected_dmem_wdata)
                `uvm_error("FAIL", $sformatf("[STORE] WData Mismatch! Addr:%h Data:%h Exp:%h Act:%h",
                    pkt.addr, pkt.wdata, expected_dmem_wdata, pkt.actual_dmem_wdata))

            else if (verbose) begin
                $display("[PASS] STORE Addr:%h | Type:%b | BE:%b | Data:%h", pkt.addr, pkt.funct3, pkt.actual_dmem_be, pkt.actual_dmem_wdata);
            end
            cnt_store++;
        end

        // Stats
        case(pkt.funct3)
            3'b000, 3'b100: cnt_byte++;
            3'b001, 3'b101: cnt_half++;
            3'b010:         cnt_word++;
        endcase
        cnt_pass++;
    endfunction

    function void report_phase(uvm_phase phase);
        $display("\n==================================================");
        $display("           LSU VERIFICATION REPORT                ");
        $display("==================================================");
        $display("Total Transactions   : %0d", cnt_pass + cnt_misaligned);
        $display("Load Operations      : %0d", cnt_load);
        $display("Store Operations     : %0d", cnt_store);
        $display("Misaligned Traps     : %0d", cnt_misaligned);
        $display("--------------------------------------------------");
        $display("Byte Accesses (8-bit): %0d", cnt_byte);
        $display("Half Accesses (16b)  : %0d", cnt_half);
        $display("Word Accesses (32b)  : %0d", cnt_word);
        $display("==================================================\n");
    endfunction    
endclass

// -----------------------------------------------------------------------------
// 6. AGENT - ENV - TEST
// -----------------------------------------------------------------------------
class lsu_agent extends uvm_agent;
    `uvm_component_utils(lsu_agent)
    lsu_driver drv; lsu_monitor mon; uvm_sequencer #(lsu_item) sqr;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        drv = lsu_driver::type_id::create("drv", this);
        mon = lsu_monitor::type_id::create("mon", this);
        sqr = uvm_sequencer#(lsu_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(sqr.seq_item_export); endfunction
endclass

class lsu_env extends uvm_env;
    `uvm_component_utils(lsu_env)
    lsu_agent agent; lsu_scoreboard scb;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = lsu_agent::type_id::create("agent", this);
        scb   = lsu_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase); agent.mon.mon_ap.connect(scb.sb_export); endfunction
endclass

class lsu_test extends uvm_test;
    `uvm_component_utils(lsu_test)
    lsu_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); env = lsu_env::type_id::create("env", this); endfunction
    task run_phase(uvm_phase phase);
        lsu_random_seq seq = lsu_random_seq::type_id::create("seq");
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

    logic clk; always #5 clk = ~clk; 
    lsu_if vif(clk);
    
    // DUT Instantiation
    lsu dut (
        .clk_i       (vif.clk),
        .rst_i       (vif.rst_i),
        .addr_i      (vif.addr_i),
        .wdata_i     (vif.wdata_i),
        .lsu_we_i    (vif.lsu_we_i),
        .funct3_i    (vif.funct3_i),
        .valid_i     (vif.valid_i),
        .ready_o     (vif.ready_o),
        
        .valid_o     (vif.valid_o),
        .ready_i     (vif.ready_i),
        .lsu_rdata_o (vif.lsu_rdata_o),
        .lsu_err_o   (vif.lsu_err_o),
        
        .dmem_addr_o (vif.dmem_addr_o),
        .dmem_wdata_o(vif.dmem_wdata_o),
        .dmem_be_o   (vif.dmem_be_o),
        .dmem_we_o   (vif.dmem_we_o),
        .dmem_rdata_i(vif.dmem_rdata_i)
    );

    initial begin
        clk=0;
        uvm_config_db#(virtual lsu_if)::set(null, "*", "vif", vif);
        run_test("lsu_test");
    end
endmodule