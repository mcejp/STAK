;; highly displeased with the effort required to (de)serialize these classes

(import dataclasses [dataclass])

(import hy.models [Expression Integer String Symbol])


(defclass [dataclass] CompiledFunction []
  #^ str name
  #^ int argc
  #^ list constants
  #^ int num-locals
  #^ object body

  (defn #^ staticmethod clean [form]
    (cond
      (isinstance form Expression) (lfor subform form (CompiledFunction.clean subform))
      (isinstance form Integer) (int form)
      (isinstance form String) (str form)
      (isinstance form Symbol) form
      True (raise (NotImplementedError (hy.repr form)))
      )
    )

  ;; VERY ugly
  ;; maybe can use sexpdata instead of Hy Reader for this.. but that's pretty dumb too
  ;; https://docs.hylang.org/en/stable/model_patterns.html seems done for this
  (defn #^ staticmethod from-form [form]
    (assert (isinstance form Expression))
    (setv [_function name f1 f2 f3 f4] form)
    (assert (= _function 'function))
    (assert (isinstance name String))

    (assert (isinstance f1 Expression))
    (setv [_argc argc] f1)
    (assert (= _argc 'argc))
    (assert (isinstance argc Integer))

    (assert (isinstance f2 Expression))
    (setv [_constants #* constants] f2)
    (assert (= _constants 'constants))

    (assert (isinstance f3 Expression))
    (setv [_num-locals num-locals] f3)
    (assert (= _num-locals 'num-locals))
    (assert (isinstance num-locals Integer))

    (assert (isinstance f4 Expression))
    (setv [_body #* body] f4)
    (assert (= _body 'body))

    (CompiledFunction :name (str name)
                    :argc (int argc)
                    :constants (lfor c constants (int c))
                    :num-locals (int num-locals)
                    :body (lfor insn body (CompiledFunction.clean insn))
                    )
    )

  ;; ugly
  (defn to-sexpr [self]
    (Expression ['function (String self.name)
           (Expression ['argc self.argc])
           (Expression ['constants #* self.constants])
           (Expression ['num-locals self.num-locals])
           (Expression ['body #* (gfor instr self.body (Expression instr))])
             ])
    )
  )

(defclass [dataclass] LinkedFunction []
  #^ str name
  #^ int argc
  #^ int num-locals
  #^ int bytecode-offset
  #^ int constants-offset
  )

(defclass [dataclass] Unit []
  #^ list functions
  #^ dict globals

  (defn #^ staticmethod from-form [form]
    (assert (isinstance form Expression))
    (setv [_unit f1 f2] form)
    (assert (= _unit 'unit))

    (assert (isinstance f1 Expression))
    (setv [_functions #* functions] f1)
    (assert (= _functions 'functions))

    (assert (isinstance f2 Expression))
    (setv [_globals #* globals] f2)
    (assert (= _globals 'globals))

    (print globals)

    ;; ugggllyyyy
    (defn parse-dict [form]
      (dfor [name value] form (str name) (int value))
      )

    (Unit :functions (lfor f functions (CompiledFunction.from-form f))
        :globals (parse-dict globals))
    )

  (defn to-sexpr [self]
    (Expression ['unit
                 (Expression ['functions #* (gfor f self.functions (f.to-sexpr))])
                 (Expression ['globals #* (self.globals.items)])
                 ])
    )

  )

(defclass [dataclass] Program []
  #^ list bytecode
  #^ list constants
  #^ list functions
  #^ list globals   ;; list of init value
  )
