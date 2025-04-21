(import dataclasses [dataclass])
(import json)
(import os)
(import struct)
(import sys)

(import hy)
(import hy.models [Expression Integer Symbol])
(require hyrule.control [defmain unless])
(require hyrule.misc [of pun])
(import hyrule.hypprint [pprint])

(import models [CompiledFunction LinkedFunction Program Unit])


;; Information about a function, necessary and sufficient to link against it
;; Normally comes from units, but can also be injected by REPL
(defclass [dataclass] ProgramFunction []
  #^ int id
  #^ str name
  #^ int argc
  #^ int retc
  )

;; Additional information not included in program or program fragment
(defclass [dataclass] LinkInfo []
  #^ int bc-end
  #^ int constants-end
  #^ (of dict str ProgramFunction) function-table
  #^ (of dict str int) global-table
  )

(defn link-program [units
                    output
                    builtin-functions
                    [repl-initial-state None]
                    [allow-no-main False]]
  (setv bc-end 0)
  (setv constants-end 0)

  (setv #^ (of dict str ProgramFunction)
        function-table {})
  (setv #^ (of dict str int)
        global-table {})

  (setv functions-to-compile [])

  (setv program (Program :bytecode []
                         :constants []
                         :functions []
                         :globals []))

  (when (is-not repl-initial-state None)
    (setv bc-end          repl-initial-state.bc-end
          constants-end   repl-initial-state.constants-end
          function-table  {#** repl-initial-state.function-table}
          global-table    {#** repl-initial-state.global-table}))

  ;; link:
  ;; - collect functions + globals

  (for [unit units]
    (for [f unit.functions]
      (assert (not-in f.name builtin-functions))
      (assert (not-in f.name function-table))

      (setv function-index (len function-table))
      (setv (get function-table f.name)
            (ProgramFunction :id function-index
                             :name f.name
                             :argc f.argc
                             :retc f.retc))
      (functions-to-compile.append f)
      )
    (for [#(g value) (unit.globals.items)]
      (if (is value None)
          ;; If a global has no value, it has been declared akin to 'extern' in C.
          ;; The compiler doesn't currently permit this, but variables in the REPL use this.
          (get global-table g)
          (do
            (assert (not-in g global-table))

            ;; Note: global-table may contain additional entries coming from repl-initial-state,
            ;;       which will not be found in program.globals (and must not be added there)
            (setv global-index (len global-table))
            (setv (get global-table g) global-index)
            (program.globals.append value)
            ))
      )
    )

  ;; resolve calls to `call.func`, `call.ext`
  ;; resolve global var IDs

  (defn error [message]
    (raise (Exception f"error: {message}")))

  (for [f functions-to-compile]
    (defn resolve [insn]
      (cond
        ;; call
        (= (get insn 0) 'call) (do
          (setv [_ name argc retc] insn)

          (defn check-retc [produces]
            (unless (= produces retc)
              (error f"{retc} results were expected, but function '{name}' produces {produces}")))

          (cond
            (in name builtin-functions) (do
              (setv info (get builtin-functions name))
              (setv argc-expect (get info "argc"))
              (unless (= argc argc-expect)
                (error f"External function '{name}' expects {argc-expect} arguments, but {argc} were passed"))
              (check-retc (get info "retc"))
              ['call:ext (get info "id")]
              )
            (setx f (function-table.get name None)) (do
              (unless (= argc f.argc)
                (error f"Function '{name}' expects {f.argc} arguments, but {argc} were passed"))
              (check-retc f.retc)
              ['call:func f.id])
            True (raise (Exception f"unresolved function {name}"))
            ))
        ;; getglobal/setglobal
        (in (get insn 0) #{'getglobal 'setglobal}) (do
          (setv [opcode name] insn)
          [opcode (get global-table name)])

        True insn
        ))

    (setv f.body (lfor insn f.body (resolve insn)))
    )

  ;; expand jump offsets to bytes

  (defn instruction-length [insn]
    ;; 1 byte per opcode and each operand
    ;; except for branches where the operand is 2 bytes
    (if (in (get insn 0) #{'jmp 'jz})
      3
      (len insn)))

  (for [f functions-to-compile]
    (defn resolve [i insn]
      (cond
        ;; getglobal/setglobal
        (in (get insn 0) #{'jmp 'jz}) (do
          (setv [opcode dist] insn)

          ;; distance is sum of lengths of instructions, starting at the next one
          (setv start (+ i 1))
          (setv end (+ start dist))

          (defn block-length [block]
            (sum (gfor insn block (instruction-length insn))))

          (if (>= end start)
            (setv dist-bytes (block-length (cut f.body start end)))
            (setv dist-bytes (- (block-length (cut f.body end start))))
            )

          [opcode dist-bytes])

        True insn
        ))

    (setv f.body (lfor [i insn] (enumerate f.body) (resolve i insn)))
    )


  ;; - lay out bytecode

  (for [f functions-to-compile]
    (setv func-body-len
          (sum (gfor insn f.body (instruction-length insn))))

    (setv f* (LinkedFunction :name f.name
                             :argc f.argc
                             :num-locals f.num-locals
                             :bytecode-offset bc-end
                             :constants-offset constants-end))
    (program.functions.append f*)

    (setv program.bytecode (+ program.bytecode f.body)
          bc-end (+ bc-end func-body-len))

    (setv program.constants (+ program.constants f.constants)
          constants-end (+ constants-end (len f.constants)))
    )


  ;(pprint all-functions)
  (pprint global-table)
  ;; (pprint function-table)
  (pprint program)

  (setv OPCODE-NUMBERS {
    'getconst 0
    'zero 1
    'drop 2
    'getglobal 3
    'setglobal 4
    'getlocal 5
    'setlocal 6
    'call:func 10
    'call:ext 11
    'ret 13
    'jmp 20
    'jz 21
    })

  (when (is-not output None)
    (if allow-no-main
      ;; In REPL mode, definitions generate program fragments with no main function
      (setv main-func-idx (try (. function-table ["main"] id) (except [KeyError] 255)))
      (setv main-func-idx (. function-table ["main"] id)))

    (with [f (open (+ output ".tmp") "wb")]
      ;; write header
      (f.write (struct.pack "<HHBBBx" bc-end
                                      (len program.constants)
                                      (len program.functions)
                                      (len program.globals)
                                      main-func-idx))
      ;; functions
      (for [func program.functions]
        (f.write (struct.pack "<BBHHxx" func.argc func.num-locals func.bytecode-offset func.constants-offset)))
      ;; constans
      (for [value program.constants]
        (f.write (struct.pack "<h" value)))
      ;; globals
      (for [value program.globals]
        (f.write (struct.pack "<h" value)))
      ;; bytecode
      (for [[opcode #* operands] program.bytecode]
        ;(f.write (bytes [(get OPCODE-NUMBERS opcode) #* operands])))
        (if (in opcode #{'jmp 'jz})
          (do
            ;; branch instructions have a 16-bit offset operand
            (f.write (struct.pack "b" (get OPCODE-NUMBERS opcode)))
            (f.write (struct.pack "h" #* operands)))
          (for [b [(get OPCODE-NUMBERS opcode) #* operands]]
            (f.write (struct.pack "b" b)))))
    )

    (os.rename (+ output ".tmp") output))
  (pun (LinkInfo :!bc-end :!constants-end :!function-table :!global-table)))

(defmain []
  (import argparse [ArgumentParser])

  (setv parser (ArgumentParser))
  (parser.add-argument "inputs" :nargs "+")
  (parser.add-argument "-o" :dest "output" :required True)
  (setv args (parser.parse-args))

  (with [f (open "builtins.json")]
    (setv builtin-functions (json.load f))
    )

  (setv units [])

  (for [path args.inputs]
    (with [f (open path)]
      (setv [form] (hy.read-many f))
      (setv unit (Unit.from-form form))
      ;; (pprint unit)
      (units.append unit)
      )
    )

  (link-program units
                :output args.output
                :builtin-functions builtin-functions
                )
  )
