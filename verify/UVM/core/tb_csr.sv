// =============================================================================
// FILE: tb_csr.sv
// DESCRIPTION: UVM Unit Testbench for RISC-V CSR Module
// =============================================================================
`timescale 1ns/1ps

import uvm_pkg::*;
// Đảm bảo cậu đã compile package chứa csr_req_t và các enum op
import riscv_32im_pkg::*; 
import riscv_instr::*;

`include "uvm_macros.svh"

// =============================================================================
// 1. INTERFACE
// =============================================================================
interface csr_if (input logic clk_i, input logic rst_i);
    // --- Core Access ---
    csr_req_t    req;
    logic        ready;
    logic [31:0] rdata;
    logic        rsp_valid;

    // --- Trap/MRET ---
    logic        trap_valid;
    logic [3:0]  trap_cause;
    logic [31:0] trap_pc;
    logic [31:0] trap_val;
    logic        mret;

    // --- Outputs to PC ---
    logic [31:0] epc;
    logic [31:0] trap_vector;

    // --- Interrupts ---
    logic        irq_sw;
    logic        irq_timer;
    logic        irq_ext;
endinterface

// =============================================================================
// 2. TRANSACTION ITEM
// =============================================================================
class csr_item extends uvm_sequence_item;
    // Phân loại action
    typedef enum {ACT_CSR_RW, ACT_TRAP, ACT_MRET, ACT_IDLE} action_e;
    
    rand action_e     action;
    
    // Payload cho CSR RW
    rand logic [11:0] csr_addr;
    rand logic [31:0] wdata;
    rand csr_op_e  csr_op;
    
    // Payload cho Trap
    rand logic [3:0]  trap_cause;
    rand logic [31:0] trap_pc;

    `uvm_object_utils_begin(csr_item)
        `uvm_field_enum(action_e, action, UVM_ALL_ON)
        `uvm_field_int(csr_addr, UVM_HEX)
        `uvm_field_int(wdata, UVM_HEX)
        `uvm_field_int(trap_cause, UVM_HEX)
        `uvm_field_int(trap_pc, UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "csr_item"); super.new(name); endfunction
endclass

