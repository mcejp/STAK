// References:
// - PC8250A data sheet (https://web.cecs.pdx.edu/~mpj/llp/references/8250datasheet.pdf)
// - https://wiki.osdev.org/Serial_Ports

#include "listener.h"

#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <dos.h>
#include <conio.h>
#include <i86.h>

#define PIC_CMD         0x20
#define PIC_IMR         0x21
#define PIC_CMD_EOI     0x20

#define COM1_BASE       0x3F8
#define DATA_REG        0x0
#define INT_ENABLE      0x1
#define INT_ID          0x2
#define BAUD_LSB        0x0
#define BAUD_MSB        0x1
#define LINE_CTRL       0x3
#define MODEM_CTRL      0x4
#define LINE_STATUS     0x5

#define LSR_DATA_READY  0x01
#define LSR_THR_EMPTY   0x20

#define IER_RX_DATA     0x01

#define IIR_NOT_PENDING 0x01
#define IIR_ID_MASK     0x06
#define IIR_RX_DATA     0x04

#define COM1_IRQ        4
#define COM1_INT_VEC    0x0C

// 1.8432 MHz / (9600 * 16)
#define BAUD_9600       12

#define RX_BUFFER_SIZE  256
static volatile uint8_t rx_buffer[RX_BUFFER_SIZE];
static volatile uint8_t writepos = 0;
static volatile uint8_t readpos = 0;
static volatile uint8_t rx_overflow = 0;

static void (_interrupt _far * old_handler)();

static void _interrupt _far com1_handler(void) {
    uint8_t int_id, data;

    int_id = inp(COM1_BASE + INT_ID);

    if ((int_id & IIR_NOT_PENDING) || ((int_id & IIR_ID_MASK) != IIR_RX_DATA)) {
        // Not our interrupt or not RX data - chain to old handler
        _chain_intr(old_handler);
        return;
    }

    while ((inp(COM1_BASE + LINE_STATUS) & LSR_DATA_READY)) {
        uint8_t new_writepos;

        data = inp(COM1_BASE + DATA_REG);
        new_writepos = (writepos + 1) % RX_BUFFER_SIZE;

        if (new_writepos == readpos) {
            // TODO: is there a better way to handle this? (e.g. leave data in FIFO)
            rx_overflow = 1;
            return;
        }

        rx_buffer[writepos] = data;
        writepos = new_writepos;
    }

    // signal end of interrupt
    outp(PIC_CMD, PIC_CMD_EOI);
}

void listener_init(void) {
    // Disable interrupts while setting up
    _disable();

    old_handler = _dos_getvect(COM1_INT_VEC);
    _dos_setvect(COM1_INT_VEC, com1_handler);

    // Disable all UART interrupts
    outp(COM1_BASE + INT_ENABLE, 0x00);

    // Set DLAB to access baud rate divisor
    outp(COM1_BASE + LINE_CTRL, 0x80);

    // Set baud rate to 9600 (divisor = 12)
    outp(COM1_BASE + BAUD_LSB, BAUD_9600 & 0xFF);
    outp(COM1_BASE + BAUD_MSB, (BAUD_9600 >> 8) & 0xFF);

    // 8 data bits, 1 stop bit, no parity (8N1)
    outp(COM1_BASE + LINE_CTRL, 0x03);

    // Enable FIFO, clear them, with threshold of 14 bytes
    outp(COM1_BASE + 0x2, 0xC7);

    // Set RTS/DSR, OUT2 (required for interrupts)
    outp(COM1_BASE + MODEM_CTRL, 0x0B);

    // Enable received data available interrupt
    outp(COM1_BASE + INT_ENABLE, IER_RX_DATA);

    // Configure PIC to allow IRQ4 (COM1)
    outp(PIC_IMR, inp(PIC_IMR) & ~(1 << COM1_IRQ));

    // Re-enable interrupts
    _enable();

    // printf("listening on COM1 at 9600 baud, 8N1\n");
}

void listener_shutdown(void) {
    // Disable interrupts
    _disable();

    outp(COM1_BASE + INT_ENABLE, 0x00);
    _dos_setvect(COM1_INT_VEC, old_handler);

    // Re-enable interrupts
    _enable();
}

void listener_tick(void) {
    if (rx_overflow) {
        printf("listener_tick: rx_overflow!\n");
        rx_overflow = 0;
    }
}

int listener_poll_byte(void) {
    int c;

    if (writepos == readpos) {
        return -1;
    }

    c = rx_buffer[readpos];
    readpos = (readpos + 1) % RX_BUFFER_SIZE;
    return c;
}

void listener_send(uint8_t const* buffer, size_t count) {
    while (count > 0) {
        while (!(inp(COM1_BASE + LINE_STATUS) & LSR_THR_EMPTY)) {
        }

        outp(COM1_BASE + DATA_REG, *buffer);
        buffer++;
        count--;
    }
}
