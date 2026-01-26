package imem_pkg;
    import uvm_pkg::*;      // Import thư viện UVM chuẩn
    `include "uvm_macros.svh" // Import các macro như `uvm_info...

    // ---------------------------------------------------------
    // 1. SEQUENCE ITEM (Gói tin giao dịch)
    // ---------------------------------------------------------
    class imem_item extends uvm_sequence_item;
        rand bit [31:0] addr;   // Địa chỉ muốn đọc
        bit [31:0]      data;   // Dữ liệu đọc được

        `uvm_object_utils_begin(imem_item)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(data, UVM_ALL_ON)
        `uvm_object_utils_end

        // Ràng buộc: Địa chỉ phải chia hết cho 4 (Word Aligned) 
        // và nằm trong khoảng nhỏ (để dễ check trong test này)
        constraint addr_c { 
            addr[1:0] == 2'b00; 
            addr < 64; 
        }

        function new(string name = "imem_item");
            super.new(name);
        endfunction
    endclass

    // ---------------------------------------------------------
    // 2. DRIVER (Lái tín hiệu vào DUT)
    // ---------------------------------------------------------
    class imem_driver extends uvm_driver #(imem_item);
        `uvm_component_utils(imem_driver)
        virtual imem_if vif; // Interface ảo

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual imem_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "Could not get interface")
        endfunction

        task run_phase(uvm_phase phase);
            forever begin
                seq_item_port.get_next_item(req);
                // Drive logic
                @(posedge vif.clk);
                vif.addr <= req.addr;
                // Chờ 1 cycle để RAM phản hồi (nếu là sync) 
                // hoặc lấy luôn (nếu là async). Ở đây ta chờ cho ổn định.
                @(posedge vif.clk); 
                seq_item_port.item_done();
            end
        endtask
    endclass

    // ---------------------------------------------------------
    // 3. MONITOR (Quan sát tín hiệu từ DUT)
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
                @(posedge vif.clk);
                // Sample tại cạnh lên, lúc này addr đã ổn định
                // Lưu ý: Tùy timing của DUT, có thể cần sample trễ hơn 1 chút
                item = imem_item::type_id::create("item");
                item.addr = vif.addr;
                #1; // Delay 1 xíu để lấy output (nếu là logic tổ hợp)
                item.data = vif.instr;
                
                item_collected_port.write(item);
            end
        endtask
    endclass

    // ---------------------------------------------------------
    // 4. SCOREBOARD (So sánh kết quả)
    // ---------------------------------------------------------
    class imem_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(imem_scoreboard)
        uvm_analysis_imp #(imem_item, imem_scoreboard) item_collected_export;
        
        // Mô hình tham chiếu (Golden Model)
        bit [31:0] ref_mem [0:1023];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            item_collected_export = new("item_collected_export", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            // Load file hex y hệt như DUT làm để so sánh
            // ModelSim cần đường dẫn đúng, hoặc file nằm cùng folder sim
            $readmemh("program.hex", ref_mem);
        endfunction

        function void write(imem_item trans);
            bit [31:0] expected_data;
            logic [31:0] word_idx;

            // Logic tính toán của Golden Model
            word_idx = trans.addr >> 2; // Chia 4
            expected_data = ref_mem[word_idx];

            if (trans.data !== expected_data) begin
                `uvm_error("SCB", $sformatf("MISMATCH! Addr: %0h | DUT: %0h | EXP: %0h", 
                                            trans.addr, trans.data, expected_data))
            end else begin
                `uvm_info("SCB", $sformatf("PASS! Addr: %0h | Data: %0h", 
                                           trans.addr, trans.data), UVM_LOW)
            end
        endfunction
    endclass

    // ---------------------------------------------------------
    // 5. AGENT & ENV (Bộ khung chứa các thành phần trên)
    // ---------------------------------------------------------
    class imem_agent extends uvm_agent;
        `uvm_component_utils(imem_agent)
        imem_driver    driver;
        imem_monitor   monitor;
        uvm_sequencer #(imem_item) sequencer;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            driver    = imem_driver::type_id::create("driver", this);
            monitor   = imem_monitor::type_id::create("monitor", this);
            sequencer = uvm_sequencer#(imem_item)::type_id::create("sequencer", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass

    class imem_env extends uvm_env;
        `uvm_component_utils(imem_env)
        imem_agent      agent;
        imem_scoreboard scb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = imem_agent::type_id::create("agent", this);
            scb   = imem_scoreboard::type_id::create("scb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.monitor.item_collected_port.connect(scb.item_collected_export);
        endfunction
    endclass

    // ---------------------------------------------------------
    // 6. TEST (Kịch bản kiểm tra)
    // ---------------------------------------------------------
    class imem_basic_test extends uvm_test;
        `uvm_component_utils(imem_basic_test)
        imem_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = imem_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            imem_item item;
            phase.raise_objection(this);
            
            // Tạo 10 giao dịch ngẫu nhiên
            repeat(10) begin
                item = imem_item::type_id::create("item");
                item.randomize();
                env.agent.sequencer.execute_item(item); // Gửi item xuống Driver
            end
            
            #100;
            phase.drop_objection(this);
        endtask
    endclass

endpackage