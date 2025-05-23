#include "periph.h"

#include <SDL.h>

#include "sdl-vga-palette.h"

static SDL_Window* window;
static SDL_Surface* screenSurface;

enum { CANVAS_W = 320 };
enum { CANVAS_H = 200 };
enum { WINDOW_W = 640 };
enum { WINDOW_H = 480 };

static uint16_t keys_curr;
static uint16_t keys_prev;

static int min(int a, int b) {
    return (a < b) ? a : b;
}

static void swap_points(int* x1, int* y1, int* x2, int* y2) {
    int x = *x1;
    int y = *y1;
    *x1 = *x2;
    *y1 = *y2;
    *x2 = x;
    *y2 = y;
}

void periph_init(void) {
    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        fprintf(stderr, "SDL could not initialize: %s\n", SDL_GetError());
        exit(-1);
    }

    window = SDL_CreateWindow(
            "STAK VM",
            SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
            WINDOW_W, WINDOW_H,
            SDL_WINDOW_SHOWN
            );

    if (!window) {
        fprintf(stderr, "Window could not be created: %s\n", SDL_GetError());
        exit(-1);
    }

    // TODO: https://wiki.libsdl.org/SDL2/SDL_SetWindowResizable

    // Create an off-screen surface for the canvas
    screenSurface = SDL_CreateRGBSurface(0, CANVAS_W, CANVAS_H, 32, 0, 0, 0, 0);
    if (!screenSurface) {
        fprintf(stderr, "Off-screen surface could not be created: %s\n", SDL_GetError());
        exit(-1);
    }
}

void periph_shutdown(void) {
    SDL_Quit();
}

static void putpixel(int x, int y, uint8_t color) {
    SDL_Rect rect = { x, y, 1, 1 };
    SDL_FillRect(screenSurface, &rect, vga_palette[color]);
}

int draw_line(Thread* thr, int color, int x1, int y1, int x2, int y2) {
    if (!screenSurface) {
        return -1;
    }

    color &= 0xff;

    int dx, dy, err, x, y;

    if (x2 < x1) {
        // TODO: would be better inline
        swap_points(&x1, &y1, &x2, &y2);
    }

    dx = x2 - x1;
    dy = y2 - y1;

    if (y2 >= y1 && dx >= dy) {
        // right-right-down
        err = 3 * dy - 2 * dx;
        y = y1;

        for (x = x1; x < x2; x++) {
            putpixel(x, y, color);
            if (err > 0) {
                err -= 2 * dx;
                y++;
            }
            err += 2 * dy;
        }
    }
    else if (y2 < y1 && dx >= -dy) {
        // right-right-up
        dy = -dy;

        err = 3 * dy - 2 * dx;
        y = y1 - 1;

        for (x = x1; x < x2; x++) {
            putpixel(x, y, color);
            if (err > 0) {
                err -= 2 * dx;
                y--;
            }
            err += 2 * dy;
        }
    }
    else if (y2 >= y1 && dx < dy) {
        // right-down-down
        err = 3 * dx - 2 * dy;
        x = x1;

        for (y = y1; y < y2; y++) {
            putpixel(x, y, color);
            if (err > 0) {
                err -= 2 * dy;
                x++;
            }
            err += 2 * dx;
        }
    }
    else if (y2 < y1 && dx < -dy) {
        // right-up-up
        dy = -dy;

        err = 3 * dx - 2 * dy;
        x = x1;

        for (y = y1 - 1; y >= y2; y--) {
            putpixel(x, y, color);
            if (err > 0) {
                err -= 2 * dy;
                x++;
            }
            err += 2 * dx;
        }
    }

    return 0;
}

int fill_rect(Thread* thr, int color, int x, int y, int w, int h) {
    if (!screenSurface) {
        return -1;
    }

    color &= 0xff;

    SDL_Rect rect = { x, y, w, h };
    SDL_FillRect(screenSurface, &rect, vga_palette[color]);
    return 0;
}

int fill_triangle(Thread* thr, int color, int x1, int y1, int x2, int y2, int x3, int y3) {
    if (!screenSurface) {
        return -1;
    }

    color &= 0xff;

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

        SDL_Rect rect = { min(X_left, X_right), Y, abs(X_right - X_left), 1 };
        SDL_FillRect(screenSurface, &rect, vga_palette[color]);

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

        SDL_Rect rect = { min(X_left, X_right), Y, abs(X_right - X_left), 1 };
        SDL_FillRect(screenSurface, &rect, vga_palette[color]);

        E1 -= 2 * (x3 - x2);
        E2 -= 2 * (x3 - x1);
    }

    return 0;
}

static void update_key(int key, bool pressed) {
    if (pressed) {
        keys_curr |= (1 << (key));
    }
    else {
        keys_curr &= ~(1 << (key));
    }
}

void frame_start(void) {
    SDL_Event ev;

    keys_prev = keys_curr;

    while (SDL_PollEvent(&ev)) {
        switch (ev.type) {
        case SDL_KEYDOWN:
        case SDL_KEYUP: {
            bool pressed = (ev.type == SDL_KEYDOWN);

            switch (ev.key.keysym.sym) {
            case SDLK_UP:       update_key(KEY_UP, pressed); break;
            case SDLK_DOWN:     update_key(KEY_DOWN, pressed); break;
            case SDLK_LEFT:     update_key(KEY_LEFT, pressed); break;
            case SDLK_RIGHT:    update_key(KEY_RIGHT, pressed); break;
            case 'x':           update_key(KEY_A, pressed); break;
            }

            break;
        }

        case SDL_QUIT:
            exit(0);
            break;
        }
    }
}

void frame_end(void) {
    if (window && screenSurface) {
        SDL_Surface* windowSurface = SDL_GetWindowSurface(window);

        // Scale the off-screen canvas to fill the window
        SDL_Rect destRect = { 0, 0, WINDOW_W, WINDOW_H };
        SDL_BlitScaled(screenSurface, NULL, windowSurface, &destRect);
        SDL_UpdateWindowSurface(window);

        SDL_Delay(1000 / 60);
    }
}

int key_held(Thread* thr, int index) {
    return (keys_curr & (1 << index)) ? 1 : 0;
}

int key_pressed(Thread* thr, int index) {
    return (~keys_prev & keys_curr & (1 << index)) ? 1 : 0;
}

int key_released(Thread* thr, int index) {
    return (keys_prev & ~keys_curr & (1 << index)) ? 1 : 0;
}
