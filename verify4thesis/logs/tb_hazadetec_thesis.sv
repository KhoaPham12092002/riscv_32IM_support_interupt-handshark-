//==============================================================================
// tb_hazadetec_thesis.sv  —  Thesis Section 5.3.2 → Hình 5.6
//
// Hazard-detection-unit unit testbench.
//   - 10 directed cases cover: load-use rs1, load-use rs2, branch/jump flush,
//     jump priority over load-use, x0 filter, we=0 filter, WB_ALU filter,
//     rs1-only match, rs2-only match, no hazard.
//   - 90 dice-random cases (25% LU_RS1, 25% LU_RS2, 20% JUMP, 15% NONE, 15% CORNER).
//   - Golden model predicts stall/flush_if_id/flush_id_ex independently.
//   - Coverage: manual_cov (license-free), 9 bins.
//   - SVA: no-X on all 3 outputs.
//==============================================================================
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "common/tb_thesis_pkg.sv"
`include "common/tb_thesis_checker.sv"
`include "common/tb_thesis_sva.svh"

//------------------------------------------------------------------------------
// Interface — wb_sel_ex uses logic [2:0] to avoid package dependency here.
// tb_top casts to wb_sel_e when wiring DUT.
//------------------------------------------------------------------------------
interface hz_thesis_if(input logic clk);
  logic [4:0] rs1_id;
  logic [4:0] rs2_id;
  logic [4:0] rd_ex;
  logic       we_ex;
  logic [2:0] wb_sel_ex;   // WB_ALU=000, WB_MEM=001, WB_PC_PLUS4=010, WB_CSR=011
  logic       jump_trap;
  logic       stall_id_o;
  logic       flush_if_id_o;
  logic       flush_id_ex_o;
endinterface

