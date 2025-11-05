#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "periph.h"
#include "stak-vm.h"

#ifdef HAVE_DEBUG
#include "debug.h"
#include "listener.h"
#endif


typedef struct {
    uint16_t bytecode_length;
    uint8_t num_functions;
    uint8_t num_globals;
    uint8_t main_func_idx;      // useless, linker should just put main first...
    uint8_t pad[3];
} Hdr;

Module mod;
Thread thr;

void usage_exit(void) {
    fprintf(stderr, "usage: stak <filename>\n");
    fprintf(stderr, "       stak -g\n");
    exit(-1);
}

int main(int argc, char** argv) {
    char* filename = NULL;
    bool debug_mode = false;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-g") == 0) {
            debug_mode = true;
        }
        else {
            if (filename) {
                usage_exit();
            }

            filename = argv[i];
        }
    }

    if ((!filename && !debug_mode) || (filename && debug_mode)) {
        usage_exit();
    }

    if (debug_mode) {
        mod.functions = malloc(1024);
        mod.globals = malloc(1024);
        mod.bytecode = malloc(16384);
        mod.bytecode_length = 0;

        // Start as Terminated, since there is no meaningful func_index or pc (no code is loaded)
        thr.state = THREAD_TERMINATED;
        thr.func_index = -1;
        thr.pc = -1;
        thr.sp = 0;
    }
    else {
        FILE* f = fopen(filename, "rb");

        if (!f) {
            perror("fopen");
            return -1;
        }

        Hdr h;
        fread(&h, 1, sizeof(h), f);

        static uint8_t buf[0x8000];
        fread(buf, 1, sizeof(buf), f);

        mod.functions = (Func*) buf;
        mod.globals =   (V*) (buf + h.num_functions * sizeof(Func));
        mod.bytecode =  (uint8_t*) (buf + h.num_functions * sizeof(Func) + h.num_globals * sizeof(V));
        mod.bytecode_length = h.bytecode_length;

        thr.state = THREAD_EXECUTING;
        thr.func_index = h.main_func_idx;
        thr.pc = mod.functions[h.main_func_idx].bytecode_offset;
        thr.sp = mod.functions[h.main_func_idx].argc + mod.functions[h.main_func_idx].num_locals;
    }

    thr.frames_paused = 0;
    thr.fp = 0;
    thr.frame = 0;

#ifdef HAVE_DEBUG
    if (debug_mode) {
        listener_init();
    }
#endif

    // This is not so simple, as resetting the video mode will erase any error message printed
    //atexit(periph_shutdown);

    periph_init();

    while (thr.state != THREAD_TERMINATED || debug_mode) {
        frame_start();

        if (thr.frames_paused) {
            thr.frames_paused--;

            if (thr.frames_paused == 0) {
                thr.state = THREAD_EXECUTING;
            }
        }

        stak_exec(&mod, &thr);

        frame_end();

#ifdef HAVE_DEBUG
        if (debug_mode) {
            listener_tick();
            debug_tick();
        }
#endif
    }

    periph_shutdown();

#ifdef HAVE_DEBUG
    if (debug_mode) {
        listener_shutdown();
    }
#endif
}
