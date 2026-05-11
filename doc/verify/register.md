# Verification Report — Register File

## 1. Module Overview
**File:** src/core/register.sv
**Chức năng:** 32×32-bit register file, x0=0 hardwired

## 2. Testbench Hiện Tại
- **TB:** verify/UVM/core/tb_register.sv
- **Script:** sim/run_reg.do
- **Hell-Level:** 2/10

## 3. Gaps — Địa Ngục

| Scenario | Expected | Status |
|----------|----------|--------|
| Write to x0 → read x0 = 0 | x0 always 0 | Missing |
| Simultaneous write rd + read rs1=rd | Read stale or new? | Missing |
| Write all 31 registers, read back | All correct | Missing |
| Read rs1=rs2 → same value | Consistent | Missing |
| we=0 → no write | Register unchanged | Missing |

## 4. Hell-Level Upgrade: Target 7/10
