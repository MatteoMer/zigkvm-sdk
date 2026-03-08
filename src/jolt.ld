/* Jolt-compatible linker script
 * Memory map (matching Jolt/Zolt's MemoryLayout):
 *   I/O region:   below 0x80000000 (input, output, advice)
 *   RAM:          0x80000000+ (code, data, stack, heap)
 *
 * I/O addresses (with default MemoryConfig):
 *   INPUT_ADDR:   0x7FFFA000
 *   OUTPUT_ADDR:  0x7FFFB000
 *   PANIC_ADDR:   0x7FFFC000
 */

OUTPUT_FORMAT("elf64-littleriscv")
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
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
    } > RAM AT > RAM :text

    . = ALIGN(8);
    PROVIDE(_global_pointer = .);

    .rodata : {
        *(.rodata .rodata.*)
    } > RAM AT > RAM :rodata

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
