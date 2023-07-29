(define (draw-splash color)
  (fill-rect color 0 0 W H)

  (define i 0)
  (while (<= i 15)
    (fill-rect i (* i 18) (* i 13) 48 44)
    (set! i (+ i 1)))
  )

(define (main)
  (set-video-mode W H)

  (define color 0)
  (while (<= color 255)
    (draw-splash color)
    (pause-frames 10)
    (set! color (+ color 1))
    )
  )
