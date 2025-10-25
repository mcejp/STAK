(define (get-basic-color-count)
  (add1 COLOR:WHITE))

(define (clear-screen color)
  (fill-rect color 0 0 W H)

  (dotimes (i 0 (get-basic-color-count))
    (fill-rect i (* i 18) (* i 10) 48 48)))

(define (main)
  (dotimes (color COLOR:COUNT)
    (clear-screen color)
    (pause-frames 10)))
