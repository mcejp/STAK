;; transformation matrix
(define m11 64) (define m12 0)  (define m13 0)
(define m21 0)  (define m22 64) (define m23 0)

(define (main)
  (define angle 0)
  (define speed 256)

  (define num-petals 12)
  (define angle-step 5461)    ;; 65536 / num-petals
  (define half-length (/ H 4))
  (define half-width 15)

  (while 1
    (fill-rect 15 0 0 W H)

    (for [i (range num-petals)]
      (make-rotation-matrix (+ angle (* angle-step i)))
      ;; compensate Mode 13h distortion by scaling the x axis by a factor of 6/5
      (set! m11 (/ (* m11 6) 5))
      (set! m12 (/ (* m12 6) 5))
      ;; move to screen center
      (set! m13 (>> W 1))
      (set! m23 (>> H 1))
      ;; draw petal using a palette of pastel colours (56 to 79)
      (define color (+ 56 (* 2 i)))
      (tri color half-length        half-width
                 half-length        (- 0 half-width)
                 (* 2 half-length)  0)
      (tri color half-length        half-width
                 half-length        (- 0 half-width)
                 0                  0))
    (pause-frames 1)

    (when (key-held? KEY:RIGHT) (set! half-length (+ half-length 1)))
    (when (key-held? KEY:LEFT)  (set! half-length (- half-length 1)))
    (when (key-held? KEY:UP)    (set! speed (+ speed 16)))
    (when (key-held? KEY:DOWN)  (set! speed (- speed 16)))

    (set! angle (+ angle speed))))

(define (make-rotation-matrix angle)
  ;; the sin function returns -16384..16384, so we need to shift down quite a bit to reach the desired scale of +/- 64
  ;; as for the input, 32768 ~ pi (with wrap-around working naturally)
  (define the-sin (>> (sin angle) 8))
  (define the-cos (>> (sin (+ angle 16384)) 8))

  ;; rotation matrix is:
  ;;   [cos -sin  0]
  ;;   [sin  cos  0]
  ;; TODO: coordinate system to be reviewed
  (set! m11 the-cos)
  (set! m12 (- 0 the-sin))
  (set! m13 0)
  (set! m21 the-sin)
  (set! m22 the-cos)
  (set! m23 0))

;; draw a transformed triangle;
;; if coords are +/- 512
;; matrix values must be max +/- 64
;; and we shift 6 bits down
(define (tri color x1 y1 x2 y2 x3 y3)
  (fill-triangle color
    (+ (>> (+ (* m11 x1) (* m12 y1)) 6) m13) (+ (>> (+ (* m21 x1) (* m22 y1)) 6) m23)
    (+ (>> (+ (* m11 x2) (* m12 y2)) 6) m13) (+ (>> (+ (* m21 x2) (* m22 y2)) 6) m23)
    (+ (>> (+ (* m11 x3) (* m12 y3)) 6) m13) (+ (>> (+ (* m21 x3) (* m22 y3)) 6) m23)))
