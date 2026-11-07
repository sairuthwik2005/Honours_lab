/*
 * test_spi.c - SPI write + readback through the FIFO
 *
 * 1. Push 4 bytes into the TX FIFO.
 * 2. SPI WRITE transfer: the SPI master pulls them from the FIFO and sends them on MOSI.
 * 3. SPI READBACK transfer: reads 4 bytes from the slave on MISO.
 * 4. Compare; print "SPI RD xx xx xx xx" and "PASS" / "FAIL".
 *
 * The SPI slave (testbench VIP) returns the bytes it received in the previous frame.
 */
#include "soc.h"
#include "uart.h"

#define N 4
#define TIMEOUT 200000u

static int wait_status(uint32_t mask)
{
    for (uint32_t t = 0; t < TIMEOUT; t++)
        if (SPI_STATUS & mask)
            return 0;
    return -1;
}

int main(void)
{
    const uint8_t tx[N] = { 0x48, 0x49, 0x40, 0x87 };   /* "HI" + CRC-16 0x4087 */
    uint8_t rx[N] = { 0 };
    int errors = 0;

    uart_init(UART_DIV_VALUE);
    uart_puts("SPI TEST\n");

    /* ---- 1. fill the FIFO ---- */
    FIFO_CTRL = FIFO_CTRL_CLEAR | FIFO_CTRL_CLEAR_STAT;
    for (int i = 0; i < N; i++)
        FIFO_DATA = tx[i];

    /* ---- 2. WRITE transfer ---- */
    SPI_CLK_DIV = 4;
    SPI_LENGTH  = N;
    SPI_CTRL    = SPI_CTRL_ENABLE | SPI_CTRL_CLEAR_STAT;
    SPI_CTRL    = SPI_CTRL_ENABLE | SPI_CTRL_START;
    if (wait_status(SPI_ST_DONE)) { uart_puts("WRITE TIMEOUT\n"); errors++; }

    /* ---- 3. READBACK transfer ---- */
    SPI_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_CLEAR_STAT;
    SPI_CTRL = SPI_CTRL_ENABLE | SPI_CTRL_READBACK | SPI_CTRL_START;
    for (int i = 0; i < N; i++) {
        if (wait_status(SPI_ST_RX_VALID)) { uart_puts("READ TIMEOUT\n"); errors++; break; }
        rx[i] = (uint8_t)SPI_RX_DATA;
    }
    if (wait_status(SPI_ST_DONE)) { uart_puts("DONE TIMEOUT\n"); errors++; }

    /* ---- 4. compare ---- */
    uart_puts("SPI RD");
    for (int i = 0; i < N; i++) {
        uart_putc(' ');
        uart_puthex8(rx[i]);
        if (rx[i] != tx[i])
            errors++;
    }
    uart_putc('\n');

    uart_puts(errors ? "FAIL\n" : "PASS\n");
    for (;;)
        ;
    return 0;
}
