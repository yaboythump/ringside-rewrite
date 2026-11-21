ENTRY(_start)
SECTIONS {
    . = 0x080000C0;
    .text : { *(.text.start) *(.text*) }
    .rodata : { *(.rodata*) }
    /DISCARD/ : { *(.data*) *(.bss*) *(.ARM.exidx*) *(.ARM.attributes) *(.comment) }
}
