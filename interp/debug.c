#include "listener.h"
#include "stak-vm.h"

#include <stdio.h>
#include <string.h>

// #define TR(x) printf x
#define TR(x)

#ifdef __WATCOMC__
#define attribute_packed
#else
#define _Packed
#define attribute_packed __attribute__((packed))
#endif

extern Module mod;
extern Thread thr;

// DEBUGGING PRIMITIVES

enum {
    SEGMENT_BC = 0,
    SEGMENT_FUNC = 1,
    SEGMENT_GLOB = 2,
};

static void debug_begin_exec(int func_idx, int nargs) {
    // (re-)initialize thread
    thr.frames_paused = 0;
    thr.fp = 0;
    thr.frame = 0;

    // enter function
    thr.state = THREAD_EXECUTING;
    thr.func_index = func_idx;
    thr.pc = mod.functions[func_idx].bytecode_offset;
    thr.sp = mod.functions[func_idx].num_locals;
}

static void* debug_get_write_buffer(int segment, size_t offset, size_t nbytes) {
    if (segment == SEGMENT_BC) {
        // FIXME: must validate that it fits
        if (mod.bytecode_length < offset + nbytes) {
            mod.bytecode_length = offset + nbytes;
        }

        return mod.bytecode + offset;
    }
    else if (segment == SEGMENT_FUNC) {
        return ((char*) mod.functions) + offset;
    }
    else if (segment == SEGMENT_GLOB) {
        return ((char*) mod.globals) + offset;
    }

    return NULL;
}

static void debug_reset(void) {
    thr.frames_paused = 0;
    thr.fp = 0;
    thr.frame = 0;

    thr.state = THREAD_TERMINATED;
    thr.func_index = -1;
    thr.pc = -1;
    thr.sp = 0;
}

// SERIAL PROTOCOL

enum {
    OP_HELLO = 'h',
    OP_BEGIN_EXEC = 'x',
    OP_RESET = 'r',
    OP_WRITE_MEM = 'w',
};

// framing state
enum {
    FSTATE_INIT,
    FSTATE_INFRAME,
    FSTATE_ESCAPE,
};

enum {
    ESCAPE_MARKER = 0x7D,
    FRAME_DELIMITER = 0x7E,
};

enum {
    STATE_INIT,
    STATE_RECEPTION,
    STATE_WRITE_MEM,
};

_Packed
struct BeginExecCmd {
    uint8_t opcode;
    uint8_t func_idx;
    uint8_t nargs;
} attribute_packed;

_Packed
struct WriteMemCmd {
    uint8_t opcode;
    uint8_t segment;    // TODO: rename to avoid confusion with x86 segments
                        //       ideas: Address Space, Section
    uint16_t offset;
    uint16_t nbytes;
} attribute_packed;

static uint8_t state = STATE_INIT;
static uint8_t fstate = FSTATE_INIT;
static char buf[32];
static uint8_t buf_used = 0;
static uint8_t* write_buffer = NULL;

static void process_byte(int rc) {
    if (buf_used + 1 >= sizeof(buf)) {
        TR(("buffer overflow\n"));
        fstate = FSTATE_INIT;
        state = STATE_INIT;
    }

    switch (fstate) {
    case FSTATE_INIT:
        if (rc == FRAME_DELIMITER) {
            fstate = FSTATE_INFRAME;
        }
        return;

    case FSTATE_INFRAME:
        if (rc == ESCAPE_MARKER) {
            fstate = FSTATE_ESCAPE;
            return;
        }
        else if (rc == FRAME_DELIMITER) {
            // indicate end-of-frame
            rc = -1;
        }
        break;

    case FSTATE_ESCAPE:
        if (rc == FRAME_DELIMITER) {
            // error, indicate it to command parser and restart frame reception
            rc = -2;
            fstate = FSTATE_INFRAME;
            break;
        }
        rc ^= 0x20;
        fstate = FSTATE_INFRAME;
        break;
    }

    // rc is now -1 (end of frame), -2 (error, frame aborted) or the received byte
    // now interpret the commands

    if (rc == -1) {
        TR(("debug: received end-of-frame with state %d, buf:", (int) state));
        for (int i = 0; i < buf_used; i++) {
            TR((" %02X", buf[i]));
        }
        TR(("\n"));
    }

    switch (state) {
    case STATE_INIT:
        if (rc >= 0) {
            buf_used = 0;
            buf[buf_used++] = rc;
            state = STATE_RECEPTION;    // TODO: really needs to be a separate state?
            break;
        }
        // else stay in init
        break;

    case STATE_RECEPTION:
        if (rc == -2) {
            state = STATE_INIT;
        }

        if (rc == -1) {
            if (buf[0] == OP_HELLO && buf_used == 1) {
                TR(("debug: HELLO\n"));
                static const uint8_t reply[] = {FRAME_DELIMITER, OP_HELLO, 'S', 'T', 'A', 'K', FRAME_DELIMITER};
                listener_send(reply, sizeof(reply));
            }
            if (buf[0] == OP_RESET && buf_used == 1) {
                TR(("debug: RESET\n"));
                debug_reset();
                static const uint8_t reply[] = {OP_RESET, FRAME_DELIMITER};
                listener_send(reply, sizeof(reply));
            }
            else if (buf[0] == OP_BEGIN_EXEC && buf_used == sizeof(struct BeginExecCmd)) {
                struct BeginExecCmd cmd;
                memcpy(&cmd, buf, sizeof(cmd));

                TR(("debug: BEGIN_EXEC %u %u\n", cmd.func_idx, cmd.nargs));
                debug_begin_exec(cmd.func_idx, cmd.nargs);

                static const uint8_t reply[] = {OP_BEGIN_EXEC, FRAME_DELIMITER};
                listener_send(reply, sizeof(reply));
            }
            else {
                TR(("debug: unrecognized op %u (%uB)\n", buf[0], buf_used));
            }
            state = STATE_INIT;
            break;
        }

        buf[buf_used++] = rc;

        if (buf[0] == OP_WRITE_MEM && buf_used == sizeof(struct WriteMemCmd)) {
            struct WriteMemCmd cmd;
            memcpy(&cmd, buf, sizeof(cmd));

            TR(("debug: WRITE_MEM %u %u %u\n", cmd.segment, cmd.offset, cmd.nbytes));
            write_buffer = (uint8_t*) debug_get_write_buffer(cmd.segment, cmd.offset, cmd.nbytes);
            state = STATE_WRITE_MEM;
            break;
        }

        break;

    case STATE_WRITE_MEM:
        if (rc < 0) {
            static const uint8_t reply[] = {OP_WRITE_MEM, FRAME_DELIMITER};
            listener_send(reply, sizeof(reply));

            state = STATE_INIT;
        }
        else {
            *write_buffer++ = rc;
            // TODO: no checking of byte count?
        }
        break;
    }
}

void debug_tick(void) {
    int rc;

    while ((rc = listener_poll_byte()) >= 0) {
        process_byte(rc);
    }
}
