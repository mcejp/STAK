#pragma once

#include "stak-vm.h"

void frame_start(void);
void frame_end(void);

// the majority of these don't even need a Thread reference btw

int draw_line(Thread* thr, int color, int x0, int y0, int x1, int y1);
int fill_rect(Thread* thr, int color, int x, int y, int w, int h);
int fill_triangle(Thread* thr, int color, int x0, int y0, int x1, int y1, int x2, int y2);
int key_held(Thread* thr, int index);
int set_video_mode(Thread* thr, int w, int h);
int sin_fxp(Thread* thr, int angle);