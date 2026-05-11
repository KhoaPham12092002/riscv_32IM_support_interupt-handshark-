//==============================================================================
// tb_lsu_thesis.sv  —  Thesis Section 5.2.4 → Hình 5.4
//
// 11 directed test cases covering:
//   01..05  Load: LB sign-ext, LBU zero-ext, LH sign-ext, LHU zero-ext, LW
//   06..08  Store: SB, SH, SW (byte-enable + shift correctness)
//   09..11  Misaligned trap: LH @ odd, LW @ addr%4!=0, SH @ odd
//   (plus stress with dmem delay 1..5 cyc inside each case → handshake FSM cov)
//
// Architecture:
//   driver ──▶ DUT ──▶ monitor ──▶ scoreboard ◀── golden_model
//                                       │
//                                       ▼
//                                  cov + THESIS_CHECK
//
//   - Golden model is an INDEPENDENT uvm_subscriber (sb_gld_imp).
//   - Scoreboard receives both streams via uvm_tlm_analysis_fifo and compares.
//   - Covergroup samples on every monitored txn → reports `[COV] lsu: ...`.
//   - SVA library used: NO_X on outputs, HANDSHAKE req/gnt, FSM legality.
//==============================================================================
`timescale 1ns/1ps

`include "uvm_macros.svh"
`include "common/tb_thesis_pkg.sv"
`include "common/tb_thesis_checker.sv"
`include "common/tb_thesis_sva.svh"

//------------------------------------------------------------------------------
// Interface
//------------------------------------------------------------------------------
interface lsu_thesis_if(input logic clk);
  logic        rst_i;
  logic [31:0] addr_i, wdata_i;
  logic        lsu_we_i;
  logic [2:0]  funct3_i;
  logic        valid_i, ready_o;
  logic        valid_o, ready_i;
  logic [31:0] lsu_rdata_o;
  logic        lsu_err_o;
  logic        dmem_req_valid_o, dmem_req_ready_i;
  logic [31:0] dmem_addr_o, dmem_wdata_o;
  logic [3:0]  dmem_be_o;
  logic        dmem_we_o;
  logic        dmem_rsp_valid_i, dmem_rsp_ready_o;
  logic [31:0] dmem_rdata_i;
endinterface

//------------------------------------------------------------------------------
// Sequence item — NO `rand` (license locked). Fields populated by directed seq.
//------------------------------------------------------------------------------
package lsu_thesis_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class lsu_item extends uvm_sequence_item;
    int          test_id;
    string       label;
    logic [31:0] addr;
    logic [31:0] wdata;
    logic        we;
    logic [2:0]  funct3;
    logic [31:0] mock_mem_data;
    int unsigned dmem_delay;
    // Observed outputs (populated by monitor)
    logic [31:0] act_rdata, act_dmem_addr, act_dmem_wdata;
    logic [3:0]  act_dmem_be;
    logic        act_dmem_we, act_err;

    `uvm_object_utils_begin(lsu_item)
      `uvm_field_int   (test_id,        UVM_DEFAULT)
      `uvm_field_string(label,          UVM_DEFAULT)
      `uvm_field_int   (addr,           UVM_DEFAULT)
      `uvm_field_int   (wdata,          UVM_DEFAULT)
      `uvm_field_int   (we,             UVM_DEFAULT)
      `uvm_field_int   (funct3,         UVM_DEFAULT)
      `uvm_field_int   (mock_mem_data,  UVM_DEFAULT)
      `uvm_field_int   (act_rdata,      UVM_DEFAULT)
      `uvm_field_int   (act_err,        UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name="lsu_item"); super.new(name); endfunction
  endclass

  //----------------------------------------------------------------------
  // Directed sequence — 11 thesis test cases.
  // Dice picks dmem_delay per case (no $randomize, only $urandom_range).
  //----------------------------------------------------------------------
  class lsu_directed_seq extends uvm_sequence #(lsu_item);
    `uvm_object_utils(lsu_directed_seq)
    function new(string name="lsu_directed_seq"); super.new(name); endfunction

    task body();
      // dmem_delay hardcoded per case to guarantee all 3 delay-bucket cov
      // bins are hit (fast=1, med=2..3, slow=4..5).
      send_case( 1, "LB sign-ext, addr=0x2002 mem=0x00FF0000",
                 32'h0000_2002, 32'h0, 1'b0, 3'b000, 32'h00FF_0000, 1);
      send_case( 2, "LBU zero-ext, addr=0x2003 mem=0xFF000000",
                 32'h0000_2003, 32'h0, 1'b0, 3'b100, 32'hFF00_0000, 2);
      send_case( 3, "LH sign-ext, addr=0x2004 mem=0x0000FFFF",
                 32'h0000_2004, 32'h0, 1'b0, 3'b001, 32'h0000_FFFF, 4);
      send_case( 4, "LHU zero-ext, addr=0x2006 mem=0xABCD0000",
                 32'h0000_2006, 32'h0, 1'b0, 3'b101, 32'hABCD_0000, 1);
      send_case( 5, "LW pass-through, addr=0x2008 mem=0xDEADBEEF",
                 32'h0000_2008, 32'h0, 1'b0, 3'b010, 32'hDEAD_BEEF, 3);
      send_case( 6, "SB at addr=0x2001 wdata=0xAA -> be=0010",
                 32'h0000_2001, 32'h0000_00AA, 1'b1, 3'b000, 32'h0, 5);
      send_case( 7, "SH at addr=0x2002 wdata=0xBEEF -> be=1100",
                 32'h0000_2002, 32'h0000_BEEF, 1'b1, 3'b001, 32'h0, 1);
      send_case( 8, "SW at addr=0x200C wdata=0xCAFEBABE -> be=1111",
                 32'h0000_200C, 32'hCAFE_BABE, 1'b1, 3'b010, 32'h0, 2);
      // Misaligned traps
      send_case( 9, "MISALIGN LH @ odd 0x2003",
                 32'h0000_2003, 32'h0, 1'b0, 3'b001, 32'h0, 4);
      send_case(10, "MISALIGN LW @ 0x2007",
                 32'h0000_2007, 32'h0, 1'b0, 3'b010, 32'h0, 1);
      send_case(11, "MISALIGN SH @ odd 0x2005",
                 32'h0000_2005, 32'h0000_BEEF, 1'b1, 3'b001, 32'h0, 3);
    endtask

    task send_case(int id, string lbl,
                   logic [31:0] a, logic [31:0] wd,
                   logic we, logic [2:0] f3, logic [31:0] mem,
                   int unsigned delay);
      lsu_item it = lsu_item::type_id::create("it");
      start_item(it);
      it.test_id       = id;
      it.label         = lbl;
      it.addr          = a;
      it.wdata         = wd;
      it.we            = we;
      it.funct3        = f3;
      it.mock_mem_data = mem;
      it.dmem_delay    = delay;
      finish_item(it);
    endtask
  endclass

  //----------------------------------------------------------------------
  // Driver — identical handshake to old tb, but uses directed item fields.
  //----------------------------------------------------------------------
  class lsu_driver extends uvm_driver #(lsu_item);
    `uvm_component_utils(lsu_driver)
    virtual lsu_thesis_if vif;
    mailbox #(lsu_item) inflight;   // shared with monitor (set by agent)
    function new(string n, uvm_component p); super.new(n, p); endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db#(virtual lsu_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("DRV", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      vif.rst_i            <= 1;
      vif.valid_i          <= 0;
      vif.ready_i          <= 1;
      vif.dmem_rdata_i     <= 0;
      vif.dmem_req_ready_i <= 0;
      vif.dmem_rsp_valid_i <= 0;
      repeat (3) @(posedge vif.clk);
      vif.rst_i <= 0;

      forever begin
        seq_item_port.get_next_item(req);
        // Side-channel: monitor needs id/label of the next handshake.
        if (inflight != null) inflight.put(req);
        @(posedge vif.clk);
        while (vif.ready_o !== 1'b1) @(posedge vif.clk);
        vif.valid_i  <= 1;
        vif.addr_i   <= req.addr;
        vif.wdata_i  <= req.wdata;
        vif.lsu_we_i <= req.we;
        vif.funct3_i <= req.funct3;
        @(posedge vif.clk);
        vif.valid_i <= 0;

        fork
          begin : dmem_slave
            wait (vif.dmem_req_valid_o === 1'b1);
            vif.dmem_req_ready_i <= 1'b1;
            @(posedge vif.clk);
            vif.dmem_req_ready_i <= 1'b0;
            repeat (req.dmem_delay) @(posedge vif.clk);
            vif.dmem_rdata_i     <= req.mock_mem_data;
            vif.dmem_rsp_valid_i <= 1'b1;
            wait (vif.dmem_rsp_ready_o === 1'b1);
            @(posedge vif.clk);
            vif.dmem_rsp_valid_i <= 1'b0;
            forever @(posedge vif.clk);
          end
          begin : wait_done
            wait (vif.valid_o === 1'b1);
          end
        join_any
        disable fork;
        vif.dmem_req_ready_i <= 0;
        vif.dmem_rsp_valid_i <= 0;

        seq_item_port.item_done();
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // Monitor — capture both DUT-side traffic and complete txn for golden.
  //----------------------------------------------------------------------
  class lsu_monitor extends uvm_monitor;
    `uvm_component_utils(lsu_monitor)
    virtual lsu_thesis_if vif;
    uvm_analysis_port #(lsu_item) ap_dut;   // to scoreboard
    uvm_analysis_port #(lsu_item) ap_gld;   // to golden model

    mailbox #(lsu_item) inflight;   // shared with driver (set by agent)

    function new(string n, uvm_component p);
      super.new(n, p);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap_dut = new("ap_dut", this);
      ap_gld = new("ap_gld", this);
      if (!uvm_config_db#(virtual lsu_thesis_if)::get(this, "", "vif", vif))
        `uvm_fatal("MON", "no vif")
    endfunction

    task run_phase(uvm_phase phase);
      lsu_item pending = null;
      lsu_item meta;
      forever begin
        @(posedge vif.clk);
        #1;
        // start of a new transaction
        if (vif.valid_i && vif.ready_o) begin
          pending = lsu_item::type_id::create("pkt");
          if (inflight != null && inflight.try_get(meta) > 0) begin
            pending.test_id    = meta.test_id;
            pending.label      = meta.label;
            pending.dmem_delay = meta.dmem_delay;
          end
          pending.addr   = vif.addr_i;
          pending.wdata  = vif.wdata_i;
          pending.we     = vif.lsu_we_i;
          pending.funct3 = vif.funct3_i;
          pending.act_dmem_we = 0;
        end

        if (pending != null) begin
          if (vif.dmem_req_valid_o && vif.dmem_req_ready_i) begin
            pending.act_dmem_addr  = vif.dmem_addr_o;
            pending.act_dmem_wdata = vif.dmem_wdata_o;
            pending.act_dmem_be    = vif.dmem_be_o;
            pending.act_dmem_we    = vif.dmem_we_o;
          end
          if (vif.dmem_rsp_valid_i && vif.dmem_rsp_ready_o) begin
            pending.mock_mem_data = vif.dmem_rdata_i;
          end
          if (vif.valid_o && vif.ready_i) begin
            pending.act_rdata = vif.lsu_rdata_o;
            pending.act_err   = vif.lsu_err_o;
            ap_dut.write(pending);
            ap_gld.write(pending);   // golden uses same input fields
            pending = null;
          end
        end
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // GOLDEN MODEL — INDEPENDENT component (separate from scoreboard).
  // Receives txn (with input fields populated), computes expected output,
  // forwards to scoreboard via a separate analysis port.
  //----------------------------------------------------------------------
  class lsu_golden extends uvm_subscriber #(lsu_item);
    `uvm_component_utils(lsu_golden)
    uvm_analysis_port #(lsu_item) ap;

    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      ap = new("ap", this);
    endfunction

    function bit golden_misaligned(logic [31:0] a, logic [2:0] f3);
      case (f3)
        3'b001, 3'b101: return (a[0] != 1'b0);
        3'b010:         return (a[1:0] != 2'b00);
        default:        return 1'b0;
      endcase
    endfunction

    function logic [31:0] golden_rdata(lsu_item p);
      logic [1:0] off = p.addr[1:0];
      logic [31:0] sh = p.mock_mem_data >> (off * 8);
      case (p.funct3)
        3'b000: return {{24{sh[7]}}, sh[7:0]};
        3'b100: return {24'b0, sh[7:0]};
        3'b001: return {{16{sh[15]}}, sh[15:0]};
        3'b101: return {16'b0, sh[15:0]};
        3'b010: return p.mock_mem_data;
        default: return 32'b0;
      endcase
    endfunction

    function void golden_store(lsu_item p,
                               output logic [31:0] e_wd,
                               output logic [3:0]  e_be);
      logic [1:0] off = p.addr[1:0];
      e_wd = p.wdata << (off * 8);
      case (p.funct3)
        3'b000: e_be = 4'b0001 << off;
        3'b001: e_be = 4'b0011 << off;
        3'b010: e_be = 4'b1111;
        default: e_be = 4'b0000;
      endcase
    endfunction

    function void write(lsu_item t);
      lsu_item g = lsu_item::type_id::create("gld");
      g.copy(t);
      g.act_err = golden_misaligned(t.addr, t.funct3);
      if (g.act_err) begin
        g.act_rdata      = 32'b0;
        g.act_dmem_we    = 1'b0;
        g.act_dmem_be    = 4'b0;
        g.act_dmem_wdata = 32'b0;
      end else if (t.we == 1'b0) begin
        g.act_rdata      = golden_rdata(t);
        g.act_dmem_we    = 1'b0;
        g.act_dmem_be    = 4'b0;
        g.act_dmem_wdata = 32'b0;
      end else begin
        g.act_rdata   = 32'b0;
        g.act_dmem_we = 1'b1;
        golden_store(t, g.act_dmem_wdata, g.act_dmem_be);
      end
      ap.write(g);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // COVERGROUP — module-level functional coverage (target: 100%).
  // Bins:
  //   - funct3 (8 values)
  //   - we (load/store)
  //   - addr offset (4)
  //   - misalign_x_funct3 cross
  //   - dmem_delay buckets {0,1,2..3,4..5}
  //----------------------------------------------------------------------
  class lsu_coverage extends uvm_subscriber #(lsu_item);
    `uvm_component_utils(lsu_coverage)
    tb_thesis_pkg::manual_cov mc;

    function new(string n, uvm_component p);
      super.new(n, p);
      mc = new("lsu");
      // Register all expected bins so total is fixed (denominator stable).
      // funct3 (5 ops)
      mc.add_bin("f3_LB");  mc.add_bin("f3_LBU"); mc.add_bin("f3_LH");
      mc.add_bin("f3_LHU"); mc.add_bin("f3_LW");
      mc.add_bin("f3_SB");  mc.add_bin("f3_SH");  mc.add_bin("f3_SW");
      // we
      mc.add_bin("we_load"); mc.add_bin("we_store");
      // addr offset
      mc.add_bin("off_0"); mc.add_bin("off_1");
      mc.add_bin("off_2"); mc.add_bin("off_3");
      // dmem_delay buckets
      mc.add_bin("dly_fast"); mc.add_bin("dly_med"); mc.add_bin("dly_slow");
      // misaligned trap path
      mc.add_bin("misalign_LH"); mc.add_bin("misalign_LW");
      mc.add_bin("misalign_SH");
    endfunction

    function void write(lsu_item t);
      // funct3
      case ({t.we, t.funct3})
        {1'b0, 3'b000}: mc.hit_bin("f3_LB");
        {1'b0, 3'b100}: mc.hit_bin("f3_LBU");
        {1'b0, 3'b001}: mc.hit_bin("f3_LH");
        {1'b0, 3'b101}: mc.hit_bin("f3_LHU");
        {1'b0, 3'b010}: mc.hit_bin("f3_LW");
        {1'b1, 3'b000}: mc.hit_bin("f3_SB");
        {1'b1, 3'b001}: mc.hit_bin("f3_SH");
        {1'b1, 3'b010}: mc.hit_bin("f3_SW");
        default: ;
      endcase
      // we
      mc.hit_bin(t.we ? "we_store" : "we_load");
      // offset
      case (t.addr[1:0])
        2'b00: mc.hit_bin("off_0");
        2'b01: mc.hit_bin("off_1");
        2'b10: mc.hit_bin("off_2");
        2'b11: mc.hit_bin("off_3");
      endcase
      // delay bucket
      if (t.dmem_delay <= 1)      mc.hit_bin("dly_fast");
      else if (t.dmem_delay <= 3) mc.hit_bin("dly_med");
      else                        mc.hit_bin("dly_slow");
      // misalign
      if (t.act_err) begin
        case ({t.we, t.funct3})
          {1'b0, 3'b001}, {1'b0, 3'b101}: mc.hit_bin("misalign_LH");
          {1'b0, 3'b010}:                 mc.hit_bin("misalign_LW");
          {1'b1, 3'b001}:                 mc.hit_bin("misalign_SH");
          default: ;
        endcase
      end
    endfunction

    function void report_phase(uvm_phase phase);
      mc.report();
    endfunction
  endclass

  //----------------------------------------------------------------------
  // SCOREBOARD — INDEPENDENT from golden: receives DUT txn + golden txn
  // through TWO separate analysis fifos and compares.
  //----------------------------------------------------------------------
  class lsu_scoreboard extends uvm_component;
    `uvm_component_utils(lsu_scoreboard)
    uvm_tlm_analysis_fifo #(lsu_item) dut_fifo;
    uvm_tlm_analysis_fifo #(lsu_item) gld_fifo;

    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dut_fifo = new("dut_fifo", this);
      gld_fifo = new("gld_fifo", this);
    endfunction

    task run_phase(uvm_phase phase);
      lsu_item d, g;
      forever begin
        fork
          dut_fifo.get(d);
          gld_fifo.get(g);
        join

        tb_thesis_pkg::test_begin(d.label);
        tb_thesis_pkg::stim($sformatf(
          "addr=0x%08h wdata=0x%08h we=%0b funct3=%03b mem=0x%08h",
          d.addr, d.wdata, d.we, d.funct3, d.mock_mem_data));

        if (g.act_err == 1'b1) begin
          void'(tb_thesis_pkg::check(
            d.act_err === 1'b1,
            "lsu_err_o=1",
            $sformatf("lsu_err_o=%0b lsu_rdata=0x%08h",
                      d.act_err, d.act_rdata)));
        end
        else if (d.we == 1'b0) begin
          void'(tb_thesis_pkg::check(
            (d.act_err === 1'b0) && (d.act_rdata === g.act_rdata),
            $sformatf("lsu_rdata=0x%08h lsu_err=0", g.act_rdata),
            $sformatf("lsu_rdata=0x%08h lsu_err=%0b",
                      d.act_rdata, d.act_err)));
        end
        else begin
          void'(tb_thesis_pkg::check(
            (d.act_err === 1'b0) &&
            (d.act_dmem_we === 1'b1) &&
            (d.act_dmem_be === g.act_dmem_be) &&
            (d.act_dmem_wdata === g.act_dmem_wdata),
            $sformatf("dmem_we=1 be=%04b wdata=0x%08h err=0",
                      g.act_dmem_be, g.act_dmem_wdata),
            $sformatf("dmem_we=%0b be=%04b wdata=0x%08h err=%0b",
                      d.act_dmem_we, d.act_dmem_be,
                      d.act_dmem_wdata, d.act_err)));
        end
      end
    endtask
  endclass

  //----------------------------------------------------------------------
  // Agent / Env / Test
  //----------------------------------------------------------------------
  class lsu_agent extends uvm_agent;
    `uvm_component_utils(lsu_agent)
    lsu_driver  drv;
    lsu_monitor mon;
    uvm_sequencer #(lsu_item) sqr;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      drv = lsu_driver ::type_id::create("drv", this);
      mon = lsu_monitor::type_id::create("mon", this);
      sqr = uvm_sequencer#(lsu_item)::type_id::create("sqr", this);
      drv.inflight = new();
      mon.inflight = drv.inflight;   // share the same mailbox
    endfunction
    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

  class lsu_env extends uvm_env;
    `uvm_component_utils(lsu_env)
    lsu_agent      agent;
    lsu_golden     gld;
    lsu_coverage   cov;
    lsu_scoreboard scb;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      agent = lsu_agent     ::type_id::create("agent", this);
      gld   = lsu_golden    ::type_id::create("gld",   this);
      cov   = lsu_coverage  ::type_id::create("cov",   this);
      scb   = lsu_scoreboard::type_id::create("scb",   this);
    endfunction
    function void connect_phase(uvm_phase phase);
      // monitor splits to: golden, coverage, scoreboard-DUT
      agent.mon.ap_dut.connect(scb.dut_fifo.analysis_export);
      agent.mon.ap_dut.connect(cov.analysis_export);
      agent.mon.ap_gld.connect(gld.analysis_export);
      gld.ap.connect(scb.gld_fifo.analysis_export);
    endfunction
  endclass

  class lsu_test extends uvm_test;
    `uvm_component_utils(lsu_test)
    lsu_env env;
    function new(string n, uvm_component p); super.new(n, p); endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      env = lsu_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
      lsu_directed_seq seq = lsu_directed_seq::type_id::create("seq");
      phase.raise_objection(this);
      seq.start(env.agent.sqr);
      // give time for golden + scoreboard to drain
      #500;
      phase.drop_objection(this);
    endtask
    function void report_phase(uvm_phase phase);
      tb_thesis_pkg::summary();
    endfunction
  endclass

endpackage : lsu_thesis_pkg

//------------------------------------------------------------------------------
// Top module
//------------------------------------------------------------------------------
module tb_top;
  import uvm_pkg::*;
  import tb_thesis_pkg::*;
  import lsu_thesis_pkg::*;

  // Wave marker signals
  logic [7:0] tb_test_id;
  logic       tb_check_pass;

  logic clk = 0;
  always #5 clk = ~clk;

  lsu_thesis_if vif(clk);

  // Wave hook — drives tb_test_id / tb_check_pass from package counters.
  `THESIS_WAVE_HOOK(clk)

  // DUT
  lsu dut (
    .clk_i(clk),                  .rst_i(vif.rst_i),
    .addr_i(vif.addr_i),          .wdata_i(vif.wdata_i),
    .lsu_we_i(vif.lsu_we_i),      .funct3_i(vif.funct3_i),
    .valid_i(vif.valid_i),        .ready_o(vif.ready_o),
    .valid_o(vif.valid_o),        .ready_i(vif.ready_i),
    .lsu_rdata_o(vif.lsu_rdata_o),.lsu_err_o(vif.lsu_err_o),
    .dmem_req_valid_o(vif.dmem_req_valid_o),
    .dmem_req_ready_i(vif.dmem_req_ready_i),
    .dmem_addr_o(vif.dmem_addr_o),.dmem_wdata_o(vif.dmem_wdata_o),
    .dmem_be_o(vif.dmem_be_o),    .dmem_we_o(vif.dmem_we_o),
    .dmem_rsp_valid_i(vif.dmem_rsp_valid_i),
    .dmem_rsp_ready_o(vif.dmem_rsp_ready_o),
    .dmem_rdata_i(vif.dmem_rdata_i)
  );

  // ---- SVA: bind to DUT-facing signals ----
  // Active-high reset on this DUT — wrap rst_n = !rst_i.
  wire rst_n = !vif.rst_i;
  `THESIS_ASSERT_NO_X       (lsu_rdata, clk, rst_n, vif.lsu_rdata_o)
  `THESIS_ASSERT_NO_X       (lsu_err,   clk, rst_n, vif.lsu_err_o)
  `THESIS_ASSERT_NO_X       (dmem_be,   clk, rst_n, vif.dmem_be_o)
  `THESIS_ASSERT_HANDSHAKE  (dmem_req,  clk, rst_n, vif.dmem_req_valid_o, vif.dmem_req_ready_i, 16)
  `THESIS_ASSERT_STABLE_UNTIL(req_stable, clk, rst_n, vif.dmem_req_valid_o, vif.dmem_req_ready_i)

  initial begin
    tb_thesis_pkg::header("tb_lsu_thesis", "5.2.4", "5.4");
    uvm_config_db#(virtual lsu_thesis_if)::set(null, "*", "vif", vif);
    run_test("lsu_test");
  end

  // Wave dump
  initial begin
    $dumpfile("vsim.wlf");
    $dumpvars(0, tb_top);
  end

endmodule
