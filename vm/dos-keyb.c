#include <conio.h>
#include <dos.h>
#include <stdbool.h>
#include <stdint.h>

#define PIC_CMD         0x20
#define PIC_CMD_EOI     0x20

static bool initialized = false;
static void (_interrupt _far * old_keyb_handler)(void);

enum { BUFFER_SIZE = 16 };
static volatile uint16_t buffer[BUFFER_SIZE];
static volatile uint8_t writepos = 0;
static volatile uint8_t readpos = 0;
static volatile uint8_t extended = 0;  // strictly speaking, we shouldn't assume this

// Register reference: https://bitsavers.org/pdf/ibm/pc/xt/6361459_PC_XT_Technical_Reference_Apr84.pdf, p 1-26
static void _interrupt keyb_handler(void) {
    uint16_t scancode;
    uint8_t status, new_writepos;

    scancode = inp(0x60);
    status = inp(0x61);

    // acknowledge key by strobing PORTB7
    outp(0x61, status | 0x80);
    outp(0x61, status);

    if (extended) {
        scancode |= 0xE000;
        extended = 0;
    }
    else if (scancode == 0xE0) {
        extended = 1;
        goto end;
    }

    if (scancode & 0x80) {
        // "break" (key released)
    }
    else {
        // "make" (key pressed)
    }

    new_writepos = (writepos + 1) % BUFFER_SIZE;
    if (new_writepos != readpos) {
        buffer[writepos] = scancode;
        writepos = new_writepos;
    }

end:

    // signal end of interrupt
    outp(PIC_CMD, PIC_CMD_EOI);
}

void keyb_init(void) {
    // need to reset the keybord, enable IRQ or anything? assuming all already done by BIOS.

    _disable();
    old_keyb_handler = _dos_getvect(0x09);
    _dos_setvect(0x09, keyb_handler);
    _enable();

    initialized = true;
}

void keyb_shutdown(void) {
    if (initialized) {
        _dos_setvect(0x09, old_keyb_handler);
    }
}

int keyb_read(void) {
    uint16_t scancode;

    if (writepos == readpos) {
        return -1;
    }

    scancode = buffer[readpos];
    readpos = (readpos + 1) % BUFFER_SIZE;
    return scancode;
}
