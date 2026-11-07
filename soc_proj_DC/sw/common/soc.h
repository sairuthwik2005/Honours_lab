/*
 * soc.h - Address map and register definitions for the
 *         RISC-V Reliable Digital Communication SoC (soc_top.v)
 *
 * Address map (from rtl/soc_top.v, axi_interconnect_wrap_1x8):
 *   M00 IMEM   0x0000_0000  64 KiB   program code + read-only data
 *   M01 DMEM   0x1000_0000  64 KiB   variables + stack
 *   M02 UART   0x2000_0000   4 KiB
 *   M03 Timer  0x2000_1000   4 KiB
 *   M04 GPIO   0x2000_2000   4 KiB
 *   M05 CRC16  0x2000_3000   4 KiB
 *   M06 FIFO   0x2000_4000   4 KiB
 *   M07 SPI    0x2000_5000   4 KiB
 */
#ifndef SOC_H
#define SOC_H

#include <stdint.h>

#define REG32(addr)   (*(volatile uint32_t *)(addr))

#define IMEM_BASE     0x00000000u
#define DMEM_BASE     0x10000000u
#define UART_BASE     0x20000000u
#define TIMER_BASE    0x20001000u
#define GPIO_BASE     0x20002000u
#define CRC_BASE      0x20003000u
#define FIFO_BASE     0x20004000u
#define SPI_BASE      0x20005000u

/* ------------------------------------------------------------------ */
/* UART (IPs/UART_IP, 16550-style, registers on 32-bit word slots)     */
/* ------------------------------------------------------------------ */
#define UART_RBR      REG32(UART_BASE + 0x00)  /* read : received byte (pops RX FIFO), DLAB=0 */
#define UART_THR      REG32(UART_BASE + 0x00)  /* write: byte to send (pushes TX FIFO), DLAB=0 */
#define UART_IER      REG32(UART_BASE + 0x04)  /* write only: bit0 = RX enable/interrupt      */
#define UART_DIV      REG32(UART_BASE + 0x08)  /* write only: baud divisor, needs DLAB=1      */
#define UART_LCR      REG32(UART_BASE + 0x0C)  /* write only: line control                    */
#define UART_LSR      REG32(UART_BASE + 0x14)  /* read : line status                          */

/* NOTE: only RBR and LSR can be READ. Reading IER, DIV or LCR gets no
 *       response from this UART IP and the bus hangs - never read them. */

#define UART_LCR_DLAB      (1u << 7)   /* 1 = DIV register visible at 0x08 */
#define UART_LCR_STOP2     (1u << 2)   /* 0 = 1 stop bit                   */
#define UART_LCR_PARITY_EN (1u << 3)   /* 0 = no parity                    */
#define UART_LCR_8N1       0x00u       /* data is always 8 bits            */

#define UART_IER_RX_EN     (1u << 0)   /* must be 1, or LSR.DR never sets  */

#define UART_LSR_DR        (1u << 0)   /* 1 = a received byte is waiting   */
#define UART_LSR_THRE      (1u << 5)   /* 1 = TX FIFO has space            */
#define UART_LSR_TEMT      (1u << 6)   /* same as THRE in this IP          */

/* Bit time = (UART_DIV_VALUE + 1) clock cycles.
 * Hardware default: 100 MHz / 115200 = 868.
 * Simulation uses a small value to run fast (set with -DUART_DIV_VALUE=..). */
#ifndef UART_DIV_VALUE
#define UART_DIV_VALUE     868u
#endif


/* ------------------------------------------------------------------ */
/* TX FIFO (IPs/fifo) - feeds the SPI master directly in WRITE mode    */
/* ------------------------------------------------------------------ */
#define FIFO_CTRL     REG32(FIFO_BASE + 0x00)  /* bit0 clear FIFO, bit1 clear sticky flags */
#define FIFO_STATUS   REG32(FIFO_BASE + 0x04)  /* bit0 full, bit1 empty, bit2 overflow, bit3 underflow */
#define FIFO_LEVEL    REG32(FIFO_BASE + 0x08)  /* number of bytes stored (0..16) */
#define FIFO_DATA     REG32(FIFO_BASE + 0x0C)  /* write: push one byte */

#define FIFO_CTRL_CLEAR       (1u << 0)
#define FIFO_CTRL_CLEAR_STAT  (1u << 1)
#define FIFO_ST_FULL          (1u << 0)
#define FIFO_ST_EMPTY         (1u << 1)
#define FIFO_DEPTH            16u

/* ------------------------------------------------------------------ */
/* SPI master (IPs/spi) - mode 0, MSB first                            */
/* ------------------------------------------------------------------ */
#define SPI_CTRL      REG32(SPI_BASE + 0x00)
#define SPI_STATUS    REG32(SPI_BASE + 0x04)
#define SPI_LENGTH    REG32(SPI_BASE + 0x08)   /* bytes per transfer */
#define SPI_CLK_DIV   REG32(SPI_BASE + 0x0C)   /* SCLK half period in clocks */
#define SPI_RX_DATA   REG32(SPI_BASE + 0x10)   /* read: received byte (clears RX_VALID) */

#define SPI_CTRL_ENABLE      (1u << 0)
#define SPI_CTRL_START       (1u << 1)  /* auto-clears */
#define SPI_CTRL_READBACK    (1u << 2)  /* 0 = WRITE (bytes from FIFO), 1 = READBACK */
#define SPI_CTRL_ABORT       (1u << 3)
#define SPI_CTRL_CLEAR_STAT  (1u << 4)

#define SPI_ST_BUSY          (1u << 0)
#define SPI_ST_DONE          (1u << 1)
#define SPI_ST_RX_VALID      (1u << 2)
#define SPI_ST_RX_OVERRUN    (1u << 3)


/* ------------------------------------------------------------------ */
/* GPIO (IPs/gpio) - bits [7:0] drive the gpio_out_o pins (LEDs)       */
/* ------------------------------------------------------------------ */
#define GPIO_DATA_IN  REG32(GPIO_BASE + 0x00)  /* read: input pins (tied 0 in soc_top) */
#define GPIO_DATA_OUT REG32(GPIO_BASE + 0x04)  /* read/write: output value            */
#define GPIO_DIR      REG32(GPIO_BASE + 0x08)  /* 1 = output                          */
#define GPIO_SET      REG32(GPIO_BASE + 0x0C)  /* write 1s: set those output bits     */
#define GPIO_CLEAR    REG32(GPIO_BASE + 0x10)  /* write 1s: clear those output bits   */

#endif /* SOC_H */
