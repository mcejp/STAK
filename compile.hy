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
  #^ dict builtin-functions
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

(defn iterate-with-first-and-last [lst]
  ;; usage: (for [#(my-item is-first is-last) (iterate-with-first-and-last my-list)] ...)
  ;;
  ;; could be implemented differently to support non-list iterables
  ;; but not needed right now
  (let [n (len lst)]
    (for [#(i item) (enumerate lst)]
      (yield #(item (= i 0) (= i (- n 1)))))))

(defn pairwise [lst]
  (assert (= 0 (% (len lst) 2)))
  (let [it (iter lst)]
    (list (zip it it))))

;; returns number of actually produced values
(defn compile-expression [ctx expr [expected-values 1]]
  (setv builtin-constants ctx.builtin-constants)
  (setv builtin-functions ctx.builtin-functions)
  (setv unit ctx.unit)
  (setv function ctx.function)
  (setv output ctx.output)
  (setv produced-values None)

  (defn produces-values [count [blame-expr expr]]
    (when (and (is-not expected-values None)
               (!= expected-values count))
        (ctx.error f"Expected {expected-values} values, but form produces {count}" blame-expr))

    (nonlocal produced-values)
    (when (and (is-not produced-values None)
               (!= produced-values count))
        (ctx.error f"Mismatched number of produced values: previously {produced-values}, now {count}" blame-expr))
    (setv produced-values count))

  ;; expand non-core forms
  (setv expr (transform-expression expr))

  (setv maybe-parse* (partial maybe-parse expr))

  (cond
    ;; (cond <cond1> <body1> <cond2> <body2> ...)
    (setx parsed (maybe-parse* (whole [(sym "cond") (many FORM)]))) (do
      (setv clauses (pairwise parsed))

      ;; compiles to:
      ;;   evaluate cond1
      ;;   jz past_body1
      ;;   body1
      ;;   jmp end
      ;; past_body1:
      ;;   evaluate cond2
      ;;   jz past_body2
      ;;   body2
      ;;   (jmp end)
      ;; end:

      ;; perform a rudimentary analysis of the clauses;
      ;; this is not only useful for optimization, but also necessary to see if we can always produce a value
      (setv clauses-plus [])
      (setv have-default False)

      (for [#(clause is-first is-last) (iterate-with-first-and-last clauses)]
        (let [#(cond body) clause
              always-true? (and (isinstance cond Integer) (= (int cond) 1))]
          ;; catch-all clause must be the last one
          (when (and always-true? (not is-last))
            (ctx.error "catch-all clause in 'cond' must be last" expr))
          (clauses-plus.append #(cond body is-first is-last always-true?))
          (when always-true?
            (setv have-default True))))

      ;; cond will only produce values if there is a 'catch-all' branch (condition is just `1`)
      (when (not have-default)
        (produces-values 0))

      ;; finally generate code
      (setv jmps [])

      (for [#(cond body is-first is-last always-true?) clauses-plus]
        ;; insert evaluation of condition and jump to next clause
        (unless always-true?
          (compile-expression ctx cond)
          (setv jz (ctx.emit 'jz None))
          (setv after-jz (len output)))

        (let [num-values-on-stack (compile-statements ctx [body])]
          (if have-default
            ;; recall that this also ensures a consistent number of values across branches
            (produces-values num-values-on-stack :blame-expr body)
            ;; no default -> no values shall be returned -> clean stack after each branch
            (for [i (range num-values-on-stack)]
              (ctx.emit 'drop))))

        ;; insert (placeholder) jump to end
        (unless is-last
          (let [jmp (ctx.emit 'jmp None)
                pos (len output)]
            (.append jmps #(pos jmp))))

        ;; fix up jump to next clause
        (unless always-true?
          (setv (get jz 1) (- (len output) after-jz))))

      ;; fix up those jumps to end
      (for [#(pos jmp) jmps]
        (setv (get jmp 1) (- (len output) pos)))
      )

    ;; (values <value> ...)
    (setx parsed (maybe-parse* (whole [(sym "values") (many FORM)]))) (do
      (setv values parsed)

      (produces-values (len values))
      (for [expr values]
        (compile-expression ctx expr)))

    ;; integer literal
    (isinstance expr Integer) (do
      (produces-values 1)
      (compile-getconst ctx (int expr)))

    (isinstance expr Expression) (do
      ;; function call
      (setv [name-sym #* args] expr)
      (assert (isinstance name-sym Symbol))
      (setv name (str name-sym))

      ;; is a built-in?
      (setv builtin (.get builtin-functions name None))

      (for [arg args]
        (compile-expression ctx arg))

      (lif builtin
        (do
          (unless (= (len args) (get builtin "argc"))
                  (error f"Function '{name}' expects {f.argc} arguments, but {argc} were passed"))
          (produces-values (get builtin "retc"))
          (ctx.emit name-sym))
        (do
          ;; if by now we don't know how many values are expected, assume 1
          (when (is expected-values None)
            (setv expected-values 1))

          (produces-values expected-values)
          (ctx.emit 'call (str name) (len args) expected-values))))

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

  ;; before returning, the number of produced values must be known
  (assert (is-not produced-values None))
  produced-values)

;; returns number of values left over on the stack
(defn compile-statements [ctx statement-list]
  (setv builtin-constants ctx.builtin-constants)
  (setv unit ctx.unit)
  (setv function ctx.function)
  (setv output ctx.output)

  (setv num-values-on-stack 0)

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

      ;; (do <body> ...)
      (setx parsed (maybe-parse* (whole [(sym "do") (many FORM)]))) (do
        (let [body parsed]
          (setv num-values-on-stack (compile-statements ctx body))))

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
        ;; at this point we don't prescribe how many values it should produce
        (let [num-values (compile-expression ctx form :expected-values None)]
          (setv num-values-on-stack num-values)))
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
                    builtin-functions
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

        (when (in name builtin-functions)
          (raise (Exception f"cannot redefine built-in function '{name}'")))

        ;; from the declared parameters, build initial list of local variables
        (setv locals (dfor [i param] (enumerate parameters) (str param) i))

        (setv function (CompiledFunction :name name
                                         :argc (len parameters)
                                         :retc None   ;; don't know yet at this point
                                         :num-locals 0
                                         :body None))

        (setv ctx (CompilationContext :builtin-constants builtin-constants
                                      :builtin-functions builtin-functions
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

  (with [f (open "builtins.json")]
    (setv builtin-functions (json.load f)))

  (with [f (open args.input)]
    (setv forms (hy.read-many f))

    (setv unit (compile-unit builtin-constants
                             builtin-functions
                             (str args.input)
                             forms)))

  (with [f (open (+ args.output ".tmp") "wt")]
    (f.write (write (unit.to-sexpr)))
    (f.write "\n")
    )

  (os.rename (+ args.output ".tmp") args.output)
  )