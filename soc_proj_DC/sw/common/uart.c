/* uart.c - polling driver for the SoC UART (IPs/UART_IP) */
#include "soc.h"
#include "uart.h"

void uart_init(uint32_t divisor)
{
    UART_LCR = UART_LCR_DLAB;        /* open the divisor register      */
    UART_DIV = divisor;              /* bit time = divisor + 1 clocks  */
    UART_LCR = UART_LCR_8N1;         /* 8 data, no parity, 1 stop      */
    UART_IER = UART_IER_RX_EN;       /* enable RX "data ready" flag    */
}

void uart_putc(char c)
{
    while ((UART_LSR & UART_LSR_THRE) == 0)
        ;                            /* wait for space in the TX FIFO  */
    UART_THR = (uint32_t)(uint8_t)c;
}

void uart_puts(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

void uart_puthex8(uint8_t v)
{
    static const char hex[] = "0123456789ABCDEF";
    uart_putc(hex[v >> 4]);
    uart_putc(hex[v & 0xF]);
}

int uart_getc_timeout(uint32_t loops)
{
    while (loops--) {
        if (UART_LSR & UART_LSR_DR)
            return (int)(UART_RBR & 0xFF);
    }
    return -1;
}
