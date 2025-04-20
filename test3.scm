(define (get-basic-color-count)
  16)

(define (draw-splash color)
  (fill-rect color 0 0 W H)

  (for [i (range 0 (get-basic-color-count))]
    (fill-rect i (* i 18) (* i 10) 48 48))
  )

(define (main)
  (for [color (range COLOR:COUNT)]
    (draw-splash color)
    (pause-frames 10)
    )
  )
