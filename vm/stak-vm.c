#include <stdio.h>
#include <stdlib.h>

#include "debug.h"
#include "periph.h"
#include "stak-isa.h"
#include "stak-vm.h"


static V stack[STACK_SIZE];

// #define TR(x) printf x
#define TR(x)

#define CURR_FUNC (mod->functions[thr->func_index])
#define DROP() --thr->sp
#define TOP() stack[thr->sp - 1]
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

        // define some helper macros for the built-in library

#define BUILTIN_0(id, c_name, name) case id:\
                TR(("  " name "\n")); \
                ret_val = c_name(thr); \
                PUSH(ret_val); \
                break;

#define BUILTIN_1(id, c_name, name) case id:\
                thr->sp -= 1; \
                TR(("  " name " %d\n", stack[thr->sp])); \
                ret_val = c_name(thr, stack[thr->sp]); \
                PUSH(ret_val); \
                break;

#define BUILTIN_UNARY_OP(id, operator, name) case id:\
                thr->sp -= 1; \
                TR(("  " name " %d\n", stack[thr->sp])); \
                ret_val = operator stack[thr->sp]; \
                PUSH(ret_val); \
                break;

#define BUILTIN_2(id, c_name, name) case id:\
                thr->sp -= 2; \
                TR(("  " name " %d %d\n", stack[thr->sp], stack[thr->sp + 1])); \
                ret_val = c_name(thr, stack[thr->sp], stack[thr->sp + 1]); \
                PUSH(ret_val); \
                break;

#define BUILTIN_BIN_OP(id, operator, name) case id:\
                thr->sp -= 2; \
                TR(("  %d " name " %d\n", stack[thr->sp], stack[thr->sp + 1])); \
                ret_val = stack[thr->sp] operator stack[thr->sp + 1]; \
                PUSH(ret_val); \
                break;

#define BUILTIN_5(id, c_name, name) case id:\
                thr->sp -= 5; \
                TR(("  " name " %d %d %d %d %d\n", stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4])); \
                ret_val = c_name(thr, stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4]); \
                PUSH(ret_val); \
                break;

#define BUILTIN_7(id, c_name, name) case id:\
                thr->sp -= 7; \
                TR(("  " name " %d %d %d %d %d %d %d\n", stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4], \
                        stack[thr->sp + 5], stack[thr->sp + 6])); \
                ret_val = c_name(thr, stack[thr->sp], stack[thr->sp + 1], \
                        stack[thr->sp + 2], stack[thr->sp + 3], stack[thr->sp + 4], \
                        stack[thr->sp + 5], stack[thr->sp + 6]); \
                PUSH(ret_val); \
                break;

            // math
            BUILTIN_BIN_OP(128, +, "+");
            BUILTIN_BIN_OP(129, -, "-");
            BUILTIN_BIN_OP(130, *, "*");
            BUILTIN_BIN_OP(131, /, "/");
            BUILTIN_BIN_OP(132, %, "%%");
            BUILTIN_BIN_OP(133, <<, "<<");
            BUILTIN_BIN_OP(134, >>, ">>");
            BUILTIN_2(135, mul_fxp, "mul@");
            BUILTIN_1(136, sin_fxp, "sin@");
            BUILTIN_1(137, cos_fxp, "cos@");

            // comparison + logic
            BUILTIN_BIN_OP(144, <, "<");
            BUILTIN_BIN_OP(145, <=, "<=");
            BUILTIN_BIN_OP(146, ==, "=");
            BUILTIN_BIN_OP(147, !=, "!=");
            BUILTIN_BIN_OP(148, >, ">");
            BUILTIN_BIN_OP(149, >=, ">=");
            BUILTIN_UNARY_OP(150, !, "not");
            BUILTIN_BIN_OP(151, &&, "and");
            BUILTIN_BIN_OP(152, ||, "or");

            // graphics
            BUILTIN_5(176, draw_line, "draw-line");
            BUILTIN_5(177, fill_rect, "fill-rect");
            BUILTIN_7(178, fill_triangle, "fill-triangle");
            BUILTIN_1(179, pause_frames, "pause-frames");

            // keyboard
            BUILTIN_1(192, key_pressed, "key-pressed?");
            BUILTIN_1(193, key_released, "key-released?");
            BUILTIN_1(194, key_held, "key-held?");

            // random
            BUILTIN_0(208, do_random, "random");
            BUILTIN_1(209, set_random_seed, "set-random-seed!");

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
            TR(("  getlocal %d\t(value=%d)\n", op1, stack[thr->fp + op1]));
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

        case OP_PUSHCONST:
            op1 = bc[thr->pc++];    // LSB
            op2 = bc[thr->pc++];    // MSB

            TR(("  pushconst "));
            PUSH(((uint8_t)op2) << 8 | (uint8_t)op1);
            TR((" %d\n", stack[thr->sp - 1]));
            break;

        case OP_RET:
            op1 = bc[thr->pc++];    // retc
            TR(("  ret %d\n", op1));

            // TODO: stop abusing ret_val as a temporary, the compiler is not so dumb
            // at this point: thr->sp == thr->fp + argc + nloc + retc
            // rightmost:   [thr->sp - 1]    => [thr->sp - nloc - argc - retc + retc - 1]
            // ...
            // leftmost:    [thr->sp - retc] => [thr->sp - nloc - argc - retc]
            thr->sp -= op1;
            for (ret_val = 0; ret_val < op1; ret_val++) {
                stack[thr->sp - CURR_FUNC.num_locals - CURR_FUNC.argc] = stack[thr->sp];
                thr->sp++;
            }

            thr->sp = thr->sp - CURR_FUNC.num_locals - CURR_FUNC.argc;

            if (thr->frame == 0) {
                TR(("  return from main -> %d value(s) (sp = %d)\n", ret_val, thr->sp));
                thr->state = THREAD_TERMINATED;
                // a well-formed program should always terminate with thr->sp == ret_val... I think
                debug_on_program_completion(ret_val, &stack[thr->sp - ret_val]);
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
            TR(("  setlocal %d\t(value=%d)\n", op1, TOP()));
            stack[thr->fp + op1] = POP();
            break;

        case OP_ZERO:
            TR(("  zero\n"));
            PUSH(0);
            break;

        default:
            printf("  opcode error %d\n", opcode);
            exit(0);
        }
    }
}
