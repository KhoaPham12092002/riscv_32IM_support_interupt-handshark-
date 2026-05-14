/* =============================================================================
 * link.ld — Linker script cho RISC-V RV32IM SoC (DE10-Standard)
 *
 * Memory Map phần cứng:
 *   IMEM : 0x0000_0000 – 0x0000_0FFF  (4 KB, Read/Execute)
 *   DMEM : 0x2000_0000 – 0x2000_0FFF  (4 KB, Read/Write)
 *   IO   : 0x4000_0000+               (Memory-mapped peripherals)
 *
 * Quy tắc đặt section:
 *   .text / .rodata  → IMEM  (chỉ đọc, CPU fetch)
 *   .data / .bss     → DMEM  (đọc/ghi, CPU load-store)
 *
 * LƯU Ý QUAN TRỌNG — Harvard Architecture:
 *   LSU chỉ route địa chỉ 0x2000_xxxx sang DMEM và 0x4000_xxxx sang IO.
 *   Lệnh LOAD/STORE với địa chỉ 0x0000_xxxx (IMEM) sẽ TREO CPU.
 *   → Mọi bảng tra cứu (lookup table) phải ở DMEM, KHÔNG ở IMEM.
 *   → Dùng startup code để copy/khởi tạo bảng vào DMEM trước khi dùng.
 *
 * Stack: đỉnh DMEM = 0x2000_0FFC (grows downward)
 * ============================================================================= */

OUTPUT_ARCH(riscv)
OUTPUT_FORMAT("elf32-littleriscv")
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 4K   /* Instruction Memory */
    DMEM (rw)  : ORIGIN = 0x20000000, LENGTH = 4K   /* Data Memory        */
}

SECTIONS
{
    /* =========================================================================
     * .text — Code + Read-Only Constants → IMEM
     * ========================================================================= */
    .text 0x00000000 : {
        KEEP(*(.text.boot))         /* Boot entry point (nếu có section riêng) */
        *(.text*)                   /* Tất cả code */
        *(.rodata*)                 /* Hằng số read-only (string, const array) */
        . = ALIGN(4);
        _text_end = .;
    } > IMEM

    /* =========================================================================
     * .data — Initialized global/static variables → DMEM
     *
     * LMA (Load Memory Address) = nơi dữ liệu được lưu trong file hex (sau .text)
     * VMA (Virtual/Runtime Address) = nơi code truy cập khi chạy (DMEM)
     *
     * CẢNH BÁO: DMEM không tự load từ hex file (không có $readmemh).
     * Nếu dùng .data, cần startup code copy từ LMA (IMEM) sang VMA (DMEM):
     *   memcpy(_data_start, _data_lma, _data_end - _data_start);
     * Với programv2.s thuần assembly: không có .data, bảng hex_map được
     * khởi tạo trực tiếp bằng SB instructions trong _init.
     * ========================================================================= */
    .data : AT(_text_end) {
        _data_lma   = LOADADDR(.data); /* Địa chỉ trong hex file */
        _data_start = .;               /* Địa chỉ runtime (DMEM) */
        *(.data*)
        . = ALIGN(4);
        _data_end   = .;
    } > DMEM

    /* =========================================================================
     * .bss — Zero-initialized variables → DMEM
     * DMEM đã được khởi tạo = 0 trong simulation (initial block), nên
     * .bss hoạt động đúng mà không cần zero-fill startup code.
     * ========================================================================= */
    .bss (NOLOAD) : {
        _bss_start = .;
        *(.bss*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end   = .;
    } > DMEM

    /* =========================================================================
     * Symbols hỗ trợ
     * ========================================================================= */
    _stack_top  = ORIGIN(DMEM) + LENGTH(DMEM) - 4;  /* 0x20000FFC */
    _heap_start = _bss_end;
    _heap_end   = _stack_top;

    /* =========================================================================
     * Loại bỏ các section không cần thiết (debug, attributes...)
     * ========================================================================= */
    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.riscv.attributes)
        *(.debug*)
        *(.eh_frame*)
    }
}
