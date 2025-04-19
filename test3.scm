(define (draw-splash color)
  (fill-rect color 0 0 W H)

  (for [i (range 0 16)]
    (fill-rect i (* i 18) (* i 10) 48 48))
  )

(define (main)
  (for [color (range 256)]
    (draw-splash color)
    (pause-frames 10)
    )
  )
