/* uart.h - polling driver for the SoC UART */
#ifndef UART_H
#define UART_H
#include <stdint.h>

void uart_init(uint32_t divisor);
void uart_putc(char c);
void uart_puts(const char *s);
void uart_puthex8(uint8_t v);
int  uart_getc_timeout(uint32_t loops);   /* returns byte, or -1 on timeout */

#endif
