interface decoder_if (input logic clk);
    import decoder_pkg::*; // Import để dùng dec_out_t

    // Input signals
    logic [31:0] instr_i;

    // Output signals
    dec_out_t    ctrl_o;
    logic [31:0] imm_o;
    logic [4:0]  rd_addr_o;
    logic [4:0]  rs1_addr_o;
    logic [4:0]  rs2_addr_o;

    // Clocking block (Optional nhưng khuyên dùng cho Driver/Monitor)
    clocking cb @(posedge clk);
        default input #1step output #1step;
        output instr_i;
        input  ctrl_o, imm_o, rd_addr_o, rs1_addr_o, rs2_addr_o;
    endclocking
endinterface
import uvm_pkg::*;
`include "uvm_macros.svh"
import decoder_pkg::*;
import riscv_instr::*;

class decoder_item extends uvm_sequence_item;
    // Input (Randomize)
    rand logic [31:0] instr;

    // Outputs (Để Monitor thu thập)
    dec_out_t    ctrl;
    logic [31:0] imm;
    logic [4:0]  rd_addr;
    logic [4:0]  rs1_addr;
    logic [4:0]  rs2_addr;

    `uvm_object_utils_begin(decoder_item)
        `uvm_field_int(instr, UVM_ALL_ON)
        // Các field output không cần pack nếu không dùng feature record có sẵn
    `uvm_object_utils_end

    function new(string name = "decoder_item");
        super.new(name);
    endfunction

    // Constraint ví dụ: Random instruction phải có Opcode valid (2 bit cuối = 11)
    constraint valid_opcode_c {
        instr[1:0] == 2'b11;
    }
    // Bạn nên thêm constraint để test từng nhóm lệnh (R-type, I-type...)
endclass
class decoder_driver extends uvm_driver #(decoder_item);
    `uvm_component_utils(decoder_driver)
    
    virtual decoder_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual decoder_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "Could not get vif")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            seq_item_port.get_next_item(req);
            drive();
            seq_item_port.item_done();
        end
    endtask

    task drive();
        @(vif.cb); // Đợi cạnh lên clock
        vif.cb.instr_i <= req.instr; // Đẩy instruction vào DUT
    endtask
endclass
class decoder_monitor extends uvm_monitor;
    `uvm_component_utils(decoder_monitor)
    virtual decoder_if vif;
    uvm_analysis_port #(decoder_item) mon_ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        mon_ap = new("mon_ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        // ... Lấy vif tương tự Driver ...
        if(!uvm_config_db#(virtual decoder_if)::get(this, "", "vif", vif))
             `uvm_fatal("MON", "Could not get vif")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(vif.cb); // Đợi clock sample
            // Đợi 1 chu kỳ để tín hiệu ổn định (hoặc sample ngay tại cb input)
            @(vif.cb);

            decoder_item item = decoder_item::type_id::create("item");
            item.instr    = vif.cb.instr_i;
            item.ctrl     = vif.cb.ctrl_o;
            item.imm      = vif.cb.imm_o;
            item.rd_addr  = vif.cb.rd_addr_o;
            // ... (gán nốt rs1, rs2) ...

            mon_ap.write(item); // Gửi đi
        end
    endtask
endclass
class decoder_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(decoder_scoreboard)
    uvm_analysis_imp #(decoder_item, decoder_scoreboard) item_collected_export;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        item_collected_export = new("item_collected_export", this);
    endfunction

    // Hàm write được gọi mỗi khi Monitor gửi gói tin sang
    function void write(decoder_item item);
        dec_out_t expected_ctrl;
        logic [31:0] expected_imm;

        // 1. Tính toán giá trị mong đợi (Golden Model)
        reference_model(item.instr, expected_ctrl, expected_imm);

        // 2. So sánh Actual (DUT) vs Expected (Ref Model)
        if (item.ctrl !== expected_ctrl) begin
            `uvm_error("SCB", $sformatf("Mismatch Control! Instr: %h. Expected Op: %s, Got: %s",
                                        item.instr, expected_ctrl.alu_req.op.name(), item.ctrl.alu_req.op.name()))
        end

        if (item.imm !== expected_imm) begin
            `uvm_error("SCB", $sformatf("Mismatch Imm! Instr: %h. Exp: %h, Got: %h", item.instr, expected_imm, item.imm))
        end

        // ... So sánh tiếp rd_addr, rs1...
    endfunction

    // Đây là nơi bạn tái tạo lại logic của DUT để kiểm tra chéo
    function void reference_model(input logic [31:0] instr, output dec_out_t ctrl, output logic [31:0] imm);
        // Copy logic casez từ thiết kế vào đây hoặc viết một logic kiểm tra đơn giản hơn
        // Ví dụ: Check Opcode LUI
        logic [6:0] opcode = instr[6:0];

        // Reset defaults
        ctrl.rf_we = 0;
        // ...

        case(opcode)
            7'b0110111: begin // LUI
                ctrl.imm_type = IMM_U;
                ctrl.rf_we = 1;
                // Tính expected IMM
                imm = {instr[31:12], 12'b0};
            end
            // ... Viết tiếp cho các lệnh khác ...
        endcase
    endfunction
endclass
class decoder_random_test extends uvm_test;
    `uvm_component_utils(decoder_random_test)
    decoder_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        env = decoder_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        decoder_base_sequence seq;
        phase.raise_objection(this);
        seq = decoder_base_sequence::type_id::create("seq");
        seq.start(env.agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass
module decoder_uvm;
    import uvm_pkg::*;
    import decoder_pkg::*;

    logic clk;

    // Tạo clock giả (mặc dù DUT không dùng, nhưng Interface cần)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Interface
    decoder_if dut_if(clk);

    // DUT Instance
    decoder dut (
        .instr_i    (dut_if.instr_i),
        .ctrl_o     (dut_if.ctrl_o),
        .imm_o      (dut_if.imm_o),
        .rd_addr_o  (dut_if.rd_addr_o),
        .rs1_addr_o (dut_if.rs1_addr_o),
        .rs2_addr_o (dut_if.rs2_addr_o)
    );
decoder
    initial begin
        // Đặt interface vào Config DB
        uvm_config_db#(virtual decoder_if)::set(null, "*", "vif", dut_if);

        // Chạy Test
        run_test("decoder_random_test");
    end
endmodule
