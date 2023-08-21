#include <stdio.h>
#include <stdlib.h>

#include "periph.h"
#include "stak-vm.h"


typedef struct {
    uint16_t bytecode_length;
    uint16_t num_constants;
    uint8_t num_functions;
    uint8_t num_globals;
    uint8_t main_func_idx;      // useless, linker should just put main first...
    uint8_t pad;
} Hdr;


int main(int argc, char** argv) {
    if (argc < 2) { exit (-1); }
    FILE* f = fopen(argv[1], "rb");
    Hdr h;
    fread(&h, 1, sizeof(h), f);

    static uint8_t buf[64*1024];
    fread(buf, 1, sizeof(buf), f);

    Module mod;
    mod.functions = (Func*) buf;
    mod.constants = (V*) (buf + h.num_functions * sizeof(Func));
    mod.globals =   (V*) (buf + h.num_functions * sizeof(Func) + h.num_constants * sizeof(V));
    mod.bytecode =  (uint8_t*) (buf + h.num_functions * sizeof(Func) + h.num_constants * sizeof(V) + h.num_globals * sizeof(V));
    mod.bytecode_length = h.bytecode_length;

    Thread thr;
    thr.terminated = false;
    thr.frames_paused = 0;
    thr.pc = mod.functions[h.main_func_idx].bytecode_offset;
    thr.sp = mod.functions[h.main_func_idx].argc + mod.functions[h.main_func_idx].num_locals;
    thr.fp = 0;
    thr.frames[0].func_index = h.main_func_idx;
    // thr.frames[0].pc = mod.functions[h.main_func_idx].bytecode_offset;
    thr.frame = 0;

    while (!thr.terminated) {
        frame_start();

        if (thr.frames_paused) {
            thr.frames_paused--;
        }
        else {
            stak_exec(&mod, &thr);
        }

        frame_end();
    }
}
