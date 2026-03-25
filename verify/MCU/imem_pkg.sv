package imem_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // 1. Transaction Item
    class imem_item extends uvm_sequence_item;
        rand logic [31:0] req_addr;
        rand int req_delay;
        rand int rsp_ready_delay;
        logic [31:0] rsp_instr;
        logic rst_snapshot;
        logic req_valid_snapshot;
        logic req_ready_snapshot;
        logic rsp_valid_snapshot;
        logic rsp_ready_snapshot;

        `uvm_object_utils_begin(imem_item)
            `uvm_field_int(req_addr, UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(req_delay, UVM_DEFAULT | UVM_DEC)
            `uvm_field_int(rsp_ready_delay, UVM_DEFAULT | UVM_DEC)
            `uvm_field_int(rsp_instr, UVM_DEFAULT | UVM_HEX)
            `uvm_field_int(rst_snapshot, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(req_valid_snapshot, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(req_ready_snapshot, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(rsp_valid_snapshot, UVM_DEFAULT | UVM_BIN)
        `uvm_field_int(rsp_ready_snapshot, UVM_DEFAULT | UVM_BIN)
        `uvm_object_utils_end

        function new(string name = "imem_item"); super.new(name); endfunction
    endclass

    // 2. Driver (Non-blocking Pipeline)
    class imem_driver extends uvm_driver #(imem_item);
        `uvm_component_utils(imem_driver)
        virtual imem_if vif;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual imem_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "No vif")
        endfunction

        task run_phase(uvm_phase phase);
            vif.req_valid_i <= 0;
            vif.rsp_ready_i <= 0;
            wait(vif.rst_i === 1'b0);
            @(posedge vif.clk);

            fork
                // Luồng Request
                forever begin
                    seq_item_port.get_next_item(req);
                    repeat(req.req_delay) @(posedge vif.clk);
                    vif.req_valid_i <= 1;
                    vif.req_addr_i  <= req.req_addr;
                    do begin @(posedge vif.clk); end while (vif.req_ready_o !== 1'b1);
                    vif.req_valid_i <= 0;
                    seq_item_port.item_done();
                end
                // Luồng Response
                forever begin
                    int dly = $urandom_range(0, 5);
                    repeat(dly) @(posedge vif.clk);
                    vif.rsp_ready_i <= 1;
                    do begin @(posedge vif.clk); end while (vif.rsp_valid_o !== 1'b1);
                    vif.rsp_ready_i <= 0;
                end
            join_none
        endtask
    endclass

    // 3. Monitor (Pipeline Queue)
    class imem_monitor extends uvm_monitor;
        `uvm_component_utils(imem_monitor)
        virtual imem_if vif;
        uvm_analysis_port #(imem_item) item_collected_port;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            item_collected_port = new("item_collected_port", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual imem_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "No vif")
        endfunction

task run_phase(uvm_phase phase);
    imem_item pending[$];
    imem_item curr;
    
    wait(vif.rst_i === 1'b0);
    @(posedge vif.clk); 

    forever begin
        @(posedge vif.clk);  // ← was @(negedge vif.clk) — THIS is the fix
        
        if (vif.rst_i) begin
            pending.delete();
        end else begin
            // 1. Capture REQUEST: push before pop — correct order
            if (vif.req_valid_i === 1'b1 && vif.req_ready_o === 1'b1) begin
                curr = imem_item::type_id::create("curr");
                curr.req_addr = vif.req_addr_i;
                pending.push_back(curr);
            end
            
            // 2. Capture RESPONSE: rsp_instr_o at posedge = value from PREVIOUS cycle's NBA
            //    i.e. the response for the oldest pending request — correct!
            if (vif.rsp_valid_o === 1'b1 && vif.rsp_ready_i === 1'b1) begin
                if (pending.size() > 0) begin
                    imem_item done = pending.pop_front();
                    done.rsp_instr = vif.rsp_instr_o;
                    done.rst_snapshot       = vif.rst_i;
                    done.req_valid_snapshot = vif.req_valid_i;
                    done.req_ready_snapshot = vif.req_ready_o;
                    done.rsp_valid_snapshot = vif.rsp_valid_o;
                    done.rsp_ready_snapshot = vif.rsp_ready_i;
                    item_collected_port.write(done);
                end
            end
        end
    end
endtask
    endclass

    // 4. Scoreboard (Golden Model)
    class imem_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(imem_scoreboard)
        uvm_analysis_imp #(imem_item, imem_scoreboard) item_collected_export;
        logic [31:0] ref_mem [0:1023];
        int cnt_pass = 0, cnt_fail = 0;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            for(int i=0; i<1024; i++) ref_mem[i] = 32'h0;
            $readmemh("new_code.hex", ref_mem);
        endfunction
    function void write(imem_item trans);
    logic [31:0] exp;
    int word_addr = trans.req_addr >> 2;
    exp = (word_addr < 1024) ? ref_mem[word_addr] : 32'h0000_0013;

    if (trans.rsp_instr !== exp) begin
        cnt_fail++;
        $display("\n[!!!] FAIL DETECTED at Time: %0t", $time);
        $display("      ADDR: %h | ACT: %h | EXP: %h", trans.req_addr, trans.rsp_instr, exp);
        $display("      ------------------- SIGNALS SNAPSHOT -------------------");
        $display("      Reset (rst_i): %b", trans.rst_snapshot);
        $display("      Request Channel : VALID=%b, READY=%b", trans.req_valid_snapshot, trans.req_ready_snapshot);
        $display("      Response Channel: VALID=%b, READY=%b", trans.rsp_valid_snapshot, trans.rsp_ready_snapshot);
        $display("      --------------------------------------------------------\n");
        `uvm_error("SB_FAIL", "Data Mismatch!")
    end else begin
        cnt_pass++;
    end

    
endfunction
        // BÁO CÁO TỔNG KẾT (Report Phase)
        function void report_phase(uvm_phase phase);
            int total_pkts = cnt_pass + cnt_fail;
            
            $display("\n==================================================");
            $display("             IMEM VERIFICATION REPORT             ");
            $display("==================================================");
            $display(" Total Instructions Fetched : %0d", total_pkts);
            $display("--------------------------------------------------");
            $display(" PASS SUMMARY:");
            $display("   [+] Valid Matches        : %0d", cnt_pass);
            $display("--------------------------------------------------");
            $display(" FAIL SUMMARY:");
            $display("   [-] Data Mismatch Fails  : %0d", cnt_fail);
            $display("==================================================");
            
            if (total_pkts == 0) begin
                $display(" >>> FINAL STATUS: [FAILED] NO TRANSACTIONS! <<< ");
                `uvm_error("REPORT", "Không có bất kỳ gói tin nào được xử lý. Check lại Driver/Monitor!")
            end else if (cnt_fail == 0) begin
                $display(" >>> FINAL STATUS: [PASSED] PERFECT MATCH! <<< ");
                `uvm_info("REPORT", "DON'T HAVE ANY ERRORS", UVM_NONE)
            end else begin
                $display(" >>> FINAL STATUS: [FAILED] %0d ERRORS FOUND! <<< ", cnt_fail);
                `uvm_error("REPORT", "Detected data mismatches. Please check the log for details [!!!] FAIL DETECTED.")
            end
            $display("==================================================\n");
        endfunction
    endclass

    // 5. Agent, Env, Test (Khởi tạo nhanh)
    class imem_agent extends uvm_agent;
        `uvm_component_utils(imem_agent)
        imem_driver drv; imem_monitor mon; uvm_sequencer#(imem_item) sqr;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            drv=imem_driver::type_id::create("drv",this);
            mon=imem_monitor::type_id::create("mon",this);
            sqr=uvm_sequencer#(imem_item)::type_id::create("sqr",this);
        endfunction
        function void connect_phase(uvm_phase phase); drv.seq_item_port.connect(sqr.seq_item_export); endfunction
    endclass

    class imem_env extends uvm_env;
        `uvm_component_utils(imem_env)
        imem_agent agt; imem_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            agt=imem_agent::type_id::create("agt",this);
            scb=imem_scoreboard::type_id::create("scb",this);
        endfunction
        function void connect_phase(uvm_phase phase); agt.mon.item_collected_port.connect(scb.item_collected_export); endfunction
    endclass

    class imem_basic_test extends uvm_test;
        `uvm_component_utils(imem_basic_test)
        imem_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase); env=imem_env::type_id::create("env",this); endfunction
        task run_phase(uvm_phase phase);
            imem_item item;
            phase.raise_objection(this);
            repeat(50000) begin
                item = imem_item::type_id::create("item");
                item.req_addr = $urandom_range(0, 5000);
                item.req_addr[1:0] = 0;
                item.req_delay = $urandom_range(0, 3);
                env.agt.sqr.execute_item(item);
            end
            #100;
            phase.drop_objection(this);
        endtask
    endclass
endpackage