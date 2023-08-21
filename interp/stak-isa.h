#pragma once

enum {
    OP_GETCONST = 0,
    OP_ZERO = 1,
    OP_DROP = 2,
    OP_GETGLOBAL = 3,
    OP_SETGLOBAL = 4,
    OP_GETLOCAL = 5,
    OP_SETLOCAL = 6,

    OP_CALLFUNC = 10,
    OP_CALL_EXT = 11,
    OP_RET = 13,

    OP_JMP = 20,
    OP_JZ = 21,
};
