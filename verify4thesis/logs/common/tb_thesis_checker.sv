//==============================================================================
// tb_thesis_checker.sv
// Scoreboard base — INDEPENDENT from golden model.
//
// Architecture (per thesis requirement: scoreboard độc lập với golden model):
//   ┌────────────┐  txn   ┌──────────────┐
//   │  Monitor   │───────▶│  Scoreboard  │──── compare ─── golden vs DUT
//   └────────────┘   ▲    └──────────────┘
//                    │
//                    └─── txn from Golden Model (separate component)
//
// The golden model is a DIFFERENT component (per-module file). The scoreboard
// only knows TWO transaction streams: from monitor (DUT) and from golden.
// It does NOT compute the expected value itself — that's the golden's job.
//
// Each per-module tb extends `thesis_scoreboard_base` and overrides:
//   - `compare_txn(dut_txn, gld_txn)` — module-specific equality
//   - `coverage_sample(dut_txn)`      — module-specific covergroup hook
//==============================================================================
`ifndef TB_THESIS_CHECKER_SV
`define TB_THESIS_CHECKER_SV

package tb_thesis_checker_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //----------------------------------------------------------------------
  // Generic transaction base — module tb extends with its own fields.
  //----------------------------------------------------------------------
  class thesis_txn extends uvm_sequence_item;
    int unsigned test_id;
    string       label;     // human-readable test label, used in logs

    `uvm_object_utils_begin(thesis_txn)
      `uvm_field_int   (test_id, UVM_DEFAULT)
      `uvm_field_string(label,   UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name="thesis_txn");
      super.new(name);
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Scoreboard base.
  // Two TLM analysis FIFOs (DUT side, golden side) feed compare_txn().
  //----------------------------------------------------------------------
  class thesis_scoreboard_base #(type T = thesis_txn) extends uvm_component;

    uvm_tlm_analysis_fifo #(T) dut_fifo;
    uvm_tlm_analysis_fifo #(T) gld_fifo;

    int unsigned matched   = 0;
    int unsigned mismatched= 0;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      dut_fifo = new("dut_fifo", this);
      gld_fifo = new("gld_fifo", this);
    endfunction

    // Module tb override this with field-by-field compare.
    // Default: assumes T has a do_compare or relies on uvm_object compare().
    virtual function bit compare_txn(T dut_t, T gld_t);
      return dut_t.compare(gld_t);
    endfunction

    // Module tb override this to drive its own covergroup.
    virtual function void coverage_sample(T dut_t);
      // no-op
    endfunction

    task run_phase(uvm_phase phase);
      T dut_t, gld_t;
      forever begin
        fork
          dut_fifo.get(dut_t);
          gld_fifo.get(gld_t);
        join
        coverage_sample(dut_t);
        if (compare_txn(dut_t, gld_t)) begin
          matched++;
          `uvm_info("SB", $sformatf("MATCH test=%0d label=%s", dut_t.test_id, dut_t.label), UVM_HIGH)
        end else begin
          mismatched++;
          `uvm_error("SB", $sformatf("MISMATCH test=%0d label=%s\n  DUT=%s\n  GLD=%s",
                     dut_t.test_id, dut_t.label, dut_t.sprint(), gld_t.sprint()))
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      `uvm_info("SB", $sformatf("Scoreboard: matched=%0d mismatched=%0d",
                matched, mismatched), UVM_LOW)
    endfunction

  endclass

endpackage : tb_thesis_checker_pkg

`endif // TB_THESIS_CHECKER_SV
