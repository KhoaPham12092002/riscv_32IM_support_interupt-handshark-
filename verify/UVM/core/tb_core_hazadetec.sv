`timescale 1ns/1ps

// =============================================================================
// PACKAGE IMPORT & MACROS
// =============================================================================
import uvm_pkg::*;
`include "uvm_macros.svh"
import riscv_32im_pkg::*; 

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface riscv_core_if (input logic clk_i);
    logic        rst_i;
    // IMEM
    logic [31:0] imem_addr_o;
    logic        imem_valid_o;
    logic        imem_ready_i;
    logic [31:0] imem_instr_i;
    logic        imem_valid_i;
    logic        imem_ready_o;
    // DMEM
    logic [31:0] dmem_addr_o;
    logic [31:0] dmem_wdata_o;
    logic [3:0]  dmem_be_o;
    logic        dmem_we_o;
    logic        dmem_valid_o;
    logic        dmem_ready_i;
    logic [31:0] dmem_rdata_i;
    logic        dmem_valid_i;
    logic        dmem_ready_o;
endinterface

// =============================================================================
// 2. SEQUENCE ITEM
// =============================================================================
class riscv_core_item extends uvm_sequence_item;
    // Control bit: 1 = Nạp code vào Memory ảo, 0 = Chạy mô phỏng
    bit is_load_mode; 
    logic [31:0] load_addr;
    logic [31:0] load_instr;

    // Stress Params: Random delay trả về của Memory
    rand int imem_delay; 
    rand int dmem_delay;

    constraint c_delay { 
        imem_delay inside {[0:2]}; // Ép Pipeline phải chờ đợi (Elastic)
        dmem_delay inside {[0:2]}; 
    }

    `uvm_object_utils_begin(riscv_core_item)
        `uvm_field_int(is_load_mode, UVM_DEFAULT)
        `uvm_field_int(load_addr,    UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(load_instr,   UVM_DEFAULT | UVM_HEX)
        `uvm_field_int(imem_delay,   UVM_DEFAULT | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "riscv_core_item"); super.new(name); endfunction
endclass

