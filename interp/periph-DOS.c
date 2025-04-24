#include "periph.h"

#include <dos.h>
#include <math.h>

enum {
    SCRW = 320,
    SCRH = 200,
};

static bool key_state[KEY_MAX];     // true = held down

// TODO: use near pointer and DS switching instead
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
    _asm {
        mov ax,13h
        int 10h
    }

    screen = (char far *)MK_FP(0xA000, 0);
}

int draw_line(Thread* thr, int color, int x1, int y1, int x2, int y2) {
    if (!screen) {
        return -1;
    }

    // this implementation is probably inefficient, it's just a derivative of the triangle fill code

    // we need abs(dy)>abs(dx); swap X/Y if not the case
    bool swapped = false;

    if (abs(y2 - y1) < abs(x2 - x1)) {
        swap_points(&x1, &x2, &y1, &y2);
        swapped = true;
    }

    // reorder vertices so that y1 <= y2

    if (y2 < y1) {
        swap_points(&x2, &y2, &x1, &y1);
    }

    // see https://mcejp.github.io/2020/11/06/bresenham.html for algorithm derivation

    int E;
    int X = x1;

    if (x2 >= x1) {
        E = (y2 - y1) - (x2 - x1);
    }
    else {
        E = -(y2 - y1) - (x2 - x1);
    }

    for (int Y = y1; Y < y2; Y++) {
        if (x2 >= x1) {
            while (E < 0) {
                X++;
                E += 2 * (y2 - y1);
            }
        }
        else {
            while (E >= 0) {
                X--;
                E -= 2 * (y2 - y1);
            }
        }

        // TODO: check for off-screen
        PXL(swapped ? X : Y, swapped ? Y : X) = color;

        E -= 2 * (x2 - x1);
    }

    return 0;
}

int fill_rect(Thread* thr, int color, int x, int y, int w, int h) {
    if (!screen) {
        return -1;
    }

    // highly sub-optimal
    for (int yy = y; yy < y + h && y < SCRH; yy++) {
        for (int xx = x; xx < x + w && x < SCRW; xx++) {
            PXL(yy, xx) = color;
        }
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
    // TODO: wait for vertical retrace
}

void frame_end(void) {
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
