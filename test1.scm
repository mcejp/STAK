(define (draw-splash)
  (fill-rect COLOR:WHITE 0 0 W H)
  )

(define (main)
  (set-video-mode W H)
  (draw-splash)
  (pause-frames 100)
  )
