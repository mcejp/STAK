#include "periph.h"

#include <stdlib.h>

#define FXP_FRAC_BITS 6

// See https://github.com/mcejp/fixed-point-math/blob/main/sin_cos.cpp
static const int8_t sin_table[65] = {
    0x00, 0x02, 0x03, 0x05, 0x06, 0x08, 0x09, 0x0b, 0x0c, 0x0e,
    0x10, 0x11, 0x13, 0x14, 0x16, 0x17, 0x18, 0x1a, 0x1b, 0x1d,
    0x1e, 0x20, 0x21, 0x22, 0x24, 0x25, 0x26, 0x27, 0x29, 0x2a,
    0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34,
    0x35, 0x36, 0x37, 0x38, 0x38, 0x39, 0x3a, 0x3b, 0x3b, 0x3c,
    0x3c, 0x3d, 0x3d, 0x3e, 0x3e, 0x3e, 0x3f, 0x3f, 0x3f, 0x40,
    0x40, 0x40, 0x40, 0x40, 0x40,
};

#define sin_table_size 65
#define index_mask 63

int sin_fxp(Thread* thr, int angle) {
    int index;

    if ((angle & 0x40) == 0) {
        // 1st or 3rd quarter
        index = angle & index_mask;
    }
    else {
        index = sin_table_size - 1 - (angle & index_mask) - 1;
    }

    if ((angle & 0x80) == 0) {
        return sin_table[index];
    }
    else {
        return -sin_table[index];
    }
}

int cos_fxp(Thread* thr, int angle) {
    return sin_fxp(thr, angle + 0x40);
}

#ifdef __WATCOMC__
int32_t mul16x16(int a, int b);

#pragma aux mul16x16 = \
    "imul dx"       \
    parm [dx] [ax] value [dx ax] modify exact [ax dx];

int mul_fxp(Thread* thr, int a, int b) {
    // This still generates pretty slow code (loop over FXP_FRAC_BITS)
    // It doesn't help that 8086 cannot shift by an immediate >1
    return mul16x16(a, b) >> FXP_FRAC_BITS;
}
#else
int mul_fxp(Thread* thr, int a, int b) {
    return ((int32_t)a * b) >> FXP_FRAC_BITS;
}
#endif

int do_random(Thread* thr) {
    return rand() & 0x7fff;
}

int set_random_seed(Thread* thr, int seed) {
    srand(seed);
    return 0;
}
