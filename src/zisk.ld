/* ZisK-compatible linker script
 * Memory map:
 *   ROM_ADDR:           0x80000000 - program code
 *   INPUT_ADDR:         0x90000000 - input data (read-only)
 *   RAM_ADDR:           0xa0000000 - system/registers
 *   OUTPUT_ADDR:        0xa0010000 - output data
 *   AVAILABLE_MEM_ADDR: 0xa0030000 - program memory (heap/stack)
 *   END OF RAM:         0xc0000000
 */

OUTPUT_FORMAT("elf64-littleriscv")
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    ROM (rx)  : ORIGIN = 0x80000000, LENGTH = 0x07F00000
    RAM (rwx) : ORIGIN = 0xa0030000, LENGTH = 0x1FFD0000
}

PHDRS {
    text PT_LOAD FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data PT_LOAD FLAGS(6);
    bss PT_LOAD FLAGS(6);
}

SECTIONS {
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > ROM AT > ROM :text

    . = ALIGN(8);
    PROVIDE(_global_pointer = .);

    .rodata : {
        *(.rodata .rodata.*)
    } > ROM AT > ROM :rodata

    .data : {
        *(.data .data.* .sdata .sdata.*)
    } > RAM AT > RAM :data

    . = ALIGN(8);
    .bss : {
        PROVIDE(_bss_start = .);
        *(.bss .bss.* .sbss .sbss.*)
        PROVIDE(_bss_end = .);
    } > RAM AT > RAM :bss

    . = ALIGN(8);
    _end = .;

    /* Stack grows down from 1MB above BSS end */
    PROVIDE(_init_stack_top = _end + 0x100000);

    /* Heap starts after stack and extends to end of RAM */
    _heap_start = _init_stack_top;
    _heap_end = ORIGIN(RAM) + LENGTH(RAM);
}
