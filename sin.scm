(define (main)
  (for (i (range 0 256))
    (define next (+ i 1))
    (define the-sin@ (sin@ i))
    (define the-cos@ (cos@ i))
    (define the-sin-next@ (sin@ next))
    (define the-cos-next@ (cos@ next))

    (draw-line (+ 32 (>> i 2))
               (+ (/ W 2) the-cos@)
               (- (/ H 2) the-sin@)
               (+ (/ W 2) the-cos-next@)
               (- (/ H 2) the-sin-next@)))

  (while 1
    (pause-frames 1)))