// =============================================================================
// 3. DRIVER
// =============================================================================
class csr_driver extends uvm_driver #(csr_item);
    `uvm_component_utils(csr_driver)
    virtual csr_if vif;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual csr_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Interface not found!")
    endfunction 

    task run_phase(uvm_phase phase);
        // Reset initialization
        vif.req.valid  <= 0;
        vif.trap_valid <= 0;
        vif.mret       <= 0;
        vif.irq_sw <= 0; vif.irq_timer <= 0; vif.irq_ext <= 0;

        // [SỬA Ở ĐÂY 1] Đợi Reset xả hoàn toàn (rst_i xuống 0)
        wait(vif.rst_i == 1'b0); 
        @(posedge vif.clk_i); // Đợi thêm 1 nhịp Clock cho an toàn

        forever begin
            seq_item_port.get_next_item(req);
            
            vif.req.valid  <= 0;
            vif.trap_valid <= 0;
            vif.mret       <= 0;

            case (req.action)
                csr_item::ACT_CSR_RW: begin
                    vif.req.valid  <= 1;
                    vif.req.addr   <= req.csr_addr;
                    vif.req.wdata  <= req.wdata;
                    vif.req.op     <= req.csr_op;
                    
                    // [SỬA Ở ĐÂY 2] Vòng lặp chờ Handshake chuẩn đồng bộ
                    do begin
                        @(posedge vif.clk_i);
                    end while (vif.ready !== 1'b1);
                    
                    vif.req.valid  <= 0; // Kéo valid xuống sau khi đã bắt tay xong
                end
                
                csr_item::ACT_TRAP: begin
                    vif.trap_valid <= 1;
                    vif.trap_cause <= req.trap_cause;
                    vif.trap_pc    <= req.trap_pc;
                    @(posedge vif.clk_i);
                    vif.trap_valid <= 0;
                end
                
                csr_item::ACT_MRET: begin
                    vif.mret <= 1;
                    @(posedge vif.clk_i);
                    vif.mret <= 0;
                end
                
                csr_item::ACT_IDLE: begin
                    @(posedge vif.clk_i);
                end
            endcase
            
            seq_item_port.item_done();
        end
    endtask
endclass

// =============================================================================
// 4. SEQUENCES (DIRECTED SCENARIOS)
// =============================================================================
class csr_stress_seq extends uvm_sequence #(csr_item);
    `uvm_object_utils(csr_stress_seq)
    function new(string name=""); super.new(name); endfunction

    // Hàm tạo Item không dùng Constraint (Chống nghèo License)
    function csr_item gen_dice_item();
        csr_item itm = csr_item::type_id::create("itm");
        int dice = $urandom_range(0, 99); // Dice từ 0 đến 99

        if (dice < 60) begin
            // 60% Tỉ lệ: Thực hiện đọc/ghi các thanh ghi cơ bản
            itm.action = csr_item::ACT_CSR_RW;
            itm.wdata  = $urandom;
            
            // Tung xí ngầu chọn địa chỉ
            case ($urandom_range(0, 2))
                0: itm.csr_addr = 12'h305; // mtvec
                1: itm.csr_addr = 12'h341; // mepc
                2: itm.csr_addr = 12'h342; // mcause
            endcase
            
            // Tung xí ngầu chọn lệnh đọc hay ghi
           itm.csr_op = csr_op_e'($urandom_range(1, 3));
            //itm.csr_op   = CSR_RS; // Chỉ test ghi để dễ theo dõi, đọc sẽ được Scoreboard check sau

        end else if (dice < 85) begin
            // 25% Tỉ lệ: Nhảy vào Trap
            itm.action     = csr_item::ACT_TRAP;
            itm.trap_cause = $urandom_range(0, 15);
            itm.trap_pc    = $urandom;
            
        end else if (dice < 95) begin
            // 10% Tỉ lệ: Thoát ngắt
            itm.action = csr_item::ACT_MRET;
            
        end else begin
            // 5% Tỉ lệ: Nghỉ ngơi 1 nhịp (Idle)
            itm.action = csr_item::ACT_IDLE;
        end
        
        return itm;
    endfunction

    task body();
        csr_item req;
        
        `uvm_info("SEQ", "STARTING 50,000 CSR STRESS TEST (DICE METHOD)...", UVM_LOW)
        
        for (int i = 0; i < 50000; i++) begin
            req = gen_dice_item();
            start_item(req);
            finish_item(req);
            
            // Ép đọc lại mcause ngay sau khi có Trap để kiểm tra Scoreboard
            if (req.action == csr_item::ACT_TRAP) begin
                csr_item check_req = csr_item::type_id::create("check_req");
                check_req.action   = csr_item::ACT_CSR_RW;
                check_req.csr_addr = 12'h342; // mcause
                check_req.csr_op   = CSR_RS;  // Read Only
                
                // [THÊM DÒNG NÀY ĐỂ GIẾT BÓNG MA "X"]
                check_req.wdata    = 32'b0;   
                
                start_item(check_req);
                finish_item(check_req);
            end
        end
        
        `uvm_info("SEQ", "STRESS TEST COMPLETED.", UVM_LOW)
    endtask