// =============================================================================
// 3. DRIVER (MEMORY SIMULATOR)
// =============================================================================
class riscv_core_driver extends uvm_driver #(riscv_core_item);
    `uvm_component_utils(riscv_core_driver)
    virtual riscv_core_if vif;

    logic [31:0] fake_imem [0:8191]; // 32KB Instruction Memory
    logic [31:0] fake_dmem [0:1023]; // 4KB Data Memory

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        // Init Memory = NOP
        for(int i=0; i<8192; i++) fake_imem[i] = 32'h0000_0013; 
        for(int i=0; i<1024; i++) fake_dmem[i] = 32'h0000_0000;

        if (!uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "FATAL: Interface Missing")
    endfunction

    int current_imem_delay = 0;
    int current_dmem_delay = 0;

    task run_phase(uvm_phase phase);
        vif.imem_ready_i <= 0; vif.imem_valid_i <= 0; vif.imem_instr_i <= 0;
        vif.dmem_ready_i <= 0; vif.dmem_valid_i <= 0; vif.dmem_rdata_i <= 0;
        vif.rst_i <= 1;

        fork
            sequence_loader();
            imem_responder();
            dmem_responder();
        join_none
    endtask

    task sequence_loader();
        forever begin
            seq_item_port.get_next_item(req);
            
            if (req.is_load_mode) begin
                // Mode 1: Backdoor Load
                fake_imem[req.load_addr[14:2]] = req.load_instr;
            end 
            else begin
                // Mode 0: Run CPU
                if (vif.rst_i) vif.rst_i <= 0; // Thả Reset
                current_imem_delay = req.imem_delay;
                current_dmem_delay = req.dmem_delay;
                @(posedge vif.clk_i);
            end
            seq_item_port.item_done();
        end
    endtask

    task imem_responder();
        bit rsp_pending = 0;
        vif.imem_ready_i <= 1; // Always ready to accept
        forever begin
            @(posedge vif.clk_i);
            
            if (rsp_pending && vif.imem_ready_o) begin
                vif.imem_valid_i <= 0;
                rsp_pending = 0;
                vif.imem_ready_i <= 1;
            end
            
            if (vif.imem_valid_o && vif.imem_ready_i && !rsp_pending) begin
                logic [31:0] addr = vif.imem_addr_o;
                vif.imem_ready_i <= 0; // Hold new requests
                
                for (int i=0; i<current_imem_delay; i++) @(posedge vif.clk_i);

                vif.imem_valid_i <= 1;
                vif.imem_instr_i <= (addr[14:2] < 8192) ? fake_imem[addr[14:2]] : 32'h00000013;
                rsp_pending = 1;
            end
        end
    endtask

    task dmem_responder();
        bit rsp_pending = 0;
        vif.dmem_ready_i <= 1;
        forever begin
            @(posedge vif.clk_i);
            
            if (rsp_pending && vif.dmem_ready_o) begin
                vif.dmem_valid_i <= 0;
                rsp_pending = 0;
                vif.dmem_ready_i <= 1;
            end
            
            if (vif.dmem_valid_o && vif.dmem_ready_i && !rsp_pending) begin
                logic [31:0] addr = vif.dmem_addr_o;
                logic we = vif.dmem_we_o;
                logic [31:0] wdata = vif.dmem_wdata_o;
                
                vif.dmem_ready_i <= 0;
                
                if (we) fake_dmem[addr[11:2]] = wdata;

                for (int i=0; i<current_dmem_delay; i++) @(posedge vif.clk_i);

                if (!we) begin
                    vif.dmem_rdata_i <= fake_dmem[addr[11:2]];
                end
                
                vif.dmem_valid_i <= 1;
                rsp_pending = 1;
            end
        end
    endtask
endclass

// =============================================================================
// 4. SEQUENCE: SELF-CHECKING HAZARD STRESS
// =============================================================================
class riscv_hazard_stress_seq extends uvm_sequence #(riscv_core_item);
    `uvm_object_utils(riscv_hazard_stress_seq)
    function new(string name = ""); super.new(name); endfunction

    // --- RISC-V Instruction Encoders ---
    function logic [31:0] enc_i(bit [4:0] rd, rs1, bit [11:0] imm, bit [2:0] f3, bit [6:0] op);
        return {imm, rs1, f3, rd, op};
    endfunction
    function logic [31:0] enc_r(bit [4:0] rd, rs1, rs2, bit [2:0] f3, bit [6:0] f7);
        return {f7, rs2, rs1, f3, rd, 7'b0110011};
    endfunction
    function logic [31:0] enc_s(bit [4:0] rs1, rs2, bit [11:0] imm);
        return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function logic [31:0] enc_b(bit [4:0] rs1, rs2, bit [12:0] imm, bit [2:0] f3);
        return {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
    endfunction
    function logic [31:0] enc_lui(bit [4:0] rd, bit [19:0] imm20);
        return {imm20, rd, 7'b0110111};
    endfunction

    logic [31:0] cur_pc = 0;

    task send_instr(logic [31:0] instr);
        riscv_core_item r;
        r = riscv_core_item::type_id::create("req");
        start_item(r);
        r.is_load_mode = 1; r.load_addr = cur_pc; r.load_instr = instr;
        finish_item(r);
        cur_pc += 4;
    endtask

    // Load bất kỳ giá trị 32-bit vào rd (LUI+ADDI khi cần)
    task load_const(bit [4:0] rd, bit [31:0] val);
        bit [11:0] lo12 = val[11:0];
        bit [19:0] hi20 = val[31:12] + (lo12[11] ? 20'd1 : 20'd0);
        if (hi20 != 0) begin
            send_instr(enc_lui(rd, hi20));
            send_instr(enc_i(rd, rd, lo12, 3'b000, 7'b0010011));
        end else
            send_instr(enc_i(rd, 5'd0, lo12, 3'b000, 7'b0010011));
    endtask

    // Kiểm tra reg_idx == expected. FAIL -> SW x0,0(x0) -> fatal monitor
    // BEQ offset=+8: nhảy đúng 1 instruction phía trước (qua SW)
    task check_result(bit [4:0] reg_idx, bit [31:0] expected_val);
        load_const(5'd30, expected_val);
        send_instr(enc_b(reg_idx, 5'd30, 13'd8, 3'b000)); // BEQ reg,x30,+8
        send_instr(enc_s(5'd0, 5'd0, 12'd0));              // FAIL: SW x0,0(x0)
    endtask

    task body();
        int i, scenario;
        bit [4:0] r1, r2, r3, r_dst;
        bit [31:0] val1, val2, val3;

        $display("[SEQ] Generating HARDCORE HAZARD Program (2000 iter)...");

        // ----------------------------------------------------------
        // WARMUP: x0 luon = 0, pipeline sach
        // ----------------------------------------------------------
        send_instr(enc_i(5'd1, 5'd0, 12'd42, 3'b000, 7'b0010011)); // x1=42
        send_instr(enc_r(5'd2, 5'd0, 5'd1, 3'b000, 7'b0100000));   // x2=x0-x1=-42
        send_instr(enc_r(5'd3, 5'd1, 5'd2, 3'b000, 7'b0000000));   // x3=x1+x2=0
        check_result(5'd3, 32'd0);

        // ----------------------------------------------------------
        // MAIN LOOP — 7 scenarios
        // ----------------------------------------------------------
        for (i = 0; i < 2000; i++) begin
            r1    = $urandom_range(1, 6);
            r2    = $urandom_range(1, 6);
            r3    = $urandom_range(1, 6);
            r_dst = $urandom_range(7, 13);
            val1  = $urandom_range(1, 60);
            val2  = $urandom_range(1, 60);
            val3  = $urandom_range(1, 60);
            scenario = $urandom_range(0, 6);

            case (scenario)
                // SC0: EX->EX Forwarding RS1 (RAW gap=0)
                0: begin
                    send_instr(enc_i(r1,    5'd0, val1[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_i(r_dst, r1,   val2[11:0], 3'b000, 7'b0010011));
                    check_result(r_dst, val1 + val2);
                end

                // SC1: Load-Use Stall (bắt buộc stall 1 cycle)
                1: begin
                    send_instr(enc_i(5'd15, 5'd0, val1[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_s(5'd0, 5'd15, 12'h080));
                    send_instr(enc_i(r1, 5'd0, 12'h080, 3'b010, 7'b0000011));
                    send_instr(enc_r(r_dst, r1, r1, 3'b000, 7'b0000000));
                    check_result(r_dst, val1 * 2);
                end

                // SC2: WB->EX Forwarding (gap=1)
                2: begin
                    send_instr(enc_i(r1,    5'd0, val1[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_i(r2,    5'd0, val2[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_r(r_dst, r1,   r2, 3'b000, 7'b0000000));
                    check_result(r_dst, val1 + val2);
                end

                // SC3: Dual Forward (RS1 tu MEM, RS2 tu EX cung luc)
                3: begin
                    send_instr(enc_i(r1,    5'd0, val1[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_i(r2,    5'd0, val2[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_r(r_dst, r1,   r2, 3'b000, 7'b0000000));
                    check_result(r_dst, val1 + val2);
                end

                // SC4: 3-deep RAW chain (EX->EX lien tiep)
                4: begin
                    send_instr(enc_i(r1,    5'd0, val1[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_i(r2,    r1,   val2[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_i(r_dst, r2,   val3[11:0], 3'b000, 7'b0010011));
                    check_result(r_dst, val1 + val2 + val3);
                end

                // SC5: Store -> Load consistency
                5: begin
                    send_instr(enc_i(r1, 5'd0, val1[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_s(5'd0, r1, 12'h090));
                    send_instr(enc_i(5'd0, 5'd0, 12'd0, 3'b000, 7'b0010011)); // NOP
                    send_instr(enc_i(r_dst, 5'd0, 12'h090, 3'b010, 7'b0000011));
                    check_result(r_dst, val1);
                end

                // SC6: EX->EX tren RS2 slot (ADD r_dst, r2, r2)
                6: begin
                    send_instr(enc_i(r2,    5'd0, val2[11:0], 3'b000, 7'b0010011));
                    send_instr(enc_r(r_dst, r2,   r2, 3'b000, 7'b0000000));
                    check_result(r_dst, val2 * 2);
                end
            endcase
        end

        // ----------------------------------------------------------
        // CORNER CASES co dinh
        // ----------------------------------------------------------
        // CC1: forward gia tri 0
        send_instr(enc_i(5'd1, 5'd0, 12'd0, 3'b000, 7'b0010011));
        send_instr(enc_i(5'd2, 5'd1, 12'd7, 3'b000, 7'b0010011));
        check_result(5'd2, 32'd7);

        // CC2: Hai load-use lien tiep
        send_instr(enc_i(5'd15, 5'd0, 12'd9,  3'b000, 7'b0010011));
        send_instr(enc_s(5'd0, 5'd15, 12'h0A0));
        send_instr(enc_i(5'd16, 5'd0, 12'd4,  3'b000, 7'b0010011));
        send_instr(enc_s(5'd0, 5'd16, 12'h0A4));
        send_instr(enc_i(5'd1, 5'd0, 12'h0A0, 3'b010, 7'b0000011));
        send_instr(enc_r(5'd3, 5'd1, 5'd1, 3'b000, 7'b0000000)); // x3=9+9=18
        send_instr(enc_i(5'd2, 5'd0, 12'h0A4, 3'b010, 7'b0000011));
        send_instr(enc_r(5'd4, 5'd2, 5'd3, 3'b000, 7'b0000000)); // x4=4+18=22
        check_result(5'd4, 32'd22);

        // CC3: 4-deep chain
        send_instr(enc_i(5'd1, 5'd0, 12'd1, 3'b000, 7'b0010011));
        send_instr(enc_i(5'd2, 5'd1, 12'd1, 3'b000, 7'b0010011));
        send_instr(enc_i(5'd3, 5'd2, 12'd1, 3'b000, 7'b0010011));
        send_instr(enc_i(5'd4, 5'd3, 12'd1, 3'b000, 7'b0010011));
        check_result(5'd4, 32'd4);

        send_instr(32'h0000006f); // JAL x0, 0

        // ----------------------------------------------------------
        // RUN SIMULATION — delay 0-3 (stress back-pressure)
        // ----------------------------------------------------------
        $display("[SEQ] Running simulation (20000 cycles, delay 0-3)...");
        repeat(20000) begin
            riscv_core_item r;
            r = riscv_core_item::type_id::create("req");
            start_item(r);
            r.is_load_mode = 0;
            r.imem_delay   = $urandom_range(0, 3);
            r.dmem_delay   = $urandom_range(0, 3);
            finish_item(r);
        end
        $display("[SEQ] Done.");
    endtask
endclass

// =============================================================================
// 5. MONITOR & SCOREBOARD (REQUIRED BY UVM)
// =============================================================================
class riscv_core_monitor extends uvm_monitor;
    `uvm_component_utils(riscv_core_monitor)
    virtual riscv_core_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase); super.build_phase(phase); uvm_config_db#(virtual riscv_core_if)::get(this, "", "vif", vif); endfunction
    task run_phase(uvm_phase phase); endtask // Passive
endclass

class riscv_core_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(riscv_core_scoreboard)

    int unsigned n_pass;   // Số scenario chạy qua không lỗi
    int unsigned n_fail;   // Số lỗi UVM_ERROR/FATAL tích lũy
    time         t_start;  // Thời điểm bắt đầu run

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    // ------------------------------------------------------------------
    // start_of_simulation: ghi nhận mốc thời gian
    // ------------------------------------------------------------------
    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        t_start = $time;
        $display("[SCB] start_of_simulation: Scoreboard ready");
    endfunction

    // ------------------------------------------------------------------
    // run_phase: passive — không raise objection
    // ------------------------------------------------------------------
    task run_phase(uvm_phase phase);
        $display("[SCB] run_phase: Scoreboard listening...");
    endtask

    // ------------------------------------------------------------------
    // extract_phase: thu thập số lỗi từ UVM report server
    // ------------------------------------------------------------------
    function void extract_phase(uvm_phase phase);
        super.extract_phase(phase);
        n_fail = uvm_report_server::get_server().get_severity_count(UVM_ERROR)
               + uvm_report_server::get_server().get_severity_count(UVM_FATAL);
        $display("[SCB] extract_phase: Errors/Fatals = %0d", n_fail);
    endfunction

    // ------------------------------------------------------------------
    // report_phase: in banner PASS / FAIL
    // ------------------------------------------------------------------
    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        $display("");
        $display("=====================================================");
        $display("  [SCB] Sim duration : %0t", $time - t_start);
        if (n_fail == 0)
            $display("  [SCB] RESULT *** SCOREBOARD PASS *** No hazard errors!");
        else
            $display("  [SCB] RESULT *** SCOREBOARD FAIL *** %0d error(s)!", n_fail);
        $display("=====================================================");
        $display("");
    endfunction

endclass

// =============================================================================
// 6. AGENT & ENV & TEST
// =============================================================================
class riscv_core_agent extends uvm_agent;
    `uvm_component_utils(riscv_core_agent)
    riscv_core_driver driver; uvm_sequencer #(riscv_core_item) sequencer; riscv_core_monitor monitor;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = riscv_core_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(riscv_core_item)::type_id::create("sequencer", this);
        monitor = riscv_core_monitor::type_id::create("monitor", this);
    endfunction
    function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); endfunction
endclass

class riscv_core_env extends uvm_env;
    `uvm_component_utils(riscv_core_env)
    riscv_core_agent agent; riscv_core_scoreboard scb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = riscv_core_agent::type_id::create("agent", this);
        scb = riscv_core_scoreboard::type_id::create("scb", this);
    endfunction
endclass

class riscv_hazard_test extends uvm_test;
    `uvm_component_utils(riscv_hazard_test)
    riscv_core_env env;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = riscv_core_env::type_id::create("env", this);
        $display("[TEST] build_phase: env created");
    endfunction

    function void end_of_elaboration_phase(uvm_phase phase);
        super.end_of_elaboration_phase(phase);
        $display("[TEST] elab_phase : UVM hierarchy elaborated");
    endfunction

    function void start_of_simulation_phase(uvm_phase phase);
        super.start_of_simulation_phase(phase);
        $display("");
        $display("=====================================================");
        $display("  TEST : riscv_hazard_test");
        $display("  SCOPE: Forwarding (EX-EX) + Load-Use Stall");
        $display("=====================================================");
        $display("");
    endfunction

    task run_phase(uvm_phase phase);
        riscv_hazard_stress_seq seq;
        seq = riscv_hazard_stress_seq::type_id::create("seq");
        $display("[TEST] run_phase : START — sequence launching");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
        $display("[TEST] run_phase : DONE — objection dropped");
    endtask
    // NOTE: extract_phase & report_phase nam trong riscv_core_scoreboard
endclass

// =============================================================================
// 7. TOP MODULE (SNOOPING FOR ERROR TRAP)
// =============================================================================
module tb_top;
    import uvm_pkg::*;
    bit clk; always #5 clk = ~clk; 
    riscv_core_if vif(clk);

    riscv_core dut (
        .clk_i(clk), .rst_i(vif.rst_i),
        .imem_addr_o(vif.imem_addr_o), .imem_valid_o(vif.imem_valid_o), .imem_ready_i(vif.imem_ready_i),
        .imem_instr_i(vif.imem_instr_i), .imem_valid_i(vif.imem_valid_i), .imem_ready_o(vif.imem_ready_o),
        .dmem_addr_o(vif.dmem_addr_o), .dmem_wdata_o(vif.dmem_wdata_o), .dmem_be_o(vif.dmem_be_o),
        .dmem_we_o(vif.dmem_we_o), .dmem_valid_o(vif.dmem_valid_o), .dmem_ready_i(vif.dmem_ready_i),
        .dmem_rdata_i(vif.dmem_rdata_i), .dmem_valid_i(vif.dmem_valid_i), .dmem_ready_o(vif.dmem_ready_o)
    );

    initial begin
        uvm_config_db#(virtual riscv_core_if)::set(null, "*", "vif", vif);
        run_test("riscv_hazard_test"); 
    end

    // --- FINAL SIMULATION SUMMARY ---
    final begin
        $display("");
        $display("=====================================================");
        $display("  SIMULATION ENDED at time %0t", $time);
        $display("  UVM Errors  : %0d",
            uvm_report_server::get_server().get_severity_count(UVM_ERROR));
        $display("  UVM Fatals  : %0d",
            uvm_report_server::get_server().get_severity_count(UVM_FATAL));
        $display("=====================================================");
        $display("");
    end

    // --- FATAL ERROR DETECTION (TRAP MONITOR) ---
    always @(posedge clk) begin
        // Nếu CPU ghi vào địa chỉ 0x00000000 -> Có nghĩa là Branch Check bị SAI -> Hazard Lỗi!
        if (vif.dmem_valid_o && vif.dmem_we_o && vif.dmem_addr_o == 0) begin
            $display("\n[!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!]");
            $display("[FATAL] CPU CALCULATION ERROR DETECTED at Time %0t", $time);
            $display("[FATAL] A Hazard (Forwarding/Stall) was MISSED.");
            $display("[!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!]\n");
            $stop;
        end
        
        // Debug: Báo Stall
        if (dut.u_control.u_hazard.ctrl_force_stall_id_o)
            $display("[INFO] %0t: Stall Active (Load-Use Detected) at PC=%h", $time, dut.imem_addr_o);
    end
endmodule