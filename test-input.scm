(defun (main)
  (set-video-mode W H)

  (define x 100)
  (define y 100)
  (define speed 4)

  (while 1
    (fill-rect 15 0 0 W H)
    (fill-rect 0 x y 30 30)
    (pause-frames 1)

    (when (key-held? KEY:UP)    (set! y (- y speed)))
    (when (key-held? KEY:DOWN)  (set! y (+ y speed)))
    (when (key-held? KEY:LEFT)  (set! x (- x speed)))
    (when (key-held? KEY:RIGHT) (set! x (+ x speed)))
    ))
