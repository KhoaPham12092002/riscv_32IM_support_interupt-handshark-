//==============================================================================
// tb_fwd_thesis.sv  —  Thesis Section 5.3.1 → Hình 5.5
//
// Forwarding-unit unit testbench.
//   - 9 directed seed cases guarantee all corner cases:
//       rs1/rs2 EX hazard, rs1/rs2 MEM hazard, double hazard priority,
//       x0 filtering, and no-hazard.
//   - Remaining transactions are weighted dice-random using $urandom % 100
//     via tb_thesis_pkg::dice_pct (no randomize()).
//   - Scoreboard is independent from golden model (2 FIFOs).
//   - Coverage is manual_cov (license-free), no covergroup.
//==============================================================================
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "common/tb_thesis_pkg.sv"
`include "common/tb_thesis_checker.sv"
`include "common/tb_thesis_sva.svh"

//------------------------------------------------------------------------------
// Interface
//------------------------------------------------------------------------------
interface fwd_thesis_if(input logic clk);
  logic [4:0] rs1_addr_ex;
  logic [4:0] rs2_addr_ex;
  logic [4:0] rd_addr_mem;
  logic       rf_we_mem;
  logic [4:0] rd_addr_wb;
  logic       rf_we_wb;
  logic [1:0] ctrl_fwd_rs1_sel_o;
  logic [1:0] ctrl_fwd_rs2_sel_o;
endinterface

