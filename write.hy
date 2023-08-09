;; Warning: This code is quite ad-hoc and not well tested. Proceed at your own peril.

(import
  itertools [chain]

  hy.models [Expression Integer String Symbol])

(require
  hyrule.control [unless])

(setv WIDTH 80)
(setv STEP 2)
(setv STEP-STR "  ")

(defn write-lines [model max-width]
  (cond
    (isinstance model Expression) (do
      ;; Possibilities to consider:
      ;;  - short form containing only atoms, such as `(call "draw-splash" 0)`
      ;;  - form containing only atoms but too long to fit on one line
      ;;  - form starting with a few atoms, followed by nested forms
      ;;  - form starting with a few atoms (but too many to fit on a single line),
      ;;    followed by nested forms
      ;;  - form consisting only of sub-forms

      (setv model (list model))

      (setv opener "(")
      (while (> (len model) 0)
        ;; opportunistically try to tack nested models onto the opening line
        (setv thing (get model 0))
        (when (isinstance thing Expression)
          ;; sub-forms go on new lines
          (break))

        (setv stringified (write-lines thing 0))
        (when (!= (len stringified) 1)
          ;; item spreads over multiple lines
          (break))

        ;; build new opener and check if it fits within width limit
        (setv [s] stringified)
        (setv new-opener
          (if (= (len opener) 1)
            (+ opener s)
            (+ opener " " s)))
        (when (> (len new-opener) max-width)
          (break))

        ;; ok, accept
        (setv opener new-opener)
        (setv model (cut model 1 None)))

      (when (= (len model) 0)
        ;; if we have exhausted everything, good!
        (return [(+ opener ")")]))

      (setv constituents (lfor e model (write-lines e (- max-width STEP))))
      (setv flattened (list (chain #* constituents)))
      (setv closer (+ (get flattened -1) ")"))

      [opener #* (gfor line (cut flattened 0 -1) (+ STEP-STR line)) (+ STEP-STR closer)]
      )

    ;; TODO: plain int/str should just be rejected, too confusing
    (isinstance model int) [(str model)]
    (isinstance model Symbol) [(str model)]
    (isinstance model tuple) [(hy.repr model)]
    (isinstance model String) [(hy.repr (str model))]
    (isinstance model str) [(hy.repr model)]  ; WATCH OUT that Symbol also seems to test as 'str'

    True (raise (NotImplementedError f"Cannot serialize `{(hy.repr model)}` (type {(type model)})"))
    ))

(defn write [model]
  (setv lines (write-lines model WIDTH))
  (.join "\n" lines)
  )
