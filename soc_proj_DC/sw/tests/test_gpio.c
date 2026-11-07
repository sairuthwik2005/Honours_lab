/*
 * test_gpio.c - GPIO interface test
 *
 * Drives a sequence of LED patterns on gpio_out_o[7:0] and reads each back:
 *   write 0x55, write 0xAA, SET 0x05 (-> 0xAF), CLEAR 0xA0 (-> 0x0F), write 0x01
 * The GPIO VIP (passive) records every change on the pins; the UVM test checks
 * that the pins showed exactly 55 AA AF 0F 01.
 * Prints "GPIO 55 AA AF 0F 01" and "PASS" / "FAIL" on the UART.
 */
#include "soc.h"
#include "uart.h"

#define N 5

int main(void)
{
    const uint8_t expect[N] = { 0x55, 0xAA, 0xAF, 0x0F, 0x01 };
    uint8_t got[N];
    int errors = 0;

    uart_init(UART_DIV_VALUE);
    uart_puts("GPIO TEST\n");

    GPIO_DIR = 0xFF;                       /* all 8 pins are outputs */

    GPIO_DATA_OUT = 0x55;  got[0] = (uint8_t)GPIO_DATA_OUT;
    GPIO_DATA_OUT = 0xAA;  got[1] = (uint8_t)GPIO_DATA_OUT;
    GPIO_SET      = 0x05;  got[2] = (uint8_t)GPIO_DATA_OUT;   /* 0xAA | 0x05 = 0xAF */
    GPIO_CLEAR    = 0xA0;  got[3] = (uint8_t)GPIO_DATA_OUT;   /* 0xAF & ~0xA0 = 0x0F */
    GPIO_DATA_OUT = 0x01;  got[4] = (uint8_t)GPIO_DATA_OUT;   /* final: LED0 on */

    uart_puts("GPIO");
    for (int i = 0; i < N; i++) {
        uart_putc(' ');
        uart_puthex8(got[i]);
        if (got[i] != expect[i])
            errors++;
    }
    uart_putc('\n');

    uart_puts(errors ? "FAIL\n" : "PASS\n");
    for (;;)
        ;
    return 0;
}
