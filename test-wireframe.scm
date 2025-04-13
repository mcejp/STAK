;; world-space transformation matrix
(define m11 64) (define m12 0)  (define m13 0)  (define m14 0)
(define m21 0)  (define m22 64) (define m23 0)  (define m24 0)
(define m31 0)  (define m32 0)  (define m33 64) (define m34 0)


(define (main)
  (define speed 4)
  (define angle 0)

  (while 1
    (fill-rect 15 0 0 W H)

    ;; TRIPPY version
    ;; (not so trippy anymore with the overflow bug fixed)
    ; (define i 0)
    ; (while (<= i 14)
    ;   (make-rotation-matrix-z (+ angle (* 256 i)))
    ;   (cube i -100 -100 -100 100 100 100)
    ;   (set! i (+ i 1)))

    ;; Sober version
    (make-rotation-matrix-z angle)
    (cube 0 -100 -100 -100 100 100 100)

    (pause-frames 1)
    (set! angle (+ angle 256))))


(define (make-rotation-matrix-z angle)
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
  (set! m23 0)
  (set! m31 0)
  (set! m32 0)
  (set! m33 64))


(define (cube color x1 y1 z1 x2 y2 z2)
  ;; z1
  (line color x1 y1 z1    x2 y1 z1)
  (line color x2 y1 z1    x2 y2 z1)
  (line color x2 y2 z1    x1 y2 z1)
  (line color x1 y2 z1    x1 y1 z1)

  ;; transitional
  (line color x1 y1 z1    x1 y1 z2)
  (line color x2 y1 z1    x2 y1 z2)
  (line color x2 y2 z1    x2 y2 z2)
  (line color x1 y2 z1    x1 y2 z2)

  ;; z2
  (line color x1 y1 z2    x2 y1 z2)
  (line color x2 y1 z2    x2 y2 z2)
  (line color x2 y2 z2    x1 y2 z2)
  (line color x1 y2 z2    x1 y1 z2))


;; draw a transformed line;
;; if coords are +/- 512
;; matrix values must be max +/- 64
;; and we shift 6 bits down
(define (line color x1 y1 z1 x2 y2 z2)
  (define xx1 yy1 (project x1 y1 z1))
  (define xx2 yy2 (project x2 y2 z2))

  (draw-line color xx1 yy1 xx2 yy2))


(define (project x y z)
  ;; world:  x = right, y = forward, z = up
  ;; screen: x = right, y = down,    z = forward

  ;; apply transformwation in world-space
  (define x* (+ (>> (+ (+ (* m11 x) (* m12 y)) (* m13 z)) 6) m14))
  (define y* (+ (>> (+ (+ (* m21 x) (* m22 y)) (* m23 z)) 6) m24))
  (define z* (+ (>> (+ (+ (* m31 x) (* m32 y)) (* m33 z)) 6) m34))

  ;; move to screen space (fixed camera)
  (define sx x*)
  (define sy (- 0 z*))
  (define sz (+ y* 500))

  ;; top-down view (useful for debugging)
  ; (define sx x*)
  ; (define sy y*)
  ; (define sz (- 500 z*))

  ;; divide by z and shift to middle of screen

  (set! sx (/ (* sx 128) (>> sz 1)))
  (set! sy (/ (* sy 128) (>> sz 1)))

  (values (+ sx (>> W 1))
          (+ sy (>> H 1))))
