(define (main)
  (define bk-color COLOR:WHITE)
  (define w 30)
  (define h 25)
  (define x (/ (- W w) 2))
  (define y (/ (- H h) 2))
  (define speed 4)

  ;; clear screen
  (fill-rect bk-color 0 0 W H)

  (while 1
    ;; draw
    (fill-rect COLOR:LIGHTRED x y w h)
    ;; display
    (pause-frames 1)
    ;; erase
    (fill-rect bk-color x y w h)

    ;; movement
    (when (key-held? KEY:UP)    (set! y (clip (- y speed) 0 (- H h))))
    (when (key-held? KEY:DOWN)  (set! y (clip (+ y speed) 0 (- H h))))
    (when (key-held? KEY:LEFT)  (set! x (clip (- x speed) 0 (- W w))))
    (when (key-held? KEY:RIGHT) (set! x (clip (+ x speed) 0 (- W w))))
    ))

(define (clip val min max)
  (cond (< val min) min
        (> val max) max
                  1 val))
