// ==========================================
// 1. INTERFACE
// ==========================================
interface decoder_if (input logic clk);
    import decoder_pkg::*; 
    logic [31:0] instr_i;
    dec_out_t    ctrl_o;
    logic [31:0] imm_o;
    logic [4:0]  rd_addr_o;
    logic [4:0]  rs1_addr_o;
    logic [4:0]  rs2_addr_o;

    clocking cb @(posedge clk);
        default input #1step output #1step;
        output instr_i;
        input  ctrl_o, imm_o, rd_addr_o, rs1_addr_o, rs2_addr_o;
    endclocking
endinterface

// ==========================================
// 2. CLASSES
// ==========================================
package tb_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import decoder_pkg::*;
    import riscv_instr::*;

    // --------------------------------------------------------
    // 2.1 ITEM
    // --------------------------------------------------------
    class decoder_item extends uvm_sequence_item;
        rand logic [31:0] instr;
        dec_out_t    ctrl;
        logic [31:0] imm;
        logic [4:0]  rd_addr;
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;

        `uvm_object_utils_begin(decoder_item)
            `uvm_field_int(instr, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "decoder_item");
            super.new(name);
        endfunction
    endclass

    // --------------------------------------------------------
    // 2.2 SEQUENCER
    // --------------------------------------------------------
    typedef uvm_sequencer #(decoder_item) decoder_sequencer;

    // --------------------------------------------------------
    // 2.3 SEQUENCE (FULL COVERAGE - 50 CASES PER INSTR)
    // --------------------------------------------------------
    class decoder_full_sequence extends uvm_sequence #(decoder_item);
        `uvm_object_utils(decoder_full_sequence)

        function new(string name = "decoder_full_sequence");
            super.new(name);
        endfunction

        // --- Helper Tasks để tạo lệnh theo định dạng ---
        
        // 1. R-Type: {funct7, rs2, rs1, funct3, rd, opcode}
        task gen_r_type(string name, logic [6:0] op, logic [2:0] f3, logic [6:0] f7);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {f7, 5'($urandom), 5'($urandom), f3, 5'($urandom), op};
                finish_item(req);
            end
        endtask

        // 2. I-Type: {imm[11:0], rs1, funct3, rd, opcode}
        task gen_i_type(string name, logic [6:0] op, logic [2:0] f3);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {12'($urandom), 5'($urandom), f3, 5'($urandom), op};
                finish_item(req);
            end
        endtask

        // 2b. Shift I-Type (Special): {funct7, shamt, rs1, funct3, rd, opcode}
        task gen_shift_i_type(string name, logic [6:0] op, logic [2:0] f3, logic [6:0] f7);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {f7, 5'($urandom), 5'($urandom), f3, 5'($urandom), op};
                finish_item(req);
            end
        endtask

        // 3. S-Type: {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode}
        task gen_s_type(string name, logic [6:0] op, logic [2:0] f3);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {7'($urandom), 5'($urandom), 5'($urandom), f3, 5'($urandom), op};
                finish_item(req);
            end
        endtask

        // 4. B-Type: {imm..., rs2, rs1, funct3, imm..., opcode} (Random bits vào vị trí imm)
        task gen_b_type(string name, logic [6:0] op, logic [2:0] f3);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {7'($urandom), 5'($urandom), 5'($urandom), f3, 5'($urandom), op};
                finish_item(req);
            end
        endtask

        // 5. U-Type: {imm[31:12], rd, opcode}
        task gen_u_type(string name, logic [6:0] op);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {20'($urandom), 5'($urandom), op};
                finish_item(req);
            end
        endtask

        // 6. J-Type (JAL): {imm..., rd, opcode}
        task gen_j_type(string name, logic [6:0] op);
            `uvm_info("SEQ", $sformatf("Generating 50 cases for: %s", name), UVM_LOW)
            repeat(50) begin
                req = decoder_item::type_id::create("req");
                start_item(req);
                req.instr = {20'($urandom), 5'($urandom), op};
                finish_item(req);
            end
        endtask


        // --- MAIN BODY: Liệt kê tất cả lệnh ---
        task body();
            // Định nghĩa Opcode chuẩn RISC-V (RV32I + M)
            logic [6:0] OP_LUI    = 7'b0110111;
            logic [6:0] OP_AUIPC  = 7'b0010111;
            logic [6:0] OP_JAL    = 7'b1101111;
            logic [6:0] OP_JALR   = 7'b1100111;
            logic [6:0] OP_BRANCH = 7'b1100011;
            logic [6:0] OP_LOAD   = 7'b0000011;
            logic [6:0] OP_STORE  = 7'b0100011;
            logic [6:0] OP_IMM    = 7'b0010011;
            logic [6:0] OP_REG    = 7'b0110011;

            // 1. U-Type
            gen_u_type("LUI",   OP_LUI);
            gen_u_type("AUIPC", OP_AUIPC);

            // 2. J-Type
            gen_j_type("JAL",   OP_JAL);
            gen_i_type("JALR",  OP_JALR, 3'b000); // JALR la I-Type

            // 3. B-Type (Branch)
            gen_b_type("BEQ",  OP_BRANCH, 3'b000);
            gen_b_type("BNE",  OP_BRANCH, 3'b001);
            gen_b_type("BLT",  OP_BRANCH, 3'b100);
            gen_b_type("BGE",  OP_BRANCH, 3'b101);
            gen_b_type("BLTU", OP_BRANCH, 3'b110);
            gen_b_type("BGEU", OP_BRANCH, 3'b111);

            // 4. Load Instructions (I-Type)
            gen_i_type("LB",  OP_LOAD, 3'b000);
            gen_i_type("LH",  OP_LOAD, 3'b001);
            gen_i_type("LW",  OP_LOAD, 3'b010);
            gen_i_type("LBU", OP_LOAD, 3'b100);
            gen_i_type("LHU", OP_LOAD, 3'b101);

            // 5. Store Instructions (S-Type)
            gen_s_type("SB", OP_STORE, 3'b000);
            gen_s_type("SH", OP_STORE, 3'b001);
            gen_s_type("SW", OP_STORE, 3'b010);

            // 6. ALU Immediate (I-Type)
            gen_i_type("ADDI",  OP_IMM, 3'b000);
            gen_i_type("SLTI",  OP_IMM, 3'b010);
            gen_i_type("SLTIU", OP_IMM, 3'b011);
            gen_i_type("XORI",  OP_IMM, 3'b100);
            gen_i_type("ORI",   OP_IMM, 3'b110);
            gen_i_type("ANDI",  OP_IMM, 3'b111);
            
            // Shift Immediate (Can funct7)
            gen_shift_i_type("SLLI", OP_IMM, 3'b001, 7'b0000000);
            gen_shift_i_type("SRLI", OP_IMM, 3'b101, 7'b0000000);
            gen_shift_i_type("SRAI", OP_IMM, 3'b101, 7'b0100000);

            // 7. ALU Register (R-Type)
            gen_r_type("ADD",  OP_REG, 3'b000, 7'b0000000);
            gen_r_type("SUB",  OP_REG, 3'b000, 7'b0100000);
            gen_r_type("SLL",  OP_REG, 3'b001, 7'b0000000);
            gen_r_type("SLT",  OP_REG, 3'b010, 7'b0000000);
            gen_r_type("SLTU", OP_REG, 3'b011, 7'b0000000);
            gen_r_type("XOR",  OP_REG, 3'b100, 7'b0000000);
            gen_r_type("SRL",  OP_REG, 3'b101, 7'b0000000);
            gen_r_type("SRA",  OP_REG, 3'b101, 7'b0100000);
            gen_r_type("OR",   OP_REG, 3'b110, 7'b0000000);
            gen_r_type("AND",  OP_REG, 3'b111, 7'b0000000);

            // 8. Multiply Extension (R-Type) - funct7=0000001
            gen_r_type("MUL",    OP_REG, 3'b000, 7'b0000001);
            gen_r_type("MULH",   OP_REG, 3'b001, 7'b0000001);
            gen_r_type("MULHSU", OP_REG, 3'b010, 7'b0000001);
            gen_r_type("MULHU",  OP_REG, 3'b011, 7'b0000001);
            gen_r_type("DIV",    OP_REG, 3'b100, 7'b0000001);
            gen_r_type("DIVU",   OP_REG, 3'b101, 7'b0000001);
            gen_r_type("REM",    OP_REG, 3'b110, 7'b0000001);
            gen_r_type("REMU",   OP_REG, 3'b111, 7'b0000001);

        endtask
    endclass

    // --------------------------------------------------------
    // 2.4 DRIVER
    // --------------------------------------------------------
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
            @(posedge vif.clk);
            vif.instr_i <= req.instr;
        endtask
    endclass

    // --------------------------------------------------------
    // 2.5 MONITOR
    // --------------------------------------------------------
    class decoder_monitor extends uvm_monitor;
        `uvm_component_utils(decoder_monitor)
        virtual decoder_if vif;
        uvm_analysis_port #(decoder_item) mon_ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            mon_ap = new("mon_ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if(!uvm_config_db#(virtual decoder_if)::get(this, "", "vif", vif))
                 `uvm_fatal("MON", "Could not get vif")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                @(posedge vif.clk); 
                #1; 
                begin
                    decoder_item item = decoder_item::type_id::create("item");
                    item.instr    = vif.instr_i;
                    item.ctrl     = vif.ctrl_o;
                    item.imm      = vif.imm_o;
                    item.rd_addr  = vif.rd_addr_o;
                    
                    if (item.instr !== 'x) begin
                        mon_ap.write(item);
                    end
                end
            end
        endtask
    endclass

    // --------------------------------------------------------
    // 2.6 AGENT
    // --------------------------------------------------------
    class decoder_agent extends uvm_agent;
        `uvm_component_utils(decoder_agent)
        decoder_driver    driver;
        decoder_monitor   monitor;
        decoder_sequencer sequencer;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = decoder_driver::type_id::create("driver", this);
            monitor   = decoder_monitor::type_id::create("monitor", this);
            sequencer = decoder_sequencer::type_id::create("sequencer", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    // --------------------------------------------------------
    // 2.7 SCOREBOARD (Đã nâng cấp để in log đẹp hơn)
    // --------------------------------------------------------
    class decoder_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(decoder_scoreboard)
        uvm_analysis_imp #(decoder_item, decoder_scoreboard) item_collected_export;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
        endfunction

        function void write(decoder_item item);
            // In thông tin để check
            `uvm_info("SCB", $sformatf("INSTR: %h | DEC_IMM: %h | ALU_OP: %s", 
                item.instr, item.imm, item.ctrl.alu_req.op.name()), UVM_LOW)
        endfunction
    endclass

    // --------------------------------------------------------
    // 2.8 ENV
    // --------------------------------------------------------
    class decoder_env extends uvm_env;
        `uvm_component_utils(decoder_env)
        decoder_agent      agent;
        decoder_scoreboard scb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = decoder_agent::type_id::create("agent", this);
            scb   = decoder_scoreboard::type_id::create("scb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.monitor.mon_ap.connect(scb.item_collected_export);
        endfunction
    endclass

    // --------------------------------------------------------
    // 2.9 TEST (Sử dụng Sequence Full Coverage)
    // --------------------------------------------------------
    class decoder_full_test extends uvm_test;
        `uvm_component_utils(decoder_full_test)
        decoder_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = decoder_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            decoder_full_sequence seq; // Dùng Sequence mới
            phase.raise_objection(this);
            seq = decoder_full_sequence::type_id::create("seq");
            seq.start(env.agent.sequencer);
            phase.drop_objection(this);
        endtask
    endclass
endpackage

// ==========================================
// 3. TOP MODULE
// ==========================================
module tb_decoder_top;
    import uvm_pkg::*;
    import decoder_pkg::*;
    import tb_pkg::*;

    logic clk;
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    decoder_if dut_if(clk);

    decoder dut (
        .instr_i    (dut_if.instr_i),
        .ctrl_o     (dut_if.ctrl_o),
        .imm_o      (dut_if.imm_o),
        .rd_addr_o  (dut_if.rd_addr_o),
        .rs1_addr_o (dut_if.rs1_addr_o),
        .rs2_addr_o (dut_if.rs2_addr_o)
    );

    initial begin
        uvm_config_db#(virtual decoder_if)::set(null, "*", "vif", dut_if);
        // Chạy test mới: decoder_full_test
        run_test("decoder_full_test");
    end
endmodule