(define (clear-screen)
  (fill-rect COLOR:WHITE 0 0 W H))

(define (main)
  (clear-screen)
  (pause-frames 100))
