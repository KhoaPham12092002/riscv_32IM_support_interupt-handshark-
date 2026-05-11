//==============================================================================
// tb_core_riscv_thesis.sv  —  Thesis Section 5.4 → Bảng 1
//
// Full-core hazard stress testbench (most complex of the 6 thesis tbs).
// Updated to match `soc_without_mem` top design.
//==============================================================================
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "common/tb_thesis_pkg.sv"
`include "common/tb_thesis_sva.svh"

//------------------------------------------------------------------------------
// Interface (matches soc_without_mem IF/DMEM split + interrupts)
//------------------------------------------------------------------------------
interface core_thesis_if (input logic clk_i);
  logic        rst_i;
  
  // IMEM (IF)
  logic [31:0] if_req_addr_o;
  logic        if_req_valid_o, if_req_ready_i;
  logic [31:0] if_rsp_instr_i;
  logic        if_rsp_valid_i, if_rsp_ready_o;
  
  // DMEM
  logic [31:0] dmem_addr_o, dmem_wdata_o;
  logic [3:0]  dmem_be_o;
  logic        dmem_we_o;
  logic        dmem_req_valid_o, dmem_req_ready_i;
  logic [31:0] dmem_rdata_i;
  logic        dmem_rsp_valid_i, dmem_rsp_ready_o;
  logic        dmem_err_i;
  
  // Interrupts
  logic        irq_sw_i;
  logic        irq_timer_i;
  logic        irq_ext_i;
endinterface

package core_thesis_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //----------------------------------------------------------------------
  // Item 
  //----------------------------------------------------------------------
  class core_item extends uvm_sequence_item;
    bit          is_load_mode; 
    logic [31:0] load_addr;
    logic [31:0] load_instr;
    int unsigned imem_delay;
    int unsigned dmem_delay;

    `uvm_object_utils(core_item)
    function new(string n="core_item"); super.new(n); endfunction
  endclass

  //----------------------------------------------------------------------
  // Prediction packet
  //----------------------------------------------------------------------
  class core_prediction extends uvm_sequence_item;
    int unsigned alu_raw_cnt;
    int unsigned load_use_cnt;
    int unsigned branch_cnt;
    int unsigned store_cnt;

    `uvm_object_utils(core_prediction)
    function new(string n="core_prediction"); super.new(n); endfunction
  endclass

  //----------------------------------------------------------------------
  // Driver
  //----------------------------------------------------------------------
  class core_driver extends uvm_driver #(core_item);
    `uvm_component_utils(core_driver)
    virtual core_thesis_if vif;
    logic [31:0] fake_imem [0:4095];
    logic [31:0] fake_dmem [0:1023];

    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void build_phase(uvm_phase phase);
      int i;
      for (i = 0; i < 4096; i++) fake_imem[i] = 32'h0000_0013;  // NOP
      for (i = 0; i < 1024; i++) fake_dmem[i] = 32'h0000_0000;
      if (!uvm_config_db#(virtual core_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      vif.if_req_ready_i <= 0; vif.if_rsp_valid_i <= 0; vif.if_rsp_instr_i <= 0;
      vif.dmem_req_ready_i <= 0; vif.dmem_rsp_valid_i <= 0; vif.dmem_rdata_i <= 0;
      vif.dmem_err_i <= 0;
      vif.irq_sw_i <= 0; vif.irq_timer_i <= 0; vif.irq_ext_i <= 0;
      vif.rst_i <= 1;
      @(posedge vif.clk_i);
      @(posedge vif.clk_i);

      fork
        forever handle_dmem_bg();
      join_none

      forever begin
        seq_item_port.get_next_item(req);
        if (req.is_load_mode) begin
          fake_imem[req.load_addr[13:2]] = req.load_instr;
        end
        else begin
          if (vif.rst_i) vif.rst_i <= 0;
            handle_imem(req.imem_delay);
        end
        seq_item_port.item_done();
      end
    endtask

    task handle_imem(int delay);
      logic [31:0] captured_addr;
      vif.if_req_ready_i <= 1'b1;
      do @(posedge vif.clk_i); while (!(vif.if_req_valid_o && vif.if_req_ready_i));
      captured_addr = vif.if_req_addr_o;
      vif.if_req_ready_i <= 0;
      
      repeat (delay) @(posedge vif.clk_i);
      
      vif.if_rsp_valid_i <= 1'b1;
      vif.if_rsp_instr_i <= (captured_addr[13:2] < 4096) ?
                            fake_imem[captured_addr[13:2]] : 32'h0000_0013;
      do @(posedge vif.clk_i); while (!(vif.if_rsp_valid_i && vif.if_rsp_ready_o));
      vif.if_rsp_valid_i <= 0;
    endtask

    task handle_dmem_bg();
      logic [31:0] captured_addr;
      logic        captured_we;
      logic [31:0] captured_wdata;
      int delay;

      vif.dmem_req_ready_i <= 1'b1;
      
      do @(posedge vif.clk_i);
      while (!(vif.dmem_req_valid_o && vif.dmem_req_ready_i));

      captured_addr  = vif.dmem_addr_o;
      captured_we    = vif.dmem_we_o;
      captured_wdata = vif.dmem_wdata_o;
      
      vif.dmem_req_ready_i <= 0;

      if (captured_we) begin
        fake_dmem[captured_addr[11:2]] = captured_wdata;
      end

      delay = $urandom_range(0, 1);
      repeat (delay) @(posedge vif.clk_i);

      if (!captured_we) begin
        vif.dmem_rsp_valid_i <= 1'b1;
        vif.dmem_rdata_i <= fake_dmem[captured_addr[11:2]];
        
        do @(posedge vif.clk_i); while (!(vif.dmem_rsp_valid_i && vif.dmem_rsp_ready_o));
        vif.dmem_rsp_valid_i <= 0;
      end
    endtask 
  endclass

  //----------------------------------------------------------------------
  // Sequence
  //----------------------------------------------------------------------
  class core_stress_seq extends uvm_sequence #(core_item);
    `uvm_object_utils(core_stress_seq)

    int unsigned n_instr     = 100;
    int unsigned n_run_cycle = 500;

    int unsigned pred_alu_raw   = 0;
    int unsigned pred_load_use  = 0;
    int unsigned pred_branch    = 0;
    int unsigned pred_store     = 0;

    function new(string n=""); super.new(n); endfunction

    function logic [31:0] enc_r_type(bit [4:0] rd, bit [4:0] rs1, bit [4:0] rs2,
                                     bit [2:0] f3, bit [6:0] f7, bit [6:0] op);
      return {f7, rs2, rs1, f3, rd, op};
    endfunction
    function logic [31:0] enc_i_type(bit [4:0] rd, bit [4:0] rs1, bit [11:0] imm,
                                     bit [2:0] f3, bit [6:0] op);
      return {imm, rs1, f3, rd, op};
    endfunction
    function logic [31:0] enc_store(bit [4:0] rs1, bit [4:0] rs2, bit [11:0] imm);
      return {imm[11:5], rs2, rs1, 3'b010, imm[4:0], 7'b0100011};
    endfunction
    function logic [31:0] enc_branch(bit [4:0] rs1, bit [4:0] rs2, bit [12:0] imm);
      return {imm[12], imm[10:5], rs2, rs1, 3'b000, imm[4:1], imm[11], 7'b1100011};
    endfunction

    task body();
      int i;
      logic [31:0] instr;
      logic [31:0] cur_addr = 0;
      bit [4:0] rd, rs1, rs2;
      bit [4:0] last_rd = 0;
      int hz_dice;
      core_prediction pred;

      `uvm_info("SEQ", "Generating thesis stress program...", UVM_LOW)

      for (i = 1; i <= 5; i++) begin
        instr = enc_i_type(i[4:0], 5'b0, 12'(i*10), 3'b000, 7'b0010011);
        send_load(cur_addr, instr);
        cur_addr += 4;
      end

      for (i = 0; i < n_instr; i++) begin
        rd = $urandom_range(1, 5);
        if (($urandom_range(0, 99) < 60) && (last_rd != 0)) begin
          rs1 = last_rd;
          rs2 = $urandom_range(1, 5);
        end
        else begin
          rs1 = $urandom_range(1, 5);
          rs2 = $urandom_range(1, 5);
        end

        hz_dice = $urandom_range(0, 5);
        case (hz_dice)
          0, 1, 2: begin
            instr = enc_r_type(rd, rs1, rs2, 3'b000, 7'b0000000, 7'b0110011);
            send_load(cur_addr, instr);
            if ((rs1 == last_rd || rs2 == last_rd) && last_rd != 0) pred_alu_raw++;
            last_rd = rd;
          end
          3: begin
            instr = enc_i_type(rd, rs1, 12'b0, 3'b010, 7'b0000011); 
            send_load(cur_addr, instr);
            cur_addr += 4;
            instr = enc_r_type(rd, rd, rs2, 3'b000, 7'b0000000, 7'b0110011);
            send_load(cur_addr, instr);
            pred_load_use++;
            last_rd = rd;
          end
          4: begin
            instr = enc_branch(rs1, rs1, 13'd8);
            send_load(cur_addr, instr);
            cur_addr += 4;
            send_load(cur_addr, 32'h0000_0013); 
            pred_branch++;
          end
          5: begin
            instr = enc_store(rs1, rs2, 12'b0);
            send_load(cur_addr, instr);
            pred_store++;
          end
        endcase
        cur_addr += 4;
      end

      send_load(cur_addr, 32'h0000_006f);

      `uvm_info("SEQ", $sformatf(
        "Predict: ALU-RAW=%0d LOAD-USE=%0d BRANCH=%0d STORE=%0d",
        pred_alu_raw, pred_load_use, pred_branch, pred_store), UVM_LOW)

      `uvm_info("SEQ", $sformatf("Entering run-cycle phase (%0d items)", n_run_cycle), UVM_LOW)
      for (int k = 0; k < n_run_cycle; k++) begin
        req = core_item::type_id::create("req");
        start_item(req);
        req.is_load_mode = 0;
        req.imem_delay   = $urandom_range(0, 1);
        req.dmem_delay   = $urandom_range(0, 1);
        finish_item(req);
        if ((k+1) % 50 == 0)
          `uvm_info("SEQ", $sformatf("Run-cycle progress: %0d/%0d @ %0t",
                    k+1, n_run_cycle, $time), UVM_LOW)
      end
      `uvm_info("SEQ", "Run-cycle phase done", UVM_LOW)
    endtask

    task send_load(logic [31:0] addr, logic [31:0] val);
      req = core_item::type_id::create("req");
      start_item(req);
      req.is_load_mode = 1;
      req.load_addr    = addr;
      req.load_instr   = val;
      finish_item(req);
    endtask
  endclass

  //----------------------------------------------------------------------
  // Golden
  //----------------------------------------------------------------------
  class core_golden extends uvm_component;
    `uvm_component_utils(core_golden)
    core_prediction pred;
    bit             have_pred = 0;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void set_pred(core_prediction p);
      pred = p;
      have_pred = 1;
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Monitor globals
  //----------------------------------------------------------------------
  int unsigned obs_stalls   = 0;
  int unsigned obs_flushes  = 0;
  int unsigned obs_loads    = 0;
  int unsigned obs_stores   = 0;
  int unsigned obs_wb       = 0;
  int unsigned obs_fwd_ex   = 0;
  int unsigned obs_fwd_mem  = 0;

  //----------------------------------------------------------------------
  // Scoreboard
  //----------------------------------------------------------------------
  class core_scoreboard extends uvm_component;
    `uvm_component_utils(core_scoreboard)
    core_golden gld_h;

    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void final_check();
      bit             ok_stall, ok_flush, ok_store;
      string          s_stall, s_flush, s_store;
      core_prediction p;

      if (gld_h == null || !gld_h.have_pred) begin
        `uvm_error("SCB", "Golden has no prediction available")
        return;
      end
      p = gld_h.pred;

      ok_stall = (obs_stalls >= p.load_use_cnt) && (obs_stalls <= p.load_use_cnt + 10);
      s_stall  = $sformatf("stalls=%0d (need [%0d, %0d])",
                           obs_stalls, p.load_use_cnt, p.load_use_cnt + 10);

      ok_flush = (obs_flushes >= 2 * p.branch_cnt);
      s_flush  = $sformatf("flushes=%0d (need >= 2*branch=%0d)",
                           obs_flushes, 2 * p.branch_cnt);

      ok_store = (obs_stores >= p.store_cnt) && (obs_stores <= p.store_cnt + 5);
      s_store  = $sformatf("stores=%0d (need [%0d, %0d])",
                           obs_stores, p.store_cnt, p.store_cnt + 5);

      tb_thesis_pkg::test_begin("Stress hazard accounting (golden vs DUT)");
      tb_thesis_pkg::stim($sformatf(
        "instr=%0d  predicted: ALU-RAW=%0d LOAD-USE=%0d BRANCH=%0d STORE=%0d",
        p.alu_raw_cnt + p.load_use_cnt + p.branch_cnt + p.store_cnt,
        p.alu_raw_cnt, p.load_use_cnt, p.branch_cnt, p.store_cnt));

      void'(tb_thesis_pkg::check(ok_stall, "stalls in [load_use, load_use+10]", s_stall));
      void'(tb_thesis_pkg::check(ok_flush, "flushes >= 2*branch", s_flush));
      void'(tb_thesis_pkg::check(ok_store, "stores in [injected, injected+5]", s_store));
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Coverage
  //----------------------------------------------------------------------
  class core_coverage extends uvm_component;
    `uvm_component_utils(core_coverage)
    tb_thesis_pkg::manual_cov mc;

    function new(string n, uvm_component p);
      super.new(n, p);
      mc = new("core");
      mc.add_bin("hz_alu_raw");  mc.add_bin("hz_load_use");
      mc.add_bin("hz_branch");   mc.add_bin("hz_store");
      mc.add_bin("ev_stall");    mc.add_bin("ev_flush");
      mc.add_bin("ev_load");     mc.add_bin("ev_store_actual");
      mc.add_bin("ev_wb");       mc.add_bin("ev_fwd_ex");
      mc.add_bin("ev_fwd_mem");
    endfunction

    function void final_sample(core_prediction p);
      if (p.alu_raw_cnt   > 0) mc.hit_bin("hz_alu_raw");
      if (p.load_use_cnt  > 0) mc.hit_bin("hz_load_use");
      if (p.branch_cnt    > 0) mc.hit_bin("hz_branch");
      if (p.store_cnt     > 0) mc.hit_bin("hz_store");
      if (obs_stalls      > 0) mc.hit_bin("ev_stall");
      if (obs_flushes     > 0) mc.hit_bin("ev_flush");
      if (obs_loads       > 0) mc.hit_bin("ev_load");
      if (obs_stores      > 0) mc.hit_bin("ev_store_actual");
      if (obs_wb          > 0) mc.hit_bin("ev_wb");
      if (obs_fwd_ex      > 0) mc.hit_bin("ev_fwd_ex");
      if (obs_fwd_mem     > 0) mc.hit_bin("ev_fwd_mem");
    endfunction

    function void report_phase(uvm_phase phase);
      mc.report();
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Agent / Env / Test
  //----------------------------------------------------------------------
  class core_agent extends uvm_agent;
    `uvm_component_utils(core_agent)
    core_driver drv;
    uvm_sequencer #(core_item) sqr;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = core_driver::type_id::create("drv", this);
      sqr = uvm_sequencer#(core_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class core_env extends uvm_env;
    `uvm_component_utils(core_env)
    core_agent      agent;
    core_golden     gld;
    core_scoreboard scb;
    core_coverage   cov;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = core_agent     ::type_id::create("agent", this);
      gld   = core_golden    ::type_id::create("gld",   this);
      scb   = core_scoreboard::type_id::create("scb",   this);
      cov   = core_coverage  ::type_id::create("cov",   this);
    endfunction
    function void connect_phase(uvm_phase phase);
      scb.gld_h = gld;
    endfunction
  endclass

  class core_thesis_test extends uvm_test;
    `uvm_component_utils(core_thesis_test)
    core_env        env;
    core_stress_seq seq;

    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = core_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      core_prediction pred;
      seq = core_stress_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      pred = core_prediction::type_id::create("pred");
      pred.alu_raw_cnt   = seq.pred_alu_raw;
      pred.load_use_cnt  = seq.pred_load_use;
      pred.branch_cnt    = seq.pred_branch;
      pred.store_cnt     = seq.pred_store;
      env.gld.set_pred(pred);
      phase.drop_objection(this);
    endtask

    function void extract_phase(uvm_phase phase);
      env.scb.final_check();
      if (env.gld.have_pred) env.cov.final_sample(env.gld.pred);
    endfunction

    function void report_phase(uvm_phase phase);
      core_prediction p;
      if (env.gld.have_pred) begin
        p = env.gld.pred;
        $display("[BANG1] instr=%0d ALU_RAW=%0d LOAD_USE=%0d BRANCH=%0d STORE=%0d STALLS=%0d FLUSHES=%0d LOADS=%0d STORES=%0d WB=%0d FWD_EX=%0d FWD_MEM=%0d",
                 p.alu_raw_cnt + p.load_use_cnt + p.branch_cnt + p.store_cnt,
                 p.alu_raw_cnt, p.load_use_cnt, p.branch_cnt, p.store_cnt,
                 obs_stalls, obs_flushes, obs_loads, obs_stores, obs_wb,
                 obs_fwd_ex, obs_fwd_mem);
      end
      tb_thesis_pkg::summary();
    endfunction
  endclass

endpackage : core_thesis_pkg

//------------------------------------------------------------------------------
// Top module
//------------------------------------------------------------------------------
module tb_top;
  import uvm_pkg::*;
  import tb_thesis_pkg::*;
  import core_thesis_pkg::*;

  logic [7:0] tb_test_id;
  logic       tb_check_pass;

  bit clk = 0;
  always #5 clk = ~clk;

  core_thesis_if vif(clk);

  `THESIS_WAVE_HOOK(clk)

  // Thay vì riscv_core thì dùng soc_without_mem
  soc_without_mem dut (
    .clk_i            (clk),
    .rst_i            (vif.rst_i),
    
    // Interrupts
    .irq_sw_i         (vif.irq_sw_i),
    .irq_timer_i      (vif.irq_timer_i),
    .irq_ext_i        (vif.irq_ext_i),

    // IMEM -> Giao tiếp IF
    .if_req_valid_o   (vif.if_req_valid_o),
    .if_req_addr_o    (vif.if_req_addr_o),
    .if_req_ready_i   (vif.if_req_ready_i),
    .if_rsp_valid_i   (vif.if_rsp_valid_i),
    .if_rsp_instr_i   (vif.if_rsp_instr_i),
    .if_rsp_ready_o   (vif.if_rsp_ready_o),

    // DMEM -> Giao tiếp DMEM
    .dmem_req_valid_o (vif.dmem_req_valid_o),
    .dmem_req_ready_i (vif.dmem_req_ready_i),
    .dmem_addr_o      (vif.dmem_addr_o),
    .dmem_wdata_o     (vif.dmem_wdata_o),
    .dmem_be_o        (vif.dmem_be_o),
    .dmem_we_o        (vif.dmem_we_o),
    .dmem_rsp_valid_i (vif.dmem_rsp_valid_i),
    .dmem_rsp_ready_o (vif.dmem_rsp_ready_o),
    .dmem_rdata_i     (vif.dmem_rdata_i),
    .dmem_err_i       (vif.dmem_err_i)
  );

  // ---- Observation: count DUT events post-reset using hierarchical refs ----
  always @(negedge clk) begin
    if (!vif.rst_i) begin
      if (dut.ctrl_force_stall_id) core_thesis_pkg::obs_stalls++;
      if (dut.ctrl_flush_id_ex)    core_thesis_pkg::obs_flushes++;
      
      // Load/Store events based on new DMEM request interface
      if (vif.dmem_req_valid_o && vif.dmem_req_ready_i &&  vif.dmem_we_o)
        core_thesis_pkg::obs_stores++;
      if (vif.dmem_req_valid_o && vif.dmem_req_ready_i && !vif.dmem_we_o)
        core_thesis_pkg::obs_loads++;
        
      // WB tracking since dbg_wb_we is gone (Hook into internal net)
      if (dut.hz_wb_reg_we && dut.hz_wb_rd_addr != 5'b0)
        core_thesis_pkg::obs_wb++;
        
      if (dut.ctrl_fwd_rs1_sel == 2'b01 || dut.ctrl_fwd_rs2_sel == 2'b01)
        core_thesis_pkg::obs_fwd_ex++;
      if (dut.ctrl_fwd_rs1_sel == 2'b10 || dut.ctrl_fwd_rs2_sel == 2'b10)
        core_thesis_pkg::obs_fwd_mem++;
    end
  end

  // ---- SVA: bind to core control signals ----
  wire rst_n = !vif.rst_i;
  `THESIS_ASSERT_NO_X (stall_sig,  clk, rst_n, dut.ctrl_force_stall_id)
  `THESIS_ASSERT_NO_X (flush_sig,  clk, rst_n, dut.ctrl_flush_id_ex)
  `THESIS_ASSERT_NO_X (fwd_rs1,    clk, rst_n, dut.ctrl_fwd_rs1_sel)
  `THESIS_ASSERT_NO_X (fwd_rs2,    clk, rst_n, dut.ctrl_fwd_rs2_sel)

  initial begin
    tb_thesis_pkg::header("tb_core_riscv_thesis", "5.4", "Bang_1");
    uvm_config_db#(virtual core_thesis_if)::set(null, "*", "vif", vif);
    run_test("core_thesis_test");
  end

  // Hard timeout
  initial begin
    #2ms;
    $display("[TIMEOUT] tb_core_riscv_thesis hit hard cap (2ms). Aborting.");
    $finish;
  end

  // Wave dump
  initial begin
    $dumpfile("vsim.wlf");
    $dumpvars(0, tb_top);
  end

endmodule