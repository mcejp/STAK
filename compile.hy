(import
  functools [partial]
  os)
(import argparse [ArgumentParser])
(import dataclasses [dataclass])
(import json)
(import sys)

(import
  funcparserlib.parser [maybe many]
  hy.model-patterns *)
(import hy)
(import hy.models [Expression Integer Symbol])
(require hyrule.control [lif unless])

(import
  models [CompiledFunction Unit]
  write [write])

(defclass [dataclass] CompilationContext []
  #^ object builtin-constants
  #^ str filename
  #^ CompiledFunction function
  #^ dict locals
  #^ list output
  #^ Unit unit

  ;; TODO: Can we reuse Python's/Hy's own traceback mechanism?
  (defn error [self message form]
    (raise (Exception (+ f"{self.filename}:{form.start-line}: {message}\n"
                         f"\tin form {(hy.repr form)}'"))))

  (defn emit [self opcode #* args]
    (setv instr [opcode #* args])
    (self.output.append instr)
    ;; return reference to the appended array
    instr)

  )

(defn maybe-parse [form syntax]
  (try
    (.parse syntax form)
    (except [err NoParseError]
      None)))

(defn compile-getconst [ctx value]
  (if (= value 0)
    ;; special opcode for 0
    (ctx.emit 'zero)
    ;; general case
    (try
      (setv index (.index ctx.function.constants value))
      (except [ValueError]
        (setv index (len ctx.function.constants))
        (ctx.function.constants.append value)
        )
      (finally (ctx.emit 'getconst index)))))

(defn compile-expression [ctx expr]
  (setv builtin-constants ctx.builtin-constants)
  (setv unit ctx.unit)
  (setv function ctx.function)
  (setv output ctx.output)

  (cond
    (isinstance expr Integer)
      (compile-getconst ctx (int expr))

    (isinstance expr Expression) (do
      ;; function call
      (setv [name #* args] expr)
      ; (print "CALL" name args)
      (assert (isinstance name Symbol))
      (for [arg args]
        (compile-expression ctx arg)
        )
      (ctx.emit 'call (str name) (len args))
      )

    ;; symbol (constant, global, local variable)
    (isinstance expr Symbol) (do
      (setv name (str expr))    ;; ugly

      ;; builtin constant with this name exists?
      (setv builtin-const (builtin-constants.get name))

      (lif builtin-const        ;; lif x = if x is not None
        (compile-getconst ctx builtin-const)
        (cond
          ;; local?
          (in name ctx.locals) (ctx.emit 'getlocal (get ctx.locals name))
          ;; global?
          (in name unit.globals) (ctx.emit 'getglobal name)
          ;;
          True (ctx.error f"undefined variable" expr))
        )
      )

    True (raise (Exception f"unhandled form {expr}"))
    )
  )

;; returns true if something is left over on the stack
(defn compile-statements [ctx statement-list]
  (setv builtin-constants ctx.builtin-constants)
  (setv unit ctx.unit)
  (setv function ctx.function)
  (setv output ctx.output)

  (setv last-statement-produced-result False)

  (for [form statement-list]
    ;; discard any result of previous statement
    (when last-statement-produced-result
      (ctx.emit 'drop))

    (setv maybe-parse* (partial maybe-parse form))

    ;; TODO: can do something like cond for maybe-parse with custom unpacking
    ;;       https://github.com/hylang/hy/blob/39be258387c3ced1ee0ca5b1376917d078970f6a/hy/core/macros.hy#L6

    (cond
      ;; (define <variable> <value>)
      (setx parsed (maybe-parse* (whole [(sym "define") SYM FORM]))) (do
        (setv [target value] parsed)
        (setv name (str target))    ;; ugly

        (compile-expression ctx value)

        ;; local?
        (cond
          (in name ctx.locals) (ctx.error f"variable already defined" target)
          ;; global?
          (in name unit.globals) (ctx.error f"definition shadows global variable" target)
          )

        ;; define new local & pop the value into it
        (setv (get ctx.locals name) (len ctx.locals))
        (ctx.emit 'setlocal (get ctx.locals name))

        (setv last-statement-produced-result False))

      ;; (set! <variable> <value>)
      (setx parsed (maybe-parse* (whole [(sym "set!") SYM FORM]))) (do
        (setv [target value] parsed)
        (setv name (str target))    ;; ugly

        (compile-expression ctx value)

        ;; local?
        (cond
          (in name ctx.locals) (ctx.emit 'setlocal (get ctx.locals name))
          ;; global?
          (in name unit.globals) (ctx.emit 'setglobal name)
          ;;
          True (ctx.error f"undefined variable" target))

        (setv last-statement-produced-result False))

      ;; (when <cond> <body> ...)
      ;; this should probably just be a macro
      (setx parsed (maybe-parse* (whole [(sym "when") FORM (many FORM)]))) (do
        (setv [cond body] parsed)

        ;; TODO: how to make this not suck?

        ;; compiles to:
        ;;   evaluate condition
        ;;   jz end
        ;;   body
        ;; end:
        (compile-expression ctx cond)
        (setv jz (ctx.emit 'jz None))
        (setv after-jz (len output))
        (setv last-statement-produced-result
          (compile-statements ctx body))
        (when last-statement-produced-result
          (ctx.emit 'drop))
        (setv (get jz 1) (- (len output) after-jz))

        (setv last-statement-produced-result False)
        )

      ;; (while <cond> <body> ...)
      (setx parsed (maybe-parse* (whole [(sym "while") FORM (many FORM)]))) (do
        (setv [cond body] parsed)

        ;; TODO: how to make this not suck?

        ;; compiles to:
        ;; begin:
        ;;   evaluate condition
        ;;   jz end
        ;;   body
        ;;   jmp begin
        ;; end:
        (setv begin (len output))
        (compile-expression ctx cond)
        (setv jz (ctx.emit 'jz None))
        (setv after-jz (len output))
        (setv last-statement-produced-result
          (compile-statements ctx body))
        (when last-statement-produced-result
          (ctx.emit 'drop))
        (setv end (+ (len output) 1))
        (ctx.emit 'jmp (- begin end))
        (setv (get jz 1) (- end after-jz))

        (setv last-statement-produced-result False)
        )

      True (do
        ;; compile expression
        (compile-expression ctx form)
        (setv last-statement-produced-result True)
        )
      )
    )

  last-statement-produced-result
  )

(defn compile-function-body [ctx body]
  (setv last-statement-produced-result
    (compile-statements ctx body))

  (unless last-statement-produced-result
    ;; make sure we're returning something
    (ctx.emit 'zero))

  (ctx.emit 'ret))


(setv parser (ArgumentParser))
(parser.add-argument "input")
(parser.add-argument "-o" :dest "output" :required True)
(setv args (parser.parse-args))

(with [f (open "constants.json")]
    (setv builtin-constants (json.load f))
    )

(with [f (open args.input)]
  (setv forms (hy.read-many f))

  (setv unit (Unit :globals {} :functions []))

  (for [f forms]
    ;(print f)

    (setv maybe-parse* (partial maybe-parse f))
    (setv INTEGER-LITERAL (some (fn [x] (isinstance x Integer))))

    (cond
      ;; (define <variable> <value>)
      (setx parsed (maybe-parse* (whole [(sym "define") SYM INTEGER-LITERAL]))) (do
        (setv [target value] parsed)
        (setv name (str target))    ;; ugly

        (setv (get unit.globals name) (int value))
        )
      ;; (define (<name> <args> ...) <body> ...)
      (setx parsed (maybe-parse* (whole [(sym "define") (pexpr SYM (many SYM)) (many FORM)]))) (do
        (setv [[target parameters] body] parsed)
        (setv name (str target))    ;; ugly

        ;; from the declared parameters, build initial list of local variables
        (setv locals (dfor [i param] (enumerate parameters) (str param) i))

        (setv function (CompiledFunction :name name
                                         :argc (len parameters)
                                         :constants []
                                         :num-locals 0
                                         :body None))

        (setv ctx (CompilationContext :builtin-constants builtin-constants
                                      :filename (str args.input)
                                      :function function
                                      :locals locals
                                      :output []
                                      :unit unit))
        (compile-function-body ctx body)
        (setv function.body ctx.output)
        (setv function.num-locals (- (len ctx.locals) (len parameters)))

        (unit.functions.append function)
        )
      True (raise (Exception f"unhandled form {f}"))
      )
    ))


(with [f (open (+ args.output ".tmp") "wt")]
  (f.write (write (unit.to-sexpr)))
  (f.write "\n")
  )

(os.rename (+ args.output ".tmp") args.output)
