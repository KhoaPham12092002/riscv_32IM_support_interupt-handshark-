package imem_pkg;
    import uvm_pkg::*;      
    `include "uvm_macros.svh"

    // Forward declaration
    typedef class imem_item;
    typedef class imem_driver;
    typedef class imem_monitor;
    typedef class imem_agent;
    typedef class imem_scoreboard;
    typedef class imem_env;
    typedef class imem_rand_sequence; // Sequence
    typedef class imem_basic_test;

    // ---------------------------------------------------------
    // 1. SEQUENCE ITEM (Giữ nguyên)
    // ---------------------------------------------------------
    class imem_item extends uvm_sequence_item;
        rand bit [31:0] addr;   
        rand int        delay;
        bit [31:0]      data;   

        `uvm_object_utils_begin(imem_item)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
            `uvm_field_int(delay, UVM_ALL_ON)
        `uvm_object_utils_end

        constraint addr_c { addr[1:0] == 2'b00; addr < 4096; }
        constraint delay_c { delay inside {[0:2]}; }

        function new(string name = "imem_item");
            super.new(name);
        endfunction
    endclass

    // ---------------------------------------------------------
    // 2. DRIVER (Sửa logic Reset Active High)
    // ---------------------------------------------------------
    class imem_driver extends uvm_driver #(imem_item);
        `uvm_component_utils(imem_driver)
        virtual imem_if vif; 

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual imem_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "Could not get interface")
        endfunction

        task run_phase(uvm_phase phase);
            // Reset state
            vif.req_i   <= 0;
            vif.addr_i  <= 0;
            
            // Wait for Reset to drop (Active High -> Wait for 0)
            wait(vif.rst_i === 0); 

            forever begin
                seq_item_port.get_next_item(req);
                repeat(req.delay) @(posedge vif.clk_i);

                @(posedge vif.clk_i);
                vif.req_i  <= 1'b1;       
                vif.addr_i <= req.addr;   

                @(posedge vif.clk_i);
                vif.req_i  <= 1'b0;       

                seq_item_port.item_done();
            end
        endtask
    endclass

    // ---------------------------------------------------------
    // 3. MONITOR (Sửa logic Reset Active High)
    // ---------------------------------------------------------
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
                `uvm_fatal("MON", "Could not get interface")
        endfunction

        task run_phase(uvm_phase phase);
            imem_item item;
            forever begin
                @(posedge vif.clk_i);
                
                // Thu thập khi: Reset = 0 (Không reset) VÀ Req = 1
                if (vif.rst_i === 0 && vif.req_i === 1) begin
                    item = imem_item::type_id::create("item");
                    item.addr = vif.addr_i;

                    @(posedge vif.clk_i); 
                    #1; 
                    item.data = vif.instr_o;
                    item_collected_port.write(item);
                end
            end
        endtask
    endclass

    // ---------------------------------------------------------
    // 4. SCOREBOARD (Giữ nguyên)
    // ---------------------------------------------------------
    class imem_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(imem_scoreboard)
        uvm_analysis_imp #(imem_item, imem_scoreboard) item_collected_export;
        bit [31:0] ref_mem [0:4095];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            $readmemh("program.hex", ref_mem); 
        endfunction

        function void write(imem_item trans);
            bit [31:0] expected_data;
            logic [31:0] word_idx;
            word_idx = trans.addr >> 2; 
            
            if (word_idx < 1024) expected_data = ref_mem[word_idx];
            else expected_data = 32'h0;

            if (trans.data !== expected_data)
                `uvm_error("SCB", $sformatf("MISMATCH! Addr: 0x%h | DUT: 0x%h | EXP: 0x%h", trans.addr, trans.data, expected_data))
            else
                `uvm_info("SCB", $sformatf("PASS! Addr: 0x%h | Data: 0x%h", trans.addr, trans.data), UVM_HIGH)
        endfunction
    endclass

    // ---------------------------------------------------------
    // 5. AGENT, ENV, SEQUENCE, TEST (Giữ nguyên cấu trúc)
    // ---------------------------------------------------------
    class imem_agent extends uvm_agent;
        `uvm_component_utils(imem_agent)
        imem_driver    driver;
        imem_monitor   monitor;
        uvm_sequencer #(imem_item) sequencer;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = imem_driver::type_id::create("driver", this);
            monitor   = imem_monitor::type_id::create("monitor", this);
            sequencer = uvm_sequencer#(imem_item)::type_id::create("sequencer", this);
        endfunction
        function void connect_phase(uvm_phase phase); driver.seq_item_port.connect(sequencer.seq_item_export); endfunction
    endclass

    class imem_env extends uvm_env;
        `uvm_component_utils(imem_env)
        imem_agent agent;
        imem_scoreboard scb;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = imem_agent::type_id::create("agent", this);
            scb   = imem_scoreboard::type_id::create("scb", this);
        endfunction
        function void connect_phase(uvm_phase phase); agent.monitor.item_collected_port.connect(scb.item_collected_export); endfunction
    endclass

   // ---------------------------------------------------------
    // 2. SEQUENCE & TEST (FIX LICENSE ERROR)
    // ---------------------------------------------------------
    
    class imem_rand_sequence extends uvm_sequence #(imem_item);
        `uvm_object_utils(imem_rand_sequence)
        
        function new(string name = "imem_rand_sequence");
            super.new(name);
        endfunction

        task body();
            // Tạo 50 giao dịch
            repeat(5000) begin
                req = imem_item::type_id::create("req");
                
                start_item(req);
                
                // --- THAY THẾ randomize() BẰNG $urandom ---
                // Vì bản Questa Starter không cho dùng randomize() với Constraints
                
                // 1. Random địa chỉ: Đảm bảo chia hết cho 4 (Word Aligned)
                // Logic: Random số từ 0->1023, rồi nhân 4 -> Ra địa chỉ 0->4092
                req.addr = $urandom_range(0, 1023) * 4;
                
                // 2. Random delay: Từ 0 đến 2
                req.delay = $urandom_range(0, 2);
                
                // req.data là output, không cần random
                
                // Không cần gọi if(!req.randomize())... nữa
                
                finish_item(req);
            end
        endtask
    endclass

    class imem_basic_test extends uvm_test;
        `uvm_component_utils(imem_basic_test)
        imem_env env;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = imem_env::type_id::create("env", this);
        endfunction
        task run_phase(uvm_phase phase);
            imem_rand_sequence seq;
            phase.raise_objection(this);
            seq = imem_rand_sequence::type_id::create("seq");
            seq.start(env.agent.sequencer);
            #100;
            phase.drop_objection(this);
        endtask
    endclass   
endpackage