package hz_thesis_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import tb_thesis_pkg::*;
  import tb_thesis_checker_pkg::*;

  // WB_MEM encoding (matches riscv_32im_pkg.sv: WB_MEM = 3'b001)
  localparam logic [2:0] WB_ALU      = 3'b000;
  localparam logic [2:0] WB_MEM      = 3'b001;
  localparam logic [2:0] WB_PC_PLUS4 = 3'b010;
  localparam logic [2:0] WB_CSR      = 3'b011;

  //----------------------------------------------------------------------
  // Item
  //----------------------------------------------------------------------
  class hz_item extends thesis_txn;
    logic [4:0] rs1_id, rs2_id;
    logic [4:0] rd_ex;
    logic       we_ex;
    logic [2:0] wb_sel_ex;
    logic       jump_trap;
    // DUT outputs
    logic act_stall, act_flush_if_id, act_flush_id_ex;
    // Golden expected
    logic exp_stall, exp_flush_if_id, exp_flush_id_ex;

    `uvm_object_utils_begin(hz_item)
      `uvm_field_int   (test_id,        UVM_DEFAULT)
      `uvm_field_string(label,          UVM_DEFAULT)
      `uvm_field_int   (rs1_id,         UVM_DEFAULT)
      `uvm_field_int   (rs2_id,         UVM_DEFAULT)
      `uvm_field_int   (rd_ex,          UVM_DEFAULT)
      `uvm_field_int   (we_ex,          UVM_DEFAULT)
      `uvm_field_int   (wb_sel_ex,      UVM_DEFAULT)
      `uvm_field_int   (jump_trap,      UVM_DEFAULT)
      `uvm_field_int   (act_stall,      UVM_DEFAULT)
      `uvm_field_int   (act_flush_if_id, UVM_DEFAULT)
      `uvm_field_int   (act_flush_id_ex, UVM_DEFAULT)
      `uvm_field_int   (exp_stall,      UVM_DEFAULT)
      `uvm_field_int   (exp_flush_if_id, UVM_DEFAULT)
      `uvm_field_int   (exp_flush_id_ex, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name="hz_item");
      super.new(name);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Stimulus sequence — 10 directed + 90 random = 100 total
  //----------------------------------------------------------------------
  class hz_stress_seq extends uvm_sequence #(hz_item);
    `uvm_object_utils(hz_stress_seq)

    int unsigned n_random = 90;

    function new(string name="");
      super.new(name);
    endfunction

    task body();
      int unsigned id = 1;
      string mode;
      tb_thesis_pkg::dice_pct dice;

      dice = new("hz_dice");
      dice.add("LOAD_USE_RS1", 25);
      dice.add("LOAD_USE_RS2", 25);
      dice.add("JUMP",         20);
      dice.add("NO_HAZARD",    15);
      dice.add("CORNER",       15);

      // 10 directed cases
      // 1. Load-use: rs1 match
      send_case(id++, "LU stall rs1",          5'd3, 5'd9,  5'd3, 1'b1, WB_MEM,      1'b0);
      // 2. Load-use: rs2 match
      send_case(id++, "LU stall rs2",          5'd9, 5'd5,  5'd5, 1'b1, WB_MEM,      1'b0);
      // 3. Branch/jump flush (no load-use)
      send_case(id++, "Branch flush",          5'd1, 5'd2,  5'd8, 1'b1, WB_PC_PLUS4, 1'b1);
      // 4. Load-use + jump — jump takes priority (flush, NO stall)
      send_case(id++, "LU+Jump jump-wins",     5'd3, 5'd9,  5'd3, 1'b1, WB_MEM,      1'b1);
      // 5. x0 filter: rd=x0 never causes stall
      send_case(id++, "x0 filter",             5'd0, 5'd0,  5'd0, 1'b1, WB_MEM,      1'b0);
      // 6. we=0 filter: write-enable off → no stall
      send_case(id++, "WE=0 filter",           5'd3, 5'd9,  5'd3, 1'b0, WB_MEM,      1'b0);
      // 7. WB_ALU filter: ALU instr in EX → not a load → no stall
      send_case(id++, "WB_ALU no stall",       5'd7, 5'd9,  5'd7, 1'b1, WB_ALU,      1'b0);
      // 8. rs1-only match
      send_case(id++, "LU rs1 only",           5'd6, 5'd9,  5'd6, 1'b1, WB_MEM,      1'b0);
      // 9. rs2-only match
      send_case(id++, "LU rs2 only",           5'd9, 5'd8,  5'd8, 1'b1, WB_MEM,      1'b0);
      // 10. No hazard: registers don't overlap
      send_case(id++, "No hazard",             5'd1, 5'd2, 5'd15, 1'b1, WB_ALU,      1'b0);

      // Weighted stress
      repeat (n_random) begin
        logic [4:0] rs1, rs2, rd;
        logic [2:0] wb_sel;
        logic       we, jump;

        rs1 = logic'( $urandom_range(1, 15) );
        rs2 = logic'( $urandom_range(1, 15) );
        rd  = logic'( $urandom_range(1, 15) );
        we  = 1'b1;
        jump = 1'b0;
        mode = dice.roll();

        if (mode == "LOAD_USE_RS1") begin
          rs1 = rd;
          rs2 = logic'( $urandom_range(16, 31) );
          send_case(id, $sformatf("RAND %0d LU_RS1", id),
                    rs1, rs2, rd, 1'b1, WB_MEM, 1'b0);
        end
        else if (mode == "LOAD_USE_RS2") begin
          rs1 = logic'( $urandom_range(16, 31) );
          rs2 = rd;
          send_case(id, $sformatf("RAND %0d LU_RS2", id),
                    rs1, rs2, rd, 1'b1, WB_MEM, 1'b0);
        end
        else if (mode == "JUMP") begin
          wb_sel = logic'( $urandom_range(0, 3) );
          send_case(id, $sformatf("RAND %0d JUMP", id),
                    rs1, rs2, rd, 1'b1, wb_sel, 1'b1);
        end
        else if (mode == "NO_HAZARD") begin
          rd = logic'( $urandom_range(16, 29) );   // far from rs range 1-15
          wb_sel = logic'( $urandom_range(0, 3) );
          send_case(id, $sformatf("RAND %0d NONE", id),
                    rs1, rs2, rd, 1'b1, wb_sel, 1'b0);
        end
        else begin  // CORNER
          case ($urandom_range(0, 3))
            0: send_case(id, $sformatf("RAND %0d CRN_X0",  id),
                         5'd0, 5'd0, 5'd0, 1'b1, WB_MEM,  1'b0);
            1: send_case(id, $sformatf("RAND %0d CRN_WE0", id),
                         rs1, rs2, rs1, 1'b0, WB_MEM,  1'b0);
            2: send_case(id, $sformatf("RAND %0d CRN_ALU", id),
                         rs1, rs2, rs1, 1'b1, WB_ALU,  1'b0);
            3: send_case(id, $sformatf("RAND %0d CRN_JLU", id),
                         rs1, rs2, rs1, 1'b1, WB_MEM,  1'b1);
          endcase
        end
        id++;
      end
    endtask

    task send_case(int unsigned id, string lbl,
                   logic [4:0] rs1, logic [4:0] rs2,
                   logic [4:0] rd,  logic we,
                   logic [2:0] wb_sel, logic jump);
      hz_item it = hz_item::type_id::create("it");
      start_item(it);
      it.test_id    = id;
      it.label      = lbl;
      it.rs1_id     = rs1;
      it.rs2_id     = rs2;
      it.rd_ex      = rd;
      it.we_ex      = we;
      it.wb_sel_ex  = wb_sel;
      it.jump_trap  = jump;
      finish_item(it);
    endtask
  endclass

  //----------------------------------------------------------------------
  // Driver — combinational DUT, drive one transaction per clock.
  //----------------------------------------------------------------------
  class hz_driver extends uvm_driver #(hz_item);
    `uvm_component_utils(hz_driver)
    virtual hz_thesis_if vif;
    mailbox #(hz_item) inflight;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual hz_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      vif.rs1_id    <= '0;
      vif.rs2_id    <= '0;
      vif.rd_ex     <= '0;
      vif.we_ex     <= 1'b0;
      vif.wb_sel_ex <= 3'b000;
      vif.jump_trap <= 1'b0;
      @(posedge vif.clk);

      forever begin
        seq_item_port.get_next_item(req);
        if (inflight != null) inflight.put(req);
        //@(posedge vif.clk);
        vif.rs1_id    <= req.rs1_id;
        vif.rs2_id    <= req.rs2_id;
        vif.rd_ex     <= req.rd_ex;
        vif.we_ex     <= req.we_ex;
        vif.wb_sel_ex <= req.wb_sel_ex;
        vif.jump_trap <= req.jump_trap;
        @(posedge vif.clk);
        seq_item_port.item_done();
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // Monitor — sample combinational outputs after settle.
  //----------------------------------------------------------------------
  class hz_monitor extends uvm_monitor;
    `uvm_component_utils(hz_monitor)
    virtual hz_thesis_if vif;
    uvm_analysis_port #(hz_item) ap_dut;
    uvm_analysis_port #(hz_item) ap_gld;
    mailbox #(hz_item) inflight;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap_dut = new("ap_dut", this);
      ap_gld = new("ap_gld", this);
      if (!uvm_config_db#(virtual hz_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      hz_item pkt, meta;
      forever begin
        if (inflight != null) inflight.get(meta);
        @(negedge vif.clk);
        #1;
        pkt = hz_item::type_id::create("pkt");
        pkt.copy(meta);
        pkt.act_stall       = vif.stall_id_o;
        pkt.act_flush_if_id = vif.flush_if_id_o;
        pkt.act_flush_id_ex = vif.flush_id_ex_o;
        ap_dut.write(pkt);
        ap_gld.write(pkt);
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // Golden model — independent subscriber, predicts all 3 outputs.
  // Priority encoder mirrors hazard_unit.sv exactly:
  //   1. jump_trap → flush both pipelines, no stall
  //   2. load-use  → stall ID, flush ID/EX, no flush IF/ID
  //   3. else      → no action
  //----------------------------------------------------------------------
  class hz_golden extends uvm_subscriber #(hz_item);
    `uvm_component_utils(hz_golden)
    uvm_analysis_port #(hz_item) ap;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
    endfunction

    function void write(hz_item t);
      hz_item g = hz_item::type_id::create("gld");
      g.copy(t);
      begin
        logic is_lu;
        is_lu = (t.wb_sel_ex == WB_MEM) && (t.rd_ex != 5'd0) && t.we_ex &&
                ((t.rd_ex == t.rs1_id) || (t.rd_ex == t.rs2_id));
        if (t.jump_trap) begin
          g.exp_stall       = 1'b0;
          g.exp_flush_if_id = 1'b1;
          g.exp_flush_id_ex = 1'b1;
        end else if (is_lu) begin
          g.exp_stall       = 1'b1;
          g.exp_flush_if_id = 1'b0;
          g.exp_flush_id_ex = 1'b1;
        end else begin
          g.exp_stall       = 1'b0;
          g.exp_flush_if_id = 1'b0;
          g.exp_flush_id_ex = 1'b0;
        end
      end
      ap.write(g);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Coverage — 9 bins (manual_cov, license-free)
  //----------------------------------------------------------------------
  class hz_coverage extends uvm_subscriber #(hz_item);
    `uvm_component_utils(hz_coverage)
    tb_thesis_pkg::manual_cov mc;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      mc = new("hz");
      mc.add_bin("ev_load_use_stall");   // stall=1 observed
      mc.add_bin("ev_jump_flush");       // flush observed from jump
      mc.add_bin("ev_jump_over_lu");     // jump wins over simultaneous LU
      mc.add_bin("ev_no_hazard");        // all outputs = 0
      mc.add_bin("lu_rs1_match");        // stall triggered by rs1
      mc.add_bin("lu_rs2_match");        // stall triggered by rs2
      mc.add_bin("lu_x0_filter");        // rd=x0 — stall suppressed
      mc.add_bin("lu_we0_filter");       // we=0 — stall suppressed
      mc.add_bin("lu_wb_alu_filter");    // WB_ALU — not a load
    endfunction

    function void write(hz_item t);
      logic is_lu_cond;
      is_lu_cond = (t.wb_sel_ex == WB_MEM) && t.we_ex &&
                   ((t.rd_ex == t.rs1_id) || (t.rd_ex == t.rs2_id));

      // Corner filter bins
      if ((t.rd_ex == 5'd0) && !t.jump_trap && (t.wb_sel_ex == WB_MEM))
        mc.hit_bin("lu_x0_filter");
      else if (!t.we_ex && !t.jump_trap && (t.wb_sel_ex == WB_MEM))
        mc.hit_bin("lu_we0_filter");
      else if ((t.wb_sel_ex == WB_ALU) && !t.jump_trap)
        mc.hit_bin("lu_wb_alu_filter");

      // Event bins from DUT outputs
      if (t.act_stall && !t.act_flush_if_id)
        mc.hit_bin("ev_load_use_stall");
      if (t.act_flush_if_id && !t.act_stall)
        mc.hit_bin("ev_jump_flush");
      if (t.act_flush_if_id && t.jump_trap && is_lu_cond)
        mc.hit_bin("ev_jump_over_lu");
      if (!t.act_stall && !t.act_flush_if_id && !t.act_flush_id_ex)
        mc.hit_bin("ev_no_hazard");

      // Which register triggered the stall
      if (t.act_stall && t.rd_ex != 5'd0) begin
        if (t.rd_ex == t.rs1_id) mc.hit_bin("lu_rs1_match");
        if (t.rd_ex == t.rs2_id) mc.hit_bin("lu_rs2_match");
      end
    endfunction

    function void report_phase(uvm_phase phase);
      mc.report();
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Scoreboard — independent from golden, uses thesis base.
  //----------------------------------------------------------------------
  class hz_scoreboard extends thesis_scoreboard_base #(hz_item);
    `uvm_component_utils(hz_scoreboard)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
      hz_item dut_t, gld_t;
      forever begin
        fork
          dut_fifo.get(dut_t);
          gld_fifo.get(gld_t);
        join
        if (compare_txn(dut_t, gld_t)) matched++; else mismatched++;
      end
    endtask

    virtual function bit compare_txn(hz_item dut_t, hz_item gld_t);
      bit ok;
      tb_thesis_pkg::test_begin(dut_t.label);
      tb_thesis_pkg::stim($sformatf(
        "rs1=%0d rs2=%0d rd=%0d we=%0b wb_sel=%03b jump=%0b",
        dut_t.rs1_id, dut_t.rs2_id, dut_t.rd_ex,
        dut_t.we_ex, dut_t.wb_sel_ex, dut_t.jump_trap));
      ok = (dut_t.act_stall       === gld_t.exp_stall) &&
           (dut_t.act_flush_if_id === gld_t.exp_flush_if_id) &&
           (dut_t.act_flush_id_ex === gld_t.exp_flush_id_ex);
      return tb_thesis_pkg::check(
        ok,
        $sformatf("stall=%0b fif=%0b fidex=%0b",
                  gld_t.exp_stall, gld_t.exp_flush_if_id, gld_t.exp_flush_id_ex),
        $sformatf("stall=%0b fif=%0b fidex=%0b",
                  dut_t.act_stall, dut_t.act_flush_if_id, dut_t.act_flush_id_ex));
    endfunction

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Agent / Env / Test
  //----------------------------------------------------------------------
  class hz_agent extends uvm_agent;
    `uvm_component_utils(hz_agent)
    hz_driver  drv;
    hz_monitor mon;
    uvm_sequencer #(hz_item) sqr;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = hz_driver ::type_id::create("drv", this);
      mon = hz_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(hz_item)::type_id::create("sqr", this);
      drv.inflight = new();
      mon.inflight = drv.inflight;
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class hz_env extends uvm_env;
    `uvm_component_utils(hz_env)
    hz_agent      agent;
    hz_golden     gld;
    hz_coverage   cov;
    hz_scoreboard scb;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = hz_agent     ::type_id::create("agent", this);
      gld   = hz_golden    ::type_id::create("gld",   this);
      cov   = hz_coverage  ::type_id::create("cov",   this);
      scb   = hz_scoreboard::type_id::create("scb",   this);
    endfunction

    function void connect_phase(uvm_phase phase);
      agent.mon.ap_dut.connect(scb.dut_fifo.analysis_export);
      agent.mon.ap_dut.connect(cov.analysis_export);
      agent.mon.ap_gld.connect(gld.analysis_export);
      gld.ap.connect(scb.gld_fifo.analysis_export);
    endfunction
  endclass

  class hz_test extends uvm_test;
    `uvm_component_utils(hz_test)
    hz_env env;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = hz_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
      hz_stress_seq seq = hz_stress_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      #20;
      phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
      tb_thesis_pkg::summary();
    endfunction
  endclass

endpackage : hz_thesis_pkg

//------------------------------------------------------------------------------
// Top module
//------------------------------------------------------------------------------
module tb_top;
  import uvm_pkg::*;
  import tb_thesis_pkg::*;
  import hz_thesis_pkg::*;
  import riscv_32im_pkg::*;   // for wb_sel_e cast

  logic [7:0] tb_test_id;
  logic       tb_check_pass;
  logic clk = 0;
  always #5 clk = ~clk;

  hz_thesis_if vif(clk);

  `THESIS_WAVE_HOOK(clk)

  hazard_unit dut (
    .hz_id_rs1_addr_i       (vif.rs1_id),
    .hz_id_rs2_addr_i       (vif.rs2_id),
    .hz_ex_rd_addr_i        (vif.rd_ex),
    .hz_ex_reg_we_i         (vif.we_ex),
    .hz_ex_wb_sel_i         (wb_sel_e'(vif.wb_sel_ex)),
    .jump_trap_i            (vif.jump_trap),
    .ctrl_force_stall_id_o  (vif.stall_id_o),
    .ctrl_flush_if_id_o     (vif.flush_if_id_o),
    .ctrl_flush_id_ex_o     (vif.flush_id_ex_o)
  );

  // SVA — outputs always known (combinational, no reset needed)
  `THESIS_ASSERT_NO_X (hz_stall,     clk, 1'b1, vif.stall_id_o)
  `THESIS_ASSERT_NO_X (hz_flush_fif, clk, 1'b1, vif.flush_if_id_o)
  `THESIS_ASSERT_NO_X (hz_flush_fidx,clk, 1'b1, vif.flush_id_ex_o)

  initial begin
    vif.rs1_id    = '0;
    vif.rs2_id    = '0;
    vif.rd_ex     = '0;
    vif.we_ex     = 1'b0;
    vif.wb_sel_ex = 3'b000;
    vif.jump_trap = 1'b0;
    tb_thesis_pkg::header("tb_hazadetec_thesis", "5.3.2", "5.6");
    uvm_config_db#(virtual hz_thesis_if)::set(null, "*", "vif", vif);
    run_test("hz_test");
  end

  initial begin
    $dumpfile("vsim.wlf");
    $dumpvars(0, tb_top);
  end
endmodule
