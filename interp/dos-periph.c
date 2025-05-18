#include "periph.h"

#include <conio.h>
#include <dos.h>
#include <math.h>
#include <stdio.h>

void keyb_init(void);
void keyb_shutdown(void);
int keyb_read(void);

#define VGA_STATUS_REGISTER 0x3DA
#define VRETRACE_FLAG       0x08

enum {
    SCRW = 320,
    SCRH = 200,
};

static bool key_state[KEY_MAX];     // true = held down

// TODO: use near pointer and DS switching instead
static unsigned fb_segment;
char far *screen;
#define PXL(y_, x_) screen[(y_)*320+(x_)]

static void swap_points(int* x1, int* y1, int* x2, int* y2) {
    int x = *x1;
    int y = *y1;
    *x1 = *x2;
    *y1 = *y2;
    *x2 = x;
    *y2 = y;
}

void periph_init(void) {
    if (_dos_allocmem(SCRH * (SCRW / 16), &fb_segment) != 0) {
        fputs("interp: failed to allocate back buffer", stderr);
        exit(1);
    }

    screen = (char far*) MK_FP(fb_segment, 0);

    _asm {
        mov ax, 13h
        int 10h
    }

    keyb_init();
}

void periph_shutdown(void) {
    keyb_shutdown();

    _asm {
        mov ax, 3
        int 10h
    }
}

int draw_line(Thread* thr, int color, int x1, int y1, int x2, int y2) {
    int dx, dy, err, x, y;
    uint8_t near* fb = 0;

    if (x2 < x1) {
        // TODO: would be better inline
        swap_points(&x1, &y1, &x2, &y2);
    }

    _asm {
        push ds
        mov ds, fb_segment
    }

    dx = x2 - x1;
    dy = y2 - y1;

    if (y2 >= y1 && dx >= dy) {
        // right-right-down
        err = 3 * dy - 2 * dx;
        fb = (uint8_t*)(y1 * SCRW + x1);

        for (x = x1; ; ) {
            *fb++ = color;
            x++;
            if (x >= x2) { break; }
            if (err > 0) {
                err -= 2 * dx;
                fb += SCRW;
            }
            err += 2 * dy;
        }
    }
    else if (y2 < y1 && dx >= -dy) {
        // right-right-up
        dy = -dy;

        err = 3 * dy - 2 * dx;
        fb = (uint8_t*)((y1 - 1) * SCRW + x1);

        for (x = x1; ; ) {
            *fb++ = color;
            x++;
            if (x >= x2) { break; }
            if (err > 0) {
                err -= 2 * dx;
                fb -= SCRW;
            }
            err += 2 * dy;
        }
    }
    else if (y2 >= y1 && dx < dy) {
        // right-down-down
        err = 3 * dx - 2 * dy;
        fb = (uint8_t*)(y1 * SCRW + x1);

        for (y = y1; ; ) {
            *fb = color;
            y++;
            if (y >= y2) { break; }
            fb += SCRW;
            if (err > 0) {
                err -= 2 * dy;
                fb++;
            }
            err += 2 * dx;
        }
    }
    else if (y2 < y1 && dx < -dy) {
        // right-up-up
        dy = -dy;

        err = 3 * dx - 2 * dy;
        fb = (uint8_t*)((y1 - 1) * SCRW + x1);

        for (y = y1 - 1; ; ) {
            *fb = color;
            y--;
            if (y < y2) { break; }
            fb -= SCRW;
            if (err > 0) {
                err -= 2 * dy;
                fb++;
            }
            err += 2 * dx;
        }
    }

    _asm {
        pop ds
    }

    return 0;
}

int fill_rect(Thread* thr, int color, int x, int y, int w, int h) {
    // clip to screen
    // examples: (-50, 70) -> (0, 20)
    //           (-50, 40) -> (0, -10) -> reject
    if (x < 0) {
        w += x;
        x = 0;
    }
    if (y < 0) {
        h += y;
        y = 0;
    }
    if (w < 0 || h < 0) {
        return 0;
    }
    if (x + w > SCRW) {
        w = SCRW - x;
    }
    if (y + h > SCRH) {
        h = SCRH - y;
    }

    // optimize full-screen clear (use word store)
    if (x == 0 && y == 0 && w == SCRW && h == SCRH) {
        _asm {
            push di
            push es

            mov ax, fb_segment
            mov es, ax
            xor di, di
            mov ax, color
            mov cl, 8
            shl ax, cl
            or ax, color
            mov cx, 32000
            rep stosw

            pop es
            pop di
        }

        return 0;
    }

    // h is now y2
    h += y;

    // TODO: use word store. needs special hadnling if starting/ending on odd columns
    // w /= 2;
    // color = (color & 0xff) * 0x0101;

    _asm {
        push bx
        push di
        push es

        mov ax, fb_segment
        mov es, ax

        // ax = clobber
        // bx = row counter
        // cx = count
        // dx = clobber
        // di = write pointer

        mov bx, y

        $1:
        // compute di = y * 320 + x
        mov ax, bx
        mov di, 320
        // dx:ax = ax * di
        mul di
        add ax, x
        mov di, ax

        mov ax, color
        mov cx, w
        rep stosb

        inc bx
        cmp bx, h
        jl $1

        pop es
        pop di
        pop bx
    }

    return 0;
}

