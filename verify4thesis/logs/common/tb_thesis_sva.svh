//==============================================================================
// tb_thesis_sva.svh
// SystemVerilog Assertion library — bắt lỗi cục bộ.
//
// Each macro takes an explicit LBL identifier so the generated assertion has
// a unique, syntactically valid name regardless of the SIG expression.
//
// USAGE:
//   `THESIS_ASSERT_NO_X     (lsu_rdata,  clk, rst_n, vif.lsu_rdata_o)
//   `THESIS_ASSERT_HANDSHAKE(dmem_req,   clk, rst_n, vif.req_v, vif.req_r, 16)
//   `THESIS_ASSERT_ONEHOT0  (fwd_sel,    clk, rst_n, vif.fwd_rs1_sel)
//   `THESIS_ASSERT_IMPL_NEXT(branch_flush, clk, rst_n, br_taken, flush_if_id)
//==============================================================================
`ifndef TB_THESIS_SVA_SVH
`define TB_THESIS_SVA_SVH

// ---------- No-X check on a signal -------------------------------------------
`define THESIS_ASSERT_NO_X(LBL, CLK, RSTN, SIG)                                 \
  a_thesis_no_x_``LBL: assert property (                                        \
    @(posedge CLK) disable iff (!RSTN)                                          \
    !$isunknown(SIG)                                                            \
  ) else `uvm_error("SVA_NOX",                                                  \
    $sformatf("Signal %s went X/Z @ %0t", `"LBL`", $time))

// ---------- Handshake: while req asserted, grant must come within MAX_CYC ----
// Uses ##[0:MAX_CYC] so a same-cycle grant counts as success.
`define THESIS_ASSERT_HANDSHAKE(LBL, CLK, RSTN, REQ, GNT, MAX_CYC)              \
  a_thesis_hs_``LBL: assert property (                                          \
    @(posedge CLK) disable iff (!RSTN)                                          \
    REQ |-> ##[0:MAX_CYC] GNT                                                   \
  ) else `uvm_error("SVA_HS",                                                   \
    $sformatf("HS %s: req asserted but grant did not within %0d cyc @ %0t",     \
              `"LBL`", MAX_CYC, $time))

// ---------- One-hot or all-zero ----------------------------------------------
`define THESIS_ASSERT_ONEHOT0(LBL, CLK, RSTN, SIG)                              \
  a_thesis_oh0_``LBL: assert property (                                         \
    @(posedge CLK) disable iff (!RSTN)                                          \
    $onehot0(SIG)                                                               \
  ) else `uvm_error("SVA_OH0",                                                  \
    $sformatf("%s not one-hot0 @ %0t", `"LBL`", $time))

// ---------- Strict one-hot (exactly one bit) ---------------------------------
`define THESIS_ASSERT_ONEHOT(LBL, CLK, RSTN, SIG)                               \
  a_thesis_oh_``LBL: assert property (                                          \
    @(posedge CLK) disable iff (!RSTN)                                          \
    $onehot(SIG)                                                                \
  ) else `uvm_error("SVA_OH",                                                   \
    $sformatf("%s not one-hot @ %0t", `"LBL`", $time))

// ---------- A implies B within next cycle ------------------------------------
`define THESIS_ASSERT_IMPL_NEXT(LBL, CLK, RSTN, A, B)                           \
  a_thesis_impl_``LBL: assert property (                                        \
    @(posedge CLK) disable iff (!RSTN)                                          \
    A |=> B                                                                     \
  ) else `uvm_error("SVA_IMPL",                                                 \
    $sformatf("%s: A |=> B violated @ %0t", `"LBL`", $time))

// ---------- A implies B same cycle -------------------------------------------
`define THESIS_ASSERT_IMPL_SAME(LBL, CLK, RSTN, A, B)                           \
  a_thesis_implsame_``LBL: assert property (                                    \
    @(posedge CLK) disable iff (!RSTN)                                          \
    A |-> B                                                                     \
  ) else `uvm_error("SVA_IMPL",                                                 \
    $sformatf("%s: A |-> B violated @ %0t", `"LBL`", $time))

// ---------- Stable when held -------------------------------------------------
`define THESIS_ASSERT_STABLE_UNTIL(LBL, CLK, RSTN, SIG, GNT)                    \
  a_thesis_stable_``LBL: assert property (                                      \
    @(posedge CLK) disable iff (!RSTN)                                          \
    SIG && !GNT |=> $stable(SIG)                                                \
  ) else `uvm_error("SVA_STBL",                                                 \
    $sformatf("%s not stable while waiting grant @ %0t", `"LBL`", $time))

// ---------- Reset behaviour --------------------------------------------------
`define THESIS_ASSERT_RESET_VAL(LBL, CLK, RSTN, SIG, RST_VAL)                   \
  a_thesis_rstval_``LBL: assert property (                                      \
    @(posedge CLK) (!RSTN) |-> (SIG == RST_VAL)                                 \
  ) else `uvm_error("SVA_RST",                                                  \
    $sformatf("%s != %0d during reset @ %0t", `"LBL`", RST_VAL, $time))

`endif // TB_THESIS_SVA_SVH
