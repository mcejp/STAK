;; transformation matrix
(define m11 64) (define m12 0)  (define m13 0)
(define m21 0)  (define m22 64) (define m23 0)

(define (main)
  (define speed 4)
  (define angle 0)

  (while 1
    (fill-rect 15 0 0 W H)

    (for [i (range COLOR:COUNT)]
      (make-rotation-matrix (+ angle i))
      ;; compensate Mode 13h distortion by scaling the y axis by a factor of 5/6
      (set! m21 (/ (* m21 5) 6))
      (set! m22 (/ (* m22 5) 6))
      ;; move to screen center
      (set! m13 (>> W 1))
      (set! m23 (>> H 1))
      ;; draw two line segments
      (line i 0 0 35 0)
      (line i 60 0 90 0))
    (pause-frames 1)

    (set! angle (+ angle 1))))

(define (make-rotation-matrix angle)
  ;; sin@ and cos@ return result in 10.6 fixed-point format
  ;; as for the input, 128 ~ pi (with wrap-around)
  (define the-sin@ (sin@ angle))
  (define the-cos@ (cos@ angle))

  ;; rotation matrix is:
  ;;   [cos -sin  0]
  ;;   [sin  cos  0]
  ;; TODO: coordinate system to be reviewed
  (set! m11 the-cos@)
  (set! m12 (- 0 the-sin@))
  (set! m13 0)
  (set! m21 the-sin@)
  (set! m22 the-cos@)
  (set! m23 0))

;; draw a transformed line;
;; if coords are +/- 512
;; matrix values must be max +/- 64
;; and we shift 6 bits down
(define (line color x1 y1 x2 y2)
  (draw-line color
    (+ (>> (+ (* m11 x1) (* m12 y1)) 6) m13) (+ (>> (+ (* m21 x1) (* m22 y1)) 6) m23)
    (+ (>> (+ (* m11 x2) (* m12 y2)) 6) m13) (+ (>> (+ (* m21 x2) (* m22 y2)) 6) m23)))