int fill_triangle(Thread* thr, int color, int x1, int y1, int x2, int y2, int x3, int y3) {
    if (!screen) {
        return -1;
    }

    // reorder vertices so that y1 <= y2 <= y3

    if (y2 < y1) {
        swap_points(&x2, &y2, &x1, &y1);
    }

    if (y3 < y1) {
        swap_points(&x3, &y3, &x1, &y1);
    }

    if (y3 < y2) {
        swap_points(&x3, &y3, &x2, &y2);
    }

    // see https://mcejp.github.io/2020/11/06/bresenham.html for algorithm derivation
    int E1, E2;
    int X_left = x1;
    int X_right = x1;

    if (x2 >= x1) {
        E1 = (y2 - y1) - (x2 - x1);
    }
    else {
        E1 = -(y2 - y1) - (x2 - x1);
    }

    if (x3 >= x1) {
        E2 = (y3 - y1) - (x3 - x1);
    }
    else {
        E2 = -(y3 - y1) - (x3 - x1);
    }

    for (int Y = y1; Y < y2; Y++) {
        if (x2 >= x1) {
            while (E1 < 0) {
                X_left++;
                E1 += 2 * (y2 - y1);
            }
        }
        else {
            while (E1 >= 0) {
                X_left--;
                E1 -= 2 * (y2 - y1);
            }
        }

        if (x3 >= x1) {
            while (E2 < 0) {
                X_right++;
                E2 += 2 * (y3 - y1);
            }
        }
        else {
            while (E2 >= 0) {
                X_right--;
                E2 -= 2 * (y3 - y1);
            }
        }

        for (int xx = min(X_left, X_right); xx < max(X_left, X_right); xx++) {
            PXL(Y, xx) = color;
        }

        E1 -= 2 * (x2 - x1);
        E2 -= 2 * (x3 - x1);
    }

    // setup for 2nd half

    X_left = x2;

    if (x3 >= x2) {
        E1 = (y3 - y2) - (x3 - x2);
    }
    else {
        E1 = -(y3 - y2) - (x3 - x2);
    }

    for (int Y = y2; Y < y3; Y++) {
        if (x3 >= x2) {
            while (E1 < 0) {
                X_left++;
                E1 += 2 * (y3 - y2);
            }
        }
        else {
            while (E1 >= 0) {
                X_left--;
                E1 -= 2 * (y3 - y2);
            }
        }

        if (x3 >= x1) {
            while (E2 < 0) {
                X_right++;
                E2 += 2 * (y3 - y1);
            }
        }
        else {
            while (E2 >= 0) {
                X_right--;
                E2 -= 2 * (y3 - y1);
            }
        }

        for (int xx = min(X_left, X_right); xx < max(X_left, X_right); xx++) {
            PXL(Y, xx) = color;
        }

        E1 -= 2 * (x3 - x2);
        E2 -= 2 * (x3 - x1);
    }

    return 0;
}

void frame_start(void) {
    int key;

    while ((key = keyb_read()) != -1) {
        // I used to distinguish extended codes for arrow keys,
        // but on the Pocket 8086 only the non-extended codes are emitted
        // (as would have been the case on a classic PC XT keyboard, I suppose)
        switch (key & 0xff) {
        case 0x0001:  // Esc
            periph_shutdown();
            exit(0);
            break;
        case 0x001D:  // LCtrl
        case 0x009D:
            key_state[KEY_A] = !(key & 0x80);
            break;
        case 0x0048:
        case 0x00C8:
            key_state[KEY_UP] = !(key & 0x80);
            break;
        case 0x004B:
        case 0x00CB:
            key_state[KEY_LEFT] = !(key & 0x80);
            break;
        case 0x004D:
        case 0x00CD:
            key_state[KEY_RIGHT] = !(key & 0x80);
            break;
        case 0x0050:
        case 0x00D0:
            key_state[KEY_DOWN] = !(key & 0x80);
            break;
        }
    }
}

void frame_end(void) {
    // wait until NOT in retrace
    while (inp(VGA_STATUS_REGISTER) & VRETRACE_FLAG);

    // wait until in retrace
    while (!(inp(VGA_STATUS_REGISTER) & VRETRACE_FLAG));

    // copy back buffer to VRAM
    _asm {
        push ds
        push es

        // movsw copies CX words from DS:SI to ES:DI
        mov ax, fb_segment
        mov ds, ax
        mov ax, 0xA000
        mov es, ax
        xor si, si
        xor di, di

        mov cx, 32000
        cld
        rep movsw

        pop es
        pop ds
    }
}

int key_held(Thread* thr, int index) {
    // TODO: this needs to be actually implemented

    if (index >= 0 && index < KEY_MAX) {
        return key_state[index] ? 1 : 0;
    }
    else {
        return 0;
    }
}

#define M_PI 3.1415926535

int sin_fxp(Thread* thr, int angle) {
    return (int)round(sin(angle * M_PI / 32768.0) * 16384.0);
}
