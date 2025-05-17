(define *color* COLOR:BLUE)

(define (clear-screen)
  (fill-rect *color* 0 0 W H))

(define (main)
  (clear-screen)
  (pause-frames 10)

  (set! *color* COLOR:LIGHTBLUE)
  (clear-screen)
  (pause-frames 10)

  (set! *color* COLOR:LIGHTCYAN)
  (clear-screen)
  (pause-frames 10)

  (set! *color* COLOR:WHITE)
  (clear-screen)
  (pause-frames 10))
