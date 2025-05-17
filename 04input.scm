(define (main)
  (define bk-color COLOR:WHITE)
  (define w 30)
  (define h 25)
  (define x (/ (- W w) 2))
  (define y (/ (- H h) 2))
  (define speed 4)

  (fill-rect bk-color 0 0 W H)

  (while 1
    ;; draw
    (fill-rect COLOR:LIGHTRED x y w h)
    ;; display
    (pause-frames 1)
    ;; erase
    (fill-rect bk-color x y w h)

    (when (key-held? KEY:UP)    (set! y (- y speed)))
    (when (key-held? KEY:DOWN)  (set! y (+ y speed)))
    (when (key-held? KEY:LEFT)  (set! x (- x speed)))
    (when (key-held? KEY:RIGHT) (set! x (+ x speed)))
    ))
