#include <stdio.h>
#include <stdlib.h>

#include "periph.h"
#include "stak-isa.h"
#include "stak-vm.h"


static V stack[STACK_SIZE];

// #define TR(x) printf x
#define TR(x)

#define CURR_FUNC (mod->functions[thr->func_index])
#define DROP() --thr->sp
#define POP() stack[--thr->sp]
#define PUSH(x) stack[thr->sp++] = (x)

static int pause_frames(Thread* thr, int count) {
    if (count > 0) {
        thr->state = THREAD_SUSPENDED;
        thr->frames_paused = count;
    }
    return 0;
}

void stak_exec(Module const* mod, Thread* thr) {
    uint8_t const* bc = mod->bytecode;

    while (thr->state == THREAD_EXECUTING) {
        if (thr->pc >= mod->bytecode_length) {
            fprintf(stderr, "pc overflow\n");
            exit(-1);
        }

        uint8_t opcode = bc[thr->pc++];
        int8_t op1, op2;
        V ret_val;

        TR(("[%04X] op %02X\tsp=%d\tfp=%d\n", thr->pc - 1, opcode, thr->sp, thr->fp));

        switch (opcode) {
        case OP_GETCONST:
            op1 = bc[thr->pc++];
            TR(("  getconst %d\n", op1));

            stack[thr->sp++] = mod->constants[CURR_FUNC.constants_offset + op1];
            TR(("    (%d)\n", stack[thr->sp - 1]));
            break;

        case OP_CALLFUNC:
            op1 = bc[thr->pc++];    // func_idx
            TR(("  call/func %d\n", op1));

            // save current pc
            thr->frames[thr->frame].func_index = thr->func_index;
            thr->frames[thr->frame].pc = thr->pc;
            thr->frames[thr->frame].fp = thr->fp;
            thr->frame++;

            // call function
            thr->func_index = op1;
            thr->pc = mod->functions[op1].bytecode_offset;

            // pop args to locals + allocate space for the rest
            thr->fp = thr->sp - mod->functions[op1].argc;
            thr->sp += mod->functions[op1].num_locals;
            break;

        case OP_CALL_EXT:
            op1 = bc[thr->pc++];    // ext_func_idx
            TR(("  call/ext %d\n", op1));

#define BUILTIN_1(id, c_name, name) case id:\
                thr->sp -= 1; \
                TR(("    (" name " %d)\n", stack[thr->sp])); \
                ret_val = c_name(thr, stack[thr->sp]); \
                PUSH(ret_val); \
                break;

#define BUILTIN_2(id, c_name, name) case id:\
                thr->sp -= 2; \
                TR(("    (" name " %d %d)\n", stack[thr->sp], stack[thr->sp + 1])); \
                ret_val = c_name(thr, stack[thr->sp], stack[thr->sp + 1]); \
                PUSH(ret_val); \
                break;

#define BUILTIN_BIN_OP(id, c_name, name) case id:\
                thr->sp -= 2; \
                TR(("    (%d " name " %d)\n", stack[thr->sp], stack[thr->sp + 1])); \
                ret_val = stack[thr->sp] c_name stack[thr->sp + 1]; \
                PUSH(ret_val); \
                break;

#define BUILTIN_5(id, c_name, name) case id:\
                thr->sp -= 5; \
                TR(("    (" name " %d %d %d %d %d)\n", stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4])); \
                ret_val = c_name(thr, stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4]); \
                PUSH(ret_val); \
                break;

#define BUILTIN_7(id, c_name, name) case id:\
                thr->sp -= 7; \
                TR(("    (" name " %d %d %d %d %d %d %d)\n", stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4], \
                        stack[thr->sp + 5], stack[thr->sp + 6])); \
                ret_val = c_name(thr, stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4], \
                        stack[thr->sp + 5], stack[thr->sp + 6]); \
                PUSH(ret_val); \
                break;

            switch (op1) {
            BUILTIN_5(0, fill_rect, "fill-rect");
            BUILTIN_1(1, pause_frames, "pause-frames");
            BUILTIN_BIN_OP(3, <, "<");
            BUILTIN_BIN_OP(4, +, "+");
            BUILTIN_BIN_OP(5, *, "*");
            BUILTIN_1(6, key_held, "key-held?");
            BUILTIN_BIN_OP(7, -, "-");
            BUILTIN_7(8, fill_triangle, "fill-triangle");
            BUILTIN_BIN_OP(9, >>, ">>");
            BUILTIN_1(10, sin_fxp, "sin");
            BUILTIN_5(11, draw_line, "draw-line");
            BUILTIN_BIN_OP(12, /, "/");
            BUILTIN_BIN_OP(13, ==, "=");
            BUILTIN_BIN_OP(14, >, ">");
            BUILTIN_BIN_OP(15, &&, "and");
            default:
                printf("  unhandled, sorry\n");
                exit(0);
            }
            break;

        case OP_DROP:
            TR(("  drop\n"));
            DROP();
            break;

        case OP_GETGLOBAL:
            op1 = bc[thr->pc++];    // index
            TR(("  getglobal %d\n", op1));
            PUSH(mod->globals[op1]);
            break;

        case OP_GETLOCAL:
            op1 = bc[thr->pc++];    // index
            TR(("  getlocal %d\n", op1));
            PUSH(stack[thr->fp + op1]);
            break;

        case OP_JMP:
            op1 = bc[thr->pc++];    // distance LSB
            op2 = bc[thr->pc++];    // distance MSB
            TR(("  jmp %+d\n", (op2 << 8 | (uint8_t)op1)));
            thr->pc += (op2 << 8 | (uint8_t)op1);
            break;

        case OP_JZ:
            op1 = bc[thr->pc++];    // distance LSB
            op2 = bc[thr->pc++];    // distance MSB
            TR(("  jz %+d\n", (op2 << 8 | (uint8_t)op1)));
            if (POP() == 0) {
                thr->pc += (op2 << 8 | (uint8_t)op1);
            }
            break;

        case OP_RET:
            op1 = bc[thr->pc++];    // retc
            TR(("  ret %d\n", op1));

            // TODO: stop abusing ret_val as a temporary, the compiler is not so dumb
            // at this point: thr->sp == thr->fp + argc + nloc + retc
            // rightmost:   [thr->sp - 1]    => [thr->sp - nloc - argc - retc + retc - 1]
            // ...
            // leftmost:    [thr->sp - retc] => [thr->sp - nloc - argc - retc]
            for (ret_val = 0; ret_val < op1; ret_val++) {
                thr->sp--;
                stack[thr->sp - CURR_FUNC.num_locals - CURR_FUNC.argc] = stack[thr->sp];
            }

            thr->sp = thr->sp - CURR_FUNC.num_locals - CURR_FUNC.argc + op1;

            if (thr->frame == 0) {
                TR(("  return from main -> %d\n", ret_val));
                thr->state = THREAD_TERMINATED;
                return;
            }

            // restore fp & pc
            thr->frame--;
            thr->fp = thr->frames[thr->frame].fp;
            thr->pc = thr->frames[thr->frame].pc;
            thr->func_index = thr->frames[thr->frame].func_index;
            break;

        case OP_SETGLOBAL:
            op1 = bc[thr->pc++];    // index
            TR(("  setglobal %d\n", op1));
            mod->globals[op1] = POP();
            break;

        case OP_SETLOCAL:
            op1 = bc[thr->pc++];    // index
            TR(("  setlocal %d\n", op1));
            stack[thr->fp + op1] = POP();
            break;

        case OP_ZERO:
            TR(("  zero\n"));
            PUSH(0);
            break;

        default:
            printf("  unhandled, sorry\n");
            exit(0);
        }
    }
}