endclass
// =============================================================================
// 5. SCOREBOARD 
// =============================================================================
class csr_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(csr_scoreboard)
    virtual csr_if vif;

    bit enable_uvm_log = 1;
    bit enable_debug_dump = 1; // debug print all pin to console

    // --- Biến đếm thống kê (Report) ---
    int total_rw      = 0;
    int total_trap    = 0;
    int total_mret    = 0;
    int err_count     = 0;

    // --- Két sắt ảo (Reference Model) ---
    logic [31:0] ref_mtvec  = 0;
    logic [31:0] ref_mepc   = 0;
    logic [31:0] ref_mcause = 0;

    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual csr_if)::get(this, "", "vif", vif))
            `uvm_fatal("SCB", "Interface not found!")
        
        void'($value$plusargs("UVM_LOG_EN=%d", enable_uvm_log));
        void'($value$plusargs("UVM_DEBUG_DUMP=%d", enable_debug_dump));
    endfunction
    
    function void dump_all_pins(string msg);
        $display("\n------------------- [DEBUG PIN DUMP] -------------------");
        $display(" TIME: %0t ns | %s", $time, msg);
        $display(" [CORE ACCESS] Valid:%b | Addr:%h | WData:%h | Op:%b | Ready:%b", 
                  vif.req.valid, vif.req.addr, vif.req.wdata, vif.req.op, vif.ready);
        $display(" [DATA OUT   ] RData:%h | RspValid:%b", vif.rdata, vif.rsp_valid);
        $display(" [TRAP/MRET  ] TrapValid:%b | Cause:%h | TrapPC:%h | MRET:%b", 
                  vif.trap_valid, vif.trap_cause, vif.trap_pc, vif.mret);
        $display(" [ARCH STATE ] EPC:%h | TrapVec:%h", vif.epc, vif.trap_vector);
        $display(" [INTERRUPTS ] SW:%b | Timer:%b | Ext:%b", vif.irq_sw, vif.irq_timer, vif.irq_ext);
        $display("--------------------------------------------------------\n");
    endfunction
 logic [31:0] expected_rdata;
task run_phase(uvm_phase phase);
        // [TUYỆT CHIÊU] Đưa khai báo lên trên cùng của task để triệt tiêu lỗi Syntax 100%
        logic [31:0] expected_rdata; 
        
        @(negedge vif.rst_i);
        forever begin
            @(posedge vif.clk_i);
            
            // 1. KHI CÓ LỆNH CORE TRUY CẬP HỢP LỆ
            if (vif.req.valid && vif.ready) begin
                
                total_rw++;
                
                // Bước A: Kiểm tra Dữ liệu ĐỌC RA (rdata) có khớp với Két sắt ảo không
                // [NÂNG CẤP] Dùng Macro địa chỉ chuẩn như cậu gợi ý
                case (vif.req.addr)
                    CSR_MTVEC:  expected_rdata = ref_mtvec;
                    CSR_MEPC:   expected_rdata = ref_mepc;
                    CSR_MCAUSE: expected_rdata = ref_mcause;
                    default:    expected_rdata = vif.rdata; // Bỏ qua thanh ghi lạ
                endcase
                
                if (vif.rdata !== expected_rdata) begin
                    err_count++;
                    if (enable_uvm_log) 
                        `uvm_error("SCB_FAIL", $sformatf("Addr %3x: Exp %08x, Got %08x", vif.req.addr, expected_rdata, vif.rdata))
                    else 
                        $display("[%0t ns] [SCB_FAIL] Addr %3x: Exp %08x, Got %08x", $time, vif.req.addr, expected_rdata, vif.rdata);
                        
                    if (enable_debug_dump) dump_all_pins("Data Mismatch!");
                end

                // Bước B: CẬP NHẬT Két sắt ảo dựa trên Lệnh
                if (vif.req.op == CSR_RW) begin
                    case (vif.req.addr)
                        CSR_MTVEC:  ref_mtvec  = vif.req.wdata;
                        CSR_MEPC:   ref_mepc   = vif.req.wdata;
                        CSR_MCAUSE: ref_mcause = vif.req.wdata;
                    endcase
                end 
                else if (vif.req.op == CSR_RS) begin
                    case (vif.req.addr)
                        CSR_MTVEC:  ref_mtvec  = ref_mtvec  | vif.req.wdata;
                        CSR_MEPC:   ref_mepc   = ref_mepc   | vif.req.wdata;
                        CSR_MCAUSE: ref_mcause = ref_mcause | vif.req.wdata;
                    endcase
                end 
                else if (vif.req.op == CSR_RC) begin
                    case (vif.req.addr)
                        CSR_MTVEC:  ref_mtvec  = ref_mtvec  & ~vif.req.wdata;
                        CSR_MEPC:   ref_mepc   = ref_mepc   & ~vif.req.wdata;
                        CSR_MCAUSE: ref_mcause = ref_mcause & ~vif.req.wdata;
                    endcase
                end
            end

            // 2. KHI CÓ TRAP (Ngắt)
            if (vif.trap_valid) begin
                total_trap++;
                // Cập nhật Két sắt ảo y hệt phần cứng
                ref_mepc   = vif.trap_pc;
                ref_mcause = {28'b0, vif.trap_cause};
            end

            if (vif.mret) begin
                total_mret++;
            end
        end
    endtask
    

    function void report_phase(uvm_phase phase);
        $display("\n==========================================================");
        $display("                 CSR SCOREBOARD REPORT                    ");
        $display("==========================================================");
        $display(" Total Read/Write Cmds : %0d", total_rw);
        $display(" Total Traps Handled   : %0d", total_trap);
        $display(" Total MRETs Executed  : %0d", total_mret);
        $display(" Total                 : %0d", total_rw + total_trap + total_mret);
        $display("----------------------------------------------------------");
        if (err_count == 0)
            $display(" RESULT: PASSED (0 Errors found)");
        else
            $display(" RESULT: FAILED (%0d Errors found)", err_count);
        $display("==========================================================\n");
    endfunction
endclass
// =============================================================================
// 6. AGENT, ENV, TEST
// =============================================================================
class csr_agent extends uvm_agent;
    `uvm_component_utils(csr_agent)
    csr_driver driver;
    uvm_sequencer #(csr_item) sequencer;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase); 
        super.build_phase(phase);
        driver = csr_driver::type_id::create("driver", this);
        sequencer = uvm_sequencer#(csr_item)::type_id::create("sequencer", this);
    endfunction
    function void connect_phase(uvm_phase phase); 
        driver.seq_item_port.connect(sequencer.seq_item_export); 
    endfunction
endclass

class csr_env extends uvm_env;
    `uvm_component_utils(csr_env)
    csr_agent agent;
    csr_scoreboard scoreboard;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = csr_agent::type_id::create("agent", this);
        scoreboard = csr_scoreboard::type_id::create("scoreboard", this);
    endfunction
endclass

class csr_test extends uvm_test;
    `uvm_component_utils(csr_test)
    csr_env env;
    function new(string name, uvm_component p); super.new(name, p); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = csr_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        csr_stress_seq seq = csr_stress_seq::type_id::create("seq");
        phase.raise_objection(this);
        seq.start(env.agent.sequencer);
        #50ns; // Đợi xem kết quả
        phase.drop_objection(this);
    endtask
endclass

// =============================================================================
// 6. SVA (SYSTEMVERILOG ASSERTIONS)
// =============================================================================
module csr_sva_checker (
    input logic clk,
    input logic rst, // Giả sử rst_i là active-high
    input logic trap_valid,
    input logic mret,
    input logic [31:0] epc,
    input logic [31:0] trap_pc
);
    // Bắt buộc: Không được kích hoạt MRET và TRAP cùng một lúc
    property p_no_trap_mret_collision;
        @(posedge clk) disable iff (rst)
        !(trap_valid && mret);
    endproperty
    A_COLLISION: assert property(p_no_trap_mret_collision) 
        else $error("[SVA] Trap and MRET asserted simultaneously!");

    // Khi có Trap, EPC (mepc) phải được cập nhật bằng trap_pc ở nhịp sau
    property p_trap_updates_mepc;
        @(posedge clk) disable iff (rst)
        trap_valid |=> (epc == $past(trap_pc));
    endproperty
    A_TRAP_EPC: assert property(p_trap_updates_mepc) 
        else $warning("[SVA] EPC was not updated with Trap PC. (Check if this is intentional behavior in your design)");
endmodule

// =============================================================================
// 7. TOP MODULE
// =============================================================================
module tb_csr_top;
    logic clk;
    logic rst_i;

    always #5 clk = ~clk;

    csr_if vif(clk, rst_i);

    // DUT
    csr dut (
        .clk_i           (clk),
        .rst_i           (rst_i),
        .csr_req_i       (vif.req),
        .csr_ready_o     (vif.ready),
        .csr_rdata_o     (vif.rdata),
        .csr_rsp_valid_o (vif.rsp_valid),
        .trap_valid_i    (vif.trap_valid),
        .trap_cause_i    (vif.trap_cause),
        .trap_pc_i       (vif.trap_pc),
        .trap_val_i      (vif.trap_val),
        .mret_i          (vif.mret),
        .epc_o           (vif.epc),
        .trap_vector_o   (vif.trap_vector),
        .irq_sw_i        (vif.irq_sw),
        .irq_timer_i     (vif.irq_timer),
        .irq_ext_i       (vif.irq_ext)
    );

    // SVA BINDING
    csr_sva_checker u_sva (
        .clk        (clk),
        .rst        (rst_i),
        .trap_valid (vif.trap_valid),
        .mret       (vif.mret),
        .epc        (vif.epc),
        .trap_pc    (vif.trap_pc)
    );

    // Simple Waveform dump & Console tracing
    bit enable_log = 1;
    
        
    initial begin
        if (enable_log)
        $display("Time | Action | Addr | WData | RData | TrapValid | TrapVec | EPC");
    end

    always @(posedge clk) begin
    if (enable_log) begin
        if (vif.req.valid && vif.ready)
            $display("%0t | CSR RW | %h | %h | %h |     -     |    -    |  - ", $time, vif.req.addr, vif.req.wdata, vif.rdata);
        if (vif.trap_valid)
            $display("%0t |  TRAP  |  -   |    -    |    -    |     1     | %h |  - ", $time, vif.trap_vector);
        if (vif.mret)
            $display("%0t |  MRET  |  -   |    -    |    -    |     -     |    -    | %h", $time, vif.epc);
    end
end

    initial begin
        uvm_config_db#(virtual csr_if)::set(null, "*", "vif", vif);
        run_test("csr_test");
    end

    initial begin
        clk = 0; rst_i = 1; // Reset active high (Sửa lại nếu của cậu là active low)
        #20 rst_i = 0;
    end
endmodule