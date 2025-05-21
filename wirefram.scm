;; world-space transformation matrix
(define m11@ 64) (define m12@ 0)  (define m13@ 0)  (define m14@ 0)
(define m21@ 0)  (define m22@ 64) (define m23@ 0)  (define m24@ 0)
(define m31@ 0)  (define m32@ 0)  (define m33@ 64) (define m34@ 0)


(define (main)
  (define angle 0)
  (define speed 256)
  (define color COLOR:LIGHTRED)

  (fill-rect COLOR:WHITE 0 0 W H)
  (while 1
    ;; TRIPPY version
    ;; (not so trippy anymore with the overflow bug fixed)
    ; (for [i (range 15)]
    ;   (make-rotation-matrix-z (+ angle (* 256 i)))
    ;   (cube i -100 -100 -100 100 100 100))

    (make-rotation-matrix-z (>> angle 8))

    ;; draw
    (cube color -100 -100 -100 100 100 100)
    (pause-frames 1)
    ;; erase
    (cube COLOR:WHITE -100 -100 -100 100 100 100)

    (when (key-held? KEY:LEFT)    (set! speed (- speed 32)))
    (when (key-held? KEY:RIGHT)   (set! speed (+ speed 32)))
    (when (key-pressed? KEY:UP)   (set! color (+ color 1)))
    (when (key-pressed? KEY:DOWN) (set! color (- color 1)))

    (set! angle (+ angle speed))))


(define (make-rotation-matrix-z angle)
  ;; sin@ and cos@ return result in 10.6 fixed-point format
  ;; as for the input, 128 ~ pi (with wrap-around)
  (define the-sin@ (sin@ angle))
  (define the-cos@ (cos@ angle))

  ;; rotation matrix is:
  ;;   [cos -sin  0]
  ;;   [sin  cos  0]
  ;; TODO: coordinate system to be reviewed
  (set! m11@ the-cos@)
  (set! m12@ (- 0 the-sin@))
  (set! m13@ 0)
  (set! m21@ the-sin@)
  (set! m22@ the-cos@)
  (set! m23@ 0)
  (set! m31@ 0)
  (set! m32@ 0)
  (set! m33@ 64))


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


;; draw a projected line
(define (line color x1 y1 z1 x2 y2 z2)
  (define xx1 yy1 (project x1 y1 z1))
  (define xx2 yy2 (project x2 y2 z2))

  (draw-line color xx1 yy1 xx2 yy2))


(define (project x y z)
  ;; world:  x = right, y = forward, z = up
  ;; screen: x = right, y = down,    z = forward

  ;; apply transformation in world-space
  (define x* (+ (+ (+ (mul@ m11@ x) (mul@ m12@ y)) (mul@ m13@ z)) m14@))
  (define y* (+ (+ (+ (mul@ m21@ x) (mul@ m22@ y)) (mul@ m23@ z)) m24@))
  (define z* (+ (+ (+ (mul@ m31@ x) (mul@ m32@ y)) (mul@ m33@ z)) m34@))

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
  (set! sy (/ (* sy 107) (>> sz 1)))  ; 128 * 5/6, to compensate Mode 13h distortion

  (values (+ sx (>> W 1))
          (+ sy (>> H 1))))