package fwd_thesis_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import tb_thesis_pkg::*;
  import tb_thesis_checker_pkg::*;

  //----------------------------------------------------------------------
  // Item
  //----------------------------------------------------------------------
  class fwd_item extends thesis_txn;
    logic [4:0] rs1_ex;
    logic [4:0] rs2_ex;
    logic [4:0] rd_mem;
    logic       we_mem;
    logic [4:0] rd_wb;
    logic       we_wb;
    logic [1:0] act_fwd_a;
    logic [1:0] act_fwd_b;
    logic [1:0] exp_fwd_a;
    logic [1:0] exp_fwd_b;

    `uvm_object_utils_begin(fwd_item)
      `uvm_field_int   (test_id,    UVM_DEFAULT)
      `uvm_field_string(label,      UVM_DEFAULT)
      `uvm_field_int   (rs1_ex,     UVM_DEFAULT)
      `uvm_field_int   (rs2_ex,     UVM_DEFAULT)
      `uvm_field_int   (rd_mem,     UVM_DEFAULT)
      `uvm_field_int   (we_mem,     UVM_DEFAULT)
      `uvm_field_int   (rd_wb,      UVM_DEFAULT)
      `uvm_field_int   (we_wb,      UVM_DEFAULT)
      `uvm_field_int   (act_fwd_a,  UVM_DEFAULT)
      `uvm_field_int   (act_fwd_b,  UVM_DEFAULT)
      `uvm_field_int   (exp_fwd_a,  UVM_DEFAULT)
      `uvm_field_int   (exp_fwd_b,  UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name="fwd_item");
      super.new(name);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Helpers
  //----------------------------------------------------------------------
  function automatic logic [4:0] pick_reg(int lo = 1, int hi = 31);
    return logic'( $urandom_range(lo, hi) );
  endfunction

  function automatic logic [4:0] pick_other(logic [4:0] avoid, int lo = 1, int hi = 31);
    logic [4:0] v;
    do begin
      v = logic'( $urandom_range(lo, hi) );
    end while (v == avoid);
    return v;
  endfunction

  //----------------------------------------------------------------------
  // Directed/random stimulus sequence
  //----------------------------------------------------------------------
  class fwd_stress_seq extends uvm_sequence #(fwd_item);
    `uvm_object_utils(fwd_stress_seq)

    int unsigned n_random = 91; // 9 directed + 91 random = 100 total

    function new(string name="");
      super.new(name);
    endfunction

    task body();
      int unsigned id = 1;
      string mode;
      tb_thesis_pkg::dice_pct dice;

      dice = new("fwd_dice");
      dice.add("RS1_EX", 20);
      dice.add("RS1_MEM", 20);
      dice.add("RS2_EX", 20);
      dice.add("RS2_MEM", 20);
      dice.add("DOUBLE", 10);
      dice.add("X0", 5);
      dice.add("NONE", 5);

      // 9 directed seed cases: guarantee all corner cases are hit.
      send_case(id++, "RS1 EX hazard", 5'd3, 5'd11, 5'd3, 1'b1, 5'd8, 1'b1);
      send_case(id++, "RS1 MEM hazard", 5'd4, 5'd12, 5'd9, 1'b1, 5'd4, 1'b1);
      send_case(id++, "RS2 EX hazard", 5'd12, 5'd6, 5'd6, 1'b1, 5'd9, 1'b1);
      send_case(id++, "RS2 MEM hazard", 5'd12, 5'd7, 5'd8, 1'b1, 5'd7, 1'b1);
      send_case(id++, "DOUBLE hazard priority", 5'd5, 5'd5, 5'd5, 1'b1, 5'd5, 1'b1);
      send_case(id++, "x0 filtered", 5'd0, 5'd0, 5'd0, 1'b1, 5'd0, 1'b1);
      send_case(id++, "No hazard", 5'd1, 5'd2, 5'd21, 1'b1, 5'd22, 1'b1);
      send_case(id++, "RS1 EX we_mem=0 (no fwd)", 5'd3, 5'd9, 5'd3, 1'b0, 5'd8, 1'b1);
      send_case(id++, "RS1 WB we_wb=0 (no fwd)", 5'd4, 5'd9, 5'd8, 1'b1, 5'd4, 1'b0);

      // Weighted stress run.
      repeat (n_random) begin
        logic [4:0] rs1;
        logic [4:0] rs2;
        logic [4:0] rd_mem;
        logic [4:0] rd_wb;
        mode = dice.roll();

        if (mode == "RS1_EX") begin
          rs1    = pick_reg(1, 10);
          rs2    = pick_reg(11, 20);
          rd_mem = rs1;
          rd_wb  = pick_reg(21, 29);
          send_case(id, $sformatf("RAND %0d RS1_EX", id), rs1, rs2, rd_mem, 1'b1, rd_wb, 1'b1);
        end
        else if (mode == "RS1_MEM") begin
          rs1    = pick_reg(1, 10);
          rs2    = pick_reg(11, 20);
          rd_mem = pick_reg(21, 29);
          rd_wb  = rs1;
          send_case(id, $sformatf("RAND %0d RS1_MEM", id), rs1, rs2, rd_mem, 1'b1, rd_wb, 1'b1);
        end
        else if (mode == "RS2_EX") begin
          rs1    = pick_reg(11, 20);
          rs2    = pick_reg(1, 10);
          rd_mem = rs2;
          rd_wb  = pick_reg(21, 29);
          send_case(id, $sformatf("RAND %0d RS2_EX", id), rs1, rs2, rd_mem, 1'b1, rd_wb, 1'b1);
        end
        else if (mode == "RS2_MEM") begin
          rs1    = pick_reg(11, 20);
          rs2    = pick_reg(1, 10);
          rd_mem = pick_reg(21, 29);
          rd_wb  = rs2;
          send_case(id, $sformatf("RAND %0d RS2_MEM", id), rs1, rs2, rd_mem, 1'b1, rd_wb, 1'b1);
        end
        else if (mode == "DOUBLE") begin
          rs1    = pick_reg(1, 10);
          rs2    = rs1;
          rd_mem = rs1;
          rd_wb  = rs1;
          send_case(id, $sformatf("RAND %0d DOUBLE", id), rs1, rs2, rd_mem, 1'b1, rd_wb, 1'b1);
        end
        else if (mode == "X0") begin
          send_case(id, $sformatf("RAND %0d X0", id), 5'd0, 5'd0, 5'd0, 1'b1, 5'd0, 1'b1);
        end
        else begin
          rs1    = pick_reg(1, 10);
          rs2    = pick_reg(11, 20);
          rd_mem = pick_reg(21, 29);
          rd_wb  = pick_reg(30, 31);
          send_case(id, $sformatf("RAND %0d NONE", id), rs1, rs2, rd_mem, 1'b1, rd_wb, 1'b1);
        end
        id++;
      end
    endtask

    task send_case(int unsigned id, string lbl,
                   logic [4:0] rs1, logic [4:0] rs2,
                   logic [4:0] rd_mem, logic we_mem,
                   logic [4:0] rd_wb,  logic we_wb);
      fwd_item it = fwd_item::type_id::create("it");
      start_item(it);
      it.test_id = id;
      it.label   = lbl;
      it.rs1_ex  = rs1;
      it.rs2_ex  = rs2;
      it.rd_mem  = rd_mem;
      it.we_mem  = we_mem;
      it.rd_wb   = rd_wb;
      it.we_wb   = we_wb;
      finish_item(it);
    endtask
  endclass

  //----------------------------------------------------------------------
  // Driver — drive one transaction per clock.
  //----------------------------------------------------------------------
  class fwd_driver extends uvm_driver #(fwd_item);
    `uvm_component_utils(fwd_driver)
    virtual fwd_thesis_if vif;
    mailbox #(fwd_item) inflight;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual fwd_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      vif.rs1_addr_ex <= '0;
      vif.rs2_addr_ex <= '0;
      vif.rd_addr_mem  <= '0;
      vif.rf_we_mem    <= 1'b0;
      vif.rd_addr_wb   <= '0;
      vif.rf_we_wb     <= 1'b0;
      @(posedge vif.clk);

      forever begin
        seq_item_port.get_next_item(req);
        if (inflight != null) inflight.put(req);
        //@(posedge vif.clk);
        vif.rs1_addr_ex <= req.rs1_ex;
        vif.rs2_addr_ex <= req.rs2_ex;
        vif.rd_addr_mem  <= req.rd_mem;
        vif.rf_we_mem    <= req.we_mem;
        vif.rd_addr_wb   <= req.rd_wb;
        vif.rf_we_wb     <= req.we_wb;
        @(posedge vif.clk);
        seq_item_port.item_done();
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // Monitor — capture inputs and combinational outputs after settle.
  //----------------------------------------------------------------------
  class fwd_monitor extends uvm_monitor;
    `uvm_component_utils(fwd_monitor)
    virtual fwd_thesis_if vif;
    uvm_analysis_port #(fwd_item) ap_dut;
    uvm_analysis_port #(fwd_item) ap_gld;
    mailbox #(fwd_item) inflight;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap_dut = new("ap_dut", this);
      ap_gld = new("ap_gld", this);
      if (!uvm_config_db#(virtual fwd_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      fwd_item pkt;
      fwd_item meta;
      forever begin
        if (inflight != null) inflight.get(meta);
        @(negedge vif.clk);
        #1;
        pkt = fwd_item::type_id::create("pkt");
        pkt.copy(meta);
        pkt.act_fwd_a = vif.ctrl_fwd_rs1_sel_o;
        pkt.act_fwd_b = vif.ctrl_fwd_rs2_sel_o;
        ap_dut.write(pkt);
        ap_gld.write(pkt);
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // Golden model — independent subscriber.
  //----------------------------------------------------------------------
  class fwd_golden extends uvm_subscriber #(fwd_item);
    `uvm_component_utils(fwd_golden)
    uvm_analysis_port #(fwd_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
    endfunction

    function logic [1:0] predict_sel(logic [4:0] rs,
                                     logic [4:0] rd_mem, logic we_mem,
                                     logic [4:0] rd_wb,  logic we_wb);
      if (we_mem && (rd_mem != 5'd0) && (rd_mem == rs)) begin
        return 2'b01;
      end
      else if (we_wb && (rd_wb != 5'd0) && (rd_wb == rs)) begin
        return 2'b10;
      end
      return 2'b00;
    endfunction

    function void write(fwd_item t);
      fwd_item g = fwd_item::type_id::create("gld");
      g.copy(t);
      g.exp_fwd_a = predict_sel(t.rs1_ex, t.rd_mem, t.we_mem, t.rd_wb, t.we_wb);
      g.exp_fwd_b = predict_sel(t.rs2_ex, t.rd_mem, t.we_mem, t.rd_wb, t.we_wb);
      ap.write(g);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Coverage — manual_cov bins only.
  //----------------------------------------------------------------------
  class fwd_coverage extends uvm_subscriber #(fwd_item);
    `uvm_component_utils(fwd_coverage)
    tb_thesis_pkg::manual_cov mc;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      mc = new("fwd");
      mc.add_bin("rs1_sel_00"); mc.add_bin("rs1_sel_01"); mc.add_bin("rs1_sel_10");
      mc.add_bin("rs2_sel_00"); mc.add_bin("rs2_sel_01"); mc.add_bin("rs2_sel_10");
      mc.add_bin("in_double");
      mc.add_bin("in_x0");
      mc.add_bin("in_none");
    endfunction

    function void write(fwd_item t);
      case (t.act_fwd_a)
        2'b00: mc.hit_bin("rs1_sel_00");
        2'b01: mc.hit_bin("rs1_sel_01");
        2'b10: mc.hit_bin("rs1_sel_10");
        default: ;
      endcase
      case (t.act_fwd_b)
        2'b00: mc.hit_bin("rs2_sel_00");
        2'b01: mc.hit_bin("rs2_sel_01");
        2'b10: mc.hit_bin("rs2_sel_10");
        default: ;
      endcase

      if ((t.rs1_ex == 5'd0) && (t.rs2_ex == 5'd0) && (t.rd_mem == 5'd0) && (t.rd_wb == 5'd0)) begin
        mc.hit_bin("in_x0");
      end
      else if ((t.we_mem && t.we_wb) && (t.rd_mem != 5'd0) && (t.rd_mem == t.rd_wb) &&
               (t.rd_mem == t.rs1_ex) && (t.rd_mem == t.rs2_ex) &&
               (t.act_fwd_a == 2'b01) && (t.act_fwd_b == 2'b01)) begin
        mc.hit_bin("in_double");
      end
      else if ((t.act_fwd_a == 2'b00) && (t.act_fwd_b == 2'b00)) begin
        mc.hit_bin("in_none");
      end
    endfunction

    function void report_phase(uvm_phase phase);
      mc.report();
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Scoreboard — independent from golden, uses the thesis base.
  //----------------------------------------------------------------------
  class fwd_scoreboard extends thesis_scoreboard_base #(fwd_item);
    `uvm_component_utils(fwd_scoreboard)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      fwd_item dut_t, gld_t;
      forever begin
        fork
          dut_fifo.get(dut_t);
          gld_fifo.get(gld_t);
        join
        if (compare_txn(dut_t, gld_t)) matched++; else mismatched++;
      end
    endtask

    virtual function bit compare_txn(fwd_item dut_t, fwd_item gld_t);
      bit ok;
      tb_thesis_pkg::test_begin(dut_t.label);
      tb_thesis_pkg::stim($sformatf(
        "rs1=%0d rs2=%0d rd_mem=%0d we_mem=%0b rd_wb=%0d we_wb=%0b",
        dut_t.rs1_ex, dut_t.rs2_ex, dut_t.rd_mem, dut_t.we_mem, dut_t.rd_wb, dut_t.we_wb));
      ok = (dut_t.test_id == gld_t.test_id) &&
           (dut_t.label   == gld_t.label)   &&
           (dut_t.rs1_ex  == gld_t.rs1_ex)  &&
           (dut_t.rs2_ex  == gld_t.rs2_ex)  &&
           (dut_t.rd_mem  == gld_t.rd_mem)  &&
           (dut_t.we_mem  == gld_t.we_mem)  &&
           (dut_t.rd_wb   == gld_t.rd_wb)   &&
           (dut_t.we_wb   == gld_t.we_wb)   &&
           (dut_t.act_fwd_a === gld_t.exp_fwd_a) &&
           (dut_t.act_fwd_b === gld_t.exp_fwd_b);
      return tb_thesis_pkg::check(
        ok,
        $sformatf("fwd_a=%02b fwd_b=%02b", gld_t.exp_fwd_a, gld_t.exp_fwd_b),
        $sformatf("fwd_a=%02b fwd_b=%02b", dut_t.act_fwd_a, dut_t.act_fwd_b));
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Agent / Env / Test
  //----------------------------------------------------------------------
  class fwd_agent extends uvm_agent;
    `uvm_component_utils(fwd_agent)
    fwd_driver  drv;
    fwd_monitor mon;
    uvm_sequencer #(fwd_item) sqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = fwd_driver ::type_id::create("drv", this);
      mon = fwd_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(fwd_item)::type_id::create("sqr", this);
      drv.inflight = new();
      mon.inflight = drv.inflight;
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class fwd_env extends uvm_env;
    `uvm_component_utils(fwd_env)
    fwd_agent      agent;
    fwd_golden     gld;
    fwd_coverage   cov;
    fwd_scoreboard scb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = fwd_agent     ::type_id::create("agent", this);
      gld   = fwd_golden    ::type_id::create("gld",   this);
      cov   = fwd_coverage  ::type_id::create("cov",   this);
      scb   = fwd_scoreboard ::type_id::create("scb",   this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap_dut.connect(scb.dut_fifo.analysis_export);
      agent.mon.ap_dut.connect(cov.analysis_export);
      agent.mon.ap_gld.connect(gld.analysis_export);
      gld.ap.connect(scb.gld_fifo.analysis_export);
    endfunction
  endclass

  class fwd_test extends uvm_test;
    `uvm_component_utils(fwd_test)
    fwd_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = fwd_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      fwd_stress_seq seq = fwd_stress_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      #20;
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      tb_thesis_pkg::summary();
    endfunction
  endclass

endpackage : fwd_thesis_pkg

//------------------------------------------------------------------------------
// Top module
//------------------------------------------------------------------------------
module tb_top;
  import uvm_pkg::*;
  import tb_thesis_pkg::*;
  import fwd_thesis_pkg::*;

  logic [7:0] tb_test_id;
  logic       tb_check_pass;
  logic clk = 0;
  always #5 clk = ~clk;

  fwd_thesis_if vif(clk);

  `THESIS_WAVE_HOOK(clk)

  forwarding_unit dut (
    .hz_ex_rs1_addr_i   (vif.rs1_addr_ex),
    .hz_ex_rs2_addr_i   (vif.rs2_addr_ex),
    .hz_mem_rd_addr_i   (vif.rd_addr_mem),
    .hz_mem_reg_we_i    (vif.rf_we_mem),
    .hz_wb_rd_addr_i    (vif.rd_addr_wb),
    .hz_wb_reg_we_i     (vif.rf_we_wb),
    .ctrl_fwd_rs1_sel_o (vif.ctrl_fwd_rs1_sel_o),
    .ctrl_fwd_rs2_sel_o (vif.ctrl_fwd_rs2_sel_o)
  );

  // SVA — combinational outputs should always be known and legal.
  `THESIS_ASSERT_NO_X     (fwd_rs1, clk, 1'b1, vif.ctrl_fwd_rs1_sel_o)
  `THESIS_ASSERT_NO_X     (fwd_rs2, clk, 1'b1, vif.ctrl_fwd_rs2_sel_o)
  `THESIS_ASSERT_ONEHOT0   (fwd_rs1, clk, 1'b1, vif.ctrl_fwd_rs1_sel_o)
  `THESIS_ASSERT_ONEHOT0   (fwd_rs2, clk, 1'b1, vif.ctrl_fwd_rs2_sel_o)

  initial begin
    vif.rs1_addr_ex = '0;
    vif.rs2_addr_ex = '0;
    vif.rd_addr_mem  = '0;
    vif.rf_we_mem    = 1'b0;
    vif.rd_addr_wb   = '0;
    vif.rf_we_wb     = 1'b0;
    tb_thesis_pkg::header("tb_fwd_thesis", "5.3.1", "5.5");
    uvm_config_db#(virtual fwd_thesis_if)::set(null, "*", "vif", vif);
    run_test("fwd_test");
  end

  initial begin
    $dumpfile("vsim.wlf");
    $dumpvars(0, tb_top);
  end
endmodule
