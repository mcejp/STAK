#pragma once

#include "stak-vm.h"

enum {
    KEY_UP,
    KEY_DOWN,
    KEY_LEFT,
    KEY_RIGHT,
    KEY_CTRL,
    KEY_MAX
};

void periph_init(void);
void periph_shutdown(void);
void frame_start(void);
void frame_end(void);

// the majority of these don't even need a Thread reference btw

int draw_line(Thread* thr, int color, int x0, int y0, int x1, int y1);
int fill_rect(Thread* thr, int color, int x, int y, int w, int h);
int fill_triangle(Thread* thr, int color, int x0, int y0, int x1, int y1, int x2, int y2);
int key_held(Thread* thr, int index);
int key_pressed(Thread* thr, int index);
int key_released(Thread* thr, int index);
int sin_fxp(Thread* thr, int angle);
int cos_fxp(Thread* thr, int angle);
int mul_fxp(Thread* thr, int a, int b);

int do_random(Thread* thr);
int set_random_seed(Thread* thr, int seed);
