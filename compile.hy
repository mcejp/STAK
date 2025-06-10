(import
  functools [partial]
  os)
(import dataclasses [dataclass])
(import json)
(import sys)

(import
  funcparserlib.parser [maybe many some]
  hy.model-patterns [NoParseError pexpr sym whole FORM SYM])
(import hy)
(import hy.models [Expression Integer Symbol])
(require hyrule.control [defmain lif unless])

(import
  models [CompiledFunction Unit]
  transforms [maybe-parse transform-expression transform-statement]
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

(defn compile-getconst [ctx value]
  (if (= value 0)
    ;; special opcode for 0
    (ctx.emit 'zero)
    ;; general case
    (ctx.emit 'pushconst value)))

;; returns nothing
(defn compile-expression [ctx expr [expected-values 1]]
  (setv builtin-constants ctx.builtin-constants)
  (setv unit ctx.unit)
  (setv function ctx.function)
  (setv output ctx.output)

  (defn produces-values [count]
    (when (!= expected-values count)
      (ctx.error f"Expected {expected-values} values, but form produces {count}" expr)))

  ;; expand non-core forms
  (setv expr (transform-expression expr))

  (cond
    (isinstance expr Integer) (do
      (produces-values 1)
      (compile-getconst ctx (int expr)))

    (isinstance expr Expression) (do
      ;; function call
      (setv [name #* args] expr)
      ; (print "CALL" name args)
      (assert (isinstance name Symbol))
      (for [arg args]
        (compile-expression ctx arg)
        )
      (ctx.emit 'call (str name) (len args) expected-values)
      )

    ;; symbol (constant, global, local variable)
    (isinstance expr Symbol) (do
      (produces-values 1)

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

;; returns number of values left over on the stack
(defn compile-statements [ctx statement-list]
  (setv builtin-constants ctx.builtin-constants)
  (setv unit ctx.unit)
  (setv function ctx.function)
  (setv output ctx.output)

  (setv num-values-on-stack False)

  (for [form statement-list]
    ;; discard any result of previous statement
    (for [i (range num-values-on-stack)]
      (ctx.emit 'drop))

    ;; expand non-core forms
    (setv form (transform-statement form))

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

        (setv num-values-on-stack 0))

      ;; (define <var1> <var2> ... <value>)
      (setx parsed (maybe-parse* (whole [(sym "define") (many SYM) FORM]))) (do
        (setv [targets value] parsed)

        (compile-expression ctx value :expected-values (len targets))

        (for [target (reversed targets)]
          (setv name (str target))    ;; ugly

          ;; local?
          (cond
            (in name ctx.locals) (ctx.error f"variable already defined" target)
            ;; global?
            (in name unit.globals) (ctx.error f"definition shadows global variable" target)
            )

          ;; define new local & pop the value into it
          (setv (get ctx.locals name) (len ctx.locals))
          (ctx.emit 'setlocal (get ctx.locals name)))

        (setv num-values-on-stack 0))

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

        (setv num-values-on-stack 0))

      ;; (values <value> ...)
      (setx parsed (maybe-parse* (whole [(sym "values") (many FORM)]))) (do
        (setv values parsed)

        (for [expr values]
          (compile-expression ctx expr))

        (setv num-values-on-stack (len values)))

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
        (setv num-values-on-stack
          (compile-statements ctx body))
        (for [i (range num-values-on-stack)]
          (ctx.emit 'drop))
        (setv (get jz 1) (- (len output) after-jz))

        (setv num-values-on-stack 0)
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
        (setv num-values-on-stack
          (compile-statements ctx body))
        (for [i (range num-values-on-stack)]
          (ctx.emit 'drop))
        (setv end (+ (len output) 1))
        (ctx.emit 'jmp (- begin end))
        (setv (get jz 1) (- end after-jz))

        (setv num-values-on-stack 0)
        )

      True (do
        ;; compile expression
        (compile-expression ctx form)
        (setv num-values-on-stack 1))
      )
    )

  num-values-on-stack
  )

(defn compile-function-body [ctx body]
  (setv num-values-on-stack
    (compile-statements ctx body))

  (unless num-values-on-stack
    ;; make sure we're returning something
    (ctx.emit 'zero)
    (setv num-values-on-stack 1))

  (ctx.emit 'ret num-values-on-stack)
  num-values-on-stack)

(defn compile-unit [builtin-constants
                    filename
                    forms
                    [repl-globals None]]
  (setv unit (Unit :globals {} :functions []))

  (when (is-not repl-globals None)
    ;; Pre-populate unit.globals with names of previously defined globals
    (setv unit.globals (dfor name repl-globals name None)))

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
      ;; (define <variable> <constant>)
      (setx parsed (maybe-parse* (whole [(sym "define") SYM SYM]))) (do
        (setv [target constant] parsed)
        (setv name (str target))    ;; ugly

        (setv (get unit.globals name) (get builtin-constants (str constant))))
      ;; (define (<name> <args> ...) <body> ...)
      (setx parsed (maybe-parse* (whole [(sym "define") (pexpr SYM (many SYM)) (many FORM)]))) (do
        (setv [[target parameters] body] parsed)
        (setv name (str target))    ;; ugly

        ;; from the declared parameters, build initial list of local variables
        (setv locals (dfor [i param] (enumerate parameters) (str param) i))

        (setv function (CompiledFunction :name name
                                         :argc (len parameters)
                                         :retc None   ;; don't know yet at this point
                                         :num-locals 0
                                         :body None))

        (setv ctx (CompilationContext :builtin-constants builtin-constants
                                      :filename filename
                                      :function function
                                      :locals locals
                                      :output []
                                      :unit unit))
        (setv function.retc (compile-function-body ctx body))
        (setv function.body ctx.output)
        (setv function.num-locals (- (len ctx.locals) (len parameters)))

        (unit.functions.append function)
        )
      True (raise (Exception f"unhandled form {f}"))
      )
    )

  unit)

(defmain []
  (import argparse [ArgumentParser])

  (setv parser (ArgumentParser))
  (parser.add-argument "input")
  (parser.add-argument "-o" :dest "output" :required True)
  (setv args (parser.parse-args))

  (with [f (open "constants.json")]
    (setv builtin-constants (json.load f)))

  (with [f (open args.input)]
    (setv forms (hy.read-many f))

    (setv unit (compile-unit builtin-constants (str args.input) forms)))

  (with [f (open (+ args.output ".tmp") "wt")]
    (f.write (write (unit.to-sexpr)))
    (f.write "\n")
    )

  (os.rename (+ args.output ".tmp") args.output)
  )