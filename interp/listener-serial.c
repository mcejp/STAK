/* Reference: https://wiki.osdev.org/Serial_Ports */

#include "listener.h"

#include <stdio.h>
#include <stdlib.h>
#include <dos.h>
#include <conio.h>
#include <i86.h>

/* COM port registers and their offsets */
#define COM1_BASE       0x3F8
#define DATA_REG        0x0     /* Data register (read/write) */
#define INT_ENABLE      0x1     /* Interrupt enable register */
#define INT_ID          0x2     /* Interrupt identification register */
#define BAUD_LSB        0x0     /* Baud rate divisor LSB (when DLAB=1) */
#define BAUD_MSB        0x1     /* Baud rate divisor MSB (when DLAB=1) */
#define LINE_CTRL       0x3     /* Line control register */
#define MODEM_CTRL      0x4     /* Modem control register */
#define LINE_STATUS     0x5     /* Line status register */

/* Line status register bits */
#define LSR_DATA_READY  0x01    /* Data ready */
#define LSR_THR_EMPTY   0x20    /* Transmitter holding register empty */

/* Interrupt enable register bits */
#define IER_RX_DATA     0x01    /* Enable received data available interrupt */

/* Interrupt identification register bits */
#define IIR_PENDING     0x01    /* 0 = interrupt pending, 1 = no interrupt */
#define IIR_ID_MASK     0x06    /* Interrupt ID bits */
#define IIR_RX_DATA     0x04    /* Received data available */

/* COM1 uses IRQ4, which corresponds to interrupt vector 0x0C */
#define COM1_IRQ        4
#define COM1_INT_VEC    0x0C

/* Baud rate divisors (for 1.8432 MHz clock) */
#define BAUD_9600       12      /* 1.8432 MHz / (9600 * 16) */

/* Circular buffer for received data - adjust size as needed */
#define RX_BUFFER_SIZE  256
static volatile unsigned char rx_buffer[RX_BUFFER_SIZE];
static volatile int writepos = 0;
static volatile int readpos = 0;

/* Flag to indicate buffer overflow */
static volatile int rx_overflow = 0;

static volatile int called = 0;

/* Original interrupt vector */
static void (__interrupt __far *old_handler)();

static int rx_buffer_empty(void) {
    return (writepos == readpos);
}

static int rx_buffer_available(void) {
    if (writepos >= readpos) {
        return writepos - readpos;
    }
    else {
        return RX_BUFFER_SIZE - (readpos - writepos);
    }
}

static void rx_buffer_put(unsigned char c) {
    int next_head = (writepos + 1) % RX_BUFFER_SIZE;

    if (next_head == readpos) {
        rx_overflow = 1;
        return;
    }

    rx_buffer[writepos] = c;
    writepos = next_head;
}

static void __interrupt __far com1_handler(void) {
    unsigned char status, data;

    status = inp(COM1_BASE + INT_ID);
    called = 0x100 + status;

    if ((status & IIR_PENDING) || ((status & IIR_ID_MASK) != IIR_RX_DATA)) {
        // Not our interrupt or not RX data - chain to old handler
        _chain_intr(old_handler);
        return;
    }

    while (inp(COM1_BASE + LINE_STATUS) & LSR_DATA_READY) {
        data = inp(COM1_BASE + DATA_REG);
        rx_buffer_put(data);
    }

    // Send EOI to PIC
    outp(0x20, 0x20);
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
    outp(0x21, inp(0x21) & ~(1 << COM1_IRQ));
    
    // Re-enable interrupts
    _enable();
    
    // printf("listening on COM1 at 9600 baud, 8N1\n");
}

void listener_shutdown(void) {
    // Disable interrupts */
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
