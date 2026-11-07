/* crt0.S - startup for VeeR EL2 in soc_top
 *  - marks the peripheral region (0x2xxx_xxxx) as side-effect (no merging/speculation)
 *  - sets the stack, copies .data from IMEM to DMEM, clears .bss, calls main()
 */
    .section .text.init
    .globl _start
_start:
    /* VeeR MRAC CSR (0x7C0): 2 bits per 256 MB region, bit1 = side-effect.
       Region 2 (0x2000_0000 - 0x2FFF_FFFF) = peripherals -> 0b10 at bits [5:4]. */
    li   t0, 0x20
    csrw 0x7c0, t0
    fence

    la   sp, _stack_top

    /* copy .data (stored in IMEM) to DMEM */
    la   t0, _data_lma
    la   t1, _data_start
    la   t2, _data_end
1:  bgeu t1, t2, 2f
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j    1b

    /* clear .bss */
2:  la   t0, _bss_start
    la   t1, _bss_end
3:  bgeu t0, t1, 4f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    3b

4:  call main
5:  j    5b
