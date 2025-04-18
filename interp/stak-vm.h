#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>


enum {
    MAX_FRAMES = 64,
    STACK_SIZE = 1024,
};

enum {
    THREAD_TERMINATED,
    THREAD_EXECUTING,
    THREAD_SUSPENDED,
};

typedef int16_t V;

typedef struct {
    int func_index;
    int pc;
    int fp;
} Frame;

typedef struct {
    int state;
    int frames_paused;      // belongs here not

    // since VM already accesses Thread through a pointer, maybe we could store these
    // directly in Frame and access through a pointer as well
    int func_index;
    int pc;
    int sp;
    int fp;
    int frame;

    Frame frames[MAX_FRAMES];
} Thread;

typedef struct {
    uint8_t argc, num_locals;
    uint16_t bytecode_offset;
    uint16_t constants_offset;
    uint8_t pad[2];
} Func;

typedef struct {
    Func* functions;
    //size_t num_functions;
    V* constants;
    V* globals;
    uint8_t* bytecode;
    size_t bytecode_length;
} Module;

void stak_exec(Module const* mod, Thread* thr);
