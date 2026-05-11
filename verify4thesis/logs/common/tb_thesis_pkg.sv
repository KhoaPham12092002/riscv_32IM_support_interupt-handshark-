//==============================================================================
// tb_thesis_pkg.sv
// Foundation package — functions + dice + 1 macro (WAVE_HOOK).
//
// Calling style (functions in package):
//   tb_thesis_pkg::header("tb_lsu_thesis", "5.2.4", "5.4");
//   tb_thesis_pkg::test_begin("LB sign-extend addr=0x2002");
//   tb_thesis_pkg::stim($sformatf("addr=0x%08h ...", a));
//   if (tb_thesis_pkg::check_eq(actual, expected, expect_str, actual_str)) ...
//   tb_thesis_pkg::cov("lsu", 47, 47);
//   tb_thesis_pkg::summary();
//
// Wave hook (macro, must expand at module scope):
//   `THESIS_WAVE_HOOK(clk_i)
//==============================================================================
`ifndef TB_THESIS_PKG_SV
`define TB_THESIS_PKG_SV

package tb_thesis_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //----------------------------------------------------------------------
  // Counters
  //----------------------------------------------------------------------
  int unsigned thesis_pass_cnt = 0;
  int unsigned thesis_fail_cnt = 0;
  int unsigned thesis_test_id  = 0;

  //----------------------------------------------------------------------
  // Dice random — replaces randomize() (license locked).
  //----------------------------------------------------------------------
  class dice_pct;
    string  name;
    string  labels[$];
    int     pcts  [$];
    int     total = 0;

    function new(string n="dice");
      this.name = n;
    endfunction

    function void add(string label, int pct);
      labels.push_back(label);
      pcts.push_back(pct);
      total += pct;
    endfunction

    function string roll();
      int r;
      int acc;
      int eff;
      acc = 0;
      eff = (total == 0) ? 100 : total;
      r = $urandom_range(0, eff-1);
      foreach (labels[i]) begin
        acc += pcts[i];
        if (r < acc) return labels[i];
      end
      return "NONE";
    endfunction
  endclass

  //----------------------------------------------------------------------
  // Logging functions — grep-friendly, fixed format.
  //----------------------------------------------------------------------
  function automatic void header(string tb_name, string section, string figure);
    $display("================================================================");
    $display(" TB: %s | Section: %s | Figure: %s", tb_name, section, figure);
    $display("================================================================");
    thesis_pass_cnt = 0;
    thesis_fail_cnt = 0;
    thesis_test_id  = 0;
  endfunction

  function automatic void test_begin(string label);
    thesis_test_id++;
    $display("[TEST %02d] %s", thesis_test_id, label);
  endfunction

  function automatic void stim(string msg);
    $display("   Stimulus : %s", msg);
  endfunction

  // Returns 1 if pass, 0 if fail. Caller can short-circuit subsequent checks.
  function automatic bit check(bit cond, string expect_s, string actual_s);
    $display("   Expected : %s", expect_s);
    $display("   Actual   : %s  @ %0t", actual_s, $time);
    if (cond) begin
      $display("   Result   : PASS");
      thesis_pass_cnt++;
    end
    else begin
      $display("   Result   : FAIL");
      thesis_fail_cnt++;
      uvm_pkg::uvm_report_error("THESIS_CHECK",
        $sformatf("FAIL test %0d: exp=%s got=%s",
                  thesis_test_id, expect_s, actual_s));
    end
    $display("----------------------------------------------------------------");
    return cond;
  endfunction

  function automatic void cov(string mod_name, int covered, int total_bins);
    real pct;
    pct = (total_bins == 0) ? 0.0 : (100.0 * real'(covered)) / real'(total_bins);
    $display("[COV] %s: %0d/%0d = %0.2f%%", mod_name, covered, total_bins, pct);
  endfunction

  //----------------------------------------------------------------------
  // Manual coverage tracker — replaces covergroup (license locked).
  // Each bin is a string label. Caller registers all expected bins up
  // front, then calls hit_bin() during sim. report() prints the
  // standard `[COV]` line.
  //----------------------------------------------------------------------
  class manual_cov;
    string         name;
    int unsigned   hits[string];    // bin name → count
    string         all_bins[$];     // ordered registry for reporting

    function new(string n);
      this.name = n;
    endfunction

    // Register a bin (must call before hit_bin).
    function void add_bin(string b);
      if (!hits.exists(b)) begin
        hits[b] = 0;
        all_bins.push_back(b);
      end
    endfunction

    // Mark bin hit. Auto-registers if unknown.
    function void hit_bin(string b);
      if (!hits.exists(b)) begin
        hits[b] = 0;
        all_bins.push_back(b);
      end
      hits[b]++;
    endfunction

    function int covered();
      int c;
      c = 0;
      foreach (hits[k]) if (hits[k] > 0) c++;
      return c;
    endfunction

    function int total();
      return all_bins.size();
    endfunction

    function void report();
      cov(name, covered(), total());
      foreach (all_bins[i]) begin
        $display("    [bin] %s = %0d", all_bins[i], hits[all_bins[i]]);
      end
    endfunction
  endclass

  function automatic void summary();
    int unsigned total;
    total = thesis_pass_cnt + thesis_fail_cnt;
    $display("================================================================");
    $display(" SUMMARY: %0d/%0d PASS, %0d FAIL | Sim time: %0t",
             thesis_pass_cnt, total, thesis_fail_cnt, $time);
    $display("================================================================");
    if (thesis_fail_cnt != 0) begin
      uvm_pkg::uvm_report_fatal("THESIS",
        $sformatf("%0d test(s) FAILED", thesis_fail_cnt));
    end
  endfunction

endpackage : tb_thesis_pkg

//==============================================================================
// WAVE_HOOK macro — must expand in module scope (always_ff).
// Requires `tb_test_id` (logic[7:0]) and `tb_check_pass` (logic) at TB top.
//==============================================================================
`define THESIS_WAVE_HOOK(CLK)                                                   \
  always_ff @(posedge CLK) begin                                                \
    static int unsigned __thesis_prev_total = 0;                                \
    int unsigned __thesis_cur_total;                                            \
    __thesis_cur_total =                                                        \
      tb_thesis_pkg::thesis_pass_cnt + tb_thesis_pkg::thesis_fail_cnt;          \
    tb_test_id    <= 8'(tb_thesis_pkg::thesis_test_id);                         \
    tb_check_pass <= (__thesis_cur_total != __thesis_prev_total);               \
    __thesis_prev_total = __thesis_cur_total;                                   \
  end

`endif // TB_THESIS_PKG_SV
