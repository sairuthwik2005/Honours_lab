/*
 * test_uart.c - basic UART C test
 *
 * 1. TX : CPU prints "UART OK".
 * 2. RX : testbench sends 'H' 'I' (0x48 0x49); CPU reads both bytes.
 * 3. CPU echoes what it received and checks the values.
 * 4. CPU prints "PASS" or "FAIL" - the testbench ends the simulation on that line.
 */
#include "soc.h"
#include "uart.h"

#define RX_TIMEOUT  2000000u

int main(void)
{
    const uint8_t expected[2] = { 0x48, 0x49 };     /* "HI" */
    uint8_t got[2] = { 0, 0 };
    int errors = 0;

    uart_init(UART_DIV_VALUE);

    /* ---- Test 1: transmit ---- */
    uart_puts("UART OK\n");

    /* ---- Test 2: receive ---- */
    for (int i = 0; i < 2; i++) {
        int c = uart_getc_timeout(RX_TIMEOUT);
        if (c < 0) {                /* byte never arrived */
            errors++;
            break;
        }
        got[i] = (uint8_t)c;
        if (got[i] != expected[i])
            errors++;
    }

    /* ---- Echo what was received ---- */
    uart_puts("RX ");
    uart_puthex8(got[0]);
    uart_putc(' ');
    uart_puthex8(got[1]);
    uart_putc('\n');

    uart_puts(errors ? "FAIL\n" : "PASS\n");

    for (;;)
        ;                           /* testbench ends the simulation */
    return 0;
}
