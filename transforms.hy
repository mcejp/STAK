(import
  funcparserlib.parser [maybe many some]
  hy.models [Expression]
  hy.model-patterns [NoParseError pexpr sym whole FORM SYM])

(defn transform-expression [form]
  (cond
  ;; (add1 <value@>)
  (setx parsed (maybe-parse form (whole [(sym "add1") FORM]))) (do
    `(+ ~parsed 1))

  ;; (from-int@ <value>)
  (setx parsed (maybe-parse form (whole [(sym "from-int@") FORM]))) (do
    (setv value parsed)
    `(<< ~value 6))

  ;; (sub1 <value@>)
  (setx parsed (maybe-parse form (whole [(sym "sub1") FORM]))) (do
    `(- ~parsed 1))

  ;; (to-int <value@>)
  (setx parsed (maybe-parse form (whole [(sym "to-int") FORM]))) (do
    (setv value parsed)
    `(>> ~value 6))

  ;; default return
  True form))

(defn transform-statement [form]
  (cond
  ;; (dotimes (<variable> [<from>] <to>) <body> ...)
  (setx parsed (maybe-parse form (whole [(sym "dotimes") FORM (many FORM)]))) (do
    (setv [for-clause body] parsed)

    ;; Since the parsing is greedy, we have to mark <to> as optional rather than <from>.
    ;; This is accounted for just below.
    (let [syntax (whole [SYM FORM (maybe FORM)])]
      (setv [var from to] (syntax.parse for-clause)))
    (when (is to None)
      (setv [from to] [`0 from]))

    (if (isinstance to Expression)
      ;; If <to> is an expression, evaluate it only once and store it
      ;; in a temporary variable.
      (let [end (hy.gensym "max")]
        `(do
          (define ~var ~from)
          (define ~end ~to)
          (while (< ~var ~end)
            ~@body
            (set! ~var (+ ~var 1)))))
      ;; Otherwise, <to> is either a literal or a symbol, which is fine to use as-is.
      ;; We do this optimization so that the compiler doesn't have to.
      `(do
        (define ~var ~from)
        (while (< ~var ~to)
          ~@body
          (set! ~var (+ ~var 1))))))

  ;; (when <condition> <body> ...)
  (setx parsed (maybe-parse form (whole [(sym "when") FORM (many FORM)]))) (do
    (setv [condition body] parsed)

    `(cond ~condition (do ~@body)))

  ;; default return
  True form))

(defn maybe-parse [form syntax]
  (if (isinstance form Expression)
      (try
        (.parse syntax form)
        (except [err NoParseError]
          None))
      None))
