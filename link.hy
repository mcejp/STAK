(import dataclasses [dataclass])
(import json)
(import os)
(import struct)
(import sys)

(import hy)
(import hy.models [Expression Integer Symbol])
(require hyrule.control [defmain unless])
(import hyrule.hypprint [pprint])

(import models [CompiledFunction LinkedFunction Program Unit])


(defn link-program [units output builtin-functions]
  ;; link:
  ;; - collect functions + globals

  (setv global-ids {})
  (setv function-ids {})
  (setv all-functions {})

  (setv program (Program :bytecode []
                         :constants []
                         :functions []
                         :globals []))

  (for [unit units]
    (for [f unit.functions]
      (assert (not-in f.name function-ids))
      (assert (not-in f.name builtin-functions))

      (setv function-index (len all-functions))
      (setv (get function-ids f.name) function-index)
      (setv (get all-functions f.name) f)
      )
    (for [#(g value) (unit.globals.items)]
      (assert (not-in g global-ids))

      (setv global-index (len program.globals))
      (setv (get global-ids g) global-index)
      (program.globals.append value)
      )
    )

  ;; resolve calls to `call.func`, `call.ext`
  ;; resolve global var IDs

  (defn error [message]
    (raise (Exception f"error: {message}")))

  (for [f (all-functions.values)]
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
            (in name function-ids) (do
              (check-retc (. (get all-functions name) retc))
              ['call:func (get function-ids name) argc])
            True (raise (Exception f"unresolved function {name}"))
            ))
        ;; getglobal/setglobal
        (in (get insn 0) #{'getglobal 'setglobal}) (do
          (setv [_ name] insn)
          [_ (get global-ids name)])

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

  (for [f (all-functions.values)]
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

  (setv bc-pos 0)

  (for [f (all-functions.values)]
    (setv func-body-len
          (sum (gfor insn f.body (instruction-length insn))))

    (setv f* (LinkedFunction :name f.name
                             :argc f.argc
                             :num-locals f.num-locals
                             :bytecode-offset bc-pos
                             :constants-offset (len program.constants)))
    (program.functions.append f*)

    (setv program.bytecode (+ program.bytecode f.body))
    (setv bc-pos (+ bc-pos func-body-len))

    (setv program.constants (+ program.constants f.constants))
    )


  ;(pprint all-functions)
  (pprint global-ids)
  (pprint function-ids)
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
    (setv main-func-idx (get function-ids "main"))

    (with [f (open (+ output ".tmp") "wb")]
      ;; write header
      (f.write (struct.pack "<HHBBBx" bc-pos
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
  )

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
      (pprint unit)
      (units.append unit)
      )
    )

  (link-program units
                :output args.output
                :builtin-functions builtin-functions
                )
  )
